// <!-- agentID: DEV-011 -->
// File: NotificationUtils.ets
// Task: T007a Core utility - Notification sending, channel creation, permission handling
// Architecture: ARC-001 4.4 / non-functional notification
// Skill Ref: frontend-design / ui-ux-pro-max

import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common, WantAgent } from '@kit.AbilityKit';

const TAG = 'NotificationUtils';

export interface NotificationOptions {
  title: string;
  text: string;
  wantAgent?: WantAgent;
  notificationSlotType?: notificationManager.SlotType;
}

/**
 * NotificationUtils - Notification management utilities.
 * Handles: channel creation, notification sending, permission checks, dynamic permission requests.
 */
export class NotificationUtils {
  /**
   * Create all notification slots (call in P1 startup).
   * Reference: notificationManager.addSlot (SDK 6.1.1) — @ohos.notificationManager.d.ts §addSlot
   */
  static async createChannels(): Promise<void> {
    try {
      // Daily reminder slot
      await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION);
      // Pomodoro timer slot
      await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
      // General slot
      await notificationManager.addSlot(notificationManager.SlotType.CONTENT_INFORMATION);
      hilog.info(0xFF00, TAG, 'Notification slots created');
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to create slots: %{public}s', error.message);
    }
  }

  /**
   * Check if notification permission is granted.
   */
  static async isPermissionGranted(): Promise<boolean> {
    try {
      const result = await notificationManager.isNotificationEnabled();
      return result;
    } catch (err) {
      hilog.error(0xFF00, TAG, 'Permission check failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * Request notification permission (caller must handle user rejection gracefully).
   * Reference: notificationManager.requestEnableNotification (SDK 12+) — requires UIAbilityContext
   */
  static async requestPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      await notificationManager.requestEnableNotification(context);
      return true;
    } catch (err) {
      hilog.warn(0xFF00, TAG, 'User denied notification permission');
      return false;
    }
  }

  /**
   * Send a daily reminder notification.
   */
  static async sendDailyReminder(title: string, text: string): Promise<void> {
    await NotificationUtils.sendNotification({
      title: title,
      text: text,
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
    });
  }

  /** DEV-013：待办提醒通知（系统提醒降级兜底 + 一般通知） */
  static async sendTodoReminder(todoId: number, title: string): Promise<void> {
    await NotificationUtils.sendNotification({
      title: '⏰ 待办提醒',
      text: title,
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
    });
  }

  /**
   * Send a pomodoro completion notification.
   */
  static async sendPomodoroComplete(remainingText: string): Promise<void> {
    await NotificationUtils.sendNotification({
      title: '番茄钟完成',
      text: remainingText,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION
    });
  }

  /**
   * Send a general notification.
   */
  static async sendGeneral(title: string, text: string): Promise<void> {
    await NotificationUtils.sendNotification({
      title: title,
      text: text,
      notificationSlotType: notificationManager.SlotType.CONTENT_INFORMATION
    });
  }

  /**
   * Generic notification sender.
   * Reference: NotificationRequest.notificationSlotType (SDK 11+) replaces deprecated slotType
   */
  private static async sendNotification(options: NotificationOptions): Promise<void> {
    try {
      const isEnabled = await NotificationUtils.isPermissionGranted();
      if (!isEnabled) {
        hilog.warn(0xFF00, TAG, 'Notification not enabled, skipping');
        return;
      }
      const request: notificationManager.NotificationRequest = {
        id: Date.now(),
        notificationSlotType: options.notificationSlotType ?? notificationManager.SlotType.CONTENT_INFORMATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: options.title,
            text: options.text
          }
        }
      };
      await notificationManager.publish(request);
      hilog.info(0xFF00, TAG, 'Notification sent: %{public}s', options.title);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to send notification: %{public}s', error.message);
    }
  }

  /**
   * Cancel a specific notification by ID.
   */
  static async cancel(id: number): Promise<void> {
    try {
      await notificationManager.cancel(id);
    } catch (err) {
      hilog.error(0xFF00, TAG, 'Failed to cancel notification: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * Cancel all notifications.
   */
  static async cancelAll(): Promise<void> {
    try {
      await notificationManager.cancelAll();
    } catch (err) {
      hilog.error(0xFF00, TAG, 'Failed to cancel all notifications: %{public}s', JSON.stringify(err));
    }
  }
}
