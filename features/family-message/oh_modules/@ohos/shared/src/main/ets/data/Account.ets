// <!-- agentID: DEV+HUI -->
// File: Account.ets
// Task: Account entity - login state persistence
// Architecture: Shared data model for account table
// Dev paradigm: ArkTS declarative
// fix: DEV-006 · T013 用户资料 4 列（avatar/gender/birthday/bio），与 account 表新增列一一对应
//   （建列见 DatabaseHelper.ensureAccountProfileColumns；读写见 AccountDao）

/**
 * Account entity — persisted to account table.
 * Holds AGC Auth uid, phone, token, and login state.
 */
export class Account {
  id: number = 0;
  uid: string = '';
  phone: string = '';
  token: string = '';
  is_logged_in: number = 0;
  login_time: number = 0;
  created_at: number = 0;
  /** fix: DEV-006 · T013 头像 URL / 本地 file uri（null=未设置，UI 用默认头像兜底） */
  avatar: string | null = null;
  /** fix: DEV-006 · T013 性别（'male' | 'female' | 'other'，null=未填写） */
  gender: string | null = null;
  /** fix: DEV-006 · T013 生日 'YYYY-MM-DD'（TEXT 落库，null=未填写） */
  birthday: string | null = null;
  /** fix: DEV-006 · T013 个性签名（null=未填写） */
  bio: string | null = null;

  constructor(uid?: string, phone?: string, token?: string) {
    if (uid) { this.uid = uid; }
    if (phone) { this.phone = phone; }
    if (token) { this.token = token; }
    this.is_logged_in = 0;
    this.login_time = 0;
    this.created_at = Date.now();
  }
}
