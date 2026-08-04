// <!-- agentID: DEV-DB -->
// File: CustomEmoji.ets
// Task: DB 缺口#8 - 自定义心情 emoji 库实体（custom_emoji 表）
// 关联设计: ARC-001_DB_DESIGN.md §4 缺口#8 / §5.5 v1→v2 迁移
// 字段对齐 DDL: type TEXT('emoji'|'image')、含 updated_at INTEGER；boolean 存 0/1

export class CustomEmoji {
  id: number = 0;
  /** 唯一标识；内置项 = 原始 emoji 字符（护老数据，可 join happy_thing.emoji_id）；图片项 = img_<createdAt> */
  emoji_key: string = '';
  /** 心情标签/显示名（如「开心」「难过」）*/
  label: string = '';
  /** 'emoji' = Unicode 表情字符 / 'image' = 用户导入图片 */
  type: string = 'emoji';
  /** type='emoji': 表情字符（与 emoji_key 同值）; type='image': 图片沙箱 URI */
  value: string = '';
  /** 展示排序 */
  sort_order: number = 0;
  /** 是否内置默认 emoji (0/1) */
  is_builtin: number = 0;
  created_at: number = 0;
  updated_at: number = 0;

  constructor(emoji_key?: string, label?: string, value?: string, type?: string) {
    if (emoji_key) { this.emoji_key = emoji_key; }
    if (label) { this.label = label; }
    if (value) { this.value = value; }
    if (type) { this.type = type; }
    const now = Date.now();
    this.created_at = now;
    this.updated_at = now;
  }
}
