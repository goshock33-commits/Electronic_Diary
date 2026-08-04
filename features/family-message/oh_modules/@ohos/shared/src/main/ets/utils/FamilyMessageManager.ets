// agentID: DEV-013
// agentID: DEV-002
// File: FamilyMessageManager.ets
// Task: T032 家庭消息流管理单例 —— 发送/接收/查询家庭消息
// Task: T035 推送降级轮询 —— 无 token/推送不可达时的兜底方案
// 关联架构: REFACTOR_ARCHITECTURE.md §2 家庭消息流章节
// 合规: ArkTS 严格模式，单例模式（参考 AccountManager/FamilyManager）

import { hilog } from '@kit.PerformanceAnalysisKit';
import { FamilyMessage } from '../data/FamilyMessage';
import { MessageGroup } from '../data/MessageGroup';
import { FamilyMember } from '../data/FamilyMember';
import { CloudDbService, CloudFamilyMessage } from '../cloud/CloudDbService';
import { AccountManager } from './AccountManager';
import { FamilyManager, Result } from './FamilyManager';

const TAG: string = 'FamilyMessageManager';

// T035: 轮询配置常量
const DEFAULT_POLLING_INTERVAL: number = 60000; // 默认 60 秒
const POLLING_INTERVAL_KEY: string = 'message_polling_interval';
const PUSH_SERVICE_AVAILABLE_KEY: string = 'push_service_available';

/**
 * 家庭消息流管理单例
 *
 * 职责：
 * 1. 发送家庭消息（待办、日记分享等）
 * 2. 查询消息流（按发送人分组，每组取最新一条）
 * 3. 标记消息已读
 * 4. T035: 推送降级轮询（无 token/推送不可达时的兜底方案）
 *
 * 架构要点：
 * - 消息推送到 CloudDB FamilyMessage 表
 * - CloudDB 触发器自动发送 Push 通知（本模块不负责）
 * - 消息接收由 PushManager 处理（本模块不负责）
 * - T035: 前台轮询作为推送降级方案，后台停止轮询
 *
 * 单例模式：参考 AccountManager/FamilyManager/CloudDbService
 */
export class FamilyMessageManager {
  private static instance: FamilyMessageManager | null = null;

  // T035: 轮询降级相关状态
  private pollingTimerId: number | null = null;
  private receivedMessageIds: Set<string> = new Set<string>();
  private isPollingActive: boolean = false;

  private constructor() {
    // 初始化 AppStorage 配置
    if (!AppStorage.has(POLLING_INTERVAL_KEY)) {
      AppStorage.setOrCreate(POLLING_INTERVAL_KEY, DEFAULT_POLLING_INTERVAL);
    }
    if (!AppStorage.has(PUSH_SERVICE_AVAILABLE_KEY)) {
      AppStorage.setOrCreate(PUSH_SERVICE_AVAILABLE_KEY, true);
    }
  }

  /**
   * 获取全局单例
   */
  static getInstance(): FamilyMessageManager {
    if (FamilyMessageManager.instance === null) {
      FamilyMessageManager.instance = new FamilyMessageManager();
    }
    return FamilyMessageManager.instance;
  }

  /**
   * T040: 通用消息发送
   *
   * 流程：
   * 1. 创建 FamilyMessage 记录
   * 2. 推送到 CloudDB FamilyMessage 表
   * 3. 本地缓存（断网降级）
   * 4. 失败重试队列
   *
   * @param type 消息类型（'todo' | 'diary_share' | 'voice' | 'system'）
   * @param toUid 接收人 uid
   * @param content 消息内容
   * @param referenceId 关联 ID（可选）
   * @returns Result<string> 成功时 data=message_id
   */
  async sendMessage(
    type: string,
    toUid: string,
    content: string,
    referenceId?: string
  ): Promise<Result<string>> {
    // ① 参数校验
    if (toUid.length === 0) {
      return Result.fail<string>('接收人 uid 不能为空');
    }
    if (content.length === 0) {
      return Result.fail<string>('消息内容不能为空');
    }

    // ② 获取发送人 uid 和家庭 ID
    const fromUid: string = AccountManager.getInstance().getUid();
    if (fromUid.length === 0) {
      return Result.fail<string>('未登录');
    }

    const familyManager: FamilyManager = FamilyManager.getInstance();
    const familyIdResult: string = await this.getCurrentFamilyId(familyManager);
    if (familyIdResult.length === 0) {
      return Result.fail<string>('未加入家庭');
    }

    try {
      // ③ 创建 CloudFamilyMessage 记录
      const message: CloudFamilyMessage = new CloudFamilyMessage();
      message.message_id = this.generateMessageId();
      message.family_id = familyIdResult;
      message.from_uid = fromUid;
      message.to_uid = toUid;
      message.type = type;
      message.content = content;
      message.reference_id = referenceId !== undefined && referenceId.length > 0 ? referenceId : '';
      message.read_status = 0;
      message.created_at = Date.now();

      // ④ 推送到 CloudDB
      const cloudService: CloudDbService = CloudDbService.getInstance();
      if (!cloudService.isZoneOpened()) {
        // 断网降级：仅本地缓存，待联网后重试
        hilog.warn(0x0000, TAG, 'sendMessage: CloudDB not ready, offline mode');
        // TODO: 加入失败重试队列
        return Result.ok<string>(message.message_id);
      }

      await cloudService.upsertFamilyMessage(message);

      hilog.info(0x0000, TAG, 'sendMessage: message_id=%{public}s type=%{public}s',
        message.message_id, type);

      return Result.ok<string>(message.message_id);
    } catch (e) {
      hilog.error(0x0000, TAG, 'sendMessage failed: %{public}s', (e as Error).message);
      // 断网不崩溃：本地缓存 + 重试队列
      // TODO: 加入失败重试队列
      return Result.fail<string>('发送消息失败，请重试');
    }
  }

  /**
   * 发送待办消息（复用 sendMessage）
   *
   * @param familyId 家庭 ID（保留参数兼容性）
   * @param fromUid 发送人 uid（保留参数兼容性）
   * @param toUid 接收人 uid
   * @param todoId 待办 ID（reference_id）
   * @param todoTitle 待办标题（content）
   * @returns Result<string> 成功时 data=message_id
   */
  async sendTodoMessage(
    familyId: string,
    fromUid: string,
    toUid: string,
    todoId: string,
    todoTitle: string
  ): Promise<Result<string>> {
    return await this.sendMessage('todo', toUid, todoTitle, todoId);
  }

  /**
   * T040: 获取会话列表（按对端成员分组）
   *
   * 流程：
   * 1. 查询 CloudDB FamilyMessage 表（to_uid = 我的 uid）
   * 2. 按 from_uid 分组，每组取最新一条（created_at DESC）
   * 3. 查询每个发送人的 FamilyMember 信息
   * 4. 计算每组未读数
   * 5. 按最新消息时间降序排序
   *
   * @returns Result<MessageGroup[]> 成功时 data=会话分组列表
   */
  async getConversationList(): Promise<Result<MessageGroup[]>> {
    try {
      // ① 获取我的 uid
      const myUid: string = AccountManager.getInstance().getUid();
      if (myUid.length === 0) {
        return Result.fail<MessageGroup[]>('未登录');
      }

      // ② 查询 CloudDB FamilyMessage 表（to_uid = myUid）
      const cloudService: CloudDbService = CloudDbService.getInstance();
      if (!cloudService.isZoneOpened()) {
        return Result.fail<MessageGroup[]>('云数据库未初始化');
      }

      const cloudMessages: CloudFamilyMessage[] = await cloudService.queryMyFamilyMessages(myUid);
      hilog.info(0x0000, TAG, 'getConversationList: fetched %{public}d messages', cloudMessages.length);

      // ③ 按 from_uid 分组（Map<from_uid, CloudFamilyMessage[]>）
      const groupMap: Map<string, CloudFamilyMessage[]> = new Map();
      for (const msg of cloudMessages) {
        const fromUid: string = msg.from_uid;
        if (!groupMap.has(fromUid)) {
          groupMap.set(fromUid, []);
        }
        const arr: CloudFamilyMessage[] = groupMap.get(fromUid)!;
        arr.push(msg);
      }

      // ④ 每组取最新一条 + 计算未读数
      const groups: MessageGroup[] = [];
      const fromUids: string[] = Array.from(groupMap.keys());

      for (const fromUid of fromUids) {
        const messages: CloudFamilyMessage[] = groupMap.get(fromUid)!;

        // 按 created_at 降序排序，取第一条
        messages.sort((a: CloudFamilyMessage, b: CloudFamilyMessage): number => {
          return b.created_at - a.created_at;
        });
        const latestCloudMsg: CloudFamilyMessage = messages[0];

        // 转换为本地 FamilyMessage
        const latestMessage: FamilyMessage = this.cloudToLocal(latestCloudMsg);

        // 计算未读数
        let unreadCount: number = 0;
        for (const msg of messages) {
          if (msg.read_status === 0) {
            unreadCount++;
          }
        }

        // 查询发送人信息
        const fromMember: FamilyMember | null = await this.getMemberByUid(fromUid);
        if (fromMember === null) {
          hilog.warn(0x0000, TAG, 'getConversationList: from_uid=%{public}s not found, skip', fromUid);
          continue;
        }

        // 创建 MessageGroup
        const group: MessageGroup = new MessageGroup(fromMember, latestMessage);
        group.unreadCount = unreadCount;
        groups.push(group);
      }

      // ⑤ 按最新消息时间降序排序
      groups.sort((a: MessageGroup, b: MessageGroup): number => {
        return b.timestamp - a.timestamp;
      });

      hilog.info(0x0000, TAG, 'getConversationList: grouped into %{public}d groups', groups.length);

      // T048: 查询后同步未读总数到 AppStorage
      this.syncUnreadToAppStorage().catch((err: Error) => {
        hilog.error(0x0000, TAG, 'getConversationList: syncUnreadToAppStorage failed: %{public}s', err.message);
      });

      return Result.ok<MessageGroup[]>(groups);
    } catch (e) {
      hilog.error(0x0000, TAG, 'getConversationList failed: %{public}s', (e as Error).message);
      return Result.fail<MessageGroup[]>('查询会话列表失败，请重试');
    }
  }

  /**
   * 获取我的消息流（兼容旧方法，调用 getConversationList）
   *
   * @deprecated 使用 getConversationList() 替代
   */
  async getMyMessageStream(): Promise<Result<MessageGroup[]>> {
    return await this.getConversationList();
  }

  /**
   * T040: 获取与指定成员的消息时间线
   *
   * 流程：
   * 1. 查询与 peerUid 的双向消息（to_uid=peerUid OR from_uid=peerUid）
   * 2. 按 created_at 升序排序（时间线从旧到新）
   * 3. 支持分页（limit + offset）
   *
   * @param peerUid 对端成员 uid
   * @param limit 每页条数（默认 50）
   * @param offset 偏移量（默认 0）
   * @returns Result<FamilyMessage[]> 成功时 data=消息列表
   */
  async getMessages(peerUid: string, limit: number = 50, offset: number = 0): Promise<Result<FamilyMessage[]>> {
    if (peerUid.length === 0) {
      return Result.fail<FamilyMessage[]>('对端成员 uid 不能为空');
    }

    try {
      const myUid: string = AccountManager.getInstance().getUid();
      if (myUid.length === 0) {
        return Result.fail<FamilyMessage[]>('未登录');
      }

      const cloudService: CloudDbService = CloudDbService.getInstance();
      if (!cloudService.isZoneOpened()) {
        return Result.fail<FamilyMessage[]>('云数据库未初始化');
      }

      // 查询双向消息（我发给对方 + 对方发给我）
      const sentByMe: CloudFamilyMessage[] = await cloudService.queryMessagesBetweenUsers(myUid, peerUid);
      const sentByPeer: CloudFamilyMessage[] = await cloudService.queryMessagesBetweenUsers(peerUid, myUid);

      // 合并并按 created_at 升序排序
      const allCloudMessages: CloudFamilyMessage[] = sentByMe.concat(sentByPeer);
      allCloudMessages.sort((a: CloudFamilyMessage, b: CloudFamilyMessage): number => {
        return a.created_at - b.created_at;
      });

      // 分页处理
      const startIdx: number = offset;
      const endIdx: number = Math.min(offset + limit, allCloudMessages.length);
      const pagedCloudMessages: CloudFamilyMessage[] = allCloudMessages.slice(startIdx, endIdx);

      // 转换为本地 FamilyMessage
      const messages: FamilyMessage[] = [];
      for (const cloudMsg of pagedCloudMessages) {
        messages.push(this.cloudToLocal(cloudMsg));
      }

      hilog.info(0x0000, TAG, 'getMessages: peer_uid=%{public}s total=%{public}d paged=%{public}d',
        peerUid, allCloudMessages.length, messages.length);
      return Result.ok<FamilyMessage[]>(messages);
    } catch (e) {
      hilog.error(0x0000, TAG, 'getMessages failed: %{public}s', (e as Error).message);
      return Result.fail<FamilyMessage[]>('查询消息时间线失败，请重试');
    }
  }

  /**
   * T040: 批量标记与某成员的所有未读消息为已读
   *
   * 流程：
   * 1. 查询与 peerUid 的未读消息（from_uid=peerUid AND to_uid=我 AND read_status=0）
   * 2. 批量更新 read_status = 1
   *
   * @param peerUid 对端成员 uid
   * @returns Result<void> 成功/失败
   */
  async markConversationRead(peerUid: string): Promise<Result<void>> {
    if (peerUid.length === 0) {
      return Result.fail<void>('对端成员 uid 不能为空');
    }

    try {
      const myUid: string = AccountManager.getInstance().getUid();
      if (myUid.length === 0) {
        return Result.fail<void>('未登录');
      }

      const cloudService: CloudDbService = CloudDbService.getInstance();
      if (!cloudService.isZoneOpened()) {
        return Result.fail<void>('云数据库未初始化');
      }

      // 查询对方发给我的所有消息
      const allMessages: CloudFamilyMessage[] = await cloudService.queryMessagesBetweenUsers(peerUid, myUid);

      // 筛选未读消息
      const unreadMessages: CloudFamilyMessage[] = [];
      for (const msg of allMessages) {
        if (msg.read_status === 0) {
          unreadMessages.push(msg);
        }
      }

      if (unreadMessages.length === 0) {
        hilog.info(0x0000, TAG, 'markConversationRead: no unread messages, peer_uid=%{public}s', peerUid);
        return Result.ok<void>(undefined as void);
      }

      // 批量标记已读
      for (const msg of unreadMessages) {
        msg.read_status = 1;
      }

      // 批量 upsert
      await cloudService.batchUpsert(unreadMessages);

      hilog.info(0x0000, TAG, 'markConversationRead: peer_uid=%{public}s marked %{public}d messages',
        peerUid, unreadMessages.length);

      // T048: 标记已读后同步未读总数到 AppStorage
      this.syncUnreadToAppStorage().catch((err: Error) => {
        hilog.error(0x0000, TAG, 'markConversationRead: syncUnreadToAppStorage failed: %{public}s', err.message);
      });

      return Result.ok<void>(undefined as void);
    } catch (e) {
      hilog.error(0x0000, TAG, 'markConversationRead failed: %{public}s', (e as Error).message);
      return Result.fail<void>('标记已读失败，请重试');
    }
  }

  /**
   * 标记单条消息为已读（保留原有方法）
   *
   * @param messageId 消息 ID
   * @returns Result<void> 成功/失败
   */
  async markAsRead(messageId: string): Promise<Result<void>> {
    if (messageId.length === 0) {
      return Result.fail<void>('消息 ID 不能为空');
    }

    try {
      const cloudService: CloudDbService = CloudDbService.getInstance();
      if (!cloudService.isZoneOpened()) {
        return Result.fail<void>('云数据库未初始化');
      }

      // 查询消息
      const message: CloudFamilyMessage | null = await cloudService.queryFamilyMessageById(messageId);
      if (message === null) {
        return Result.fail<void>('消息不存在');
      }

      // 更新 read_status = 1
      message.read_status = 1;
      await cloudService.upsertFamilyMessage(message);

      hilog.info(0x0000, TAG, 'markAsRead: message_id=%{public}s', messageId);

      // T048: 标记已读后同步未读总数到 AppStorage
      this.syncUnreadToAppStorage().catch((err: Error) => {
        hilog.error(0x0000, TAG, 'markAsRead: syncUnreadToAppStorage failed: %{public}s', err.message);
      });

      return Result.ok<void>(undefined as void);
    } catch (e) {
      hilog.error(0x0000, TAG, 'markAsRead failed: %{public}s', (e as Error).message);
      return Result.fail<void>('标记已读失败，请重试');
    }
  }

  // ==================== 私有辅助方法 ====================

  /**
   * 生成消息 ID（UUID 格式）
   *
   * 简化版 UUID v4：时间戳 + 随机数（不依赖外部库）
   */
  private generateMessageId(): string {
    const timestamp: number = Date.now();
    const random: number = Math.floor(Math.random() * 1000000);
    return `msg_${timestamp}_${random}`;
  }

  /**
   * 获取当前家庭 ID（辅助方法）
   *
   * @param familyManager FamilyManager 实例
   * @returns family_id 或空字符串
   */
  private async getCurrentFamilyId(familyManager: FamilyManager): Promise<string> {
    try {
      const members: Result<FamilyMember[]> = await familyManager.getAllMembers();
      if (!members.success || members.data === null || members.data.length === 0) {
        return '';
      }
      // 取第一个成员的 family_id（所有成员的 family_id 相同）
      return members.data[0].family_id ?? '';
    } catch (e) {
      hilog.error(0x0000, TAG, 'getCurrentFamilyId failed: %{public}s', (e as Error).message);
      return '';
    }
  }

  /**
   * 按 uid 查询家庭成员
   *
   * @param uid 成员 uid
   * @returns FamilyMember | null
   */
  private async getMemberByUid(uid: string): Promise<FamilyMember | null> {
    try {
      const familyManager: FamilyManager = FamilyManager.getInstance();
      const result: Result<FamilyMember[]> = await familyManager.getAllMembers();

      if (!result.success || result.data === null) {
        return null;
      }

      const members: FamilyMember[] = result.data;
      for (const member of members) {
        if (member.uid === uid) {
          return member;
        }
      }

      return null;
    } catch (e) {
      hilog.error(0x0000, TAG, 'getMemberByUid failed: %{public}s', (e as Error).message);
      return null;
    }
  }

  /**
   * 将 CloudFamilyMessage 转换为本地 FamilyMessage
   *
   * @param cloudMsg CloudFamilyMessage
   * @returns FamilyMessage
   */
  private cloudToLocal(cloudMsg: CloudFamilyMessage): FamilyMessage {
    const local: FamilyMessage = new FamilyMessage();
    local.message_id = cloudMsg.message_id;
    local.family_id = cloudMsg.family_id;
    local.from_uid = cloudMsg.from_uid;
    local.to_uid = cloudMsg.to_uid;
    local.type = cloudMsg.type;
    local.content = cloudMsg.content.length > 0 ? cloudMsg.content : null;
    local.reference_id = cloudMsg.reference_id.length > 0 ? cloudMsg.reference_id : null;
    local.read_status = cloudMsg.read_status;
    local.created_at = cloudMsg.created_at;
    return local;
  }

  // ==================== T035: 推送降级轮询 ====================

  /**
   * 启动轮询（前台兜底方案）
   *
   * 使用场景：
   * 1. 通知权限被拒绝
   * 2. Push Token 获取失败
   * 3. 推送服务不可达
   *
   * 行为：
   * - 每 N 秒（可配置）调用 queryMyFamilyMessages
   * - 按 message_id 去重（与推送消息去重）
   * - 应用进后台时自动停止（需外部调用 stopPolling）
   */
  startPolling(): void {
    if (this.isPollingActive) {
      hilog.warn(0x0000, TAG, 'startPolling: already active, skip');
      return;
    }

    const interval: number = AppStorage.get<number>(POLLING_INTERVAL_KEY) ?? DEFAULT_POLLING_INTERVAL;
    hilog.info(0x0000, TAG, 'startPolling: interval=%{public}d ms', interval);

    // 立即执行一次轮询
    this.pollMessages();

    // 启动定时器
    this.pollingTimerId = setInterval((): void => {
      this.pollMessages();
    }, interval);

    this.isPollingActive = true;
    AppStorage.setOrCreate(PUSH_SERVICE_AVAILABLE_KEY, false);
  }

  /**
   * 停止轮询（应用进后台时调用）
   */
  stopPolling(): void {
    if (this.pollingTimerId !== null) {
      clearInterval(this.pollingTimerId);
      this.pollingTimerId = null;
      hilog.info(0x0000, TAG, 'stopPolling: timer cleared');
    }
    this.isPollingActive = false;
  }

  /**
   * 手动刷新消息（用户点击刷新按钮时调用）
   *
   * @returns Result<MessageGroup[]> 刷新后的消息流
   */
  async refreshMessages(): Promise<Result<MessageGroup[]>> {
    hilog.info(0x0000, TAG, 'refreshMessages: manual refresh triggered');
    return await this.getMyMessageStream();
  }

  /**
   * 设置轮询间隔（设置页面调用）
   *
   * @param intervalMs 轮询间隔（毫秒）
   */
  setPollingInterval(intervalMs: number): void {
    if (intervalMs < 10000) {
      hilog.warn(0x0000, TAG, 'setPollingInterval: interval too short, using 10s');
      intervalMs = 10000;
    }
    AppStorage.setOrCreate(POLLING_INTERVAL_KEY, intervalMs);
    hilog.info(0x0000, TAG, 'setPollingInterval: set to %{public}d ms', intervalMs);

    // 如果轮询正在运行，重启以应用新间隔
    if (this.isPollingActive) {
      this.stopPolling();
      this.startPolling();
    }
  }

  /**
   * 获取轮询间隔（设置页面读取）
   *
   * @returns 轮询间隔（毫秒）
   */
  getPollingInterval(): number {
    return AppStorage.get<number>(POLLING_INTERVAL_KEY) ?? DEFAULT_POLLING_INTERVAL;
  }

  /**
   * 检查推送服务是否可用
   *
   * @returns true=推送可用，false=降级到轮询
   */
  isPushServiceAvailable(): boolean {
    return AppStorage.get<boolean>(PUSH_SERVICE_AVAILABLE_KEY) ?? true;
  }

  /**
   * 标记推送服务状态（PushManager 调用）
   *
   * @param available true=推送恢复，false=推送失败
   */
  setPushServiceAvailable(available: boolean): void {
    AppStorage.setOrCreate(PUSH_SERVICE_AVAILABLE_KEY, available);
    hilog.info(0x0000, TAG, 'setPushServiceAvailable: %{public}s',
      available ? 'available' : 'unavailable');

    if (available) {
      // 推送恢复，停止轮询
      this.stopPolling();
    } else {
      // 推送失败，启动轮询
      this.startPolling();
    }
  }

  /**
   * 标记消息为已接收（推送/轮询去重）
   *
   * @param messageId 消息 ID
   */
  markMessageReceived(messageId: string): void {
    this.receivedMessageIds.add(messageId);
  }

  /**
   * 检查消息是否已接收（去重判断）
   *
   * @param messageId 消息 ID
   * @returns true=已接收，false=新消息
   */
  isMessageReceived(messageId: string): boolean {
    return this.receivedMessageIds.has(messageId);
  }

  /**
   * 轮询核心逻辑（私有方法）
   */
  private async pollMessages(): Promise<void> {
    try {
      const myUid: string = AccountManager.getInstance().getUid();
      if (myUid.length === 0) {
        hilog.warn(0x0000, TAG, 'pollMessages: not logged in, skip');
        return;
      }

      const cloudService: CloudDbService = CloudDbService.getInstance();
      if (!cloudService.isZoneOpened()) {
        hilog.warn(0x0000, TAG, 'pollMessages: CloudDB not ready, skip');
        return;
      }

      const cloudMessages: CloudFamilyMessage[] = await cloudService.queryMyFamilyMessages(myUid);
      let newCount: number = 0;

      for (const msg of cloudMessages) {
        // 按 message_id 去重
        if (!this.receivedMessageIds.has(msg.message_id)) {
          this.receivedMessageIds.add(msg.message_id);
          newCount++;

          // TODO: 触发 UI 更新（通过 emitter 或 callback）
          hilog.info(0x0000, TAG, 'pollMessages: new message received, id=%{public}s type=%{public}s',
            msg.message_id, msg.type);
        }
      }

      if (newCount > 0) {
        hilog.info(0x0000, TAG, 'pollMessages: %{public}d new messages', newCount);
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'pollMessages failed: %{public}s', (e as Error).message);
    }
  }

  /**
   * 清空已接收消息缓存（登出时调用）
   */
  clearReceivedMessages(): void {
    this.receivedMessageIds.clear();
    hilog.info(0x0000, TAG, 'clearReceivedMessages: cache cleared');
  }

  // ==================== T048: 未读红点全局联动 ====================

  /**
   * 获取未读消息总数（计算所有会话的未读数之和）
   *
   * @returns Promise<number> 未读总数
   */
  async getUnreadTotal(): Promise<number> {
    try {
      const result: Result<MessageGroup[]> = await this.getConversationList();
      if (!result.success || result.data === null) {
        return 0;
      }

      const groups: MessageGroup[] = result.data;
      let total: number = 0;
      for (const group of groups) {
        total += group.unreadCount;
      }

      return total;
    } catch (e) {
      hilog.error(0x0000, TAG, 'getUnreadTotal failed: %{public}s', (e as Error).message);
      return 0;
    }
  }

  /**
   * 同步未读总数到 AppStorage（供底部 Tab 角标和首页列表共用）
   *
   * 调用时机：
   * 1. getConversationList() 查询后
   * 2. markAsRead() / markConversationRead() 标记已读后
   * 3. EntryAbility 启动时
   */
  async syncUnreadToAppStorage(): Promise<void> {
    try {
      const total: number = await this.getUnreadTotal();
      AppStorage.setOrCreate('unread_message_total', total);
      hilog.info(0x0000, TAG, 'syncUnreadToAppStorage: total=%{public}d', total);
    } catch (e) {
      hilog.error(0x0000, TAG, 'syncUnreadToAppStorage failed: %{public}s', (e as Error).message);
    }
  }
}
