// <!-- agentID: DEV-001 -->
// File: StartupConfig.ets
// Task: T040 AppStartup - 3-level startup task configuration
// Architecture: ARC-001 3.6 AppStartup
// Skill Ref: frontend-design / ui-ux-pro-max

/**
 * Startup task priority levels
 */
export enum StartupPriority {
  /** P0 - Synchronous on main thread, must complete before first frame */
  P0_SYNC = 0,
  /** P1 - Asynchronous via TaskPool, parallel execution, first frame NOT blocked */
  P1_ASYNC = 1,
  /** P2 - Deferred via requestIdleCallback, after first frame rendered */
  P2_IDLE = 2
}

/**
 * Startup task descriptor
 */
export interface StartupTask {
  /** Unique task identifier */
  name: string;
  /** Priority level */
  priority: StartupPriority;
  /** Tasks that must complete before this task starts */
  dependencies: string[];
  /** Execution timeout in milliseconds (0 = no timeout) */
  timeout: number;
  /** Whether failure blocks startup */
  critical: boolean;
}

/**
 * Startup phase timing targets (per AppGallery Connect audit standard)
 */
export interface StartupTimingTargets {
  /** Application response target (ms) */
  appResponse: number;
  /** Application startup target (ms) */
  appStartup: number;
  /** First page load target (ms) */
  firstPageLoad: number;
}

/**
 * StartupConfig - Defines the AppStartup framework configuration
 *
 * 3-level startup strategy:
 * - P0 SYNC: AbilityStage base init + exception hook + database init (serial on main thread)
 * - P1 ASYNC: Theme restore + notification channel registration (parallel via TaskPool)
 * - P2 IDLE: Quote preload + stats cache warmup (deferred via requestIdleCallback)
 */
export class StartupConfig {
  /** Performance timing targets */
  static readonly TIMING: StartupTimingTargets = {
    appResponse: 85,
    appStartup: 600,
    firstPageLoad: 1000
  };

  /** Task definitions in dependency order */
  static readonly TASKS: StartupTask[] = [
    {
      name: 'InitBaseContext',
      priority: StartupPriority.P0_SYNC,
      dependencies: [],
      timeout: 5000,
      critical: true
    },
    {
      name: 'InitDatabase',
      priority: StartupPriority.P0_SYNC,
      dependencies: ['InitBaseContext'],
      timeout: 10000,
      critical: true
    },
    {
      name: 'RestoreTheme',
      priority: StartupPriority.P1_ASYNC,
      dependencies: ['InitBaseContext'],
      timeout: 3000,
      critical: false
    },
    {
      name: 'RegisterNotificationChannels',
      priority: StartupPriority.P1_ASYNC,
      dependencies: ['InitBaseContext'],
      timeout: 3000,
      critical: false
    },
    {
      name: 'PreloadQuotes',
      priority: StartupPriority.P2_IDLE,
      dependencies: ['InitDatabase'],
      timeout: 5000,
      critical: false
    },
    {
      name: 'WarmupStatsCache',
      priority: StartupPriority.P2_IDLE,
      dependencies: ['InitDatabase'],
      timeout: 5000,
      critical: false
    }
  ];

  /**
   * Get tasks by priority level
   */
  static getTasksByPriority(priority: StartupPriority): StartupTask[] {
    return StartupConfig.TASKS.filter(t => t.priority === priority);
  }

  /**
   * Check if all critical P0 tasks have completed
   */
  static isP0Complete(completedTasks: Set<string>): boolean {
    const p0Critical = StartupConfig.TASKS.filter(t =>
      t.priority === StartupPriority.P0_SYNC && t.critical
    );
    return p0Critical.every(t => completedTasks.has(t.name));
  }
}
