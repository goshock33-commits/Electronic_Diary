// <!-- agentID: DEV-001 -->
// fix: DEV-011 —— T-P01 设置项持久化端到端修复：initialize() 调用时机由 onCreate(P0) 改为
//   EntryAbility.onWindowStageCreate 的 loadContent 回调（唯一属主）。官方约束：PersistentStorage
//   和 UI 实例相关联，早于 loadContent 回调调用 persistProp 会导致持久化静默失败——此前全部
//   persistProp 键（字号/高对比/摇一摇/灵敏度/悬浮窗/安全锁开关等）杀进程即回默认的根因。
// File: PersistentState.ets
// Task: T005 Global state management - PersistentStorage keys
// Architecture: ARC-001 5.4 / 5.5
// Skill Ref: frontend-design / ui-ux-pro-max
// fix: MAIN-001 · 补回被误覆盖的 T102 增量（AI API-Key 加密存取 + 番茄自定义分钟键），原文取自编译缓存

import { EncryptionUtils, EncryptionResult } from '../utils/EncryptionUtils';

/**
 * PersistentState - Defines all PersistentStorage keys
 * Values persist across app restarts (durable local storage)
 * Paired with AppStorage for reactive UI updates
 */
export class PersistentState {
  // ==================== Persistent State Keys ====================

  /** Current theme preset ID (1-5), persists across restarts */
  static readonly KEY_THEME_ID = 'persist_theme_id';

  /** Dark mode preference (0=light/auto, 1=dark) */
  static readonly KEY_DARK_MODE = 'persist_dark_mode';

  /** Font size level (0=standard, 1=large, 2=extra large) */
  static readonly KEY_FONT_SIZE = 'persist_font_size';

  /** Gesture diary global toggle */
  static readonly KEY_GESTURE_DIARY = 'persist_gesture_diary';

  /** Shake detection sensitivity (0=low, 1=medium, 2=high) */
  static readonly KEY_SHAKE_SENSITIVITY = 'persist_shake_sensitivity';

  /** Daily reminder switch */
  static readonly KEY_REMINDER_ENABLED = 'persist_reminder_enabled';

  /** Daily reminder time (HH:mm format) */
  static readonly KEY_REMINDER_TIME = 'persist_reminder_time';

  /** First launch flag (used for onboarding/welcome) */
  static readonly KEY_FIRST_LAUNCH = 'persist_first_launch';

  /** Last check-in date "YYYY-MM-DD" (for resume) */
  static readonly KEY_LAST_CHECKIN_DATE = 'persist_last_checkin_date';

  /** Pomodoro resume state (JSON string of active session) */
  static readonly KEY_POMODORO_RESUME = 'persist_pomodoro_resume';

  /** Custom theme config (JSON string of CustomThemeConfig) */
  static readonly KEY_CUSTOM_THEME = 'persist_custom_theme';

  /** Security PIN hash (AES encrypted) */
  static readonly KEY_SECURITY_PIN = 'persist_security_pin';

  /** Reminder ringtone URI */
  static readonly KEY_REMINDER_RINGTONE = 'persist_reminder_ringtone';

  /** Notification mode (0=notification only, 1=ring only, 2=both) */
  static readonly KEY_REMINDER_MODE = 'persist_reminder_mode';

  /** Pomodoro custom minutes (user-picked custom duration, T102 batch) */
  static readonly KEY_POMODORO_CUSTOM_MINUTES = 'persist_pomodoro_custom_minutes';

  /** AI API key (AES-256-CBC encrypted, "cipher:iv" format) — T102 */
  static readonly KEY_AI_API_KEY = 'persist_ai_api_key';

  /** AI writing suggestion (ghost text) toggle: 1=on(default) / 0=off — HUI-001 日记编辑页内联补全 */
  static readonly KEY_AI_WRITING_SUGGESTION = 'persist_ai_writing_suggestion';

  /** Elder mode (长辈模式) toggle: 1=on / 0=off(default) — DEV：开启后 MainPage onPageShow 整页替换为 ElderModePage */
  static readonly KEY_ELDER_MODE = 'persist_elder_mode';

  /** Master password for API key encryption (对标 SettingsViewModel APP_SECRET 先例) — T102 */
  private static readonly APP_SECRET = 'HuaweiDiary2024!@#$';

  // ==================== Default Values ====================

  /**
   * Get default values for all persistent state keys
   */
  static getDefaults(): Record<string, Object> {
    const defaults: Record<string, Object> = {};
    defaults[PersistentState.KEY_THEME_ID] = 1;
    defaults[PersistentState.KEY_DARK_MODE] = -1; // -1 means follow system
    defaults[PersistentState.KEY_FONT_SIZE] = 0;
    defaults[PersistentState.KEY_GESTURE_DIARY] = 1;
    defaults[PersistentState.KEY_SHAKE_SENSITIVITY] = 1;
    defaults[PersistentState.KEY_REMINDER_ENABLED] = 0;
    defaults[PersistentState.KEY_REMINDER_TIME] = '20:00';
    defaults[PersistentState.KEY_FIRST_LAUNCH] = 1;
    defaults[PersistentState.KEY_LAST_CHECKIN_DATE] = '';
    defaults[PersistentState.KEY_POMODORO_RESUME] = '';
    defaults[PersistentState.KEY_CUSTOM_THEME] = '';
    defaults[PersistentState.KEY_SECURITY_PIN] = '';
    defaults[PersistentState.KEY_REMINDER_RINGTONE] = '';
    defaults[PersistentState.KEY_REMINDER_MODE] = 2;
    defaults[PersistentState.KEY_POMODORO_CUSTOM_MINUTES] = 0;
    defaults[PersistentState.KEY_AI_API_KEY] = '';
    defaults[PersistentState.KEY_AI_WRITING_SUGGESTION] = 1; // HUI-001：AI 写作建议默认开
    defaults[PersistentState.KEY_ELDER_MODE] = 0; // DEV：长辈模式默认关
    return defaults;
  }

  /**
   * Initialize all PersistentStorage keys.
   * Links PersistentStorage with AppStorage for reactive updates.
   *
   * 🔴 fix: DEV-011 调用时机铁律（T-P01 根因）：
   *   必须且只能在 EntryAbility.onWindowStageCreate 的 windowStage.loadContent 回调内调用。
   *   官方约束：PersistentStorage 和 UI 实例相关联，持久化操作需在 UI 实例初始化成功后
   *   （即 loadContent 传入的回调被调用时）才可以被调用，早于该时机（onCreate / AbilityStage /
   *   loadContent 之前）调用会导致持久化失败。原先本方法经 StartupTasks.initBaseContext 跑在
   *   onCreate（P0），所有 persistProp 静默失效 → 除落 DB 的提醒设置外全部设置杀进程回默认。
   * 🔴 单一属主：本方法是全部 persist 键的唯一 persistProp 调用点（ThemeManager.restorePersisted
   *   负责它自己的 persist_theme_* 键），任何启动路径不得在此之前 setOrCreate 这些键，
   *   否则触发"内存值胜出覆盖磁盘值"铁律。
   */
  static initialize(context: Context): void {
    PersistentStorage.persistProp(PersistentState.KEY_THEME_ID, 1);
    PersistentStorage.persistProp(PersistentState.KEY_DARK_MODE, -1);
    PersistentStorage.persistProp(PersistentState.KEY_FONT_SIZE, 0);
    PersistentStorage.persistProp(PersistentState.KEY_GESTURE_DIARY, 1);
    PersistentStorage.persistProp(PersistentState.KEY_SHAKE_SENSITIVITY, 1);
    PersistentStorage.persistProp(PersistentState.KEY_REMINDER_ENABLED, 0);
    PersistentStorage.persistProp(PersistentState.KEY_REMINDER_TIME, '20:00');
    PersistentStorage.persistProp(PersistentState.KEY_FIRST_LAUNCH, 1);
    PersistentStorage.persistProp(PersistentState.KEY_LAST_CHECKIN_DATE, '');
    PersistentStorage.persistProp(PersistentState.KEY_POMODORO_RESUME, '');
    PersistentStorage.persistProp(PersistentState.KEY_CUSTOM_THEME, '');
    PersistentStorage.persistProp(PersistentState.KEY_SECURITY_PIN, '');
    PersistentStorage.persistProp(PersistentState.KEY_REMINDER_RINGTONE, '');
    PersistentStorage.persistProp(PersistentState.KEY_REMINDER_MODE, 2);
    PersistentStorage.persistProp(PersistentState.KEY_POMODORO_CUSTOM_MINUTES, 0);
    PersistentStorage.persistProp(PersistentState.KEY_AI_API_KEY, '');
    PersistentStorage.persistProp(PersistentState.KEY_AI_WRITING_SUGGESTION, 1); // HUI-001：AI 写作建议默认开
    PersistentStorage.persistProp(PersistentState.KEY_ELDER_MODE, 0); // DEV：长辈模式默认关

    // —— 接盘设置页真实 UI 键（修复重启丢设置）——
    // 设置页 @StorageProp/@StorageLink 直接读写这些键；此前 persistProp 声明的 persist_* 键无人读写，
    // 导致 UI 写入从未落盘、冷启动回退默认值。以下键在 loadContent 回调（UI 实例就绪，fix: DEV-011）接盘，
    // disk 值在重启时优先覆盖 AppState 默认。
    PersistentStorage.persistProp('app_gesture_diary_enabled', 1);          // number 0/1
    PersistentStorage.persistProp('app_floating_entry', true);              // boolean
    PersistentStorage.persistProp('app_security_lock', false);             // boolean
    PersistentStorage.persistProp('app_reminder_method', 'both');          // string
    PersistentStorage.persistProp('app_shake_sensitivity_value', 'medium'); // string
    PersistentStorage.persistProp('app_font_scale', 1);                    // number
    PersistentStorage.persistProp('app_high_contrast', false);             // boolean
    PersistentStorage.persistProp('app_reminder_enabled', false);            // boolean（M17-FIX-PERSIST: 补漏——entry SettingsPage 回调写到该键但此前未 persistProp，致每日提醒开关重启恒默认为关）
    // fix: MAIN-001·M17 —— 提醒时间两键补漏（同 app_reminder_enabled 病根：UI 写这两键但没 persistProp，重启回默认 20:00）
    PersistentStorage.persistProp('app_reminder_hour', 20);                  // number
    PersistentStorage.persistProp('app_reminder_minute', 0);                 // number

    // fix: DEV-011 · T-P01 —— 数值镜像键回灌：AppState.initialize 每次冷启动把
    //   app_shake_sensitivity / app_font_size_level 重置为默认（它们不持久化，属 AppState 属主），
    //   此处依据刚恢复的持久值（字符串档位/缩放系数）重算镜像，保证运行时消费方读到的档位与 UI 回显一致。
    const shakeVal = AppStorage.get<string>('app_shake_sensitivity_value');
    if (shakeVal === 'low') {
      AppStorage.setOrCreate('app_shake_sensitivity', 0);
    } else if (shakeVal === 'high') {
      AppStorage.setOrCreate('app_shake_sensitivity', 2);
    } else if (shakeVal === 'medium') {
      AppStorage.setOrCreate('app_shake_sensitivity', 1);
    }
    const fontScale = AppStorage.get<number>('app_font_scale');
    if (fontScale !== undefined) {
      let fontLevel: number = 0;
      if (fontScale >= 1.5) {
        fontLevel = 2;
      } else if (fontScale >= 1.25) {
        fontLevel = 1;
      }
      AppStorage.setOrCreate('app_font_size_level', fontLevel);
    }
  }

  // ==================== AI API Key (AES encrypted) — T102 ====================

  /**
   * Save AI API key with AES-256-CBC encryption.
   * 落盘格式 "cipher:iv"（对标 EncryptionUtils.encryptPin 先例）。
   * 传空串视为清除 Key。
   * @param text Plaintext API key.
   * @returns true on success, false if encryption failed (key NOT persisted).
   */
  static async saveApiKey(text: string): Promise<boolean> {
    if (text.length === 0) {
      AppStorage.setOrCreate<string>(PersistentState.KEY_AI_API_KEY, '');
      return true;
    }
    // 已核实签名：EncryptionUtils.encrypt(plaintext, password): Promise<EncryptionResult | null>
    const result: EncryptionResult | null = await EncryptionUtils.encrypt(text, PersistentState.APP_SECRET);
    if (result === null) {
      return false;
    }
    AppStorage.setOrCreate<string>(PersistentState.KEY_AI_API_KEY, result.ciphertext + ':' + result.iv);
    return true;
  }

  /**
   * Read and decrypt the stored AI API key.
   * @returns Plaintext key, or '' when unset / format invalid / decryption failed.
   */
  static async getApiKey(): Promise<string> {
    const stored: string = AppStorage.get<string>(PersistentState.KEY_AI_API_KEY) ?? '';
    if (stored.length === 0) {
      return '';
    }
    const parts: string[] = stored.split(':');
    if (parts.length !== 2) {
      return '';
    }
    // 已核实签名：EncryptionUtils.decrypt(hexCiphertext, hexIv, password): Promise<string | null>
    const plain: string | null = await EncryptionUtils.decrypt(parts[0], parts[1], PersistentState.APP_SECRET);
    return plain ?? '';
  }

  /**
   * Whether an AI API key has been configured (non-empty ciphertext persisted).
   */
  static isApiKeyConfigured(): boolean {
    const stored: string = AppStorage.get<string>(PersistentState.KEY_AI_API_KEY) ?? '';
    return stored.length > 0;
  }
}
