// agentID: DEV-005
// File: FamilyMessageViewModel.ets
// Task: T041 消息流 ViewModel —— 会话列表状态管理 + 分页加载 + EventBus 订阅
// 依赖: T040 FamilyMessageManager（已完成）
// 合规: ArkTS 严格模式，@Observed 装饰器，EventBus 常量事件名

import { FamilyMessageManager } from '@ohos/shared';
import { MessageGroup } from '@ohos/shared';
import { Result } from '@ohos/shared';
import { EventBus } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'FamilyMessageViewModel';

// EventBus 事件名常量
const EVENT_MESSAGE_RECEIVED: string = 'event:message:received';
const EVENT_MESSAGE_REFRESH: string = 'event:message:refresh';

/**
 * 家庭消息流 ViewModel
 *
 * 职责：
 * 1. 管理会话列表状态（conversationList, unreadTotal）
 * 2. 支持分页加载
 * 3. 订阅 EventBus 事件自动刷新（推送/轮询触发）
 * 4. 提供手动刷新接口
 *
 * 使用示例：
 * ```
 * @State viewModel: FamilyMessageViewModel = new FamilyMessageViewModel();
 *
 * aboutToAppear() {
 *   this.viewModel.loadConversations();
 * }
 *
 * aboutToDisappear() {
 *   this.viewModel.dispose();
 * }
 * ```
 */
@Observed
export class FamilyMessageViewModel {
  /** 会话列表（按最新消息时间降序） */
  conversationList: MessageGroup[] = [];

  /** 未读总数 */
  unreadTotal: number = 0;

  /** 加载状态 */
  isLoading: boolean = false;

  /** 是否还有更多数据（分页） */
  hasMore: boolean = true;

  /** 当前页码（从 0 开始） */
  private currentPage: number = 0;

  /** 每页条数 */
  private readonly pageSize: number = 20;

  /** FamilyMessageManager 实例 */
  private messageManager: FamilyMessageManager = FamilyMessageManager.getInstance();

  /** EventBus 订阅标记 */
  private isSubscribed: boolean = false;

  constructor() {
    this.setupEventBusSubscriptions();
  }

  /**
   * 加载会话列表（首次加载 + 下拉刷新）
   */
  async loadConversations(): Promise<void> {
    if (this.isLoading) {
      hilog.warn(0x0000, TAG, 'loadConversations: already loading, skip');
      return;
    }

    this.isLoading = true;
    this.currentPage = 0;

    try {
      const result: Result<MessageGroup[]> = await this.messageManager.getConversationList();

      if (result.success && result.data !== null) {
        this.conversationList = result.data;
        this.calculateUnreadTotal();
        this.hasMore = result.data.length >= this.pageSize;

        hilog.info(0x0000, TAG, 'loadConversations: loaded %{public}d conversations, unread=%{public}d',
          this.conversationList.length, this.unreadTotal);
      } else {
        hilog.error(0x0000, TAG, 'loadConversations failed: %{public}s', result.message);
        this.conversationList = [];
        this.unreadTotal = 0;
        this.hasMore = false;
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'loadConversations exception: %{public}s', (e as Error).message);
      this.conversationList = [];
      this.unreadTotal = 0;
      this.hasMore = false;
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 加载更多会话（上拉加载）
   *
   * 注意：由于 FamilyMessageManager.getConversationList() 返回完整列表，
   * 此方法模拟分页效果（实际场景中应由后端支持分页查询）
   */
  async loadMore(): Promise<void> {
    if (this.isLoading || !this.hasMore) {
      return;
    }

    this.isLoading = true;
    this.currentPage++;

    try {
      // 模拟分页：实际应调用支持 limit/offset 的 API
      // 当前 getConversationList() 返回全量数据，此处仅演示分页逻辑
      hilog.info(0x0000, TAG, 'loadMore: page=%{public}d (simulated)', this.currentPage);

      // 实际应用中，此处调用：
      // const result = await this.messageManager.getConversationListPaged(this.currentPage, this.pageSize);

      // 当前实现：标记无更多数据（因为 getConversationList 已返回全量）
      this.hasMore = false;
    } catch (e) {
      hilog.error(0x0000, TAG, 'loadMore exception: %{public}s', (e as Error).message);
      this.hasMore = false;
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 手动刷新消息流（用户下拉刷新时调用）
   */
  async refresh(): Promise<void> {
    hilog.info(0x0000, TAG, 'refresh: manual refresh triggered');
    await this.loadConversations();
  }

  /**
   * 标记指定会话为已读
   *
   * @param peerUid 对端成员 uid
   */
  async markConversationRead(peerUid: string): Promise<void> {
    try {
      const result: Result<void> = await this.messageManager.markConversationRead(peerUid);

      if (result.success) {
        // 更新本地状态
        const conversation: MessageGroup | undefined = this.conversationList.find(
          (group: MessageGroup): boolean => group.fromMember.uid === peerUid
        );

        if (conversation !== undefined) {
          conversation.unreadCount = 0;
          this.calculateUnreadTotal();
          hilog.info(0x0000, TAG, 'markConversationRead: peer_uid=%{public}s, unreadTotal=%{public}d',
            peerUid, this.unreadTotal);
        }
      } else {
        hilog.error(0x0000, TAG, 'markConversationRead failed: %{public}s', result.message);
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'markConversationRead exception: %{public}s', (e as Error).message);
    }
  }

  /**
   * 计算未读总数
   */
  private calculateUnreadTotal(): void {
    this.unreadTotal = 0;
    for (const group of this.conversationList) {
      this.unreadTotal += group.unreadCount;
    }
  }

  /**
   * 设置 EventBus 订阅（监听推送/轮询事件）
   */
  private setupEventBusSubscriptions(): void {
    if (this.isSubscribed) {
      return;
    }

    // 订阅消息接收事件（推送/轮询触发）
    EventBus.on(EVENT_MESSAGE_RECEIVED, (data: Record<string, Object>): void => {
      hilog.info(0x0000, TAG, 'EVENT_MESSAGE_RECEIVED: auto refresh');
      this.loadConversations();
    });

    // 订阅消息刷新事件（其他页面触发刷新）
    EventBus.on(EVENT_MESSAGE_REFRESH, (data: Record<string, Object>): void => {
      hilog.info(0x0000, TAG, 'EVENT_MESSAGE_REFRESH: auto refresh');
      this.loadConversations();
    });

    this.isSubscribed = true;
    hilog.info(0x0000, TAG, 'setupEventBusSubscriptions: subscribed to message events');
  }

  /**
   * 释放资源（组件 aboutToDisappear 时调用）
   */
  dispose(): void {
    if (this.isSubscribed) {
      EventBus.off(EVENT_MESSAGE_RECEIVED);
      EventBus.off(EVENT_MESSAGE_REFRESH);
      this.isSubscribed = false;
      hilog.info(0x0000, TAG, 'dispose: unsubscribed from message events');
    }
  }

  /**
   * 获取会话数量
   */
  getConversationCount(): number {
    return this.conversationList.length;
  }

  /**
   * 检查是否有未读消息
   */
  hasUnreadMessages(): boolean {
    return this.unreadTotal > 0;
  }

  /**
   * 获取指定会话
   *
   * @param peerUid 对端成员 uid
   * @returns MessageGroup | null
   */
  getConversation(peerUid: string): MessageGroup | null {
    const conversation: MessageGroup | undefined = this.conversationList.find(
      (group: MessageGroup): boolean => group.fromMember.uid === peerUid
    );
    return conversation !== undefined ? conversation : null;
  }
}
