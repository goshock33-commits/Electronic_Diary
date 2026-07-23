// <!-- agentID: DEV-008 -->
// File: PomodoroDao.ets
// Task: M08 Pomodoro DAO async migration - 4 sync APIs converted
// Architecture: ARC-001 4.1 PomodoroDao API
// Migration: insertSync→insert, querySqlSync×3→querySql
// Fields aligned to DDL: preset_type TEXT, duration_minutes INTEGER, actual_seconds, completed
// Reference template: B00 CheckInDao.ets

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseExecutor } from '../DatabaseExecutor';
import { PomodoroSession } from '../../data/PomodoroSession';

const TAG = 'PomodoroDao';

export class PomodoroDao {
  /**
   * Insert a completed or interrupted pomodoro session.
   * Sync→Async: insertSync → await store.insert()
   * @returns Promise<number> Inserted row ID
   */
  static async insert(session: PomodoroSession): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('PomodoroDao.insert', async (store: relationalStore.RdbStore): Promise<number> => {
      const valueBucket: relationalStore.ValuesBucket = {
        'date': session.date,
        'preset_type': session.preset_type,
        'duration_minutes': session.duration_minutes,
        'actual_seconds': session.actual_seconds,
        'completed': session.completed,
        'created_at': session.created_at,
        'ended_at': session.ended_at
      };
      const rowId = await store.insert('pomodoro_session', valueBucket);
      hilog.info(0x0000, TAG, 'Pomodoro session inserted: type=%{public}s, rowId=%{public}d',
        session.preset_type, rowId);
      return rowId;
    });
  }

  /**
   * Query pomodoro sessions by date range (for statistics).
   * Sync→Async: querySqlSync → await store.querySql()
   * @param start Start date "YYYY-MM-DD"
   * @param end End date "YYYY-MM-DD"
   * @returns Promise<PomodoroSession[]>
   */
  static async queryByDateRange(start: string, end: string): Promise<PomodoroSession[]> {
    return DatabaseExecutor.executeRead<PomodoroSession[]>('PomodoroDao.queryByDateRange',
      async (store: relationalStore.RdbStore): Promise<PomodoroSession[]> => {
        const sql = "SELECT * FROM pomodoro_session WHERE date >= ? AND date <= ? ORDER BY created_at DESC";
        const resultSet = await store.querySql(sql, [start, end]);
        const sessions: PomodoroSession[] = [];
        while (resultSet.goToNextRow()) {
          sessions.push(PomodoroDao.rowToSession(resultSet));
        }
        resultSet.close();
        return sessions;
      });
  }

  /**
   * Count completed pomodoro sessions for a date range (for statistics module).
   * Sync→Async: querySqlSync → await store.querySql()
   */
  static async countCompleted(start: string, end: string): Promise<number> {
    return DatabaseExecutor.executeRead<number>('PomodoroDao.countCompleted',
      async (store: relationalStore.RdbStore): Promise<number> => {
        const sql = "SELECT COUNT(*) as cnt FROM pomodoro_session WHERE date >= ? AND date <= ? AND completed = 1";
        const resultSet = await store.querySql(sql, [start, end]);
        if (resultSet.goToFirstRow()) {
          const count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
          resultSet.close();
          return count;
        }
        resultSet.close();
        return 0;
      });
  }

  /**
   * Sum total focused seconds for a date range (for statistics module).
   * Sync→Async: querySqlSync → await store.querySql()
   */
  static async sumFocusSeconds(start: string, end: string): Promise<number> {
    return DatabaseExecutor.executeRead<number>('PomodoroDao.sumFocusSeconds',
      async (store: relationalStore.RdbStore): Promise<number> => {
        const sql = "SELECT COALESCE(SUM(actual_seconds), 0) as total FROM pomodoro_session " +
          "WHERE date >= ? AND date <= ? AND preset_type = 'focus' AND completed = 1";
        const resultSet = await store.querySql(sql, [start, end]);
        if (resultSet.goToFirstRow()) {
          const total = resultSet.getLong(resultSet.getColumnIndex('total'));
          resultSet.close();
          return total;
        }
        resultSet.close();
        return 0;
      });
  }

  private static rowToSession(resultSet: relationalStore.ResultSet): PomodoroSession {
    const session = new PomodoroSession();
    session.id = resultSet.getLong(resultSet.getColumnIndex('id'));
    session.date = resultSet.getString(resultSet.getColumnIndex('date'));
    session.preset_type = resultSet.getString(resultSet.getColumnIndex('preset_type'));
    session.duration_minutes = resultSet.getLong(resultSet.getColumnIndex('duration_minutes'));
    session.actual_seconds = resultSet.isColumnNull(resultSet.getColumnIndex('actual_seconds'))
      ? null : resultSet.getLong(resultSet.getColumnIndex('actual_seconds'));
    session.completed = resultSet.getLong(resultSet.getColumnIndex('completed'));
    session.created_at = resultSet.getLong(resultSet.getColumnIndex('created_at'));
    session.ended_at = resultSet.isColumnNull(resultSet.getColumnIndex('ended_at'))
      ? null : resultSet.getLong(resultSet.getColumnIndex('ended_at'));
    return session;
  }
}
