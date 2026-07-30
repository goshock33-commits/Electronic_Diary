// <!-- agentID: DEV-017 -->
// fix: DEV-011 —— T-P01：initBaseContext 不再调用 PersistentState.initialize。persistProp 早于
//   loadContent 回调（UI 实例就绪）调用会静默失败，且失败调用可能先把键 setOrCreate 进 AppStorage，
//   反过来触发"内存值胜出覆盖磁盘值"踩死真正的持久化。唯一属主改为 EntryAbility.onWindowStageCreate
//   的 loadContent 回调（见 PersistentState.initialize 头注释）。
// File: StartupTasks.ets
// Task: T040 AppStartup - Startup task implementations (6 tasks)
// Architecture: ARC-001 3.6 AppStartup
// Skill Ref: frontend-design / ui-ux-pro-max

import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseHelper } from '../database/DatabaseHelper';
// M17-FIX-WARM(DEV-006): 冷启动把 app_settings(DB 真相源)的提醒开关/时间/方式+昵称回灌 AppStorage
import { AppSettingsDao } from '../database/dao/AppSettingsDao';
import { CustomEmojiDao } from '../database/dao/CustomEmojiDao';
// M10: 名言内置种子(120 条)启动灌入,与 custom_emoji 同处 initDatabase 非致命调用。
import { QuoteDao } from '../database/dao/QuoteDao';
// M06(DEV-005): 首启灌默认分区种子 + 暖入 AppStorage('sectionConfigs')
import { SectionConfigDao, type SectionConfig } from '../database/dao/SectionConfigDao';
import { AppState } from '../state/AppState';
import { PersistentState } from '../state/PersistentState';
import { EventBus } from '../utils/EventBus';
import { NotificationUtils } from '../utils/NotificationUtils';
import { StartupConfig, StartupPriority } from './StartupConfig';
import { getThemeManager } from '../theme/ThemeManager';

const TAG = 'StartupTasks';

/**
 * StartupTasks - Implements the 6 startup tasks defined in StartupConfig
 *
 * Execution flow:
 *   1. P0 SYNC (serial on main thread): InitBaseContext -> InitDatabase
 *   2. P1 ASYNC (parallel via TaskPool): RestoreTheme || RegisterNotificationChannels
 *   3. P2 IDLE (deferred via requestIdleCallback): PreloadQuotes || WarmupStatsCache
 */
export class StartupTasks {
  private static completedTasks: Set<string> = new Set();
  private static taskResults: Map<string, Object> = new Map();

  /**
   * P0 Task 1: Initialize base application context
   * - Register global error handler / exception hook
   * - Initialize AppState (AppStorage keys)
   * - Initialize EventBus emitter
   * fix: DEV-011 —— PersistentState.initialize 已移出（persistProp 在 onCreate 阶段静默失效，
   *   见文件头注释）；由 EntryAbility.onWindowStageCreate 的 loadContent 回调独占调用。
   */
  static async initBaseContext(context: Context): Promise<void> {
    console.info('[STARTUP-P0] initBaseContext START');
    hilog.info(0xFF00, TAG, '[P0] InitBaseContext starting...');
    try {
      console.info('[STARTUP-P0] Before AppState.initialize');
      // Initialize global state keys in AppStorage
      AppState.initialize(context);
      console.info('[STARTUP-P0] After AppState.initialize');
      // fix: DEV-011 —— 此处不得调用 PersistentState.initialize（UI 实例未就绪，persistProp 必失效）
      // Initialize the event bus
      console.info('[STARTUP-P0] Before EventBus.initialize');
      EventBus.initialize();
      console.info('[STARTUP-P0] After EventBus.initialize');
      StartupTasks.markComplete('InitBaseContext');
      hilog.info(0xFF00, TAG, '[P0] InitBaseContext completed');
      console.info('[STARTUP-P0] initBaseContext SUCCESS');
    } catch (err) {
      console.error('[STARTUP-P0] initBaseContext FAILED:', err);
      hilog.error(0xFF00, TAG, '[P0] InitBaseContext FAILED: %{public}s', JSON.stringify(err));
      throw new Error('[P0] InitBaseContext failed');
    }
  }

  /**
   * P0 Task 2: Initialize database
   * - Instantiate DatabaseHelper singleton
   * - Create tables + indexes
   * - Set securityLevel: S2
   */
  static async initDatabase(context: Context): Promise<void> {
    console.info('[STARTUP-P0] initDatabase START');
    hilog.info(0xFF00, TAG, '[P0] InitDatabase starting...');
    try {
      console.info('[STARTUP-P0] Before DatabaseHelper.getInstance');
      const dbHelper = DatabaseHelper.getInstance();
      console.info('[STARTUP-P0] Before dbHelper.initialize');
      await dbHelper.initialize(context);
      console.info('[STARTUP-P0] After dbHelper.initialize');
      // Seed builtin moods into custom_emoji (DEV-DB 缺口#8). Idempotent (is_builtin count guard).
      // Non-critical: seed failure must NOT block startup — log and continue (同 registerNotificationChannels 范式)。
      try {
        await CustomEmojiDao.seedBuiltins();
        hilog.info(0xFF00, TAG, '[P0] InitDatabase: custom_emoji builtins seeded');
      } catch (seedErr) {
        hilog.error(0xFF00, TAG, '[P0] seedBuiltins failed (non-critical): %{public}s', JSON.stringify(seedErr));
      }
      // M10: Seed 120 builtin quotes into quote table. Idempotent (is_builtin count guard).
      // Non-critical: 空表会导致名言卡空白,但 seed 失败不阻断启动 — 记录并继续(同 custom_emoji 范式)。
      try {
        await QuoteDao.seedBuiltins();
        hilog.info(0xFF00, TAG, '[P0] InitDatabase: quote builtins seeded');
      } catch (quoteSeedErr) {
        hilog.error(0xFF00, TAG, '[P0] quote seedBuiltins failed (non-critical): %{public}s', JSON.stringify(quoteSeedErr));
      }
      // M06(DEV-005): 灌默认五分区(幂等) + 暖入 AppStorage('sectionConfigs') 供首页冷启动响应式读取。
      // 键名与 SectionViewModel 写入一致(不新造)。非致命:失败仅记日志,不阻塞启动(同 custom_emoji/quote 范式)。
      try {
        await SectionConfigDao.seedDefaults();
        const sections: SectionConfig[] = await SectionConfigDao.loadAll();
        AppStorage.setOrCreate('sectionConfigs', sections);
        hilog.info(0xFF00, TAG, '[P0] InitDatabase: section_config seeded + warmed (%{public}d)', sections.length);
      } catch (sectionSeedErr) {
        hilog.error(0xFF00, TAG, '[P0] section seed/warm failed (non-critical): %{public}s', JSON.stringify(sectionSeedErr));
      }
      // M17-FIX-WARM(DEV-006): DB 真相源 → AppStorage 冷启动暖入(每日提醒开关/时间/方式 + 昵称)。
      // 背景:设置页开关键已由 PersistentState.persistProp 接盘,但每日提醒真相源是 app_settings 表
      // (SettingsViewModel 落库);persistProp 只能恢复「上次扳动开关时」的会话值,DB 值经备份导入/
      // VM 直改后两源会漂移。此处在 P0(首帧前,EntryAbility loadContent 等 startupPromise)回灌:
      // 仅当 DB 存在该键才覆盖(null 不写,避免把 persistProp 恢复的用户选择踩成默认);setOrCreate
      // 发生在 persistProp 之后,新值自动落盘,两源收敛。非致命:失败仅记日志,不阻塞启动(同上范式)。
      try {
        await StartupTasks.warmupSettingsFromDb();
        hilog.info(0xFF00, TAG, '[P0] InitDatabase: settings warmed from DB into AppStorage');
      } catch (warmErr) {
        hilog.error(0xFF00, TAG, '[P0] settings warm failed (non-critical): %{public}s', JSON.stringify(warmErr));
      }
      StartupTasks.markComplete('InitDatabase');
      hilog.info(0xFF00, TAG, '[P0] InitDatabase completed (v%{public}d)', dbHelper.getVersion());
    } catch (err) {
      hilog.error(0xFF00, TAG, '[P0] InitDatabase FAILED: %{public}s', JSON.stringify(err));
      throw new Error('[P0] InitDatabase failed');
    }
  }

  /**
   * M17-FIX-WARM(DEV-006): 把 app_settings(DB)中已存在的设置值回灌 AppStorage。
   * 键名与 features/settings SettingsViewModel 的落库常量一致(shared 不能反向 import features,
   * 就地复刻字面量 —— 同 ReminderAgentService 先例):
   *   'reminder_enabled'('true'/'false') → AppStorage 'app_reminder_enabled'(boolean)
   *   'reminder_time'("HH:mm")           → AppStorage 'app_reminder_hour'/'app_reminder_minute'(number)
   *   'reminder_method'                  → AppStorage 'app_reminder_method'(string)
   *   'app_user_nickname'                → AppStorage 'app_user_nickname'(string)
   * 铁律:DB 无该键(null)时不写,免踩 persistProp 恢复的磁盘值。
   */
  private static async warmupSettingsFromDb(): Promise<void> {
    const enabledStr: string | null = await AppSettingsDao.get('reminder_enabled');
    if (enabledStr !== null) {
      AppStorage.setOrCreate('app_reminder_enabled', enabledStr === 'true');
    }
    const timeStr: string | null = await AppSettingsDao.get('reminder_time');
    if (timeStr !== null && timeStr.length > 0) {
      const parts: string[] = timeStr.split(':');
      if (parts.length >= 2) {
        const hour: number = parseInt(parts[0], 10);
        const minute: number = parseInt(parts[1], 10);
        if (!isNaN(hour) && !isNaN(minute)) {
          AppStorage.setOrCreate('app_reminder_hour', hour);
          AppStorage.setOrCreate('app_reminder_minute', minute);
        }
      }
    }
    const methodStr: string | null = await AppSettingsDao.get('reminder_method');
    if (methodStr !== null && methodStr.length > 0) {
      AppStorage.setOrCreate('app_reminder_method', methodStr);
    }
    const nickname: string | null = await AppSettingsDao.get('app_user_nickname');
    if (nickname !== null && nickname.length > 0) {
      AppStorage.setOrCreate('app_user_nickname', nickname);
    }
  }

  /**
   * P1 Task 3: Restore theme from PersistentStorage
   * - Read current theme ID and dark mode flag
   * - Apply theme configuration
   */
  static async restoreTheme(): Promise<void> {
    hilog.info(0xFF00, TAG, '[P1] RestoreTheme starting...');
    try {
      // 冷启动主题恢复主路径：ThemeManager.init() 会先 persistProp 外观键（从磁盘载入上次 preset/mode/frost/isDark），
      // 再 applyTokens 重算 theme_tokens 并 syncToAppStorage 广播 → 全 App @StorageLink 重着色。
      // init() 是 async，await 之。restoreTheme 属 P1（非致命，见下方 catch）。
      await getThemeManager().init();

      // Theme restoration logic - reads from PersistentStorage
      // 下方 persist_theme_id → app_theme_preset_id 为历史断链路径（无人真正消费 app_theme_preset_id 上屏），
      // 保留不删（别处可能读该键），ThemeManager.init 已接管真实恢复。
      const themeId = AppStorage.get<number>(PersistentState.KEY_THEME_ID);
      const darkMode = AppStorage.get<number>(PersistentState.KEY_DARK_MODE);
      AppStorage.setOrCreate(AppState.KEY_THEME_PRESET_ID, themeId ?? 1);
      AppStorage.setOrCreate(AppState.KEY_DARK_MODE, darkMode ?? -1);
      StartupTasks.markComplete('RestoreTheme');
      hilog.info(0xFF00, TAG, '[P1] RestoreTheme completed (themeId=%{public}d, darkMode=%{public}d)',
        themeId ?? 1, darkMode ?? -1);
    } catch (err) {
      hilog.error(0xFF00, TAG, '[P1] RestoreTheme failed (non-critical): %{public}s', JSON.stringify(err));
      StartupTasks.markComplete('RestoreTheme');
    }
  }

  /**
   * P1 Task 4: Register notification channels
   * - Create daily reminder, pomodoro, and general notification channels
   */
  static async registerNotificationChannels(context: Context): Promise<void> {
    hilog.info(0xFF00, TAG, '[P1] RegisterNotificationChannels starting...');
    try {
      await NotificationUtils.createChannels();
      StartupTasks.markComplete('RegisterNotificationChannels');
      hilog.info(0xFF00, TAG, '[P1] RegisterNotificationChannels completed');
    } catch (err) {
      hilog.error(0xFF00, TAG, '[P1] RegisterNotificationChannels failed (non-critical): %{public}s',
        JSON.stringify(err));
      StartupTasks.markComplete('RegisterNotificationChannels');
    }
  }

  /**
   * P2 Task 5: Preload daily quote
   * - Fetch today's quote from database
   * - Cache in AppStorage for immediate display
   */
  static async preloadQuotes(): Promise<void> {
    hilog.info(0xFF00, TAG, '[P2] PreloadQuotes starting...');
    try {
      // Quote preloading will be fully implemented in T027 (QuoteViewModel)
      // For now, mark as completed (non-critical)
      StartupTasks.markComplete('PreloadQuotes');
      hilog.info(0xFF00, TAG, '[P2] PreloadQuotes completed');
    } catch (err) {
      hilog.error(0xFF00, TAG, '[P2] PreloadQuotes failed (non-critical): %{public}s', JSON.stringify(err));
      StartupTasks.markComplete('PreloadQuotes');
    }
  }

  /**
   * P2 Task 6: Warm up statistics cache
   * - Pre-compute current month check-in rate
   * - Cache for immediate statistics display
   */
  static async warmupStatsCache(): Promise<void> {
    hilog.info(0xFF00, TAG, '[P2] WarmupStatsCache starting...');
    try {
      // Stats cache warmup will be fully implemented in T025 (StatisticsViewModel)
      // For now, mark as completed (non-critical)
      StartupTasks.markComplete('WarmupStatsCache');
      hilog.info(0xFF00, TAG, '[P2] WarmupStatsCache completed');
    } catch (err) {
      hilog.error(0xFF00, TAG, '[P2] WarmupStatsCache failed (non-critical): %{public}s', JSON.stringify(err));
      StartupTasks.markComplete('WarmupStatsCache');
    }
  }

  // ==================== Execution Orchestration ====================

  /**
   * Execute all startup tasks in priority order
   * Must be called from AbilityStage.onCreate
   */
  static async executeAll(context: Context): Promise<void> {
    const startTime = Date.now();
    console.info('[STARTUP] executeAll BEGIN');
    hilog.info(0xFF00, TAG, '========== AppStartup Begin ==========');

    // Phase 1: P0 synchronous tasks (serial, blocking first frame)
    console.info('[STARTUP] About to execute P0 tasks');
    await StartupTasks.executeP0Tasks(context);
    console.info('[STARTUP] P0 tasks completed');
    const p0Time = Date.now() - startTime;
    hilog.info(0xFF00, TAG, '[P0] Phase completed in %{public}dms', p0Time);

    // Phase 2: P1 async tasks (parallel via TaskPool, non-blocking)
    StartupTasks.executeP1Tasks(context).catch((err: Object) => {
      hilog.error(0xFF00, TAG, '[P1] Phase error: %{public}s', JSON.stringify(err));
    });

    // Phase 3: P2 idle tasks (deferred, after first frame)
    StartupTasks.scheduleP2Tasks();

    const totalTime = Date.now() - startTime;
    hilog.info(0xFF00, TAG, '========== AppStartup End (%{public}dms) ==========', totalTime);
  }

  /**
   * Execute P0 synchronous tasks (serial order)
   */
  private static async executeP0Tasks(context: Context): Promise<void> {
    const p0Tasks = StartupConfig.getTasksByPriority(StartupPriority.P0_SYNC);
    for (const task of p0Tasks) {
      switch (task.name) {
        case 'InitBaseContext':
          await StartupTasks.initBaseContext(context);
          break;
        case 'InitDatabase':
          await StartupTasks.initDatabase(context);
          break;
        default:
          hilog.warn(0xFF00, TAG, 'Unknown P0 task: %{public}s', task.name);
      }
    }
  }

  /**
   * Execute P1 async tasks (parallel execution)
   */
  private static async executeP1Tasks(context: Context): Promise<void> {
    const p1Tasks = StartupConfig.getTasksByPriority(StartupPriority.P1_ASYNC);
    const promises: Promise<void>[] = [];
    for (const task of p1Tasks) {
      switch (task.name) {
        case 'RestoreTheme':
          promises.push(StartupTasks.restoreTheme());
          break;
        case 'RegisterNotificationChannels':
          promises.push(StartupTasks.registerNotificationChannels(context));
          break;
      }
    }
    await Promise.all(promises);
  }

  /**
   * Schedule P2 idle tasks (via setTimeout as requestIdleCallback polyfill)
   */
  private static scheduleP2Tasks(): void {
    setTimeout(() => {
      StartupTasks.preloadQuotes().catch((err: Object) => {
        hilog.error(0xFF00, TAG, '[P2] PreloadQuotes error: %{public}s', JSON.stringify(err));
      });
      StartupTasks.warmupStatsCache().catch((err: Object) => {
        hilog.error(0xFF00, TAG, '[P2] WarmupStatsCache error: %{public}s', JSON.stringify(err));
      });
    }, 100);
  }

  // ==================== Utilities ====================

  /**
   * Mark a task as completed
   */
  static markComplete(taskName: string): void {
    StartupTasks.completedTasks.add(taskName);
  }

  /**
   * Check if a specific task has completed
   */
  static isTaskComplete(taskName: string): boolean {
    return StartupTasks.completedTasks.has(taskName);
  }

  /**
   * Check if all P0 tasks have completed
   */
  static isP0Complete(): boolean {
    return StartupConfig.isP0Complete(StartupTasks.completedTasks);
  }

  /**
   * Get all completed task names
   */
  static getCompletedTasks(): string[] {
    return Array.from(StartupTasks.completedTasks);
  }
}
