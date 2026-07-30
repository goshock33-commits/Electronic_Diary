// agentID: DEV-013
// File: FamilyMessage.ets
// Task: T032 家庭消息流数据模型 —— CloudDB FamilyMessage 表实体
// 关联架构: REFACTOR_ARCHITECTURE.md §3 数据库架构变更 → CloudDB Schema v19
// 合规: ArkTS 严格模式，字段类型与 CloudDB Schema 完全一致

/**
 * 家庭消息流实体（对应 CloudDB FamilyMessage 表）
 *
 * 用途：家庭成员间的消息记录（待办指派、日记分享、语音提醒、系统通知）
 *
 * 字段说明：
 * - message_id: 主键（UUID，本地生成）
 * - family_id: 所属家庭 ID
 * - from_uid: 发送人 uid
 * - to_uid: 接收人 uid
 * - type: 消息类型（'todo' | 'diary_share' | 'voice' | 'system'）
 * - content: 消息内容（如待办标题）
 * - reference_id: 关联 ID（如 todo_id、diary_id）
 * - read_status: 已读状态（0=未读，1=已读）
 * - created_at: 创建时间戳
 */
export class FamilyMessage {
  /** 消息 ID（主键，UUID） */
  message_id: string = '';
  /** 所属家庭 ID */
  family_id: string = '';
  /** 发送人 uid */
  from_uid: string = '';
  /** 接收人 uid */
  to_uid: string = '';
  /** 消息类型（'todo' | 'diary_share' | 'voice' | 'system'） */
  type: string = 'todo';
  /** 消息内容 */
  content: string | null = null;
  /** 关联 ID（如 todo_id、diary_id） */
  reference_id: string | null = null;
  /** 已读状态（0=未读，1=已读） */
  read_status: number = 0;
  /** 创建时间戳 */
  created_at: number = 0;

  constructor() {
    this.created_at = Date.now();
  }

  /**
   * 标记为已读
   */
  markAsRead(): void {
    this.read_status = 1;
  }

  /**
   * 是否已读
   */
  isRead(): boolean {
    return this.read_status === 1;
  }

  /**
   * 是否未读
   */
  isUnread(): boolean {
    return this.read_status === 0;
  }
}
