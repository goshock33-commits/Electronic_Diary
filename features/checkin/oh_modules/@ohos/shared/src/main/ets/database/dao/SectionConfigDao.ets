// <!-- agentID: DEV-009 -->
// File: SectionConfigDao.ets
// Task: M06 New DAO - section_config CRUD (table has DDL but previously no DAO)
// Architecture: ARC-001 4.1 SectionConfigDao API
// Previously SectionViewModel used raw SQL inline; now encapsulated here with async APIs

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseExecutor } from '../DatabaseExecutor';

const TAG = 'SectionConfigDao';

/**
 * Section configuration data object.
 * Maps to section_config table columns (snake_case in DB, camelCase in code).
 */
export interface SectionConfig {
  id: number;
  sectionKey: string;
  title: string;
  isVisible: number;
  sortOrder: number;
}

export class SectionConfigDao {
  /**
   * M06(DEV-005): 默认五分区种子。首次启动由 StartupTasks 非致命调用灌入,
   * 保证空表时首页也有分区配置(否则冷启动首页无分区可渲染)。
   * key/title/顺序与 SectionViewModel.DEFAULT_SECTIONS 及 SectionManager.DEFAULT_SECTION_ITEMS
   * 三处同源,勿改散。
   */
  private static readonly DEFAULT_SEEDS: SectionConfig[] = [
    { id: 0, sectionKey: 'today_todo', title: '今日待办', isVisible: 1, sortOrder: 1 },
    { id: 0, sectionKey: 'tomorrow_todo', title: '明日待办', isVisible: 1, sortOrder: 2 },
    { id: 0, sectionKey: 'extra', title: '多做的事', isVisible: 1, sortOrder: 3 },
    { id: 0, sectionKey: 'happy', title: '开心的事', isVisible: 1, sortOrder: 4 },
    { id: 0, sectionKey: 'extracted', title: '提取任务', isVisible: 1, sortOrder: 5 }
  ];

  /**
   * Load all section configs ordered by sort_order.
   * Sync→Async: querySqlSync → await store.querySql()
   * @returns Promise<SectionConfig[]>
   */
  static async loadAll(): Promise<SectionConfig[]> {
    return DatabaseExecutor.executeRead<SectionConfig[]>('SectionConfigDao.loadAll',
      async (store: relationalStore.RdbStore): Promise<SectionConfig[]> => {
        const sql = 'SELECT * FROM section_config ORDER BY sort_order ASC';
        const resultSet = await store.querySql(sql, []);
        const configs: SectionConfig[] = [];
        while (resultSet.goToNextRow()) {
          configs.push({
            id: resultSet.getLong(resultSet.getColumnIndex('id')),
            sectionKey: resultSet.getString(resultSet.getColumnIndex('section_key')),
            title: resultSet.getString(resultSet.getColumnIndex('title')),
            isVisible: resultSet.getLong(resultSet.getColumnIndex('is_visible')),
            sortOrder: resultSet.getLong(resultSet.getColumnIndex('sort_order'))
          });
        }
        resultSet.close();
        hilog.debug(0x0000, TAG, 'Loaded %{public}d section configs', configs.length);
        return configs;
      });
  }

  /**
   * Save all section configs in a single transaction.
   * Uses executeInTransaction for atomicity; upserts each config (update if id>0, insert otherwise).
   * Sync→Async: insertSync→insert, updateSync→update
   * @param configs Array of SectionConfig to persist
   */
  static async saveAll(configs: SectionConfig[]): Promise<void> {
    return DatabaseExecutor.executeInTransaction<void>('SectionConfigDao.saveAll',
      async (store: relationalStore.RdbStore): Promise<void> => {
        const now = Date.now();
        for (const cfg of configs) {
          const valueBucket: relationalStore.ValuesBucket = {
            'section_key': cfg.sectionKey,
            'title': cfg.title,
            'is_visible': cfg.isVisible,
            'sort_order': cfg.sortOrder,
            'updated_at': now
          };
          if (cfg.id > 0) {
            const predicates = new relationalStore.RdbPredicates('section_config');
            predicates.equalTo('id', cfg.id);
            await store.update(valueBucket, predicates);
            hilog.debug(0x0000, TAG, 'Updated section: key=%{public}s', cfg.sectionKey);
          } else {
            const rowId = await store.insert('section_config', valueBucket);
            hilog.info(0x0000, TAG, 'Inserted section: key=%{public}s, rowId=%{public}d',
              cfg.sectionKey, rowId);
          }
        }
      });
  }

  /**
   * M06(DEV-005): 幂等灌入默认五分区(仅当 section_config 为空时)。
   * 范式对齐 CustomEmojiDao.seedBuiltins: executeTransaction + SELECT COUNT(*) 守卫。
   * 由 StartupTasks.initDatabase 非致命调用(失败不阻塞启动)。
   */
  static async seedDefaults(): Promise<void> {
    return DatabaseExecutor.executeTransaction<void>('SectionConfigDao.seedDefaults',
      async (store: relationalStore.RdbStore): Promise<void> => {
        // 幂等守卫: 表非空(用户已有配置或已灌种子)则跳过
        const checkSql = 'SELECT COUNT(*) as cnt FROM section_config';
        const checkRs = await store.querySql(checkSql, []);
        let existing = 0;
        if (checkRs.goToFirstRow()) {
          existing = checkRs.getLong(checkRs.getColumnIndex('cnt'));
        }
        checkRs.close();
        if (existing > 0) {
          hilog.info(0x0000, TAG, 'seedDefaults skipped: %{public}d sections present', existing);
          return;
        }
        const now = Date.now();
        for (const cfg of SectionConfigDao.DEFAULT_SEEDS) {
          const valueBucket: relationalStore.ValuesBucket = {
            'section_key': cfg.sectionKey,
            'title': cfg.title,
            'is_visible': cfg.isVisible,
            'sort_order': cfg.sortOrder,
            'updated_at': now
          };
          await store.insert('section_config', valueBucket);
        }
        hilog.info(0x0000, TAG, 'seedDefaults inserted %{public}d sections', SectionConfigDao.DEFAULT_SEEDS.length);
      });
  }

  /**
   * Delete a section config by key (for cleanup / reset).
   * @param sectionKey The section key to delete
   * @returns Promise<number> Number of deleted rows
   */
  static async deleteByKey(sectionKey: string): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('SectionConfigDao.deleteByKey',
      async (store: relationalStore.RdbStore): Promise<number> => {
        const predicates = new relationalStore.RdbPredicates('section_config');
        predicates.equalTo('section_key', sectionKey);
        const deletedRows = await store.delete(predicates);
        hilog.info(0x0000, TAG, 'Deleted section: key=%{public}s, affected=%{public}d',
          sectionKey, deletedRows);
        return deletedRows;
      });
  }
}
