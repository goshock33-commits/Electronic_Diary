// <!-- agentID: DEV-010 -->
// <!-- agentID: DEV+HUI / D-ACCT -->
// File: AccountManager.ets
// Task: Login state management — phone + password over Cloud DB Account table
// fix: DEV+HUI —— 四期改密码方案：删 @hw-agconnect/auth 全部代码（发码 requestVerifyCode /
//   signIn / signOut / EntryAbility auth.init / oh-package 依赖），注册登录直连 Cloud DB：
//   · register(phone, pwd)：queryAccountByPhone 查重 → EncryptionUtils.encryptPin(pwd, APP_SECRET)
//     AES 加密（`ct:iv` 密文）→ uid = util.generateRandomUUID（本地生成，替代 AGC uid）
//     → CloudDbService.upsertAccount 写云表 → 成功后 AccountDao.saveLoginAccount 本地缓存登录态
//   · login(phone, pwd)：queryAccountByPhone 查云表 → EncryptionUtils.verifyPin 验密
//     （云端密文为空时显式拒绝，防 verifyPin「未设 PIN 即放行」旧语义被当成免密登录）
//     → 验证通过 AccountDao.saveLoginAccount 本地缓存登录态
//   · logout()：仅清本地 Account 表（无 SDK 会话可退）
//   · 控制台前置（人工）：Account 表补 password(String) 字段；phone 取消云侧加密并建普通索引
//     （加密字段不可作查询谓词）；无 Auth 后客户端为匿名身份，表权限需放开「所有人」读写
// fix: T602(DEV-010) · 登录态响应式广播：注册/登录/登出/启动恢复每次内存态变迁同步写
//   AppStorage['account_logged_in' / 'account_uid' / 'account_phone']，修复「UI aboutToAppear
//   一次性快照 → LoginPage 注册成功 router.back() 后仍显示未登录」读写断链
//   （UI 侧改 @StorageProp('account_logged_in') 订阅，见《UI 侧修改说明》，由 HUI 执行）。
// Architecture: Singleton wrapping CloudDbService + AccountDao
// Dev paradigm: ArkTS async; follows FamilyManager pattern (Result<T> uniform returns)

import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { AccountDao } from '../database/dao/AccountDao';
import { CloudDbService, CloudAccount } from '../cloud/CloudDbService';
import { EncryptionUtils } from './EncryptionUtils';
import { Result } from './FamilyManager';
import { FamilyMemberDao } from '../database/dao/FamilyMemberDao';
import { EventBus, AccountLoginSuccessData } from './EventBus';

const TAG: string = 'AccountManager';
const LOG_DOMAIN: number = 0xFF00;

/** 密码 AES 加密主密钥（app 级密钥，对标 SettingsViewModel PIN 加密先例同值口径） */
const APP_SECRET: string = 'HuaweiDiary2024!@#$';

/** 密码长度下限/上限（与 LoginPage 校验口径一致） */
const PWD_MIN_LEN: number = 6;
const PWD_MAX_LEN: number = 20;

/** 本地 Account 表 token 列占位——密码方案无服务端会话 token，恒存空串 */
const NO_TOKEN: string = '';

/** T602: 登录态 AppStorage 业务键（AccountManager 每次状态变迁必写；UI @StorageProp 同名字面量订阅） */
const KEY_ACCOUNT_LOGGED_IN: string = 'account_logged_in';
const KEY_ACCOUNT_UID: string = 'account_uid';
const KEY_ACCOUNT_PHONE: string = 'account_phone';
/** T701: 注册用户名广播键（UI @StorageProp 订阅，getCurrentNickname 优先此值，fallback 手机号脱敏） */
const KEY_ACCOUNT_NICKNAME: string = 'account_nickname';

/**
 * 注册/登录入参本地校验（手机号已在页面层做 11 位校验，此处兜底非空 + 密码长度）。
 * @returns 错误文案；'' 表示校验通过
 */
function validateCredentials(phone: string, pwd: string): string {
  if (phone.length === 0) {
    return '请输入手机号';
  }
  if (pwd.length < PWD_MIN_LEN || pwd.length > PWD_MAX_LEN) {
    return `请输入 ${PWD_MIN_LEN}-${PWD_MAX_LEN} 位密码`;
  }
  return '';
}

/**
 * AccountManager — singleton for login state management.
 *
 * Flow:
 *   register(phone, pwd) → 云表查重 → AES 加密 → upsert Cloud DB Account → 本地缓存登录态
 *   login(phone, pwd)    → 云表按 phone 查询 → verifyPin 验密 → 本地缓存登录态
 *   logout()             → 清本地 Account 表登录态
 *
 * 云端真相源：Cloud DB Account 表（CloudDbService，@kit.CloudFoundationKit）；
 * 本地 Account 表仅作登录态缓存（AccountDao，冷启动 init() 恢复）。
 *
 * Usage:
 *   const mgr = AccountManager.getInstance();
 *   const reg = await mgr.register('13800138000', 'abc123', '小明');
 *   const login = await mgr.login('13800138000', 'abc123');
 */
export class AccountManager {
  private static instance: AccountManager | null = null;

  /** Cached login state (updated on login/logout, checked on init) */
  private loggedIn: boolean = false;
  private currentUid: string = '';
  private currentPhone: string = '';
  /** T701: 注册用户名缓存（publishLoginState 广播到 AppStorage） */
  private currentNickname: string = '';
  private initPromise: Promise<void> | null = null;

  private constructor() {
    // T602: 建键定型（boolean/string），保证 UI 首帧 @StorageProp 绑定时键已存在且类型正确
    this.publishLoginState();
  }

  /**
   * Get singleton instance.
   */
  static getInstance(): AccountManager {
    if (!AccountManager.instance) {
      AccountManager.instance = new AccountManager();
    }
    return AccountManager.instance;
  }

  // ════════════════════════════════════════════════════════
  // Initialization
  // ════════════════════════════════════════════════════════

  /**
   * Initialize: restore login state from local DB.
   * Call once at app startup. Safe to call multiple times (idempotent).
   */
  async init(): Promise<void> {
    if (this.initPromise) {
      return this.initPromise;
    }
    this.initPromise = this.doInit();
    return this.initPromise;
  }

  private async doInit(): Promise<void> {
    try {
      const account = await AccountDao.getLoggedInAccount();
      if (account) {
        this.loggedIn = true;
        this.currentUid = account['uid'] as string;
        this.currentPhone = (account['phone'] as string) ?? '';
        this.currentNickname = (account['nickname'] as string) ?? '';
        hilog.info(LOG_DOMAIN, TAG, 'Login state restored: uid=%{public}s', this.currentUid);
      } else {
        this.loggedIn = false;
        this.currentUid = '';
        this.currentPhone = '';
        this.currentNickname = '';
        hilog.info(LOG_DOMAIN, TAG, 'No logged-in account found');
      }
    } catch (err) {
      hilog.error(LOG_DOMAIN, TAG, 'AccountManager init failed: %{public}s',
        (err as Error).message ?? '');
      this.loggedIn = false;
      this.currentUid = '';
      this.currentPhone = '';
      this.currentNickname = '';
    }
    // T602: 启动恢复完成（含失败兜底）后广播——UI 早于恢复完成渲染也能收到最终态
    this.publishLoginState();
  }

  // ════════════════════════════════════════════════════════
  // Public API
  // ════════════════════════════════════════════════════════

  /**
   * Check if a user is currently logged in (in-memory cache).
   * For authoritative check, use refreshLoginState().
   */
  isLoggedIn(): boolean {
    return this.loggedIn;
  }

  /**
   * Get the uid of the currently logged-in user.
   * Returns empty string if not logged in.
   */
  getUid(): string {
    return this.currentUid;
  }

  /**
   * Get the phone number of the currently logged-in user.
   * Returns empty string if not logged in.
   */
  getPhone(): string {
    return this.currentPhone;
  }

  /** T701: 已登录用户的注册用户名；无昵称则 fallback 用户短标识（不泄露手机号） */
  getCurrentNickname(): string {
    if (this.currentNickname.length > 0) {
      return this.currentNickname;
    }
    // 没有昵称时用 uid 后 4 位生成唯一短标识，不泄露手机号
    if (this.currentUid.length >= 4) {
      return '用户' + this.currentUid.slice(-4);
    }
    return '用户';
  }

  /**
   * T701: Register a new account: Cloud DB Account 表写入 + 本地缓存登录态（注册即登录）。
   *
   * 流程：queryAccountByPhone 查重 → encryptPin AES 加密 → uid = generateRandomUUID
   *   → upsertAccount 写云表（含 nickname）→ AccountDao.saveLoginAccount 本地缓存。
   *
   * @param phone Phone number (11-digit, page-level validated)
   * @param pwd Plaintext password (6-20 chars)
   * @param nickname 注册用户名（1-12 字符，trim 非空；T701 新增必填）
   * @returns Result<string> with the new uid on success
   */
  async register(phone: string, pwd: string, nickname: string): Promise<Result<string>> {
    const trimmedPhone: string = phone ? phone.trim() : '';
    const invalidMsg: string = validateCredentials(trimmedPhone, pwd);
    if (invalidMsg.length > 0) {
      return Result.fail<string>(invalidMsg);
    }
    if (!this.ensureZoneOpened()) {
      return Result.fail<string>('云服务不可用，请稍后重试');
    }

    hilog.info(LOG_DOMAIN, TAG, 'register: phone=%{public}s → Cloud DB Account', trimmedPhone);

    try {
      const svc: CloudDbService = CloudDbService.getInstance();
      // Step 1: 查重——同手机号已注册则拒绝
      const existed: CloudAccount | null = await svc.queryAccountByPhone(trimmedPhone);
      if (existed !== null) {
        return Result.fail<string>('该手机号已注册，请直接登录');
      }

      // Step 2: AES 加密密码（EncryptionUtils `ct:iv` 密文，主密钥 APP_SECRET）
      const cipher: string | null = await EncryptionUtils.encryptPin(pwd, APP_SECRET);
      if (cipher === null || cipher.length === 0) {
        hilog.error(LOG_DOMAIN, TAG, 'register: encryptPin returned empty');
        return Result.fail<string>('密码加密失败，请重试');
      }

      // Step 3: 本地生成 UUID 作 uid（替代 AGC Auth uid）→ 写云表
      // 用户名校验（T701 必填，与 LoginPage 校验口径一致）
      const trimmedNick: string = nickname ? nickname.trim() : '';
      if (trimmedNick.length === 0 || trimmedNick.length > 12) {
        return Result.fail<string>('请输入 1-12 位用户名');
      }

      const uid: string = util.generateRandomUUID(true);
      const account: CloudAccount = new CloudAccount();
      account.uid = uid;
      account.phone = trimmedPhone;
      account.nickname = trimmedNick; // T701: 注册时写云端 Account 表 nickname
      account.password = cipher;
      account.created_at = Date.now();
      await svc.upsertAccount(account);
      hilog.info(LOG_DOMAIN, TAG, 'register: cloud Account upserted, uid=%{public}s nick=%{public}s', uid, trimmedNick);

      // Step 4: 成功后本地 Account 表缓存登录态（注册即登录）
      return this.cacheLoginLocally(uid, trimmedPhone, trimmedNick);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(LOG_DOMAIN, TAG, 'register failed: code=%{public}d %{public}s',
        e.code ?? 0, e.message ?? '');
      return Result.fail<string>('注册失败: ' + ((err as BusinessError).message ?? '').substring(0, 80));
    }
  }

  /**
   * Login with phone + password: Cloud DB Account 表查询 → 验密 → 本地缓存登录态。
   *
   * @param phone Phone number
   * @param pwd Plaintext password entered by user
   * @returns Result<string> with the uid on success
   */
  async login(phone: string, pwd: string): Promise<Result<string>> {
    const trimmedPhone: string = phone ? phone.trim() : '';
    const invalidMsg: string = validateCredentials(trimmedPhone, pwd);
    if (invalidMsg.length > 0) {
      return Result.fail<string>(invalidMsg);
    }
    if (!this.ensureZoneOpened()) {
      return Result.fail<string>('云服务不可用，请稍后重试');
    }

    hilog.info(LOG_DOMAIN, TAG, 'login: phone=%{public}s → Cloud DB Account', trimmedPhone);

    try {
      const svc: CloudDbService = CloudDbService.getInstance();
      // Step 1: 云表按 phone 查账号
      const account: CloudAccount | null = await svc.queryAccountByPhone(trimmedPhone);
      if (account === null) {
        return Result.fail<string>('该手机号未注册，请先注册');
      }

      // Step 2: 验密。云端密文为空必须显式拒绝——verifyPin 对空密文返回 true
      //   （「未设 PIN 即放行」语义），不拦会变成免密登录漏洞。
      const stored: string = account.password;
      if (stored.length === 0) {
        hilog.warn(LOG_DOMAIN, TAG, 'login: cloud account has empty password, reject');
        return Result.fail<string>('该账号未设置密码，请重新注册');
      }
      const match: boolean = await EncryptionUtils.verifyPin(pwd, stored, APP_SECRET);
      if (!match) {
        return Result.fail<string>('手机号或密码错误');
      }

      // Step 3: 本地 Account 表缓存登录态（含云端 nickname）
      return this.cacheLoginLocally(account.uid, trimmedPhone, account.nickname);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(LOG_DOMAIN, TAG, 'login failed: code=%{public}d %{public}s',
        e.code ?? 0, e.message ?? '');
      return Result.fail<string>('登录失败: ' + ((err as BusinessError).message ?? '').substring(0, 80));
    }
  }

  /**
   * Log out: clear local login state and persistent cache.
   * 密码方案无 SDK 会话可退，仅清本地 Account 表登录态。
   */
  async logout(): Promise<Result<void>> {
    try {
      await AccountDao.logout();
      // 清本地家庭数据，防止下一用户登录后看到上一用户的残留成员
      await FamilyMemberDao.deleteAll();
      this.loggedIn = false;
      this.currentUid = '';
      this.currentPhone = '';
      this.currentNickname = '';
      this.publishLoginState(); // T602: 登出即时广播
      hilog.info(LOG_DOMAIN, TAG, 'Logout successful');
      return Result.ok<void>(undefined as void);
    } catch (err) {
      hilog.error(LOG_DOMAIN, TAG, 'Logout failed: %{public}s', (err as Error).message ?? '');
      return Result.fail<void>((err as Error).message ?? 'Unknown error');
    }
  }

  /**
   * Check login state against the database (force refresh in-memory cache).
   */
  async refreshLoginState(): Promise<boolean> {
    try {
      const account = await AccountDao.getLoggedInAccount();
      if (account) {
        this.loggedIn = true;
        this.currentUid = (account['uid'] as string) ?? '';
        this.currentPhone = (account['phone'] as string) ?? '';
      } else {
        this.loggedIn = false;
        this.currentUid = '';
        this.currentPhone = '';
      }
      this.publishLoginState(); // T602: 强制刷新后广播
      return this.loggedIn;
    } catch (err) {
      hilog.error(LOG_DOMAIN, TAG, 'refreshLoginState failed: %{public}s',
        (err as Error).message ?? '');
      return false;
    }
  }

  // ════════════════════════════════════════════════════════
  // Internal helpers
  // ════════════════════════════════════════════════════════

  /**
   * T602: 登录态唯一广播口——内存态每次变迁后同步写 AppStorage 业务键。
   * 断链背景：LoginPage 注册/登录成功 router.back() 后，FamilyPage / 设置页均为非 @Entry
   * 嵌入组件（无 onPageShow），aboutToAppear 一次性快照永不重读 → UI 停留「未登录」。
   * UI 侧以 @StorageProp('account_logged_in') 等同名字面量订阅即可响应式刷新
   * （AppStorage 为全局对象，禁 import，PROJECT_SPEC §8.3②；键名契约见文件头 KEY_ACCOUNT_*）。
   */
  private publishLoginState(): void {
    AppStorage.setOrCreate<boolean>(KEY_ACCOUNT_LOGGED_IN, this.loggedIn);
    AppStorage.setOrCreate<string>(KEY_ACCOUNT_UID, this.currentUid);
    AppStorage.setOrCreate<string>(KEY_ACCOUNT_PHONE, this.currentPhone);
    AppStorage.setOrCreate<string>(KEY_ACCOUNT_NICKNAME, this.currentNickname);
  }

  /**
   * 打开 Cloud DB zone（已开跳过；AGC 未配置/无网时 zone() 抛错 → 告警降级返回 false）。
   * 与 VoiceReminderSender.ensureZoneOpened 同模式：注册/登录不依赖启动期
   * VoiceReminderSender.initialize 是否成功。
   */
  private ensureZoneOpened(): boolean {
    const svc: CloudDbService = CloudDbService.getInstance();
    if (svc.isZoneOpened()) {
      return true;
    }
    try {
      svc.openCloudDBZone();
      return true;
    } catch (err) {
      const msg: string = (err as BusinessError).message ?? String(err);
      promptAction.showToast({ message: 'Cloud DB: ' + msg.substring(0, 60), duration: 3000 });
      return false;
    }
  }

  /**
   * 登录/注册成功后的本地落库 + 内存态更新（token 列恒存空串占位）。
   * T705: 新增 nickname 参数，写入本地 account 表 + 更新内存态 currentNickname 供 getCurrentNickname 使用。
   * T031 (DEV-001): 登录成功后触发 push token 上报到云端（火后不管模式，失败仅记日志）。
   * DEV-007: 登录成功后发送 EventBus 事件，触发首页等订阅方刷新数据。
   */
  private async cacheLoginLocally(uid: string, phone: string, nickname?: string): Promise<Result<string>> {
    try {
      const nick: string = nickname !== undefined ? nickname : '';
      await AccountDao.saveLoginAccount(uid, phone, NO_TOKEN, nick);
      this.loggedIn = true;
      this.currentUid = uid;
      this.currentPhone = phone;
      if (nick.length > 0) {
        this.currentNickname = nick;
      }
      this.publishLoginState(); // T602: 注册/登录成功即时广播 → UI 无需重进页面即刷新

      // DEV-007: 发送登录成功事件，触发首页数据刷新
      const loginEventData: AccountLoginSuccessData = { uid: uid, phone: phone };
      EventBus.emit(EventBus.EventNames.ACCOUNT_LOGIN_SUCCESS, loginEventData);
      hilog.info(LOG_DOMAIN, TAG, 'DEV-007: emitted ACCOUNT_LOGIN_SUCCESS event');

      // T031: 登录成功后触发 push token 同步（fire-and-forget，失败不影响登录结果）
      this.syncPushTokenAfterLogin().catch((err: Error) => {
        hilog.error(LOG_DOMAIN, TAG, 'T031: syncPushTokenAfterLogin failed: %{public}s', err.message);
      });

      hilog.info(LOG_DOMAIN, TAG, 'Login cached: uid=%{public}s phone=%{public}s nick=%{public}s', uid, phone, nick);
      return Result.ok<string>(uid);
    } catch (err) {
      hilog.error(LOG_DOMAIN, TAG, 'Failed to save login account: %{public}s',
        (err as Error).message ?? '');
      return Result.fail<string>('Failed to save login state: ' + (err as Error).message);
    }
  }

  /**
   * T031: 登录成功后同步 push token 到云端（异步 fire-and-forget）。
   * 场景：① 先登录后授权推送 ② 登录时 token 已就绪 ③ token 变更后重新登录。
   * PushManager.syncToken 内部自动处理：token 未就绪时重试获取 + 与上次缓存比较去重。
   */
  private async syncPushTokenAfterLogin(): Promise<void> {
    try {
      // 动态 import 避免循环依赖（PushManager 依赖 AccountManager，此处反向依赖需延迟加载）
      const pushModule = await import('../push/PushManager');
      const result = await pushModule.PushManager.getInstance().syncToken();
      if (result.success) {
        hilog.info(LOG_DOMAIN, TAG, 'T031: push token synced after login, len=%{public}d',
          result.data?.length ?? 0);
      } else {
        hilog.warn(LOG_DOMAIN, TAG, 'T031: push token sync skipped: %{public}s', result.message);
      }
    } catch (err) {
      hilog.error(LOG_DOMAIN, TAG, 'T031: push token sync exception: %{public}s',
        (err as Error).message ?? '');
    }
  }
}
