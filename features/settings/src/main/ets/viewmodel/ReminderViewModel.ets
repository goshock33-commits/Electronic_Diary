// <!-- agentID: DEV-M17 -->
// File: ReminderViewModel.ets
// Task: M17 Reminder backend - ViewModel bridge wrapping DiaryReminderManager
// Architecture: ARC-001 S4 reminders / B01 EventBus / R0-3 AppStorage
// Pattern: Follows TodoViewModel (M02) and DiaryViewModel (M03) patterns

import { DiaryReminderManager } from '@ohos/shared';
import type { DiaryReminderConfig } from '@ohos/shared';
import { EventBus } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'ReminderViewModel';

/**
 * ReminderViewModel - Bridges DiaryReminderManager with AppStorage + EventBus.
 * DiaryReminderManager handles the hardware-level reminder agent registration;
 * this ViewModel adds reactive state management so the UI layer can consume
 * config changes via @StorageLink('reminderConfig').
 */
export class ReminderViewModel {
  private config: DiaryReminderConfig | null = null;

  /**
   * Initialize - load current config from DiaryReminderManager.
   */
  async init(): Promise<void> {
    try {
      this.config = await DiaryReminderManager.getConfig();
      AppStorage.setOrCreate('reminderConfig', this.config);
      hilog.info(0x0000, TAG, 'ReminderViewModel init: enabled=%{public}s',
        String(this.config.enabled));
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Init failed: %{public}s', error.message);
    }
  }

  /**
   * Get current reminder config.
   */
  getConfig(): DiaryReminderConfig | null {
    return this.config;
  }

  /**
   * Toggle the daily reminder on/off.
   */
  async toggleReminder(enabled: boolean): Promise<boolean> {
    try {
      const result = await DiaryReminderManager.toggleReminder(enabled);
      if (result) {
        this.config = await DiaryReminderManager.getConfig();
        AppStorage.setOrCreate('reminderConfig', this.config);
        const payload: Record<string, Object> = {};
        payload['enabled'] = this.config.enabled;
        payload['hour'] = this.config.hour;
        payload['minute'] = this.config.minute;
        payload['notifyMethod'] = this.config.notifyMethod;
        EventBus.emit(EventBus.EventNames.REMINDER_CHANGED, payload);
        hilog.info(0x0000, TAG, 'Reminder toggled: enabled=%{public}s', String(enabled));
      }
      return result;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Toggle failed: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Update the reminder time.
   */
  async setReminderTime(hour: number, minute: number): Promise<boolean> {
    try {
      const result = await DiaryReminderManager.setReminderTime(hour, minute);
      if (result) {
        this.config = await DiaryReminderManager.getConfig();
        AppStorage.setOrCreate('reminderConfig', this.config);
        const payload: Record<string, Object> = {};
        payload['enabled'] = this.config.enabled;
        payload['hour'] = this.config.hour;
        payload['minute'] = this.config.minute;
        payload['notifyMethod'] = this.config.notifyMethod;
        EventBus.emit(EventBus.EventNames.REMINDER_CHANGED, payload);
        hilog.info(0x0000, TAG, 'Reminder time set: %{public}d:%{public}d', hour, minute);
      }
      return result;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'SetTime failed: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Set the notification method (notification / ring / both).
   */
  async setNotifyMethod(method: string): Promise<boolean> {
    try {
      const result = await DiaryReminderManager.setNotifyMethod(method);
      if (result) {
        this.config = await DiaryReminderManager.getConfig();
        AppStorage.setOrCreate('reminderConfig', this.config);
        const payload: Record<string, Object> = {};
        payload['enabled'] = this.config.enabled;
        payload['hour'] = this.config.hour;
        payload['minute'] = this.config.minute;
        payload['notifyMethod'] = this.config.notifyMethod;
        EventBus.emit(EventBus.EventNames.REMINDER_CHANGED, payload);
        hilog.info(0x0000, TAG, 'Notify method set: %{public}s', method);
      }
      return result;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'SetMethod failed: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Set custom ringtone URI.
   */
  async setRingtone(uri: string): Promise<boolean> {
    try {
      const result = await DiaryReminderManager.setRingtone(uri);
      if (result) {
        this.config = await DiaryReminderManager.getConfig();
        AppStorage.setOrCreate('reminderConfig', this.config);
        hilog.info(0x0000, TAG, 'Ringtone set');
      }
      return result;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'SetRingtone failed: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Check if the reminder is currently active.
   */
  async isReminderActive(): Promise<boolean> {
    return await DiaryReminderManager.isReminderActive();
  }
}
