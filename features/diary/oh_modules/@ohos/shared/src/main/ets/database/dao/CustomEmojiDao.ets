// <!-- agentID: DEV-DB -->
// File: CustomEmojiDao.ets
// Task: DB 缺口#8 - 自定义心情 emoji 库 DAO（queryAll/insert/delete/updateSort/seedBuiltins）
// 关联设计: ARC-001_DB_DESIGN.md §4 缺口#8（值域对齐红线）/ §5.5
// 模板: CheckInDao.ets / AppSettingsDao.ets 异步范式
// 🔴 值域对齐: seedBuiltins 的 emoji_key = value = 原始 emoji 字符，与 happy_thing.emoji_id 值域一致（护老数据可 join）

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseExecutor } from '../DatabaseExecutor';
import { CustomEmoji } from '../../data/CustomEmoji';

const TAG = 'CustomEmojiDao';

/** 内置心情种子（emoji_key 用原始 emoji 字符，对齐前端心情值域）*/
interface BuiltinEmojiSeed {
  emoji_key: string;
  label: string;
}

export class CustomEmojiDao {
  /**
   * 6 个内置心情：开心/平静/难过/生气/惊喜/疲惫。
   * emoji_key = value = 原始 emoji 字符（type='emoji', is_builtin=1）。
   * 见 ARC-001 §4#8 值域对齐红线：与 happy_thing.emoji_id 存的原始字符值域一致，老数据可直接 join，不丢心情。
   */
  private static readonly BUILTIN_SEEDS: BuiltinEmojiSeed[] = [
    { emoji_key: '😊', label: '开心' },
    { emoji_key: '😌', label: '平静' },
    { emoji_key: '😢', label: '难过' },
    { emoji_key: '😠', label: '生气' },
    { emoji_key: '😲', label: '惊喜' },
    { emoji_key: '😪', label: '疲惫' }
  ];

  /**
   * Query all custom emoji ordered by sort_order ascending.
   * @returns Promise<CustomEmoji[]>
   */
  static async queryAll(): Promise<CustomEmoji[]> {
    return DatabaseExecutor.executeRead<CustomEmoji[]>('CustomEmojiDao.queryAll',
      async (store: relationalStore.RdbStore): Promise<CustomEmoji[]> => {
        const sql = "SELECT * FROM custom_emoji ORDER BY sort_order ASC";
        const resultSet = await store.querySql(sql, []);
        const list: CustomEmoji[] = [];
        while (resultSet.goToNextRow()) {
          list.push(CustomEmojiDao.rowToEmoji(resultSet));
        }
        resultSet.close();
        return list;
      });
  }

  /**
   * Insert a custom emoji (user imported or seeded).
   * @returns Promise<number> Inserted row ID
   */
  static async insert(emoji: CustomEmoji): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('CustomEmojiDao.insert',
      async (store: relationalStore.RdbStore): Promise<number> => {
        const now = Date.now();
        emoji.created_at = emoji.created_at > 0 ? emoji.created_at : now;
        emoji.updated_at = now;
        const valueBucket: relationalStore.ValuesBucket = {
          'emoji_key': emoji.emoji_key,
          'label': emoji.label,
          'type': emoji.type,
          'value': emoji.value,
          'sort_order': emoji.sort_order,
          'is_builtin': emoji.is_builtin,
          'created_at': emoji.created_at,
          'updated_at': emoji.updated_at
        };
        const rowId = await store.insert('custom_emoji', valueBucket);
        hilog.info(0x0000, TAG, 'CustomEmoji inserted: key=%{public}s, rowId=%{public}d', emoji.emoji_key, rowId);
        return rowId;
      });
  }

  /**
   * Delete a custom emoji by id.
   * @returns Promise<number> Number of deleted rows
   */
  static async delete(id: number): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('CustomEmojiDao.delete',
      async (store: relationalStore.RdbStore): Promise<number> => {
        const predicates = new relationalStore.RdbPredicates('custom_emoji');
        predicates.equalTo('id', id);
        const deletedRows = await store.delete(predicates);
        hilog.info(0x0000, TAG, 'CustomEmoji deleted: id=%{public}d, affected=%{public}d', id, deletedRows);
        return deletedRows;
      });
  }

  /**
   * Batch update sort_order for reordering (transactional).
   * @param configs Emoji objects with id + new sort_order set
   */
  static async updateSort(configs: CustomEmoji[]): Promise<void> {
    return DatabaseExecutor.executeTransaction<void>('CustomEmojiDao.updateSort',
      async (store: relationalStore.RdbStore): Promise<void> => {
        const now = Date.now();
        for (const cfg of configs) {
          const valueBucket: relationalStore.ValuesBucket = {
            'sort_order': cfg.sort_order,
            'updated_at': now
          };
          const predicates = new relationalStore.RdbPredicates('custom_emoji');
          predicates.equalTo('id', cfg.id);
          await store.update(valueBucket, predicates);
        }
        hilog.info(0x0000, TAG, 'CustomEmoji sort updated: %{public}d rows', configs.length);
      });
  }

  /**
   * Seed the 6 builtin moods on first run (idempotent — skips if builtins already present).
   * emoji_key = value = 原始 emoji 字符（see BUILTIN_SEEDS / ARC-001 §4#8）。
   * 由 startup/VM 层在首次加载 emoji 库时调用（与 QuoteDao 种子灌入同范式），避免 DatabaseHelper→DAO 循环依赖。
   */
  static async seedBuiltins(): Promise<void> {
    return DatabaseExecutor.executeTransaction<void>('CustomEmojiDao.seedBuiltins',
      async (store: relationalStore.RdbStore): Promise<void> => {
        // 幂等守卫：已存在内置项则跳过
        const checkSql = "SELECT COUNT(*) as cnt FROM custom_emoji WHERE is_builtin = 1";
        const checkRs = await store.querySql(checkSql, []);
        let existing = 0;
        if (checkRs.goToFirstRow()) {
          existing = checkRs.getLong(checkRs.getColumnIndex('cnt'));
        }
        checkRs.close();
        if (existing > 0) {
          hilog.info(0x0000, TAG, 'seedBuiltins skipped: %{public}d builtins present', existing);
          return;
        }
        const now = Date.now();
        for (let i = 0; i < CustomEmojiDao.BUILTIN_SEEDS.length; i++) {
          const seed = CustomEmojiDao.BUILTIN_SEEDS[i];
          const valueBucket: relationalStore.ValuesBucket = {
            'emoji_key': seed.emoji_key,
            'label': seed.label,
            'type': 'emoji',
            'value': seed.emoji_key, // type='emoji': value == 原始字符
            'sort_order': i,
            'is_builtin': 1,
            'created_at': now,
            'updated_at': now
          };
          await store.insert('custom_emoji', valueBucket);
        }
        hilog.info(0x0000, TAG, 'seedBuiltins inserted %{public}d builtins', CustomEmojiDao.BUILTIN_SEEDS.length);
      });
  }

  private static rowToEmoji(resultSet: relationalStore.ResultSet): CustomEmoji {
    const emoji = new CustomEmoji();
    emoji.id = resultSet.getLong(resultSet.getColumnIndex('id'));
    emoji.emoji_key = resultSet.getString(resultSet.getColumnIndex('emoji_key'));
    emoji.label = resultSet.getString(resultSet.getColumnIndex('label'));
    emoji.type = resultSet.getString(resultSet.getColumnIndex('type'));
    emoji.value = resultSet.getString(resultSet.getColumnIndex('value'));
    emoji.sort_order = resultSet.getLong(resultSet.getColumnIndex('sort_order'));
    emoji.is_builtin = resultSet.getLong(resultSet.getColumnIndex('is_builtin'));
    emoji.created_at = resultSet.getLong(resultSet.getColumnIndex('created_at'));
    emoji.updated_at = resultSet.getLong(resultSet.getColumnIndex('updated_at'));
    return emoji;
  }
}
