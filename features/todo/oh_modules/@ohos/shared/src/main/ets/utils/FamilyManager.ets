// <!-- agentID: DEV-011 -->
// <!-- agentID: DEV-010 -->
// <!-- agentID: DEV-FAMILY / DEV-CLOUD-CACHE -->
// <!-- agentID: DEV-012 -->
// File: FamilyManager.ets
// Task: 家庭成员业务层单例 —— 包装 FamilyMemberDao，统一 Result<T> 返回（不外抛异常）
// 单例范式对齐: TtsService（private constructor + static getInstance）
// 错误范式: DAO/DatabaseExecutor 失败外抛 Error → 此层 try/catch 收敛为 Result.fail，hilog.error 记录
// 别名匹配: 按 FamilyMemberDao.findByNickname 注释约定，业务层用 FamilyMember.matchesName 遍历 queryAll
// 云端接入(DEV-CLOUD-CACHE): 本地 SQLite 降级为缓存层，Cloud DB（CloudDbService.FamilyMember 表）为远端真源——
//   读路径 getAllMembers 先读本地立即返回，后台拉云端合并回本地缓存；
//   写路径 add/update/delete 本地成功后 fire-and-forget 推送云端。
//   zone 未开 / 云端失败仅 hilog 记录，不影响返回值 —— 接口签名与语义不变，页面无感。
// T602(DEV-010): createFamily + joinFamilyByCode 云端家庭创建与邀请码验证——Family 表直写 Cloud DB，
//   FamilyMember 双写云+本；邀请码 6 位去歧义字符。
// T705(DEV-011): init() 新设备登录从 Cloud DB 全量恢复家庭数据到本地
// T706(DEV-011): 去掉「我」硬编码 fallback，改用 AccountManager.getCurrentNickname()
// T707(DEV-011): aliases 重构（Record<string,string>）+ setAlias/getMyAliases + addMember uid 查重

import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { FamilyMemberDao } from '../database/dao/FamilyMemberDao';
import { FamilyMember } from '../data/FamilyMember';
import { CloudDbService, CloudFamily, CloudFamilyMember } from '../cloud/CloudDbService';
import { AccountManager } from './AccountManager';

const TAG = 'FamilyManager';

/**
 * 统一业务返回包装。
 * success=true 时 data 非 null（Result<T> 的 T 本身允许 null 除外）；
 * success=false 时 data 为 null，message 携带失败原因（可直接用于 UI 提示）。
 */
export class Result<T> {
  success: boolean = false;
  data: T | null = null;
  message: string = '';

  static ok<U>(data: U): Result<U> {
    const r = new Result<U>();
    r.success = true;
    r.data = data;
    return r;
  }

  static fail<U>(message: string): Result<U> {
    const r = new Result<U>();
    r.success = false;
    r.message = message;
    return r;
  }
}

/** T602: createFamily 成功返回体（code 侧 zone 自动用 ElectronicDiary） */
export interface CreateFamilyResult {
  family_id: string;
  invite_code: string;
  family_name: string;
}

/** T602: joinFamilyByCode 成功返回体 */
export interface JoinFamilyResult {
  family_id: string;
  family_name: string;
  owner_uid: string;
}

/**
 * FamilyManager —— 家庭成员管理单例。
 *
 * 用法:
 *   const mgr = FamilyManager.getInstance();
 *   const res = await mgr.addMember(new FamilyMember('妈妈', 'mom'));
 *   if (res.success) { ... } else { promptAction.showToast({ message: res.message }); }
 *
 * 所有方法不外抛异常，失败路径 hilog.error 并返回 Result.fail。
 */
export class FamilyManager {
  private static instance: FamilyManager | null = null;

  /** 云端拉取防重入标记（getAllMembers 高频调用时避免并发合并） */
  private cloudRefreshInFlight: boolean = false;

  private constructor() {
  }

  /** 获取全局单例。 */
  static getInstance(): FamilyManager {
    if (FamilyManager.instance === null) {
      FamilyManager.instance = new FamilyManager();
    }
    return FamilyManager.instance;
  }

  /**
   * T705: 新设备登录从 Cloud DB 全量恢复家庭数据到本地。
   * 调用时机：AccountManager.cacheLoginLocally 之后 / getAllMembers 首次调用时自动触发。
   * 幂等：本地已有成员数据则跳过。
   *
   * 恢复内容：
   * - 按 owner_uid = myUid 查 Cloud DB Family 表 → 取 family_id
   * - 按 family_id 拉 Cloud DB FamilyMember 表全量成员 → 批量写本地 family_member 表
   * - 自己的 FamilyMember 记录设置 is_self=1（通过 uid 匹配）
   */
  async init(): Promise<void> {
    const acct = AccountManager.getInstance();
    if (!acct.isLoggedIn()) {
      hilog.debug(0x0000, TAG, 'init skipped: not logged in');
      return;
    }
    const myUid: string = acct.getUid();
    if (myUid.length === 0) {
      hilog.debug(0x0000, TAG, 'init skipped: empty uid');
      return;
    }

    const svc = CloudDbService.getInstance();
    if (!svc.isZoneOpened()) {
      hilog.debug(0x0000, TAG, 'init skipped: cloud zone not opened');
      return;
    }

    try {
      // 本地数据归属校验：检查是否有当前用户的有效家庭数据
      const locals: FamilyMember[] = await FamilyMemberDao.queryAll();
      const validMembers = locals.filter((m: FamilyMember): boolean =>
        m.family_id !== null && m.family_id!.length > 0);

      if (validMembers.length > 0) {
        const hasMyRecord: boolean = validMembers.some((m: FamilyMember): boolean => m.uid === myUid);
        if (hasMyRecord) {
          hilog.debug(0x0000, TAG, 'init skipped: local cache has my valid record (%{public}d valid members)', validMembers.length);
          return;
        }
      }

      // 本地无有效数据或不属于当前用户（残留上一用户的脏数据），清空后全量恢复
      if (locals.length > 0) {
        hilog.warn(0x0000, TAG, 'init: clearing stale/invalid data (total=%{public}d, valid=%{public}d)',
          locals.length, validMembers.length);
        await FamilyMemberDao.deleteAll();
      } else {
        hilog.info(0x0000, TAG, 'init: local cache empty, restoring from cloud for uid=%{public}s', myUid);
      }

      // ① 查 Cloud DB Family 表（owner_uid = myUid）
      let familyId: string = '';
      const families: CloudFamily[] = await svc.queryFamiliesByOwner(myUid);
      if (families.length > 0) {
        familyId = families[0].family_id;
        hilog.info(0x0000, TAG, 'init: found owned family_id=%{public}s, pulling members...', familyId);
      } else {
        // DEV-012: fallback 按 member uid 查找（加入的家庭，非 owner）
        hilog.info(0x0000, TAG, 'init: no owned family, trying member lookup for uid=%{public}s', myUid);
        const myMember = await svc.queryFamilyMemberByUid(myUid);
        if (myMember !== null && myMember.family_id.length > 0) {
          familyId = myMember.family_id;
          hilog.info(0x0000, TAG, 'init: found joined family_id=%{public}s via member lookup', familyId);
        }
      }

      if (familyId.length === 0) {
        hilog.info(0x0000, TAG, 'init: no family found in cloud for uid=%{public}s', myUid);
        return;
      }

      // ② 拉 Cloud DB FamilyMember 全量成员
      const cloudMembers: CloudFamilyMember[] = await svc.queryFamilyMembers(familyId);
      hilog.info(0x0000, TAG, 'init: pulled %{public}d cloud members', cloudMembers.length);

      // ③ 批量写本地 family_member 表
      let restoredCount: number = 0;
      for (let i = 0; i < cloudMembers.length; i++) {
        const cloudMember: CloudFamilyMember = cloudMembers[i];
        const local: FamilyMember = FamilyManager.toLocalMember(cloudMember);
        // DEV-012: 云端旧数据 aliases 可能是旧格式 string[] 而非 Record<string,string>，入库前归一化
        try {
          const parsedAliases: object = JSON.parse(local.aliases) as object;
          if (parsedAliases === null || Array.isArray(parsedAliases)) {
            local.aliases = '{}';
          }
        } catch (_e) {
          local.aliases = '{}';
        }
        // 自己的记录设置 is_self=1（通过 uid 匹配，不依赖本地已有标记）
        if (local.uid === myUid) {
          local.is_self = 1;
        }
        try {
          await FamilyMemberDao.insert(local);
          restoredCount++;
        } catch (e) {
          hilog.warn(0x0000, TAG, 'init: insert member failed (may already exist): %{public}s',
            (e as Error).message);
        }
      }
      hilog.info(0x0000, TAG, 'init: restored %{public}d members to local cache', restoredCount);
    } catch (e) {
      hilog.error(0x0000, TAG, 'init failed: %{public}s', (e as Error).message);
    }
  }

  /**
   * 新增家庭成员（昵称去首尾空格；空昵称/重名拒绝）。
   * T707: 新增可选 uid 参数 —— 若传了 uid 则先 findByUid 查重，命中则 update 而非 insert（消灭 INSERT 代替 UPDATE Bug）。
   * @param member 待添加的成员
   * @param uid 可选：服务端用户 uid（传了则按 uid 查重做 upsert）
   * @returns Result<number> 成功时 data=行 id（insert 返回 rowId，update 返回已存在行的 id）
   */
  async addMember(member: FamilyMember, uid?: string): Promise<Result<number>> {
    const nickname = member.nickname.trim();
    if (nickname.length === 0) {
      return Result.fail<number>('昵称不能为空');
    }
    member.nickname = nickname;
    try {
      // T707: uid 查重 → update 而非 insert（消灭 INSERT 代替 UPDATE Bug）
      if (uid !== undefined && uid.length > 0) {
        const byUid = await FamilyMemberDao.findByUid(uid);
        if (byUid !== null) {
          // 已有记录：update 而非 insert
          byUid.nickname = nickname;
          byUid.role = member.role;
          byUid.aliases = member.aliases;
          byUid.phone = member.phone;
          byUid.push_token = member.push_token;
          byUid.family_id = member.family_id;
          byUid.is_self = member.is_self;
          const rows = await FamilyMemberDao.update(byUid);
          member.id = byUid.id;
          // T708: await 推云端，失败返回 fail 让调用方可感知
          await this.pushMemberToCloud(byUid);
          hilog.info(0x0000, TAG, 'addMember: uid matched → update id=%{public}d nickname=%{public}s', byUid.id, nickname);
          return Result.ok<number>(byUid.id);
        }
      }
      // 正常 insert 路径
      const existed = await FamilyMemberDao.findByNickname(nickname);
      if (existed !== null) {
        return Result.fail<number>(`成员"${nickname}"已存在`);
      }
      const rowId = await FamilyMemberDao.insert(member);
      member.id = rowId;
      // T708: await 推云端，失败抛异常由外层 catch 捕获 → Result.fail
      await this.pushMemberToCloud(member);
      hilog.info(0x0000, TAG, 'addMember: rowId=%{public}d nickname=%{public}s', rowId, nickname);
      return Result.ok<number>(rowId);
    } catch (e) {
      hilog.error(0x0000, TAG, 'addMember failed: %{public}s', (e as Error).message);
      return Result.fail<number>('添加成员失败，请重试');
    }
  }

  /**
   * 更新家庭成员（按 id 全量更新；id 不存在视为失败）。
   * @returns Result<number> 成功时 data=受影响行数（恒为 1）
   */
  async updateMember(member: FamilyMember): Promise<Result<number>> {
    const nickname = member.nickname.trim();
    if (nickname.length === 0) {
      return Result.fail<number>('昵称不能为空');
    }
    member.nickname = nickname;
    try {
      // 改名重名防御：同昵称已被其他 id 占用则拒绝
      const existed = await FamilyMemberDao.findByNickname(nickname);
      if (existed !== null && existed.id !== member.id) {
        return Result.fail<number>(`成员"${nickname}"已存在`);
      }
      const rows = await FamilyMemberDao.update(member);
      if (rows === 0) {
        return Result.fail<number>('成员不存在或已被删除');
      }
      // T708: await 推云端，失败抛异常由外层 catch 捕获 → Result.fail
      await this.pushMemberToCloud(member);
      hilog.info(0x0000, TAG, 'updateMember: id=%{public}d rows=%{public}d', member.id, rows);
      return Result.ok<number>(rows);
    } catch (e) {
      hilog.error(0x0000, TAG, 'updateMember failed: %{public}s', (e as Error).message);
      return Result.fail<number>('更新成员失败，请重试');
    }
  }

  /**
   * 删除家庭成员（id 不存在视为失败）。
   * 注：todo.assignee_member_id 残留指派为逻辑引用，由调用方按需清理（见 FamilyMemberDao.delete 注释）。
   * @returns Result<number> 成功时 data=受影响行数（恒为 1）
   */
  async deleteMember(id: number): Promise<Result<number>> {
    try {
      // 先查后删：云端删除需要成员的 family_id/uid 推导 member_id（本地删完就取不到了）
      let target: FamilyMember | null = null;
      const all = await FamilyMemberDao.queryAll();
      for (const m of all) {
        if (m.id === id) {
          target = m;
          break;
        }
      }
      const rows = await FamilyMemberDao.delete(id);
      if (rows === 0) {
        return Result.fail<number>('成员不存在或已被删除');
      }
      // 云端同步删除（缓存一致性：否则后台拉取会把已删成员"复活"回本地）
      if (target !== null) {
        this.pushMemberDeleteToCloud(target);
      }
      hilog.info(0x0000, TAG, 'deleteMember: id=%{public}d rows=%{public}d', id, rows);
      return Result.ok<number>(rows);
    } catch (e) {
      hilog.error(0x0000, TAG, 'deleteMember failed: %{public}s', (e as Error).message);
      return Result.fail<number>('删除成员失败，请重试');
    }
  }

  /**
   * 查询全部成员（is_self=1 置顶，其余按创建时间升序，排序由 DAO 保证）。
   * T705: 首次调用本地为空时自动从云端恢复（await init）；缓存策略：先读本地，后台同步云端。
   * @returns Result<FamilyMember[]> 成功时 data=成员列表（可能为空数组）
   */
  async getAllMembers(): Promise<Result<FamilyMember[]>> {
    try {
      let members: FamilyMember[] = await FamilyMemberDao.queryAll();
      // 过滤：只返回已绑定家庭的成员（family_id 为空 = 残留脏数据 / 尚未加入家庭）
      members = members.filter((m: FamilyMember): boolean => m.family_id !== null && m.family_id!.length > 0);

      hilog.info(0x0000, TAG, '🔍 getAllMembers: local filtered count=%{public}d', members.length);

      // T705: 本地无有效成员时自动从云端全量恢复
      if (members.length === 0) {
        hilog.info(0x0000, TAG, '🔄 getAllMembers: triggering init() for cloud restore');
        await this.init();
        members = (await FamilyMemberDao.queryAll())
          .filter((m: FamilyMember): boolean => m.family_id !== null && m.family_id!.length > 0);
        hilog.info(0x0000, TAG, '✅ getAllMembers: after init, count=%{public}d', members.length);
      }

      // T708: 每次进 FamilyPage 必须从云端拉最新数据
      if (members.length > 0) {
        hilog.info(0x0000, TAG, '🔄 getAllMembers: triggering refreshCacheFromCloud()');
        await this.refreshCacheFromCloud();
        members = await FamilyMemberDao.queryAll();
        // 云端合并后重读本地，再次过滤并去重
        members = members.filter((m: FamilyMember): boolean => m.family_id !== null && m.family_id!.length > 0);
        members = this.deduplicateMembers(members);
        hilog.info(0x0000, TAG, '✅ getAllMembers: final count after refresh=%{public}d', members.length);
      }

      return Result.ok<FamilyMember[]>(members);
    } catch (e) {
      hilog.error(0x0000, TAG, '❌ getAllMembers failed: %{public}s', (e as Error).message);
      return Result.fail<FamilyMember[]>('查询成员列表失败，请重试');
    }
  }

  /**
   * 按称呼查找成员：先昵称精确匹配（DAO 索引路径），未命中再遍历全表按别名匹配
   * （FamilyMember.matchesName，用于 AI 抽取任务按"妈妈/老妈"等称呼定位成员）。
   * @returns Result<FamilyMember> 未找到返回 fail（message='未找到该成员'）
   */
  async findMemberByName(name: string): Promise<Result<FamilyMember>> {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      return Result.fail<FamilyMember>('称呼不能为空');
    }
    try {
      const byNickname = await FamilyMemberDao.findByNickname(trimmed);
      if (byNickname !== null) {
        return Result.ok<FamilyMember>(byNickname);
      }
      const members = await FamilyMemberDao.queryAll();
      for (const member of members) {
        if (member.matchesName(trimmed)) {
          return Result.ok<FamilyMember>(member);
        }
      }
      return Result.fail<FamilyMember>('未找到该成员');
    } catch (e) {
      hilog.error(0x0000, TAG, 'findMemberByName failed: %{public}s', (e as Error).message);
      return Result.fail<FamilyMember>('查找成员失败，请重试');
    }
  }

  /**
   * 获取本机用户自己。
   * 匹配优先级：uid（AccountManager 身份）→ is_self=1 标记。
   * 防止云端合并把别人记录误标 is_self 后读到别人的 aliases。
   */
  async getSelf(): Promise<Result<FamilyMember>> {
    try {
      const myUid: string = AccountManager.getInstance().getUid();
      const members = await FamilyMemberDao.queryAll();
      // 优先按 uid 精确匹配（防止 is_self 被误标导致的身份混淆）
      if (myUid.length > 0) {
        for (const member of members) {
          if (member.uid === myUid) {
            if (!member.isSelf()) {
              member.is_self = 1;
              await FamilyMemberDao.update(member);
            }
            return Result.ok<FamilyMember>(member);
          }
        }
      }
      // fallback：uid 为空或本地无 uid 匹配 → 按 is_self=1
      for (const member of members) {
        if (member.isSelf()) {
          return Result.ok<FamilyMember>(member);
        }
      }
      return Result.fail<FamilyMember>('尚未设置本机成员');
    } catch (e) {
      hilog.error(0x0000, TAG, 'getSelf failed: %{public}s', (e as Error).message);
      return Result.fail<FamilyMember>('查询本机成员失败，请重试');
    }
  }

  // ===================== T707 aliases 备注方法 =====================

  /**
   * T707: 设置我对某成员的备注名。
   * aliases 存「我对别人的备注」，存在我自己的 FamilyMember 记录里。
   * 流程：取我自己的 member → 更新 aliases[targetUid] = alias → update 本地 → await pushMemberToCloud。
   *
   * @param targetUid 被备注成员的 uid
   * @param alias 备注名（空字符串表示清除备注）
   * @returns Result<void> 成功/失败
   */
  async setAlias(targetUid: string, alias: string): Promise<Result<void>> {
    if (targetUid.length === 0) {
      return Result.fail<void>('目标成员 uid 不能为空');
    }
    const selfRes = await this.getSelf();
    if (!selfRes.success || selfRes.data === null) {
      return Result.fail<void>('尚未设置本机成员');
    }
    const myMember: FamilyMember = selfRes.data;
    const aliases: Record<string, string> = myMember.getAliases();
    const trimmedAlias: string = alias.trim();
    // 直接写入（空字符串 = 清除备注，getDisplayName 中会 fallback 到 nickname）
    aliases[targetUid] = trimmedAlias;
    myMember.setAliases(aliases);

    try {
      const rows = await FamilyMemberDao.update(myMember);
      if (rows === 0) {
        return Result.fail<void>('更新备注失败：本地记录不存在');
      }
      // T707: await 推云端，失败返回 fail 让调用方可感知
      await this.pushMemberToCloud(myMember);
      hilog.info(0x0000, TAG, 'setAlias: targetUid=%{public}s alias=%{public}s', targetUid, trimmedAlias);
      return Result.ok<void>(undefined as void);
    } catch (e) {
      hilog.error(0x0000, TAG, 'setAlias failed: %{public}s', (e as Error).message);
      return Result.fail<void>('设置备注失败，请重试');
    }
  }

  /**
   * T707: 获取我的 aliases 映射（我对别人的备注）。
   * @returns Record<string, string> targetUid → alias 映射；未设置本机成员时返回空对象
   */
  async getMyAliases(): Promise<Record<string, string>> {
    const selfRes = await this.getSelf();
    if (!selfRes.success || selfRes.data === null) {
      return {};
    }
    return selfRes.data.getAliases();
  }

  // ===================== T602 家庭创建 / 加入（Cloud DB Family 表主链路） =====================

  /** 邀请码字符集（排除易混淆的 0/O/1/I） */
  static readonly CODE_CHARSET: string = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  /** 邀请码固定长度 */
  static readonly CODE_LENGTH: number = 6;

  /**
   * 邀请码格式校验（6 位，限定字符集，大小写不敏感）。
   */
  static isValidInviteCode(code: string): boolean {
    const c: string = code.trim().toUpperCase();
    if (c.length !== FamilyManager.CODE_LENGTH) {
      return false;
    }
    for (let i = 0; i < c.length; i++) {
      if (FamilyManager.CODE_CHARSET.indexOf(c.charAt(i)) < 0) {
        return false;
      }
    }
    return true;
  }

  /** 生成 6 位去歧义邀请码（复用 CODE_CHARSET）。 */
  private static generateCode(): string {
    let code: string = '';
    for (let i = 0; i < FamilyManager.CODE_LENGTH; i++) {
      const idx: number = Math.floor(Math.random() * FamilyManager.CODE_CHARSET.length);
      code += FamilyManager.CODE_CHARSET.charAt(idx);
    }
    return code;
  }

  /**
   * T602 创建家庭：先查本地去重 → 生成 family_id UUID + 6 位邀请码 →
   * 本地 family_member insert → await 云端 Family + FamilyMember 双写 → 返回结果。
   *
   * HJDG-001 重审 fix: 取消 fire-and-forget，改为 await 云端写入（generateInviteCode 需要真实结果判断
   * 是否需重试）；本地去重查询替代假唯一约束 catch；insert 失败为真实错误、不外吞。
   *
   * 前置：本机已登录（需 owner_uid）、Cloud DB zone 已开。
   */
  async createFamily(ownerUid: string, ownerNickname: string,
    familyName?: string, preGeneratedCode?: string): Promise<Result<CreateFamilyResult>> {
    const uid: string = ownerUid.trim();
    if (uid.length === 0) {
      return Result.fail<CreateFamilyResult>('未登录，无法创建家庭');
    }
    const nickname: string = ownerNickname.trim();
    if (nickname.length === 0) {
      return Result.fail<CreateFamilyResult>('请先设置本机称呼');
    }

    // ① 本地去重：此 uid 是否已有本地 family_member 记录（含 family_id）→ 已有则复用
    try {
      const locals: FamilyMember[] = await FamilyMemberDao.queryAll();
      for (const local of locals) {
        if (local.uid === uid && local.family_id !== null && local.family_id.length > 0) {
          // 已存在：云端重推该家庭（补偿首次创建时云端写入失败）
          const existingFamilyId: string = local.family_id;
          const existingCode: string = preGeneratedCode !== undefined && preGeneratedCode.length > 0
            ? preGeneratedCode
            : FamilyManager.generateCode();
          const name: string = familyName !== undefined ? familyName.trim() : '我们的家';
          const finalName: string = name.length > 0 ? name : '我们的家';
          hilog.info(0x0000, TAG, 'createFamily: local record exists family_id=%{public}s, retry cloud push', existingFamilyId);
          try {
            await this.pushFamilyToCloud(existingFamilyId, existingCode, finalName, uid, nickname);
            const data: CreateFamilyResult = { family_id: existingFamilyId, invite_code: existingCode, family_name: finalName };
            return Result.ok<CreateFamilyResult>(data);
          } catch (e) {
            hilog.error(0x0000, TAG, 'createFamily retry cloud push failed: %{public}s', (e as Error).message);
            return Result.fail<CreateFamilyResult>('云端同步失败，请检查网络后重试');
          }
        }
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'createFamily local dedup query failed: %{public}s', (e as Error).message);
      return Result.fail<CreateFamilyResult>('本地数据查询失败，请重试');
    }

    // ② 全新创建
    const name: string = familyName !== undefined ? familyName.trim() : '我们的家';
    const finalName: string = name.length > 0 ? name : '我们的家';
    const familyId: string = util.generateRandomUUID(true);
    const inviteCode: string = preGeneratedCode !== undefined && preGeneratedCode.length > 0
      ? preGeneratedCode
      : FamilyManager.generateCode();

    // ③ 本地 family_member insert（is_self=1, role=owner）—— insert 失败为真实错误，不外吞
    const localMember: FamilyMember = new FamilyMember();
    localMember.uid = uid;
    localMember.nickname = nickname;
    localMember.role = 'owner';
    localMember.is_self = 1;
    localMember.family_id = familyId;
    localMember.created_at = Date.now();
    const rowId: number = await FamilyMemberDao.insert(localMember);
    localMember.id = rowId;
    hilog.info(0x0000, TAG, 'createFamily: local owner inserted id=%{public}d family_id=%{public}s', rowId, familyId);

    // ④ AWAIT 云端双写（非 fire-and-forget——generateInviteCode 需根据真实结果决定）
    try {
      await this.pushFamilyToCloud(familyId, inviteCode, finalName, uid, nickname);
    } catch (e) {
      hilog.error(0x0000, TAG, 'createFamily cloud push failed: %{public}s', (e as Error).message);
      // 本地记录已落盘——下次 generateInviteCode 调用时步骤①会命中去重分支，重推云端
      return Result.fail<CreateFamilyResult>('云端创建失败，请检查网络后重试');
    }

    const data: CreateFamilyResult = {
      family_id: familyId,
      invite_code: inviteCode,
      family_name: finalName
    };
    return Result.ok<CreateFamilyResult>(data);
  }

  /**
   * HJDG-001 重审: 供 generateInviteCode 查询云端是否已有家庭（owner_uid 索引查询）。
   * @returns 邀请码；未创建家庭返回空串
   */
  async getMyFamilyInviteCode(uid: string): Promise<string> {
    const svc: CloudDbService = CloudDbService.getInstance();
    if (!svc.isZoneOpened()) {
      return '';
    }
    try {
      const families: CloudFamily[] = await svc.queryFamiliesByOwner(uid);
      if (families.length > 0) {
        hilog.info(0x0000, TAG, 'getMyFamilyInviteCode: found family_id=%{public}s', families[0].family_id);
        return families[0].invite_code;
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'getMyFamilyInviteCode query failed: %{public}s', (e as Error).message);
    }
    return '';
  }

  /**
   * 内部方法：推送 Family + owner FamilyMember 到云端。
   * pushFamilyToCloud Family upsert 失败时提前返回（跳过 Member，member 缺 family 引用无意义）。
   */
  private async pushFamilyToCloud(familyId: string, inviteCode: string, familyName: string,
    ownerUid: string, ownerNickname: string): Promise<void> {
    const svc: CloudDbService = CloudDbService.getInstance();
    if (!svc.isZoneOpened()) {
      throw new Error('Cloud DB zone not opened');
    }
    const family: CloudFamily = new CloudFamily();
    family.family_id = familyId;
    family.name = familyName;
    family.invite_code = inviteCode;
    family.owner_uid = ownerUid;
    family.created_at = Date.now();
    await svc.upsertFamily(family);
    hilog.info(0x0000, TAG, 'pushFamilyToCloud: Family upserted family_id=%{public}s', familyId);

    const cloudMember: CloudFamilyMember = new CloudFamilyMember();
    cloudMember.member_id = FamilyManager.buildMemberId(familyId, ownerUid);
    cloudMember.family_id = familyId;
    cloudMember.uid = ownerUid;
    cloudMember.nickname = ownerNickname;
    cloudMember.role = 'owner';
    cloudMember.created_at = Date.now();
    await svc.upsertFamilyMember(cloudMember);
    hilog.info(0x0000, TAG, 'pushFamilyToCloud: owner member upserted member_id=%{public}s', cloudMember.member_id);
  }

  /**
   * T603 通过邀请码加入家庭（HJDG-001 fix#5：joinerUid/joinerNickname 入参化，不再内部读 AccountManager）。
   *
   * 流程：格式校验 → Cloud DB Family 表按 invite_code 验证 → 本地优先写 family_member（is_self=1）
   * → 后台 fire-and-forget 推 Cloud DB FamilyMember。
   *
   * 前置：本机已登录、zone 已开（均由调用方 FamilyViewModel 保证）。
   *
   * @param inviteCode 6 位邀请码（家人分享）
   * @param joinerUid 加入者账号 uid（AccountManager.getUid()）
   * @param joinerNickname 加入者在本家庭的称呼
   * @returns Result<JoinFamilyResult>
   */
  async joinFamilyByCode(inviteCode: string, joinerUid: string,
    joinerNickname: string): Promise<Result<JoinFamilyResult>> {
    const code: string = inviteCode.trim().toUpperCase();
    if (!FamilyManager.isValidInviteCode(code)) {
      return Result.fail<JoinFamilyResult>('邀请码格式不正确，应为 6 位字母数字');
    }

    const uid: string = joinerUid.trim();
    if (uid.length === 0) {
      return Result.fail<JoinFamilyResult>('未登录，无法加入家庭');
    }
    // T706: fallback 从硬编码「我」改为 getCurrentNickname()（注册用户名或手机号脱敏）
    const nickname: string = joinerNickname.trim().length > 0
      ? joinerNickname.trim()
      : AccountManager.getInstance().getCurrentNickname();

    const svc: CloudDbService = CloudDbService.getInstance();
    if (!svc.isZoneOpened()) {
      return Result.fail<JoinFamilyResult>('云服务不可用，请稍后重试');
    }

    // ① 云端验证：根据邀请码查 Cloud DB Family 表（必须 await 同步确认）
    let family: CloudFamily | null = null;
    try {
      family = await svc.queryFamilyByInviteCode(code);
    } catch (e) {
      hilog.error(0x0000, TAG, 'joinFamilyByCode query failed: %{public}s', (e as Error).message);
      return Result.fail<JoinFamilyResult>('云端验证失败，请检查网络后重试');
    }
    if (family === null) {
      return Result.fail<JoinFamilyResult>('邀请码无效或已过期');
    }

    const familyId: string = family.family_id;

    // ② 防自建重入
    if (family.owner_uid === uid) {
      return Result.fail<JoinFamilyResult>('不能加入自己创建的家庭');
    }

    // ③ 本地优先：写 family_member 表（is_self=1, role=member）
    const localMember: FamilyMember = new FamilyMember();
    localMember.uid = uid;
    localMember.nickname = nickname;
    localMember.role = 'member';
    localMember.is_self = 1;
    localMember.family_id = familyId;
    localMember.created_at = Date.now();

    try {
      await FamilyMemberDao.insert(localMember);
      hilog.info(0x0000, TAG, 'joinFamilyByCode: local member inserted id=%{public}d family_id=%{public}s',
        localMember.id, familyId);
    } catch (e) {
      // 唯一约束冲突：已在此家庭中（幂等，不视为失败——但需告知上层已加入）
      hilog.warn(0x0000, TAG, 'joinFamilyByCode: local insert duplicate (already joined), idempotent');
    }

    // ④ 后台 fire-and-forget 推 Cloud DB FamilyMember
    this.pushJoinToCloud(familyId, uid, nickname);

    const data: JoinFamilyResult = {
      family_id: familyId,
      family_name: family.name,
      owner_uid: family.owner_uid
    };
    return Result.ok<JoinFamilyResult>(data);
  }

  /**
   * HJDG-001 fix#2: 后台推送加入者 FamilyMember 到云端（fire-and-forget）。
   */
  private async pushJoinToCloud(familyId: string, uid: string, nickname: string): Promise<void> {
    const svc: CloudDbService = CloudDbService.getInstance();
    if (!svc.isZoneOpened()) {
      hilog.warn(0x0000, TAG, 'pushJoinToCloud skipped: cloud zone not opened');
      return;
    }
    try {
      const cloudMember: CloudFamilyMember = new CloudFamilyMember();
      cloudMember.member_id = FamilyManager.buildMemberId(familyId, uid);
      cloudMember.family_id = familyId;
      cloudMember.uid = uid;
      cloudMember.nickname = nickname;
      cloudMember.role = 'member';
      cloudMember.created_at = Date.now();
      await svc.upsertFamilyMember(cloudMember);
      hilog.info(0x0000, TAG, 'pushJoinToCloud: member upserted member_id=%{public}s', cloudMember.member_id);
    } catch (e) {
      hilog.error(0x0000, TAG, 'pushJoinToCloud failed: %{public}s', (e as Error).message);
    }
  }

  // ===================== Cloud DB 同步（本地 SQLite=缓存层，云端=远端真源） =====================
  // fix: DEV-VOICE-REMIND —— CloudFamilyMember 模型已与控制台建表同步（主键 member_id:String，
  //   无 is_self/phone 列），映射随之调整：
  //   · member_id 约定 `${family_id}_${uid}`（同家同人幂等 upsert，对齐控制台 family_id+uid 索引）；
  //   · 未绑定账号（uid 空）或未入家庭（family_id 空）的纯本地成员不上云（也收不到推送）；
  //   · is_self/phone 为本地专属列，拉取合并时保留本地值。

  /** 成员是否具备上云条件（已绑定账号 + 已加入家庭）。 */
  private static isCloudEligible(member: FamilyMember): boolean {
    return member.uid !== null && member.uid.length > 0
      && member.family_id !== null && member.family_id.length > 0;
  }

  /** 云端主键约定：`${family_id}_${uid}`。 */
  private static buildMemberId(familyId: string, uid: string): string {
    return familyId + '_' + uid;
  }

  /** 本地成员 → Cloud DB 对象（调用前须过 isCloudEligible；is_self/phone 不上云）。 */
  private static toCloudMember(member: FamilyMember): CloudFamilyMember {
    const cloud = new CloudFamilyMember();
    const familyId: string = member.family_id ?? '';
    const uid: string = member.uid ?? '';
    cloud.member_id = FamilyManager.buildMemberId(familyId, uid);
    cloud.family_id = familyId;
    cloud.uid = uid;
    cloud.nickname = member.nickname;
    cloud.aliases = member.aliases;
    cloud.role = member.role;
    cloud.push_token = member.push_token ?? '';
    cloud.created_at = member.created_at;
    return cloud;
  }

  /** Cloud DB 对象 → 本地成员（id/is_self/phone 由合并策略按需覆盖；空串统一还原 null）。 */
  private static toLocalMember(cloud: CloudFamilyMember): FamilyMember {
    const member = new FamilyMember();
    member.id = 0;
    member.uid = cloud.uid.length > 0 ? cloud.uid : null;
    member.nickname = cloud.nickname;
    member.aliases = cloud.aliases;
    member.role = cloud.role;
    member.phone = null;
    member.push_token = cloud.push_token.length > 0 ? cloud.push_token : null;
    member.family_id = cloud.family_id.length > 0 ? cloud.family_id : null;
    member.is_self = 0;
    member.created_at = cloud.created_at > 0 ? cloud.created_at : Date.now();
    return member;
  }

  /** 云端数据与本地缓存是否有业务字段差异（id/is_self/phone/created_at 按合并策略排除）。
   *  T707-fix: 云端 nickname 为已知脏默认值（空串/「我」/纯手机号脱敏模式）时不覆盖本地。 */
  private static memberFieldsDiffer(local: FamilyMember, incoming: FamilyMember): boolean {
    // 昵称：如果云端是脏默认值，保留本地昵称不覆盖
    const nickDiffer: boolean = FamilyManager.isCleanNickname(incoming.nickname)
      && local.nickname !== incoming.nickname;
    return local.uid !== incoming.uid
      || nickDiffer
      || local.aliases !== incoming.aliases
      || local.role !== incoming.role
      || local.push_token !== incoming.push_token
      || local.family_id !== incoming.family_id;
  }

  /** 昵称是否为有效值（非默认脏数据：空/「我」/手机号脱敏模式 138****1234） */
  private static isCleanNickname(nick: string): boolean {
    if (nick.length === 0 || nick === '我') {
      return false;
    }
    // 手机号脱敏模式：3位 + **** + 4位
    if (nick.indexOf('****') > 0 && nick.length >= 11) {
      return false;
    }
    return true;
  }

  /**
   * 后台推送单个成员到 Cloud DB（fire-and-forget）。
   * zone 未开（未登录/未初始化）静默跳过；纯本地成员（未绑账号/未入家庭）不上云；
   * 云端失败仅记日志——本地缓存已写成功，页面无感。
   */
  private async pushMemberToCloud(member: FamilyMember): Promise<void> {
    const svc = CloudDbService.getInstance();
    if (!svc.isZoneOpened()) {
      hilog.debug(0x0000, TAG, 'pushMemberToCloud skipped: cloud zone not opened');
      return;
    }
    if (!FamilyManager.isCloudEligible(member)) {
      hilog.debug(0x0000, TAG, 'pushMemberToCloud skipped: member not cloud-eligible (no uid/family_id)');
      return;
    }
    try {
      await svc.upsertFamilyMember(FamilyManager.toCloudMember(member));
    } catch (e) {
      hilog.error(0x0000, TAG, 'pushMemberToCloud failed (local cache kept): %{public}s', (e as Error).message);
    }
  }

  /**
   * 后台推送删除到 Cloud DB（按约定主键 member_id=`${family_id}_${uid}`，fire-and-forget）。
   * 缓存一致性所需：不推删除的话 refreshCacheFromCloud 会把已删成员重新插回本地。
   * 注：须在本地删除前捕获成员的 family_id/uid（deleteMember 内先查后删）。
   */
  private async pushMemberDeleteToCloud(member: FamilyMember): Promise<void> {
    const svc = CloudDbService.getInstance();
    if (!svc.isZoneOpened()) {
      hilog.debug(0x0000, TAG, 'pushMemberDeleteToCloud skipped: cloud zone not opened');
      return;
    }
    if (!FamilyManager.isCloudEligible(member)) {
      hilog.debug(0x0000, TAG, 'pushMemberDeleteToCloud skipped: member not cloud-eligible');
      return;
    }
    try {
      const cloud = FamilyManager.toCloudMember(member);
      await svc.deleteFamilyMember(cloud);
    } catch (e) {
      hilog.error(0x0000, TAG, 'pushMemberDeleteToCloud failed: %{public}s', (e as Error).message);
    }
  }

  /**
   * 后台从 Cloud DB 拉取本家庭成员，合并回本地缓存（fire-and-forget，防重入）。
   * 合并策略：
   * - 先按 id、再按昵称匹配本地行：命中且业务字段有差异 → 更新（保留本地 id/is_self/created_at）；
   * - 云端有、本地无 → 插入本地（is_self 置 0，"本机"标记只能由本机产生）；
   * - 本地有、云端无 → 保留（删除传播由写路径 pushMemberDeleteToCloud 负责，拉取侧不做删除）。
   * familyId 取本地成员中首个非空 family_id；本地无家庭信息时跳过（纯本地模式）。
   */
  private async refreshCacheFromCloud(): Promise<void> {
    const svc = CloudDbService.getInstance();
    if (!svc.isZoneOpened() || this.cloudRefreshInFlight) {
      return;
    }
    this.cloudRefreshInFlight = true;
    try {
      const locals = await FamilyMemberDao.queryAll();
      let familyId: string | null = null;
      for (const local of locals) {
        if (local.family_id !== null && local.family_id.length > 0) {
          familyId = local.family_id;
          break;
        }
      }
      if (familyId === null) {
        hilog.debug(0x0000, TAG, 'refreshCacheFromCloud skipped: no family_id in local cache');
        return;
      }
      const cloudMembers = await svc.queryFamilyMembers(familyId);
      for (const cloudMember of cloudMembers) {
        const incoming = FamilyManager.toLocalMember(cloudMember);
        // 匹配优先级：uid（云端身份唯一，不再按昵称匹配——昵称可能重复或为旧脏数据「我」）
        let matched: FamilyMember | undefined = undefined;
        if (cloudMember.uid.length > 0) {
          matched = locals.find((item: FamilyMember): boolean => item.uid === cloudMember.uid);
        }
        if (matched !== undefined) {
          // 保护本地昵称不被云端脏默认值覆盖（空/「我」/手机号脱敏模式）
          if (!FamilyManager.isCleanNickname(incoming.nickname)) {
            incoming.nickname = matched.nickname;
          }
          if (FamilyManager.memberFieldsDiffer(matched, incoming)) {
            // 本地专属字段保留：id 主键 / is_self 本机标记 / phone（云表无此列）
            incoming.id = matched.id;
            incoming.is_self = matched.is_self;
            incoming.phone = matched.phone;
            await FamilyMemberDao.update(incoming);
          }
        } else {
          // 云端记录无本地匹配 → 仅当 uid 非空才插入（空 uid = 脏数据，跳过）
          if (incoming.uid !== null && incoming.uid!.length > 0) {
            incoming.is_self = 0;
            await FamilyMemberDao.insert(incoming);
          }
        }
      }
      hilog.info(0x0000, TAG, 'refreshCacheFromCloud: merged %{public}d cloud members', cloudMembers.length);
    } catch (e) {
      hilog.error(0x0000, TAG, 'refreshCacheFromCloud failed (local cache kept): %{public}s', (e as Error).message);
    } finally {
      this.cloudRefreshInFlight = false;
    }
  }

  /**
   * 按 uid 去重成员列表（同一个 uid 只保留一条记录）。
   * 去重策略：
   * - 优先保留 is_self=1 的记录（本机用户）
   * - 其次保留 uid 非空的记录
   * - 最后按 id 升序（保留较早创建的记录）
   * - uid 为空的记录不参与去重，独立保留（历史数据兼容）
   * @param members 待去重的成员列表
   * @returns 去重后的成员列表
   */
  private deduplicateMembers(members: FamilyMember[]): FamilyMember[] {
    const uidMap: Map<string, FamilyMember> = new Map<string, FamilyMember>();
    const noUidMembers: FamilyMember[] = [];

    for (const member of members) {
      // uid 为空的记录单独保留（历史数据）
      if (member.uid === null || member.uid.length === 0) {
        noUidMembers.push(member);
        continue;
      }

      const existing = uidMap.get(member.uid);
      if (existing === undefined) {
        // 首次遇到此 uid，直接保存
        uidMap.set(member.uid, member);
      } else {
        // 已存在此 uid，按优先级选择保留哪条记录
        // 1. 优先保留 is_self=1 的记录
        if (member.is_self === 1 && existing.is_self !== 1) {
          uidMap.set(member.uid, member);
        } else if (member.is_self !== 1 && existing.is_self === 1) {
          // existing 是本机用户，保留 existing
          continue;
        } else {
          // 都是本机用户或都不是，保留 id 较小的（较早创建的）
          if (member.id < existing.id) {
            uidMap.set(member.uid, member);
          }
        }
      }
    }

    // 合并结果：uid 去重后的 + uid 为空的
    const result: FamilyMember[] = Array.from(uidMap.values());
    result.push(...noUidMembers);

    // 按 DAO 的排序规则重新排序：is_self DESC, created_at ASC, id ASC
    result.sort((a: FamilyMember, b: FamilyMember): number => {
      if (a.is_self !== b.is_self) {
        return b.is_self - a.is_self; // is_self=1 在前
      }
      if (a.created_at !== b.created_at) {
        return a.created_at - b.created_at; // 创建时间升序
      }
      return a.id - b.id; // id 升序
    });

    hilog.info(0x0000, TAG, 'deduplicateMembers: %{public}d → %{public}d members', members.length, result.length);
    return result;
  }
}
