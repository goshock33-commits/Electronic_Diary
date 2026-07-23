// <!-- agentID: DEV-010 -->
// File: ExtractedTaskDao.ets
// Task: M07 DAO async migration - ExtractedTask CRUD + conversion (6 methods)
// Architecture: ARC-001 4.1 ExtractedTaskDao API
// Migration: insertSync→insert, updateSync→update, querySync→query, querySqlSync→querySql, deleteSync→delete
// Fields per DDL: is_converted, converted_todo_id, priority INTEGER
// Ref: B00 CheckInDao async template

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseExecutor } from '../DatabaseExecutor';
import { ExtractedTask } from '../../data/ExtractedTask';

const TAG = 'ExtractedTaskDao';

export class ExtractedTaskDao {
  /**
   * Insert an extracted task.
   * Sync→Async: insertSync → await store.insert()
   * @returns Promise<number> Inserted row ID
   */
  static async insert(task: ExtractedTask): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('ExtractedTaskDao.insert', async (store: relationalStore.RdbStore): Promise<number> => {
      const valueBucket: relationalStore.ValuesBucket = {
        'source': task.source,
        'category': task.category,
        'title': task.title,
        'description': task.description,
        'task_date': task.task_date,
        'task_time': task.task_time,
        'location': task.location,
        'priority': task.priority,
        'is_converted': task.is_converted,
        'converted_todo_id': task.converted_todo_id,
        'created_at': task.created_at
      };
      const rowId = await store.insert('extracted_task', valueBucket);
      hilog.info(0x0000, TAG, 'ExtractedTask inserted: title=%{public}s, rowId=%{public}d',
        task.title, rowId);
      return rowId;
    });
  }

  /**
   * Mark a task as converted and link it to a todo item.
   * Sync→Async: updateSync → await store.update()
   */
  static async convertToTodo(id: number, todoId: number): Promise<void> {
    return DatabaseExecutor.executeWrite<void>('ExtractedTaskDao.convertToTodo',
      async (store: relationalStore.RdbStore): Promise<void> => {
        const valueBucket: relationalStore.ValuesBucket = {
          'is_converted': 1,
          'converted_todo_id': todoId
        };
        const predicates = new relationalStore.RdbPredicates('extracted_task');
        predicates.equalTo('id', id);
        await store.update(valueBucket, predicates);
        hilog.info(0x0000, TAG, 'Task converted: id=%{public}d -> todoId=%{public}d', id, todoId);
      });
  }

  /**
   * Query unconverted tasks (pending conversion).
   * Sync→Async: querySync → await store.query()
   */
  static async queryUnconverted(): Promise<ExtractedTask[]> {
    return DatabaseExecutor.executeRead<ExtractedTask[]>('ExtractedTaskDao.queryUnconverted',
      async (store: relationalStore.RdbStore): Promise<ExtractedTask[]> => {
        const predicates = new relationalStore.RdbPredicates('extracted_task');
        predicates.equalTo('is_converted', 0);
        predicates.orderByDesc('created_at');
        const resultSet = await store.query(predicates);
        const tasks: ExtractedTask[] = [];
        while (resultSet.goToNextRow()) {
          tasks.push(ExtractedTaskDao.rowToTask(resultSet));
        }
        resultSet.close();
        return tasks;
      });
  }

  /**
   * Query tasks by source type (share/clipboard/voice/floating).
   * Sync→Async: querySync → await store.query()
   */
  static async queryBySource(source: string): Promise<ExtractedTask[]> {
    return DatabaseExecutor.executeRead<ExtractedTask[]>('ExtractedTaskDao.queryBySource',
      async (store: relationalStore.RdbStore): Promise<ExtractedTask[]> => {
        const predicates = new relationalStore.RdbPredicates('extracted_task');
        predicates.equalTo('source', source);
        predicates.orderByDesc('created_at');
        const resultSet = await store.query(predicates);
        const tasks: ExtractedTask[] = [];
        while (resultSet.goToNextRow()) {
          tasks.push(ExtractedTaskDao.rowToTask(resultSet));
        }
        resultSet.close();
        return tasks;
      });
  }

  /**
   * Query all extracted tasks with pagination support.
   * Sync→Async: querySqlSync → await store.querySql()
   */
  static async queryAll(limit: number, offset: number): Promise<ExtractedTask[]> {
    return DatabaseExecutor.executeRead<ExtractedTask[]>('ExtractedTaskDao.queryAll',
      async (store: relationalStore.RdbStore): Promise<ExtractedTask[]> => {
        const sql = "SELECT * FROM extracted_task ORDER BY created_at DESC LIMIT ? OFFSET ?";
        const resultSet = await store.querySql(sql, [limit, offset]);
        const tasks: ExtractedTask[] = [];
        while (resultSet.goToNextRow()) {
          tasks.push(ExtractedTaskDao.rowToTask(resultSet));
        }
        resultSet.close();
        return tasks;
      });
  }

  /**
   * Search extracted tasks by title or description keyword.
   * For M18 cross-source search (5th data source).
   */
  static async searchByTitle(keyword: string): Promise<ExtractedTask[]> {
    return DatabaseExecutor.executeRead<ExtractedTask[]>('ExtractedTaskDao.searchByTitle',
      async (store: relationalStore.RdbStore): Promise<ExtractedTask[]> => {
        const sql = `SELECT * FROM extracted_task
          WHERE title LIKE ? OR description LIKE ?
          ORDER BY created_at DESC`;
        const param = `%${keyword}%`;
        const resultSet = await store.querySql(sql, [param, param]);
        const tasks: ExtractedTask[] = [];
        while (resultSet.goToNextRow()) {
          tasks.push(ExtractedTaskDao.rowToTask(resultSet));
        }
        resultSet.close();
        return tasks;
      });
  }

  /**
   * Delete an extracted task by ID.
   * Sync→Async: deleteSync → await store.delete()
   */
  static async delete(id: number): Promise<void> {
    return DatabaseExecutor.executeWrite<void>('ExtractedTaskDao.delete', async (store: relationalStore.RdbStore): Promise<void> => {
      const predicates = new relationalStore.RdbPredicates('extracted_task');
      predicates.equalTo('id', id);
      await store.delete(predicates);
      hilog.info(0x0000, TAG, 'ExtractedTask deleted: id=%{public}d', id);
    });
  }

  private static rowToTask(resultSet: relationalStore.ResultSet): ExtractedTask {
    const task = new ExtractedTask();
    task.id = resultSet.getLong(resultSet.getColumnIndex('id'));
    task.source = resultSet.getString(resultSet.getColumnIndex('source'));
    task.category = resultSet.getString(resultSet.getColumnIndex('category'));
    task.title = resultSet.getString(resultSet.getColumnIndex('title'));
    task.description = resultSet.isColumnNull(resultSet.getColumnIndex('description'))
      ? null : resultSet.getString(resultSet.getColumnIndex('description'));
    task.task_date = resultSet.isColumnNull(resultSet.getColumnIndex('task_date'))
      ? null : resultSet.getString(resultSet.getColumnIndex('task_date'));
    task.task_time = resultSet.isColumnNull(resultSet.getColumnIndex('task_time'))
      ? null : resultSet.getString(resultSet.getColumnIndex('task_time'));
    task.location = resultSet.isColumnNull(resultSet.getColumnIndex('location'))
      ? null : resultSet.getString(resultSet.getColumnIndex('location'));
    task.priority = resultSet.isColumnNull(resultSet.getColumnIndex('priority'))
      ? null : resultSet.getLong(resultSet.getColumnIndex('priority'));
    task.is_converted = resultSet.getLong(resultSet.getColumnIndex('is_converted'));
    task.converted_todo_id = resultSet.isColumnNull(resultSet.getColumnIndex('converted_todo_id'))
      ? null : resultSet.getLong(resultSet.getColumnIndex('converted_todo_id'));
    task.created_at = resultSet.getLong(resultSet.getColumnIndex('created_at'));
    return task;
  }
}
