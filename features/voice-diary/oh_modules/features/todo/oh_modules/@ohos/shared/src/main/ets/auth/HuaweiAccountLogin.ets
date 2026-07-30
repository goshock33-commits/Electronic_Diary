// <!-- agentID: DEV-023 -->
// File: HuaweiAccountLogin.ets
// Task: T-DEV-023 华为账号 OAuth 登录（修复 DEV-021 动态 import + DEV-022 Function 类型两层 hack）
// Architecture: REFACTOR_ARCHITECTURE.md §4 + USER_DATA_SUPPLEMENT.md §4
//
// 🔴 API 真相源 = 本地 SDK 声明文件（非记忆、非网页文档）
// [K] sdk/default/hms/ets/kits/@kit.AccountKit.d.ts
//     L9  import authentication from '@hms.core.authentication'
//     L16 export { authentication, ... }   → 静态 import { authentication } from '@kit.AccountKit' 成立
// [A] sdk/default/hms/ets/api/@hms.core.authentication.d.ts
//     L25   declare namespace authentication
//     L1188 class HuaweiIDProvider extends AuthenticationProvider（无自定义构造 → new 无参）
//     L1228   createAuthorizationWithHuaweiIDRequest(): AuthorizationWithHuaweiIDRequest
//     L613  class AuthorizationWithHuaweiIDRequest extends AuthenticationRequest
//     L629    scopes?: string[]
//     L645    permissions?: string[]
//     L671    forceAuthorization?: boolean  ⚠️ 本请求类无 forceLogin（forceLogin 属 LoginWithHuaweiIDRequest L534）
//     L1313 class AuthenticationController
//     L1329   constructor(context?: common.Context)  ← UIAbilityContext 是 Context 子类型，可直接传
//     L1425   executeRequest(request: AuthenticationRequest): Promise<AuthenticationResponse>
//     L1100 class AuthorizationWithHuaweiIDResponse extends AuthenticationResponse
//     L1118   readonly data?: AuthorizationWithHuaweiIDCredential
//     L880  interface AuthorizationWithHuaweiIDCredential
//     L931    readonly openID?: string
//     L950    readonly unionID?: string
//     L968    readonly avatarUri?: string
//     L986    readonly nickName?: string
//     L131  enum AuthenticationErrorCode
//           USER_CANCELED=1001502012 / NETWORK_ERROR=1001502005 / ACCOUNT_NOT_LOGGED_IN=1001502001
//           APP_NOT_AUTHORIZED=1001502002 / SCOPE_OR_PERMISSION_NOT_REQUESTED=1001502014
// [G] sdk/default/openharmony/ets/api/@internal/full/global.d.ts:727
//     export declare function canIUse(syscap: string): boolean  → 替代运行时动态 import 探测

import { authentication } from '@kit.AccountKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AccountDao } from '../database/dao/AccountDao';

const TAG: string = 'HuaweiAccountLogin';
const LOG_DOMAIN: number = 0xFF00;

/** 认证服务 syscap（[A] L13 @syscap 标注值） */
const AUTH_SYSCAP: string = 'SystemCapability.AuthenticationServices.HuaweiID.Auth';

/** 授权 scopes：openid → openID/unionID，profile → nickName/avatarUri */
const AUTH_SCOPES: string[] = ['openid', 'profile'];

/**
 * 华为账号 OAuth 登录服务
 *
 * 功能：
 * 1. 华为账号 OAuth 授权登录（AuthorizationWithHuaweiIDRequest）
 * 2. 获取用户标识与资料（unionID / openID / nickName / avatarUri）
 * 3. 生成 uid 并缓存到本地 Account 表
 *
 * uid 生成规范（USER_DATA_SUPPLEMENT.md §4）：
 * - 优先 unionID（跨应用稳定标识符）
 * - 降级 openID（应用内标识符）
 */
export class HuaweiAccountLogin {
  /**
   * 华为账号一键登录
   *
   * @param context UIAbilityContext（[A] L1329 形参类型 common.Context 的子类型）
   * @returns Promise<string> uid；失败抛 Error
   */
  static async login(context: common.UIAbilityContext): Promise<string> {
    hilog.info(LOG_DOMAIN, TAG, 'Starting Huawei Account OAuth login');

    try {
      // Step 1: Provider 与授权请求（[A] L1188 / L1228）
      const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
      const request: authentication.AuthorizationWithHuaweiIDRequest =
        provider.createAuthorizationWithHuaweiIDRequest();

      // Step 2: 填充请求参数（字段名对照 [A] L629 / L671）
      request.scopes = AUTH_SCOPES;
      // forceAuthorization=false：允许静默复用已登录的华为账号（[A] L659-671）
      request.forceAuthorization = false;

      // Step 3: 执行授权（[A] L1329 构造 + L1425 Promise 重载）
      const controller: authentication.AuthenticationController =
        new authentication.AuthenticationController(context);
      const rawResponse: authentication.AuthenticationResponse = await controller.executeRequest(request);
      const response: authentication.AuthorizationWithHuaweiIDResponse =
        rawResponse as authentication.AuthorizationWithHuaweiIDResponse;

      // Step 4: 取凭证（[A] L1118 data 为可选字段）
      const credential: authentication.AuthorizationWithHuaweiIDCredential | undefined = response.data;
      if (credential === undefined) {
        throw new Error('授权失败：未获取到凭证信息');
      }

      // Step 5: 提取用户标识与资料（[A] L931 / L950 / L968 / L986，均为 optional）
      const unionID: string | undefined = credential.unionID;
      const openID: string | undefined = credential.openID;
      const nickName: string | undefined = credential.nickName;
      const avatarUri: string | undefined = credential.avatarUri;

      hilog.info(LOG_DOMAIN, TAG,
        'Auth success: unionID=%{public}s openID=%{public}s nickname=%{public}s',
        unionID !== undefined && unionID.length > 0 ? 'exists' : 'null',
        openID !== undefined && openID.length > 0 ? 'exists' : 'null',
        nickName !== undefined ? nickName : 'null');

      // Step 6: uid 生成规范（USER_DATA_SUPPLEMENT.md §4）unionID 优先，降级 openID
      let uid: string = '';
      if (unionID !== undefined && unionID.length > 0) {
        uid = unionID;
      } else if (openID !== undefined && openID.length > 0) {
        uid = openID;
      }
      if (uid.length === 0) {
        throw new Error('授权失败：未获取到用户标识（unionID 和 openID 均为空）');
      }

      // Step 7: 缓存登录态到本地
      await HuaweiAccountLogin.cacheLoginLocally(uid, nickName, avatarUri);

      hilog.info(LOG_DOMAIN, TAG, 'Huawei Account login success: uid=%{public}s', uid);
      return uid;

    } catch (err) {
      const error = err as BusinessError;
      const code: number = error.code !== undefined ? error.code : 0;
      const rawMsg: string = error.message !== undefined ? error.message : '';
      hilog.error(LOG_DOMAIN, TAG, 'Login failed: code=%{public}d message=%{public}s', code, rawMsg);

      // 错误分流：错误码全部取自 [A] L131 AuthenticationErrorCode 枚举
      let userMessage: string = '登录失败：';
      if (code === authentication.AuthenticationErrorCode.USER_CANCELED) {
        userMessage += '用户取消授权';
      } else if (code === authentication.AuthenticationErrorCode.NETWORK_ERROR) {
        userMessage += '网络异常，请检查网络连接';
      } else if (code === authentication.AuthenticationErrorCode.ACCOUNT_NOT_LOGGED_IN) {
        userMessage += '设备未登录华为账号，请先在系统设置中登录';
      } else if (code === authentication.AuthenticationErrorCode.APP_NOT_AUTHORIZED) {
        userMessage += '应用未获授权，请检查 AGC 配置';
      } else if (code === authentication.AuthenticationErrorCode.SCOPE_OR_PERMISSION_NOT_REQUESTED) {
        userMessage += '缺少必要的授权范围';
      } else {
        userMessage += rawMsg.length > 0 ? rawMsg : '未知错误';
      }

      throw new Error(userMessage);
    }
  }

  /**
   * 缓存登录态到本地 Account 表
   *
   * 落库接口签名（codegraph 核实）：
   * - AccountDao.saveLoginAccount(uid, phone, token, nickname?) : Promise<void>（内含 upsert + 自愈补列）
   * - AccountDao.updateProfile(uid, avatar, gender, birthday, bio) : Promise<number>
   *
   * @param uid 用户唯一标识（unionID 或 openID）
   * @param nickname 用户昵称（可选）
   * @param avatarUri 用户头像 URI（可选）
   */
  private static async cacheLoginLocally(
    uid: string,
    nickname?: string,
    avatarUri?: string
  ): Promise<void> {
    try {
      const nick: string = nickname !== undefined && nickname.length > 0 ? nickname : '华为用户';
      const phone: string = ''; // 华为账号登录不涉及手机号，留空
      const token: string = ''; // OAuth 方式不使用 token 字段，留空占位

      await AccountDao.saveLoginAccount(uid, phone, token, nick);

      // 有头像时补写 avatar 列（updateProfile 为全量覆盖口径，其余 3 列传 null）
      if (avatarUri !== undefined && avatarUri.length > 0) {
        await AccountDao.updateProfile(uid, avatarUri, null, null, null);
        hilog.info(LOG_DOMAIN, TAG, 'Avatar updated: %{public}s', avatarUri);
      }

      // 写入全局状态（供 AccountManager / FamilyManager 等使用）
      AppStorage.setOrCreate<string>('current_user_uid', uid);

      hilog.info(LOG_DOMAIN, TAG, 'Login cached locally: uid=%{public}s nickname=%{public}s', uid, nick);

    } catch (err) {
      const msg: string = (err as Error).message !== undefined ? (err as Error).message : '';
      hilog.error(LOG_DOMAIN, TAG, 'Failed to cache login locally: %{public}s', msg);
      throw new Error('保存登录状态失败：' + msg);
    }
  }

  /**
   * 检查华为账号认证服务是否可用
   *
   * 静态 import 后模块存在性由编译期保证，运行时只需判设备 syscap（[G] canIUse）。
   * 保留 Promise<boolean> 签名以不破坏既有调用方。
   */
  static async isHuaweiAccountAvailable(): Promise<boolean> {
    const available: boolean = canIUse(AUTH_SYSCAP);
    if (!available) {
      hilog.warn(LOG_DOMAIN, TAG, 'HUAWEI ID auth syscap unavailable on this device');
    }
    return available;
  }
}
