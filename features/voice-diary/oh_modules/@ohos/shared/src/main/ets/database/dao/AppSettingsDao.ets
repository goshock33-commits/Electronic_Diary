// <!-- agentID: DEV-007 -->
// File: AppSettingsDao.ets
// Task: M11 DAO async migration - AppSettings key-value operations
// Architecture: ARC-001 5.2 table 10 / 4.1 API
// Migration: querySync→query, updateSync→update, insertSync→insert, deleteSync→delete, querySqlSync→querySql
// All 9 sync APIs converted

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseExecutor } from '../DatabaseExecutor';

const TAG = 'AppSettingsDao';

export class AppSettingsDao {
  /**
   * Get a setting value by key.
   * Sync→Async: querySync → await store.query()
   * @returns Promise<string | null> The value or null if not found
   */
  static async get(key: string): Promise<string | null> {
    return DatabaseExecutor.executeRead<string | null>('AppSettingsDao.get',
      async (store: relationalStore.RdbStore): Promise<string | null> => {
        const predicates = new relationalStore.RdbPredicates('app_settings');
        predicates.equalTo('key', key);
        const resultSet = await store.query(predicates);
        if (resultSet.goToFirstRow()) {
          const value = resultSet.getString(resultSet.getColumnIndex('value'));
          resultSet.close();
          return value;
        }
        resultSet.close();
        return null;
      });
  }

  /**
   * Set a setting value. Inserts if key doesn't exist, updates if it does.
   * Sync→Async: querySync → await store.query(), updateSync → await store.update(), insertSync → await store.insert()
   */
  static async set(key: string, value: string): Promise<void> {
    return DatabaseExecutor.executeWrite<void>('AppSettingsDao.set',
      async (store: relationalStore.RdbStore): Promise<void> => {
        const now = Date.now();
        // Check if key exists
        const predicates = new relationalStore.RdbPredicates('app_settings');
        predicates.equalTo('key', key);
        const resultSet = await store.query(predicates);
        if (resultSet.goToFirstRow()) {
          resultSet.close();
          // Update existing
          const valueBucket: relationalStore.ValuesBucket = {
            'value': value,
            'updated_at': now
          };
          await store.update(valueBucket, predicates);
        } else {
          resultSet.close();
          // Insert new
          const valueBucket: relationalStore.ValuesBucket = {
            'key': key,
            'value': value,
            'updated_at': now
          };
          await store.insert('app_settings', valueBucket);
        }
      });
  }

  /**
   * Delete a setting by key.
   * Sync→Async: deleteSync → await store.delete()
   */
  static async delete(key: string): Promise<void> {
    return DatabaseExecutor.executeWrite<void>('AppSettingsDao.delete',
      async (store: relationalStore.RdbStore): Promise<void> => {
        const predicates = new relationalStore.RdbPredicates('app_settings');
        predicates.equalTo('key', key);
        await store.delete(predicates);
      });
  }

  /**
   * Get all settings as a Map.
   * Sync→Async: querySqlSync → await store.querySql()
   */
  static async getAll(): Promise<Map<string, string>> {
    return DatabaseExecutor.executeRead<Map<string, string>>('AppSettingsDao.getAll',
      async (store: relationalStore.RdbStore): Promise<Map<string, string>> => {
        const sql = "SELECT * FROM app_settings ORDER BY key ASC";
        const resultSet = await store.querySql(sql, []);
        const map = new Map<string, string>();
        while (resultSet.goToNextRow()) {
          const key = resultSet.getString(resultSet.getColumnIndex('key'));
          const value = resultSet.getString(resultSet.getColumnIndex('value'));
          map.set(key, value);
        }
        resultSet.close();
        return map;
      });
  }

  /**
   * Get a typed setting value (parsed from JSON).
   */
  static async getTyped<T>(key: string): Promise<T | null> {
    const rawValue = await AppSettingsDao.get(key);
    if (!rawValue) {
      return null;
    }
    try {
      return JSON.parse(rawValue) as T;
    } catch (_e) {
      return null;
    }
  }

  /**
   * Set a typed setting value (serialized to JSON).
   */
  static async setTyped(key: string, value: Object): Promise<void> {
    const jsonStr = JSON.stringify(value);
    await AppSettingsDao.set(key, jsonStr);
  }

  /**
   * Batch set multiple settings (transactional).
   * Sync→Async: querySync → await store.query(), updateSync → await store.update(), insertSync → await store.insert()
   * Transaction boundary handled by executeTransaction — no manual beginTransaction/commit/rollBack needed.
   */
  static async batchSet(entries: Map<string, string>): Promise<void> {
    return DatabaseExecutor.executeTransaction<void>('AppSettingsDao.batchSet',
      async (store: relationalStore.RdbStore): Promise<void> => {
        const now = Date.now();
        // ArkTS arkts-no-destruct-decls: 禁止解构声明，改用元组索引逐个取值
        for (const entry of entries) {
          const key: string = entry[0];
          const value: string = entry[1];
          const predicates = new relationalStore.RdbPredicates('app_settings');
          predicates.equalTo('key', key);
          const resultSet = await store.query(predicates);
          const exists = resultSet.goToFirstRow();
          resultSet.close();
          const valueBucket: relationalStore.ValuesBucket = {
            'value': value,
            'updated_at': now
          };
          if (exists) {
            await store.update(valueBucket, predicates);
          } else {
            const insertBucket: relationalStore.ValuesBucket = {
              'key': key,
              'value': value,
              'updated_at': now
            };
            await store.insert('app_settings', insertBucket);
          }
        }
        hilog.info(0x0000, TAG, 'Batch set %{public}d settings', entries.size);
      });
  }
}
