// fix: HUI-048 · T-W01 打卡卡：添加周期刷新定时器 + onFormEvent，DB 查询已有 DEV-003
// <!-- agentID: DEV-010 -->
// <!-- agentID: DEV-003 --> Bug修复：卡片数据源硬编码 0 → 读真实 CheckInDao（读库缺失）
// 文件: CheckInFormAbility.ets
// 任务: T-W01 打卡进度环桌面卡片 FormExtensionAbility
// 关联架构: ARC-001 §3.1 FormExtensionAbility
// Skill 参考：frontend-design / systematic-debugging
// API 验证（本地 API24 .d.ts）：
//   - @kit.FormKit 导出 formInfo/formProvider/formBindingData（kits/@kit.FormKit.d.ts:28）
//   - formInfo.FormParam.IDENTITY_KEY = 'ohos.extra.param.key.form_identity'（@ohos.app.form.formInfo.d.ts:679）
//   - formProvider.updateForm(formId, bindingData): Promise<void>（@ohos.app.form.formProvider.d.ts:191）
//   - formBindingData.createFormBindingData(obj?)（@ohos.app.form.formBindingData.d.ts:56）

import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseHelper, CheckInDao, CheckIn, DateUtils } from '@ohos/shared';

const TAG = 'CheckInFormAbility';
const REFRESH_INTERVAL_MS = 60000;

/**
 * CheckInFormAbility - 2x2 打卡进度环桌面卡片
 * 展示当日打卡状态、连续天数、当月打卡率环形进度
 * DEV-003：卡片进程独立于主应用进程 —— 在本进程内初始化 DatabaseHelper
 * 后经 CheckInDao 读取与主应用同一 RDB（HuaweiDiary.db），
 * 替换原先 onAddForm/onUpdateForm 硬编码全 0 的假数据（打卡卡片恒 0 的根因）。
 * HUI-048：添加 60s 周期刷新 + onFormEvent('message') 即时刷新 + 定时器生命周期管理。
 */
export default class CheckInFormAbility extends FormExtensionAbility {
  private formIds: Set<string> = new Set();
  private refreshTimer: number = -1;

  onCreate(): void {
    hilog.info(0xFF00, TAG, 'CheckInFormAbility onCreate');
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(0xFF00, TAG, 'onAddForm');
    // onAddForm 必须同步返回 → 先回占位数据，随后异步查库 updateForm 刷新
    const parameters = want.parameters ?? {};
    const formIdParam = parameters[formInfo.FormParam.IDENTITY_KEY];
    const formId: string = formIdParam !== undefined ? String(formIdParam) : '';
    if (formId.length > 0) {
      this.formIds.add(formId);
      this.refreshFormData(formId);
      this.ensureRefreshTimer();
    }
    const formData: Record<string, string | number> = {};
    formData['isChecked'] = 0;
    formData['streak'] = 0;
    formData['monthRate'] = 0;
    formData['dateStr'] = DateUtils.today();
    formData['progressText'] = '0/30 0%';
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
    // 'router' 事件由卡片点击触发，仅路由，不更新数据
  }

  onDeleteForm(formId: string): void {
    hilog.info(0xFF00, TAG, 'onDeleteForm: %{public}s', formId);
    this.formIds.delete(formId);
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(0xFF00, TAG, 'onCastToNormalForm: %{public}s', formId);
  }

  onDestroy(): void {
    hilog.info(0xFF00, TAG, 'CheckInFormAbility onDestroy');
    this.clearRefreshTimer();
    this.formIds.clear();
  }

  /**
   * 启动 60s 周期刷新定时器（幂等）。
   */
  private ensureRefreshTimer(): void {
    if (this.refreshTimer !== -1) {
      return;
    }
    this.refreshTimer = setInterval(() => {
      this.formIds.forEach((id: string) => {
        this.refreshFormData(id);
      });
    }, REFRESH_INTERVAL_MS);
    hilog.info(0xFF00, TAG, 'Refresh timer started, interval=%{public}d ms', REFRESH_INTERVAL_MS);
  }

  /**
   * 清除周期刷新定时器。
   */
  private clearRefreshTimer(): void {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
      hilog.info(0xFF00, TAG, 'Refresh timer cleared');
    }
  }

  /**
   * DEV-003：查 CheckInDao 真实数据并推送到卡片。
   * 数据键与 CheckInFormPage 的 @LocalStorageProp 一一对应：
   *   isChecked / streak / monthRate / dateStr / progressText
   */
  private refreshFormData(formId: string): void {
    this.loadCheckInData().then((formData: Record<string, string | number>) => {
      formProvider.updateForm(formId, formBindingData.createFormBindingData(formData))
        .then(() => {
          hilog.info(0xFF00, TAG, 'Form updated successfully: %{public}s', formId);
        })
        .catch((err: Error) => {
          hilog.error(0xFF00, TAG, 'Form update failed: %{public}s', err.message);
        });
    }).catch((err: Error) => {
      hilog.error(0xFF00, TAG, 'loadCheckInData failed: %{public}s', err.message);
    });
  }

  /**
   * 从 RDB 读取今日打卡态 / 连续天数 / 当月打卡率。
   * DatabaseHelper.initialize 幂等（已初始化直接跳过），DAO 内部经 whenReady 门闩等待就绪。
   */
  private async loadCheckInData(): Promise<Record<string, string | number>> {
    await DatabaseHelper.getInstance().initialize(this.context);
    const today: string = DateUtils.today();
    const checked: boolean = await CheckInDao.exists(today);
    const streak: number = await CheckInDao.queryStreak(today);
    const now: Date = new Date();
    const year: number = now.getFullYear();
    const month: number = now.getMonth() + 1;
    const monthRecords: CheckIn[] = await CheckInDao.queryByMonth(year, month);
    const totalDays: number = new Date(year, month, 0).getDate();
    const checkedDays: number = monthRecords.length;
    const monthRate: number = totalDays > 0 ? Math.round((checkedDays / totalDays) * 100) : 0;

    const formData: Record<string, string | number> = {};
    formData['isChecked'] = checked ? 1 : 0;
    formData['streak'] = streak;
    formData['monthRate'] = monthRate;
    formData['dateStr'] = today;
    formData['progressText'] = '' + checkedDays + '/' + totalDays + ' ' + monthRate + '%';
    return formData;
  }
}
