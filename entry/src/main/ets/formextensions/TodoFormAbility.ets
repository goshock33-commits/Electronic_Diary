// fix: HUI-048 · T-W01 待办卡：接入 TodoDao 真实数据，替换硬编码空数组
// <!-- agentID: DEV-010 -->
// <!-- agentID: HUI-048 --> T-W01：onAddForm/onUpdateForm 原只传占位值 → 查 TodoDao 灌真实待办
// 文件: TodoFormAbility.ets
// 任务: T-W01 待办清单桌面卡片 FormExtensionAbility
// 关联架构: ARC-001 §3.1 FormExtensionAbility
// Skill 参考：frontend-design

import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DatabaseHelper, TodoDao, TodoItem, DateUtils } from '@ohos/shared';
import { relationalStore } from '@kit.ArkData';

const TAG = 'TodoFormAbility';
const REFRESH_INTERVAL_MS = 60000;

/**
 * TodoFormAbility - 2x4 待办清单桌面卡片
 * 展示今日待办前 N 条，每条显示标题和完成状态。
 * HUI-048：onAddForm/onUpdateForm 改为查 TodoDao.queryByDateAndType(today, 'today')
 * 获取真实待办列表，序列化为 JSON 字符串传 FormPage。
 * FormPage 键：dateStr / totalCount / completedCount / todos
 */
export default class TodoFormAbility extends FormExtensionAbility {
  private formIds: Set<string> = new Set();
  private refreshTimer: number = -1;

  onCreate(): void {
    hilog.info(0xFF00, TAG, 'TodoFormAbility onCreate');
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(0xFF00, TAG, 'onAddForm');
    const parameters = want.parameters ?? {};
    const formIdParam = parameters[formInfo.FormParam.IDENTITY_KEY];
    const formId: string = formIdParam !== undefined ? String(formIdParam) : '';
    // fix: MAIN-001 · 同步查库返回真实数据——onAddForm 必须同步返回 formBindingData，
    // 而 DatabaseHelper + TodoDao 已支持同步回调（async/await 在 onAddForm 同步返回限制下
    // 无法使用）。FormAbility 与主应用同进程同 RDB，store 共享，直接用同步 API 读取。
    const formData: Record<string, string | number> = this.loadTodoDataSync();
    if (formId.length > 0) {
      this.formIds.add(formId);
      // 异步刷新兜底：60s 后重查最新数据（异步路径用于后续周期性更新）
      this.ensureRefreshTimer();
    }
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
    // fix: MAIN-001 · 点击卡片路由：postCardAction(this, {action:'router', uri:'pages/TodoPage'})
    // 系统自动处理 URI 跳转到目标页，FormAbility 收到 'router' message 不额外处理
  }

  onDeleteForm(formId: string): void {
    hilog.info(0xFF00, TAG, 'onDeleteForm: %{public}s', formId);
    this.formIds.delete(formId);
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(0xFF00, TAG, 'onCastToNormalForm: %{public}s', formId);
  }

  onDestroy(): void {
    hilog.info(0xFF00, TAG, 'TodoFormAbility onDestroy');
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
   * fix: MAIN-001 · 同步版：在 onAddForm 中调用，免去"先占位→异步回填→卡片不刷新"的路径。
   * 使用 RDB store 的 querySqlSync（API 24 可用）直接读取今日待办。
   * DatabaseHelper 与主应用同实例、同存储，FormAbility 调用时 DB 应已由 StartupTasks 初始化完毕。
   */
  private loadTodoDataSync(): Record<string, string | number> {
    const today: string = DateUtils.today();
    const formData: Record<string, string | number> = {};
    formData['dateStr'] = today;
    formData['totalCount'] = 0;
    formData['completedCount'] = 0;
    formData['todos'] = '[]';
    try {
      const helper = DatabaseHelper.getInstance();
      const store = helper.getStore();
      const sql = "SELECT id, title, completed, date, type FROM todo WHERE type = 'today' AND date = ? ORDER BY sort_order ASC";
      const resultSet = store.querySqlSync(sql, [today]);
      const items: Record<string, number | string>[] = [];
      let completedCount = 0;
      while (resultSet.goToNextRow()) {
        const completed: number = resultSet.getLong(resultSet.getColumnIndex('completed'));
        const item: Record<string, number | string> = {};
        item['id'] = resultSet.getLong(resultSet.getColumnIndex('id'));
        item['title'] = resultSet.getString(resultSet.getColumnIndex('title'));
        item['isCompleted'] = completed;
        item['type'] = resultSet.getString(resultSet.getColumnIndex('type'));
        items.push(item);
        if (completed === 1) {
          completedCount = completedCount + 1;
        }
      }
      resultSet.close();
      formData['totalCount'] = items.length;
      formData['completedCount'] = completedCount;
      formData['todos'] = JSON.stringify(items);
    } catch (e) {
      hilog.error(0xFF00, TAG, 'loadTodoDataSync failed: %{public}s', (e as BusinessError).message);
    }
    return formData;
  }

  /**
   * 查 TodoDao 获取今日待办 → 推送 FormPage。
   */
  private refreshFormData(formId: string): void {
    this.loadTodoData().then((formData: Record<string, string | number>) => {
      formProvider.updateForm(formId, formBindingData.createFormBindingData(formData))
        .then(() => {
          hilog.info(0xFF00, TAG, 'Todo form updated: %{public}s', formId);
        })
        .catch((err: Error) => {
          hilog.error(0xFF00, TAG, 'Todo update failed: %{public}s', err.message);
        });
    }).catch((err: Error) => {
      hilog.error(0xFF00, TAG, 'loadTodoData failed: %{public}s', err.message);
    });
  }

  /**
   * 从 RDB 读取今日待办列表，统计完成/总数，序列化为 JSON 字符串。
   * DB 空表时 totalCount=0, completedCount=0, todos='[]'（卡片不白屏）。
   */
  private async loadTodoData(): Promise<Record<string, string | number>> {
    await DatabaseHelper.getInstance().initialize(this.context);
    const today: string = DateUtils.today();
    const todos: TodoItem[] = await TodoDao.queryByDateAndType(today, 'today');

    const totalCount: number = todos.length;
    let completedCount: number = 0;
    const items: Record<string, number | string>[] = [];
    for (let i = 0; i < todos.length; i++) {
      const t: TodoItem = todos[i];
      if (t.completed === 1) {
        completedCount = completedCount + 1;
      }
      // 映射 TodoItem.completed → TodoFormItem.isCompleted（FormPage interface 专用键名）
      const fi: Record<string, number | string> = {};
      fi['id'] = t.id;
      fi['title'] = t.title;
      fi['isCompleted'] = t.completed;
      fi['type'] = t.type;
      items.push(fi);
    }

    const formData: Record<string, string | number> = {};
    formData['dateStr'] = today;
    formData['totalCount'] = totalCount;
    formData['completedCount'] = completedCount;
    formData['todos'] = JSON.stringify(items);
    return formData;
  }
}
