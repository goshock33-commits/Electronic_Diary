// <!-- agentID: DEV-009 -->
// File: ExtraThingDao.ets
// Task: M05 DAO async migration - ExtraThing CRUD operations
// Architecture: ARC-001 4.1 ExtraThingDao API
// Migration: insertSync→insert, deleteSync→delete, querySync→query, querySqlSync→querySql
// All 4 sync APIs converted + searchByContent confirmed for M18

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseExecutor } from '../DatabaseExecutor';
import { ExtraThing } from '../../data/ExtraThing';

const TAG = 'ExtraThingDao';

export class ExtraThingDao {
  /**
   * Insert an extra thing record.
   * Sync→Async: insertSync → await store.insert()
   * @returns Promise<number> Inserted row ID
   */
  static async insert(extra: ExtraThing): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('ExtraThingDao.insert', async (store: relationalStore.RdbStore): Promise<number> => {
      const valueBucket: relationalStore.ValuesBucket = {
        'date': extra.date,
        'content': extra.content,
        'created_at': extra.created_at
      };
      const rowId = await store.insert('extra_thing', valueBucket);
      hilog.info(0x0000, TAG, 'ExtraThing inserted: rowId=%{public}d', rowId);
      return rowId;
    });
  }

  /**
   * Delete an extra thing by ID.
   * Sync→Async: deleteSync → await store.delete()
   */
  static async delete(id: number): Promise<void> {
    return DatabaseExecutor.executeWrite<void>('ExtraThingDao.delete', async (store: relationalStore.RdbStore): Promise<void> => {
      const predicates = new relationalStore.RdbPredicates('extra_thing');
      predicates.equalTo('id', id);
      await store.delete(predicates);
      hilog.info(0x0000, TAG, 'ExtraThing deleted: id=%{public}d', id);
    });
  }

  /**
   * Query extra things by date.
   * Sync→Async: querySync → await store.query()
   * @returns Promise<ExtraThing[]>
   */
  static async queryByDate(date: string): Promise<ExtraThing[]> {
    return DatabaseExecutor.executeRead<ExtraThing[]>('ExtraThingDao.queryByDate',
      async (store: relationalStore.RdbStore): Promise<ExtraThing[]> => {
        const predicates = new relationalStore.RdbPredicates('extra_thing');
        predicates.equalTo('date', date);
        predicates.orderByDesc('created_at');
        const resultSet = await store.query(predicates);
        const items: ExtraThing[] = [];
        while (resultSet.goToNextRow()) {
          items.push(ExtraThingDao.rowToExtraThing(resultSet));
        }
        resultSet.close();
        return items;
      });
  }

  /**
   * Search extra things by content keyword (used by M18 Search).
   * Sync→Async: querySqlSync → await store.querySql()
   * @returns Promise<ExtraThing[]>
   */
  static async searchByContent(keyword: string): Promise<ExtraThing[]> {
    return DatabaseExecutor.executeRead<ExtraThing[]>('ExtraThingDao.searchByContent',
      async (store: relationalStore.RdbStore): Promise<ExtraThing[]> => {
        const sql = "SELECT * FROM extra_thing WHERE content LIKE ? ORDER BY date DESC";
        const resultSet = await store.querySql(sql, [`%${keyword}%`]);
        const items: ExtraThing[] = [];
        while (resultSet.goToNextRow()) {
          items.push(ExtraThingDao.rowToExtraThing(resultSet));
        }
        resultSet.close();
        return items;
      });
  }

  private static rowToExtraThing(resultSet: relationalStore.ResultSet): ExtraThing {
    const item = new ExtraThing();
    item.id = resultSet.getLong(resultSet.getColumnIndex('id'));
    item.date = resultSet.getString(resultSet.getColumnIndex('date'));
    item.content = resultSet.getString(resultSet.getColumnIndex('content'));
    item.created_at = resultSet.getLong(resultSet.getColumnIndex('created_at'));
    return item;
  }
}
