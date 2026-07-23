// <!-- agentID: DEV-010 -->
// <!-- agentID: DEV-VOICE-REMIND -->
// File: VoiceReminderSender.ets
// Task: T307 跨设备语音提醒——发送端 + push token 上报维护（PLN-001_family_plan §T307）
// 链路：选择成员 + 内容（AI 生成/手输）→ 写 VoiceReminder 云表（status=pending）
//       → AGC 云函数 voice_push（定时触发器每分钟扫 status=pending 且 scheduled_at≤now）
//       → Push Kit 推送目标设备（title=发送人称呼，body=内容摘要）→ 标记 sent。
//       接收端点通知 → EntryAbility onNewWant 携带 voice_reminder_id → markAsRead 回写 status=read。
// token 上报：登录后 pushService.getToken() 写 Account.push_token + 本机 FamilyMember.push_token
//       （本地 + Cloud DB），并订阅 tokenUpdate 事件跟进 token 变更（T307「token 变更同步」）。
//
// ========== API 取证（本地 .d.ts，§8.3⑦ 禁凭记忆） ==========
// - pushService.getToken(): Promise<string>            ← @hms.core.push.pushService.d.ts L93
// - pushService.on('tokenUpdate', ability, cb): void   ← 同上 L274（Ability 形参=@ohos.app.ability.Ability）
// - Ability 由 @kit.AbilityKit 导出                     ← @kit.AbilityKit.d.ts L95（UIAbility extends Ability）
// - cloudDatabase.zone(name) 同步返回 DatabaseZone      ← @hms.core.deviceCloudGateway.cloudDatabase.d.ts L29
// - cloudCommon.init({databaseOptions:{schema}}) 端侧注册 schema（T601，CloudDbService 内部集中调用）
//                                                       ← @hms.core.deviceCloudGateway.cloudCommon.d.ts L29/L210-219
// 运行时前置（用户侧配置，非编译依赖）：AGC 已开通 Push Kit / Cloud DB；entry 的 module.json5
// 配置 client_id metadata 与 agconnect-services 资源，否则 getToken 抛 1000900010（仅日志降级，不崩溃）。
//
// 错误范式：全部收敛 Result<T>（对齐 FamilyManager），任何云端失败不外抛、不阻塞本机功能（断网降级红线）。

import { hilog } from '@kit.PerformanceAnalysisKit';
import { pushService } from '@kit.PushKit';
import { Ability } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CloudDbService, CloudAccount, VoiceReminder } from './CloudDbService';
import { AccountManager } from '../utils/AccountManager';
import { FamilyManager, Result } from '../utils/FamilyManager';
import { FamilyMember } from '../data/FamilyMember';

const TAG = 'VoiceReminderSender';

/** 最近一次已上报云端的 push token（AppStorage 缓存，避免重复上传；AppStorage 全局对象，§8.3② 禁 import） */
const STORAGE_KEY_LAST_PUSH_TOKEN = 'voice_push_token_last';

/** VoiceReminder.status 流转常量 */
export class VoiceReminderStatus {
  static readonly PENDING: string = 'pending';
  static readonly SENT: string = 'sent';
  static readonly READ: string = 'read';
}

/** sendReminder 可选参数（§8.2：禁匿名字面量靠推断，调用方须带显式类型） */
export interface VoiceReminderSendOptions {
  /** 期望播报/推送时刻（epoch ms）；缺省立即（云函数下一分钟扫描即推） */
  scheduledAt?: number;
  /** 推送标题（发送人称呼）；缺省取本机成员昵称，兜底「家人」 */
  title?: string;
}

/**
 * VoiceReminderSender —— 跨设备语音提醒发送端单例。
 *
 * 用法（EntryAbility onCreate 内）：
 *   VoiceReminderSender.getInstance().initialize(this);   // 开 zone + token 上报 + tokenUpdate 订阅
 * 业务侧（AI remind_member / 家庭页）：
 *   const res = await VoiceReminderSender.getInstance().sendReminder(member, '八点吃药', opts);
 *
 * 所有方法不外抛异常，失败路径 hilog 记录并返回 Result.fail。
 */
export class VoiceReminderSender {
  private static instance: VoiceReminderSender | null = null;

  /** initialize 幂等标记 */
  private initialized: boolean = false;

  private constructor() {
  }

  /** 获取全局单例。 */
  static getInstance(): VoiceReminderSender {
    if (VoiceReminderSender.instance === null) {
      VoiceReminderSender.instance = new VoiceReminderSender();
    }
    return VoiceReminderSender.instance;
  }

  // ===================== 初始化（EntryAbility 接线入口） =====================

  /**
   * 云同步初始化（幂等，EntryAbility onCreate 调用，任何一步失败均不影响本机功能）：
   * ① 打开 Cloud DB zone（AGC 未配置/无网时仅告警，后续云操作各自跳过）；
   * ② 订阅 pushService tokenUpdate（token 变更 → 重新上报，T307「token 变更同步」）；
   * ③ 恢复登录态后上报当前 push token（登录后 getToken 写 Account/FamilyMember 表）。
   */
  async initialize(ability: Ability): Promise<void> {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    // ① 打开 Cloud DB zone
    this.ensureZoneOpened();
    // ② token 变更订阅（API since 5.1.0(18)，本工程 API 24 满足）
    try {
      pushService.on('tokenUpdate', ability, (newToken: string): void => {
        hilog.info(0x0000, TAG, 'tokenUpdate event received, len=%{public}d', newToken.length);
        this.uploadPushToken(newToken).catch((e: Error) => {
          hilog.error(0x0000, TAG, 'tokenUpdate upload failed: %{public}s', e.message);
        });
      });
    } catch (e) {
      hilog.warn(0x0000, TAG, 'subscribe tokenUpdate failed: %{public}s', (e as BusinessError).message);
    }
    // ③ 登录态恢复后首轮 token 上报
    try {
      await AccountManager.getInstance().init();
      if (AccountManager.getInstance().isLoggedIn()) {
        await this.syncPushToken();
      } else {
        hilog.info(0x0000, TAG, 'initialize: not logged in, token sync deferred');
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'initialize token sync failed: %{public}s', (e as BusinessError).message);
    }
  }

  /** 打开 Cloud DB zone（已开跳过；AGC 未配置时 zone() 抛错→仅告警降级）。 */
  private ensureZoneOpened(): boolean {
    const svc = CloudDbService.getInstance();
    if (svc.isZoneOpened()) {
      return true;
    }
    try {
      svc.openCloudDBZone();
      return true;
    } catch (e) {
      hilog.warn(0x0000, TAG, 'openCloudDBZone failed (cloud features degraded): %{public}s',
        (e as BusinessError).message);
      return false;
    }
  }

  // ===================== push token 上报维护（T307） =====================

  /**
   * 获取当前 push token 并按需上报（登录后调用；与上次已上报值一致则跳过）。
   * @returns Result<string> 成功时 data=token
   */
  async syncPushToken(): Promise<Result<string>> {
    if (!AccountManager.getInstance().isLoggedIn()) {
      return Result.fail<string>('未登录，跳过 push token 上报');
    }
    let token: string = '';
    try {
      token = await pushService.getToken();
    } catch (e) {
      // 1000900010 身份非法（AGC 未配 client_id）/ 1000900011 无网络 —— 降级不致命
      hilog.warn(0x0000, TAG, 'getToken failed: %{public}s', (e as BusinessError).message);
      return Result.fail<string>('获取推送 token 失败');
    }
    if (token.length === 0) {
      return Result.fail<string>('推送 token 为空');
    }
    const last: string | undefined = AppStorage.get<string>(STORAGE_KEY_LAST_PUSH_TOKEN);
    if (last !== undefined && last === token) {
      hilog.debug(0x0000, TAG, 'syncPushToken: token unchanged, skip upload');
      return Result.ok<string>(token);
    }
    return this.uploadPushToken(token);
  }

  /**
   * 上报 push token：写云端 Account.push_token + 本机 FamilyMember.push_token（本地缓存 +
   * FamilyManager.updateMember 内部自动推 Cloud DB FamilyMember 表）。
   */
  private async uploadPushToken(token: string): Promise<Result<string>> {
    const mgr = AccountManager.getInstance();
    if (!mgr.isLoggedIn()) {
      return Result.fail<string>('未登录，无法上报 push token');
    }
    const uid: string = mgr.getUid();
    if (!this.ensureZoneOpened()) {
      return Result.fail<string>('云服务不可用，push token 未上报');
    }
    const svc = CloudDbService.getInstance();
    // ① 本机成员行：uid 补绑 + push_token 写入（updateMember 内部同步 Cloud DB FamilyMember）
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
        }
      } else {
        hilog.info(0x0000, TAG, 'uploadPushToken: no self member yet, skip member row');
      }
    } catch (e) {
      hilog.warn(0x0000, TAG, 'uploadPushToken self member update failed: %{public}s',
        (e as BusinessError).message);
    }
    // ② 云端 Account 行：保留既有 created_at/nickname，仅更新 push_token（无则建）
    try {
      let account: CloudAccount | null = await svc.queryAccountByUid(uid);
      if (account === null) {
        account = new CloudAccount();
        account.uid = uid;
        account.phone = mgr.getPhone();
        account.nickname = selfNickname;
        account.created_at = Date.now();
      }
      account.push_token = token;
      await svc.upsertAccount(account);
      AppStorage.setOrCreate<string>(STORAGE_KEY_LAST_PUSH_TOKEN, token);
      hilog.info(0x0000, TAG, 'uploadPushToken ok: uid=%{public}s tokenLen=%{public}d', uid, token.length);
      return Result.ok<string>(token);
    } catch (e) {
      hilog.error(0x0000, TAG, 'uploadPushToken Account upsert failed: %{public}s',
        (e as BusinessError).message);
      return Result.fail<string>('push token 云端上报失败');
    }
  }

  // ===================== 发送（T307 核心） =====================

  /**
   * 向家庭成员发送跨设备语音提醒：写 VoiceReminder 云表（status=pending），
   * 由云函数 voice_push 定时扫描推送到对方设备。
   *
   * 前置：本机已登录、对方成员已绑定账号（uid 非空）、已加入家庭（family_id 可从成员或本机推导）。
   * 不满足时返回 fail（message 可直接用于 UI/AI 回报），绝不抛异常。
   *
   * @param target  目标家庭成员（FamilyManager.findMemberByName / 家庭页选择）
   * @param message 提醒内容（推送 body + 对方端 TTS 播报文本）
   * @param options 可选：scheduledAt 定时（缺省立即）、title 推送标题（缺省本机昵称）
   * @returns Result<string> 成功时 data=reminder_id
   */
  async sendReminder(target: FamilyMember, message: string,
    options?: VoiceReminderSendOptions): Promise<Result<string>> {
    const content: string = message.trim();
    if (content.length === 0) {
      return Result.fail<string>('提醒内容不能为空');
    }
    const mgr = AccountManager.getInstance();
    if (!mgr.isLoggedIn()) {
      return Result.fail<string>('未登录，无法发送跨设备提醒');
    }
    const fromUid: string = mgr.getUid();
    const toUid: string = target.uid ?? '';
    if (toUid.length === 0) {
      return Result.fail<string>('对方还未绑定账号，无法推送到对方设备');
    }
    if (toUid === fromUid) {
      return Result.fail<string>('目标是本机账号，无需跨设备提醒');
    }
    // family_id：目标成员 → 本机成员 兜底
    let familyId: string = target.family_id ?? '';
    if (familyId.length === 0) {
      const selfRes: Result<FamilyMember> = await FamilyManager.getInstance().getSelf();
      if (selfRes.success && selfRes.data !== null) {
        familyId = selfRes.data.family_id ?? '';
      }
    }
    if (familyId.length === 0) {
      return Result.fail<string>('尚未加入家庭，无法发送跨设备提醒');
    }
    if (!this.ensureZoneOpened()) {
      return Result.fail<string>('云服务不可用，请稍后重试');
    }
    // 推送标题=发送人称呼（PLN T307：title=发送人称呼，body=内容摘要）
    let title: string = options !== undefined && options.title !== undefined ? options.title : '';
    if (title.length === 0) {
      const selfRes: Result<FamilyMember> = await FamilyManager.getInstance().getSelf();
      if (selfRes.success && selfRes.data !== null && selfRes.data.nickname.length > 0) {
        title = selfRes.data.nickname;
      } else {
        title = '家人';
      }
    }
    const now: number = Date.now();
    let scheduledAt: number = options !== undefined && options.scheduledAt !== undefined
      ? options.scheduledAt : now;
    if (scheduledAt < now) {
      scheduledAt = now;
    }
    const reminder = new VoiceReminder();
    reminder.reminder_id = 'vr_' + fromUid + '_' + now.toString() + '_' +
      Math.floor(Math.random() * 10000).toString();
    reminder.family_id = familyId;
    reminder.from_uid = fromUid;
    reminder.to_uid = toUid;
    reminder.to_nickname = target.nickname;
    reminder.title = title;
    reminder.message = content;
    reminder.scheduled_at = scheduledAt;
    reminder.status = VoiceReminderStatus.PENDING;
    // T601: 云端 schema 该字段为 String（clouddb_schema.json），端侧类已同型 string
    reminder.created_at = now.toString();
    try {
      await CloudDbService.getInstance().upsertVoiceReminder(reminder);
      hilog.info(0x0000, TAG, 'sendReminder ok: id=%{public}s to=%{public}s scheduled=%{public}d',
        reminder.reminder_id, target.nickname, scheduledAt);
      return Result.ok<string>(reminder.reminder_id);
    } catch (e) {
      hilog.error(0x0000, TAG, 'sendReminder upsert failed: %{public}s', (e as BusinessError).message);
      return Result.fail<string>('云端写入失败，请检查网络后重试');
    }
  }

  // ===================== 已读回写（T308 接收端配套） =====================

  /**
   * 标记提醒已读（接收端点通知拉起 / TTS 播报完成后回写 status=read，发送端可见流转）。
   * @returns Result<string> 成功时 data=reminder_id
   */
  async markAsRead(reminderId: string): Promise<Result<string>> {
    const id: string = reminderId.trim();
    if (id.length === 0) {
      return Result.fail<string>('reminder_id 为空');
    }
    if (!this.ensureZoneOpened()) {
      return Result.fail<string>('云服务不可用');
    }
    try {
      const svc = CloudDbService.getInstance();
      const reminder: VoiceReminder | null = await svc.queryVoiceReminderById(id);
      if (reminder === null) {
        return Result.fail<string>('提醒不存在或已被删除');
      }
      if (reminder.status === VoiceReminderStatus.READ) {
        return Result.ok<string>(id);
      }
      reminder.status = VoiceReminderStatus.READ;
      await svc.upsertVoiceReminder(reminder);
      hilog.info(0x0000, TAG, 'markAsRead ok: id=%{public}s', id);
      return Result.ok<string>(id);
    } catch (e) {
      hilog.error(0x0000, TAG, 'markAsRead failed: %{public}s', (e as BusinessError).message);
      return Result.fail<string>('已读状态回写失败');
    }
  }
}
