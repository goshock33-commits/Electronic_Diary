// <!-- agentID: DEV-010 -->
// <!-- agentID: DEV+HUI -->
// File: AccountDao.ets
// Task: Account DAO — CRUD for account table
// Architecture: Follows existing DAO patterns (AppSettingsDao et al.)
// Dev paradigm: Async RelationalStore via DatabaseExecutor
// T701: 自愈补列 nickname + saveLoginAccount 写入 + getNickname 查询

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseExecutor } from '../DatabaseExecutor';

const TAG: string = 'AccountDao';

export class AccountDao {
  /**
   * T701: 自愈补列 nickname TEXT（老用户 account 表无此列，PRAGMA + ALTER TABLE 幂等补列）。
   * 由 saveLoginAccount 首次写入时触发，后续调用跳过。
   */
  private static nicknameEnsured: boolean = false;

  private static async ensureNicknameColumn(store: relationalStore.RdbStore): Promise<void> {
    if (AccountDao.nicknameEnsured) {
      return;
    }
    const rs = await store.querySql('PRAGMA table_info(account)', []);
    let found = false;
    while (rs.goToNextRow()) {
      if (rs.getString(rs.getColumnIndex('name')) === 'nickname') {
        found = true;
        break;
      }
    }
    rs.close();
    if (!found) {
      await store.executeSql('ALTER TABLE account ADD COLUMN nickname TEXT');
      hilog.info(0x0000, TAG, 'Self-heal: added nickname column to account');
    }
    AccountDao.nicknameEnsured = true;
  }

  /**
   * Get the currently logged-in account (is_logged_in = 1).
   * Returns null if no account is logged in.
   */
  static async getLoggedInAccount(): Promise<relationalStore.ValuesBucket | null> {
    return DatabaseExecutor.executeRead<relationalStore.ValuesBucket | null>('AccountDao.getLoggedInAccount',
      async (store: relationalStore.RdbStore): Promise<relationalStore.ValuesBucket | null> => {
        const sql: string = "SELECT * FROM account WHERE is_logged_in = 1 LIMIT 1";
        const resultSet = await store.querySql(sql, []);
        let result: relationalStore.ValuesBucket | null = null;
        if (resultSet.goToFirstRow()) {
          result = {
            'id': resultSet.getLong(resultSet.getColumnIndex('id')),
            'uid': resultSet.getString(resultSet.getColumnIndex('uid')),
            'phone': resultSet.getString(resultSet.getColumnIndex('phone')),
            'token': resultSet.getString(resultSet.getColumnIndex('token')),
            'is_logged_in': resultSet.getLong(resultSet.getColumnIndex('is_logged_in')),
            'login_time': resultSet.getLong(resultSet.getColumnIndex('login_time')),
            'created_at': resultSet.getLong(resultSet.getColumnIndex('created_at')),
            'nickname': resultSet.getString(resultSet.getColumnIndex('nickname'))
          };
        }
        resultSet.close();
        return result;
      });
  }

  /**
   * Get an account by uid.
   * Returns null if not found.
   */
  static async getByUid(uid: string): Promise<relationalStore.ValuesBucket | null> {
    return DatabaseExecutor.executeRead<relationalStore.ValuesBucket | null>('AccountDao.getByUid',
      async (store: relationalStore.RdbStore): Promise<relationalStore.ValuesBucket | null> => {
        const predicates = new relationalStore.RdbPredicates('account');
        predicates.equalTo('uid', uid);
        const resultSet = await store.query(predicates);
        let result: relationalStore.ValuesBucket | null = null;
        if (resultSet.goToFirstRow()) {
          result = {
            'id': resultSet.getLong(resultSet.getColumnIndex('id')),
            'uid': resultSet.getString(resultSet.getColumnIndex('uid')),
            'phone': resultSet.getString(resultSet.getColumnIndex('phone')),
            'token': resultSet.getString(resultSet.getColumnIndex('token')),
            'is_logged_in': resultSet.getLong(resultSet.getColumnIndex('is_logged_in')),
            'login_time': resultSet.getLong(resultSet.getColumnIndex('login_time')),
            'created_at': resultSet.getLong(resultSet.getColumnIndex('created_at')),
            'nickname': resultSet.getString(resultSet.getColumnIndex('nickname'))
          };
        }
        resultSet.close();
        return result;
      });
  }

  /**
   * T701: Save or update an account record.
   * If an account with the same uid exists, update it; otherwise insert.
   * Sets is_logged_in = 1, records login_time, and writes nickname.
   */
  static async saveLoginAccount(uid: string, phone: string, token: string,
    nickname?: string): Promise<void> {
    return DatabaseExecutor.executeWrite<void>('AccountDao.saveLoginAccount',
      async (store: relationalStore.RdbStore): Promise<void> => {
        // T701: 自愈补列（幂等，仅首次执行）
        await AccountDao.ensureNicknameColumn(store);

        const now: number = Date.now();
        // First, clear any existing logged-in state for all accounts
        await store.executeSql("UPDATE account SET is_logged_in = 0, token = ''");

        // Check if this uid already has a record
        const predicates = new relationalStore.RdbPredicates('account');
        predicates.equalTo('uid', uid);
        const resultSet = await store.query(predicates);
        const exists: boolean = resultSet.goToFirstRow();
        resultSet.close();

        const nick: string = nickname !== undefined ? nickname : '';

        if (exists) {
          // Update existing
          const valueBucket: relationalStore.ValuesBucket = {
            'phone': phone,
            'token': token,
            'is_logged_in': 1,
            'login_time': now
          };
          if (nick.length > 0) {
            valueBucket['nickname'] = nick;
          }
          const updatePredicates = new relationalStore.RdbPredicates('account');
          updatePredicates.equalTo('uid', uid);
          await store.update(valueBucket, updatePredicates);
          hilog.info(0x0000, TAG, 'Account updated: uid=%{public}s', uid);
        } else {
          // Insert new
          const valueBucket: relationalStore.ValuesBucket = {
            'uid': uid,
            'phone': phone,
            'token': token,
            'nickname': nick,
            'is_logged_in': 1,
            'login_time': now,
            'created_at': now
          };
          await store.insert('account', valueBucket);
          hilog.info(0x0000, TAG, 'Account inserted: uid=%{public}s nickname=%{public}s', uid, nick);
        }
      });
  }

  /**
   * T701: 查询已登录账号的 nickname。
   * @returns nickname 字符串；无登录账号或 nick 字段为空时返回空串
   */
  static async getNickname(uid: string): Promise<string> {
    return DatabaseExecutor.executeRead<string>('AccountDao.getNickname',
      async (store: relationalStore.RdbStore): Promise<string> => {
        const sql: string = "SELECT nickname FROM account WHERE uid = ? LIMIT 1";
        const resultSet = await store.querySql(sql, [uid]);
        let nick: string = '';
        if (resultSet.goToFirstRow()) {
          nick = resultSet.getString(resultSet.getColumnIndex('nickname'));
        }
        resultSet.close();
        return nick.length > 0 ? nick : '';
      });
  }

  /** 更新已登录账号的 nickname（仅改昵称，不动登录态） */
  static async updateNickname(uid: string, nickname: string): Promise<void> {
    return DatabaseExecutor.executeWrite<void>('AccountDao.updateNickname',
      async (store: relationalStore.RdbStore): Promise<void> => {
        const valueBucket: relationalStore.ValuesBucket = { 'nickname': nickname };
        const predicates = new relationalStore.RdbPredicates('account');
        predicates.equalTo('uid', uid);
        await store.update(valueBucket, predicates);
      });
  }

  /**
   * Log out: clear is_logged_in for all accounts.
   */
  static async logout(): Promise<void> {
    return DatabaseExecutor.executeWrite<void>('AccountDao.logout',
      async (store: relationalStore.RdbStore): Promise<void> => {
        await store.executeSql("UPDATE account SET is_logged_in = 0, token = ''");
        hilog.info(0x0000, TAG, 'All accounts logged out');
      });
  }

  /**
   * Check if any account is currently logged in.
   */
  static async isLoggedIn(): Promise<boolean> {
    return DatabaseExecutor.executeRead<boolean>('AccountDao.isLoggedIn',
      async (store: relationalStore.RdbStore): Promise<boolean> => {
        const sql: string = "SELECT COUNT(*) AS cnt FROM account WHERE is_logged_in = 1";
        const resultSet = await store.querySql(sql, []);
        let count: number = 0;
        if (resultSet.goToFirstRow()) {
          count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
        }
        resultSet.close();
        return count > 0;
      });
  }

  /**
   * Get the uid of the currently logged-in account, or null.
   */
  static async getLoggedInUid(): Promise<string | null> {
    return DatabaseExecutor.executeRead<string | null>('AccountDao.getLoggedInUid',
      async (store: relationalStore.RdbStore): Promise<string | null> => {
        const sql: string = "SELECT uid FROM account WHERE is_logged_in = 1 LIMIT 1";
        const resultSet = await store.querySql(sql, []);
        let uid: string | null = null;
        if (resultSet.goToFirstRow()) {
          uid = resultSet.getString(resultSet.getColumnIndex('uid'));
        }
        resultSet.close();
        return uid;
      });
  }
}
