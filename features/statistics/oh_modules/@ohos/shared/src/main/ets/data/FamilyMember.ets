// <!-- agentID: DEV-011 -->
// <!-- agentID: DEV-FAMILY -->
// File: FamilyMember.ets
// Task: 家庭成员实体 —— family_member 表（v4→v5 迁移新增）；todo.assignee_member_id 指派外键（逻辑引用，不建 FK 约束，先例：happy_thing.emoji_id）
// 合规(§8.2): 时间戳 INTEGER、snake_case 列名；aliases 以 JSON 字符串落库（RDB 无对象列型，先例：todo.custom_tags / diary.images）
// T707: aliases 格式重构 —— 从 string[] 改为 Record<string,string>（targetUid → alias 映射），存在「我自己」的 FamilyMember 记录里
export class FamilyMember {
  id: number = 0;
  /** 服务端用户 uid（未绑定账号的本地成员为 null） */
  uid: string | null = null;
  /** 成员昵称（展示名） */
  nickname: string = '';
  /** 别名 JSON 对象字符串（Record<targetUid, alias>，如 '{"uid_xxx":"奶奶"}'），恒非 null，默认 '{}' */
  aliases: string = '{}';
  /** 家庭角色（如 'owner'|'member'），默认 'member' */
  role: string = 'member';
  /** 手机号（null=未填写） */
  phone: string | null = null;
  /** 推送 token（null=未注册推送） */
  push_token: string | null = null;
  /** 所属家庭组 id（null=未加入家庭） */
  family_id: string | null = null;
  /** 是否本机用户自己（0/1，一个家庭内本机仅一条 is_self=1） */
  is_self: number = 0;
  created_at: number = 0;

  constructor(nickname?: string, role?: string, family_id?: string) {
    if (nickname) { this.nickname = nickname; }
    if (role) { this.role = role; }
    if (family_id) { this.family_id = family_id; }
    this.created_at = Date.now();
  }

  isSelf(): boolean {
    return this.is_self === 1;
  }

  /** T707: 解析别名 —— 返回 targetUid→alias 映射；损坏 JSON / 旧格式数组 防御性回退空对象 */
  getAliases(): Record<string, string> {
    try {
      const parsed = JSON.parse(this.aliases) as Record<string, string>;
      if (typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)) {
        return parsed;
      }
      return {};
    } catch (_e) {
      return {};
    }
  }

  /** T707: 序列化别名（统一入口，保证 aliases 恒为合法 JSON 对象字符串） */
  setAliases(aliases: Record<string, string>): void {
    this.aliases = JSON.stringify(aliases);
  }

  /** 昵称或任一别名是否命中（用于 AI 抽取任务时按称呼匹配成员） */
  matchesName(name: string): boolean {
    if (!name) {
      return false;
    }
    if (this.nickname === name) {
      return true;
    }
    const aliases = this.getAliases();
    const keys: string[] = Object.keys(aliases);
    for (let i = 0; i < keys.length; i++) {
      if (aliases[keys[i]] === name) {
        return true;
      }
    }
    return false;
  }
}
