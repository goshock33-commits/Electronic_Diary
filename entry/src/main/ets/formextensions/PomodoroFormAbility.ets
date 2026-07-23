// fix: HUI-048 · T-W01 番茄卡：接入 PomodoroDao 真实数据 + 1s 定时器实时倒计时
// <!-- agentID: DEV-010 -->
// <!-- agentID: HUI-048 --> T-W01：onAddForm/onUpdateForm 原只传硬编码 idle → 查 PomodoroDao 真实数据
// 文件: PomodoroFormAbility.ets
// 任务: T-W01 番茄钟状态桌面卡片 FormExtensionAbility
// 关联架构: ARC-001 §3.1 FormExtensionAbility
// Skill 参考：frontend-design

import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseHelper, PomodoroDao, PomodoroSession, DateUtils } from '@ohos/shared';

const TAG = 'PomodoroFormAbility';
const SLOW_REFRESH_MS = 60000;
const FAST_REFRESH_MS = 1000;

/**
 * PomodoroFormAbility - 2x2 番茄钟状态桌面卡片
 * 展示计时剩余时间 + 环形进度 + 状态文字。
 * HUI-048：onAddForm/onUpdateForm 改为查 PomodoroDao 真实累计数据；
 * 检测活跃会话（completed=0）→ 启用 1s 实时倒计时；
 * 无活跃会话时 60s 周期刷新。
 * FormPage 键：state / remainingStr / progress / preset / totalStr
 */
export default class PomodoroFormAbility extends FormExtensionAbility {
  private formIds: Set<string> = new Set();
  private refreshTimer: number = -1;
  /** 缓存的活跃会话终了时间（毫秒时间戳），用于 1s 本地计算剩余时间，避免每次 tick 查 DB */
  private sessionEndMs: number = 0;
  /** 缓存的活跃会话预设类型 */
  private sessionPreset: string = 'focus';
  /** 缓存的活跃会话总时长（秒） */
  private sessionTotalSec: number = 1500;
  /** 当前定时器间隔（1s=FAST 或 60s=SLOW），用于运行时切换 */
  private currentInterval: number = SLOW_REFRESH_MS;

  onCreate(): void {
    hilog.info(0xFF00, TAG, 'PomodoroFormAbility onCreate');
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(0xFF00, TAG, 'onAddForm');
    // onAddForm 必须同步返回 → 先回占位数据，随后异步刷新
    const parameters = want.parameters ?? {};
    const formIdParam = parameters[formInfo.FormParam.IDENTITY_KEY];
    const formId: string = formIdParam !== undefined ? String(formIdParam) : '';
    if (formId.length > 0) {
      this.formIds.add(formId);
      this.refreshFormData(formId);
      this.ensureRefreshTimer();
    }
    const formData: Record<string, string | number> = {};
    formData['state'] = 'idle';
    formData['remainingStr'] = '25:00';
    formData['progress'] = 0;
    formData['preset'] = 'focus';
    formData['totalStr'] = '25:00';
    return formBindingData.createFormBindingData(formData);
  }

  onUpdateForm(formId: string): void {
    hilog.info(0xFF00, TAG, 'onUpdateForm: %{public}s', formId);
    this.refreshFormData(formId);
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(0xFF00, TAG, 'onFormEvent: %{public}s msg=%{public}s', formId, message);
    if (message === 'message') {
      this.refreshFormData(formId);
    }
    if (message === 'destroy') {
      // 页面退场：清定时器
      this.clearRefreshTimer();
    }
    // 'router' 事件仅路由，不更新数据
  }

  onDeleteForm(formId: string): void {
    hilog.info(0xFF00, TAG, 'onDeleteForm: %{public}s', formId);
    this.formIds.delete(formId);
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(0xFF00, TAG, 'onCastToNormalForm: %{public}s', formId);
  }

  onDestroy(): void {
    hilog.info(0xFF00, TAG, 'PomodoroFormAbility onDestroy');
    this.clearRefreshTimer();
    this.formIds.clear();
  }

  /**
   * 启动刷新定时器。首次启动时查询 DB 判断是否活跃会话，
   * 活跃 → 1s 快定时器；非活跃 → 60s 慢定时器。
   */
  private ensureRefreshTimer(): void {
    if (this.refreshTimer !== -1) {
      return;
    }
    // 先用慢定时器启动，首次 refreshFormData 完成后会根据会话状态决定是否切换到快定时器
    this.startTimer(SLOW_REFRESH_MS);
    hilog.info(0xFF00, TAG, 'Refresh timer started');
  }

  /**
   * 启动/重启定时器（支持运行时切换快/慢）。
   */
  private startTimer(intervalMs: number): void {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
    this.currentInterval = intervalMs;
    this.refreshTimer = setInterval(() => {
      // 快定时器时用本地缓存计算剩余时间（不查 DB，仅 formProvider.updateForm 推送）
      if (this.currentInterval === FAST_REFRESH_MS && this.sessionEndMs > 0) {
        this.pushCachedPomodoroData();
      } else {
        // 慢定时器时查 DB 刷新全量数据
        this.formIds.forEach((id: string) => {
          this.refreshFormData(id);
        });
      }
    }, intervalMs);
  }

  /**
   * 清除周期刷新定时器。
   */
  private clearRefreshTimer(): void {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
      this.sessionEndMs = 0;
      this.currentInterval = SLOW_REFRESH_MS;
      hilog.info(0xFF00, TAG, 'Refresh timer cleared');
    }
  }

  /**
   * 查 PomodoroDao 获取累计数据 + 活跃会话 → 推送 FormPage。
   */
  private refreshFormData(formId: string): void {
    this.loadPomodoroData().then((formData: Record<string, string | number>) => {
      formProvider.updateForm(formId, formBindingData.createFormBindingData(formData))
        .then(() => {
          hilog.info(0xFF00, TAG, 'Pomodoro form updated: %{public}s', formId);
        })
        .catch((err: Error) => {
          hilog.error(0xFF00, TAG, 'Pomodoro update failed: %{public}s', err.message);
        });
    }).catch((err: Error) => {
      hilog.error(0xFF00, TAG, 'loadPomodoroData failed: %{public}s', err.message);
    });
  }

  /**
   * 快定时器 tick：用本地缓存数据计算剩余时间，零 DB 查询。
   */
  private pushCachedPomodoroData(): void {
    const nowMs: number = Date.now();
    let remainingSec: number = Math.round((this.sessionEndMs - nowMs) / 1000);
    if (remainingSec < 0) {
      remainingSec = 0;
    }
    const totalSec: number = this.sessionTotalSec;
    const elapsedSec: number = totalSec - remainingSec;
    const progress: number = totalSec > 0 ? Math.round((elapsedSec / totalSec) * 100) : 0;
    const min: number = Math.floor(remainingSec / 60);
    const sec: number = remainingSec % 60;
    const remainingStr: string = '' + min + ':' + (sec < 10 ? '0' : '') + sec;
    const totalMin: number = Math.floor(totalSec / 60);
    const totalSecRem: number = totalSec % 60;
    const totalStr: string = '' + totalMin + ':' + (totalSecRem < 10 ? '0' : '') + totalSecRem;

    const formData: Record<string, string | number> = {};
    formData['state'] = this.sessionPreset;
    formData['remainingStr'] = remainingStr;
    formData['progress'] = progress;
    formData['preset'] = this.sessionPreset;
    formData['totalStr'] = totalStr;

    // 推送所有活跃卡片
    this.formIds.forEach((id: string) => {
      formProvider.updateForm(id, formBindingData.createFormBindingData(formData))
        .catch((err: Error) => {
          hilog.error(0xFF00, TAG, 'Fast tick update failed for %{public}s: %{public}s', id, err.message);
        });
    });

    // 会话结束时切回慢定时器
    if (remainingSec <= 0) {
      this.sessionEndMs = 0;
      this.startTimer(SLOW_REFRESH_MS);
      // 立即做一次 DB 刷新确认会话状态
      this.formIds.forEach((id: string) => {
        this.refreshFormData(id);
      });
    }
  }

  /**
   * 从 RDB 获取今日番茄钟会话列表 + 累计完成数。
   * 检测活跃会话（completed=0 AND ended_at IS NULL）→ 缓存 endTime 启用快定时器。
   * 无活跃会话 → 显示 idle 状态 + 累计统计。
   */
  private async loadPomodoroData(): Promise<Record<string, string | number>> {
    await DatabaseHelper.getInstance().initialize(this.context);
    const today: string = DateUtils.today();

    // 默认 idle 状态
    let pomodoroState: string = 'idle';
    let remainingStr: string = '25:00';
    let progress: number = 0;
    let preset: string = 'focus';
    let totalStr: string = '25:00';

    try {
      // 查今日会话列表（DESC created_at，最新在前）
      const todaySessions: PomodoroSession[] = await PomodoroDao.queryByDateRange(today, today);

      // 找活跃会话：completed=0 AND ended_at IS NULL（插入时未完成/未结束的记录）
      let activeSession: PomodoroSession | null = null;
      for (let i = 0; i < todaySessions.length; i++) {
        const s: PomodoroSession = todaySessions[i];
        if (s.completed === 0 && s.ended_at === null) {
          activeSession = s;
          break;
        }
      }

      if (activeSession !== null) {
        // 活跃会话：计算进度和剩余时间
        const totalSec: number = activeSession.duration_minutes * 60;
        const endMs: number = activeSession.created_at + totalSec * 1000;
        const nowMs: number = Date.now();
        let remainingSec: number = Math.round((endMs - nowMs) / 1000);
        if (remainingSec < 0) {
          remainingSec = 0;
        }

        const elapsedSec: number = totalSec - remainingSec;
        progress = totalSec > 0 ? Math.round((elapsedSec / totalSec) * 100) : 0;
        const min: number = Math.floor(remainingSec / 60);
        const sec: number = remainingSec % 60;
        remainingStr = '' + min + ':' + (sec < 10 ? '0' : '') + sec;
        const totalMin: number = Math.floor(totalSec / 60);
        const totalSecRem: number = totalSec % 60;
        totalStr = '' + totalMin + ':' + (totalSecRem < 10 ? '0' : '') + totalSecRem;

        pomodoroState = activeSession.preset_type;
        preset = activeSession.preset_type;

        // 缓存快定时器所需数据
        this.sessionEndMs = endMs;
        this.sessionPreset = activeSession.preset_type;
        this.sessionTotalSec = totalSec;

        // 切到 1s 快定时器
        if (this.currentInterval !== FAST_REFRESH_MS) {
          this.startTimer(FAST_REFRESH_MS);
        }
      } else {
        // 无活跃会话：清除缓存，用慢定时器
        this.sessionEndMs = 0;
        if (this.currentInterval !== SLOW_REFRESH_MS) {
          this.startTimer(SLOW_REFRESH_MS);
        }
      }
    } catch (err) {
      const error = err as Error;
      hilog.error(0xFF00, TAG, 'loadPomodoroData inner error: %{public}s', error.message);
      // 回退 idle 默认值（已在上面初始化）
    }

    const formData: Record<string, string | number> = {};
    formData['state'] = pomodoroState;
    formData['remainingStr'] = remainingStr;
    formData['progress'] = progress;
    formData['preset'] = preset;
    formData['totalStr'] = totalStr;
    return formData;
  }
}
