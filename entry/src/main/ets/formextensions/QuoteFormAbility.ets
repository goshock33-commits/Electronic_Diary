// fix: HUI-048 · T-W01 名言卡：接入 QuoteDao 真实数据，确定性每日偏移选取
// <!-- agentID: DEV-010 -->
// <!-- agentID: HUI-048 --> T-W01：onAddForm/onUpdateForm 原只传硬编码占位名言 → 查 QuoteDao 真实数据
// 文件: QuoteFormAbility.ets
// 任务: T-W01 每日一言桌面卡片 FormExtensionAbility
// 关联架构: ARC-001 §3.1 FormExtensionAbility
// Skill 参考：frontend-design

import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseHelper, QuoteDao, Quote, DateUtils } from '@ohos/shared';
import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'QuoteFormAbility';

/**
 * QuoteFormAbility - 2x2 每日一言桌面卡片
 * 展示今日名言正文 + 作者。
 * HUI-048：onAddForm/onUpdateForm 改为查 QuoteDao.getByOffset(日期偏移)
 * 确定性每日选取（同日同偏移 → 同一句），DB 空/异常时回退占位文本。
 * FormPage 键：quoteText / quoteAuthor / dateStr
 */
export default class QuoteFormAbility extends FormExtensionAbility {

  onCreate(): void {
    hilog.info(0xFF00, TAG, 'QuoteFormAbility onCreate');
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(0xFF00, TAG, 'onAddForm');
    const formData: Record<string, string | number> = this.loadQuoteDataSync();
    return formBindingData.createFormBindingData(formData);
  }

  onUpdateForm(formId: string): void {
    hilog.info(0xFF00, TAG, 'onUpdateForm: %{public}s', formId);
    this.refreshFormData(formId);
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(0xFF00, TAG, 'onFormEvent: %{public}s msg=%{public}s', formId, message);
    if (message === 'refresh') {
      this.refreshFormWithRandom(formId);
    }
  }

  onDeleteForm(formId: string): void {
    hilog.info(0xFF00, TAG, 'onDeleteForm: %{public}s', formId);
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(0xFF00, TAG, 'onCastToNormalForm: %{public}s', formId);
  }

  onDestroy(): void {
    hilog.info(0xFF00, TAG, 'QuoteFormAbility onDestroy');
  }

  /**
   * 手动刷新（onFormEvent 'refresh'）：随机选取一条今日未展示过的名言。
   */
  private refreshFormWithRandom(formId: string): void {
    this.loadRandomQuoteData().then((formData: Record<string, string | number>) => {
      formProvider.updateForm(formId, formBindingData.createFormBindingData(formData))
        .then(() => {
          hilog.info(0xFF00, TAG, 'Quote form (random) updated: %{public}s', formId);
        })
        .catch((err: Error) => {
          hilog.error(0xFF00, TAG, 'Quote update (random) failed: %{public}s', err.message);
        });
    }).catch((err: Error) => {
      hilog.error(0xFF00, TAG, 'loadRandomQuoteData failed: %{public}s', err.message);
    });
  }

  /**
   * 随机选取一条名言（排除今日已展示），用于手动刷新按钮。
   */
  private async loadRandomQuoteData(): Promise<Record<string, string | number>> {
    await DatabaseHelper.getInstance().initialize(this.context);
    const today: string = DateUtils.today();
    let quoteText: string = '每一天都是新的开始';
    let quoteAuthor: string = '—— 佚名';

    try {
      const quote: Quote | null = await QuoteDao.random(today);
      if (quote !== null) {
        quoteText = quote.content;
        const authorRaw: string = quote.author.length > 0 ? quote.author : '佚名';
        quoteAuthor = '—— ' + authorRaw;
        await QuoteDao.markShown(quote.id, today);
      }
    } catch (err) {
      const error = err as Error;
      hilog.error(0xFF00, TAG, 'loadRandomQuoteData error: %{public}s', error.message);
    }

    const formData: Record<string, string | number> = {};
    formData['quoteText'] = quoteText;
    formData['quoteAuthor'] = quoteAuthor;
    formData['dateStr'] = today;
    return formData;
  }

  /**
   * fix: MAIN-001 · 同步版：在 onAddForm 中调用，免去"先占位→异步回填→卡片不刷新"的路径。
   * 使用 RDB store 的 querySqlSync（API 24 可用）直接读取每日名言。
   * 日期偏移: 当天是当年第 N 天 → offset = N % total → 确定性每日一句话。
   */
  private loadQuoteDataSync(): Record<string, string | number> {
    const today: string = DateUtils.today();
    const formData: Record<string, string | number> = {};
    formData['quoteText'] = '每一天都是新的开始';
    formData['quoteAuthor'] = '—— 佚名';
    formData['dateStr'] = today;
    try {
      const helper = DatabaseHelper.getInstance();
      const store = helper.getStore();
      // 取总条数
      const countRs = store.querySqlSync("SELECT COUNT(*) as cnt FROM quote");
      let totalCount = 0;
      if (countRs.goToFirstRow()) {
        totalCount = countRs.getLong(countRs.getColumnIndex('cnt'));
      }
      countRs.close();
      if (totalCount > 0) {
        // 日期 → 当年第 N 天
        const now = new Date();
        const yearStart = new Date(now.getFullYear(), 0, 1);
        const dayOfYear: number = Math.floor((now.getTime() - yearStart.getTime()) / 86400000);
        const offset: number = dayOfYear % totalCount;
        const quoteRs = store.querySqlSync("SELECT content, author FROM quote ORDER BY id ASC LIMIT 1 OFFSET " + offset.toString());
        if (quoteRs.goToFirstRow()) {
          formData['quoteText'] = quoteRs.getString(quoteRs.getColumnIndex('content'));
          const author: string = quoteRs.getString(quoteRs.getColumnIndex('author'));
          formData['quoteAuthor'] = author.length > 0 ? '—— ' + author : '';
        }
        quoteRs.close();
      }
    } catch (e) {
      hilog.error(0xFF00, TAG, 'loadQuoteDataSync failed: %{public}s', (e as BusinessError).message);
    }
    return formData;
  }

  /**
   * 查 QuoteDao 用日期偏移取每日名言 → 推送 FormPage。
   */
  private refreshFormData(formId: string): void {
    this.loadQuoteData().then((formData: Record<string, string | number>) => {
      formProvider.updateForm(formId, formBindingData.createFormBindingData(formData))
        .then(() => {
          hilog.info(0xFF00, TAG, 'Quote form updated: %{public}s', formId);
        })
        .catch((err: Error) => {
          hilog.error(0xFF00, TAG, 'Quote update failed: %{public}s', err.message);
        });
    }).catch((err: Error) => {
      hilog.error(0xFF00, TAG, 'loadQuoteData failed: %{public}s', err.message);
    });
  }

  /**
   * 从 RDB 确定性获取每日名言：日期 → 当年第 N 天 → offset = N % totalCount → getByOffset(offset)。
   * DB 空（未灌入种子）或 getByOffset 返回 null 时回退占位文本，卡片不白屏。
   */
  private async loadQuoteData(): Promise<Record<string, string | number>> {
    await DatabaseHelper.getInstance().initialize(this.context);
    const today: string = DateUtils.today();
    let quoteText: string = '每一天都是新的开始';
    let quoteAuthor: string = '—— 佚名';

    try {
      const totalCount: number = await QuoteDao.count();
      if (totalCount > 0) {
        // 计算当年第几天作为确定性偏移（同日同偏移 → 同一句）
        const now: Date = new Date();
        const yearStart: Date = new Date(now.getFullYear(), 0, 1);
        const dayOfYear: number = Math.floor((now.getTime() - yearStart.getTime()) / 86400000);
        const offset: number = dayOfYear % totalCount;
        const quote: Quote | null = await QuoteDao.getByOffset(offset);
        if (quote !== null) {
          quoteText = quote.content;
          // 作者署名为空时用默认署名
          const authorRaw: string = quote.author.length > 0 ? quote.author : '佚名';
          quoteAuthor = '—— ' + authorRaw; // '—— '
        }
      }
    } catch (err) {
      const error = err as Error;
      hilog.error(0xFF00, TAG, 'loadQuoteData inner error: %{public}s', error.message);
      // 回退占位文本（已在上面初始化为占位值）
    }

    const formData: Record<string, string | number> = {};
    formData['quoteText'] = quoteText;
    formData['quoteAuthor'] = quoteAuthor;
    formData['dateStr'] = today;
    return formData;
  }
}
