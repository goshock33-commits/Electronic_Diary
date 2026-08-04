// <!-- agentID: DEV-011 -->
// <!-- agentID: DEV-FAMILY -->
// File: FamilyMemberDao.ets
// Task: family_member 表 DAO —— insert/update/delete/queryAll/findByNickname/findByUid
// 范式对齐: QuoteDao（DatabaseExecutor.executeRead/executeWrite + 静态方法 + rowTo 私有映射）
// 表结构见 DatabaseHelper.DDL_CREATE_FAMILY_MEMBER（v4→v5 迁移新增）
// T707: 新增 findByUid —— 按 uid 查成员，用于 addMember 去重（uid 匹配则 update 而非 insert）
// fix: DEV-006 · T013 insert/update/rowToMember 补 avatar/gender/birthday（读列 isColumnNull 兜底老数据）

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseExecutor } from '../DatabaseExecutor';
import { FamilyMember } from '../../data/FamilyMember';

const TAG = 'FamilyMemberDao';
const TABLE = 'family_member';

export class FamilyMemberDao {
  /**
   * 插入家庭成员。
   * @returns Promise<number> 新行 rowId
   */
  static async insert(member: FamilyMember): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('FamilyMemberDao.insert',
      async (store: relationalStore.RdbStore): Promise<number> => {
        const valueBucket: relationalStore.ValuesBucket = {
          'uid': member.uid,
          'nickname': member.nickname,
          'aliases': member.aliases,
          'role': member.role,
          'phone': member.phone,
          'push_token': member.push_token,
          'family_id': member.family_id,
          'is_self': member.is_self,
          'created_at': member.created_at,
          // fix: DEV-006 · T013 成员资料列（可空，ValueType 含 null —— @ohos.data.relationalStore.d.ts:201）
          'avatar': member.avatar,
          'gender': member.gender,
          'birthday': member.birthday
        };
        const rowId = await store.insert(TABLE, valueBucket);
        hilog.info(0x0000, TAG, 'insert: rowId=%{public}d nickname=%{public}s', rowId, member.nickname);
        return rowId;
      });
  }

  /**
   * 按 id 全量更新成员（id/created_at 不变）。
   * @returns Promise<number> 受影响行数（0=id 不存在）
   */
  static async update(member: FamilyMember): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('FamilyMemberDao.update',
      async (store: relationalStore.RdbStore): Promise<number> => {
        const valueBucket: relationalStore.ValuesBucket = {
          'uid': member.uid,
          'nickname': member.nickname,
          'aliases': member.aliases,
          'role': member.role,
          'phone': member.phone,
          'push_token': member.push_token,
          'family_id': member.family_id,
          'is_self': member.is_self,
          // fix: DEV-006 · T013 成员资料列（全量 update 口径，null 会真正写回 NULL —— 清空资料靠此生效）
          'avatar': member.avatar,
          'gender': member.gender,
          'birthday': member.birthday
        };
        const predicates = new relationalStore.RdbPredicates(TABLE);
        predicates.equalTo('id', member.id);
        const rows = await store.update(valueBucket, predicates);
        hilog.info(0x0000, TAG, 'update: id=%{public}d rows=%{public}d', member.id, rows);
        return rows;
      });
  }

  /**
   * 按 id 删除成员。
   * 注：todo.assignee_member_id 为逻辑引用（无 FK 约束），残留指派由业务层自行处理。
   * @returns Promise<number> 受影响行数（0=id 不存在）
   */
  /** T708-fix: 清空全部家庭成员（登出时调用，防止用户残留数据泄漏到下一用户）。 */
  static async deleteAll(): Promise<void> {
    return DatabaseExecutor.executeWrite<void>('FamilyMemberDao.deleteAll',
      async (store: relationalStore.RdbStore): Promise<void> => {
        await store.executeSql('DELETE FROM ' + TABLE);
        hilog.info(0x0000, TAG, 'deleteAll: cleared all family members');
      });
  }

  static async delete(id: number): Promise<number> {
    return DatabaseExecutor.executeWrite<number>('FamilyMemberDao.delete',
      async (store: relationalStore.RdbStore): Promise<number> => {
        const predicates = new relationalStore.RdbPredicates(TABLE);
        predicates.equalTo('id', id);
        const rows = await store.delete(predicates);
        hilog.info(0x0000, TAG, 'delete: id=%{public}d rows=%{public}d', id, rows);
        return rows;
      });
  }

  /**
   * 查询全部成员（is_self=1 置顶，其余按创建时间升序）。
   */
  static async queryAll(): Promise<FamilyMember[]> {
    return DatabaseExecutor.executeRead<FamilyMember[]>('FamilyMemberDao.queryAll',
      async (store: relationalStore.RdbStore): Promise<FamilyMember[]> => {
        const sql = `SELECT * FROM ${TABLE} ORDER BY is_self DESC, created_at ASC, id ASC`;
        const resultSet = await store.querySql(sql, []);
        const members: FamilyMember[] = [];
        while (resultSet.goToNextRow()) {
          members.push(FamilyMemberDao.rowToMember(resultSet));
        }
        resultSet.close();
        return members;
      });
  }

  /**
   * 按昵称精确查找成员（多条同名取最早创建的一条）。
   * 注：仅匹配 nickname 列；别名匹配请在业务层用 FamilyMember.matchesName 遍历 queryAll 结果。
   * @returns Promise<FamilyMember | null> 未找到返回 null
   */
  static async findByNickname(nickname: string): Promise<FamilyMember | null> {
    return DatabaseExecutor.executeRead<FamilyMember | null>('FamilyMemberDao.findByNickname',
      async (store: relationalStore.RdbStore): Promise<FamilyMember | null> => {
        const sql = `SELECT * FROM ${TABLE} WHERE nickname = ? ORDER BY id ASC LIMIT 1`;
        const resultSet = await store.querySql(sql, [nickname]);
        if (resultSet.goToFirstRow()) {
          const member = FamilyMemberDao.rowToMember(resultSet);
          resultSet.close();
          return member;
        }
        resultSet.close();
        return null;
      });
  }

  /**
   * DEV-020: 按 id 查询成员（for GlobalSearchService FTS5 result mapping）。
   * @param id 成员 ID
   * @returns Promise<FamilyMember | null> 未找到返回 null
   */
  static async queryById(id: number): Promise<FamilyMember | null> {
    return DatabaseExecutor.executeRead<FamilyMember | null>('FamilyMemberDao.queryById',
      async (store: relationalStore.RdbStore): Promise<FamilyMember | null> => {
        const predicates = new relationalStore.RdbPredicates(TABLE);
        predicates.equalTo('id', id);
        const resultSet = await store.query(predicates);
        if (resultSet.goToFirstRow()) {
          const member = FamilyMemberDao.rowToMember(resultSet);
          resultSet.close();
          return member;
        }
        resultSet.close();
        return null;
      });
  }

  /**
   * T707: 按 uid 精确查找成员（uid 为 null 时直接返回 null）。
   * 用于 addMember 去重 —— uid 匹配则 update 而非 insert。
   * @returns Promise<FamilyMember | null> 未找到返回 null
   */
  static async findByUid(uid: string): Promise<FamilyMember | null> {
    if (uid.length === 0) {
      return null;
    }
    return DatabaseExecutor.executeRead<FamilyMember | null>('FamilyMemberDao.findByUid',
      async (store: relationalStore.RdbStore): Promise<FamilyMember | null> => {
        const sql = `SELECT * FROM ${TABLE} WHERE uid = ? ORDER BY id ASC LIMIT 1`;
        const resultSet = await store.querySql(sql, [uid]);
        if (resultSet.goToFirstRow()) {
          const member = FamilyMemberDao.rowToMember(resultSet);
          resultSet.close();
          return member;
        }
        resultSet.close();
        return null;
      });
  }

  /** 行 → FamilyMember 映射（可空列 isColumnNull 防御，先例：QuoteDao.rowToQuote） */
  private static rowToMember(resultSet: relationalStore.ResultSet): FamilyMember {
    const member = new FamilyMember();
    member.id = resultSet.getLong(resultSet.getColumnIndex('id'));
    member.uid = resultSet.isColumnNull(resultSet.getColumnIndex('uid'))
      ? null : resultSet.getString(resultSet.getColumnIndex('uid'));
    member.nickname = resultSet.getString(resultSet.getColumnIndex('nickname'));
    member.aliases = resultSet.getString(resultSet.getColumnIndex('aliases'));
    member.role = resultSet.getString(resultSet.getColumnIndex('role'));
    member.phone = resultSet.isColumnNull(resultSet.getColumnIndex('phone'))
      ? null : resultSet.getString(resultSet.getColumnIndex('phone'));
    member.push_token = resultSet.isColumnNull(resultSet.getColumnIndex('push_token'))
      ? null : resultSet.getString(resultSet.getColumnIndex('push_token'));
    member.family_id = resultSet.isColumnNull(resultSet.getColumnIndex('family_id'))
      ? null : resultSet.getString(resultSet.getColumnIndex('family_id'));
    member.is_self = resultSet.getLong(resultSet.getColumnIndex('is_self'));
    member.created_at = resultSet.getLong(resultSet.getColumnIndex('created_at'));
    // fix: DEV-006 · T013 成员资料列 —— 自愈补列对老数据恒为 NULL，必须 isColumnNull 兜底（沿用 phone/push_token 范式）
    member.avatar = resultSet.isColumnNull(resultSet.getColumnIndex('avatar'))
      ? null : resultSet.getString(resultSet.getColumnIndex('avatar'));
    member.gender = resultSet.isColumnNull(resultSet.getColumnIndex('gender'))
      ? null : resultSet.getString(resultSet.getColumnIndex('gender'));
    member.birthday = resultSet.isColumnNull(resultSet.getColumnIndex('birthday'))
      ? null : resultSet.getString(resultSet.getColumnIndex('birthday'));
    return member;
  }
}
