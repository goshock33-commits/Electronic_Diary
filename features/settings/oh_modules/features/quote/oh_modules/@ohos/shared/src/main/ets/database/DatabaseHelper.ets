// <!-- agentID: DEV-001 -->
// fix: DEV-FAMILY · 家庭成员：新表 family_member + todo.assignee_member_id 指派列（v4→v5 迁移 + 启动自愈双入口，沿用 DEV-012 范式）
// fix: DEV-013 · 待办提醒增强：todo 表自愈补列 due_date/due_time/location/custom_tags/remind_at/reminder_id（ensureTodoReminderColumns，沿用 category 自愈先例）
// fix: DEV-012 · T-M01 日记「一天多篇」：新主表 diary_entry（date 无 UNIQUE）+ v3→v4 迁移（老 diary 数据拷入，原表保留闲置）
// File: DatabaseHelper.ets
// Task: T003 Database layer - RelationalStore initialization and management
// Architecture: ARC-001 5.2 / 5.3 / 5.4
// Skill Ref: frontend-design / ui-ux-pro-max

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'DatabaseHelper';
const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'HuaweiDiary.db',
  securityLevel: relationalStore.SecurityLevel.S2,
  encrypt: false
};

/**
 * DatabaseHelper - Singleton for RelationalStore lifecycle management
 * Handles: initialization, versioning, table creation, indexes, migrations
 */
export class DatabaseHelper {
  private static instance: DatabaseHelper | null = null;
  private store: relationalStore.RdbStore | null = null;
  private initialized: boolean = false;

  /** Current database version (DEV-DB 1→2: diary.title/mood + custom_emoji; DEV-AI-COMPANION 2→3: chat_message; DEV-012 3→4: diary_entry 一天多篇; DEV-FAMILY 4→5: family_member + todo.assignee_member_id) */
  static readonly DATABASE_VERSION: number = 5;

  /**
   * diary_entry table DDL (v4, created by migrator + startup self-heal — NOT part of v1 baseline).
   * fix: DEV-012 · 产品形态变更「一天多篇」：date 为普通列（无 UNIQUE，仅 idx_diary_entry_date 普通索引），
   * 同日可多行互不覆盖；老 diary 表（date UNIQUE）保留闲置不动（禁 DROP/RENAME）。
   */
  private static readonly DDL_CREATE_DIARY_ENTRY: string =
    `CREATE TABLE IF NOT EXISTS diary_entry (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      title TEXT,
      mood TEXT,
      content TEXT,
      images TEXT DEFAULT '[]',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )`;

  /**
   * custom_emoji table DDL (v2, created by migrator only — NOT part of v1 baseline).
   * DEV-DB 缺口#8: type TEXT('emoji'|'image') + updated_at; emoji_key 逻辑被 happy_thing.emoji_id 引用。
   */
  private static readonly DDL_CREATE_CUSTOM_EMOJI: string =
    `CREATE TABLE IF NOT EXISTS custom_emoji (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      emoji_key TEXT UNIQUE NOT NULL,
      label TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'emoji',
      value TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_builtin INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )`;

  /**
   * chat_message table DDL (v3, created by migrator only — NOT part of v1 baseline).
   * DEV-AI-COMPANION: AI伙伴(Mimi)对话历史落库。§8.2 合规: INTEGER 时间戳 + snake_case。
   * role: 'user'|'ai'; session_id 预留多会话（当前单会话 'default'）。
   */
  private static readonly DDL_CREATE_CHAT_MESSAGE: string =
    `CREATE TABLE IF NOT EXISTS chat_message (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL DEFAULT 'default',
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )`;

  /**
   * family_member table DDL (v5, created by migrator + startup self-heal — NOT part of v1 baseline).
   * fix: DEV-FAMILY · 家庭成员表；aliases 以 JSON 数组字符串落库（先例：todo.custom_tags）；
   * todo.assignee_member_id 逻辑引用本表 id（不建 FK 约束，先例：happy_thing.emoji_id）。
   */
  private static readonly DDL_CREATE_FAMILY_MEMBER: string =
    `CREATE TABLE IF NOT EXISTS family_member (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uid TEXT,
      nickname TEXT NOT NULL,
      aliases TEXT NOT NULL DEFAULT '[]',
      role TEXT NOT NULL DEFAULT 'member',
      phone TEXT,
      push_token TEXT,
      family_id TEXT,
      is_self INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )`;

  /**
   * account table DDL (DEV+HUI, created by startup self-heal — NOT part of v1 baseline).
   * 登录态落库：uid/token/phone + is_logged_in 登录标记。
   */
  private static readonly DDL_CREATE_ACCOUNT: string =
    `CREATE TABLE IF NOT EXISTS account (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uid TEXT NOT NULL,
      phone TEXT,
      token TEXT,
      is_logged_in INTEGER NOT NULL DEFAULT 0,
      login_time INTEGER,
      created_at INTEGER NOT NULL
    )`;

  /** All 10 table DDL statements */
  private static readonly DDL_CREATE_TABLES: string[] = [
    // Table 1: diary
    `CREATE TABLE IF NOT EXISTS diary (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT UNIQUE NOT NULL,
      content TEXT,
      title TEXT,
      mood TEXT,
      images TEXT DEFAULT '[]',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )`,
    // Table 2: check_in
    `CREATE TABLE IF NOT EXISTS check_in (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT UNIQUE NOT NULL,
      created_at INTEGER NOT NULL
    )`,
    // Table 3: todo
    `CREATE TABLE IF NOT EXISTS todo (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'today',
      title TEXT NOT NULL,
      completed INTEGER NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      source_task_id INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )`,
    // Table 4: happy_thing
    `CREATE TABLE IF NOT EXISTS happy_thing (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      content TEXT NOT NULL,
      emoji_id TEXT NOT NULL,
      image TEXT,
      created_at INTEGER NOT NULL
    )`,
    // Table 5: extra_thing
    `CREATE TABLE IF NOT EXISTS extra_thing (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )`,
    // Table 6: extracted_task
    `CREATE TABLE IF NOT EXISTS extracted_task (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT 'general',
      title TEXT NOT NULL,
      description TEXT,
      task_date TEXT,
      task_time TEXT,
      location TEXT,
      priority INTEGER,
      is_converted INTEGER NOT NULL DEFAULT 0,
      converted_todo_id INTEGER,
      created_at INTEGER NOT NULL
    )`,
    // Table 7: quote
    `CREATE TABLE IF NOT EXISTS quote (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      content TEXT NOT NULL,
      author TEXT NOT NULL DEFAULT 'Unknown',
      is_builtin INTEGER NOT NULL DEFAULT 1,
      last_shown_date TEXT,
      created_at INTEGER NOT NULL
    )`,
    // Table 8: pomodoro_session
    `CREATE TABLE IF NOT EXISTS pomodoro_session (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      preset_type TEXT NOT NULL DEFAULT 'focus',
      duration_minutes INTEGER NOT NULL,
      actual_seconds INTEGER,
      completed INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      ended_at INTEGER
    )`,
    // Table 9: section_config
    `CREATE TABLE IF NOT EXISTS section_config (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      section_key TEXT UNIQUE NOT NULL,
      title TEXT NOT NULL,
      is_visible INTEGER NOT NULL DEFAULT 1,
      sort_order INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )`,
    // Table 10: app_settings
    `CREATE TABLE IF NOT EXISTS app_settings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      key TEXT UNIQUE NOT NULL,
      value TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )`
  ];

  /** Index DDL statements - per architecture 5.3 */
  private static readonly DDL_CREATE_INDEXES: string[] = [
    'CREATE INDEX IF NOT EXISTS idx_todo_date_type ON todo(date, type)',
    'CREATE INDEX IF NOT EXISTS idx_todo_source_task ON todo(source_task_id)',
    'CREATE INDEX IF NOT EXISTS idx_happy_thing_date ON happy_thing(date)',
    'CREATE INDEX IF NOT EXISTS idx_extra_thing_date ON extra_thing(date)',
    'CREATE INDEX IF NOT EXISTS idx_extracted_task_converted ON extracted_task(is_converted)',
    'CREATE INDEX IF NOT EXISTS idx_extracted_task_created ON extracted_task(created_at)',
    'CREATE INDEX IF NOT EXISTS idx_quote_last_shown ON quote(last_shown_date)',
    'CREATE INDEX IF NOT EXISTS idx_pomodoro_date_type ON pomodoro_session(date, preset_type)',
    'CREATE INDEX IF NOT EXISTS idx_section_config_sort ON section_config(sort_order)'
  ];

  // Private constructor for singleton
  private constructor() {}

  /**
   * Get singleton instance
   */
  static getInstance(): DatabaseHelper {
    if (!DatabaseHelper.instance) {
      DatabaseHelper.instance = new DatabaseHelper();
    }
    return DatabaseHelper.instance;
  }

  /**
   * fix: HUI-FRONTEND-1 · ready 门闩（Promise latch）——DatabaseExecutor 在 getStore 前 await whenReady()，
   * 消除启动竞态（页面首帧 DAO 查询早于 getRdbStore 完成 → getStore 抛错 → VM catch 吞掉 → 数据恒空）。
   */
  private readyPromise: Promise<void> | null = null;
  private readyResolve: (() => void) | null = null;

  whenReady(): Promise<void> {
    if (this.initialized && this.store) {
      return Promise.resolve();
    }
    if (!this.readyPromise) {
      this.readyPromise = new Promise<void>((resolve: () => void) => {
        this.readyResolve = resolve;
      });
    }
    return this.readyPromise;
  }

  /**
   * Initialize the database store. Must be called once at app startup (P0).
   */
  async initialize(context: Context): Promise<void> {
    if (this.initialized && this.store) {
      hilog.warn(0x0000, TAG, 'Database already initialized, skipping');
      return;
    }

    try {
      const store = await relationalStore.getRdbStore(context, STORE_CONFIG);
      this.store = store;
      // DEV-DB 迁移铁律: PRAGMA 与建表全程 await（现有 fire-and-forget 已修正，保证基线在迁移前落地）
      await store.executeSql('PRAGMA journal_mode=WAL');
      await store.executeSql('PRAGMA foreign_keys=ON');
      // 新装判定必须在基线建 diary 表之前（ARC-001 §5.4）
      const isFreshInstall = !(await DatabaseHelper.tableExists(store, 'diary'));
      await this.createTablesAndIndexes();               // v1 冻结基线（不含 title/mood/custom_emoji）
      await DatabaseHelper.migrate(store, isFreshInstall); // v1→v2 手动步进迁移
      await DatabaseHelper.ensureDiaryColumns(store);    // 自愈补列（不受版本号 gate）
      await DatabaseHelper.ensureTodoReminderColumns(store); // fix: DEV-013 todo 提醒 6 列自愈补列（不受版本号 gate，幂等）
      await DatabaseHelper.ensureDiaryEntryTable(store); // fix: DEV-012 v4 主表自愈守卫（不受版本号 gate，幂等）
      await DatabaseHelper.ensureFamilyMemberSchema(store); // fix: DEV-FAMILY v5 表/列自愈守卫（不受版本号 gate，幂等）
      await DatabaseHelper.ensureAccountTable(store);      // DEV+HUI 登录态 account 表自愈守卫（不受版本号 gate，幂等）
      this.initialized = true;
      // fix: HUI-FRONTEND-1 · 唤醒 whenReady 等待者
      if (this.readyResolve) {
        this.readyResolve();
        this.readyResolve = null;
      }
      hilog.info(0x0000, TAG, 'Database initialized successfully, version=%{public}d',
        DatabaseHelper.DATABASE_VERSION);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Database initialization failed: %{public}s', error.message);
      throw new Error(`Database initialization failed: ${error.message}`);
    }
  }

  /**
   * Create all tables and indexes (v1 baseline, frozen).
   * DEV-DB: executeSql now fully awaited so the baseline is guaranteed present before migration runs.
   */
  private async createTablesAndIndexes(): Promise<void> {
    if (!this.store) {
      throw new Error('Database store not available');
    }
    const store = this.store;
    // Execute all CREATE TABLE statements
    for (const ddl of DatabaseHelper.DDL_CREATE_TABLES) {
      await store.executeSql(ddl);
    }
    // Execute all CREATE INDEX statements
    for (const idxDdl of DatabaseHelper.DDL_CREATE_INDEXES) {
      await store.executeSql(idxDdl);
    }
    hilog.info(0x0000, TAG, 'Tables and indexes created: %{public}d tables, %{public}d indexes',
      DatabaseHelper.DDL_CREATE_TABLES.length, DatabaseHelper.DDL_CREATE_INDEXES.length);
  }

  /**
   * Manual version-step migration (API 24 has no onUpgrade). ARC-001 §5.4.
   * 🔴 原子性红线: 每条异步显式 await，DDL 全部落地后才写 store.version。
   * 迁移前整库 backup，失败 restore 回滚（真正新装跳过 backup/restore）。
   * @param store The RdbStore
   * @param isFreshInstall true if diary table did not exist before baseline creation
   */
  private static async migrate(store: relationalStore.RdbStore, isFreshInstall: boolean): Promise<void> {
    let oldVersion: number = store.version;   // getter；新库/历史库均为 0
    if (oldVersion === 0) {
      oldVersion = 1;                          // 归一化为基线；禁写 store.version=0（setter 要求 >0）
    }
    if (oldVersion >= DatabaseHelper.DATABASE_VERSION) {
      hilog.info(0x0000, TAG, 'DB up to date (version=%{public}d), skip migration', oldVersion);
      return;
    }
    const bak: string = `HuaweiDiary.pre_v${oldVersion}.bak`;
    if (!isFreshInstall) {
      await store.backup(bak);                 // .d.ts:6905 迁移前整库备份 · 必 await
      hilog.info(0x0000, TAG, 'Pre-migration backup created: %{public}s', bak);
    }
    try {
      if (oldVersion < 2) {
        await DatabaseHelper.migrateV1ToV2(store);   // 每条 DDL 逐条 await
      }
      if (oldVersion < 3) {
        await DatabaseHelper.migrateV2ToV3(store);   // v2→v3: chat_message（每条 DDL 逐条 await）
      }
      if (oldVersion < 4) {
        await DatabaseHelper.migrateV3ToV4(store);   // fix: DEV-012 v3→v4: diary_entry 一天多篇（每条 DDL/DML 逐条 await）
      }
      if (oldVersion < 5) {
        await DatabaseHelper.migrateV4ToV5(store);   // fix: DEV-FAMILY v4→v5: family_member + todo.assignee_member_id（每条 DDL 逐条 await）
      }
      // 全部 DDL 落地后才写版本（原子性红线；值恒 >0）
      store.version = DatabaseHelper.DATABASE_VERSION;  // .d.ts:4515
      hilog.info(0x0000, TAG, 'Migration finished, version set to %{public}d', DatabaseHelper.DATABASE_VERSION);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Migration failed: %{public}s', error.message);
      if (!isFreshInstall) {
        await store.restore(bak);              // .d.ts:7011 失败回滚整库 · 必 await
        hilog.error(0x0000, TAG, 'Database restored from backup: %{public}s', bak);
      }
      throw new Error(`Database migration failed: ${error.message}`);
    }
  }

  /**
   * v1 → v2 migration statements (ARC-001 §5.5). Every statement awaited.
   * ALTER 用 PRAGMA 守卫幂等（崩溃自愈重跑安全）；CREATE ... IF NOT EXISTS 本身幂等。
   */
  private static async migrateV1ToV2(store: relationalStore.RdbStore): Promise<void> {
    // 1) diary.title —— PRAGMA 守卫（SQLite 无 ADD COLUMN IF NOT EXISTS）
    const hasTitle: boolean = await DatabaseHelper.columnExists(store, 'diary', 'title');
    if (!hasTitle) {
      await store.executeSql('ALTER TABLE diary ADD COLUMN title TEXT');
    }
    // 2) diary.mood
    const hasMood: boolean = await DatabaseHelper.columnExists(store, 'diary', 'mood');
    if (!hasMood) {
      await store.executeSql('ALTER TABLE diary ADD COLUMN mood TEXT');
    }
    // 3) custom_emoji 表（幂等）
    await store.executeSql(DatabaseHelper.DDL_CREATE_CUSTOM_EMOJI);
    // 4) emoji 排序索引（幂等）
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_custom_emoji_sort ON custom_emoji(sort_order)');
    // 5) 心情统计索引（必建，幂等）
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_diary_mood ON diary(mood)');
    hilog.info(0x0000, TAG, 'v1->v2 DDL applied');
  }

  /**
   * v2 → v3 migration (DEV-AI-COMPANION). Every statement awaited (原子性红线).
   * 新增 chat_message 表 + created_at 索引；CREATE ... IF NOT EXISTS 本身幂等，崩溃自愈重跑安全。
   * 沿用 DEV-DB 步进范式：由 migrate() 在 v1→v2 之后调用，全部落地后才写 store.version=3。
   */
  private static async migrateV2ToV3(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(DatabaseHelper.DDL_CREATE_CHAT_MESSAGE);
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_chat_message_created ON chat_message(created_at)');
    hilog.info(0x0000, TAG, 'v2->v3 DDL applied');
  }

  /**
   * fix: DEV-012 · v3 → v4 migration: diary「一天多篇」。Every statement awaited (原子性红线).
   * ① 建 diary_entry 表 + idx_diary_entry_date 普通索引（CREATE IF NOT EXISTS 幂等）；
   * ② 老 diary 数据整表拷入 diary_entry（幂等守卫：diary_entry 已有行则跳过拷贝，崩溃自愈重跑不重复）；
   * ③ 老 diary 表保留闲置不动（迁移铁律：禁 DROP TABLE / RENAME TABLE）。
   * 拷贝前提：migrate() 顺序保证 v1→v2 已先行（diary.title/mood 列已存在）；images 用 COALESCE 兜底 NULL。
   */
  private static async migrateV3ToV4(store: relationalStore.RdbStore): Promise<void> {
    await DatabaseHelper.ensureDiaryEntryTable(store);
    const hasOldDiary: boolean = await DatabaseHelper.tableExists(store, 'diary');
    if (hasOldDiary) {
      await store.executeSql(
        "INSERT OR IGNORE INTO diary_entry (date, title, mood, content, images, created_at, updated_at) " +
        "SELECT date, title, mood, content, COALESCE(images, '[]'), created_at, updated_at FROM diary " +
        "WHERE date NOT IN (SELECT date FROM diary_entry)");
      hilog.info(0x0000, TAG, 'v3->v4 data migrated: diary -> diary_entry (incremental)');
    }
    hilog.info(0x0000, TAG, 'v3->v4 DDL applied');
  }

  /**
   * fix: DEV-012 · diary_entry 表 + date 普通索引（幂等，自愈安全）。
   * 由 migrateV3ToV4 与 initialize 启动自愈双入口调用（不受版本号 gate，防 version 已写但表缺失的病态库崩溃）。
   */
  private static async ensureDiaryEntryTable(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(DatabaseHelper.DDL_CREATE_DIARY_ENTRY);
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_diary_entry_date ON diary_entry(date)');
  }

  /**
   * fix: DEV-FAMILY · v4 → v5 migration: family_member 表 + todo.assignee_member_id 指派列。
   * Every statement awaited (原子性红线)；全部幂等（CREATE IF NOT EXISTS / PRAGMA 守卫），崩溃自愈重跑安全。
   * 与 ensureFamilyMemberSchema 共用实现（沿用 DEV-012 migrateV3ToV4 / ensureDiaryEntryTable 双入口范式）。
   */
  private static async migrateV4ToV5(store: relationalStore.RdbStore): Promise<void> {
    await DatabaseHelper.ensureFamilyMemberSchema(store);
    hilog.info(0x0000, TAG, 'v4->v5 DDL applied');
  }

  /**
   * fix: DEV-FAMILY · family_member 表 + 索引 + todo.assignee_member_id 补列（幂等，自愈安全）。
   * 由 migrateV4ToV5 与 initialize 启动自愈双入口调用（不受版本号 gate，防 version 已写但表/列缺失的病态库崩溃）。
   * assignee_member_id INTEGER 可空（null=未指派/派给自己），逻辑引用 family_member.id（不建 FK 约束）。
   */
  private static async ensureFamilyMemberSchema(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(DatabaseHelper.DDL_CREATE_FAMILY_MEMBER);
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_family_member_family ON family_member(family_id)');
    const hasAssignee: boolean = await DatabaseHelper.columnExists(store, 'todo', 'assignee_member_id');
    if (!hasAssignee) {
      await store.executeSql('ALTER TABLE todo ADD COLUMN assignee_member_id INTEGER');
      hilog.info(0x0000, TAG, 'Self-heal: added todo.assignee_member_id');
    }
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_todo_assignee ON todo(assignee_member_id)');
  }

  /**
   * fix: DEV-012 · Count rows of a table (migration idempotence guard).
   * Table name is a hardcoded literal (not user input) → safe to interpolate.
   */
  private static async tableRowCount(store: relationalStore.RdbStore, table: string): Promise<number> {
    const resultSet = await store.querySql(`SELECT COUNT(*) AS cnt FROM ${table}`, []);
    let count = 0;
    if (resultSet.goToFirstRow()) {
      count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
    }
    resultSet.close();
    return count;
  }

  /**
   * Check whether a column exists on a table via PRAGMA table_info.
   * Table name is a hardcoded literal (not user input) → safe to interpolate (PRAGMA can't bind identifiers).
   */
  private static async columnExists(store: relationalStore.RdbStore, table: string, column: string): Promise<boolean> {
    const resultSet = await store.querySql(`PRAGMA table_info(${table})`, []);
    let found = false;
    while (resultSet.goToNextRow()) {
      const name = resultSet.getString(resultSet.getColumnIndex('name'));
      if (name === column) {
        found = true;
        break;
      }
    }
    resultSet.close();
    return found;
  }

  /**
   * Self-heal: ensure diary.title and diary.mood columns exist regardless of migration gate.
   * Idempotent via columnExists guard; safe to call every startup. Fixes devices where
   * store.version was already DATABASE_VERSION but the columns were never added (crashed mid-migration).
   */
  private static async ensureDiaryColumns(store: relationalStore.RdbStore): Promise<void> {
    const hasTitle: boolean = await DatabaseHelper.columnExists(store, 'diary', 'title');
    if (!hasTitle) {
      await store.executeSql('ALTER TABLE diary ADD COLUMN title TEXT');
      hilog.info(0x0000, TAG, 'Self-heal: added diary.title');
    }
    const hasMood: boolean = await DatabaseHelper.columnExists(store, 'diary', 'mood');
    if (!hasMood) {
      await store.executeSql('ALTER TABLE diary ADD COLUMN mood TEXT');
      hilog.info(0x0000, TAG, 'Self-heal: added diary.mood');
    }
    // fix: MAIN-001 · todo.category 自愈补列（DEV-003 本地增量：旧库无此列 → TodoDao.insert 报 14800021 加不了待办）
    const hasCategory: boolean = await DatabaseHelper.columnExists(store, 'todo', 'category');
    if (!hasCategory) {
      await store.executeSql("ALTER TABLE todo ADD COLUMN category TEXT NOT NULL DEFAULT '日常'");
      hilog.info(0x0000, TAG, 'Self-heal: added todo.category');
    }
  }

  /**
   * fix: DEV-013 · todo 提醒增强 6 列自愈补列（沿用 todo.category 自愈先例）。
   * columnExists PRAGMA 守卫幂等，每次启动安全重跑；不受 store.version gate（防病态库列缺失崩溃）。
   * 列口径与 TodoItem 模型一一对应：
   *   due_date TEXT / due_time TEXT / location TEXT — 可空；
   *   custom_tags TEXT NOT NULL DEFAULT '[]' — JSON 数组字符串（先例：diary.images）；
   *   remind_at INTEGER / reminder_id INTEGER — 可空（无提醒/未调度）。
   */
  private static async ensureTodoReminderColumns(store: relationalStore.RdbStore): Promise<void> {
    const hasDueDate: boolean = await DatabaseHelper.columnExists(store, 'todo', 'due_date');
    if (!hasDueDate) {
      await store.executeSql('ALTER TABLE todo ADD COLUMN due_date TEXT');
      hilog.info(0x0000, TAG, 'Self-heal: added todo.due_date');
    }
    const hasDueTime: boolean = await DatabaseHelper.columnExists(store, 'todo', 'due_time');
    if (!hasDueTime) {
      await store.executeSql('ALTER TABLE todo ADD COLUMN due_time TEXT');
      hilog.info(0x0000, TAG, 'Self-heal: added todo.due_time');
    }
    const hasLocation: boolean = await DatabaseHelper.columnExists(store, 'todo', 'location');
    if (!hasLocation) {
      await store.executeSql('ALTER TABLE todo ADD COLUMN location TEXT');
      hilog.info(0x0000, TAG, 'Self-heal: added todo.location');
    }
    const hasCustomTags: boolean = await DatabaseHelper.columnExists(store, 'todo', 'custom_tags');
    if (!hasCustomTags) {
      await store.executeSql("ALTER TABLE todo ADD COLUMN custom_tags TEXT NOT NULL DEFAULT '[]'");
      hilog.info(0x0000, TAG, 'Self-heal: added todo.custom_tags');
    }
    const hasRemindAt: boolean = await DatabaseHelper.columnExists(store, 'todo', 'remind_at');
    if (!hasRemindAt) {
      await store.executeSql('ALTER TABLE todo ADD COLUMN remind_at INTEGER');
      hilog.info(0x0000, TAG, 'Self-heal: added todo.remind_at');
    }
    const hasReminderId: boolean = await DatabaseHelper.columnExists(store, 'todo', 'reminder_id');
    if (!hasReminderId) {
      await store.executeSql('ALTER TABLE todo ADD COLUMN reminder_id INTEGER');
      hilog.info(0x0000, TAG, 'Self-heal: added todo.reminder_id');
    }
    // 待触发提醒查询索引（冷启动恢复 queryPendingReminders 使用；IF NOT EXISTS 幂等）
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_todo_remind_at ON todo(remind_at)');
  }

  /**
   * DEV+HUI · account 表自愈守卫（幂等，自愈安全）。
   * 由 initialize 启动自愈调用（不受版本号 gate，防 version 已写但表缺失的病态库崩溃）。
   */
  private static async ensureAccountTable(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(DatabaseHelper.DDL_CREATE_ACCOUNT);
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_account_uid ON account(uid)');
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_account_logged_in ON account(is_logged_in)');
    hilog.info(0x0000, TAG, 'Self-heal: account table ensured');
  }

  /**
   * Check whether a table exists (used for fresh-install detection before baseline creation).
   */
  private static async tableExists(store: relationalStore.RdbStore, table: string): Promise<boolean> {
    const sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=?";
    const resultSet = await store.querySql(sql, [table]);
    const found = resultSet.goToFirstRow();
    resultSet.close();
    return found;
  }

  /**
   * Get the underlying RdbStore instance (for DAO use via DatabaseExecutor)
   */
  getStore(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('Database not initialized. Call initialize() first.');
    }
    return this.store;
  }

  /**
   * Get database version
   */
  getVersion(): number {
    return DatabaseHelper.DATABASE_VERSION;
  }

  /**
   * Release database resources
   */
  async close(): Promise<void> {
    if (this.store) {
      await this.store.close();
      this.store = null;
      this.initialized = false;
      hilog.info(0x0000, TAG, 'Database closed');
    }
  }
}
