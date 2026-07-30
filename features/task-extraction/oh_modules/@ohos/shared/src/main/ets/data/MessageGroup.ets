// agentID: DEV-013
// File: MessageGroup.ets
// Task: T032 家庭消息流分组模型 —— 消息列表 UI 展示用
// 关联架构: REFACTOR_ARCHITECTURE.md §2 家庭消息流 → getMyMessageStream() 返回类型
// 合规: ArkTS 严格模式，禁止 any/unknown

import { FamilyMessage } from './FamilyMessage';
import { FamilyMember } from './FamilyMember';

/**
 * 消息分组（按发送人分组，每组取最新一条）
 *
 * 用途：首页消息流展示
 *
 * 字段说明：
 * - fromMember: 发送人信息（FamilyMember，包含昵称、头像等）
 * - latestMessage: 该组最新一条消息
 * - unreadCount: 该组未读消息数
 * - timestamp: 最新消息时间戳（用于排序）
 */
export class MessageGroup {
  /** 发送人信息 */
  fromMember: FamilyMember;
  /** 该组最新一条消息 */
  latestMessage: FamilyMessage;
  /** 该组未读消息数 */
  unreadCount: number = 0;
  /** 最新消息时间戳（用于排序） */
  timestamp: number = 0;

  constructor(fromMember: FamilyMember, latestMessage: FamilyMessage) {
    this.fromMember = fromMember;
    this.latestMessage = latestMessage;
    this.timestamp = latestMessage.created_at;
  }

  /**
   * 获取显示名称（优先备注名，否则昵称）
   */
  getDisplayName(): string {
    return this.fromMember.nickname;
  }

  /**
   * 是否有未读消息
   */
  hasUnread(): boolean {
    return this.unreadCount > 0;
  }

  /**
   * 获取消息预览文本
   */
  getPreviewText(): string {
    if (this.latestMessage.content !== null && this.latestMessage.content.length > 0) {
      return this.latestMessage.content;
    }
    // 根据消息类型返回默认文本
    switch (this.latestMessage.type) {
      case 'todo':
        return '[待办消息]';
      case 'diary_share':
        return '[日记分享]';
      case 'voice':
        return '[语音消息]';
      case 'system':
        return '[系统通知]';
      default:
        return '[消息]';
    }
  }
}
