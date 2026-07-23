// <!-- agentID: DEV-004 -->
// File: CheckInViewModel.ets
// Task: T011 Check-in business logic - checkIn/undo/getTodayStatus/getStreakDays
// Architecture: ARC-001 4.1 CheckInDao / 4.5 EventBus / S1 daily check-in
// Skill Ref: frontend-design / ui-ux-pro-max

import { CheckInDao } from '@ohos/shared';
import { EventBus } from '@ohos/shared';
import { CheckIn } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'CheckInViewModel';

/**
 * CheckInViewModel - Manages check-in state and operations.
 * All data access goes through DAO layer (TaskPool-backed).
 * Emits events on state changes for UI auto-refresh.
 */
export class CheckInViewModel {
  private date: string = '';
  private checked: boolean = false;
  private streak: number = 0;

  /**
   * Initialize the view model for a target date.
   * Call this in onPageShow or when the date changes.
   */
  async init(date: string): Promise<void> {
    this.date = date;
    try {
      this.checked = await CheckInDao.exists(date);
      this.streak = await CheckInDao.queryStreak(date);
      // Sync with AppStorage for cross-component access
      AppStorage.setOrCreate('app_checked_today', this.checked ? 1 : 0);
      AppStorage.setOrCreate('app_streak_count', this.streak);
      AppStorage.setOrCreate('currentCheckInDate', this.date);
      AppStorage.setOrCreate('currentStreakDays', this.streak);
      hilog.info(0x0000, TAG, 'Init: date=%{public}s, checked=%{public}s, streak=%{public}d',
        date, String(this.checked), this.streak);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Init failed: %{public}s', error.message);
    }
  }

  /**
   * Perform check-in for the current date.
   * @returns true if check-in succeeded, false if already checked or error.
   */
  async checkIn(): Promise<boolean> {
    try {
      if (this.checked) {
        hilog.warn(0x0000, TAG, 'Already checked in for %{public}s', this.date);
        return false;
      }
      const checkIn = new CheckIn(this.date);
      const rowId = await CheckInDao.insert(checkIn);
      if (rowId > 0) {
        this.checked = true;
        this.streak = await CheckInDao.queryStreak(this.date);
        // Update AppStorage
        AppStorage.setOrCreate('app_checked_today', 1);
        AppStorage.setOrCreate('app_streak_count', this.streak);
        // Emit event for UI refresh (flat payload; EventBus wraps internally)
        AppStorage.setOrCreate('currentCheckInDate', this.date);
        AppStorage.setOrCreate('currentStreakDays', this.streak);
        const checkInPayload: Record<string, Object> = {};
        checkInPayload['date'] = this.date;
        checkInPayload['isChecked'] = true;
        checkInPayload['streakDays'] = this.streak;
        EventBus.emit(EventBus.EventNames.CHECKIN_CHANGED, checkInPayload);
        hilog.info(0x0000, TAG, 'Check-in success: date=%{public}s, streak=%{public}d',
          this.date, this.streak);
        return true;
      }
      return false;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'CheckIn failed: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Undo a check-in (remove today's check-in record).
   * Only allowed within a configurable time window (e.g., 5 minutes).
   */
  async undo(): Promise<boolean> {
    try {
      if (!this.checked) {
        hilog.warn(0x0000, TAG, 'Not checked in, cannot undo');
        return false;
      }
      // Delete the check-in record from DB (B00: CheckInDao.deleteByDate)
      const deletedRows = await CheckInDao.deleteByDate(this.date);
      if (deletedRows <= 0) {
        hilog.warn(0x0000, TAG, 'No rows deleted for date=%{public}s', this.date);
        return false;
      }
      this.checked = false;
      this.streak = await CheckInDao.queryStreak(this.date);
      AppStorage.setOrCreate('app_checked_today', 0);
      AppStorage.setOrCreate('app_streak_count', this.streak);
      AppStorage.setOrCreate('currentCheckInDate', this.date);
      AppStorage.setOrCreate('currentStreakDays', this.streak);
      const checkInPayload: Record<string, Object> = {};
      checkInPayload['date'] = this.date;
      checkInPayload['isChecked'] = false;
      checkInPayload['streakDays'] = this.streak;
      EventBus.emit(EventBus.EventNames.CHECKIN_CHANGED, checkInPayload);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Undo failed: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Get today's check-in status.
   */
  getTodayStatus(): boolean {
    return this.checked;
  }

  /**
   * Get the current streak day count.
   */
  getStreakDays(): number {
    return this.streak;
  }

  /**
   * Get the current target date.
   */
  getDate(): string {
    return this.date;
  }

  /**
   * Query the list of checked-in dates for a given month (for calendar marking).
   * Delegates to CheckInDao.queryByMonth (returns CheckIn[]) and maps to date strings.
   * @param year Full year, e.g. 2026.
   * @param month Month 1-12.
   * @returns Promise<string[]> Checked-in dates "YYYY-MM-DD" for that month.
   */
  async queryByMonth(year: number, month: number): Promise<string[]> {
    try {
      const records = await CheckInDao.queryByMonth(year, month);
      const dates: string[] = records.map((c: CheckIn) => c.date);
      hilog.info(0x0000, TAG, 'queryByMonth: year=%{public}d, month=%{public}d, count=%{public}d',
        year, month, dates.length);
      return dates;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'queryByMonth failed: %{public}s', error.message);
      return [];
    }
  }

  /**
   * Refresh check-in state (call in onPageShow for double-guarantee strategy).
   */
  async refresh(): Promise<void> {
    if (this.date.length > 0) {
      await this.init(this.date);
    }
  }
}
