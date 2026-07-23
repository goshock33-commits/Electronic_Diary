// <!-- agentID: DEV-017 -->
// fix: HUI-FRONTEND
// 文件: DiaryReminderManager.ets
// 任务: T035 日记提醒通知系统 - 每日提醒注册/更新/取消
// 关联架构: ARC-001 §4.4 外部依赖 / 需求 9.1 每日提醒 / 非功能需求通知
// Skill 参考：frontend-design

import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const TAG = 'DiaryReminderManager';

/**
 * Reminder configuration stored in preferences.
 */
export interface DiaryReminderConfig {
  /** Whether daily reminder is enabled */
  enabled: boolean;
  /** Hour (0-23) */
  hour: number;
  /** Minute (0-59) */
  minute: number;
  /** Notification method: notification / sound / both */
  notifyMethod: string;
  /** Custom ringtone URI (empty = default) */
  ringtoneUri: string;
  /** Reminder text template */
  reminderText: string;
}

/**
 * DiaryReminderManager - 日记提醒通知系统
 *
 * 功能：
 * 1. 使用 reminderAgentManager 注册后台代理提醒
 * 2. 支持每日定时提醒写日记
 * 3. 支持通知方式选择（弹通知/响铃/弹通知+响铃）
 * 4. 支持自定义铃声
 * 5. 提醒启用/禁用开关
 * 6. 提醒时间变更时自动重新注册
 *
 * SDK 6.1.1: Uses reminderAgentManager from @kit.BackgroundTasksKit
 */
export class DiaryReminderManager {
  private static readonly REMINDER_ID = 2001;
  private static readonly PREF_KEY_REMINDER = 'diary_reminder_config';
  private static context: common.Context | null = null;

  /** Default reminder config */
  private static readonly DEFAULT_CONFIG: DiaryReminderConfig = {
    enabled: false,
    hour: 20,
    minute: 0,
    notifyMethod: 'notification',
    ringtoneUri: '',
    reminderText: '今天还没有写日记哦，快来记录一下吧！'
  };

  /**
   * Initialize the reminder manager with application context.
   */
  static initialize(context: common.Context): void {
    DiaryReminderManager.context = context;
    hilog.info(0xFF00, TAG, 'DiaryReminderManager initialized');
  }

  /**
   * Get current reminder configuration from preferences.
   */
  static async getConfig(): Promise<DiaryReminderConfig> {
    try {
      if (!DiaryReminderManager.context) {
        return DiaryReminderManager.DEFAULT_CONFIG;
      }
      const dataPreferences = await preferences.getPreferences(
        DiaryReminderManager.context, 'diary_settings');
      const configStr = dataPreferences.getSync(DiaryReminderManager.PREF_KEY_REMINDER, '') as string;
      if (configStr.length > 0) {
        const parsedConfig: DiaryReminderConfig = JSON.parse(configStr) as DiaryReminderConfig;
        return parsedConfig;
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to get config: %{public}s', error.message);
    }
    return DiaryReminderManager.DEFAULT_CONFIG;
  }

  /**
   * Save reminder configuration and re-register reminder.
   */
  static async saveConfig(config: DiaryReminderConfig): Promise<boolean> {
    try {
      if (!DiaryReminderManager.context) {
        hilog.warn(0xFF00, TAG, 'Context not initialized');
        return false;
      }
      const dataPreferences = await preferences.getPreferences(
        DiaryReminderManager.context, 'diary_settings');
      await dataPreferences.put(DiaryReminderManager.PREF_KEY_REMINDER, JSON.stringify(config));
      await dataPreferences.flush();

      // Re-register reminder with new config
      await DiaryReminderManager.cancelReminder();
      if (config.enabled) {
        await DiaryReminderManager.registerReminder(config);
      }
      hilog.info(0xFF00, TAG, 'Config saved: enabled=%{public}s, time=%{public}d:%{public}d',
        config.enabled.toString(), config.hour, config.minute);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to save config: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Register a recurring daily reminder using reminderAgentManager.
   * The system will show a notification at the specified time each day.
   */
  static async registerReminder(config?: DiaryReminderConfig): Promise<boolean> {
    if (!DiaryReminderManager.context) {
      hilog.warn(0xFF00, TAG, 'Cannot register: context not initialized');
      return false;
    }

    const cfg = config ?? DiaryReminderManager.DEFAULT_CONFIG;
    if (!cfg.enabled) {
      hilog.info(0xFF00, TAG, 'Reminder disabled, skipping registration');
      return false;
    }

    try {
      // First cancel any existing reminder
      await DiaryReminderManager.cancelReminder();

      // F7: 点提醒跳「写日记页」——API 24 ActionButton 仅支持 CLOSE/SNOOZE（本地 .d.ts 实证，
      //   按钮本身无跳转能力），跳转走 ReminderRequest 级 wantAgent.parameters 带路由目标，
      //   EntryAbility onCreate/onNewWant 消费 router_target → router.pushUrl('pages/DiaryEditPage')。
      //   §8.3①：Record<string,Object> 空字面量起手 + 括号逐键赋值。
      const wantParams: Record<string, Object> = {};
      wantParams['router_target'] = 'pages/DiaryEditPage';

      // Build the reminder agent request
      const reminderRequest: reminderAgentManager.ReminderRequestTimer = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
        // Daily repeat at specified time
        triggerTimeInSeconds: DiaryReminderManager.calculateTriggerTime(cfg.hour, cfg.minute),
        actionButton: [
          {
            title: '写日记',
            type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE
          } as reminderAgentManager.ActionButton
        ],
        wantAgent: {
          // F7: pkgName 修正为真实 bundleName（AppScope/app.json5），原 com.example.huaweidiary 点击无法拉起本应用
          pkgName: 'com.example.electronic_diary',
          abilityName: 'EntryAbility',
          parameters: wantParams
        } as reminderAgentManager.WantAgent,
        notificationId: DiaryReminderManager.REMINDER_ID,
        slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        title: '日记提醒',
        content: cfg.reminderText,
        expiredContent: '日记提醒已过期',
        snoozeContent: '稍后提醒',
        ringDuration: 30,
        snoozeTimes: 3,
        timeInterval: 5 * 60
      };

      await reminderAgentManager.publishReminder(reminderRequest);
      hilog.info(0xFF00, TAG, 'Reminder registered: time=%{public}d:%{public}d, method=%{public}s',
        cfg.hour, cfg.minute, cfg.notifyMethod);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to register reminder: code=%{public}d, msg=%{public}s',
        error.code, error.message);
      return false;
    }
  }

  /**
   * Cancel the diary reminder.
   */
  static async cancelReminder(): Promise<void> {
    try {
      await reminderAgentManager.cancelReminder(DiaryReminderManager.REMINDER_ID);
      hilog.info(0xFF00, TAG, 'Reminder cancelled');
    } catch (err) {
      const error = err as BusinessError;
      // Error code 17000004 means reminder doesn't exist, which is fine
      if (error.code !== 17000004) {
        hilog.error(0xFF00, TAG, 'Failed to cancel reminder: %{public}s', error.message);
      }
    }
  }

  /**
   * Check if the diary reminder is currently active.
   */
  static async isReminderActive(): Promise<boolean> {
    try {
      const config = await DiaryReminderManager.getConfig();
      return config.enabled;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to check reminder status: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Toggle the diary reminder on/off.
   */
  static async toggleReminder(enabled: boolean): Promise<boolean> {
    try {
      const config = await DiaryReminderManager.getConfig();
      config.enabled = enabled;
      return await DiaryReminderManager.saveConfig(config);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to toggle reminder: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Update the reminder time.
   */
  static async setReminderTime(hour: number, minute: number): Promise<boolean> {
    try {
      const config = await DiaryReminderManager.getConfig();
      config.hour = hour;
      config.minute = minute;
      return await DiaryReminderManager.saveConfig(config);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to set time: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Set the notification method.
   */
  static async setNotifyMethod(method: string): Promise<boolean> {
    try {
      const config = await DiaryReminderManager.getConfig();
      config.notifyMethod = method;
      return await DiaryReminderManager.saveConfig(config);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to set method: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Set custom ringtone URI.
   */
  static async setRingtone(uri: string): Promise<boolean> {
    try {
      const config = await DiaryReminderManager.getConfig();
      config.ringtoneUri = uri;
      return await DiaryReminderManager.saveConfig(config);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to set ringtone: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Set reminder text template.
   */
  static async setReminderText(text: string): Promise<boolean> {
    try {
      const config = await DiaryReminderManager.getConfig();
      config.reminderText = text;
      return await DiaryReminderManager.saveConfig(config);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to set text: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Get all active reminders (for debugging).
   */
  static async getAllReminders(): Promise<reminderAgentManager.ReminderRequest[]> {
    try {
      const reminders: Array<reminderAgentManager.ReminderRequest> = await reminderAgentManager.getValidReminders();
      return reminders;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to get reminders: %{public}s', error.message);
      return [];
    }
  }

  /**
   * Calculate trigger time in seconds from now for the next occurrence at target hour/minute.
   */
  private static calculateTriggerTime(hour: number, minute: number): number {
    const now = new Date();
    const target = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour, minute, 0);
    // If the target time has already passed today, schedule for tomorrow
    if (target.getTime() <= now.getTime()) {
      target.setDate(target.getDate() + 1);
    }
    return Math.floor(target.getTime() / 1000);
  }
}
