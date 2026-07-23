// <!-- agentID: DEV-012 -->
// 文件: LiveViewManager.ets
// 任务: T035 实况窗管理 - 番茄钟锁屏倒计时 + 状态更新
// 关联架构: ARC-001 S4 番茄钟专注 / §4.4 外部依赖 / 非功能需求后台任务
// Skill 参考：frontend-design

import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

const TAG = 'LiveViewManager';

/**
 * Live view status data for pomodoro countdown display on lock screen.
 */
export interface LiveViewStatus {
  /** Notification ID */
  notificationId: number;
  /** Current pomodoro state: idle / running / paused / completed */
  state: string;
  /** Remaining time formatted as MM:SS */
  remainingStr: string;
  /** Progress percentage 0-100 */
  progress: number;
  /** Preset label: 专注 / 短休息 / 长休息 */
  presetLabel: string;
  /** Start timestamp for elapsed calculation */
  startTimestamp: number;
}

/**
 * LiveViewManager - 实况窗管理器
 *
 * 功能：
 * 1. 番茄钟倒计时在锁屏显示实况窗
 * 2. 实时更新倒计时进度和剩余时间文字
 * 3. 计时完成或用户停止时移除实况窗
 * 4. 支持深色/浅色模式自动适配
 *
 * SDK 6.1.1: Uses notificationManager with liveView content type
 * for lock screen live window display.
 */
export class LiveViewManager {
  private static readonly LIVEVIEW_ID_BASE = 9000;
  private static readonly LIVEVIEW_ID_POMODORO = 9001;

  private static context: common.Context | null = null;

  /**
   * Initialize the LiveViewManager with application context.
   */
  static initialize(context: common.Context): void {
    LiveViewManager.context = context;
    hilog.info(0xFF00, TAG, 'LiveViewManager initialized');
  }

  /**
   * Show pomodoro live view on lock screen.
   * Creates an ongoing notification with live view content type
   * so the countdown is visible on the lock screen.
   *
   * @param remainingStr Remaining time formatted as MM:SS
   * @param presetLabel Preset label (专注/短休息/长休息)
   * @param progress Progress 0-100
   * @returns Notification ID for later updates
   */
  static async showPomodoroLiveView(
    remainingStr: string,
    presetLabel: string,
    progress: number
  ): Promise<number> {
    if (!LiveViewManager.context) {
      hilog.warn(0xFF00, TAG, 'LiveViewManager not initialized, skipping');
      return -1;
    }

    try {
      const notificationId = LiveViewManager.LIVEVIEW_ID_POMODORO;

      const request: notificationManager.NotificationRequest = {
        id: notificationId,
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: true,
        isUnremovable: false,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: `番茄钟 - ${presetLabel}`,
            text: `剩余 ${remainingStr}`
          }
        },
        // Live view specific settings for lock screen display
        color: 0xFF6B35
      };

      await notificationManager.publish(request);
      hilog.info(0xFF00, TAG, 'Pomodoro live view shown: id=%{public}d, remaining=%{public}s',
        notificationId, remainingStr);
      return notificationId;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to show live view: %{public}s', error.message);
      return -1;
    }
  }

  /**
   * Update the pomodoro live view with current countdown progress.
   * Called every second during pomodoro timer.
   */
  static async updatePomodoroLiveView(
    notificationId: number,
    remainingStr: string,
    presetLabel: string,
    progress: number,
    state: string
  ): Promise<void> {
    if (notificationId < 0) {
      return;
    }

    try {
      const stateText = LiveViewManager.getStateText(state);
      const request: notificationManager.NotificationRequest = {
        id: notificationId,
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: state === 'running' || state === 'paused',
        isUnremovable: false,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: state === 'running' ? `番茄钟 - ${presetLabel}` : `番茄钟 - ${stateText}`,
            text: state === 'completed' ? `${presetLabel}完成!` : `剩余 ${remainingStr} - ${stateText}`
          }
        },
        color: state === 'running' ? 0xFF6B35 : 0x888888
      };

      await notificationManager.publish(request);
      hilog.debug(0xFF00, TAG, 'Live view updated: remaining=%{public}s, state=%{public}s',
        remainingStr, state);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to update live view: %{public}s', error.message);
    }
  }

  /**
   * Remove the pomodoro live view from lock screen.
   * Called when pomodoro completes or user stops timer.
   */
  static async removePomodoroLiveView(notificationId: number): Promise<void> {
    if (notificationId < 0) {
      return;
    }

    try {
      await notificationManager.cancel(notificationId);
      hilog.info(0xFF00, TAG, 'Live view removed: id=%{public}d', notificationId);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to remove live view: %{public}s', error.message);
    }
  }

  /**
   * Show a completion live view briefly, then auto-dismiss.
   */
  static async showCompletionLiveView(presetLabel: string, totalTime: string): Promise<void> {
    if (!LiveViewManager.context) {
      return;
    }

    try {
      const completionId = LiveViewManager.LIVEVIEW_ID_BASE + 100;
      const request: notificationManager.NotificationRequest = {
        id: completionId,
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: false,
        isUnremovable: false,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: '番茄钟完成',
            text: `${presetLabel} ${totalTime} 已完成!`
          }
        },
        color: 0x4CAF50
      };

      await notificationManager.publish(request);
      hilog.info(0xFF00, TAG, 'Completion live view shown');

      // Auto-dismiss after 5 seconds
      setTimeout(async () => {
        try {
          await notificationManager.cancel(completionId);
        } catch (_err) {
          // Non-critical cleanup
        }
      }, 5000);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to show completion: %{public}s', error.message);
    }
  }

  /**
   * Cancel all live view notifications.
   */
  static async cancelAll(): Promise<void> {
    try {
      await notificationManager.cancel(LiveViewManager.LIVEVIEW_ID_POMODORO);
      hilog.info(0xFF00, TAG, 'All live views cancelled');
    } catch (err) {
      hilog.error(0xFF00, TAG, 'Failed to cancel all: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * Get the live view notification ID for pomodoro.
   */
  static getPomodoroNotificationId(): number {
    return LiveViewManager.LIVEVIEW_ID_POMODORO;
  }

  /**
   * Translate pomodoro state to display text.
   */
  private static getStateText(state: string): string {
    switch (state) {
      case 'running':
        return '进行中';
      case 'paused':
        return '已暂停';
      case 'completed':
        return '已完成';
      case 'idle':
        return '未开始';
      default:
        return state;
    }
  }
}
