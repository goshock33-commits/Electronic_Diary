// <!-- agentID: DEV-001 -->
// File: SearchViewModel.ets
// Task: T019b Search business logic - cross 4 data source full-text search + source type marking
// Architecture: ARC-001 4.1 DAO APIs / S2 keyword search
// Fixes (M18 refine): data:Object -> typed union (R-ArkTS), history persistence completed (R-persist),
//   AppStorage write (R0-3), EventBus flat payload + EventNames (R0-2), B00 try-catch/BusinessError
// fix: DEV-025 · 接入 GlobalSearchService 真实 FTS5 搜索（混合方案：diary/todo 用 FTS5，其他保留 Dao）
// Skill Ref: frontend-design / ui-ux-pro-max

import { DiaryDao } from '@ohos/shared';
import { TodoDao } from '@ohos/shared';
import { HappyThingDao } from '@ohos/shared';
import { ExtraThingDao } from '@ohos/shared';
import { ExtractedTaskDao } from '@ohos/shared';
import { Diary } from '@ohos/shared';
import { TodoItem } from '@ohos/shared';
import { HappyThing } from '@ohos/shared';
import { ExtraThing } from '@ohos/shared';
import { ExtractedTask } from '@ohos/shared';
import { FamilyMember } from '@ohos/shared';
import { EventBus } from '@ohos/shared';
import { GlobalSearchService } from '@ohos/shared';
import { DatabaseHelper } from '@ohos/shared';
import type { SearchResult as GlobalSearchResult } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';

const TAG = 'SearchViewModel';

/**
 * Source type identifiers for search results.
 */
export enum SearchSourceType {
  DIARY = 'diary',
  TODO = 'todo',
  HAPPY = 'happy',
  EXTRA = 'extra',
  EXTRACTED = 'extracted'
}

/**
 * Union of all original entity types a search result may wrap.
 * Replaces `data: Object` (ArkTS strict-mode violation) with an explicit type.
 */
export type SearchResultData = Diary | TodoItem | HappyThing | ExtraThing | ExtractedTask | FamilyMember;

/**
 * Unified search result item.
 */
export interface SearchResult {
  /** Unique identifier */
  id: string;
  /** Source type */
  sourceType: SearchSourceType;
  /** Display title */
  title: string;
  /** Preview content snippet */
  snippet: string;
  /** Associated date */
  date: string;
  /** Original data object (typed union, not Object) */
  data: SearchResultData;
}

/** Maximum search history entries */
const MAX_HISTORY = 5;
/** Preferences store name */
const PREF_STORE = 'search_prefs';
/** Preferences key for history array (JSON string) */
const HISTORY_PREF_KEY = 'search_history';

/**
 * SearchViewModel - Unified search across 4 data sources.
 * Searches: diary content, todo titles, happy things content, extra things content.
 * Results are aggregated and marked with source type for UI rendering.
 */
export class SearchViewModel {
  private results: SearchResult[] = [];
  private history: string[] = [];
  private currentQuery: string = '';
  /** Retained context for history persistence (set in init). */
  private context: Context | null = null;

  /**
   * Initialize - load search history from preferences.
   * Retains the context so addToHistory/clearHistory can persist consistently.
   */
  async init(context: Context): Promise<void> {
    this.context = context;
    try {
      const pref = await preferences.getPreferences(context, PREF_STORE);
      const histStr = await pref.get(HISTORY_PREF_KEY, '[]') as string;
      this.history = JSON.parse(histStr) as string[];
      hilog.info(0x0000, TAG, 'Init: loaded history count=%{public}d', this.history.length);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Init failed: %{public}s', error.message);
      this.history = [];
    }
  }

  /**
   * Execute a cross-source search.
   * DEV-025: 混合方案 - diary/todo 使用 GlobalSearchService (FTS5)，其他源保留 Dao 查询。
   *
   * @param keyword Search keyword.
   * @returns Aggregated search results marked with source types.
   */
  async search(keyword: string): Promise<SearchResult[]> {
    if (!keyword || keyword.trim().length === 0) {
      this.results = [];
      AppStorage.setOrCreate('searchResults', this.results);
      return [];
    }
    this.currentQuery = keyword.trim();

    try {
      // 调试：查询 FTS5 表数据量
      try {
        const store = DatabaseHelper.getInstance().getStore();
        const countSql = 'SELECT COUNT(*) as count FROM fts_search';
        const result = await store.querySql(countSql, []);
        if (result.goToNextRow()) {
          const count = result.getLong(0);
          hilog.info(0x0000, TAG, '🔍 FTS5 table has %{public}d rows', count);
        }
        result.close();
      } catch (err) {
        hilog.warn(0x0000, TAG, '🔍 FTS5 table query failed: %{public}s', (err as Error).message);
      }

      // DEV-025: 并行查询 - GlobalSearchService (FTS5: diary/todo/member) + Dao (happy/extra/extracted)
      const queryResults = await Promise.all([
        GlobalSearchService.search(this.currentQuery),
        HappyThingDao.searchByContent(this.currentQuery),
        ExtraThingDao.searchByContent(this.currentQuery),
        ExtractedTaskDao.searchByTitle(this.currentQuery)
      ]);
      const globalResults = queryResults[0];
      const happyResults = queryResults[1];
      const extraResults = queryResults[2];
      const extractedResults = queryResults[3];

      // Aggregate results with source type marking
      const allResults: SearchResult[] = [];

      // DEV-025: 转换 GlobalSearchService 结果 (diary/todo/member)
      for (const item of globalResults) {
        const converted = SearchViewModel.convertGlobalSearchResult(item);
        if (converted) {
          allResults.push(converted);
        }
      }

      // 保留原有 Dao 查询结果 (happy/extra/extracted)
      for (const happy of happyResults) {
        allResults.push({
          id: `happy_${happy.id}`,
          sourceType: SearchSourceType.HAPPY,
          title: `${happy.emoji_id} ${SearchViewModel.truncate(happy.content, 40)}`,
          snippet: happy.content,
          date: happy.date,
          data: happy
        });
      }

      for (const extra of extraResults) {
        allResults.push({
          id: `extra_${extra.id}`,
          sourceType: SearchSourceType.EXTRA,
          title: SearchViewModel.truncate(extra.content, 40),
          snippet: extra.content,
          date: extra.date,
          data: extra
        });
      }

      for (const task of extractedResults) {
        allResults.push({
          id: `extracted_${task.id}`,
          sourceType: SearchSourceType.EXTRACTED,
          title: task.title,
          snippet: task.description ?? `来源: ${task.source}`,
          date: task.task_date ?? '',
          data: task
        });
      }

      // Sort by date descending (most recent first)
      allResults.sort((a: SearchResult, b: SearchResult): number => {
        if (a.date > b.date) { return -1; }
        if (a.date < b.date) { return 1; }
        return 0;
      });

      this.results = allResults;
      // AppStorage: sync results to UI consumers (R0-3 fix)
      AppStorage.setOrCreate('searchResults', this.results);
      await this.addToHistory(this.currentQuery);

      // EventBus: flat payload per B01 unified string API
      const searchPayload: Record<string, Object> = {};
      searchPayload['keyword'] = this.currentQuery;
      searchPayload['resultCount'] = allResults.length;
      EventBus.emit(EventBus.EventNames.SEARCH_EXECUTED, searchPayload);

      hilog.info(0x0000, TAG, 'Search (FTS5+Dao): query=%{public}s, results=%{public}d',
        this.currentQuery, allResults.length);
      return allResults;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Search failed: %{public}s', error.message);
      return [];
    }
  }

  /**
   * DEV-025: 转换 GlobalSearchService.SearchResult → SearchViewModel.SearchResult
   *
   * @param item GlobalSearchService 返回的搜索结果
   * @returns 转换后的 SearchViewModel.SearchResult，无法转换时返回 null
   */
  private static convertGlobalSearchResult(item: GlobalSearchResult): SearchResult | null {
    if (item.type === 'diary') {
      const diary = item.data as Diary;
      return {
        id: `diary_${diary.id}`,
        sourceType: SearchSourceType.DIARY,
        title: `日记 - ${diary.date}`,
        snippet: SearchViewModel.truncate(diary.content, 80),
        date: diary.date,
        data: diary
      };
    } else if (item.type === 'todo') {
      const todo = item.data as TodoItem;
      return {
        id: `todo_${todo.id}`,
        sourceType: SearchSourceType.TODO,
        title: todo.title,
        snippet: todo.completed === 1 ? '[已完成]' : '[未完成]',
        date: todo.date,
        data: todo
      };
    } else if (item.type === 'member') {
      const member = item.data as FamilyMember;
      return {
        id: `member_${member.id}`,
        sourceType: SearchSourceType.EXTRA,
        title: member.nickname ?? '未命名成员',
        snippet: member.role ?? '',
        date: member.created_at ? new Date(member.created_at).toISOString().split('T')[0] : '',
        data: member
      };
    }
    return null;
  }

  /**
   * DEV-003 ②：按日期跨源查找（修"按日期查找不可用"——原 VM 仅有关键词 LIKE 检索，
   * 无任何按日期查询路径，数据层能力缺失）。
   * 聚合 4 源：日记(DiaryDao.queryByDate) + 待办(TodoDao.queryByDate) +
   * 开心事(HappyThingDao.queryByDate) + 额外事(ExtraThingDao.queryByDate)。
   * ExtractedTask 的 task_date 可空、语义不稳，不纳入日期检索。
   * 结果同样写入 AppStorage('searchResults')，UI 复用现有渲染。
   *
   * @param date 日期字符串 "YYYY-MM-DD"（与库内 date 列格式一致）
   * @returns 该日期的聚合结果（日记在前，其余按源顺序）
   */
  async searchByDate(date: string): Promise<SearchResult[]> {
    if (!date || date.trim().length === 0) {
      return [];
    }
    const target = date.trim();
    try {
      const queryResults = await Promise.all([
        DiaryDao.queryByDate(target),
        TodoDao.queryByDate(target),
        HappyThingDao.queryByDate(target),
        ExtraThingDao.queryByDate(target)
      ]);
      const diary = queryResults[0] as Diary | null;
      const todoResults = queryResults[1] as TodoItem[];
      const happyResults = queryResults[2] as HappyThing[];
      const extraResults = queryResults[3] as ExtraThing[];

      const allResults: SearchResult[] = [];

      if (diary) {
        allResults.push({
          id: `diary_${diary.id}`,
          sourceType: SearchSourceType.DIARY,
          title: `日记 - ${diary.date}`,
          snippet: SearchViewModel.truncate(diary.content, 80),
          date: diary.date,
          data: diary
        });
      }

      for (const todo of todoResults) {
        allResults.push({
          id: `todo_${todo.id}`,
          sourceType: SearchSourceType.TODO,
          title: todo.title,
          snippet: todo.completed === 1 ? '[已完成]' : '[未完成]',
          date: todo.date,
          data: todo
        });
      }

      for (const happy of happyResults) {
        allResults.push({
          id: `happy_${happy.id}`,
          sourceType: SearchSourceType.HAPPY,
          title: `${happy.emoji_id} ${SearchViewModel.truncate(happy.content, 40)}`,
          snippet: happy.content,
          date: happy.date,
          data: happy
        });
      }

      for (const extra of extraResults) {
        allResults.push({
          id: `extra_${extra.id}`,
          sourceType: SearchSourceType.EXTRA,
          title: SearchViewModel.truncate(extra.content, 40),
          snippet: extra.content,
          date: extra.date,
          data: extra
        });
      }

      this.results = allResults;
      AppStorage.setOrCreate('searchResults', this.results);
      hilog.info(0x0000, TAG, 'SearchByDate: date=%{public}s, results=%{public}d',
        target, allResults.length);
      return allResults;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'SearchByDate failed: %{public}s', error.message);
      return [];
    }
  }

  /**
   * Get search history (last 5 items, most recent first).
   */
  getHistory(): string[] {
    return this.history;
  }

  /**
   * Clear search history (memory + persisted).
   */
  async clearHistory(): Promise<void> {
    this.history = [];
    await this.persistHistory();
  }

  /**
   * Get last search results.
   */
  getResults(): SearchResult[] {
    return this.results;
  }

  /**
   * Get current query string.
   */
  getCurrentQuery(): string {
    return this.currentQuery;
  }

  /* ---- Private helpers ---- */

  /**
   * Add a keyword to history (dedup, cap at MAX_HISTORY) and persist.
   */
  private async addToHistory(keyword: string): Promise<void> {
    // Remove duplicates
    this.history = this.history.filter((h: string): boolean => h !== keyword);
    // Add to front
    this.history.unshift(keyword);
    // Keep only last 5
    if (this.history.length > MAX_HISTORY) {
      this.history = this.history.slice(0, MAX_HISTORY);
    }
    // Persist to preferences using the retained context (R-persist fix)
    await this.persistHistory();
  }

  /**
   * Persist the current in-memory history to preferences.
   * No-op (with warning) if init() never supplied a context.
   */
  private async persistHistory(): Promise<void> {
    if (!this.context) {
      hilog.warn(0x0000, TAG, 'persistHistory skipped: context not initialized');
      return;
    }
    try {
      const pref = await preferences.getPreferences(this.context, PREF_STORE);
      await pref.put(HISTORY_PREF_KEY, JSON.stringify(this.history));
      await pref.flush();
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'persistHistory failed: %{public}s', error.message);
    }
  }

  private static truncate(text: string, maxLen: number): string {
    if (!text) { return ''; }
    if (text.length <= maxLen) { return text; }
    return text.substring(0, maxLen) + '...';
  }
}
