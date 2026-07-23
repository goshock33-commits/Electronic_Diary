// <!-- agentID: DEV-AI-COMPANION -->
// File: ChatMessageDao.ets
// Task: AI伙伴对话历史 DAO —— insert / queryRecent(limit) / clear，走 DatabaseExecutor
// Architecture: ARC-001 4.x DAO 范式；表 chat_message 由 DatabaseHelper.migrateV2ToV3 建
// Template: DiaryDao.ets（executeWrite/executeRead + rowToXxx）

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseExecutor } from '../DatabaseExecutor';
import { ChatMessage } from '../../data/ChatMessage';

const TAG = 'ChatMessageDao';

export class ChatMessageDao {
  /**
   * 插入一条对话消息。
   * @returns Promise<number> 新行 id
   */
  static async insert(msg: ChatMessage): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('ChatMessageDao.insert', async (store: relationalStore.RdbStore): Promise<number> => {
      const valueBucket: relationalStore.ValuesBucket = {
        'session_id': msg.session_id,
        'role': msg.role,
        'content': msg.content,
        'created_at': msg.created_at
      };
      const rowId = await store.insert('chat_message', valueBucket);
      hilog.info(0x0000, TAG, 'ChatMessage inserted: role=%{public}s, rowId=%{public}d', msg.role, rowId);
      return rowId;
    });
  }

  /**
   * 读取最近 limit 条消息，按时间正序返回（旧→新，直接用于聊天列表自上而下渲染）。
   * 子查询先取最新 limit 条(id DESC)，再整体 id ASC 复位为时间正序。
   * @param limit 上限；<=0 时兜底 50
   */
  static async queryRecent(limit: number): Promise<ChatMessage[]> {
    return DatabaseExecutor.executeRead<ChatMessage[]>('ChatMessageDao.queryRecent', async (store: relationalStore.RdbStore): Promise<ChatMessage[]> => {
      const safeLimit: number = limit > 0 ? limit : 50;
      const sql = 'SELECT * FROM (SELECT * FROM chat_message ORDER BY id DESC LIMIT ?) ORDER BY id ASC';
      const resultSet = await store.querySql(sql, [safeLimit]);
      const list: ChatMessage[] = [];
      while (resultSet.goToNextRow()) {
        list.push(ChatMessageDao.rowToChatMessage(resultSet));
      }
      resultSet.close();
      hilog.info(0x0000, TAG, 'queryRecent returned %{public}d rows', list.length);
      return list;
    });
  }

  /**
   * 清空全部对话历史。
   * @returns Promise<number> 删除行数
   */
  static async clear(): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('ChatMessageDao.clear', async (store: relationalStore.RdbStore): Promise<number> => {
      const predicates = new relationalStore.RdbPredicates('chat_message');
      const deleted = await store.delete(predicates);
      hilog.info(0x0000, TAG, 'chat_message cleared: %{public}d rows', deleted);
      return deleted;
    });
  }

  /** ResultSet 行 → ChatMessage */
  private static rowToChatMessage(resultSet: relationalStore.ResultSet): ChatMessage {
    const m = new ChatMessage();
    m.id = resultSet.getLong(resultSet.getColumnIndex('id'));
    m.session_id = resultSet.getString(resultSet.getColumnIndex('session_id'));
    m.role = resultSet.getString(resultSet.getColumnIndex('role'));
    m.content = resultSet.getString(resultSet.getColumnIndex('content'));
    m.created_at = resultSet.getLong(resultSet.getColumnIndex('created_at'));
    return m;
  }
}
