// <!-- agentID: DEV-011 -->
// <!-- agentID: DEV-010 -->
// <!-- agentID: HUI-069 + DEV-204 -->
// ViewModel：家庭成员数据管理（走 FamilyManager DAO 持久化）
// T602(DEV-010) HJDG-001 重审 fix: 删 myInviteCode 静态缓存，改云端查询（getMyFamilyInviteCode）为真源；
//   generateInviteCode 每次 async 查云端 → 已有返回已有码，无则创建并 await 云端写入；
//   joinFamily 同理 async 走 joinFamilyByCode 云端验证。
// T706(DEV-011): 去掉硬编码「我」，改用 AccountManager.getCurrentNickname()
// T707(DEV-011): aliases 重构 —— 新增 getMyAliases / setAlias 方法
// 关联规范：PROJECT_SPEC §8 ArkTS 严格模式（class 模型、显式类型、禁 any）

import { FamilyManager, AccountManager, Result, FamilyMember, type CreateFamilyResult, type JoinFamilyResult } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 家庭成员业务 VM（委托 FamilyManager DAO 持久化 + 邀请码逻辑） */
export class FamilyViewModel {
  /** 已加入的他人家庭邀请码（'' = 未加入） */
  private static joinedInviteCode: string = '';

  /** 获取成员列表（走 FamilyManager DAO） */
  static async getMembers(): Promise<FamilyMember[]> {
    const res: Result<FamilyMember[]> = await FamilyManager.getInstance().getAllMembers();
    if (res.success && res.data !== null) {
      return res.data;
    }
    return [];
  }

  /** 添加成员（走 FamilyManager DAO 持久化；空昵称拒绝，返回 null） */
  static async addMember(nickname: string): Promise<FamilyMember | null> {
    const name: string = nickname.trim();
    if (name.length === 0) {
      return null;
    }
    const member: FamilyMember = new FamilyMember();
    member.nickname = name;
    member.is_self = 1;
    const res: Result<number> = await FamilyManager.getInstance().addMember(member);
    if (res.success && res.data !== null && res.data > 0) {
      member.id = res.data;
      return member;
    }
    return null;
  }

  /** 更新成员昵称（走 FamilyManager DAO；成功返回 true） */
  static async updateNickname(id: number, nickname: string): Promise<boolean> {
    const name: string = nickname.trim();
    if (name.length === 0) {
      return false;
    }
    const allRes: Result<FamilyMember[]> = await FamilyManager.getInstance().getAllMembers();
    if (!allRes.success || allRes.data === null) {
      return false;
    }
    for (let i = 0; i < allRes.data.length; i++) {
      if (allRes.data[i].id === id) {
        allRes.data[i].nickname = name;
        const updRes: Result<number> = await FamilyManager.getInstance().updateMember(allRes.data[i]);
        return updRes.success && updRes.data !== null && updRes.data > 0;
      }
    }
    return false;
  }

  // ── T707 aliases 备注方法 ──

  /**
   * T707: 获取我的 aliases 映射（我对别人的备注 targetUid → alias）。
   * @returns Record<string, string> 空对象 = 未设置本机成员或无备注
   */
  static async getMyAliases(): Promise<Record<string, string>> {
    return FamilyManager.getInstance().getMyAliases();
  }

  /**
   * T707: 设置我对某成员的备注名（更新我自己的 aliases）。
   * @param targetUid 被备注成员的 uid
   * @param alias 备注名（空字符串 = 清除备注）
   * @returns true=成功, false=失败
   */
  static async setAlias(targetUid: string, alias: string): Promise<boolean> {
    const res: Result<void> = await FamilyManager.getInstance().setAlias(targetUid, alias);
    return res.success;
  }

  // ── 邀请码（HJDG-001 重审：删 myInviteCode 缓存，真源=Cloud DB Family 表；generateInviteCode/getMyInviteCode 均改 async 查云端） ──

  /**
   * 获取本家庭邀请码（async 查云端；'' = 未创建家庭或查询失败）。
   * 等价于 generateInviteCode 但不主动创建——仅查询云端已有记录。
   */
  static async getMyInviteCode(): Promise<string> {
    const acct = AccountManager.getInstance();
    if (!acct.isLoggedIn()) {
      return '';
    }
    return FamilyManager.getInstance().getMyFamilyInviteCode(acct.getUid());
  }

  /** 获取已加入的家庭邀请码（'' = 未加入） */
  static getJoinedInviteCode(): string {
    return FamilyViewModel.joinedInviteCode;
  }

  /**
   * 生成本家庭邀请码（async）：
   * ① 查云端 Family 表（owner_uid == self.uid）→ 已有则直接返回邀请码（真源，不重复建家）
   * ② 无则生成 6 位码 → await createFamily（内部写本地 + await 写云）→ 成功返回码，失败返回空串
   *
   * 无本地 static 缓存——真源是云端，每次调用均以云端为准。
   */
  static async generateInviteCode(): Promise<string> {
    const acct = AccountManager.getInstance();
    if (!acct.isLoggedIn()) {
      return '';
    }
    const uid: string = acct.getUid();
    if (uid.length === 0) {
      return '';
    }

    // ① 云端查重：已有家庭 → 直接返回真源邀请码
    const existingCode: string = await FamilyManager.getInstance().getMyFamilyInviteCode(uid);
    if (existingCode.length > 0) {
      hilog.info(0x0000, 'FamilyViewModel', 'generateInviteCode: family exists in cloud, return existing code');
      return existingCode;
    }

    // ② 无家庭 → 生成新码 + 创建
    let code: string = '';
    const cs: string = FamilyManager.CODE_CHARSET;
    const clen: number = FamilyManager.CODE_LENGTH;
    for (let i = 0; i < clen; i++) {
      const idx: number = Math.floor(Math.random() * cs.length);
      code += cs.charAt(idx);
    }

    // T706: 获取本机昵称 —— 优先 AccountManager.getCurrentNickname()（注册用户名/手机号脱敏），不再写「我」
    let selfNick: string = AccountManager.getInstance().getCurrentNickname();
    if (selfNick.length === 0) {
      try {
        const selfRes: Result<FamilyMember> = await FamilyManager.getInstance().getSelf();
        if (selfRes.success && selfRes.data !== null && selfRes.data.nickname.length > 0) {
          selfNick = selfRes.data.nickname;
        }
      } catch (e) {
        // getSelf 异常降级
      }
    }

    // createFamily 内部先写本地、再 await 写云——此处 await 拿到云端真实结果
    const res: Result<CreateFamilyResult> = await FamilyManager.getInstance()
      .createFamily(uid, selfNick, undefined, code);
    if (res.success && res.data !== null) {
      hilog.info(0x0000, 'FamilyViewModel', 'generateInviteCode ok: family_id=%{public}s', res.data.family_id);
      return res.data.invite_code;
    }
    hilog.error(0x0000, 'FamilyViewModel', 'generateInviteCode createFamily failed: %{public}s', res.message);
    return '';
  }

  /**
   * 重新生成邀请码（async；无缓存可清，直接重新走云端查重+创建流程）。
   */
  static async regenerateInviteCode(): Promise<string> {
    return FamilyViewModel.generateInviteCode();
  }

  /** 邀请码格式校验（6 位，限定字符集，委托 FamilyManager 统一逻辑） */
  static isValidInviteCode(code: string): boolean {
    return FamilyManager.isValidInviteCode(code);
  }

  /**
   * T603 通过邀请码加入家庭（async 云端验证）。
   * HJDG-001 重审: 自建保护由 joinFamilyByCode 的 family.owner_uid === uid 校验兜底，
   * 不再依赖已删除的 myInviteCode 本地缓存。
   *
   * @returns '' = 加入成功；非空 = 失败原因（可直接用于 Toast/弹窗提示）
   */
  static async joinFamily(code: string): Promise<string> {
    const c: string = code.trim().toUpperCase();
    if (!FamilyManager.isValidInviteCode(c)) {
      return '邀请码格式不正确，应为 6 位字母数字';
    }
    if (FamilyViewModel.joinedInviteCode.length > 0) {
      return '已加入家庭，请先退出再加入新家庭';
    }

    const acct = AccountManager.getInstance();
    if (!acct.isLoggedIn()) {
      return '未登录，无法加入家庭';
    }
    const uid: string = acct.getUid();
    if (uid.length === 0) {
      return '账号信息异常，请重新登录';
    }
    // T706: 获取本机昵称 —— 优先 AccountManager.getCurrentNickname()（注册用户名/手机号脱敏），不再写「我」
    let selfNick: string = AccountManager.getInstance().getCurrentNickname();
    if (selfNick.length === 0) {
      try {
        const selfRes: Result<FamilyMember> = await FamilyManager.getInstance().getSelf();
        if (selfRes.success && selfRes.data !== null && selfRes.data.nickname.length > 0) {
          selfNick = selfRes.data.nickname;
        }
      } catch (e) {
        // getSelf 异常降级
      }
    }

    const res: Result<JoinFamilyResult> = await FamilyManager.getInstance().joinFamilyByCode(c, uid, selfNick);
    if (res.success && res.data !== null) {
      FamilyViewModel.joinedInviteCode = c;
      hilog.info(0x0000, 'FamilyViewModel', 'joinFamily ok: family_id=%{public}s', res.data.family_id);
      return '';
    }
    return res.message.length > 0 ? res.message : '云端验证失败，请稍后重试';
  }

  /** 退出已加入的家庭（清空已加入邀请码） */
  static leaveFamily(): void {
    FamilyViewModel.joinedInviteCode = '';
  }
}
