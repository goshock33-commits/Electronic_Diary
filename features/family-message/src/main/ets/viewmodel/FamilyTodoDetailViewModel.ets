// agentID: DEV-006
// File: FamilyTodoDetailViewModel.ets
// Task: T045 待办详情页数据层
// 职责：
// 1. 按对端成员加载消息时间线（我发的/我收的双向）
// 2. 待办完成状态（completed）
// 3. 提醒状态（remind_at/reminder_id 是否已调度）
// 4. 发送新消息
// 5. 标记已读
// 依赖：T040 FamilyMessageManager、T015 statistics 模块重命名

import { hilog } from '@kit.PerformanceAnalysisKit';
import { FamilyMessageManager } from '@ohos/shared';
import { FamilyMessage } from '@ohos/shared';
import { TodoItem } from '@ohos/shared';
import { TodoDao } from '@ohos/shared';
import { Result } from '@ohos/shared';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'FamilyTodoDetailViewModel';

/**
 * 家庭待办详情页 ViewModel
 *
 * 架构职责：
 * - 管理待办详情状态（完成状态、提醒状态）
 * - 加载与对端成员的消息时间线（按 created_at 升序，包含我发的和我收的）
 * - 发送新消息（待办评论、协作通知等）
 * - 标记已读（进入详情页自动标记对话已读）
 *
 * 使用场景：
 * - FamilyTodoDetailPage 初始化时调用 init(todoId, peerUid)
 * - 发送消息调用 sendMessage(content, referenceId)
 * - 刷新时间线调用 refreshMessages()
 */
@Observed
export class FamilyTodoDetailViewModel {
  /** 当前待办对象（null = 未加载或不存在） */
  currentTodo: TodoItem | null = null;

  /** 消息时间线（按 created_at 升序） */
  messages: FamilyMessage[] = [];

  /** 待办是否已完成（从 currentTodo.completed 计算） */
  isCompleted: boolean = false;

  /** 提醒是否已调度且未过期（reminder_id 非空且 remind_at 未过期） */
  isReminded: boolean = false;

  /** 对端成员 uid（用于消息时间线查询） */
  private peerUid: string = '';

  /**
   * 初始化详情页数据
   *
   * @param todoId 待办 ID
   * @param peerUid 对端成员 uid（消息时间线对方）
   * @returns Promise<boolean> true=初始化成功，false=待办不存在或查询失败
   */
  async init(todoId: number, peerUid: string): Promise<boolean> {
    this.peerUid = peerUid;

    try {
      // ① 加载待办详情
      const todo: TodoItem | null = await TodoDao.queryById(todoId);
      if (todo === null) {
        hilog.warn(0x0000, TAG, 'init: todo not found, id=%{public}d', todoId);
        return false;
      }

      this.currentTodo = todo;
      this.updateTodoStatus();

      hilog.info(0x0000, TAG, 'init: todoId=%{public}d peerUid=%{public}s completed=%{public}d reminded=%{public}s',
        todoId, peerUid, todo.completed, JSON.stringify(this.isReminded));

      // ② 加载消息时间线（与对端成员的双向消息）
      await this.loadMessages();

      // ③ 标记与该成员的所有未读消息为已读
      await this.markMessagesRead();

      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'init failed: %{public}s', error.message);
      return false;
    }
  }

  /**
   * 加载消息时间线
   *
   * 流程：
   * 1. 调用 FamilyMessageManager.getMessages(peerUid) 获取双向消息
   * 2. 消息已按 created_at 升序排列（时间线从旧到新）
   * 3. 更新本地 messages 数组
   *
   * @returns Promise<boolean> true=加载成功，false=查询失败
   */
  private async loadMessages(): Promise<boolean> {
    try {
      const manager: FamilyMessageManager = FamilyMessageManager.getInstance();
      const result: Result<FamilyMessage[]> = await manager.getMessages(this.peerUid);

      if (!result.success || result.data === null) {
        hilog.warn(0x0000, TAG, 'loadMessages: query failed, peer_uid=%{public}s', this.peerUid);
        this.messages = [];
        return false;
      }

      this.messages = result.data;
      hilog.info(0x0000, TAG, 'loadMessages: loaded %{public}d messages', this.messages.length);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'loadMessages failed: %{public}s', error.message);
      this.messages = [];
      return false;
    }
  }

  /**
   * 标记与对端成员的所有未读消息为已读
   *
   * 进入详情页时自动调用，降低未读数
   */
  private async markMessagesRead(): Promise<void> {
    try {
      const manager: FamilyMessageManager = FamilyMessageManager.getInstance();
      const result: Result<void> = await manager.markConversationRead(this.peerUid);

      if (!result.success) {
        hilog.warn(0x0000, TAG, 'markMessagesRead: failed, peer_uid=%{public}s', this.peerUid);
      } else {
        hilog.info(0x0000, TAG, 'markMessagesRead: success, peer_uid=%{public}s', this.peerUid);
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(0x0000, TAG, 'markMessagesRead failed (non-fatal): %{public}s', error.message);
    }
  }

  /**
   * 发送新消息
   *
   * @param content 消息内容
   * @param referenceId 关联 ID（可选，如待办 ID）
   * @returns Promise<boolean> true=发送成功，false=发送失败
   */
  async sendMessage(content: string, referenceId?: string): Promise<boolean> {
    if (content.trim().length === 0) {
      hilog.warn(0x0000, TAG, 'sendMessage: content is empty');
      return false;
    }

    try {
      const manager: FamilyMessageManager = FamilyMessageManager.getInstance();
      const result: Result<string> = await manager.sendMessage('todo', this.peerUid, content, referenceId);

      if (!result.success) {
        hilog.error(0x0000, TAG, 'sendMessage: send failed, peer_uid=%{public}s', this.peerUid);
        return false;
      }

      hilog.info(0x0000, TAG, 'sendMessage: sent, message_id=%{public}s', result.data ?? 'unknown');

      // 发送成功后刷新消息时间线
      await this.loadMessages();
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'sendMessage failed: %{public}s', error.message);
      return false;
    }
  }

  /**
   * 刷新消息时间线
   *
   * 用户手动刷新或收到新消息推送时调用
   *
   * @returns Promise<boolean> true=刷新成功，false=查询失败
   */
  async refreshMessages(): Promise<boolean> {
    hilog.info(0x0000, TAG, 'refreshMessages: triggered');
    return await this.loadMessages();
  }

  /**
   * 刷新待办状态
   *
   * 待办完成状态或提醒状态变更后调用
   *
   * @returns Promise<boolean> true=刷新成功，false=待办不存在
   */
  async refreshTodoStatus(): Promise<boolean> {
    if (this.currentTodo === null) {
      hilog.warn(0x0000, TAG, 'refreshTodoStatus: currentTodo is null');
      return false;
    }

    try {
      const todo: TodoItem | null = await TodoDao.queryById(this.currentTodo.id);
      if (todo === null) {
        hilog.warn(0x0000, TAG, 'refreshTodoStatus: todo not found, id=%{public}d', this.currentTodo.id);
        return false;
      }

      this.currentTodo = todo;
      this.updateTodoStatus();

      hilog.info(0x0000, TAG, 'refreshTodoStatus: updated, completed=%{public}d reminded=%{public}s',
        todo.completed, JSON.stringify(this.isReminded));
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'refreshTodoStatus failed: %{public}s', error.message);
      return false;
    }
  }

  /**
   * 更新待办状态标志位
   *
   * 从 currentTodo 计算 isCompleted 和 isReminded
   */
  private updateTodoStatus(): void {
    if (this.currentTodo === null) {
      this.isCompleted = false;
      this.isReminded = false;
      return;
    }

    // 完成状态：completed === 1
    this.isCompleted = this.currentTodo.completed === 1;

    // 提醒状态：reminder_id 非空且 remind_at 未过期
    // reminder_id 非空表示已调度过系统提醒
    // remind_at > Date.now() 表示提醒时刻未到（未过期）
    this.isReminded = this.currentTodo.reminder_id !== null &&
      this.currentTodo.remind_at !== null &&
      this.currentTodo.remind_at > Date.now();
  }

  /**
   * 获取当前待办 ID（防御性访问）
   *
   * @returns number 待办 ID，如果 currentTodo 为 null 返回 -1
   */
  getTodoId(): number {
    return this.currentTodo !== null ? this.currentTodo.id : -1;
  }

  /**
   * 获取当前待办标题（防御性访问）
   *
   * @returns string 待办标题，如果 currentTodo 为 null 返回空字符串
   */
  getTodoTitle(): string {
    return this.currentTodo !== null ? this.currentTodo.title : '';
  }

  /**
   * 获取消息列表（只读访问）
   *
   * @returns FamilyMessage[] 消息时间线（按 created_at 升序）
   */
  getMessages(): FamilyMessage[] {
    return this.messages;
  }

  /**
   * 获取待办完成状态
   *
   * @returns boolean true=已完成，false=未完成
   */
  getIsCompleted(): boolean {
    return this.isCompleted;
  }

  /**
   * 获取提醒状态
   *
   * @returns boolean true=已调度且未过期，false=未设置或已过期
   */
  getIsReminded(): boolean {
    return this.isReminded;
  }
}
