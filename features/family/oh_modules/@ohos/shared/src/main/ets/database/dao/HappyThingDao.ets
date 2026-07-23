// <!-- agentID: DEV-009 -->
// File: HappyThingDao.ets
// Task: M04 DAO async migration - HappyThing CRUD operations
// Architecture: ARC-001 4.1 HappyThingDao API
// Migration: querySqlSync→querySql, insertSync→insert, deleteSync→delete, querySync→query
// All 5 sync APIs converted + searchByContent confirmed for M18

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseExecutor } from '../DatabaseExecutor';
import { HappyThing } from '../../data/HappyThing';

const TAG = 'HappyThingDao';

export class HappyThingDao {
  /**
   * Insert a happy thing record.
   * Sync→Async: insertSync → await store.insert()
   * @returns Promise<number> Inserted row ID
   */
  static async insert(happy: HappyThing): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('HappyThingDao.insert', async (store: relationalStore.RdbStore): Promise<number> => {
      const valueBucket: relationalStore.ValuesBucket = {
        'date': happy.date,
        'content': happy.content,
        'emoji_id': happy.emoji_id,
        'image': happy.image,
        'created_at': happy.created_at
      };
      const rowId = await store.insert('happy_thing', valueBucket);
      hilog.info(0x0000, TAG, 'HappyThing inserted: rowId=%{public}d', rowId);
      return rowId;
    });
  }

  /**
   * Delete a happy thing by ID.
   * Sync→Async: deleteSync → await store.delete()
   */
  static async delete(id: number): Promise<void> {
    return DatabaseExecutor.executeWrite<void>('HappyThingDao.delete', async (store: relationalStore.RdbStore): Promise<void> => {
      const predicates = new relationalStore.RdbPredicates('happy_thing');
      predicates.equalTo('id', id);
      await store.delete(predicates);
      hilog.info(0x0000, TAG, 'HappyThing deleted: id=%{public}d', id);
    });
  }

  /**
   * Query happy things by date.
   * Sync→Async: querySync → await store.query()
   * @returns Promise<HappyThing[]>
   */
  static async queryByDate(date: string): Promise<HappyThing[]> {
    return DatabaseExecutor.executeRead<HappyThing[]>('HappyThingDao.queryByDate',
      async (store: relationalStore.RdbStore): Promise<HappyThing[]> => {
        const predicates = new relationalStore.RdbPredicates('happy_thing');
        predicates.equalTo('date', date);
        predicates.orderByDesc('created_at');
        const resultSet = await store.query(predicates);
        const items: HappyThing[] = [];
        while (resultSet.goToNextRow()) {
          items.push(HappyThingDao.rowToHappyThing(resultSet));
        }
        resultSet.close();
        return items;
      });
  }

  /**
   * Search happy things by content keyword (used by M18 Search).
   * Sync→Async: querySqlSync → await store.querySql()
   * @returns Promise<HappyThing[]>
   */
  static async searchByContent(keyword: string): Promise<HappyThing[]> {
    return DatabaseExecutor.executeRead<HappyThing[]>('HappyThingDao.searchByContent',
      async (store: relationalStore.RdbStore): Promise<HappyThing[]> => {
        const sql = "SELECT * FROM happy_thing WHERE content LIKE ? ORDER BY date DESC";
        const resultSet = await store.querySql(sql, [`%${keyword}%`]);
        const items: HappyThing[] = [];
        while (resultSet.goToNextRow()) {
          items.push(HappyThingDao.rowToHappyThing(resultSet));
        }
        resultSet.close();
        return items;
      });
  }

  /**
   * Count happy things by emoji for a given date.
   * Sync→Async: querySqlSync → await store.querySql()
   * @returns Promise<number>
   */
  static async countByEmoji(date: string, emojiId: string): Promise<number> {
    return DatabaseExecutor.executeRead<number>('HappyThingDao.countByEmoji',
      async (store: relationalStore.RdbStore): Promise<number> => {
        const sql = "SELECT COUNT(*) as cnt FROM happy_thing WHERE date = ? AND emoji_id = ?";
        const resultSet = await store.querySql(sql, [date, emojiId]);
        if (resultSet.goToFirstRow()) {
          const count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
          resultSet.close();
          return count;
        }
        resultSet.close();
        return 0;
      });
  }

  private static rowToHappyThing(resultSet: relationalStore.ResultSet): HappyThing {
    const item = new HappyThing();
    item.id = resultSet.getLong(resultSet.getColumnIndex('id'));
    item.date = resultSet.getString(resultSet.getColumnIndex('date'));
    item.content = resultSet.getString(resultSet.getColumnIndex('content'));
    item.emoji_id = resultSet.getString(resultSet.getColumnIndex('emoji_id'));
    item.image = resultSet.isColumnNull(resultSet.getColumnIndex('image'))
      ? null : resultSet.getString(resultSet.getColumnIndex('image'));
    item.created_at = resultSet.getLong(resultSet.getColumnIndex('created_at'));
    return item;
  }
}
