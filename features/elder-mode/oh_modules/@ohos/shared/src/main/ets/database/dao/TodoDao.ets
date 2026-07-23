// <!-- agentID: DEV-005 -->
// fix: DEV-013 · 待办提醒增强：insert/update/rowToTodoItem 覆盖 due_date/due_time/location/
//   custom_tags/remind_at/reminder_id 6 新列；新增 updateReminderRef（调度成功写回提醒引用）
//   与 queryPendingReminders（未完成+提醒未过期，冷启动恢复调度用）。
// File: TodoDao.ets
// Task: M02 DAO async migration - TodoItem CRUD + toggle completion
// Architecture: ARC-001 4.1 TodoDao API
// Migration: insertSync→insert, updateSync→update, deleteSync→delete,
//   querySync→query, querySqlSync→querySql (9 sync APIs converted)
// Reference: B00 CheckInDao async migration template
// Skill Ref: frontend-design / ui-ux-pro-max

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseExecutor } from '../DatabaseExecutor';
import { TodoItem } from '../../data/TodoItem';
import { DailyCount } from '../../data/DailyCount';

const TAG = 'TodoDao';

export class TodoDao {
  /**
   * Insert a new todo item.
   * Sync→Async: insertSync → await store.insert()
   * @returns Promise<number> Inserted row ID
   */
  static async insert(todo: TodoItem): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('TodoDao.insert', async (store: relationalStore.RdbStore): Promise<number> => {
      const valueBucket: relationalStore.ValuesBucket = {
        'date': todo.date,
        'type': todo.type,
        'title': todo.title,
        'completed': todo.completed,
        'sort_order': todo.sort_order,
        'source_task_id': todo.source_task_id,
        'category': todo.category,
        'due_date': todo.due_date,
        'due_time': todo.due_time,
        'location': todo.location,
        'custom_tags': todo.custom_tags,
        'remind_at': todo.remind_at,
        'reminder_id': todo.reminder_id,
        'created_at': todo.created_at,
        'updated_at': todo.updated_at
      };
      const rowId = await store.insert('todo', valueBucket);
      hilog.info(0x0000, TAG, 'Todo inserted: title=%{public}s, rowId=%{public}d', todo.title, rowId);
      return rowId;
    });
  }

  /**
   * Update an existing todo item.
   * Sync→Async: updateSync → await store.update()
   */
  static async update(todo: TodoItem): Promise<void> {
    return DatabaseExecutor.executeWrite<void>('TodoDao.update', async (store: relationalStore.RdbStore): Promise<void> => {
      todo.updated_at = Date.now();
      const valueBucket: relationalStore.ValuesBucket = {
        'title': todo.title,
        'type': todo.type,
        'date': todo.date,
        'completed': todo.completed,
        'sort_order': todo.sort_order,
        'source_task_id': todo.source_task_id,
        'category': todo.category,
        'due_date': todo.due_date,
        'due_time': todo.due_time,
        'location': todo.location,
        'custom_tags': todo.custom_tags,
        'remind_at': todo.remind_at,
        'reminder_id': todo.reminder_id,
        'updated_at': todo.updated_at
      };
      const predicates = new relationalStore.RdbPredicates('todo');
      predicates.equalTo('id', todo.id);
      await store.update(valueBucket, predicates);
    });
  }

  /**
   * Delete a todo item by ID.
   * Sync→Async: deleteSync → await store.delete()
   */
  static async delete(id: number): Promise<void> {
    return DatabaseExecutor.executeWrite<void>('TodoDao.delete', async (store: relationalStore.RdbStore): Promise<void> => {
      const predicates = new relationalStore.RdbPredicates('todo');
      predicates.equalTo('id', id);
      const affected = await store.delete(predicates);
      hilog.info(0x0000, TAG, 'Todo deleted: id=%{public}d, affected=%{public}d', id, affected);
    });
  }

  /**
   * Query todos by date and type.
   * Sync→Async: querySync → await store.query()
   * @returns Promise<TodoItem[]> Sorted by sort_order ascending
   */
  static async queryByDateAndType(date: string, type: string): Promise<TodoItem[]> {
    return DatabaseExecutor.executeRead<TodoItem[]>('TodoDao.queryByDateAndType', async (store: relationalStore.RdbStore): Promise<TodoItem[]> => {
      const predicates = new relationalStore.RdbPredicates('todo');
      predicates.equalTo('date', date);
      predicates.equalTo('type', type);
      predicates.orderByAsc('sort_order');
      const resultSet = await store.query(predicates);
      const todos: TodoItem[] = [];
      while (resultSet.goToNextRow()) {
        todos.push(TodoDao.rowToTodoItem(resultSet));
      }
      resultSet.close();
      return todos;
    });
  }

  /**
   * DEV-003 ②：Query all todos of a date regardless of type (for search-by-date).
   * @returns Promise<TodoItem[]> Sorted by type then sort_order
   */
  static async queryByDate(date: string): Promise<TodoItem[]> {
    return DatabaseExecutor.executeRead<TodoItem[]>('TodoDao.queryByDate', async (store: relationalStore.RdbStore): Promise<TodoItem[]> => {
      const predicates = new relationalStore.RdbPredicates('todo');
      predicates.equalTo('date', date);
      predicates.orderByAsc('type');
      predicates.orderByAsc('sort_order');
      const resultSet = await store.query(predicates);
      const todos: TodoItem[] = [];
      while (resultSet.goToNextRow()) {
        todos.push(TodoDao.rowToTodoItem(resultSet));
      }
      resultSet.close();
      return todos;
    });
  }

  /**
   * Toggle the completion status of a todo item.
   * Sync→Async: querySync → await store.query(), updateSync → await store.update()
   * @param id Todo ID
   */
  static async toggleComplete(id: number): Promise<void> {
    return DatabaseExecutor.executeWrite<void>('TodoDao.toggleComplete', async (store: relationalStore.RdbStore): Promise<void> => {
      const predicates = new relationalStore.RdbPredicates('todo');
      predicates.equalTo('id', id);
      const resultSet = await store.query(predicates);
      if (resultSet.goToFirstRow()) {
        const currentCompleted = resultSet.getLong(resultSet.getColumnIndex('completed'));
        const newCompleted = currentCompleted === 1 ? 0 : 1;
        resultSet.close();
        const valueBucket: relationalStore.ValuesBucket = {
          'completed': newCompleted,
          'updated_at': Date.now()
        };
        await store.update(valueBucket, predicates);
        hilog.info(0x0000, TAG, 'Todo toggled: id=%{public}d, completed=%{public}d', id, newCompleted);
      } else {
        resultSet.close();
      }
    });
  }

  /**
   * Query todos with keyword search in title (for M18 search module).
   * Sync→Async: querySqlSync → await store.querySql()
   * Signature: searchByTitle(keyword: string): Promise<TodoItem[]>
   * Confirmed for M18 cross-source search integration.
   */
  static async searchByTitle(keyword: string): Promise<TodoItem[]> {
    return DatabaseExecutor.executeRead<TodoItem[]>('TodoDao.searchByTitle', async (store: relationalStore.RdbStore): Promise<TodoItem[]> => {
      const sql = "SELECT * FROM todo WHERE title LIKE ? ORDER BY date DESC, sort_order ASC";
      const resultSet = await store.querySql(sql, [`%${keyword}%`]);
      const todos: TodoItem[] = [];
      while (resultSet.goToNextRow()) {
        todos.push(TodoDao.rowToTodoItem(resultSet));
      }
      resultSet.close();
      return todos;
    });
  }

  /**
   * Query todos by extracted task source (for convertToTodo).
   * Sync→Async: querySync → await store.query()
   */
  static async queryBySourceTaskId(sourceTaskId: number): Promise<TodoItem | null> {
    return DatabaseExecutor.executeRead<TodoItem | null>('TodoDao.queryBySourceTaskId', async (store: relationalStore.RdbStore): Promise<TodoItem | null> => {
      const predicates = new relationalStore.RdbPredicates('todo');
      predicates.equalTo('source_task_id', sourceTaskId);
      const resultSet = await store.query(predicates);
      if (resultSet.goToFirstRow()) {
        const todo = TodoDao.rowToTodoItem(resultSet);
        resultSet.close();
        return todo;
      }
      resultSet.close();
      return null;
    });
  }

  /**
   * Get max sort_order for a date+type group.
   * Sync→Async: querySqlSync → await store.querySql()
   */
  static async getMaxSortOrder(date: string, type: string): Promise<number> {
    return DatabaseExecutor.executeRead<number>('TodoDao.getMaxSortOrder', async (store: relationalStore.RdbStore): Promise<number> => {
      const sql = "SELECT MAX(sort_order) as max_val FROM todo WHERE date = ? AND type = ?";
      const resultSet = await store.querySql(sql, [date, type]);
      if (resultSet.goToFirstRow()) {
        const maxVal = resultSet.getLong(resultSet.getColumnIndex('max_val'));
        resultSet.close();
        return maxVal;
      }
      resultSet.close();
      return 0;
    });
  }

  /**
   * agentID: DEV-004 — Per-day completed-todo count within a date range (statistics daily series).
   * 口径与统计卡一致（StatisticsViewModel.load 现算法）：type='today' AND completed=1，
   * 保证曲线最后一天数值 === totalTodoDone（今日卡片值）。GROUP BY date，缺日由调用方补 0。
   * @param start Start date "YYYY-MM-DD" (inclusive)
   * @param end End date "YYYY-MM-DD" (inclusive)
   * @returns Promise<DailyCount[]> ordered by date ASC
   */
  static async countCompletedByDateRange(start: string, end: string): Promise<DailyCount[]> {
    return DatabaseExecutor.executeRead<DailyCount[]>('TodoDao.countCompletedByDateRange', async (store: relationalStore.RdbStore): Promise<DailyCount[]> => {
      const sql = "SELECT date, COUNT(*) as cnt FROM todo WHERE date >= ? AND date <= ? AND type = 'today' AND completed = 1 GROUP BY date ORDER BY date ASC";
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
   * DEV-013：调度成功后写回提醒引用（remind_at + reminder_id 轻量更新，不动其他列）。
   * remind_at/reminder_id 传 null 即清除提醒引用（取消提醒/完成待办场景）。
   */
  static async updateReminderRef(id: number, remindAt: number | null, reminderId: number | null): Promise<void> {
    return DatabaseExecutor.executeWrite<void>('TodoDao.updateReminderRef', async (store: relationalStore.RdbStore): Promise<void> => {
      const valueBucket: relationalStore.ValuesBucket = {
        'remind_at': remindAt,
        'reminder_id': reminderId,
        'updated_at': Date.now()
      };
      const predicates = new relationalStore.RdbPredicates('todo');
      predicates.equalTo('id', id);
      await store.update(valueBucket, predicates);
      hilog.info(0x0000, TAG, 'Todo reminder ref updated: id=%{public}d, reminderId=%{public}d',
        id, reminderId !== null ? reminderId : -1);
    });
  }

  /**
   * DEV-013：查询待触发提醒的待办（未完成 + remind_at 晚于给定时刻）。
   * 冷启动/页面初始化恢复调度用（系统代理提醒可能被 cancelAllReminders/重启清掉，需重发布）。
   * @param sinceMs 时间下界（毫秒），通常传 Date.now()
   */
  static async queryPendingReminders(sinceMs: number): Promise<TodoItem[]> {
    return DatabaseExecutor.executeRead<TodoItem[]>('TodoDao.queryPendingReminders', async (store: relationalStore.RdbStore): Promise<TodoItem[]> => {
      const sql = 'SELECT * FROM todo WHERE completed = 0 AND remind_at IS NOT NULL AND remind_at > ? ORDER BY remind_at ASC';
      const resultSet = await store.querySql(sql, [sinceMs]);
      const todos: TodoItem[] = [];
      while (resultSet.goToNextRow()) {
        todos.push(TodoDao.rowToTodoItem(resultSet));
      }
      resultSet.close();
      return todos;
    });
  }

  /**
   * Convert result set row to TodoItem object.
   * Uses DDL column name 'completed' (not contract's 'is_completed', per R0-5 field truth source).
   */
  private static rowToTodoItem(resultSet: relationalStore.ResultSet): TodoItem {
    const todo = new TodoItem();
    todo.id = resultSet.getLong(resultSet.getColumnIndex('id'));
    todo.date = resultSet.getString(resultSet.getColumnIndex('date'));
    todo.type = resultSet.getString(resultSet.getColumnIndex('type'));
    todo.title = resultSet.getString(resultSet.getColumnIndex('title'));
    todo.completed = resultSet.getLong(resultSet.getColumnIndex('completed'));
    todo.sort_order = resultSet.getLong(resultSet.getColumnIndex('sort_order'));
    todo.source_task_id = resultSet.isColumnNull(resultSet.getColumnIndex('source_task_id'))
      ? null : resultSet.getLong(resultSet.getColumnIndex('source_task_id'));
    // DEV-003 ③：category 列读回（迁移列带 DEFAULT '日常'；防御性判空兜底）
    const categoryIdx = resultSet.getColumnIndex('category');
    todo.category = (categoryIdx >= 0 && !resultSet.isColumnNull(categoryIdx))
      ? resultSet.getString(categoryIdx) : '日常';
    // DEV-013：提醒增强 6 列读回（自愈补列可空；索引<0/NULL 一律回退模型默认值，防病态库崩溃）
    const dueDateIdx = resultSet.getColumnIndex('due_date');
    todo.due_date = (dueDateIdx >= 0 && !resultSet.isColumnNull(dueDateIdx))
      ? resultSet.getString(dueDateIdx) : null;
    const dueTimeIdx = resultSet.getColumnIndex('due_time');
    todo.due_time = (dueTimeIdx >= 0 && !resultSet.isColumnNull(dueTimeIdx))
      ? resultSet.getString(dueTimeIdx) : null;
    const locationIdx = resultSet.getColumnIndex('location');
    todo.location = (locationIdx >= 0 && !resultSet.isColumnNull(locationIdx))
      ? resultSet.getString(locationIdx) : null;
    const customTagsIdx = resultSet.getColumnIndex('custom_tags');
    todo.custom_tags = (customTagsIdx >= 0 && !resultSet.isColumnNull(customTagsIdx))
      ? resultSet.getString(customTagsIdx) : '[]';
    const remindAtIdx = resultSet.getColumnIndex('remind_at');
    todo.remind_at = (remindAtIdx >= 0 && !resultSet.isColumnNull(remindAtIdx))
      ? resultSet.getLong(remindAtIdx) : null;
    const reminderIdIdx = resultSet.getColumnIndex('reminder_id');
    todo.reminder_id = (reminderIdIdx >= 0 && !resultSet.isColumnNull(reminderIdIdx))
      ? resultSet.getLong(reminderIdIdx) : null;
    todo.created_at = resultSet.getLong(resultSet.getColumnIndex('created_at'));
    todo.updated_at = resultSet.getLong(resultSet.getColumnIndex('updated_at'));
    return todo;
  }
}
