// <!-- agentID: DEV-020 -->
// File: GlobalSearchService.ets
// Task: T012 GlobalSearchService - 全局搜索服务（基于 FTS5 虚拟表）
// Architecture: REFACTOR_ARCHITECTURE.md §5 全局搜索（FTS5）
// 依赖前置: DEV-005 T012（FTS5 表已在 DatabaseHelper.migrateV5ToV6 创建）
// 边界约束: 只写搜索服务，不实现 UI，不在 Dao 处调用 syncToFTS5（后续任务）

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseHelper } from '../database/DatabaseHelper';
import { SearchResult } from './SearchResult';
import { DiaryDao } from '../database/dao/DiaryDao';
import { TodoDao } from '../database/dao/TodoDao';
import { FamilyMemberDao } from '../database/dao/FamilyMemberDao';

const TAG = 'GlobalSearchService';

/**
 * 全局搜索服务（FTS5 全文索引）
 *
 * 核心功能：
 * 1. syncToFTS5() - 同步数据到 FTS5 虚拟表（供 Dao 层调用）
 * 2. search() - 执行 FTS5 全文搜索，返回 SearchResult[]
 *
 * 表结构（DatabaseHelper.migrateV5ToV6 已创建）：
 * CREATE VIRTUAL TABLE fts_search USING fts5(
 *   source_table TEXT,  -- 来源表名（diary_entry/todo/family_member）
 *   source_id INTEGER,  -- 来源表主键
 *   content TEXT        -- 搜索内容
 * );
 *
 * 分词器配置：
 * - 由 DatabaseHelper.initialize() 通过 StoreConfig.tokenizer 统一控制
 * - ICU_TOKENIZER（支持中文分词）或 NONE_TOKENIZER（降级方案）
 * - 降级标记：AppStorage.get<boolean>('fts_fallback_to_like')
 */
export class GlobalSearchService {
  /**
   * 同步数据到 FTS5 虚拟表（供 DiaryDao/TodoDao/FamilyMemberDao 调用）
   *
   * 调用时机：
   * - insert/update 后立即调用
   * - delete 后调用（传空 content 删除索引）
   *
   * @param sourceTable 来源表名（'diary_entry' | 'todo' | 'family_member'）
   * @param sourceId 来源表主键
   * @param content 搜索内容（日记标题+内容、待办标题、成员昵称+别名）
   */
  static async syncToFTS5(sourceTable: string, sourceId: number, content: string): Promise<void> {
    try {
      const store = DatabaseHelper.getInstance().getStore();

      // 删除旧记录（防止重复索引）
      await store.executeSql(
        'DELETE FROM fts_search WHERE source_table=? AND source_id=?',
        [sourceTable, sourceId]
      );

      // 插入新记录（content 为空时跳过插入，仅删除索引）
      if (content && content.trim().length > 0) {
        await store.executeSql(
          'INSERT INTO fts_search(source_table, source_id, content) VALUES(?,?,?)',
          [sourceTable, sourceId, content]
        );
      }

      hilog.info(0x0000, TAG, 'syncToFTS5: table=%{public}s id=%{public}d synced',
        sourceTable, sourceId);
    } catch (err) {
      hilog.error(0x0000, TAG, 'syncToFTS5 failed: %{public}s', (err as Error).message);
      throw new Error('syncToFTS5 failed: ' + (err as Error).message);
    }
  }

  /**
   * 执行 FTS5 全文搜索（跨日记/待办/成员）
   *
   * FTS5 MATCH 语法：
   * - 单词：'关键词' → 匹配包含"关键词"的记录
   * - 多词：'关键词1 关键词2' → 匹配包含两个词的记录（AND 语义）
   * - 前缀：'关键*' → 匹配以"关键"开头的词
   *
   * 降级策略（当 ICU_TOKENIZER 不可用）：
   * - AppStorage.get('fts_fallback_to_like') === true 时
   * - 改用多表 LIKE 查询（DiaryDao.searchByTitle / TodoDao.searchByTitle 等）
   * - 注：当前实现暂不处理降级，由后续任务补充
   *
   * @param keyword 搜索关键词
   * @returns Promise<SearchResult[]> 搜索结果数组（最多 50 条）
   */
  static async search(keyword: string): Promise<SearchResult[]> {
    if (!keyword || keyword.trim().length === 0) {
      return [];
    }

    try {
      const store = DatabaseHelper.getInstance().getStore();

      // FTS5 MATCH 查询（source_table 和 source_id 用于回查原始数据）
      const sql = 'SELECT source_table, source_id FROM fts_search WHERE fts_search MATCH ? LIMIT 50';
      const resultSet = await store.querySql(sql, [keyword]);
      const results: SearchResult[] = [];

      // 遍历 FTS5 结果，根据 source_table 回查原始数据
      while (resultSet.goToNextRow()) {
        const sourceTable = resultSet.getString(0);
        const sourceId = resultSet.getLong(1);

        if (sourceTable === 'diary_entry') {
          const diary = await DiaryDao.queryById(sourceId);
          if (diary) {
            results.push({ type: 'diary', data: diary });
          }
        } else if (sourceTable === 'todo') {
          const todo = await TodoDao.queryById(sourceId);
          if (todo) {
            results.push({ type: 'todo', data: todo });
          }
        } else if (sourceTable === 'family_member') {
          const member = await FamilyMemberDao.queryById(sourceId);
          if (member) {
            results.push({ type: 'member', data: member });
          }
        }
      }

      resultSet.close();
      hilog.info(0x0000, TAG, 'search: keyword=%{public}s results=%{public}d',
        keyword, results.length);
      return results;
    } catch (err) {
      hilog.error(0x0000, TAG, 'search failed: %{public}s', (err as Error).message);
      throw new Error('search failed: ' + (err as Error).message);
    }
  }
}
