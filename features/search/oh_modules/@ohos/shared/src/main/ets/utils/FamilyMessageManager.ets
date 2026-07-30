// agentID: DEV-013
// File: FamilyMessageManager.ets
// Task: T032 家庭消息流管理单例 —— 发送/接收/查询家庭消息
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

/**
 * 家庭消息流管理单例
 *
 * 职责：
 * 1. 发送家庭消息（待办、日记分享等）
 * 2. 查询消息流（按发送人分组，每组取最新一条）
 * 3. 标记消息已读
 *
 * 架构要点：
 * - 消息推送到 CloudDB FamilyMessage 表
 * - CloudDB 触发器自动发送 Push 通知（本模块不负责）
 * - 消息接收由 PushManager 处理（本模块不负责）
 *
 * 单例模式：参考 AccountManager/FamilyManager/CloudDbService
 */
export class FamilyMessageManager {
  private static instance: FamilyMessageManager | null = null;

  private constructor() {
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
   * 发送待办消息
   *
   * 流程：
   * 1. 创建 FamilyMessage 记录（type='todo'）
   * 2. 推送到 CloudDB FamilyMessage 表
   * 3. CloudDB 触发器会自动发送 Push 通知（无需本方法处理）
   *
   * @param familyId 家庭 ID
   * @param fromUid 发送人 uid
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
    if (familyId.length === 0) {
      return Result.fail<string>('家庭 ID 不能为空');
    }
    if (fromUid.length === 0) {
      return Result.fail<string>('发送人 uid 不能为空');
    }
    if (toUid.length === 0) {
      return Result.fail<string>('接收人 uid 不能为空');
    }
    if (todoId.length === 0) {
      return Result.fail<string>('待办 ID 不能为空');
    }

    try {
      // ① 创建 CloudFamilyMessage 记录
      const message: CloudFamilyMessage = new CloudFamilyMessage();
      message.message_id = this.generateMessageId();
      message.family_id = familyId;
      message.from_uid = fromUid;
      message.to_uid = toUid;
      message.type = 'todo';
      message.content = todoTitle;
      message.reference_id = todoId;
      message.read_status = 0;
      message.created_at = Date.now();

      // ② 推送到 CloudDB
      const cloudService: CloudDbService = CloudDbService.getInstance();
      if (!cloudService.isZoneOpened()) {
        return Result.fail<string>('云数据库未初始化');
      }

      await cloudService.upsertFamilyMessage(message);

      // 注意：CloudDB 触发器会自动发送 Push 通知，本方法无需处理
      hilog.info(0x0000, TAG, 'sendTodoMessage: message_id=%{public}s todo_id=%{public}s',
        message.message_id, todoId);

      return Result.ok<string>(message.message_id);
    } catch (e) {
      hilog.error(0x0000, TAG, 'sendTodoMessage failed: %{public}s', (e as Error).message);
      return Result.fail<string>('发送消息失败，请重试');
    }
  }

  /**
   * 获取我的消息流（按发送人分组，每组取最新一条）
   *
   * 流程：
   * 1. 查询 CloudDB FamilyMessage 表（to_uid = 我的 uid）
   * 2. 按 from_uid 分组，每组取最新一条（created_at DESC）
   * 3. 查询每个发送人的 FamilyMember 信息
   * 4. 计算每组未读数
   * 5. 按最新消息时间降序排序
   *
   * @returns Result<MessageGroup[]> 成功时 data=消息分组列表
   */
  async getMyMessageStream(): Promise<Result<MessageGroup[]>> {
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
      hilog.info(0x0000, TAG, 'getMyMessageStream: fetched %{public}d messages', cloudMessages.length);

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
          hilog.warn(0x0000, TAG, 'getMyMessageStream: from_uid=%{public}s not found, skip', fromUid);
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

      hilog.info(0x0000, TAG, 'getMyMessageStream: grouped into %{public}d groups', groups.length);
      return Result.ok<MessageGroup[]>(groups);
    } catch (e) {
      hilog.error(0x0000, TAG, 'getMyMessageStream failed: %{public}s', (e as Error).message);
      return Result.fail<MessageGroup[]>('查询消息流失败，请重试');
    }
  }

  /**
   * 标记消息为已读
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
}
