// <!-- agentID: DEV-013 -->
// fix: DEV-013 · T-B01 全库备份含照片：容器格式从单 JSON 升级为 EDIARYV2 多文件容器（metadata.json + 表 JSON + images/），
//   gzip 压缩信封，导入后重建沙箱路径。
// File: BackupUtils.ets
// Task: T007c Data utility - Data export/import, binary container, gzip, version compatibility

import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'BackupUtils';

/** Backup metadata header */
export interface BackupMeta {
  version: number;
  appVersion: string;
  created: number;
  tableCount: number;
  checksum: string;
}

/** Progress callback type */
export type ProgressCallback = (current: number, total: number, message: string) => void;

/** Backup file info */
export interface BackupFileInfo {
  name: string;
  path: string;
  size: number;
  created: number;
}

/** Backup payload structure for serialization (legacy single-JSON format, kept for backward compat) */
export interface BackupPayload {
  meta: BackupMeta;
  tables: Record<string, string>;
}

/** fix: DEV-013 · Import result containing both table data and extra files (images) */
export interface BackupContent {
  meta: BackupMeta;
  tableMap: Map<string, string>;
  extraFiles: Map<string, Uint8Array>;
}

/**
 * BackupUtils - Data export/import with binary container + gzip compression.
 * Flow Export: serialize data → build container → gzip → write .ediary.zip
 * Flow Import: read .ediary.zip → gunzip → parse container → extract tables + extra files
 *
 * Container format "EDIARYV2":
 *   [8] Magic "EDIARYV2"
 *   [4] Version uint32 LE
 *   [4] File count uint32 LE
 *   For each file:
 *     [2] Name length uint16 LE
 *     [N] Name UTF-8
 *     [4] Data length uint32 LE
 *     [M] Data
 *
 * Backward compat: if first byte is not 'E' (0x45), fall back to legacy single-JSON parse.
 */
export class BackupUtils {
  private static readonly BACKUP_DIR = 'backups';
  private static readonly BACKUP_VERSION = 1;
  private static readonly CONTAINER_VERSION = 2;
  private static readonly CONTAINER_MAGIC_STRING = 'EDIARYV2';
  private static cancelFlag: boolean = false;

  // ===================== Public API ====================

  /**
   * Export all database tables + optional extra files (images) to a gzip-compressed backup.
   *
   * @param baseDir Application files directory.
   * @param tableData Map of table name -> serialized JSON array.
   * @param password Reserved for AES (currently unused; envelope is gzip).
   * @param extraFiles Optional extra files to include (filename -> bytes), e.g. images/.
   * @param onProgress Progress callback.
   * @returns Path to the exported backup file or null on failure.
   */
  static async exportBackup(
    baseDir: string,
    tableData: Map<string, string>,
    password: string,
    extraFiles?: Map<string, Uint8Array>,
    onProgress?: ProgressCallback
  ): Promise<string | null> {
    BackupUtils.cancelFlag = false;
    const extraCount: number = extraFiles ? extraFiles.size : 0;
    const totalSteps: number = tableData.size + extraCount + 2; // build + gzip
    let currentStep: number = 0;

    try {
      const backupDir: string = baseDir + '/' + BackupUtils.BACKUP_DIR;
      BackupUtils.ensureDir(backupDir);

      // Build metadata
      onProgress?.(++currentStep, totalSteps, 'Building metadata...');
      if (BackupUtils.cancelFlag) {
        return null;
      }

      const meta: BackupMeta = {
        version: BackupUtils.BACKUP_VERSION,
        appVersion: '1.0.0',
        created: Date.now(),
        tableCount: tableData.size,
        checksum: ''
      };

      // Build file map: metadata + tables + extra files
      const fileMap: Map<string, Uint8Array> = new Map<string, Uint8Array>();
      const textEncoder: util.TextEncoder = new util.TextEncoder();

      // metadata.json
      const metaJson: string = JSON.stringify(meta);
      fileMap.set('metadata.json', textEncoder.encodeInto(metaJson));

      // Table JSONs
      const tableNames: string[] = [];
      tableData.forEach((value: string, key: string) => {
        tableNames.push(key);
      });
      let tableStep: number = 0;
      for (let t: number = 0; t < tableNames.length; t++) {
        const tName: string = tableNames[t];
        const tData: string = tableData.get(tName) as string;
        if (BackupUtils.cancelFlag) {
          return null;
        }
        onProgress?.(++currentStep, totalSteps, 'Packing: ' + tName);
        fileMap.set(tName + '.json', textEncoder.encodeInto(tData));
      }

      // Extra files (images)
      if (extraFiles !== undefined && extraFiles.size > 0) {
        const extraNames: string[] = [];
        extraFiles.forEach((_bytes: Uint8Array, name: string) => {
          extraNames.push(name);
        });
        for (let e: number = 0; e < extraNames.length; e++) {
          const eName: string = extraNames[e];
          const eData: Uint8Array = extraFiles.get(eName) as Uint8Array;
          if (BackupUtils.cancelFlag) {
            return null;
          }
          onProgress?.(++currentStep, totalSteps, 'Packing: ' + eName);
          fileMap.set(eName, eData);
        }
      }

      // Build container binary
      onProgress?.(++currentStep, totalSteps, 'Building container...');
      const containerBytes: Uint8Array = BackupUtils.buildContainer(fileMap);

      // Write container directly (不压缩：zlib.compressFile/decompressFile 格式兼容性问题，
      //   parseRawData 已支持直接解析 EDIARYV2 容器——检测 0x45 magic byte）
      const timestamp: number = Date.now();
      const finalPath: string = backupDir + '/backup_' + timestamp + '.ediary.zip';

      BackupUtils.writeBytes(finalPath, containerBytes);

      onProgress?.(totalSteps, totalSteps, 'Export complete');
      hilog.info(0xFF00, TAG, 'Backup exported: %{public}s', finalPath);
      return finalPath;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Export failed: %{public}s', error.message);
      return null;
    }
  }

  /**
   * Import data from a backup file. Supports both EDIARYV2 container and legacy single-JSON formats.
   *
   * @param filePath Path to the backup file (.ediary.zip).
   * @param password Reserved for AES (currently unused).
   * @param onProgress Progress callback.
   * @returns BackupContent with meta, tableMap, and extraFiles; or null on failure.
   */
  static async importBackup(
    filePath: string,
    password: string,
    onProgress?: ProgressCallback
  ): Promise<BackupContent | null> {
    BackupUtils.cancelFlag = false;
    const totalSteps: number = 4;
    let currentStep: number = 0;

    try {
      // Step 1: Check file exists
      onProgress?.(++currentStep, totalSteps, 'Reading backup file...');
      if (!fileIo.accessSync(filePath)) {
        hilog.error(0xFF00, TAG, 'Backup file not found: %{public}s', filePath);
        return null;
      }

      // Step 2: Unzip into a temp directory (zlib.decompressFile extracts into a directory)
      onProgress?.(++currentStep, totalSteps, 'Decompressing...');
      if (BackupUtils.cancelFlag) {
        return null;
      }
      // Legacy fallback: old exporter wrote raw JSON with .zip suffix (never actually zipped) →
      // decompressFile throws 900003 → read the file bytes directly.
      let rawBytes: Uint8Array | null = null;
      // 先尝试解压（兼容旧版 zlib 压缩的备份）
      const unzipped: Uint8Array | null = await BackupUtils.unzipSingleEntry(filePath);
      if (unzipped !== null) {
        rawBytes = unzipped;
      } else {
        // 直接读取原始字节（当前导出格式：未压缩的 EDIARYV2 容器）
        rawBytes = BackupUtils.readBytes(filePath);
      }

      if (BackupUtils.cancelFlag) {
        return null;
      }

      // Step 4: Detect format and parse
      onProgress?.(++currentStep, totalSteps, 'Extracting data...');
      const content: BackupContent | null = BackupUtils.parseRawData(rawBytes);
      if (content === null) {
        hilog.error(0xFF00, TAG, 'Failed to parse backup data');
        return null;
      }

      // Version compatibility check
      if (content.meta.version > BackupUtils.BACKUP_VERSION) {
        hilog.error(0xFF00, TAG, 'Backup version %{public}d is newer than app version %{public}d',
          content.meta.version, BackupUtils.BACKUP_VERSION);
        return null;
      }

      onProgress?.(totalSteps, totalSteps, 'Import complete');
      hilog.info(0xFF00, TAG, 'Backup imported: %{public}d tables, %{public}d extra files',
        content.tableMap.size, content.extraFiles.size);
      return content;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Import failed: %{public}s', error.message);
      return null;
    }
  }

  /**
   * Cancel an ongoing export/import operation.
   */
  static cancel(): void {
    BackupUtils.cancelFlag = true;
    hilog.info(0xFF00, TAG, 'Backup operation cancelled');
  }

  /**
   * List all backup files.
   */
  static listBackups(baseDir: string): BackupFileInfo[] {
    try {
      const backupDir: string = baseDir + '/' + BackupUtils.BACKUP_DIR;
      BackupUtils.ensureDir(backupDir);
      const files: string[] = fileIo.listFileSync(backupDir);
      const result: BackupFileInfo[] = [];
      for (const file of files) {
        // Skip temp files / unpack dirs
        if (file.startsWith('_tmp_') || file.endsWith('.unpack')) {
          continue;
        }
        const filePath: string = backupDir + '/' + file;
        const stat: fileIo.Stat = fileIo.statSync(filePath);
        const backupInfo: BackupFileInfo = {
          name: file,
          path: filePath,
          size: stat.size,
          created: stat.mtime
        };
        result.push(backupInfo);
      }
      return result.sort((a, b) => b.created - a.created);
    } catch (_err) {
      return [];
    }
  }

  /**
   * Delete a specific backup file.
   */
  static deleteBackup(filePath: string): boolean {
    try {
      fileIo.unlinkSync(filePath);
      hilog.info(0xFF00, TAG, 'Backup deleted: %{public}s', filePath);
      return true;
    } catch (err) {
      hilog.error(0xFF00, TAG, 'Failed to delete backup: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * Validate backup file version compatibility.
   */
  static async validateBackup(filePath: string): Promise<boolean> {
    try {
      const stat: fileIo.Stat = fileIo.statSync(filePath);
      if (stat.size === 0) {
        return false;
      }
      // Unzip (or legacy raw read) and check
      let rawBytes: Uint8Array | null = await BackupUtils.unzipSingleEntry(filePath);
      if (rawBytes === null) {
        rawBytes = BackupUtils.readBytes(filePath);
      }

      const content: BackupContent | null = BackupUtils.parseRawData(rawBytes);
      if (content === null) {
        return false;
      }
      return content.meta.version <= BackupUtils.BACKUP_VERSION;
    } catch (_err) {
      return false;
    }
  }

  /**
   * fix: DEV-013 · Unzip a single-entry archive produced by zlib.compressFile into a temp
   * directory and return the entry's bytes. Returns null if the file is not a valid ZIP
   * (legacy raw-JSON backups) or extraction fails; caller falls back to raw read.
   */
  private static async unzipSingleEntry(filePath: string): Promise<Uint8Array | null> {
    const unpackDir: string = filePath + '.unpack';
    let result: Uint8Array | null = null;
    // 清理上次失败残留的 .unpack 目录，避免 decompressFile 因目录非空而失败
    try {
      const leftovers: string[] = fileIo.listFileSync(unpackDir);
      for (let i: number = 0; i < leftovers.length; i++) {
        try {
          fileIo.unlinkSync(unpackDir + '/' + leftovers[i]);
        } catch (_e) {
          // ignore
        }
      }
      fileIo.rmdirSync(unpackDir);
    } catch (_e) {
      // 目录不存在，正常
    }
    try {
      BackupUtils.ensureDir(unpackDir);
      await zlib.decompressFile(filePath, unpackDir);
      const entries: string[] = fileIo.listFileSync(unpackDir);
      if (entries.length > 0) {
        result = BackupUtils.readBytes(unpackDir + '/' + entries[0]);
      }
    } catch (err) {
      hilog.warn(0xFF00, TAG, 'unzipSingleEntry: not a zip or extract failed: %{public}s',
        (err as BusinessError).message);
      result = null;
    }
    // Cleanup temp dir (best-effort)
    try {
      const leftovers: string[] = fileIo.listFileSync(unpackDir);
      for (let i: number = 0; i < leftovers.length; i++) {
        try {
          fileIo.unlinkSync(unpackDir + '/' + leftovers[i]);
        } catch (_e) {
          // ignore
        }
      }
      fileIo.rmdirSync(unpackDir);
    } catch (_e) {
      // ignore cleanup failure
    }
    return result;
  }

  // ===================== Container Builder / Parser ====================

  /**
   * Build EDIARYV2 binary container from a map of filename -> file bytes.
   */
  private static buildContainer(files: Map<string, Uint8Array>): Uint8Array {
    // Collect filenames in deterministic order (sorted)
    const names: string[] = [];
    files.forEach((_data: Uint8Array, name: string) => {
      names.push(name);
    });
    names.sort();

    // Calculate total size
    const magicBytes: Uint8Array = BackupUtils.strToUtf8(BackupUtils.CONTAINER_MAGIC_STRING);
    let totalSize: number = 0;
    totalSize += magicBytes.length;       // magic (8)
    totalSize += 4;                        // version
    totalSize += 4;                        // file count

    for (let i: number = 0; i < names.length; i++) {
      const name: string = names[i];
      const nameBytes: Uint8Array = BackupUtils.strToUtf8(name);
      const data: Uint8Array = files.get(name) as Uint8Array;
      totalSize += 2;                      // name length
      totalSize += nameBytes.length;       // name
      totalSize += 4;                      // data length
      totalSize += data.length;            // data
    }

    // Allocate buffer
    const buf: ArrayBuffer = new ArrayBuffer(totalSize);
    const out: Uint8Array = new Uint8Array(buf);
    let offset: number = 0;

    // Write magic
    out.set(magicBytes, offset);
    offset += magicBytes.length;

    // Write version
    BackupUtils.writeUint32LE(out, offset, BackupUtils.CONTAINER_VERSION);
    offset += 4;

    // Write file count
    BackupUtils.writeUint32LE(out, offset, names.length);
    offset += 4;

    // Write file entries
    for (let i: number = 0; i < names.length; i++) {
      const name: string = names[i];
      const nameBytes: Uint8Array = BackupUtils.strToUtf8(name);
      const data: Uint8Array = files.get(name) as Uint8Array;

      // Name length
      BackupUtils.writeUint16LE(out, offset, nameBytes.length);
      offset += 2;

      // Name
      out.set(nameBytes, offset);
      offset += nameBytes.length;

      // Data length
      BackupUtils.writeUint32LE(out, offset, data.length);
      offset += 4;

      // Data
      out.set(data, offset);
      offset += data.length;
    }

    return out;
  }

  /**
   * Parse EDIARYV2 binary container into a map of filename -> file bytes.
   */
  private static parseContainer(data: Uint8Array): Map<string, Uint8Array> | null {
    try {
      if (data.length < 16) {
        return null;
      }

      // Check magic
      const magicStr: string = BackupUtils.CONTAINER_MAGIC_STRING;
      const magicBytes: Uint8Array = BackupUtils.strToUtf8(magicStr);
      for (let i: number = 0; i < magicBytes.length; i++) {
        if (data[i] !== magicBytes[i]) {
          hilog.warn(0xFF00, TAG, 'Container magic mismatch');
          return null;
        }
      }

      let offset: number = magicBytes.length;

      // Version
      const version: number = BackupUtils.readUint32LE(data, offset);
      offset += 4;
      if (version !== BackupUtils.CONTAINER_VERSION) {
        hilog.warn(0xFF00, TAG, 'Container version mismatch: %{public}d', version);
      }

      // File count
      const fileCount: number = BackupUtils.readUint32LE(data, offset);
      offset += 4;

      const result: Map<string, Uint8Array> = new Map<string, Uint8Array>();

      for (let i: number = 0; i < fileCount; i++) {
        if (offset + 2 > data.length) {
          return null;
        }
        // Name length
        const nameLen: number = BackupUtils.readUint16LE(data, offset);
        offset += 2;

        if (offset + nameLen > data.length) {
          return null;
        }
        // Name
        const nameBytes: Uint8Array = new Uint8Array(nameLen);
        for (let j: number = 0; j < nameLen; j++) {
          nameBytes[j] = data[offset + j];
        }
        const name: string = BackupUtils.utf8ToStr(nameBytes);
        offset += nameLen;

        if (offset + 4 > data.length) {
          return null;
        }
        // Data length
        const dataLen: number = BackupUtils.readUint32LE(data, offset);
        offset += 4;

        if (offset + dataLen > data.length) {
          return null;
        }
        // Data
        const fileData: Uint8Array = new Uint8Array(dataLen);
        for (let j: number = 0; j < dataLen; j++) {
          fileData[j] = data[offset + j];
        }
        offset += dataLen;

        result.set(name, fileData);
      }

      return result;
    } catch (err) {
      hilog.error(0xFF00, TAG, 'Parse container failed: %{public}s', (err as BusinessError).message);
      return null;
    }
  }

  /**
   * Parse raw decompressed bytes — detects EDIARYV2 vs legacy JSON format.
   */
  private static parseRawData(data: Uint8Array): BackupContent | null {
    // Detect: if starts with 'E' (0x45), it's EDIARYV2 container
    if (data.length > 0 && data[0] === 0x45) {
      return BackupUtils.parseV2Container(data);
    }
    // Fallback: legacy single-JSON format
    return BackupUtils.parseLegacyJson(data);
  }

  /**
   * Parse EDIARYV2 container into BackupContent.
   */
  private static parseV2Container(data: Uint8Array): BackupContent | null {
    const fileMap: Map<string, Uint8Array> | null = BackupUtils.parseContainer(data);
    if (fileMap === null) {
      return null;
    }

    // Extract metadata.json
    const metaBytes: Uint8Array | undefined = fileMap.get('metadata.json');
    if (metaBytes === undefined) {
      hilog.error(0xFF00, TAG, 'Container missing metadata.json');
      return null;
    }
    const textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    const metaJson: string = textDecoder.decodeWithStream(metaBytes);
    const meta: BackupMeta = JSON.parse(metaJson) as BackupMeta;

    // Extract table JSONs (files ending in .json that are not metadata.json)
    const tableMap: Map<string, string> = new Map<string, string>();
    const extraFiles: Map<string, Uint8Array> = new Map<string, Uint8Array>();

    const allNames: string[] = [];
    fileMap.forEach((_val: Uint8Array, key: string) => {
      allNames.push(key);
    });

    for (let i: number = 0; i < allNames.length; i++) {
      const name: string = allNames[i];
      const bytes: Uint8Array = fileMap.get(name) as Uint8Array;
      if (name === 'metadata.json') {
        continue;
      }
      if (name.endsWith('.json') && !name.includes('/')) {
        // Table JSON: "diary_entry.json" -> table "diary_entry"
        const tableName: string = name.substring(0, name.length - 5);
        const tableJson: string = textDecoder.decodeWithStream(bytes);
        tableMap.set(tableName, tableJson);
      } else {
        // Extra file (e.g., images/diary_entry_1_0.jpg)
        extraFiles.set(name, bytes);
      }
    }

    const result: BackupContent = {
      meta: meta,
      tableMap: tableMap,
      extraFiles: extraFiles
    };
    return result;
  }

  /**
   * Parse legacy single-JSON backup format.
   */
  private static parseLegacyJson(data: Uint8Array): BackupContent | null {
    try {
      const textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const jsonStr: string = textDecoder.decodeWithStream(data);
      const backupData: BackupPayload = JSON.parse(jsonStr) as BackupPayload;
      const meta: BackupMeta = backupData.meta;
      const tables: Record<string, string> = backupData.tables;
      const tableMap: Map<string, string> = new Map<string, string>();
      const keys: string[] = Object.keys(tables);
      for (let i: number = 0; i < keys.length; i++) {
        const k: string = keys[i];
        tableMap.set(k, tables[k]);
      }

      const result: BackupContent = {
        meta: meta,
        tableMap: tableMap,
        extraFiles: new Map<string, Uint8Array>()
      };
      return result;
    } catch (err) {
      hilog.error(0xFF00, TAG, 'Legacy JSON parse failed: %{public}s', (err as BusinessError).message);
      return null;
    }
  }

  // ===================== Binary I/O Helpers ====================

  private static writeUint16LE(buf: Uint8Array, offset: number, value: number): void {
    buf[offset] = value & 0xFF;
    buf[offset + 1] = (value >> 8) & 0xFF;
  }

  private static writeUint32LE(buf: Uint8Array, offset: number, value: number): void {
    buf[offset] = value & 0xFF;
    buf[offset + 1] = (value >> 8) & 0xFF;
    buf[offset + 2] = (value >> 16) & 0xFF;
    buf[offset + 3] = (value >> 24) & 0xFF;
  }

  private static readUint16LE(buf: Uint8Array, offset: number): number {
    return buf[offset] | (buf[offset + 1] << 8);
  }

  private static readUint32LE(buf: Uint8Array, offset: number): number {
    return buf[offset] | (buf[offset + 1] << 8) | (buf[offset + 2] << 16) | (buf[offset + 3] << 24);
  }

  private static strToUtf8(str: string): Uint8Array {
    const encoder: util.TextEncoder = new util.TextEncoder();
    return encoder.encodeInto(str);
  }

  private static utf8ToStr(bytes: Uint8Array): string {
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    return decoder.decodeWithStream(bytes);
  }

  private static writeBytes(path: string, data: Uint8Array): void {
    const file: fileIo.File = fileIo.openSync(path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
    fileIo.writeSync(file.fd, data.buffer as ArrayBuffer);
    fileIo.closeSync(file);
  }

  private static readBytes(path: string): Uint8Array {
    const stat: fileIo.Stat = fileIo.statSync(path);
    const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, buffer);
    fileIo.closeSync(file);
    return new Uint8Array(buffer);
  }

  private static simpleHash(data: Uint8Array): string {
    let hash: number = 0;
    for (let i: number = 0; i < data.length; i++) {
      const char: number = data[i];
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash;
    }
    return Math.abs(hash).toString(16);
  }

  private static ensureDir(dirPath: string): void {
    try {
      fileIo.mkdirSync(dirPath, true);
    } catch (_err) {
      // Directory already exists
    }
  }
}
