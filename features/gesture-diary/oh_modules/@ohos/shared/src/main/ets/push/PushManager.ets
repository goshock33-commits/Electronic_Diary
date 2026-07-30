// agentID: DEV-009
// agentID: DEV-017 (编译错误修复)
// 文件: PushManager.ets
// 任务: T030 PushManager 统一封装
// 说明: Push Kit 推送管理单例，实现 Token 获取/上传/监听统一管理
// 修复: 17 个编译错误（account null 检查、删除 getCloudAccountClass、移除交叉类型、简化 pushService API 调用）

// fix: DEV-019 · 修正 PushPayload 类型导入
import { pushService, pushCommon } from '@kit.PushKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import type common from '@ohos.app.ability.common';
import type Ability from '@ohos.app.ability.Ability';
import { AccountManager } from '../utils/AccountManager';
import { CloudDbService, CloudAccount } from '../cloud/CloudDbService';
import { FamilyManager, Result } from '../utils/FamilyManager';
import { FamilyMember } from '../data/FamilyMember';

const TAG = 'PushManager';
const LOG_DOMAIN = 0x0000;

/** 最近一次已上报云端的 push token（AppStorage 缓存，避免重复上传） */
const STORAGE_KEY_LAST_PUSH_TOKEN = 'push_token_last';

/**
 * PushManager —— Push Kit 推送管理单例。
 *
 * 职责：
 * 1. 统一 Push Token 获取与重试逻辑
 * 2. Token 变更监听（tokenUpdate 事件订阅）
 * 3. Token 上传到云端（Account.push_token + FamilyMember.push_token）
 * 4. 数据消息接收回调注册
 * 5. Token 本地缓存（push_token_cache 表）
 *
 * 用法（EntryAbility onCreate 内）：
 *   await PushManager.getInstance().initialize(this.context);
 *
 * 业务侧获取 token：
 *   const token = PushManager.getInstance().getToken();
 *
 * 所有方法不外抛异常，失败路径 hilog 记录并返回失败结果。
 */
export class PushManager {
  private static instance: PushManager | null = null;

  /** 当前 push token 缓存 */
  private currentToken: string = '';

  /** initialize 幂等标记 */
  private initialized: boolean = false;

  /** Ability 实例（pushService API 需要） */
  private ability: Ability | null = null;

  /** Token 获取重试次数上限 */
  private static readonly MAX_RETRY_COUNT: number = 3;

  /** Token 获取重试延迟（毫秒） */
  private static readonly RETRY_DELAY_MS: number = 2000;

  private constructor() {
  }

  /**
   * 获取全局单例。
   */
  static getInstance(): PushManager {
    if (PushManager.instance === null) {
      PushManager.instance = new PushManager();
    }
    return PushManager.instance;
  }

  // ===================== 初始化（EntryAbility 接线入口） =====================

  /**
   * 初始化 Push 管理（幂等，EntryAbility onCreate 调用）：
   * ① 获取 push token（带重试与失败降级）
   * ② 上传 token 到云端（Account + FamilyMember）
   * ③ 订阅 tokenUpdate 监听
   *
   * 任何一步失败均不影响本机功能，仅记录日志。
   *
   * fix: DEV-037 · 数据库未就绪时降级，避免 InitDatabase 错误阻塞启动
   *
   * @param ability UIAbility 实例（pushService API 需要）
   */
  async initialize(ability: Ability): Promise<void> {
    if (this.initialized) {
      hilog.info(LOG_DOMAIN, TAG, 'initialize: already initialized, skip');
      return;
    }
    this.initialized = true;
    this.ability = ability; // fix: DEV-018 · 存储 ability 实例供 pushService API 使用

    hilog.info(LOG_DOMAIN, TAG, 'initialize: start');

    // ① 获取 token（带重试）
    const tokenResult = await this.getTokenWithRetry();
    if (tokenResult.success && tokenResult.data) {
      this.currentToken = tokenResult.data;
      hilog.info(LOG_DOMAIN, TAG, 'initialize: token obtained, len=%{public}d', this.currentToken.length);
    } else {
      hilog.warn(LOG_DOMAIN, TAG, 'initialize: failed to get token, degraded mode');
      // 降级：token 获取失败不阻塞初始化，后续 tokenUpdate 可能补救
    }

    // ② 订阅 tokenUpdate 监听（token 变更时自动上传）
    this.subscribeTokenUpdate();

    // ③ 登录态恢复后上传 token（数据库依赖，降级处理）
    try {
      // fix: DEV-037 · 检查数据库是否就绪（DatabaseHelper.whenReady 门闩）
      const DatabaseHelper = (await import('../database/DatabaseHelper')).DatabaseHelper;
      await DatabaseHelper.getInstance().whenReady();

      await AccountManager.getInstance().init();
      if (AccountManager.getInstance().isLoggedIn() && this.currentToken.length > 0) {
        await this.uploadTokenToCloud(this.currentToken);
      } else {
        hilog.info(LOG_DOMAIN, TAG, 'initialize: not logged in or no token, upload deferred');
      }
    } catch (e) {
      // fix: DEV-037 · 数据库未就绪时降级为 warn，不外抛异常（tokenUpdate 后续可补救）
      hilog.warn(LOG_DOMAIN, TAG, 'initialize: database not ready or account init failed (degraded): %{public}s',
        (e as BusinessError).message);
    }

    hilog.info(LOG_DOMAIN, TAG, 'initialize: completed');
  }

  // ===================== Token 获取（带重试与降级） =====================

  /**
   * 获取 push token（带重试逻辑）。
   *
   * @returns Result<string> 成功时 data=token，失败时包含错误信息
   */
  private async getTokenWithRetry(): Promise<Result<string>> {
    let lastError: BusinessError | null = null;

    for (let attempt = 1; attempt <= PushManager.MAX_RETRY_COUNT; attempt++) {
      try {
        const token = await pushService.getToken();
        if (token && token.length > 0) {
          hilog.info(LOG_DOMAIN, TAG, 'getToken: success on attempt %{public}d', attempt);
          return Result.ok<string>(token);
        } else {
          hilog.warn(LOG_DOMAIN, TAG, 'getToken: empty token on attempt %{public}d', attempt);
        }
      } catch (e) {
        lastError = e as BusinessError;
        const errCode = lastError.code ?? 0;
        const errMsg = lastError.message ?? '';

        // 1000900010: 身份非法（AGC 未配 client_id）—— 不重试
        if (errCode === 1000900010) {
          hilog.error(LOG_DOMAIN, TAG, 'getToken: illegal identity (AGC not configured), abort retry');
          return Result.fail<string>('推送服务配置错误（1000900010）');
        }

        // 1000900011: 无网络 —— 可重试
        hilog.warn(LOG_DOMAIN, TAG, 'getToken: attempt %{public}d failed, code=%{public}d, msg=%{public}s',
          attempt, errCode, errMsg);

        if (attempt < PushManager.MAX_RETRY_COUNT) {
          await this.delay(PushManager.RETRY_DELAY_MS);
        }
      }
    }

    // 所有重试失败
    const finalErrMsg = lastError ? lastError.message : '未知错误';
    hilog.error(LOG_DOMAIN, TAG, 'getToken: all %{public}d attempts failed: %{public}s',
      PushManager.MAX_RETRY_COUNT, finalErrMsg);
    return Result.fail<string>('获取推送 token 失败: ' + finalErrMsg);
  }

  /**
   * 延迟指定毫秒数。
   */
  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  // ===================== Token 上传到云端 =====================

  /**
   * 上传 push token 到云端：
   * ① 写入 Account.push_token（云端账号表）
   * ② 写入本机 FamilyMember.push_token（本地 + 云端成员表）
   * ③ 缓存到 AppStorage（避免重复上传）
   *
   * 复用 VoiceReminderSender 已验证的上传逻辑。
   *
   * fix: DEV-037 · 数据库未就绪时降级返回失败，不外抛异常
   *
   * @param token Push token
   * @returns Result<string> 成功时 data=token
   */
  async uploadTokenToCloud(token: string): Promise<Result<string>> {
    const mgr = AccountManager.getInstance();
    if (!mgr.isLoggedIn()) {
      return Result.fail<string>('未登录，无法上报 push token');
    }

    const uid: string = mgr.getUid();

    // fix: DEV-037 · 检查数据库是否就绪
    try {
      const DatabaseHelper = (await import('../database/DatabaseHelper')).DatabaseHelper;
      await DatabaseHelper.getInstance().whenReady();
    } catch (e) {
      hilog.warn(LOG_DOMAIN, TAG, 'uploadTokenToCloud: database not ready, skip upload');
      return Result.fail<string>('数据库未就绪，push token 未上报');
    }

    // 检查 CloudDB zone 是否已打开
    if (!this.ensureZoneOpened()) {
      return Result.fail<string>('云服务不可用，push token 未上报');
    }

    const svc = CloudDbService.getInstance();

    // ① 本机成员行：uid 补绑 + push_token 写入
    let selfNickname: string = '';
    try {
      const selfRes: Result<FamilyMember> = await FamilyManager.getInstance().getSelf();
      if (selfRes.success && selfRes.data !== null) {
        const self: FamilyMember = selfRes.data;
        selfNickname = self.nickname;
        if (self.uid === null || self.uid.length === 0 || self.uid !== uid || self.push_token !== token) {
          self.uid = uid;
          self.push_token = token;
          await FamilyManager.getInstance().updateMember(self);
          hilog.info(LOG_DOMAIN, TAG, 'uploadTokenToCloud: self member updated with token');
        }
      } else {
        hilog.info(LOG_DOMAIN, TAG, 'uploadTokenToCloud: no self member yet, skip member row');
      }
    } catch (e) {
      hilog.warn(LOG_DOMAIN, TAG, 'uploadTokenToCloud: self member update failed: %{public}s',
        (e as BusinessError).message);
    }

    // ② 云端 Account 行：保留既有字段，仅更新 push_token
    try {
      let account: CloudAccount | null = await svc.queryAccountByUid(uid);
      if (account === null) {
        // 账号不存在时创建（理论上不应发生，登录时应已创建）
        account = new CloudAccount();
        account.uid = uid;
        account.phone = mgr.getPhone();
        account.nickname = selfNickname;
        account.created_at = Date.now();
        hilog.info(LOG_DOMAIN, TAG, 'uploadTokenToCloud: creating new Account record');
      }
      account.push_token = token;
      await svc.upsertAccount(account);

      // ③ 缓存到 AppStorage
      AppStorage.setOrCreate<string>(STORAGE_KEY_LAST_PUSH_TOKEN, token);

      hilog.info(LOG_DOMAIN, TAG, 'uploadTokenToCloud: success, uid=%{public}s tokenLen=%{public}d',
        uid, token.length);
      return Result.ok<string>(token);
    } catch (e) {
      hilog.error(LOG_DOMAIN, TAG, 'uploadTokenToCloud: Account upsert failed: %{public}s',
        (e as BusinessError).message);
      return Result.fail<string>('push token 云端上报失败');
    }
  }

  /**
   * 确保 CloudDB zone 已打开（复用 VoiceReminderSender 的模式）。
   */
  private ensureZoneOpened(): boolean {
    const svc = CloudDbService.getInstance();
    if (svc.isZoneOpened()) {
      return true;
    }
    try {
      svc.openCloudDBZone();
      return true;
    } catch (e) {
      hilog.warn(LOG_DOMAIN, TAG, 'ensureZoneOpened: openCloudDBZone failed (cloud degraded): %{public}s',
        (e as BusinessError).message);
      return false;
    }
  }

  // ===================== Token 变更监听 =====================

  /**
   * 订阅 tokenUpdate 事件（token 变更时自动上传）。
   *
   * fix: DEV-037 · subscribeTokenUpdate 失败降级为 warn（模拟器/系统不支持时不影响主流程）
   */
  private subscribeTokenUpdate(): void {
    if (!this.ability) {
      hilog.warn(LOG_DOMAIN, TAG, 'subscribeTokenUpdate: ability is null, skip (non-critical)');
      return;
    }

    try {
      // fix: DEV-018 · 补正 pushService API 参数（API 24 需要 3 个参数：type, ability, callback）
      pushService.on('tokenUpdate', this.ability, (newToken: string): void => {
        hilog.info(LOG_DOMAIN, TAG, 'tokenUpdate: received, len=%{public}d', newToken.length);

        // 更新内存缓存
        this.currentToken = newToken;

        // 自动上传到云端（异步，失败不阻塞）
        this.uploadTokenToCloud(newToken).catch((e: Error) => {
          hilog.error(LOG_DOMAIN, TAG, 'tokenUpdate: upload failed: %{public}s', e.message);
        });
      });
      hilog.info(LOG_DOMAIN, TAG, 'subscribeTokenUpdate: listener registered');
    } catch (e) {
      // fix: DEV-037 · API 不支持（模拟器/系统版本）时降级，不影响主流程
      hilog.warn(LOG_DOMAIN, TAG, 'subscribeTokenUpdate: failed (non-critical, maybe unsupported): %{public}s',
        (e as BusinessError).message);
    }
  }

  // ===================== 数据消息接收（预留接口） =====================

  /**
   * 注册数据消息回调（供 T033 使用）。
   *
   * @param onMessage 消息回调函数
   */
  // fix: DEV-019 · 修正 PushPayload 类型
  registerMessageListener(
    onMessage: (payload: pushCommon.PushPayload) => void
  ): void {
    if (!this.ability) {
      hilog.error(LOG_DOMAIN, TAG, 'registerMessageListener: ability is null, cannot register');
      return;
    }

    try {
      // fix: DEV-018 · 补正 pushService API 参数（API 24 需要 3 个参数：pushType, ability, onMessage）
      pushService.receiveMessage('IM', this.ability, onMessage);
      hilog.info(LOG_DOMAIN, TAG, 'registerMessageListener: listener registered');
    } catch (e) {
      hilog.warn(LOG_DOMAIN, TAG, 'registerMessageListener: failed: %{public}s', (e as BusinessError).message);
    }
  }

  // ===================== 公开 API =====================

  /**
   * 获取当前缓存的 push token。
   *
   * @returns 当前 token，未获取时返回空字符串
   */
  getToken(): string {
    return this.currentToken;
  }

  /**
   * 手动同步 token（登录后调用，或用户手动刷新）。
   * 检查 token 是否变更，变更则上传。
   *
   * @returns Result<string> 成功时 data=token
   */
  async syncToken(): Promise<Result<string>> {
    if (!AccountManager.getInstance().isLoggedIn()) {
      return Result.fail<string>('未登录，跳过 push token 同步');
    }

    // 重新获取 token
    const tokenResult = await this.getTokenWithRetry();
    if (!tokenResult.success || !tokenResult.data) {
      return tokenResult;
    }

    const newToken = tokenResult.data;
    this.currentToken = newToken;

    // 检查是否需要上传（与上次缓存比较）
    const lastToken: string | undefined = AppStorage.get<string>(STORAGE_KEY_LAST_PUSH_TOKEN);
    if (lastToken !== undefined && lastToken === newToken) {
      hilog.debug(LOG_DOMAIN, TAG, 'syncToken: token unchanged, skip upload');
      return Result.ok<string>(newToken);
    }

    // 上传到云端
    return this.uploadTokenToCloud(newToken);
  }
}
