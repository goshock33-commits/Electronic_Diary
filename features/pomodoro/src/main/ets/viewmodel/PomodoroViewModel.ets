// <!-- agentID: DEV-008 -->
// File: PomodoroViewModel.ets
// Task: M08 Pomodoro timer business logic + LiveView lock screen countdown
// Architecture: ARC-001 S4 pomodoro / 4.1 PomodoroDao / 4.5 EventBus
// M08 fixes: EventBus flat payload (no nested data wrapper), EventNames constants,
//            AppStorage app_pomodoro_active writes, payload normalized { state, remaining, total, presetType }

import { PomodoroDao } from '@ohos/shared';
import { PomodoroSession } from '@ohos/shared';
import { EventBus } from '@ohos/shared';
import { AppState } from '@ohos/shared';
import { NotificationUtils } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';

const TAG = 'PomodoroViewModel';

export enum PomodoroState { IDLE = 'idle', RUNNING = 'running', PAUSED = 'paused', STOPPED = 'stopped' }
export enum PomodoroPreset { FOCUS = 'focus', SHORT_BREAK = 'short_break', LONG_BREAK = 'long_break' }

export class PomodoroViewModel {
  private state: PomodoroState = PomodoroState.IDLE;
  private preset: PomodoroPreset = PomodoroPreset.FOCUS;
  private totalSeconds: number = 25 * 60;
  private remainingSeconds: number = 25 * 60;
  private startTimestamp: number = 0;
  private timerId: number = -1;
  private sessionId: number = 0;
  /** Live view notification ID for lock screen countdown display */
  private liveViewNotificationId: number = -1;
  /** Tick counter to throttle live view updates (every 5 seconds) */
  private liveViewTickCounter: number = 0;

  async init(preset?: PomodoroPreset): Promise<void> {
    if (preset) { this.setPreset(preset); }
    this.remainingSeconds = this.totalSeconds;
    this.state = PomodoroState.IDLE;
  }

  setPreset(preset: PomodoroPreset): void {
    this.preset = preset;
    switch (preset) {
      case PomodoroPreset.FOCUS: this.totalSeconds = 25 * 60; break;
      case PomodoroPreset.SHORT_BREAK: this.totalSeconds = 5 * 60; break;
      case PomodoroPreset.LONG_BREAK: this.totalSeconds = 15 * 60; break;
    }
    this.remainingSeconds = this.totalSeconds;
  }

  async start(): Promise<boolean> {
    if (this.state === PomodoroState.RUNNING) { return false; }
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0
      };
      const pomodoroAgent = await wantAgent.getWantAgent(wantAgentInfo);
      await backgroundTaskManager.startBackgroundRunning(this.getContext(), backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, pomodoroAgent);
    } catch (_) { /* continue without background task */ }
    this.state = PomodoroState.RUNNING;
    this.startTimestamp = Date.now();
    // Create session record
    const session = new PomodoroSession(this.getTodayDate(), this.preset, this.totalSeconds / 60);
    this.sessionId = await PomodoroDao.insert(session);
    this.startTimer();
    // Publish live view notification for lock screen display
    this.publishLiveView();
    // AppStorage: mark pomodoro as active
    AppStorage.setOrCreate(AppState.KEY_POMODORO_ACTIVE, 1);
    // EventBus: flat payload with all 4 fields
    const startPayload: Record<string, Object> = {};
    startPayload['state'] = this.state;
    startPayload['remaining'] = this.remainingSeconds;
    startPayload['total'] = this.totalSeconds;
    startPayload['presetType'] = this.preset;
    EventBus.emit(EventBus.EventNames.POMODORO_STATE, startPayload);
    hilog.info(0x0000, TAG, 'Pomodoro started: preset=%{public}s, seconds=%{public}d', this.preset, this.remainingSeconds);
    return true;
  }

  async pause(): Promise<void> {
    if (this.state !== PomodoroState.RUNNING) { return; }
    this.state = PomodoroState.PAUSED;
    this.stopTimer();
    // Update live view to show paused state
    this.updateLiveView();
    // AppStorage: still active (session exists, just paused)
    AppStorage.setOrCreate(AppState.KEY_POMODORO_ACTIVE, 1);
    const pausePayload: Record<string, Object> = {};
    pausePayload['state'] = this.state;
    pausePayload['remaining'] = this.remainingSeconds;
    pausePayload['total'] = this.totalSeconds;
    pausePayload['presetType'] = this.preset;
    EventBus.emit(EventBus.EventNames.POMODORO_STATE, pausePayload);
  }

  async resume(): Promise<void> {
    if (this.state !== PomodoroState.PAUSED) { return; }
    this.state = PomodoroState.RUNNING;
    this.startTimestamp = Date.now();
    this.startTimer();
    // Update live view back to running
    this.updateLiveView();
    // AppStorage: active again
    AppStorage.setOrCreate(AppState.KEY_POMODORO_ACTIVE, 1);
    const resumePayload: Record<string, Object> = {};
    resumePayload['state'] = this.state;
    resumePayload['remaining'] = this.remainingSeconds;
    resumePayload['total'] = this.totalSeconds;
    resumePayload['presetType'] = this.preset;
    EventBus.emit(EventBus.EventNames.POMODORO_STATE, resumePayload);
  }

  async stop(): Promise<void> {
    this.state = PomodoroState.STOPPED;
    this.stopTimer();
    // Remove live view from lock screen
    this.removeLiveView();
    try { await backgroundTaskManager.stopBackgroundRunning(this.getContext()); } catch (_) { /* ignore */ }
    if (this.sessionId > 0) {
      const elapsed = this.totalSeconds - this.remainingSeconds;
      // Update session record would go here
    }
    // AppStorage: pomodoro no longer active
    AppStorage.setOrCreate(AppState.KEY_POMODORO_ACTIVE, 0);
    const stopPayload: Record<string, Object> = {};
    stopPayload['state'] = this.state;
    stopPayload['remaining'] = 0;
    stopPayload['total'] = this.totalSeconds;
    stopPayload['presetType'] = this.preset;
    EventBus.emit(EventBus.EventNames.POMODORO_STATE, stopPayload);
  }

  async reset(): Promise<void> {
    this.stopTimer();
    this.remainingSeconds = this.totalSeconds;
    this.state = PomodoroState.IDLE;
    // Remove live view on reset
    this.removeLiveView();
    // AppStorage: pomodoro not active
    AppStorage.setOrCreate(AppState.KEY_POMODORO_ACTIVE, 0);
    const resetPayload: Record<string, Object> = {};
    resetPayload['state'] = this.state;
    resetPayload['remaining'] = this.remainingSeconds;
    resetPayload['total'] = this.totalSeconds;
    resetPayload['presetType'] = this.preset;
    EventBus.emit(EventBus.EventNames.POMODORO_STATE, resetPayload);
  }

  private startTimer(): void {
    this.timerId = setInterval(() => {
      if (this.state !== PomodoroState.RUNNING) { return; }
      this.remainingSeconds--;
      // Update live view every 5 ticks to reduce notification spam
      this.liveViewTickCounter++;
      if (this.liveViewTickCounter >= 5 || this.remainingSeconds <= 0) {
        this.updateLiveView();
        this.liveViewTickCounter = 0;
      }
      if (this.remainingSeconds <= 0) {
        this.onComplete();
      }
    }, 1000);
  }

  private stopTimer(): void { if (this.timerId >= 0) { clearInterval(this.timerId); this.timerId = -1; } }

  private async onComplete(): Promise<void> {
    this.stopTimer();
    this.state = PomodoroState.IDLE;
    // Show completion live view briefly
    this.showCompletionLiveView();
    try { await NotificationUtils.sendPomodoroComplete(`${this.formatTime(this.totalSeconds)} 完成`); } catch (_) { /* ignore */ }
    try { await backgroundTaskManager.stopBackgroundRunning(this.getContext()); } catch (_) { /* ignore */ }
    // AppStorage: pomodoro no longer active
    AppStorage.setOrCreate(AppState.KEY_POMODORO_ACTIVE, 0);
    const completePayload: Record<string, Object> = {};
    completePayload['state'] = 'completed';
    completePayload['remaining'] = 0;
    completePayload['total'] = this.totalSeconds;
    completePayload['presetType'] = this.preset;
    EventBus.emit(EventBus.EventNames.POMODORO_STATE, completePayload);
  }

  // ==================== Live View (实况窗) Integration (T035) ====================

  /**
   * Publish an ongoing notification that shows on the lock screen as a live view.
   * This provides a countdown timer display on the lock screen.
   */
  private async publishLiveView(): Promise<void> {
    try {
      const presetLabel = this.getPresetLabel();
      const request: notificationManager.NotificationRequest = {
        id: this.getLiveViewId(),
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: true,
        isUnremovable: false,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: `番茄钟 - ${presetLabel}`,
            text: `剩余 ${this.getRemainingFormatted()}`
          }
        },
        color: 0xFF6B35
      };
      await notificationManager.publish(request);
      this.liveViewNotificationId = this.getLiveViewId();
    } catch (_err) {
      // Live view is non-critical; silently ignore failures
    }
  }

  /**
   * Update the live view notification with current countdown state.
   */
  private async updateLiveView(): Promise<void> {
    if (this.liveViewNotificationId < 0) {
      return;
    }
    try {
      const presetLabel = this.getPresetLabel();
      const stateText = this.getLiveViewStateText();
      const request: notificationManager.NotificationRequest = {
        id: this.liveViewNotificationId,
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: this.state === PomodoroState.RUNNING || this.state === PomodoroState.PAUSED,
        isUnremovable: false,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: this.state === PomodoroState.RUNNING ? `番茄钟 - ${presetLabel}` : `番茄钟 - ${stateText}`,
            text: `剩余 ${this.getRemainingFormatted()} - ${stateText}`
          }
        },
        color: this.state === PomodoroState.RUNNING ? 0xFF6B35 : 0x888888
      };
      await notificationManager.publish(request);
    } catch (_err) {
      // Non-critical; silently ignore
    }
  }

  /**
   * Remove the live view notification from lock screen.
   */
  private async removeLiveView(): Promise<void> {
    if (this.liveViewNotificationId < 0) {
      return;
    }
    try {
      await notificationManager.cancel(this.liveViewNotificationId);
      this.liveViewNotificationId = -1;
    } catch (_err) {
      // Non-critical
    }
  }

  /**
   * Show a brief completion notification as live view.
   */
  private async showCompletionLiveView(): Promise<void> {
    try {
      const presetLabel = this.getPresetLabel();
      const completionId = 9100;
      const request: notificationManager.NotificationRequest = {
        id: completionId,
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: false,
        isUnremovable: false,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: '番茄钟完成',
            text: `${presetLabel} ${this.formatTime(this.totalSeconds)} 已完成!`
          }
        },
        color: 0x4CAF50
      };
      await notificationManager.publish(request);
      // Auto-dismiss after 5 seconds
      setTimeout(async () => {
        try { await notificationManager.cancel(completionId); } catch (_) { /* ignore */ }
      }, 5000);
    } catch (_err) {
      // Non-critical
    }
  }

  /**
   * Get fixed notification ID for live view.
   */
  private getLiveViewId(): number {
    return 9001;
  }

  /**
   * Get human-readable preset label.
   */
  private getPresetLabel(): string {
    switch (this.preset) {
      case PomodoroPreset.SHORT_BREAK:
        return '短休息';
      case PomodoroPreset.LONG_BREAK:
        return '长休息';
      default:
        return '专注';
    }
  }

  /**
   * Get human-readable state text for live view display.
   */
  private getLiveViewStateText(): string {
    switch (this.state) {
      case PomodoroState.RUNNING:
        return '进行中';
      case PomodoroState.PAUSED:
        return '已暂停';
      default:
        return '未开始';
    }
  }

  private getContext(): Context { return getContext(this) as Context; }

  getState(): PomodoroState { return this.state; }
  getPreset(): PomodoroPreset { return this.preset; }
  getRemaining(): number { return this.remainingSeconds; }
  getTotal(): number { return this.totalSeconds; }
  getProgress(): number { return this.totalSeconds > 0 ? (this.totalSeconds - this.remainingSeconds) / this.totalSeconds : 0; }
  getRemainingFormatted(): string { return this.formatTime(this.remainingSeconds); }

  private formatTime(seconds: number): string {
    const m = Math.floor(seconds / 60); const s = seconds % 60;
    return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  }
  private getTodayDate(): string {
    const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
  }
}
