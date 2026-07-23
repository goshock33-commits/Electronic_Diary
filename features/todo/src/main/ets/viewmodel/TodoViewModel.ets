// <!-- agentID: DEV-005 -->
// fix: DEV-013 · 待办提醒调度接入：add 支持 TodoReminderOptions（截止日期/时间/地点/自定义标签/提醒时刻），
//   增删改/完成切换联动系统代理提醒（ReminderAgentService.scheduleTodoReminder/cancelTodoReminder），
//   init 每进程一次 rescheduleAllTodoReminders 自愈恢复；新增 setReminder/clearReminder 独立入口。
// File: TodoViewModel.ets
// Task: M02 Todo business logic - CRUD + toggle complete + date grouping
// Architecture: ARC-001 4.1 TodoDao / 4.5 EventBus / S2 diary management
// Fixes: AppStorage write (R0-3), EventBus EventNames + flat payload (R0-2),
//   DDL field 'completed' (R0-5), EventBus emit signature update (B01)
// Skill Ref: frontend-design / ui-ux-pro-max

import { TodoDao } from '@ohos/shared';
import { TodoItem } from '@ohos/shared';
import { EventBus } from '@ohos/shared';
import { ReminderAgentService } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'TodoViewModel';

/**
 * Task extraction source data for creating todos from extracted tasks.
 */
export interface TaskSource {
  sourceTaskId: number;
  sourceType: string;
}

/**
 * DEV-013：add() 可选的提醒/日程增强字段（全可选，不传保持旧行为）。
 * customTags 传字符串数组，VM 内部序列化为 JSON 字符串落库。
 */
export interface TodoReminderOptions {
  dueDate?: string;
  dueTime?: string;
  location?: string;
  customTags?: string[];
  remindAt?: number;
}

/**
 * TodoViewModel - Manages todo list CRUD operations.
 * Delegates to TodoDao (async, no TaskPool) and emits events for UI refresh.
 */
export class TodoViewModel {
  private todayTodos: TodoItem[] = [];
  private tomorrowTodos: TodoItem[] = [];
  private currentDate: string = '';
  /** DEV-013：提醒自愈恢复每进程只跑一次（init/refresh 高频调用，避免反复重发布系统提醒） */
  private static remindersRestored: boolean = false;

  /**
   * Initialize the view model for a target date.
   * Loads both today and tomorrow todo lists.
   */
  async init(date: string): Promise<void> {
    this.currentDate = date;
    try {
      // Tomorrow todos are stored under currentDate+1 by add(); query the same
      // date here so newly added tomorrow todos survive re-read / restart.
      const tomorrowDate = this.getTomorrowDate();
      const results = await Promise.all([
        TodoDao.queryByDateAndType(date, 'today'),
        TodoDao.queryByDateAndType(tomorrowDate, 'tomorrow')
      ]);
      const todayList = results[0];
      const tomorrowList = results[1];
      this.todayTodos = todayList;
      this.tomorrowTodos = tomorrowList;
      // AppStorage: sync initial state to UI (R0-3 fix)
      AppStorage.setOrCreate('todayTodos', this.todayTodos);
      hilog.info(0x0000, TAG, 'Init: date=%{public}s, today=%{public}d, tomorrow=%{public}d',
        date, todayList.length, tomorrowList.length);
      // DEV-013：首次进入时自愈恢复未过期待办提醒（scheduleDaily 的 cancelAllReminders /
      // 系统重启会清掉系统侧提醒，DB 真相源重发布）。fire-and-forget，不阻塞首帧数据。
      if (!TodoViewModel.remindersRestored) {
        TodoViewModel.remindersRestored = true;
        ReminderAgentService.rescheduleAllTodoReminders().catch((err: Error) => {
          hilog.warn(0x0000, TAG, 'Todo reminders restore failed: %{public}s', err.message);
        });
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Init failed: %{public}s', error.message);
    }
  }

  /**
   * Add a new todo item.
   * @param title Todo content text.
   * @param type "today" or "tomorrow".
   * @param category DEV-003 ③：日程标签（日常/学习/工作/日记/微信/语音），缺省'日常'。
   * @param taskSource Optional source task info for extracted tasks.
   * @param options DEV-013：可选提醒/日程增强字段（截止日期/时间/地点/自定义标签/提醒时刻）。
   * @returns The created TodoItem or null on failure.
   */
  async add(title: string, type: string, category?: string, taskSource?: TaskSource,
    options?: TodoReminderOptions): Promise<TodoItem | null> {
    try {
      const date = type === 'tomorrow' ? this.getTomorrowDate() : this.currentDate;
      const maxOrder = await TodoDao.getMaxSortOrder(date, type);
      const todo = new TodoItem(date, title, type, category);
      todo.sort_order = maxOrder + 1;
      if (taskSource) {
        todo.source_task_id = taskSource.sourceTaskId;
      }
      // DEV-013：增强字段落模型（undefined 不覆盖模型默认值）
      if (options !== undefined) {
        if (options.dueDate !== undefined) { todo.due_date = options.dueDate; }
        if (options.dueTime !== undefined) { todo.due_time = options.dueTime; }
        if (options.location !== undefined) { todo.location = options.location; }
        if (options.customTags !== undefined) { todo.setCustomTags(options.customTags); }
        if (options.remindAt !== undefined) { todo.remind_at = options.remindAt; }
      }
      const rowId = await TodoDao.insert(todo);
      if (rowId > 0) {
        todo.id = rowId;
        // DEV-013：设置了未来提醒 → 发布系统提醒并写回 reminder_id
        if (todo.hasPendingReminder()) {
          await this.syncReminder(todo);
        }
        if (type === 'today') {
          this.todayTodos.push(todo);
        } else {
          this.tomorrowTodos.push(todo);
        }
        // AppStorage: sync to frontend @StorageLink('todayTodos') (R0-3 fix)
        AppStorage.setOrCreate('todayTodos', this.todayTodos);
        // EventBus: flat payload per B01 unified string API (R0-2 fix)
        const todoPayload: Record<string, Object> = {};
        todoPayload['todoId'] = rowId;
        todoPayload['date'] = date;
        todoPayload['type'] = type;
        EventBus.emit(EventBus.EventNames.TODO_CREATED, todoPayload);
        hilog.info(0x0000, TAG, 'Todo added: title=%{public}s, type=%{public}s', title, type);
        return todo;
      }
      return null;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Add failed: %{public}s', error.message);
      return null;
    }
  }

  /**
   * Update an existing todo item.
   * DEV-003 ③：支持编辑全字段持久化（title/category/type/date），并补发 TODO_UPDATED 事件（①统计页刷新依赖）。
   * @param todo 待更新对象（title/category 等字段已由调用方改好）。
   * @param newType 可选改期："today"|"tomorrow"。与 todo.type 不同时触发日期重算：
   *   date 重算为今日/明日、sort_order 归入新组末尾（maxOrder+1）、type 更新——UI 层无需自行算日期。
   */
  async update(todo: TodoItem, newType?: string): Promise<boolean> {
    try {
      // 改期重算（业务层职责：截止日期变更 → date/sort_order/type 联动）
      if (newType !== undefined && newType !== todo.type && (newType === 'today' || newType === 'tomorrow')) {
        const newDate = newType === 'tomorrow' ? this.getTomorrowDate() : this.currentDate;
        const maxOrder = await TodoDao.getMaxSortOrder(newDate, newType);
        todo.type = newType;
        todo.date = newDate;
        todo.sort_order = maxOrder + 1;
      }
      await TodoDao.update(todo);
      // DEV-013：编辑后提醒同步——remind_at 有效且未完成 → 重调度（改时间幂等）；
      // remind_at 被清 / 已完成 → 取消系统提醒并清 DB 引用。
      await this.syncReminder(todo);
      // 本地列表同步：改期时先从两组移除再按新 type 归组，避免残留旧组
      this.todayTodos = this.todayTodos.filter((t: TodoItem) => t.id !== todo.id);
      this.tomorrowTodos = this.tomorrowTodos.filter((t: TodoItem) => t.id !== todo.id);
      if (todo.type === 'today') {
        this.todayTodos.push(todo);
        this.todayTodos.sort((a: TodoItem, b: TodoItem): number => a.sort_order - b.sort_order);
      } else {
        this.tomorrowTodos.push(todo);
        this.tomorrowTodos.sort((a: TodoItem, b: TodoItem): number => a.sort_order - b.sort_order);
      }
      // AppStorage: sync updated list to UI (R0-3 fix)
      AppStorage.setOrCreate('todayTodos', this.todayTodos);
      // DEV-003 ①：编辑后发 TODO_UPDATED（§8.3① Record 空字面量+括号逐键赋值）
      const todoPayload: Record<string, Object> = {};
      todoPayload['todoId'] = todo.id;
      todoPayload['date'] = todo.date;
      todoPayload['type'] = todo.type;
      todoPayload['category'] = todo.category;
      EventBus.emit(EventBus.EventNames.TODO_UPDATED, todoPayload);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Update failed: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Delete a todo item.
   * DEV-013：删除前按 reminder_id 取消系统提醒（本地列表找不到时跳过，提醒过期自会清理）。
   */
  async delete(id: number): Promise<boolean> {
    try {
      const found: TodoItem | undefined =
        this.todayTodos.find((t: TodoItem) => t.id === id) ?? this.tomorrowTodos.find((t: TodoItem) => t.id === id);
      if (found !== undefined && found.reminder_id !== null) {
        await ReminderAgentService.cancelTodoReminder(found.reminder_id);
        ReminderAgentService.clearTodoFallback(id);
      }
      await TodoDao.delete(id);
      this.todayTodos = this.todayTodos.filter((t: TodoItem) => t.id !== id);
      this.tomorrowTodos = this.tomorrowTodos.filter((t: TodoItem) => t.id !== id);
      // AppStorage: sync after deletion (R0-3 fix)
      AppStorage.setOrCreate('todayTodos', this.todayTodos);
      // EventBus: flat payload per B01 unified string API (R0-2 fix)
      const todoPayload: Record<string, Object> = {};
      todoPayload['todoId'] = id;
      EventBus.emit(EventBus.EventNames.TODO_DELETED, todoPayload);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Delete failed: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Toggle the completion status of a todo item.
   * Uses DDL column name 'completed' (not contract 'is_completed', per R0-5).
   */
  async toggleComplete(id: number): Promise<boolean> {
    try {
      await TodoDao.toggleComplete(id);
      // Update local state
      const updateLocal = (list: TodoItem[]): void => {
        const idx = list.findIndex((t: TodoItem) => t.id === id);
        if (idx >= 0) {
          list[idx].toggleComplete();
        }
      };
      updateLocal(this.todayTodos);
      updateLocal(this.tomorrowTodos);
      // DEV-013：完成 → 取消系统提醒（保留 remind_at，撤销完成可恢复）；撤销完成且提醒未过期 → 重调度
      const toggled: TodoItem | undefined =
        this.todayTodos.find((t: TodoItem) => t.id === id) ?? this.tomorrowTodos.find((t: TodoItem) => t.id === id);
      if (toggled !== undefined) {
        await this.syncReminder(toggled);
      }
      // AppStorage: sync toggled state to UI (R0-3 fix)
      AppStorage.setOrCreate('todayTodos', this.todayTodos);
      // EventBus: flat payload per B01 unified string API (R0-2 fix)
      const todoPayload: Record<string, Object> = {};
      todoPayload['todoId'] = id;
      EventBus.emit(EventBus.EventNames.TODO_COMPLETED, todoPayload);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Toggle failed: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Get all today todos.
   */
  getTodayTodos(): TodoItem[] {
    return this.todayTodos;
  }

  /**
   * Get all tomorrow todos.
   */
  getTomorrowTodos(): TodoItem[] {
    return this.tomorrowTodos;
  }

  /**
   * Count uncompleted todos by type.
   * Uses DDL column name 'completed' (not contract 'is_completed', per R0-5).
   */
  getUncompletedCount(type: string): number {
    const list = type === 'today' ? this.todayTodos : this.tomorrowTodos;
    return list.filter((t: TodoItem) => t.completed === 0).length;
  }

  /**
   * Refresh data (call in onPageShow for event-loss compensation).
   */
  async refresh(): Promise<void> {
    if (this.currentDate.length > 0) {
      await this.init(this.currentDate);
    }
  }

  /**
   * DEV-013：给指定待办设置/修改提醒时刻并调度系统提醒。
   * @param id 待办 id（须在当前已加载列表中）
   * @param remindAt 提醒触发时间戳（毫秒，须为未来时刻）
   * @returns true=系统提醒发布成功；false=待办不存在/时刻无效/发布失败
   */
  async setReminder(id: number, remindAt: number): Promise<boolean> {
    const found: TodoItem | undefined =
      this.todayTodos.find((t: TodoItem) => t.id === id) ?? this.tomorrowTodos.find((t: TodoItem) => t.id === id);
    if (found === undefined) {
      hilog.warn(0x0000, TAG, 'setReminder: todo not found, id=%{public}d', id);
      return false;
    }
    found.remind_at = remindAt;
    await this.syncReminder(found);
    AppStorage.setOrCreate('todayTodos', this.todayTodos);
    return found.reminder_id !== null;
  }

  /**
   * DEV-013：清除指定待办的提醒（取消系统提醒 + 清 DB 的 remind_at/reminder_id）。
   */
  async clearReminder(id: number): Promise<boolean> {
    try {
      const found: TodoItem | undefined =
        this.todayTodos.find((t: TodoItem) => t.id === id) ?? this.tomorrowTodos.find((t: TodoItem) => t.id === id);
      if (found !== undefined) {
        await ReminderAgentService.cancelTodoReminder(found.reminder_id);
        ReminderAgentService.clearTodoFallback(id);
        found.remind_at = null;
        found.reminder_id = null;
      }
      await TodoDao.updateReminderRef(id, null, null);
      AppStorage.setOrCreate('todayTodos', this.todayTodos);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'clearReminder failed: %{public}s', error.message);
      return false;
    }
  }

  /**
   * DEV-013：提醒状态与系统代理对齐（增/改/完成切换共用）。
   * 未完成且 remind_at 为未来 → 重调度（scheduleTodoReminder 内部先清旧，幂等）并写回 reminder_id；
   * 其余情况（已完成/无 remind_at/已过期）→ 取消系统提醒并清 reminder_id（remind_at 保留，撤销完成可恢复）。
   * 非致命：失败仅记日志，不影响主 CRUD 流程。
   */
  private async syncReminder(todo: TodoItem): Promise<void> {
    try {
      hilog.info(0x0000, TAG, 'syncReminder: id=%{public}d remind_at=%{public}d completed=%{public}d pending=%{public}s',
        todo.id, todo.remind_at ?? -1, todo.completed, JSON.stringify(todo.hasPendingReminder()));
      if (todo.completed === 0 && todo.hasPendingReminder()) {
        const newId: number = await ReminderAgentService.scheduleTodoReminder(todo);
        // -1 = 系统提醒失败，但降级定时器已在 scheduleTodoReminder 内部启用
        todo.reminder_id = newId >= 0 ? newId : (newId === -1 ? -2 : null);
        await TodoDao.updateReminderRef(todo.id, todo.remind_at, todo.reminder_id);
      } else if (todo.reminder_id !== null) {
        await ReminderAgentService.cancelTodoReminder(todo.reminder_id);
        todo.reminder_id = null;
        await TodoDao.updateReminderRef(todo.id, todo.remind_at, null);
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(0x0000, TAG, 'syncReminder failed (non-fatal): id=%{public}d, %{public}s',
        todo.id, error.message);
    }
  }

  /** Get tomorrow's date string "YYYY-MM-DD" */
  private getTomorrowDate(): string {
    const today = new Date(this.currentDate);
    const tomorrow = new Date(today.getTime() + 86400000);
    const y = tomorrow.getFullYear();
    const m = String(tomorrow.getMonth() + 1).padStart(2, '0');
    const d = String(tomorrow.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }
}
