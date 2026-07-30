// <!-- agentID: DEV-020 -->
// File: SearchResult.ets
// Task: T012 GlobalSearchService - SearchResult 类型定义
// Architecture: REFACTOR_ARCHITECTURE.md §5 全局搜索（FTS5）

import { Diary } from '../data/Diary';
import { TodoItem } from '../data/TodoItem';
import { FamilyMember } from '../data/FamilyMember';

/**
 * 全局搜索结果统一类型（FTS5 虚拟表查询后的原始数据映射）
 */
export interface SearchResult {
  type: 'diary' | 'todo' | 'member';
  data: Diary | TodoItem | FamilyMember;
}
