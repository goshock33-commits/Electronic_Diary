// agentID: DEV-006
// <!-- agentID: DEV-004 (M09 统计 周/月分区聚合) -->
// fix: DEV-012 · T-M01 一天多篇：全面切表 diary → diary_entry（date 无 UNIQUE）；
//   queryByDate 语义改为「该日最新一篇」；新增 queryListByDate / queryById；delete(date) 删该日全部。
// File: DiaryDao.ets
// Task: M03 Diary DAO async migration - 6 sync APIs converted + images JSON handling
// Architecture: ARC-001 4.1 DiaryDao API
// Migration: insertSync→insert, querySync→query, querySqlSync→querySql, updateSync→update
// Template: CheckInDao.ets (B00)

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseExecutor } from '../DatabaseExecutor';
import { Diary } from '../../data/Diary';
import { DailyCount } from '../../data/DailyCount';

const TAG = 'DiaryDao';

export class DiaryDao {
  /**
   * Insert a new diary entry.
   * Sync→Async: insertSync → await store.insert()
   * images field: stored as JSON string in DB TEXT column (model handles string[]↔JSON via setImageList/getImageList)
   * @returns Promise<number> Inserted row ID
   */
  static async insert(diary: Diary): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('DiaryDao.insert', async (store: relationalStore.RdbStore): Promise<number> => {
      const valueBucket: relationalStore.ValuesBucket = {
        'date': diary.date,
        'content': diary.content,
        'images': diary.images,
        'title': diary.title,
        'mood': diary.mood,
        'created_at': diary.created_at,
        'updated_at': diary.updated_at
      };
      const rowId = await store.insert('diary_entry', valueBucket);
      hilog.info(0x0000, TAG, 'Diary inserted: date=%{public}s, rowId=%{public}d', diary.date, rowId);
      return rowId;
    });
  }

  /**
   * Query diary by exact date.
   * fix: DEV-012 · 一天多篇后语义改为「该日最新一篇或 null」（ORDER BY created_at DESC LIMIT 1），
   * 兼容既有单篇调用方（SearchViewModel / AIIntentHandler / init 等）。该日全部请用 queryListByDate。
   * @param date Date string "YYYY-MM-DD"
   * @returns Promise<Diary | null> Latest diary of that day, or null if none
   */
  static async queryByDate(date: string): Promise<Diary | null> {
    return DatabaseExecutor.executeRead<Diary | null>('DiaryDao.queryByDate', async (store: relationalStore.RdbStore): Promise<Diary | null> => {
      const sql = "SELECT * FROM diary_entry WHERE date = ? ORDER BY created_at DESC LIMIT 1";
      const resultSet = await store.querySql(sql, [date]);
      if (resultSet.goToFirstRow()) {
        const diary = DiaryDao.rowToDiary(resultSet);
        resultSet.close();
        return diary;
      }
      resultSet.close();
      return null;
    });
  }

  /**
   * fix: DEV-012 · Query ALL diary entries of a day (一天多篇), newest first.
   * @param date Date string "YYYY-MM-DD"
   * @returns Promise<Diary[]> All entries of that day, created_at DESC (empty array if none)
   */
  static async queryListByDate(date: string): Promise<Diary[]> {
    return DatabaseExecutor.executeRead<Diary[]>('DiaryDao.queryListByDate', async (store: relationalStore.RdbStore): Promise<Diary[]> => {
      const sql = "SELECT * FROM diary_entry WHERE date = ? ORDER BY created_at DESC";
      const resultSet = await store.querySql(sql, [date]);
      const diaries: Diary[] = [];
      while (resultSet.goToNextRow()) {
        diaries.push(DiaryDao.rowToDiary(resultSet));
      }
      resultSet.close();
      return diaries;
    });
  }

  /**
   * fix: DEV-012 · Query a single diary entry by row id (编辑/详情按篇定位).
   * @param id diary_entry row id
   * @returns Promise<Diary | null>
   */
  static async queryById(id: number): Promise<Diary | null> {
    return DatabaseExecutor.executeRead<Diary | null>('DiaryDao.queryById', async (store: relationalStore.RdbStore): Promise<Diary | null> => {
      const predicates = new relationalStore.RdbPredicates('diary_entry');
      predicates.equalTo('id', id);
      const resultSet = await store.query(predicates);
      if (resultSet.goToFirstRow()) {
        const diary = DiaryDao.rowToDiary(resultSet);
        resultSet.close();
        return diary;
      }
      resultSet.close();
      return null;
    });
  }

  /**
   * Query diaries by year and month.
   * Sync→Async: querySqlSync → await store.querySql()
   * @returns Promise<Diary[]> List of diary entries for that month
   */
  static async queryByMonth(year: number, month: number): Promise<Diary[]> {
    return DatabaseExecutor.executeRead<Diary[]>('DiaryDao.queryByMonth', async (store: relationalStore.RdbStore): Promise<Diary[]> => {
      const monthStr = String(month).padStart(2, '0');
      const datePrefix = `${year}-${monthStr}`;
      // Use LIKE for month matching since date is stored as "YYYY-MM-DD"
      // fix: DEV-012 · 切表 diary_entry；同日多篇按 created_at ASC 稳定次序
      const sql = "SELECT * FROM diary_entry WHERE date LIKE ? ORDER BY date ASC, created_at ASC";
      const resultSet = await store.querySql(sql, [`${datePrefix}%`]);
      const diaries: Diary[] = [];
      while (resultSet.goToNextRow()) {
        diaries.push(DiaryDao.rowToDiary(resultSet));
      }
      resultSet.close();
      return diaries;
    });
  }

  /**
   * Full-text search diary content by keyword.
   * Falls back to LIKE if FTS5 is unavailable.
   * Sync→Async: querySqlSync → await store.querySql()
   * @param keyword Search keyword
   * @returns Promise<Diary[]> Matching diary entries
   */
  static async search(keyword: string): Promise<Diary[]> {
    return DatabaseExecutor.executeRead<Diary[]>('DiaryDao.search', async (store: relationalStore.RdbStore): Promise<Diary[]> => {
      // fix: DEV-012 · 切表 diary_entry；同日多篇最新在前
      const sql = "SELECT * FROM diary_entry WHERE content LIKE ? ORDER BY date DESC, created_at DESC";
      const resultSet = await store.querySql(sql, [`%${keyword}%`]);
      const diaries: Diary[] = [];
      while (resultSet.goToNextRow()) {
        diaries.push(DiaryDao.rowToDiary(resultSet));
      }
      resultSet.close();
      return diaries;
    });
  }

  /**
   * Update an existing diary entry.
   * Sync→Async: updateSync → await store.update()
   * images field: stored as JSON string in DB TEXT column (model handles string[]↔JSON via setImageList/getImageList)
   * @param diary Diary object with id set
   */
  static async update(diary: Diary): Promise<void> {
    return DatabaseExecutor.executeWrite<void>('DiaryDao.update', async (store: relationalStore.RdbStore): Promise<void> => {
      diary.updated_at = Date.now();
      const valueBucket: relationalStore.ValuesBucket = {
        'content': diary.content,
        'images': diary.images,
        'title': diary.title,
        'mood': diary.mood,
        'updated_at': diary.updated_at
      };
      const predicates = new relationalStore.RdbPredicates('diary_entry');
      predicates.equalTo('id', diary.id);
      const affectedRows = await store.update(valueBucket, predicates);
      hilog.info(0x0000, TAG, 'Diary updated: id=%{public}d, affected=%{public}d', diary.id, affectedRows);
    });
  }

  /**
   * Get all dates that have diary entries (for calendar marking).
   * Sync→Async: querySqlSync → await store.querySql()
   * @returns Promise<string[]> Array of date strings
   */
  static async queryDatesWithDiary(year: number, month: number): Promise<string[]> {
    return DatabaseExecutor.executeRead<string[]>('DiaryDao.queryDatesWithDiary', async (store: relationalStore.RdbStore): Promise<string[]> => {
      const monthStr = String(month).padStart(2, '0');
      const datePrefix = `${year}-${monthStr}`;
      // fix: DEV-012 · 切表 diary_entry + DISTINCT 去重（一天多篇日历只标一次，语义不变：有篇即标记）
      const sql = "SELECT DISTINCT date FROM diary_entry WHERE date LIKE ? ORDER BY date ASC";
      const resultSet = await store.querySql(sql, [`${datePrefix}%`]);
      const dates: string[] = [];
      while (resultSet.goToNextRow()) {
        dates.push(resultSet.getString(resultSet.getColumnIndex('date')));
      }
      resultSet.close();
      return dates;
    });
  }

  /**
   * Query all diaries in descending date order (diary carousel "all diaries").
   * DEV-DB gap#3 (ARC-001 §4). Uses querySql + rowToDiary.
   * @returns Promise<Diary[]>
   */
  static async queryAll(): Promise<Diary[]> {
    return DatabaseExecutor.executeRead<Diary[]>('DiaryDao.queryAll', async (store: relationalStore.RdbStore): Promise<Diary[]> => {
      // fix: DEV-012 · 切表 diary_entry；同日多篇最新在前
      const sql = "SELECT * FROM diary_entry ORDER BY date DESC, created_at DESC";
      const resultSet = await store.querySql(sql);
      const diaries: Diary[] = [];
      while (resultSet.goToNextRow()) {
        diaries.push(DiaryDao.rowToDiary(resultSet));
      }
      resultSet.close();
      return diaries;
    });
  }

  /**
   * Delete diary entries by date.
   * fix: DEV-012 · 一天多篇后语义为「删除该日全部篇目」（equalTo(date) 命中多行全删）。
   * 当前无调用方（核实于 2026-07-17）；按篇删除请用 deleteById。
   * @param date Date string "YYYY-MM-DD"
   * @returns Promise<boolean> true if at least one row was deleted
   */
  static async delete(date: string): Promise<boolean> {
    return DatabaseExecutor.executeWrite<boolean>('DiaryDao.delete', async (store: relationalStore.RdbStore): Promise<boolean> => {
      const predicates = new relationalStore.RdbPredicates('diary_entry');
      predicates.equalTo('date', date);
      const deletedRows = await store.delete(predicates);
      hilog.info(0x0000, TAG, 'Diary deleted: date=%{public}s, affected=%{public}d', date, deletedRows);
      return deletedRows > 0;
    });
  }

  /**
   * fix: HUI-FRONTEND-1 · Delete a diary entry by id（日记轮播长按删除契约 deleteDiary(id)）。
   * @param id Diary row id
   * @returns Promise<boolean> true if a row was deleted
   */
  static async deleteById(id: number): Promise<boolean> {
    return DatabaseExecutor.executeWrite<boolean>('DiaryDao.deleteById', async (store: relationalStore.RdbStore): Promise<boolean> => {
      const predicates = new relationalStore.RdbPredicates('diary_entry');
      predicates.equalTo('id', id);
      const deletedRows = await store.delete(predicates);
      hilog.info(0x0000, TAG, 'Diary deleted: id=%{public}d, affected=%{public}d', id, deletedRows);
      return deletedRows > 0;
    });
  }

  /**
   * M09: Count diary entries within a date range (inclusive) for week/month statistics.
   * date stored "YYYY-MM-DD" so lexical >=/<= == chronological; a week may span two months.
   * @param start Start date "YYYY-MM-DD" (inclusive)
   * @param end End date "YYYY-MM-DD" (inclusive)
   * @returns Promise<number> Diary count in range (0 if none)
   */
  static async countByDateRange(start: string, end: string): Promise<DailyCount[]> {
    return DatabaseExecutor.executeRead<DailyCount[]>('DiaryDao.countByDateRange', async (store: relationalStore.RdbStore): Promise<DailyCount[]> => {
      // fix: HUI-FRONTEND-1 · 改为 GROUP BY date 逐日计数（StatisticsViewModel.getDailySeries 契约）
      // fix: DEV-012 · 切表 diary_entry（GROUP BY date 天然兼容一天多篇：同日多篇计入当日 cnt）
      const sql = "SELECT date, COUNT(*) as cnt FROM diary_entry WHERE date >= ? AND date <= ? GROUP BY date ORDER BY date ASC";
      const resultSet = await store.querySql(sql, [start, end]);
      const counts: DailyCount[] = [];
      while (resultSet.goToNextRow()) {
        const item: DailyCount = {
          date: resultSet.getString(resultSet.getColumnIndex('date')),
          count: resultSet.getLong(resultSet.getColumnIndex('cnt'))
        };
        counts.push(item);
      }
      resultSet.close();
      return counts;
    });
  }

  /**
   * fix: HUI-FRONTEND-1 · countAll 别名（StatisticsViewModel.getProfileTotals 契约名）
   */
  static async countAll(): Promise<number> {
    return DiaryDao.count();
  }

  /**
   * DEV-WIRE-PROFILE: Count all diary entries (for "我的" profile card diaryCount).
   * All-time count, no date filter. Follows countCompleted template (executeRead + COUNT(*)).
   * SQL: SELECT COUNT(*) as cnt FROM diary_entry
   * @returns Promise<number> Total diary row count (0 if empty)
   */
  static async count(): Promise<number> {
    return DatabaseExecutor.executeRead<number>('DiaryDao.count', async (store: relationalStore.RdbStore): Promise<number> => {
      const sql = "SELECT COUNT(*) as cnt FROM diary_entry";
      const resultSet = await store.querySql(sql);
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
   * Convert a result set row to Diary object.
   * images field: reads as JSON string from DB TEXT column;
   * model's getImageList() handles JSON.parse for string[] access.
   * title/mood (v2): nullable columns for legacy rows → isColumnNull fallback to ''.
   */
  private static rowToDiary(resultSet: relationalStore.ResultSet): Diary {
    const diary = new Diary();
    diary.id = resultSet.getLong(resultSet.getColumnIndex('id'));
    diary.date = resultSet.getString(resultSet.getColumnIndex('date'));
    diary.content = resultSet.getString(resultSet.getColumnIndex('content'));
    diary.images = resultSet.getString(resultSet.getColumnIndex('images'));
    const titleIndex = resultSet.getColumnIndex('title');
    diary.title = resultSet.isColumnNull(titleIndex) ? '' : resultSet.getString(titleIndex);
    const moodIndex = resultSet.getColumnIndex('mood');
    diary.mood = resultSet.isColumnNull(moodIndex) ? '' : resultSet.getString(moodIndex);
    diary.created_at = resultSet.getLong(resultSet.getColumnIndex('created_at'));
    diary.updated_at = resultSet.getLong(resultSet.getColumnIndex('updated_at'));
    return diary;
  }
}
