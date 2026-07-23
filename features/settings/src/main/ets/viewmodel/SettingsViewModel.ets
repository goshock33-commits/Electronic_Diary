// <!-- agentID: DEV-016 -->
// fix: DEV-013 · T-B01 备份含照片：importBackup 增 context 参数（引擎导入后需在本机沙箱重建照片，签名同步升级）
// <!-- agentID: DEV-004 (M15 安全锁后端) -->
// <!-- agentID: DEV-004 (M14 碰传备份后端) -->
// <!-- agentID: DEV-004 (M15-HASH PIN 单向哈希 + 旧PIN迁移) -->
// 文件: SettingsViewModel.ets
// 任务: T028b 设置业务逻辑（基础）- 每日提醒开关/时间/方式 + 字体大小 + 手势灵敏度 + 安全锁PIN(4位) + 错误次数限制
// 关联架构: ARC-001 4.1 AppSettingsDao / 4.5 EventBus / 5.4 Preferences / 非功能需求安全
// Skill 参考: frontend-design / ui-ux-pro-max
// SDK: HarmonyOS 6.1.1 (API 24)

import { AppSettingsDao, EncryptionUtils, EventBus, ReminderAgentService, AccountManager, AccountDao, CloudDbService, CloudAccount } from '@ohos/shared';
// DEV-WIRE-PROFILE: 资料卡三项统计真实来源 DAO（日记数 / 连续天数 / 番茄数）
import { CheckInDao, DiaryDao, PomodoroDao } from '@ohos/shared';
// M14(DEV-004): 碰传备份 —— 全库导出/导入委托 KnockShareService（载荷引擎），VM 只负责事件 + AppStorage 元信息。
import { KnockShareService } from '@ohos/shared';
import type { BackupExportResult, BackupImportResult, BackupFileInfo } from '@ohos/shared';
// fix(DEV-004): PinHashUtils 在 @ohos/shared 中不存在（未实现/未导出），M15-HASH 引用为悬空符号导致编译错。
// 本次只修编译错不新写功能：PIN 存取回退既有 EncryptionUtils.encryptPin/verifyPin（AES `ct:iv` 格式）。
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'SettingsViewModel';

// ==================== Setting Keys ====================
const KEY_REMINDER_ENABLED = 'reminder_enabled';
const KEY_REMINDER_TIME = 'reminder_time';
const KEY_REMINDER_METHOD = 'reminder_method';
const KEY_REMINDER_RINGTONE_URI = 'reminder_ringtone_uri';
const KEY_FONT_SIZE = 'font_size';
const KEY_GESTURE_SENSITIVITY = 'gesture_sensitivity';
const KEY_GESTURE_DIARY_ENABLED = 'gesture_diary_enabled';
const KEY_SECURITY_PIN_ENCRYPTED = 'security_pin_encrypted';
const KEY_SECURITY_PIN_ERRORS = 'security_pin_errors';
const KEY_SECURITY_LOCKOUT_START = 'security_lockout_start';
// M15: 累计锁定次数(跨重启持久化),驱动锁定时长递增。成功验证/设/删 PIN 时清零。
const KEY_SECURITY_LOCKOUT_COUNT = 'security_lockout_count';
// DEV-WIRE-PROFILE: 昵称持久化键(app_settings 表; 与会话级 AppStorage 'app_user_nickname' 同名保持一致)
const KEY_USER_NICKNAME = 'app_user_nickname';

/** DEV-WIRE-PROFILE: 默认昵称(DB 未写入时的回退值) */
const DEFAULT_NICKNAME = '时光旅人';

// ==================== Constants ====================
const APP_SECRET = 'HuaweiDiary2024!@#$'; // Master password for PIN encryption
const MAX_PIN_ATTEMPTS = 5;
// M15: 锁定时长「阶梯递增」(按累计锁定次数取值)。恒定 30 分改为随重复触发变长,
// 抑制暴力枚举:首犯温和(30s),惯犯陡增至封顶 60 分。索引 = min(lockoutCount-1, len-1)。
const LOCKOUT_STAIRS_MS: number[] = [
  30 * 1000,        // 第 1 次锁定: 30 秒
  60 * 1000,        // 第 2 次: 1 分钟
  5 * 60 * 1000,    // 第 3 次: 5 分钟
  30 * 60 * 1000,   // 第 4 次: 30 分钟
  60 * 60 * 1000    // 第 5 次及以后: 60 分钟(封顶)
];

/** Font size options */
export enum FontSize {
  SMALL = 'small',
  MEDIUM = 'medium',
  LARGE = 'large'
}

/** Gesture sensitivity options */
export enum GestureSensitivity {
  LOW = 'low',
  MEDIUM = 'medium',
  HIGH = 'high'
}

/** Reminder method options */
export enum ReminderMethod {
  NOTIFICATION = 'notification',
  RING = 'ring',
  BOTH = 'both'
}

/** Reminder settings data structure */
export interface ReminderSettings {
  enabled: boolean;
  time: string;
  method: ReminderMethod;
  ringtoneUri: string;
}

/** DEV-WIRE-PROFILE: "我的"页资料卡三项统计(真实 DAO 聚合) */
export interface ProfileStats {
  diaryCount: number;
  streakDays: number;
  pomodoroCount: number;
}

/**
 * SettingsViewModel - Manages all application settings (basic).
 * Persistence: AppSettingsDao (key-value in relational database).
 * Events: emits via emitter for cross-module UI refresh.
 */
export class SettingsViewModel {
  // ==================== Daily Reminder ====================

  /**
   * Get the full reminder settings object.
   */
  async getReminderSettings(): Promise<ReminderSettings> {
    try {
      const enabled = await AppSettingsDao.get(KEY_REMINDER_ENABLED);
      const time = await AppSettingsDao.get(KEY_REMINDER_TIME);
      const method = await AppSettingsDao.get(KEY_REMINDER_METHOD);
      const ringtoneUri = await AppSettingsDao.get(KEY_REMINDER_RINGTONE_URI);
      return {
        enabled: enabled === 'true',
        time: time ?? '20:00',
        // M17-RINGTONE(DEV-007): 空库缺省由 NOTIFICATION 改为 BOTH —— 与 ReminderAgentService.scheduleDaily
        // 的服务端缺省 'both' 及 ReminderSettingsPage 初始态 'both' 三处对齐,消除「设置页显示无声、实际响铃」
        // 的显示/行为漂移;用户预期开启提醒默认有声(HJDG-003 方案 b)。
        method: (method as ReminderMethod) ?? ReminderMethod.BOTH,
        ringtoneUri: ringtoneUri ?? ''
      };
    } catch (err) {
      hilog.error(0x0000, TAG, 'getReminderSettings failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel getReminderSettings failed: ${(err as Error).message}`);
    }
  }

  /**
   * Set daily reminder enabled/disabled.
   */
  async setReminderEnabled(enabled: boolean): Promise<void> {
    try {
      await AppSettingsDao.set(KEY_REMINDER_ENABLED, String(enabled));
      this.emitReminderChanged();
      await this.rescheduleSystemReminder();
    } catch (err) {
      hilog.error(0x0000, TAG, 'setReminderEnabled failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel setReminderEnabled failed: ${(err as Error).message}`);
    }
  }

  /**
   * Set daily reminder time (HH:mm format).
   */
  async setReminderTime(time: string): Promise<void> {
    try {
      // Validate time format
      const timePattern = /^([01]\d|2[0-3]):([0-5]\d)$/;
      if (!timePattern.test(time)) {
        hilog.warn(0x0000, TAG, 'Invalid time format: %{public}s, expected HH:mm', time);
        return;
      }
      await AppSettingsDao.set(KEY_REMINDER_TIME, time);
      this.emitReminderChanged();
      await this.rescheduleSystemReminder();
    } catch (err) {
      hilog.error(0x0000, TAG, 'setReminderTime failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel setReminderTime failed: ${(err as Error).message}`);
    }
  }

  /**
   * Set reminder method (notification / ring / both).
   * M17-RINGTONE(DEV-007): 落库后立即重调度 —— scheduleDaily 内部会从 app_settings 读回 method/ringtone
   * 映射 slotType/ringDuration/customRingUri,让「提醒方式」选择即时作用于已发布的系统提醒。
   */
  async setReminderMethod(method: ReminderMethod): Promise<void> {
    try {
      await AppSettingsDao.set(KEY_REMINDER_METHOD, method);
      this.emitReminderChanged();
      await this.rescheduleSystemReminder();
    } catch (err) {
      hilog.error(0x0000, TAG, 'setReminderMethod failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel setReminderMethod failed: ${(err as Error).message}`);
    }
  }

  /**
   * Set custom ringtone URI for reminder.
   * M17-RINGTONE(DEV-007): 同上,选铃声后立即重发布提醒(customRingUri 换为所选音源),
   * 试听(RingtonePlayUtils.play)与真实提醒消费同一张 id→rawfile 映射表。
   */
  async setReminderRingtone(uri: string): Promise<void> {
    try {
      await AppSettingsDao.set(KEY_REMINDER_RINGTONE_URI, uri);
      this.emitReminderChanged();
      await this.rescheduleSystemReminder();
    } catch (err) {
      hilog.error(0x0000, TAG, 'setReminderRingtone failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel setReminderRingtone failed: ${(err as Error).message}`);
    }
  }

  /**
   * Convenience: save all reminder settings at once.
   */
  async saveReminderSettings(settings: ReminderSettings): Promise<void> {
    try {
      const entries = new Map<string, string>();
      entries.set(KEY_REMINDER_ENABLED, String(settings.enabled));
      entries.set(KEY_REMINDER_TIME, settings.time);
      entries.set(KEY_REMINDER_METHOD, settings.method);
      entries.set(KEY_REMINDER_RINGTONE_URI, settings.ringtoneUri);
      await AppSettingsDao.batchSet(entries);
      this.emitReminderChanged();
      await this.rescheduleSystemReminder();
    } catch (err) {
      hilog.error(0x0000, TAG, 'saveReminderSettings failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel saveReminderSettings failed: ${(err as Error).message}`);
    }
  }

  /**
   * M17: 落库成功后把当前提醒开关/时间重新调度到系统(后台代理提醒)。
   * 真相源 = app_settings(本 VM 刚写入的 reminder_enabled / reminder_time);
   * 解析 "HH:mm" → hour/minute,交由 ReminderAgentService 统一发布每日闹钟型提醒。
   * 非致命:调度失败仅记日志,不影响设置持久化本身。
   */
  private async rescheduleSystemReminder(): Promise<void> {
    try {
      const settings = await this.getReminderSettings();
      const parts: string[] = settings.time.split(':');
      const hour: number = parts.length > 0 ? parseInt(parts[0], 10) : 20;
      const minute: number = parts.length > 1 ? parseInt(parts[1], 10) : 0;
      const safeHour: number = isNaN(hour) ? 20 : hour;
      const safeMinute: number = isNaN(minute) ? 0 : minute;
      await ReminderAgentService.scheduleDaily(safeHour, safeMinute, settings.enabled);
    } catch (err) {
      hilog.error(0x0000, TAG, 'rescheduleSystemReminder failed: %{public}s', (err as Error).message);
    }
  }

  // ==================== User Nickname (DEV-WIRE-PROFILE) ====================

  /**
   * DEV-WIRE-PROFILE: 读取持久化昵称(app_settings 表)。DB 未写入时回退默认名。
   * 跨重启持久化: 值落 app_settings.value, 重启后仍可读回。
   */
  async getNickname(): Promise<string> {
    try {
      const nk = await AppSettingsDao.get(KEY_USER_NICKNAME);
      return (nk !== null && nk.length > 0) ? nk : DEFAULT_NICKNAME;
    } catch (err) {
      hilog.error(0x0000, TAG, 'getNickname failed: %{public}s', (err as Error).message);
      return DEFAULT_NICKNAME;
    }
  }

  /**
   * DEV-WIRE-PROFILE: 保存昵称并落库(app_settings)。同步会话级 AppStorage 以即时回显。
   */
  async saveNickname(name: string): Promise<void> {
    try {
      const trimmed = name.trim();
      if (trimmed.length === 0) {
        return;
      }
      // 本地持久化
      await AppSettingsDao.set(KEY_USER_NICKNAME, trimmed);
      AppStorage.setOrCreate('app_user_nickname', trimmed);
      // 同步本地 account 表 + Cloud DB Account 表 + AppStorage
      const acctMgr = AccountManager.getInstance();
      if (acctMgr.isLoggedIn()) {
        await AccountDao.updateNickname(acctMgr.getUid(), trimmed);
        AppStorage.setOrCreate('account_nickname', trimmed);
        // 推 Cloud DB（后台，失败不阻塞）
        const svc = CloudDbService.getInstance();
        if (svc.isZoneOpened()) {
          const cloudAccount = new CloudAccount();
          cloudAccount.uid = acctMgr.getUid();
          cloudAccount.nickname = trimmed;
          cloudAccount.phone = acctMgr.getPhone();
          svc.upsertAccount(cloudAccount).catch((err: Error) => {
            hilog.error(0x0000, TAG, 'Cloud sync nickname failed: %{public}s', err.message);
          });
        }
      }
      this.emitSettingsChanged();
    } catch (err) {
      hilog.error(0x0000, TAG, 'saveNickname failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel saveNickname failed: ${(err as Error).message}`);
    }
  }

  // ==================== Profile Stats (DEV-WIRE-PROFILE) ====================

  /**
   * DEV-WIRE-PROFILE: 资料卡三项统计真实聚合。
   *   diaryCount    → DiaryDao.count()           (SELECT COUNT(*) FROM diary)
   *   streakDays    → CheckInDao.queryStreak(今日) (连续打卡天数)
   *   pomodoroCount → PomodoroDao.countCompleted(全时段) (SELECT COUNT(*) WHERE completed=1)
   * 任一失败整体回退全 0(真实空态, 不写假值)。
   */
  async getProfileStats(): Promise<ProfileStats> {
    try {
      const diaryCount = await DiaryDao.count();
      const streakDays = await CheckInDao.queryStreak(this.getTodayDate());
      // fix(DEV-004): PomodoroDao 无 countAllCompleted；按既有先例（SettingsPage/PomodoroPage）
      // 用 countCompleted(start, end) 传全时段边界统计全部完成数。
      const pomodoroCount = await PomodoroDao.countCompleted('1970-01-01', '9999-12-31');
      const stats: ProfileStats = {
        diaryCount: diaryCount,
        streakDays: streakDays,
        pomodoroCount: pomodoroCount
      };
      return stats;
    } catch (err) {
      hilog.error(0x0000, TAG, 'getProfileStats failed: %{public}s', (err as Error).message);
      const empty: ProfileStats = { diaryCount: 0, streakDays: 0, pomodoroCount: 0 };
      return empty;
    }
  }

  /** DEV-WIRE-PROFILE: 今日日期 "YYYY-MM-DD"(本地) */
  private getTodayDate(): string {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  // ==================== Font Size ====================
  /**
   * Get current font size setting.
   */
  async getFontSize(): Promise<FontSize> {
    try {
      const value = await AppSettingsDao.get(KEY_FONT_SIZE);
      if (value && Object.values(FontSize).includes(value as FontSize)) {
        return value as FontSize;
      }
      return FontSize.MEDIUM; // default
    } catch (err) {
      hilog.error(0x0000, TAG, 'getFontSize failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel getFontSize failed: ${(err as Error).message}`);
    }
  }

  /**
   * Set font size (small / medium / large).
   * Emits event:fontSize:changed for global UI refresh.
   */
  async setFontSize(size: FontSize): Promise<void> {
    try {
      await AppSettingsDao.set(KEY_FONT_SIZE, size);
      // Sync to AppStorage for global UI refresh (key per B01: unprefixed contract names)
      AppStorage.setOrCreate('currentFontSize', size);
      // Emit font size change event for global UI refresh
      const fontSizePayload: Record<string, Object> = {};
      fontSizePayload['fontSize'] = size;
      EventBus.emit(EventBus.EventNames.FONT_SIZE_CHANGED, fontSizePayload);
      this.emitSettingsChanged();
    } catch (err) {
      hilog.error(0x0000, TAG, 'setFontSize failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel setFontSize failed: ${(err as Error).message}`);
    }
  }

  // ==================== Gesture Sensitivity ====================

  /**
   * Get current gesture sensitivity setting.
   */
  async getGestureSensitivity(): Promise<GestureSensitivity> {
    try {
      const value = await AppSettingsDao.get(KEY_GESTURE_SENSITIVITY);
      if (value && Object.values(GestureSensitivity).includes(value as GestureSensitivity)) {
        return value as GestureSensitivity;
      }
      return GestureSensitivity.MEDIUM; // default
    } catch (err) {
      hilog.error(0x0000, TAG, 'getGestureSensitivity failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel getGestureSensitivity failed: ${(err as Error).message}`);
    }
  }

  /**
   * Set gesture sensitivity (low / medium / high).
   */
  async setGestureSensitivity(sensitivity: GestureSensitivity): Promise<void> {
    try {
      await AppSettingsDao.set(KEY_GESTURE_SENSITIVITY, sensitivity);
      this.emitSettingsChanged();
    } catch (err) {
      hilog.error(0x0000, TAG, 'setGestureSensitivity failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel setGestureSensitivity failed: ${(err as Error).message}`);
    }
  }

  // ==================== Gesture Diary ====================

  /**
   * Check if gesture diary (shake/right-pull/long-press) is enabled.
   */
  async isGestureDiaryEnabled(): Promise<boolean> {
    try {
      const value = await AppSettingsDao.get(KEY_GESTURE_DIARY_ENABLED);
      return value === 'true';
    } catch (err) {
      hilog.error(0x0000, TAG, 'isGestureDiaryEnabled failed: %{public}s', (err as Error).message);
      return true; // Default: enabled
    }
  }

  /**
   * Enable or disable gesture diary triggers.
   * Writes to AppStorage for M12 GestureDiaryViewModel to react.
   */
  async setGestureDiaryEnabled(enabled: boolean): Promise<void> {
    try {
      await AppSettingsDao.set(KEY_GESTURE_DIARY_ENABLED, String(enabled));
      AppStorage.setOrCreate('gestureDiaryEnabled', enabled);
      this.emitSettingsChanged();
    } catch (err) {
      hilog.error(0x0000, TAG, 'setGestureDiaryEnabled failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel setGestureDiaryEnabled failed: ${(err as Error).message}`);
    }
  }

  /**
   * fix: HUI-FRONTEND · F14③ 悬浮窗开关落 DB（备份/恢复含此设置项）+ 同步 AppStorage。
   */
  async setFloatingEntryEnabled(enabled: boolean): Promise<void> {
    try {
      await AppSettingsDao.set('floating_entry_enabled', String(enabled));
      AppStorage.setOrCreate('app_floating_entry', enabled);
      this.emitSettingsChanged();
    } catch (err) {
      hilog.error(0x0000, TAG, 'setFloatingEntryEnabled failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel setFloatingEntryEnabled failed: ${(err as Error).message}`);
    }
  }

  // ==================== Security Lock PIN ====================

  /**
   * Check if a security PIN has been set.
   */
  async hasPinSet(): Promise<boolean> {
    try {
      const encrypted = await AppSettingsDao.get(KEY_SECURITY_PIN_ENCRYPTED);
      return encrypted !== null && encrypted.length > 0;
    } catch (err) {
      hilog.error(0x0000, TAG, 'hasPinSet failed: %{public}s', (err as Error).message);
      return false;
    }
  }

  /**
   * Check if the security lock is currently active (in lockout period).
   * M15: 锁定时长按累计次数递增(见 getCurrentLockoutDurationMs)。到期清 START/ERRORS,
   *      但保留 lockoutCount(累计不清零),使下次锁定更久;仅成功验证/设/删 PIN 才清零 count。
   * @returns Remaining lockout seconds, or 0 if not locked.
   */
  async getLockoutRemaining(): Promise<number> {
    try {
      const lockoutStartStr = await AppSettingsDao.get(KEY_SECURITY_LOCKOUT_START);
      if (!lockoutStartStr) {
        return 0;
      }
      const lockoutStart = parseInt(lockoutStartStr);
      const durationMs = await this.getCurrentLockoutDurationMs();
      const now = Date.now();
      const elapsed = now - lockoutStart;
      const remaining = durationMs - elapsed;
      if (remaining <= 0) {
        // Lockout expired: clear the active window and reset error counter for a fresh set of attempts.
        // NOTE: keep KEY_SECURITY_LOCKOUT_COUNT so a subsequent lockout escalates (递增不因到期而复位)。
        await AppSettingsDao.delete(KEY_SECURITY_LOCKOUT_START);
        await AppSettingsDao.set(KEY_SECURITY_PIN_ERRORS, '0');
        return 0;
      }
      return Math.ceil(remaining / 1000); // Return remaining seconds
    } catch (err) {
      hilog.error(0x0000, TAG, 'getLockoutRemaining failed: %{public}s', (err as Error).message);
      return 0;
    }
  }

  /**
   * M15: 当前一次锁定应持续的毫秒数,由累计锁定次数 lockoutCount 在阶梯表中取值。
   * count 缺省/异常按第 1 次处理(最短 30s);超出阶梯长度封顶末档(60min)。
   */
  private async getCurrentLockoutDurationMs(): Promise<number> {
    try {
      const countStr = await AppSettingsDao.get(KEY_SECURITY_LOCKOUT_COUNT);
      const count = countStr ? parseInt(countStr) : 1;
      const safeCount = count > 0 ? count : 1;
      const idx = Math.min(safeCount - 1, LOCKOUT_STAIRS_MS.length - 1);
      return LOCKOUT_STAIRS_MS[idx];
    } catch (err) {
      hilog.error(0x0000, TAG, 'getCurrentLockoutDurationMs failed: %{public}s', (err as Error).message);
      return LOCKOUT_STAIRS_MS[0];
    }
  }

  /**
   * Set a new security PIN (4 digits).
   * Stores the PIN encrypted via AES.
   *
   * @param pin 4-digit PIN string
   * @returns true if PIN was set successfully
   */
  async setPin(pin: string): Promise<boolean> {
    try {
      // Validate 4-digit PIN
      const pinPattern = /^\d{4}$/;
      if (!pinPattern.test(pin)) {
        hilog.warn(0x0000, TAG, 'Invalid PIN format: must be exactly 4 digits');
        return false;
      }

      // fix(DEV-004): PinHashUtils 未实现，回退既有 EncryptionUtils.encryptPin（AES `ct:iv`），与 verifyPin 对称。
      const hashed = await EncryptionUtils.encryptPin(pin, APP_SECRET);
      if (!hashed) {
        hilog.error(0x0000, TAG, 'Failed to encrypt PIN');
        return false;
      }

      await AppSettingsDao.set(KEY_SECURITY_PIN_ENCRYPTED, hashed);
      // Reset error count and lockout on successful set
      await AppSettingsDao.set(KEY_SECURITY_PIN_ERRORS, '0');
      await AppSettingsDao.delete(KEY_SECURITY_LOCKOUT_START);
      // M15: 重设 PIN 视作全新起点,清零累计锁定次数(下次锁定回到最短档)。
      await AppSettingsDao.delete(KEY_SECURITY_LOCKOUT_COUNT);
      this.emitSecurityLockChanged();
      hilog.info(0x0000, TAG, 'Security PIN set successfully');
      return true;
    } catch (err) {
      hilog.error(0x0000, TAG, 'setPin failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel setPin failed: ${(err as Error).message}`);
    }
  }

  /**
   * Verify the input PIN against the stored encrypted PIN.
   * Implements lockout: 5 consecutive wrong attempts -> 30 min lockout.
   *
   * @param inputPin 4-digit PIN to verify
   * @returns true if PIN matches, false if wrong or locked out
   */
  async verifyPin(inputPin: string): Promise<boolean> {
    try {
      // Check lockout status first
      const remaining = await this.getLockoutRemaining();
      if (remaining > 0) {
        hilog.warn(0x0000, TAG, 'Security lockout active: %{public}d seconds remaining', remaining);
        return false;
      }

      const storedEncrypted = await AppSettingsDao.get(KEY_SECURITY_PIN_ENCRYPTED);
      if (!storedEncrypted) {
        // No PIN set, allow access
        return true;
      }

      // fix(DEV-004): PinHashUtils 未实现，哈希分流/透明迁移不可用；统一走既有 EncryptionUtils.verifyPin（AES `ct:iv`）。
      const isValid: boolean = await EncryptionUtils.verifyPin(inputPin, storedEncrypted, APP_SECRET);

      if (isValid) {
        // Reset error count on success
        await AppSettingsDao.set(KEY_SECURITY_PIN_ERRORS, '0');
        await AppSettingsDao.delete(KEY_SECURITY_LOCKOUT_START);
        // M15: 验证成功 = 合法用户,清零累计锁定次数(递增链条重置)。
        await AppSettingsDao.delete(KEY_SECURITY_LOCKOUT_COUNT);
        return true;
      }

      // Increment error count
      const errorCountStr = await AppSettingsDao.get(KEY_SECURITY_PIN_ERRORS);
      const errorCount = (errorCountStr ? parseInt(errorCountStr) : 0) + 1;
      await AppSettingsDao.set(KEY_SECURITY_PIN_ERRORS, String(errorCount));

      // Check if lockout should be triggered
      if (errorCount >= MAX_PIN_ATTEMPTS) {
        // M15: 触发锁定时累计次数 +1,锁定时长按 count 在阶梯表递增(getCurrentLockoutDurationMs)。
        const lockoutCountStr = await AppSettingsDao.get(KEY_SECURITY_LOCKOUT_COUNT);
        const newLockoutCount = (lockoutCountStr ? parseInt(lockoutCountStr) : 0) + 1;
        await AppSettingsDao.set(KEY_SECURITY_LOCKOUT_COUNT, String(newLockoutCount));
        await AppSettingsDao.set(KEY_SECURITY_LOCKOUT_START, String(Date.now()));
        hilog.warn(0x0000, TAG, 'Security lockout triggered: %{public}d consecutive failures, lockoutCount=%{public}d',
          errorCount, newLockoutCount);
      }

      hilog.warn(0x0000, TAG, 'PIN verification failed: attempt %{public}d of %{public}d',
        errorCount, MAX_PIN_ATTEMPTS);
      return false;
    } catch (err) {
      hilog.error(0x0000, TAG, 'verifyPin failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel verifyPin failed: ${(err as Error).message}`);
    }
  }

  /**
   * Get the number of remaining PIN attempts before lockout.
   */
  async getRemainingAttempts(): Promise<number> {
    try {
      const remaining = await this.getLockoutRemaining();
      if (remaining > 0) {
        return 0; // Locked out
      }
      const errorCountStr = await AppSettingsDao.get(KEY_SECURITY_PIN_ERRORS);
      const errorCount = errorCountStr ? parseInt(errorCountStr) : 0;
      return Math.max(0, MAX_PIN_ATTEMPTS - errorCount);
    } catch (err) {
      hilog.error(0x0000, TAG, 'getRemainingAttempts failed: %{public}s', (err as Error).message);
      return MAX_PIN_ATTEMPTS;
    }
  }

  /**
   * Remove the security PIN (disable lock).
   */
  async removePin(): Promise<void> {
    try {
      await AppSettingsDao.delete(KEY_SECURITY_PIN_ENCRYPTED);
      await AppSettingsDao.delete(KEY_SECURITY_PIN_ERRORS);
      await AppSettingsDao.delete(KEY_SECURITY_LOCKOUT_START);
      // M15: 移除 PIN 一并清零累计锁定次数(避免残留影响下次设 PIN 后的递增基线)。
      await AppSettingsDao.delete(KEY_SECURITY_LOCKOUT_COUNT);
      this.emitSecurityLockChanged();
      hilog.info(0x0000, TAG, 'Security PIN removed');
    } catch (err) {
      hilog.error(0x0000, TAG, 'removePin failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel removePin failed: ${(err as Error).message}`);
    }
  }

  // ==================== Bulk Load / Save ====================

  /**
   * Load all settings at once (for settings page initialization).
   */
  async loadAllSettings(): Promise<Record<string, string>> {
    try {
      const all = await AppSettingsDao.getAll();
      const result: Record<string, string> = {};
      all.forEach((value: string, key: string) => {
        result[key] = value;
      });
      return result;
    } catch (err) {
      hilog.error(0x0000, TAG, 'loadAllSettings failed: %{public}s', (err as Error).message);
      throw new Error(`SettingsViewModel loadAllSettings failed: ${(err as Error).message}`);
    }
  }

  // ==================== M14 碰传备份 / 本地备份 ====================

  /**
   * M14: 导出全库为加密备份文件（碰传备份的「发送体」= 本地备份文件）。
   * 委托 KnockShareService.exportFullBackup（通用 SQL dump，12 表）；成功后写 AppStorage 元信息 + emit BACKUP_COMPLETED。
   * @param context UIAbility 上下文（取 filesDir；页面侧 getContext(this) as common.Context 传入）。
   * @returns 备份结果（路径/大小/表数/行数）；失败 null。
   */
  async exportBackup(context: common.Context): Promise<BackupExportResult | null> {
    try {
      this.emitBackupStarted();
      const result = await KnockShareService.exportFullBackup(context.filesDir);
      if (result !== null) {
        // 会话级元信息（键名简单直读，前端 @StorageLink 即时回显「上次备份」卡片，不自造复杂结构）
        AppStorage.setOrCreate('lastBackupPath', result.path);
        AppStorage.setOrCreate('lastBackupSize', result.sizeBytes);
        AppStorage.setOrCreate('lastBackupTime', result.created);
        this.emitBackupCompleted(result.path, result.sizeBytes, result.rowCount);
        hilog.info(0x0000, TAG, 'exportBackup ok: rows=%{public}d bytes=%{public}d', result.rowCount, result.sizeBytes);
      }
      return result;
    } catch (err) {
      hilog.error(0x0000, TAG, 'exportBackup failed: %{public}s', (err as Error).message);
      return null;
    }
  }

  /**
   * M14: 从本地备份文件路径导入并整库恢复（REPLACE 幂等，单事务）。
   * fix: DEV-013 · 新增 context 参数：导入后需在本机沙箱重建照片文件（filesDir/images/），引擎签名同步升级。
   * @param context UIAbility 上下文（取 filesDir；页面侧 getContext(this) as common.Context 传入）。
   * @param filePath 备份文件路径（.ediary.zip；来自 listBackups 或用户选择）。
   */
  async importBackup(context: common.Context, filePath: string): Promise<BackupImportResult | null> {
    try {
      this.emitRestoreStarted();
      const result = await KnockShareService.importFullBackup(context.filesDir, filePath);
      if (result !== null) {
        this.emitRestoreCompleted(result.tableCount, result.rowCount);
        hilog.info(0x0000, TAG, 'importBackup ok: tables=%{public}d rows=%{public}d', result.tableCount, result.rowCount);
      }
      return result;
    } catch (err) {
      hilog.error(0x0000, TAG, 'importBackup failed: %{public}s', (err as Error).message);
      return null;
    }
  }

  /**
   * M14: 收方入口 —— 从（碰一碰/分享授予读权限的）文件 URI 导入备份并落库。
   * EntryAbility 收到透传 shareFileUri 时调用（主进程 DB 就绪后）。
   * @param context 上下文（取 filesDir 落地接收区）。
   * @param uri 已授予读权限的文件 URI。
   */
  async importBackupFromUri(context: common.Context, uri: string): Promise<BackupImportResult | null> {
    try {
      this.emitRestoreStarted();
      const result = await KnockShareService.importBackupFromUri(context.filesDir, uri);
      if (result !== null) {
        this.emitRestoreCompleted(result.tableCount, result.rowCount);
        hilog.info(0x0000, TAG, 'importBackupFromUri ok: rows=%{public}d', result.rowCount);
      }
      return result;
    } catch (err) {
      hilog.error(0x0000, TAG, 'importBackupFromUri failed: %{public}s', (err as Error).message);
      return null;
    }
  }

  /** M14: 列出全部本地备份（供设置页「备份管理」列表 / 碰传前选择）。 */
  listBackups(context: common.Context): BackupFileInfo[] {
    return KnockShareService.listBackups(context.filesDir);
  }

  /** M14: 删除某备份文件。 */
  deleteBackup(filePath: string): boolean {
    return KnockShareService.deleteBackup(filePath);
  }

  // ==================== Event Emitters ====================

  private emitSettingsChanged(): void {
    const payload: Record<string, Object> = {};
    payload['timestamp'] = Date.now();
    EventBus.emit(EventBus.EventNames.SETTINGS_CHANGED, payload);
    hilog.debug(0x0000, TAG, 'Emitted event:settings:changed via EventBus');
  }

  private emitReminderChanged(): void {
    const payload: Record<string, Object> = {};
    payload['timestamp'] = Date.now();
    EventBus.emit(EventBus.EventNames.REMINDER_CHANGED, payload);
    hilog.debug(0x0000, TAG, 'Emitted event:reminder:changed via EventBus');
  }

  private emitSecurityLockChanged(): void {
    const payload: Record<string, Object> = {};
    payload['timestamp'] = Date.now();
    EventBus.emit(EventBus.EventNames.SECURITY_LOCK_CHANGED, payload);
    hilog.debug(0x0000, TAG, 'Emitted event:securityLock:changed via EventBus');
  }

  // M14: 备份/恢复生命周期事件（前端进度/结果提示订阅 BACKUP_*/RESTORE_*；载荷为空 Record + 括号赋值，符合 §十一）。
  private emitBackupStarted(): void {
    const payload: Record<string, Object> = {};
    payload['timestamp'] = Date.now();
    EventBus.emit(EventBus.EventNames.BACKUP_STARTED, payload);
  }

  private emitBackupCompleted(path: string, sizeBytes: number, rowCount: number): void {
    const payload: Record<string, Object> = {};
    payload['path'] = path;
    payload['size'] = sizeBytes;
    payload['rowCount'] = rowCount;
    EventBus.emit(EventBus.EventNames.BACKUP_COMPLETED, payload);
  }

  private emitRestoreStarted(): void {
    const payload: Record<string, Object> = {};
    payload['timestamp'] = Date.now();
    EventBus.emit(EventBus.EventNames.RESTORE_STARTED, payload);
  }

  private emitRestoreCompleted(tableCount: number, rowCount: number): void {
    const payload: Record<string, Object> = {};
    payload['tableCount'] = tableCount;
    payload['rowCount'] = rowCount;
    EventBus.emit(EventBus.EventNames.RESTORE_COMPLETED, payload);
  }
}
