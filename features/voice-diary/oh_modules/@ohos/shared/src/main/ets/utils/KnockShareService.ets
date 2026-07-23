// <!-- agentID: DEV-004 (M14 碰一碰后端 · 传输载荷引擎) -->
// fix: DEV-012 · T-M01 一天多篇：ALL_TABLES 增 diary_entry；单篇日记碰传升级为「导出该日全部篇目（载荷 v2 entries[]）、
//   导入逐篇 insert（date+created_at 幂等去重）」，兼容 v1 单篇载荷。
// fix: DEV-013 · T-B01 全库备份含真实照片：导出时收集 diary_entry/happy_thing 的沙箱图片文件入容器，
//   导入后复制图片到新设备沙箱并逐行重建 images/image 列路径，保证关联关系不错乱。
// File: KnockShareService.ets
// Task: M14 碰一碰分享 Knock Share / NFC —— 传输载荷引擎（与链路解耦）
//   ① 全库备份 导出/导入：通用 SQL dump（SELECT * + getRow / insert），DAO 无关，复用 BackupUtils 文件层
//   ② 单篇日记(含图片引用) 碰传载荷：序列化/导入（DiaryVM「碰传图」的数据面）
//   ③ 从 URI 导入备份：接收方（分享/碰一碰拉起）落库
// 架构: ARC-001 §4.4 备份 / §3.1 分布式；依赖 B00(DatabaseExecutor) / M03(Diary/DiaryDao) / BackupUtils

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DatabaseExecutor } from '../database/DatabaseExecutor';
import { DiaryDao } from '../database/dao/DiaryDao';
import { Diary } from '../data/Diary';
import { BackupUtils } from './BackupUtils';
import type { BackupFileInfo, BackupContent } from './BackupUtils';

const TAG = 'KnockShareService';

/**
 * 全库表清单（与 DatabaseHelper DDL 严格一致，共 13 表；fix: DEV-012 增 diary_entry，老 diary 表保留闲置仍随备份）。
 * 顺序无外键强依赖（本库外键为逻辑关联而非 DDL FOREIGN KEY），REPLACE 幂等，任意顺序可恢复。
 */
const ALL_TABLES: string[] = [
  'diary', 'diary_entry', 'check_in', 'todo', 'happy_thing', 'extra_thing',
  'extracted_task', 'quote', 'pomodoro_session', 'section_config',
  'app_settings', 'custom_emoji', 'chat_message'
];

/** 备份加解密口令（真 AES-256-GCM + zlib：此口令即 PBKDF2 密钥派生输入 = app-secret）。
 *  #28/#29 已统一：设置页备份（SettingsViewModel + AdvancedSettingsViewModel）与碰一碰路径均委托本引擎、
 *  用此同一 BACKUP_SECRET、同一 12 表 ValuesBucket 格式 → 跨路径 .ediary.zip 完全互通。此处为唯一真相源，勿再分叉。 */
const BACKUP_SECRET = 'HuaweiDiaryBackup2024#Knock';

/** 接收区目录（导入 URI 备份时先落地此处再解析）。 */
const RECEIVE_DIR = 'received';

/** 备份导出结果 */
export interface BackupExportResult {
  path: string;
  sizeBytes: number;
  tableCount: number;
  rowCount: number;
  imageCount: number;
  created: number;
}

/** 备份导入结果 */
export interface BackupImportResult {
  tableCount: number;
  rowCount: number;
  imageCount: number;
}

/** fix: DEV-012 · 载荷 v2 单篇条目（一天多篇：DiaryBundle.entries 携带该日全部篇目）。 */
export interface DiaryEntryPayload {
  title: string;
  content: string;
  mood: string;
  images: string[];
  created_at: number;
}

/**
 * 单篇日记碰传载荷（跨设备可读的自描述结构）。images 为发送端本地 URI，跨设备需另经分布式文件搬运（见文末说明）。
 * fix: DEV-012 · v2：新增 entries[]（该日全部篇目）；顶层 title/content/... 保留 = 最新一篇（向后兼容 v1 接收端）。
 */
export interface DiaryBundle {
  schema: string;   // 恒 'diary'，接收端据此校验
  version: number;  // 载荷版本，向后兼容判据（v2 起带 entries）
  date: string;
  title: string;
  content: string;
  mood: string;
  images: string[];
  created_at: number;
  entries?: DiaryEntryPayload[];  // v2：该日全部篇目（created_at ASC）；缺省时按 v1 单篇解析顶层字段
}

/** 内部：整库聚合结果 */
interface GatherResult {
  tableMap: Map<string, string>;
  rowCount: number;
}

/** fix: DEV-013 · 内部：diary 图片文件名解析结果（diary_entry_{id}_{idx}.jpg） */
interface DiaryImageKey {
  id: number;
  idx: number;
}

/**
 * KnockShareService —— 碰一碰/备份 的「载荷引擎」。
 * 纯数据：DB 整库序列化/反序列化 + 单篇日记载荷 + 从 URI 导入。全部经 DatabaseExecutor，无 UI、无链路依赖。
 */
export class KnockShareService {

  // ==================== 全库备份（SettingsVM「碰传备份」/ 本地备份 共用）====================

  /**
   * 导出全库为加密 .ediary.zip 备份文件（含真实照片）。
   * @param baseDir 应用 files 目录（context.filesDir）。
   * @returns 备份结果（路径/大小/表数/行数/图片数）；失败返回 null。
   */
  static async exportFullBackup(baseDir: string): Promise<BackupExportResult | null> {
    try {
      const gathered: GatherResult = await KnockShareService.gatherAllTables();
      // fix: DEV-013 · 收集日记 + 开心小事关联的真实图片文件
      const imageFiles: Map<string, Uint8Array> = await KnockShareService.collectImageFiles(
        baseDir, gathered.tableMap);

      const path: string | null = await BackupUtils.exportBackup(
        baseDir, gathered.tableMap, BACKUP_SECRET, imageFiles);
      if (path === null) {
        hilog.error(0x0000, TAG, 'exportFullBackup: BackupUtils returned null');
        return null;
      }
      const sizeBytes: number = KnockShareService.safeFileSize(path);
      const result: BackupExportResult = {
        path: path,
        sizeBytes: sizeBytes,
        tableCount: gathered.tableMap.size,
        rowCount: gathered.rowCount,
        imageCount: imageFiles.size,
        created: Date.now()
      };
      hilog.info(0x0000, TAG, 'exportFullBackup ok: tables=%{public}d rows=%{public}d images=%{public}d bytes=%{public}d',
        result.tableCount, result.rowCount, result.imageCount, result.sizeBytes);
      return result;
    } catch (err) {
      hilog.error(0x0000, TAG, 'exportFullBackup failed: %{public}s', (err as BusinessError).message);
      return null;
    }
  }

  /**
   * 从备份文件路径导入并整库恢复（REPLACE 幂等）+ 照片重建。
   * @param baseDir 应用 files 目录（context.filesDir），用于创建 images/ 子目录。
   * @param filePath 备份文件路径（.ediary.zip）。
   * @returns 导入结果（恢复表数/行数/图片数）；失败返回 null。
   */
  static async importFullBackup(baseDir: string, filePath: string): Promise<BackupImportResult | null> {
    try {
      const content: BackupContent | null = await BackupUtils.importBackup(filePath, BACKUP_SECRET);
      if (content === null) {
        hilog.error(0x0000, TAG, 'importFullBackup: BackupUtils returned null');
        return null;
      }
      // 先恢复表数据（含旧路径的 images/image 列）
      const restoreResult: BackupImportResult = await KnockShareService.restoreAllTables(content.tableMap);
      // fix: DEV-013 · 表数据落库后，将容器中的照片拷贝到新设备沙箱并重建 diary_entry/happy_thing 路径
      let imageCount: number = 0;
      if (content.extraFiles.size > 0) {
        imageCount = await KnockShareService.rebuildImagePaths(baseDir, content.extraFiles);
      }
      const result: BackupImportResult = {
        tableCount: restoreResult.tableCount,
        rowCount: restoreResult.rowCount,
        imageCount: imageCount
      };
      hilog.info(0x0000, TAG, 'importFullBackup ok: tables=%{public}d rows=%{public}d images=%{public}d',
        result.tableCount, result.rowCount, result.imageCount);
      return result;
    } catch (err) {
      hilog.error(0x0000, TAG, 'importFullBackup failed: %{public}s', (err as BusinessError).message);
      return null;
    }
  }

  /**
   * 从（分享/碰一碰授予读权限的）URI 导入备份：先落地到接收区，再走 importFullBackup。
   * 接收方（EntryAbility / ShareReceiveAbility 拉起主进程）用此入口。
   * @param baseDir 应用 files 目录。
   * @param uri 已授予读权限的文件 URI（file://...）。
   * @returns 导入结果；失败返回 null。
   */
  static async importBackupFromUri(baseDir: string, uri: string): Promise<BackupImportResult | null> {
    try {
      const receiveDir: string = baseDir + '/' + RECEIVE_DIR;
      KnockShareService.ensureDir(receiveDir);
      const destPath: string = receiveDir + '/received_' + Date.now() + '.ediary.zip';
      // 用 fd 复制：picker 返回的 URI 需通过 openSync 打开，copyFileSync(string) 无法处理 filedocs:// URI
      const srcFile: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const dstFile: fileIo.File = fileIo.openSync(destPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.copyFileSync(srcFile.fd, dstFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(dstFile);
      const result: BackupImportResult | null = await KnockShareService.importFullBackup(baseDir, destPath);
      try {
        fileIo.unlinkSync(destPath);
      } catch (_e) {
        // ignore cleanup failure
      }
      return result;
    } catch (err) {
      hilog.error(0x0000, TAG, 'importBackupFromUri failed: %{public}s', (err as BusinessError).message);
      return null;
    }
  }

  /** 列出全部本地备份（供设置页「备份管理」/ 接收前选择）。委托 BackupUtils。 */
  static listBackups(baseDir: string): BackupFileInfo[] {
    return BackupUtils.listBackups(baseDir);
  }

  /** 删除某备份文件。委托 BackupUtils。 */
  static deleteBackup(filePath: string): boolean {
    return BackupUtils.deleteBackup(filePath);
  }

  /** 全库备份表数（供 UI 预览「将备份 N 张表」；与 ALL_TABLES 单一真相同步，勿硬编码）。 */
  static tableCount(): number {
    return ALL_TABLES.length;
  }

  // ==================== 单篇日记碰传（DiaryVM「碰传图」的数据面）====================

  /**
   * 序列化某日日记为跨设备可读的碰传载荷 JSON。
   * fix: DEV-012 · 一天多篇：导出该日**全部篇目**（entries[]，created_at ASC，不丢数据）；
   * 顶层字段 = 最新一篇（v1 接收端向后兼容）。
   * @param date 'YYYY-MM-DD'
   * @returns 载荷 JSON 字符串；该日无日记返回 null。
   */
  static async exportDiaryBundle(date: string): Promise<string | null> {
    try {
      const list: Diary[] = await DiaryDao.queryListByDate(date);   // created_at DESC
      if (list.length === 0) {
        hilog.warn(0x0000, TAG, 'exportDiaryBundle: no diary on %{public}s', date);
        return null;
      }
      const latest: Diary = list[0];
      const entries: DiaryEntryPayload[] = [];
      for (let i: number = list.length - 1; i >= 0; i--) {
        const d: Diary = list[i];
        const item: DiaryEntryPayload = {
          title: d.title,
          content: d.content,
          mood: d.mood,
          images: d.getImageList(),
          created_at: d.created_at
        };
        entries.push(item);
      }
      const bundle: DiaryBundle = {
        schema: 'diary',
        version: 2,
        date: latest.date,
        title: latest.title,
        content: latest.content,
        mood: latest.mood,
        images: latest.getImageList(),
        created_at: latest.created_at,
        entries: entries
      };
      return JSON.stringify(bundle);
    } catch (err) {
      hilog.error(0x0000, TAG, 'exportDiaryBundle failed: %{public}s', (err as BusinessError).message);
      return null;
    }
  }

  /**
   * 导入碰传日记载荷落库。
   * fix: DEV-012 · 一天多篇：**逐篇 insert 新行**（不再按 date UPSERT 覆盖——date 已无 UNIQUE）；
   * 幂等守卫：该日已存在相同 created_at 的篇目则跳过（重复碰传不重复落库，且不丢对端既有数据）。
   * v1 单篇载荷（无 entries）降级为单条 insert，同样过幂等守卫。
   * @param json exportDiaryBundle 产出的载荷 JSON。
   * @returns 落库行 id（>0 成功；载荷全部为重复篇目时返回该日最新篇 id）；schema 不符或异常返回 -1。
   */
  static async importDiaryBundle(json: string): Promise<number> {
    try {
      const bundle: DiaryBundle = JSON.parse(json) as DiaryBundle;
      if (bundle === null || bundle.schema !== 'diary') {
        hilog.warn(0x0000, TAG, 'importDiaryBundle: schema mismatch');
        return -1;
      }
      const existingList: Diary[] = await DiaryDao.queryListByDate(bundle.date);
      const existingCreated: Set<number> = new Set<number>();
      for (let i: number = 0; i < existingList.length; i++) {
        existingCreated.add(existingList[i].created_at);
      }
      let entries: DiaryEntryPayload[] = [];
      if (bundle.entries !== undefined && bundle.entries.length > 0) {
        entries = bundle.entries;
      } else {
        const single: DiaryEntryPayload = {
          title: bundle.title !== undefined ? bundle.title : '',
          content: bundle.content !== undefined ? bundle.content : '',
          mood: bundle.mood !== undefined ? bundle.mood : '',
          images: bundle.images !== undefined ? bundle.images : [],
          created_at: bundle.created_at !== undefined ? bundle.created_at : Date.now()
        };
        entries = [single];
      }
      let lastId: number = -1;
      let inserted: number = 0;
      for (const e of entries) {
        const createdAt: number = e.created_at !== undefined && e.created_at > 0 ? e.created_at : Date.now();
        if (existingCreated.has(createdAt)) {
          continue;
        }
        const diary: Diary = new Diary(bundle.date);
        diary.content = e.content !== undefined ? e.content : '';
        diary.title = e.title !== undefined ? e.title : '';
        diary.mood = e.mood !== undefined ? e.mood : '';
        diary.setImageList(e.images !== undefined ? e.images : []);
        diary.created_at = createdAt;
        diary.updated_at = Date.now();
        lastId = await DiaryDao.insert(diary);
        inserted++;
      }
      if (inserted === 0 && existingList.length > 0) {
        hilog.info(0x0000, TAG, 'importDiaryBundle: all entries duplicated on %{public}s, skip', bundle.date);
        return existingList[0].id;
      }
      hilog.info(0x0000, TAG, 'importDiaryBundle ok: date=%{public}s inserted=%{public}d lastId=%{public}d',
        bundle.date, inserted, lastId);
      return lastId;
    } catch (err) {
      hilog.error(0x0000, TAG, 'importDiaryBundle failed: %{public}s', (err as BusinessError).message);
      return -1;
    }
  }

  // ==================== 私有：整库聚合 / 恢复 ====================

  /**
   * 逐表 SELECT * → getRow()（ValuesBucket）→ JSON 数组字符串，聚合成 Map<表名, JSON>。
   * 缺表（老版本无某表）跳过并告警，不阻断整体备份。
   */
  private static async gatherAllTables(): Promise<GatherResult> {
    return DatabaseExecutor.executeRead<GatherResult>('KnockShareService.gatherAllTables',
      async (store: relationalStore.RdbStore): Promise<GatherResult> => {
        const tableMap: Map<string, string> = new Map<string, string>();
        let rowCount: number = 0;
        for (const table of ALL_TABLES) {
          const rows: relationalStore.ValuesBucket[] = [];
          try {
            const rs: relationalStore.ResultSet = await store.querySql('SELECT * FROM ' + table);
            while (rs.goToNextRow()) {
              rows.push(rs.getRow());
            }
            rs.close();
          } catch (e) {
            hilog.warn(0x0000, TAG, 'gather skip table %{public}s: %{public}s', table, (e as BusinessError).message);
          }
          tableMap.set(table, JSON.stringify(rows));
          rowCount += rows.length;
        }
        const result: GatherResult = { tableMap: tableMap, rowCount: rowCount };
        return result;
      });
  }

  /**
   * 逐表把 JSON 数组还原为 ValuesBucket 行，REPLACE 冲突策略插入（保留主键 id，幂等覆盖）。
   * 全程单事务，任一失败整体回滚（避免半量恢复导致数据错乱）。
   */
  private static async restoreAllTables(map: Map<string, string>): Promise<BackupImportResult> {
    return DatabaseExecutor.executeInTransaction<BackupImportResult>('KnockShareService.restoreAllTables',
      async (store: relationalStore.RdbStore): Promise<BackupImportResult> => {
        let tableCount: number = 0;
        let rowCount: number = 0;
        for (const table of ALL_TABLES) {
          const json: string | undefined = map.get(table);
          if (json === undefined || json.length === 0) {
            continue;
          }
          const rows: relationalStore.ValuesBucket[] = JSON.parse(json) as relationalStore.ValuesBucket[];
          if (rows === null || rows.length === 0) {
            continue;
          }
          for (const row of rows) {
            await store.insert(table, row, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
            rowCount++;
          }
          tableCount++;
        }
        const result: BackupImportResult = { tableCount: tableCount, rowCount: rowCount, imageCount: 0 };
        return result;
      });
  }

  /**
   * 选择性恢复：按用户选中的表 + 模式（合并/覆盖）恢复数据。
   * @param map 表名 → JSON 数组字符串
   * @param selectedTables 用户勾选的表名列表
   * @param mode 'merge'=REPLACE 插入（保留已有，冲突覆盖）；'overwrite'=先 DELETE 全表再 INSERT
   * @returns 恢复结果
   */
  static async restoreTables(
    map: Map<string, string>,
    selectedTables: string[],
    mode: string
  ): Promise<BackupImportResult> {
    return DatabaseExecutor.executeInTransaction<BackupImportResult>('KnockShareService.restoreTables',
      async (store: relationalStore.RdbStore): Promise<BackupImportResult> => {
        let tableCount: number = 0;
        let rowCount: number = 0;
        for (let i: number = 0; i < selectedTables.length; i++) {
          const table: string = selectedTables[i];
          const json: string | undefined = map.get(table);
          if (json === undefined || json.length === 0) {
            continue;
          }
          const rows: relationalStore.ValuesBucket[] = JSON.parse(json) as relationalStore.ValuesBucket[];
          if (rows === null || rows.length === 0) {
            continue;
          }
          if (mode === 'overwrite') {
            const predicate: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(table);
            await store.delete(predicate);
          }
          for (let r: number = 0; r < rows.length; r++) {
            await store.insert(table, rows[r], relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
            rowCount++;
          }
          tableCount++;
        }
        const result: BackupImportResult = { tableCount: tableCount, rowCount: rowCount, imageCount: 0 };
        return result;
      });
  }

  /**
   * 从 BackupContent 执行选择性恢复 + 图片重建。
   * @param baseDir 应用 files 目录
   * @param content 解析后的备份内容
   * @param selectedTables 用户选中的表名列表
   * @param mode 'merge' | 'overwrite'
   */
  static async restoreFromContent(
    baseDir: string,
    content: BackupContent,
    selectedTables: string[],
    mode: string
  ): Promise<BackupImportResult | null> {
    try {
      const restoreResult: BackupImportResult = await KnockShareService.restoreTables(
        content.tableMap, selectedTables, mode);
      let imageCount: number = 0;
      // 仅当选中了含图片的表时才重建图片
      if (content.extraFiles.size > 0 &&
        (selectedTables.includes('diary_entry') || selectedTables.includes('happy_thing'))) {
        imageCount = await KnockShareService.rebuildImagePaths(baseDir, content.extraFiles);
      }
      const result: BackupImportResult = {
        tableCount: restoreResult.tableCount,
        rowCount: restoreResult.rowCount,
        imageCount: imageCount
      };
      return result;
    } catch (err) {
      hilog.error(0x0000, TAG, 'restoreFromContent failed: %{public}s', (err as BusinessError).message);
      return null;
    }
  }

  // ==================== fix: DEV-013 · 图片收集与路径重建 ====================

  /**
   * 从已聚合的表数据中收集 diary_entry 和 happy_thing 的真实沙箱图片文件。
   * 命名规则保证导入后可依 id+索权重建映射：
   *   diary_entry → images/diary_entry_{id}_{idx}.jpg
   *   happy_thing → images/happy_thing_{id}.jpg
   *
   * @param baseDir 应用 files 目录，用于解析相对路径。
   * @param tableMap 已聚合的表 JSON 数据。
   * @returns Map<容器内路径, 文件字节>。
   */
  private static async collectImageFiles(
    baseDir: string,
    tableMap: Map<string, string>
  ): Promise<Map<string, Uint8Array>> {
    const result: Map<string, Uint8Array> = new Map<string, Uint8Array>();

    // 扫描 diary_entry 表
    const diaryJson: string | undefined = tableMap.get('diary_entry');
    if (diaryJson !== undefined && diaryJson.length > 0) {
      const diaryRows: relationalStore.ValuesBucket[] = JSON.parse(diaryJson) as relationalStore.ValuesBucket[];
      for (let i: number = 0; i < diaryRows.length; i++) {
        const row: relationalStore.ValuesBucket = diaryRows[i];
        const rowId: number = row['id'] as number;
        const imagesVal: relationalStore.ValueType = row['images'];
        let imagesRaw: string = '[]';
        if (imagesVal !== null && imagesVal !== undefined) {
          imagesRaw = imagesVal as string;
        }
        const imagePaths: string[] = KnockShareService.parseImageArray(imagesRaw);
        for (let idx: number = 0; idx < imagePaths.length; idx++) {
          const oldPath: string = imagePaths[idx];
          const filePath: string = KnockShareService.uriToPath(oldPath);
          if (filePath.length > 0 && fileIo.accessSync(filePath)) {
            const bytes: Uint8Array = KnockShareService.readFileBytes(filePath);
            if (bytes.length > 0) {
              const containerName: string = 'images/diary_entry_' + rowId + '_' + idx + '.jpg';
              result.set(containerName, bytes);
            }
          }
        }
      }
    }

    // 扫描 happy_thing 表
    const happyJson: string | undefined = tableMap.get('happy_thing');
    if (happyJson !== undefined && happyJson.length > 0) {
      const happyRows: relationalStore.ValuesBucket[] = JSON.parse(happyJson) as relationalStore.ValuesBucket[];
      for (let i: number = 0; i < happyRows.length; i++) {
        const row: relationalStore.ValuesBucket = happyRows[i];
        const rowId: number = row['id'] as number;
        const imageVal: relationalStore.ValueType = row['image'];
        if (imageVal !== null && imageVal !== undefined) {
          const imageRaw: string = imageVal as string;
          if (imageRaw.length > 0) {
            const filePath: string = KnockShareService.uriToPath(imageRaw);
            if (filePath.length > 0 && fileIo.accessSync(filePath)) {
              const bytes: Uint8Array = KnockShareService.readFileBytes(filePath);
              if (bytes.length > 0) {
                const containerName: string = 'images/happy_thing_' + rowId + '.jpg';
                result.set(containerName, bytes);
              }
            }
          }
        }
      }
    }

    hilog.info(0x0000, TAG, 'collectImageFiles: %{public}d images collected', result.size);
    return result;
  }

  /**
   * 从导入的 extraFiles 中将图片复制到新设备沙箱，并 UPDATE diary_entry / happy_thing 的路径列。
   * 文件名中的 id 即导入后数据库行的 id（REPLACE 保留主键，故 id 与导出时一致）。
   *
   * @param baseDir 应用 files 目录。
   * @param extraFiles 容器中 images/ 下的文件（文件名 → 字节）。
   * @returns 成功重建的图片数量。
   */
  private static async rebuildImagePaths(
    baseDir: string,
    extraFiles: Map<string, Uint8Array>
  ): Promise<number> {
    // 确保沙箱 images/ 目录存在
    const sandboxImageDir: string = baseDir + '/images';
    KnockShareService.ensureDir(sandboxImageDir);

    // 收集文件名，按 diary_entry / happy_thing 分组
    const fileNames: string[] = [];
    extraFiles.forEach((_val: Uint8Array, key: string) => {
      fileNames.push(key);
    });

    // 分组：diary_entry -> Map<id, Map<idx, bytes>>
    const diaryGroups: Map<number, Map<number, Uint8Array>> = new Map<number, Map<number, Uint8Array>>();
    // 分组：happy_thing -> Map<id, bytes>
    const happyGroups: Map<number, Uint8Array> = new Map<number, Uint8Array>();

    for (let i: number = 0; i < fileNames.length; i++) {
      const name: string = fileNames[i];
      const bytes: Uint8Array = extraFiles.get(name) as Uint8Array;
      // 期望格式: images/diary_entry_{id}_{idx}.jpg 或 images/happy_thing_{id}.jpg
      const baseName: string = KnockShareService.fileBaseName(name);

      if (baseName.startsWith('diary_entry_')) {
        const parsed: DiaryImageKey | null = KnockShareService.parseDiaryImageName(baseName);
        if (parsed !== null) {
          let idxMap: Map<number, Uint8Array> | undefined = diaryGroups.get(parsed.id);
          if (idxMap === undefined) {
            idxMap = new Map<number, Uint8Array>();
            diaryGroups.set(parsed.id, idxMap);
          }
          idxMap.set(parsed.idx, bytes);
        }
      } else if (baseName.startsWith('happy_thing_')) {
        const parsedId: number | null = KnockShareService.parseHappyImageName(baseName);
        if (parsedId !== null) {
          happyGroups.set(parsedId, bytes);
        }
      }
    }

    let rebuiltCount: number = 0;

    // 重建 diary_entry 图片
    const diaryEntries: Map<number, Map<number, Uint8Array>> = diaryGroups;
    if (diaryEntries.size > 0) {
      const diaryRebuilt: number = await DatabaseExecutor.executeWrite<number>(
        'KnockShareService.rebuildDiaryImages',
        async (store: relationalStore.RdbStore): Promise<number> => {
          let count: number = 0;
          const diaryIds: number[] = [];
          diaryEntries.forEach((_idxMap: Map<number, Uint8Array>, idKey: number) => {
            diaryIds.push(idKey);
          });

          for (let d: number = 0; d < diaryIds.length; d++) {
            const rowId: number = diaryIds[d];
            const idxMap: Map<number, Uint8Array> = diaryEntries.get(rowId) as Map<number, Uint8Array>;

            // 读取当前行以获取 images JSON（可能含旧路径需要替换）
            const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('diary_entry');
            predicates.equalTo('id', rowId);
            const rs: relationalStore.ResultSet = await store.query(predicates);
            if (!rs.goToFirstRow()) {
              rs.close();
              // 行不存在（可能被 REPLACE 变更 id — 极端情况），跳过但仍拷贝文件
              const idxKeys: number[] = [];
              idxMap.forEach((_b: Uint8Array, k: number) => { idxKeys.push(k); });
              idxKeys.sort((a: number, b: number) => a - b);   // 数值升序（默认 sort 为字典序，idx≥10 会错位）
              for (let k: number = 0; k < idxKeys.length; k++) {
                const idx: number = idxKeys[k];
                const imgBytes: Uint8Array = idxMap.get(idx) as Uint8Array;
                const sandboxName: string = 'diary_entry_' + rowId + '_' + idx + '.jpg';
                const sandboxPath: string = sandboxImageDir + '/' + sandboxName;
                KnockShareService.writeFileBytes(sandboxPath, imgBytes);
                count++;
              }
              continue;
            }

            // 构建新 images 数组（file:// 前缀的沙箱路径）
            const newPaths: string[] = [];
            const idxKeys: number[] = [];
            idxMap.forEach((_b: Uint8Array, k: number) => { idxKeys.push(k); });
            idxKeys.sort((a: number, b: number) => a - b);   // 数值升序：保证图片顺序与导出时 images[] 索引一致（对应关系不错乱）

            for (let k: number = 0; k < idxKeys.length; k++) {
              const idx: number = idxKeys[k];
              const imgBytes: Uint8Array = idxMap.get(idx) as Uint8Array;
              const sandboxName: string = 'diary_entry_' + rowId + '_' + idx + '.jpg';
              const sandboxPath: string = sandboxImageDir + '/' + sandboxName;
              KnockShareService.writeFileBytes(sandboxPath, imgBytes);
              newPaths.push('file://' + sandboxPath);
              count++;
            }

            // UPDATE images 列
            const newImagesJson: string = JSON.stringify(newPaths);
            const updateBucket: relationalStore.ValuesBucket = {};
            updateBucket['images'] = newImagesJson;
            await store.update(updateBucket, predicates);
            rs.close();
          }
          return count;
        });
      rebuiltCount += diaryRebuilt;
    }

    // 重建 happy_thing 图片
    if (happyGroups.size > 0) {
      const happyRebuilt: number = await DatabaseExecutor.executeWrite<number>(
        'KnockShareService.rebuildHappyImages',
        async (store: relationalStore.RdbStore): Promise<number> => {
          let count: number = 0;
          const happyIds: number[] = [];
          happyGroups.forEach((_b: Uint8Array, idKey: number) => {
            happyIds.push(idKey);
          });

          for (let h: number = 0; h < happyIds.length; h++) {
            const rowId: number = happyIds[h];
            const imgBytes: Uint8Array = happyGroups.get(rowId) as Uint8Array;

            const sandboxName: string = 'happy_thing_' + rowId + '.jpg';
            const sandboxPath: string = sandboxImageDir + '/' + sandboxName;
            KnockShareService.writeFileBytes(sandboxPath, imgBytes);
            const newUri: string = 'file://' + sandboxPath;
            count++;

            // UPDATE image 列
            const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('happy_thing');
            predicates.equalTo('id', rowId);
            const updateBucket: relationalStore.ValuesBucket = {};
            updateBucket['image'] = newUri;
            await store.update(updateBucket, predicates);
          }
          return count;
        });
      rebuiltCount += happyRebuilt;
    }

    hilog.info(0x0000, TAG, 'rebuildImagePaths: %{public}d images rebuilt', rebuiltCount);
    return rebuiltCount;
  }

  // ==================== 私有：文件/路径工具 ====================

  private static safeFileSize(path: string): number {
    try {
      return fileIo.statSync(path).size;
    } catch (_e) {
      return 0;
    }
  }

  private static ensureDir(dirPath: string): void {
    try {
      fileIo.mkdirSync(dirPath, true);
    } catch (_e) {
      // 目录已存在
    }
  }

  /**
   * 将 file:// URI 转为文件系统绝对路径；非 file:// 或异常返回空串。
   */
  private static uriToPath(uri: string): string {
    if (uri.startsWith('file://')) {
      return uri.substring(7);
    }
    if (uri.startsWith('/')) {
      return uri;
    }
    return '';
  }

  /**
   * 从路径中提取文件名（去目录前缀）。
   */
  private static fileBaseName(path: string): string {
    const lastSlash: number = path.lastIndexOf('/');
    if (lastSlash >= 0) {
      return path.substring(lastSlash + 1);
    }
    return path;
  }

  /**
   * 解析 "diary_entry_{id}_{idx}.jpg" → DiaryImageKey
   */
  private static parseDiaryImageName(baseName: string): DiaryImageKey | null {
    // 去掉 "diary_entry_" 前缀 和 ".jpg" 后缀
    const prefix: string = 'diary_entry_';
    if (!baseName.startsWith(prefix)) {
      return null;
    }
    const withoutExt: string = baseName.endsWith('.jpg') ? baseName.substring(0, baseName.length - 4) : baseName;
    const body: string = withoutExt.substring(prefix.length); // "{id}_{idx}"
    const underscoreIdx: number = body.lastIndexOf('_');
    if (underscoreIdx < 0) {
      return null;
    }
    const idStr: string = body.substring(0, underscoreIdx);
    const idxStr: string = body.substring(underscoreIdx + 1);
    const id: number = parseInt(idStr);
    const idx: number = parseInt(idxStr);
    if (isNaN(id) || isNaN(idx)) {
      return null;
    }
    const result: DiaryImageKey = { id: id, idx: idx };
    return result;
  }

  /**
   * 解析 "happy_thing_{id}.jpg" → id
   */
  private static parseHappyImageName(baseName: string): number | null {
    const prefix: string = 'happy_thing_';
    if (!baseName.startsWith(prefix)) {
      return null;
    }
    const withoutExt: string = baseName.endsWith('.jpg') ? baseName.substring(0, baseName.length - 4) : baseName;
    const idStr: string = withoutExt.substring(prefix.length);
    const id: number = parseInt(idStr);
    if (isNaN(id)) {
      return null;
    }
    return id;
  }

  /**
   * 解析 diary_entry.images JSON 字符串为路径数组。
   */
  private static parseImageArray(imagesJson: string): string[] {
    try {
      const arr: string[] = JSON.parse(imagesJson) as string[];
      if (arr === null || arr === undefined) {
        return [];
      }
      return arr;
    } catch (_e) {
      return [];
    }
  }

  /**
   * 读取文件全部字节。
   */
  private static readFileBytes(path: string): Uint8Array {
    try {
      const stat: fileIo.Stat = fileIo.statSync(path);
      if (stat.size === 0) {
        return new Uint8Array(0);
      }
      const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);
      return new Uint8Array(buffer);
    } catch (_e) {
      return new Uint8Array(0);
    }
  }

  /**
   * 将字节写入文件（覆盖创建）。
   */
  private static writeFileBytes(path: string, data: Uint8Array): void {
    const file: fileIo.File = fileIo.openSync(path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
    fileIo.writeSync(file.fd, data.buffer as ArrayBuffer);
    fileIo.closeSync(file);
  }
}

// ── 图片跨设备搬运说明（诚实边界）──────────────────────────────────────
// DiaryBundle.images 为「发送端本地 URI」；跨设备导入时对端文件系统无这些路径。
// 真·双真机碰传图片需把图片字节经【分布式文件】(context.distributedFilesDir) 或软总线搬到对端后
// 重写为对端本地路径 —— 该步依赖两台已互信设备，属「双真机验证」范畴，本引擎负责载荷与落库，
// 图片字节搬运在 ShareViewModel 传输阶段接线（见其 startTransfer 注释）。单机导入(相同设备)图片路径有效。
