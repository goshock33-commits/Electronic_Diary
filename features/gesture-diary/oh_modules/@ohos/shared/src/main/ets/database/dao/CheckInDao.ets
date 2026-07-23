// <!-- agentID: DEV-001 -->
// File: CheckInDao.ets
// Task: B00 DAO async migration template - CheckIn operations
// Architecture: ARC-001 4.1 CheckInDao API
// Migration: querySqlSync→querySql, insertSync→insert, querySync→query
// All 4 sync APIs converted + deleteByDate added (R0-6)

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseExecutor } from '../DatabaseExecutor';
import { CheckIn } from '../../data/CheckIn';

const TAG = 'CheckInDao';

export class CheckInDao {
  /**
   * Insert a check-in record for the given date.
   * Sync→Async: insertSync → await store.insert()
   * @returns Promise<number> Inserted row ID
   */
  static async insert(checkIn: CheckIn): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('CheckInDao.insert', async (store: relationalStore.RdbStore): Promise<number> => {
      const valueBucket: relationalStore.ValuesBucket = {
        'date': checkIn.date,
        'created_at': checkIn.created_at
      };
      const rowId = await store.insert('check_in', valueBucket);
      hilog.info(0x0000, TAG, 'CheckIn inserted: date=%{public}s, rowId=%{public}d', checkIn.date, rowId);
      return rowId;
    });
  }

  /**
   * Check if a date has been checked in.
   * Sync→Async: querySync → await store.query()
   * @param date Date string "YYYY-MM-DD"
   * @returns Promise<boolean>
   */
  static async exists(date: string): Promise<boolean> {
    return DatabaseExecutor.executeRead<boolean>('CheckInDao.exists', async (store: relationalStore.RdbStore): Promise<boolean> => {
      const predicates = new relationalStore.RdbPredicates('check_in');
      predicates.equalTo('date', date);
      const resultSet = await store.query(predicates);
      const found = resultSet.goToFirstRow();
      resultSet.close();
      return found;
    });
  }

  /**
   * Calculate continuous check-in streak ending at the given date.
   * T-D09: Rewritten to use queryByDateRange (proven working by StatisticsPage).
   * Original querySql(sql, []) had ArkTS strict-mode type mismatch with empty array.
   */
  static async queryStreak(date: string): Promise<number> {
    return DatabaseExecutor.executeRead<number>('CheckInDao.queryStreak', async (store: relationalStore.RdbStore): Promise<number> => {
      const ref = new Date(date);
      const start = CheckInDao.formatLocalDate(new Date(ref.getTime() - 90 * 86400000));
      const allRecords = await CheckInDao.queryByDateRange(start, date);
      if (allRecords.length === 0) {
        return 0;
      }
      const checkSet = new Set<string>();
      for (const r of allRecords) {
        checkSet.add(r.date);
      }
      // fix: MAIN-001 · 恢复 DEV-003 口径——计数起点 = 最近一个 <= referenceDate 的打卡日，
      // 而非 referenceDate 本身：今天未打卡时展示上一轮连续天数（不归 0）；今天已打卡与原逻辑一致。
      // queryByDateRange 返回 ASC，最后一条即最近打卡日。
      const latest: string = allRecords[allRecords.length - 1].date;
      let streak = 0;
      let cur = new Date(latest);
      while (true) {
        const formatted = CheckInDao.formatLocalDate(cur);
        if (checkSet.has(formatted)) {
          streak++;
          cur = new Date(cur.getTime() - 86400000);
        } else {
          break;
        }
      }
      return streak;
    });
  }

  /**
   * Query all check-in records for a month (for statistics).
   * Sync→Async: querySqlSync → await store.querySql()
   * @returns Promise<CheckIn[]>
   */
  static async queryByMonth(year: number, month: number): Promise<CheckIn[]> {
    return DatabaseExecutor.executeRead<CheckIn[]>('CheckInDao.queryByMonth', async (store: relationalStore.RdbStore): Promise<CheckIn[]> => {
      const monthStr = String(month).padStart(2, '0');
      const datePrefix = `${year}-${monthStr}`;
      const sql = "SELECT * FROM check_in WHERE date LIKE ? ORDER BY date ASC";
      const resultSet = await store.querySql(sql, [`${datePrefix}%`]);
      const records: CheckIn[] = [];
      while (resultSet.goToNextRow()) {
        const c = new CheckIn();
        c.id = resultSet.getLong(resultSet.getColumnIndex('id'));
        c.date = resultSet.getString(resultSet.getColumnIndex('date'));
        c.created_at = resultSet.getLong(resultSet.getColumnIndex('created_at'));
        records.push(c);
      }
      resultSet.close();
      return records;
    });
  }

  /**
   * agentID: DEV-004 — Query check-in records by date range (statistics daily series).
   * Predicate pattern mirrors PomodoroDao.queryByDateRange (date >= ? AND date <= ?, TEXT compare
   * safe because date column is zero-padded "YYYY-MM-DD").
   * @param start Start date "YYYY-MM-DD" (inclusive)
   * @param end End date "YYYY-MM-DD" (inclusive)
   * @returns Promise<CheckIn[]> ordered by date ASC
   */
  static async queryByDateRange(start: string, end: string): Promise<CheckIn[]> {
    return DatabaseExecutor.executeRead<CheckIn[]>('CheckInDao.queryByDateRange', async (store: relationalStore.RdbStore): Promise<CheckIn[]> => {
      const sql = "SELECT * FROM check_in WHERE date >= ? AND date <= ? ORDER BY date ASC";
      const resultSet = await store.querySql(sql, [start, end]);
      const records: CheckIn[] = [];
      while (resultSet.goToNextRow()) {
        const c = new CheckIn();
        c.id = resultSet.getLong(resultSet.getColumnIndex('id'));
        c.date = resultSet.getString(resultSet.getColumnIndex('date'));
        c.created_at = resultSet.getLong(resultSet.getColumnIndex('created_at'));
        records.push(c);
      }
      resultSet.close();
      return records;
    });
  }

  /**
   * Delete a check-in record by date (for undo functionality, M01 R0-6).
   * New method added in B00 migration.
   * @param date Date string "YYYY-MM-DD"
   * @returns Promise<number> Number of deleted rows (1 if found, 0 if not)
   */
  static async deleteByDate(date: string): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('CheckInDao.deleteByDate', async (store: relationalStore.RdbStore): Promise<number> => {
      const predicates = new relationalStore.RdbPredicates('check_in');
      predicates.equalTo('date', date);
      const deletedRows = await store.delete(predicates);
      hilog.info(0x0000, TAG, 'CheckIn deleted: date=%{public}s, affected=%{public}d', date, deletedRows);
      return deletedRows;
    });
  }

  /**
   * Format a Date object to "YYYY-MM-DD" local date string
   */
  private static formatLocalDate(date: Date): string {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
}
