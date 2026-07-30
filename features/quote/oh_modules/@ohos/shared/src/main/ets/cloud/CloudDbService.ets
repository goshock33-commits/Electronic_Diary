// <!-- agentID: DEV-010 -->
// <!-- agentID: DEV-VOICE-REMIND -->
// <!-- agentID: DEV-012 -->
// File: CloudDbService.ets
// Task: AGC Cloud DB SDK encapsulation
// Four tables: Account / Family / FamilyMember / VoiceReminder
// openCloudDBZone + upsert/delete/query + sync callback re-read
// SDK: @kit.CloudFoundationKit (API 24 / 6.1.1)
// fix: T601 · Cloud DB 端侧 schema 注册（根因修复 "schema parse fail or objectTypeName error"）：
//   本地 SDK 实证（PROJECT_SPEC §8.3⑦/§10，禁凭记忆）：
//   · cloudDatabase.zone(zone: string) 仅 1 个参数，无 objectTypeInfo，全文件无任何 schema 注册 API
//     ← @hms.core.deviceCloudGateway.cloudDatabase.d.ts L29（namespace cloudDatabase 全量 L19-545）
//   · 端侧注册唯一入口 = cloudCommon.init({ databaseOptions: { schema: rawfile 文件名 } })
//     ← @hms.core.deviceCloudGateway.cloudCommon.d.ts L29 init(options?: CloudOptions) /
//       L210-229 DatabaseOptions.schema（d.ts 注释原文：缺省读 rawfile 目录下 app-schema.json）
//   本工程 schema 文件名为 clouddb_schema.json（AppScope/resources/rawfile/，构建期合入 HAP rawfile 根，
//   见 entry/build/.../resources/rawfile/），与 SDK 缺省名不符 → 必须显式 init 指定文件名。
//   openCloudDBZone() 内部「先注册后开 zone」，全部调用方（AccountManager/VoiceReminderSender
//   的 ensureZoneOpened）零改动自动覆盖。

import { cloudDatabase, cloudCommon } from '@kit.CloudFoundationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'CloudDbService';
// T601-fix2: 原拟 'HuaweiDiary' 在 AGC 控制台创建存储区被拒（品牌词 Huawei 被平台隐性拦截，
// 报错文案只提字符规则）。经用户决策改用 'ElectronicDiary'，须与控制台存储区名逐字符一致（大小写敏感）。
const DEFAULT_ZONE_NAME = 'ElectronicDiary';
/** T601: 端侧 schema 文件名（AppScope/resources/rawfile/clouddb_schema.json，构建期合入 HAP rawfile 根目录） */
const SCHEMA_RAW_FILE = 'clouddb_schema.json';

// ===================== Cloud DB Object Type Definitions =====================

export class CloudAccount extends cloudDatabase.DatabaseObject {
  uid: string = '';
  phone: string = '';
  password: string = '';
  nickname: string = '';
  push_token: string = '';
  created_at: number = 0;

  naturalbase_ClassName(): string {
    return 'Account';
  }
}

export class CloudFamily extends cloudDatabase.DatabaseObject {
  family_id: string = '';
  name: string = '';
  invite_code: string = '';
  owner_uid: string = '';
  created_at: number = 0;

  naturalbase_ClassName(): string {
    return 'Family';
  }
}

export class CloudFamilyMember extends cloudDatabase.DatabaseObject {
  member_id: string = '';
  family_id: string = '';
  uid: string = '';
  nickname: string = '';
  aliases: string = '[]';
  role: string = 'member';
  push_token: string = '';
  created_at: number = 0;

  naturalbase_ClassName(): string {
    return 'FamilyMember';
  }
}

export class VoiceReminder extends cloudDatabase.DatabaseObject {
  reminder_id: string = '';
  family_id: string = '';
  from_uid: string = '';
  to_uid: string = '';
  to_nickname: string = '';
  title: string = '';
  message: string = '';
  scheduled_at: number = 0;
  status: string = 'pending';
  // T601: 云端 schema 此字段为 String（clouddb_schema.json → VoiceReminder.created_at fieldType=String），
  // schema 注册生效后端侧必须同型，否则 upsert 报对象校验错（1008230002/1008230003）
  created_at: string = '0';

  naturalbase_ClassName(): string {
    return 'VoiceReminder';
  }
}

// agentID: DEV-013
// T032: 家庭消息流 CloudDB 对象类型（对应 FamilyMessage 云表）
export class CloudFamilyMessage extends cloudDatabase.DatabaseObject {
  message_id: string = '';
  family_id: string = '';
  from_uid: string = '';
  to_uid: string = '';
  type: string = 'todo';
  content: string = '';
  reference_id: string = '';
  read_status: number = 0;
  created_at: number = 0;

  naturalbase_ClassName(): string {
    return 'FamilyMessage';
  }
}

// ===================== CloudDbService Singleton =====================

export class CloudDbService {
  private static instance: CloudDbService | null = null;
  private zone: cloudDatabase.DatabaseZone | null = null;
  private zoneName: string = DEFAULT_ZONE_NAME;
  /** T601: cloudCommon.init 幂等标记（进程级注册一次即可） */
  private schemaRegistered: boolean = false;
  private syncListeners: Array<() => void> = [];

  private constructor() {
  }

  static getInstance(): CloudDbService {
    if (CloudDbService.instance === null) {
      CloudDbService.instance = new CloudDbService();
    }
    return CloudDbService.instance;
  }

  // ===================== Zone Initialization =====================

  /**
   * Open a Cloud DB zone（cloudDatabase.zone 同步返回，cloudDatabase.d.ts L29）。
   * T601: 内部先做端侧 schema 注册（registerSchema → cloudCommon.init）再开 zone，
   * 调用方无需感知 schema；注意 cloudDatabase.zone() 无 objectTypeInfo 参数（本地 d.ts 实证），
   * 端侧对象类型结构只能经 cloudCommon.init 的 databaseOptions.schema 注册。
   * @param zoneName - Zone name（缺省 DEFAULT_ZONE_NAME = 'ElectronicDiary'）
   * @param schemaFile - 可选：rawfile 下 schema 配置文件名，缺省 SCHEMA_RAW_FILE
   *   ('clouddb_schema.json')。SDK 缺省找 app-schema.json（cloudCommon.d.ts L212），
   *   与本工程文件名不符，不显式注册即报 "schema parse fail or objectTypeName error"。
   */
  openCloudDBZone(zoneName?: string, schemaFile?: string): cloudDatabase.DatabaseZone {
    if (zoneName !== undefined) {
      this.zoneName = zoneName;
    }
    this.registerSchema(schemaFile !== undefined ? schemaFile : SCHEMA_RAW_FILE);
    this.zone = cloudDatabase.zone(this.zoneName);
    hilog.info(0x0000, TAG, 'openCloudDBZone: zone=%{public}s', this.zoneName);
    return this.zone;
  }

  /**
   * T601: 端侧注册云端对象类型结构（幂等）。
   * cloudCommon.init(options?: CloudOptions): void ← cloudCommon.d.ts L29；
   * DatabaseOptions.schema = rawfile 目录下 schema 配置文件路径 ← 同文件 L210-219。
   * init 失败抛 BusinessError 401，交由调用方 ensureZoneOpened 既有 try/catch 降级
   * （AccountManager toast / VoiceReminderSender 日志），此处不吞错。
   */
  private registerSchema(schemaFile: string): void {
    if (this.schemaRegistered) {
      return;
    }
    const dbOptions: cloudCommon.DatabaseOptions = { schema: schemaFile };
    const cloudOptions: cloudCommon.CloudOptions = { databaseOptions: dbOptions };
    cloudCommon.init(cloudOptions);
    this.schemaRegistered = true;
    hilog.info(0x0000, TAG, 'registerSchema: cloudCommon.init ok, schema=%{public}s', schemaFile);
  }

  /**
   * Get the current DatabaseZone instance.
   * Throws if zone not opened yet.
   */
  getZone(): cloudDatabase.DatabaseZone {
    if (this.zone === null) {
      throw new Error('Cloud DB zone not opened. Call openCloudDBZone() first.');
    }
    return this.zone;
  }

  isZoneOpened(): boolean {
    return this.zone !== null;
  }

  // ===================== Account CRUD =====================

  async upsertAccount(account: CloudAccount): Promise<number> {
    const z = this.getZone();
    const count = await z.upsert(account);
    hilog.info(0x0000, TAG, 'upsertAccount: uid=%{public}s count=%{public}d', account.uid, count);
    this.notifySync();
    return count;
  }

  async deleteAccount(account: CloudAccount): Promise<number> {
    const z = this.getZone();
    const count = await z.delete(account);
    hilog.info(0x0000, TAG, 'deleteAccount: uid=%{public}s count=%{public}d', account.uid, count);
    this.notifySync();
    return count;
  }

  async queryAccounts(): Promise<CloudAccount[]> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(CloudAccount);
    const results = await z.query(query);
    hilog.info(0x0000, TAG, 'queryAccounts: count=%{public}d', results.length);
    return results;
  }

  async queryAccountByUid(uid: string): Promise<CloudAccount | null> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(CloudAccount);
    query.equalTo('uid', uid);
    const results = await z.query(query);
    if (results.length > 0) {
      return results[0];
    }
    return null;
  }

  async queryAccountByPhone(phone: string): Promise<CloudAccount | null> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(CloudAccount);
    query.equalTo('phone', phone);
    const results = await z.query(query);
    hilog.info(0x0000, TAG, 'queryAccountByPhone: hit=%{public}d', results.length);
    if (results.length > 0) {
      return results[0];
    }
    return null;
  }

  // ===================== Family CRUD =====================

  async upsertFamily(family: CloudFamily): Promise<number> {
    const z = this.getZone();
    const count = await z.upsert(family);
    hilog.info(0x0000, TAG, 'upsertFamily: family_id=%{public}s count=%{public}d', family.family_id, count);
    this.notifySync();
    return count;
  }

  async deleteFamily(family: CloudFamily): Promise<number> {
    const z = this.getZone();
    const count = await z.delete(family);
    hilog.info(0x0000, TAG, 'deleteFamily: family_id=%{public}s count=%{public}d', family.family_id, count);
    this.notifySync();
    return count;
  }

  async queryFamilies(): Promise<CloudFamily[]> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(CloudFamily);
    const results = await z.query(query);
    hilog.info(0x0000, TAG, 'queryFamilies: count=%{public}d', results.length);
    return results;
  }

  async queryFamilyById(familyId: string): Promise<CloudFamily | null> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(CloudFamily);
    query.equalTo('family_id', familyId);
    const results = await z.query(query);
    if (results.length > 0) {
      return results[0];
    }
    return null;
  }

  async queryFamiliesByOwner(ownerUid: string): Promise<CloudFamily[]> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(CloudFamily);
    query.equalTo('owner_uid', ownerUid);
    const results = await z.query(query);
    hilog.info(0x0000, TAG, 'queryFamiliesByOwner: owner=%{public}s count=%{public}d', ownerUid, results.length);
    return results;
  }

  /**
   * T602: 按邀请码查询家庭（joinFamily 云端验证用）。
   * Family 表 invite_code 字段建有唯一索引，最坏情况命中 0 或 1 行。
   */
  async queryFamilyByInviteCode(inviteCode: string): Promise<CloudFamily | null> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(CloudFamily);
    query.equalTo('invite_code', inviteCode);
    const results = await z.query(query);
    hilog.info(0x0000, TAG, 'queryFamilyByInviteCode: code=%{public}s hit=%{public}d', inviteCode, results.length);
    if (results.length > 0) {
      return results[0];
    }
    return null;
  }

  // ===================== FamilyMember CRUD =====================

  async upsertFamilyMember(member: CloudFamilyMember): Promise<number> {
    const z = this.getZone();
    const count = await z.upsert(member);
    hilog.info(0x0000, TAG, 'upsertFamilyMember: member_id=%{public}s count=%{public}d', member.member_id, count);
    this.notifySync();
    return count;
  }

  async deleteFamilyMember(member: CloudFamilyMember): Promise<number> {
    const z = this.getZone();
    const count = await z.delete(member);
    hilog.info(0x0000, TAG, 'deleteFamilyMember: member_id=%{public}s count=%{public}d', member.member_id, count);
    this.notifySync();
    return count;
  }

  async queryFamilyMembers(familyId: string): Promise<CloudFamilyMember[]> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(CloudFamilyMember);
    query.equalTo('family_id', familyId);
    const results = await z.query(query);
    hilog.info(0x0000, TAG, 'queryFamilyMembers: family=%{public}s count=%{public}d', familyId, results.length);
    return results;
  }

  async queryFamilyMemberById(memberId: string): Promise<CloudFamilyMember | null> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(CloudFamilyMember);
    query.equalTo('member_id', memberId);
    const results = await z.query(query);
    if (results.length > 0) {
      return results[0];
    }
    return null;
  }

  async queryFamilyMemberByFamilyAndUid(familyId: string, uid: string): Promise<CloudFamilyMember | null> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(CloudFamilyMember);
    query.equalTo('family_id', familyId);
    query.equalTo('uid', uid);
    const results = await z.query(query);
    if (results.length > 0) {
      return results[0];
    }
    return null;
  }

  // <!-- agentID: DEV-012 -->
  /** 按 uid 查 FamilyMember 表（不限 family_id），用于 init() 恢复非 owner 的加入家庭场景。 */
  async queryFamilyMemberByUid(uid: string): Promise<CloudFamilyMember | null> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(CloudFamilyMember);
    query.equalTo('uid', uid);
    query.limit(1);
    const results = await z.query(query);
    if (results.length > 0) {
      return results[0];
    }
    return null;
  }

  // ===================== VoiceReminder CRUD =====================

  async upsertVoiceReminder(reminder: VoiceReminder): Promise<number> {
    const z = this.getZone();
    const count = await z.upsert(reminder);
    hilog.info(0x0000, TAG, 'upsertVoiceReminder: reminder_id=%{public}s count=%{public}d',
      reminder.reminder_id, count);
    this.notifySync();
    return count;
  }

  async deleteVoiceReminder(reminder: VoiceReminder): Promise<number> {
    const z = this.getZone();
    const count = await z.delete(reminder);
    hilog.info(0x0000, TAG, 'deleteVoiceReminder: reminder_id=%{public}s count=%{public}d',
      reminder.reminder_id, count);
    this.notifySync();
    return count;
  }

  async queryVoiceReminders(toUid: string): Promise<VoiceReminder[]> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(VoiceReminder);
    query.equalTo('to_uid', toUid);
    const results = await z.query(query);
    hilog.info(0x0000, TAG, 'queryVoiceReminders: to_uid=%{public}s count=%{public}d', toUid, results.length);
    return results;
  }

  async queryVoiceRemindersByFamily(familyId: string): Promise<VoiceReminder[]> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(VoiceReminder);
    query.equalTo('family_id', familyId);
    const results = await z.query(query);
    hilog.info(0x0000, TAG, 'queryVoiceRemindersByFamily: family=%{public}s count=%{public}d',
      familyId, results.length);
    return results;
  }

  async queryVoiceReminderById(reminderId: string): Promise<VoiceReminder | null> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(VoiceReminder);
    query.equalTo('reminder_id', reminderId);
    const results = await z.query(query);
    if (results.length > 0) {
      return results[0];
    }
    return null;
  }

  async queryPendingVoiceReminders(toUid: string): Promise<VoiceReminder[]> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(VoiceReminder);
    query.equalTo('status', 'pending');
    query.equalTo('to_uid', toUid);
    query.orderByAsc('scheduled_at');
    const results = await z.query(query);
    hilog.info(0x0000, TAG, 'queryPendingVoiceReminders: to_uid=%{public}s count=%{public}d',
      toUid, results.length);
    return results;
  }

  // ===================== FamilyMessage CRUD (agentID: DEV-013 · T032) =====================

  async upsertFamilyMessage(message: CloudFamilyMessage): Promise<number> {
    const z = this.getZone();
    const count = await z.upsert(message);
    hilog.info(0x0000, TAG, 'upsertFamilyMessage: message_id=%{public}s count=%{public}d',
      message.message_id, count);
    this.notifySync();
    return count;
  }

  async deleteFamilyMessage(message: CloudFamilyMessage): Promise<number> {
    const z = this.getZone();
    const count = await z.delete(message);
    hilog.info(0x0000, TAG, 'deleteFamilyMessage: message_id=%{public}s count=%{public}d',
      message.message_id, count);
    this.notifySync();
    return count;
  }

  async queryMyFamilyMessages(toUid: string): Promise<CloudFamilyMessage[]> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(CloudFamilyMessage);
    query.equalTo('to_uid', toUid);
    query.orderByDesc('created_at');
    const results = await z.query(query);
    hilog.info(0x0000, TAG, 'queryMyFamilyMessages: to_uid=%{public}s count=%{public}d',
      toUid, results.length);
    return results;
  }

  async queryFamilyMessageById(messageId: string): Promise<CloudFamilyMessage | null> {
    const z = this.getZone();
    const query = new cloudDatabase.DatabaseQuery(CloudFamilyMessage);
    query.equalTo('message_id', messageId);
    const results = await z.query(query);
    if (results.length > 0) {
      return results[0];
    }
    return null;
  }

  // ===================== Batch Operations =====================

  async batchUpsert<T extends cloudDatabase.DatabaseObject>(objects: T[]): Promise<number> {
    if (objects.length === 0) {
      return 0;
    }
    const z = this.getZone();
    const count = await z.upsert(objects);
    hilog.info(0x0000, TAG, 'batchUpsert: count=%{public}d', count);
    this.notifySync();
    return count;
  }

  async batchDelete<T extends cloudDatabase.DatabaseObject>(objects: T[]): Promise<number> {
    if (objects.length === 0) {
      return 0;
    }
    const z = this.getZone();
    const count = await z.delete(objects);
    hilog.info(0x0000, TAG, 'batchDelete: count=%{public}d', count);
    this.notifySync();
    return count;
  }

  // ===================== Sync Callback =====================

  setSyncListener(listener: () => void): void {
    this.syncListeners.push(listener);
    hilog.info(0x0000, TAG, 'setSyncListener: total listeners=%{public}d', this.syncListeners.length);
  }

  removeSyncListener(listener: () => void): boolean {
    const idx = this.syncListeners.indexOf(listener);
    if (idx >= 0) {
      this.syncListeners.splice(idx, 1);
      hilog.info(0x0000, TAG, 'removeSyncListener: removed, remaining=%{public}d', this.syncListeners.length);
      return true;
    }
    return false;
  }

  clearSyncListeners(): void {
    this.syncListeners = [];
    hilog.info(0x0000, TAG, 'clearSyncListeners');
  }

  private notifySync(): void {
    for (const listener of this.syncListeners) {
      try {
        listener();
      } catch (e) {
        hilog.error(0x0000, TAG, 'syncListener error: %{public}s', (e as Error).message);
      }
    }
  }
}
