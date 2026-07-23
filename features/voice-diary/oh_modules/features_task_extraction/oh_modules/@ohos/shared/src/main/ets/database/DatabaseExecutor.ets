// <!-- agentID: DEV-001 -->
// File: DatabaseExecutor.ets
// Task: B00 Database layer - Thin passthrough (no TaskPool, R0-1 fix)
// Architecture: 方案A = 去 TaskPool + DAO 异步化
// RelationalStore 原生 Promise API 由系统线程池执行，天然不阻塞 UI
// External signature Promise<T> unchanged → ViewModel 调用方零改动

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseHelper } from './DatabaseHelper';

const TAG = 'DatabaseExecutor';

/**
 * DatabaseExecutor - Thin passthrough for database operations.
 * Removed TaskPool (R0-1). RelationalStore native Promise APIs
 * execute on system thread pool, naturally non-blocking UI.
 *
 * Key changes from old version:
 * - executeRead/executeWrite: direct await callback (no cross-thread RdbStore passing)
 * - executeTransaction/executeInTransaction: beginTransaction/commit/rollBack with error safety
 * - Callback signatures: (store: RdbStore) => Promise<T> to support async DAO APIs
 */
export class DatabaseExecutor {
  private static dbHelper: DatabaseHelper = DatabaseHelper.getInstance();

  /**
   * Execute a database read operation directly (no TaskPool).
   * RelationalStore.query/querySql are native Promises on system thread pool.
   * @param taskName Descriptive name for logging
   * @param readFn Async callback that receives RdbStore and returns data
   * @returns Promise<T> with the query result
   */
  static async executeRead<T>(taskName: string, readFn: (store: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    hilog.debug(0x0000, TAG, 'executeRead: %{public}s', taskName);
    try {
      // DEV-003：等待 DB 初始化完成（消除启动竞态：页面首帧 DAO 查询早于 getRdbStore 完成）
      await DatabaseExecutor.dbHelper.whenReady();
      const store = DatabaseExecutor.dbHelper.getStore();
      return await readFn(store);
    } catch (err) {
      hilog.error(0x0000, TAG, 'executeRead failed [%{public}s]: %{public}s',
        taskName, JSON.stringify(err));
      throw new Error(`executeRead '${taskName}' failed: ${(err as Error).message}`);
    }
  }

  /**
   * Execute a database write operation directly (no TaskPool).
   * RelationalStore.insert/update/delete are native Promises on system thread pool.
   * @param taskName Descriptive name for logging
   * @param writeFn Async callback that receives RdbStore and performs write operations
   * @returns Promise<T> with the write result (e.g., inserted row ID, affected count)
   */
  static async executeWrite<T>(taskName: string, writeFn: (store: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    hilog.debug(0x0000, TAG, 'executeWrite: %{public}s', taskName);
    try {
      // DEV-003：等待 DB 初始化完成（消除启动竞态）
      await DatabaseExecutor.dbHelper.whenReady();
      const store = DatabaseExecutor.dbHelper.getStore();
      return await writeFn(store);
    } catch (err) {
      hilog.error(0x0000, TAG, 'executeWrite failed [%{public}s]: %{public}s',
        taskName, JSON.stringify(err));
      throw new Error(`executeWrite '${taskName}' failed: ${(err as Error).message}`);
    }
  }

  /**
   * Execute operations within a transaction with automatic rollback on failure.
   * Backward-compatible replacement for the old TaskPool-based executeTransaction.
   * @param taskName Descriptive name for logging
   * @param txFn Async callback that receives RdbStore for transaction operations
   * @returns Promise<T> with the transaction result
   */
  static async executeTransaction<T>(taskName: string, txFn: (store: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    hilog.debug(0x0000, TAG, 'executeTransaction: %{public}s', taskName);
    // DEV-003：等待 DB 初始化完成（消除启动竞态）
    await DatabaseExecutor.dbHelper.whenReady();
    const store = DatabaseExecutor.dbHelper.getStore();
    try {
      store.beginTransaction();
      const result = await txFn(store);
      store.commit();
      hilog.debug(0x0000, TAG, 'executeTransaction committed: %{public}s', taskName);
      return result;
    } catch (err) {
      store.rollBack();
      hilog.error(0x0000, TAG, 'executeTransaction rolled back [%{public}s]: %{public}s',
        taskName, JSON.stringify(err));
      throw new Error(`executeTransaction '${taskName}' failed: ${(err as Error).message}`);
    }
  }

  /**
   * Execute operations within a transaction with automatic rollback on failure.
   * Preferred over executeTransaction for clarity. Multi-step write operations
   * that must be atomic should use this method.
   * @param taskName Descriptive name for logging
   * @param txFn Async callback that receives RdbStore for transaction operations
   * @returns Promise<T> with the transaction result
   */
  static async executeInTransaction<T>(taskName: string, txFn: (store: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    hilog.debug(0x0000, TAG, 'executeInTransaction: %{public}s', taskName);
    // DEV-003：等待 DB 初始化完成（消除启动竞态）
    await DatabaseExecutor.dbHelper.whenReady();
    const store = DatabaseExecutor.dbHelper.getStore();
    try {
      store.beginTransaction();
      const result = await txFn(store);
      store.commit();
      hilog.debug(0x0000, TAG, 'executeInTransaction committed: %{public}s', taskName);
      return result;
    } catch (err) {
      store.rollBack();
      hilog.error(0x0000, TAG, 'executeInTransaction rolled back [%{public}s]: %{public}s',
        taskName, JSON.stringify(err));
      throw new Error(`executeInTransaction '${taskName}' failed: ${(err as Error).message}`);
    }
  }
}
