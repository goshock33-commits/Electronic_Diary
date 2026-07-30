// <!-- agentID: DEV-001 -->
// <!-- agentID: DEV-003 --> ③待办编辑持久化：补 category 日程标签字段（HUI"分类未持久化"实锤——模型/表原先均无此字段）
// <!-- agentID: DEV-013 --> 待办提醒增强：补 due_date/due_time/location/custom_tags/remind_at/reminder_id
//   6 字段（表列自愈补列见 DatabaseHelper.ensureTodoReminderColumns；读写见 TodoDao）。
//   custom_tags 以 JSON 数组字符串落库（RDB 无数组列型，先例：diary.images TEXT DEFAULT '[]'）。
// fix: DEV-004 · T011 家庭待办字段：补 from_uid / is_family_todo
//   （表列见 DatabaseHelper.ensureTodoFamilyColumns；读写见 TodoDao insert/update/rowToTodoItem）
// Task: T002 TodoItem entity - architecture 5.2 table 3

export class TodoItem {
  id: number = 0;
  date: string = '';
  type: string = 'today';
  title: string = '';
  completed: number = 0;
  sort_order: number = 0;
  source_task_id: number | null = null;
  /** 日程标签（日常/学习/工作/日记/微信/语音），对齐 AddTodoDialog categoryOptions，默认'日常' */
  category: string = '日常';
  /** DEV-013 截止日期 "YYYY-MM-DD"（null=无截止日期） */
  due_date: string | null = null;
  /** DEV-013 截止时间 "HH:mm"（null=全天/未设时间） */
  due_time: string | null = null;
  /** DEV-013 地点（null=未设置） */
  location: string | null = null;
  /** DEV-013 自定义标签 JSON 数组字符串（如 '["买菜","顺路"]'），恒非 null，默认 '[]' */
  custom_tags: string = '[]';
  /** DEV-013 提醒触发时间戳（毫秒，null=不提醒） */
  remind_at: number | null = null;
  /** DEV-013 系统代理提醒 id（reminderAgentManager.publishReminder 返回值；null=未调度） */
  reminder_id: number | null = null;
  /** DEV-FAMILY 指派成员 id（逻辑引用 family_member.id；null=未指派） */
  assignee_member_id: number | null = null;
  /** T011 家庭待办发送人 uid（null=本人创建的个人待办） */
  from_uid: string | null = null;
  /** T011 是否家庭待办（0=个人 1=家庭互动待办） */
  is_family_todo: number = 0;
  created_at: number = 0;
  updated_at: number = 0;

  constructor(date?: string, title?: string, type?: string, category?: string) {
    if (date) { this.date = date; }
    if (title) { this.title = title; }
    if (type) { this.type = type; }
    if (category) { this.category = category; }
    this.created_at = Date.now();
    this.updated_at = Date.now();
  }

  isCompleted(): boolean { return this.completed === 1; }

  toggleComplete(): void {
    this.completed = this.completed === 1 ? 0 : 1;
    this.updated_at = Date.now();
  }

  /** DEV-013 是否设置了未来的提醒（remind_at 非空且在当前时刻之后） */
  hasPendingReminder(): boolean {
    return this.remind_at !== null && this.remind_at > Date.now();
  }

  /** DEV-013 解析自定义标签（损坏 JSON 防御性回退空数组，先例：AppSettings.getValueAsObject as 断言） */
  getCustomTags(): string[] {
    try {
      const parsed: string[] = JSON.parse(this.custom_tags) as string[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (_e) {
      return [];
    }
  }

  /** DEV-013 序列化自定义标签（统一入口，保证 custom_tags 恒为合法 JSON 数组字符串） */
  setCustomTags(tags: string[]): void {
    this.custom_tags = JSON.stringify(tags);
    this.updated_at = Date.now();
  }
}
