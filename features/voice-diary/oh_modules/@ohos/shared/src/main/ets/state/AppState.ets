// <!-- agentID: DEV-001 -->
// File: AppState.ets
// Task: T005 Global state management - AppStorage state keys
// Architecture: ARC-001 3.5 / 5.4 / 4.6
// Skill Ref: frontend-design / ui-ux-pro-max

import { emitter } from '@kit.BasicServicesKit';

/**
 * AppState - Defines all global state keys stored in AppStorage
 * Used for cross-page, cross-component shared state
 */
export class AppState {
  // ==================== App State Keys ====================

  /** Current selected date "YYYY-MM-DD" */
  static readonly KEY_CURRENT_DATE = 'app_current_date';

  /** Whether user has checked in today */
  static readonly KEY_CHECKED_TODAY = 'app_checked_today';

  /** Current check-in streak (consecutive days) */
  static readonly KEY_STREAK_COUNT = 'app_streak_count';

  /** Current theme preset ID (1-5) */
  static readonly KEY_THEME_PRESET_ID = 'app_theme_preset_id';

  /** Dark mode enabled flag (0=light, 1=dark) */
  static readonly KEY_DARK_MODE = 'app_dark_mode';

  /** Font size level (0=standard, 1=large, 2=extra large) */
  static readonly KEY_FONT_SIZE_LEVEL = 'app_font_size_level';

  /** Gesture diary enabled flag (0=disabled, 1=enabled) */
  static readonly KEY_GESTURE_DIARY_ENABLED = 'app_gesture_diary_enabled';

  /** Shake sensitivity level (0=low, 1=medium, 2=high) */
  static readonly KEY_SHAKE_SENSITIVITY = 'app_shake_sensitivity';

  /** Whether the app is currently in background */
  static readonly KEY_APP_IN_BACKGROUND = 'app_in_background';

  /** Today's diary word count (for quick overview) */
  static readonly KEY_TODAY_DIARY_WORD_COUNT = 'app_today_word_count';

  /** Loading state for main page */
  static readonly KEY_IS_LOADING = 'app_is_loading';

  /** Initialization complete flag */
  static readonly KEY_INIT_COMPLETE = 'app_init_complete';

  /** Active pomodoro session (0=no active session) */
  static readonly KEY_POMODORO_ACTIVE = 'app_pomodoro_active';

  /** Unread message total count (for home tab badge) */
  static readonly KEY_UNREAD_MESSAGE_TOTAL = 'unread_message_total';

  // ==================== Default Values ====================

  /**
   * Get default values for all state keys
   */
  static getDefaults(): Record<string, Object> {
    const defaults: Record<string, Object> = {};
    defaults[AppState.KEY_CURRENT_DATE] = '';
    defaults[AppState.KEY_CHECKED_TODAY] = 0;
    defaults[AppState.KEY_STREAK_COUNT] = 0;
    defaults[AppState.KEY_THEME_PRESET_ID] = 1;
    defaults[AppState.KEY_DARK_MODE] = 0;
    defaults[AppState.KEY_FONT_SIZE_LEVEL] = 0;
    defaults[AppState.KEY_GESTURE_DIARY_ENABLED] = 1;
    defaults[AppState.KEY_SHAKE_SENSITIVITY] = 1;
    defaults[AppState.KEY_APP_IN_BACKGROUND] = 0;
    defaults[AppState.KEY_TODAY_DIARY_WORD_COUNT] = 0;
    defaults[AppState.KEY_IS_LOADING] = 1;
    defaults[AppState.KEY_INIT_COMPLETE] = 0;
    defaults[AppState.KEY_POMODORO_ACTIVE] = 0;
    defaults[AppState.KEY_UNREAD_MESSAGE_TOTAL] = 0;
    return defaults;
  }

  /**
   * Initialize all AppStorage state keys with default values.
   * Call once in AbilityStage.onCreate (P0 startup).
   */
  static initialize(context: Context): void {
    const defaults = AppState.getDefaults();
    AppStorage.setOrCreate(AppState.KEY_CURRENT_DATE, defaults[AppState.KEY_CURRENT_DATE]);
    AppStorage.setOrCreate(AppState.KEY_CHECKED_TODAY, defaults[AppState.KEY_CHECKED_TODAY]);
    AppStorage.setOrCreate(AppState.KEY_STREAK_COUNT, defaults[AppState.KEY_STREAK_COUNT]);
    AppStorage.setOrCreate(AppState.KEY_THEME_PRESET_ID, defaults[AppState.KEY_THEME_PRESET_ID]);
    AppStorage.setOrCreate(AppState.KEY_DARK_MODE, defaults[AppState.KEY_DARK_MODE]);
    AppStorage.setOrCreate(AppState.KEY_FONT_SIZE_LEVEL, defaults[AppState.KEY_FONT_SIZE_LEVEL]);
    // M15-FIX(DEV-005): 不再在此 setOrCreate('app_gesture_diary_enabled') —— 该键归 PersistentState.persistProp 所有。
    // ArkUI persistProp 铁律：若键在调用 persistProp 前已存在于 AppStorage，则「内存值胜出并覆盖磁盘值」。
    // 本方法在 StartupTasks.initBaseContext 里先于 PersistentState.initialize 执行，若在此预置该键，
    // 会导致 persistProp 每次冷启动都丢弃磁盘持久值 → 摇一摇开关重启必被重置。故此处不碰，由 persistProp 独占初始化。
    AppStorage.setOrCreate(AppState.KEY_SHAKE_SENSITIVITY, defaults[AppState.KEY_SHAKE_SENSITIVITY]);
    AppStorage.setOrCreate(AppState.KEY_APP_IN_BACKGROUND, defaults[AppState.KEY_APP_IN_BACKGROUND]);
    AppStorage.setOrCreate(AppState.KEY_TODAY_DIARY_WORD_COUNT, defaults[AppState.KEY_TODAY_DIARY_WORD_COUNT]);
    AppStorage.setOrCreate(AppState.KEY_IS_LOADING, defaults[AppState.KEY_IS_LOADING]);
    AppStorage.setOrCreate(AppState.KEY_INIT_COMPLETE, defaults[AppState.KEY_INIT_COMPLETE]);
    AppStorage.setOrCreate(AppState.KEY_POMODORO_ACTIVE, defaults[AppState.KEY_POMODORO_ACTIVE]);
    AppStorage.setOrCreate(AppState.KEY_UNREAD_MESSAGE_TOTAL, defaults[AppState.KEY_UNREAD_MESSAGE_TOTAL]);
  }
}
