// <!-- agentID: DEV-AI-COMPANION -->
// File: ChatMessage.ets
// Task: AI伙伴(Mimi)对话历史落库 —— chat_message 表实体（v2→v3 迁移新增）
// 关联: ChatMessageDao / DatabaseHelper.migrateV2ToV3 / AIChatView 渲染
// 合规(§8.2): 时间戳 INTEGER、snake_case 列名；role 语义 'user'(用户右气泡) | 'ai'(Mimi 左气泡)
export class ChatMessage {
  id: number = 0;
  /** 会话分组，预留多会话；当前单会话固定 'default' */
  session_id: string = 'default';
  /** 'user' = 用户；'ai' = Mimi */
  role: string = 'ai';
  content: string = '';
  created_at: number = 0;

  constructor(role?: string, content?: string, session_id?: string) {
    if (role) { this.role = role; }
    if (content) { this.content = content; }
    if (session_id) { this.session_id = session_id; }
    this.created_at = Date.now();
  }

  isUser(): boolean {
    return this.role === 'user';
  }
}
