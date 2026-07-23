<!-- agentID: ARC-001 -->
# 数据库设计文档：电子日记本 HuaweiDiary（鸿蒙原生）

> 目标平台：HarmonyOS NEXT · SDK 6.1.1（API 24）
> 存储引擎：`@ohos.data.relationalStore`（RelationalStore / RdbStore，SQLite 内核）
> 数据库文件：`HuaweiDiary.db` · `securityLevel: S2` · `journal_mode=WAL`
> 定位：**在现有 10 表 + 10 DAO（基础功能 100% 覆盖）之上做完善、补缺口、建版本迁移机制**，不推翻既有设计
> 唯一真相源：现有 `DatabaseHelper.ets` 建表 DDL（PROJECT_SPEC / 架构 §5.0 裁决：数据事实以 DDL 为准）

---

## 0. 元信息与验证声明

### 0.1 强制 Skill 调用
- 本任务为**后端数据持久层设计**，无新增 UI 设计面；按角色规范说明：`frontend-design` / `ui-ux-pro-max` 沿用既有主题/组件契约，本文不产出 UI 稿。

### 0.2 华为官方 API 权威验证（据 PROJECT_SPEC §十：本地 .d.ts = API 24 唯一真相，胜过网页文档）
- 校验文件：`D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\ets\api\@ohos.data.relationalStore.d.ts`（API 24）。
- 关键结论（逐条 grep 核实）：

| 核实项 | 本地 .d.ts 事实（行号） | 对设计的影响 |
|--------|------------------------|--------------|
| `StoreConfig` 字段（非穷举）| `name / securityLevel / encrypt? / dataGroupId? / customDir? / rootDir? / autoCleanDirtyData? / allowRebuild? / vector? / isReadOnly? / pluginLibs? / cryptoParam? ...`（:286-405）| **`StoreConfig` 里没有 `onUpgrade` 回调** |
| `onUpgrade / onCreate / onDowngrade` | **全文件 grep 零命中** | 🔴 HarmonyOS RelationalStore **不提供** Android 式 `onUpgrade(db, old, new)` 回调；迁移必须应用侧手动做 |
| `RdbStore.version` | `version: number`（可读可写属性，since 10/12，:4515；setter 注释「must be an integer greater than 0」，:4492）| ✅ 版本管理靠**读写 `store.version` 属性**（get 取旧版本、set 写新版本）；🔴 **禁止写 `store.version = 0`**（setter 要求 >0），基线用逻辑常量 1 表示，物理 0 只读不写 |
| `RdbStore.executeSql` | `executeSql(sql, bindArgs?): Promise<void>`（:6471）| ✅ 执行 `ALTER TABLE` / `CREATE TABLE` / `PRAGMA` 的异步入口 |
| `RdbStore.backup / restore` | `backup(destName): Promise<void>`（:6905）/ `restore(srcName): Promise<void>`（:7011）| ✅ 迁移前可整库备份，失败可回滚整库 |
| `getRdbStore` | `getRdbStore(context, config): Promise<RdbStore>`（:9198）| ✅ 现有初始化用法正确 |

> ⚠️ **对架构方案 §5.4 的更正**：架构方案-HuaweiDiary.md §5.4 给出的 `onUpgrade(db, oldVersion, newVersion){...}` 示例是 **Android SQLiteOpenHelper 的范式，不适用于 HarmonyOS**。API 24 的 `StoreConfig` 无此回调项。本文档给出符合 API 24 真相的**基于 `store.version` 属性 + 手动步进迁移**的正确方案（见 §5）。
> 引用章节（官方文档对应）：华为开发者文档 → 应用框架 → 数据管理 → 关系型数据库（RelationalStore）→「数据库的备份、恢复与版本升级」/「RdbStore.version」。本次 dokobot 本地 bridge 未运行且 search 需远程 API Key（不可用），故以本地 SDK .d.ts 为最终裁决依据（符合 §十 优先级：本地 .d.ts > 网页文档）。

### 0.3 交付范围
- ✅ 出：数据库设计文档（schema、缺口设计、迁移机制、覆盖核对、ER）。
- ❌ 不出：任何 `.ets` 实现代码改动；本文的 DDL/迁移片段为**设计规格**，供 DEV 实现，非本人落地。

---

## 1. 设计原则与强制规范对齐（PROJECT_SPEC §8.2 数据库）

| 规范 | 现状核实 | 本设计遵守方式 |
|------|---------|----------------|
| 类型只用 `INTEGER`，**禁 FLOAT/REAL** | 现有 10 表 grep 无 `REAL/FLOAT`；`actual_seconds`/`priority`/`duration_minutes` 均 `INTEGER` | 新增字段一律 `TEXT`/`INTEGER`；秒/分/优先级用 `INTEGER` |
| `boolean` 存 `number`(0/1) | `completed`/`is_visible`/`is_builtin`/`is_converted` 均 `INTEGER DEFAULT 0/1` | 新增布尔（如 `custom_emoji.is_builtin`）用 `INTEGER 0/1` |
| 日期/时间统一格式 | 日期列 `date TEXT` = `"YYYY-MM-DD"`；时间列 `task_time TEXT` = `"HH:mm"`；时间戳列 `*_at INTEGER` = `Date.now()` 毫秒 epoch | 新增字段沿用同约定（见 §3.2） |
| 表名/字段命名风格 | 表名 `snake_case` 单数（`happy_thing`）；列名 `snake_case`；布尔前缀 `is_`；时间戳后缀 `_at` | 新增表/列严格沿用（`custom_emoji`、`diary.title`、`diary.mood`） |
| 建表方式 | 全部 `CREATE TABLE IF NOT EXISTS` 原始 SQL（非 `ColumnType` table-config API）| §8.2 的 `ColumnType.INTEGER` 语义映射为 SQL `INTEGER`；迁移用 `executeSql` 原始 SQL 保持一致 |

> 说明：现有工程用**原始 SQL DDL**（`store.executeSql('CREATE TABLE ...')`）而非 `relationalStore` 的 `ColumnType` 结构化建表 API，故不存在 `ColumnType.FLOAT` 误用面；`ColumnType.INTEGER` 规范在此语境下等价于「SQL 数值列一律 INTEGER，不用 REAL」。

---

## 2. 现有 10 表完整 Schema 梳理（唯一真相源 · 逐表）

> 来源：`shared/src/main/ets/database/DatabaseHelper.ets` DDL_CREATE_TABLES（表 1-10）+ DDL_CREATE_INDEXES（9 索引）。类型/约束/默认值均照实抄录。

### 表1 · diary（日记表）
| 列 | SQL 类型 | 约束 / 默认 | 含义 |
|----|---------|-------------|------|
| id | INTEGER | PK AUTOINCREMENT | 主键 |
| date | TEXT | UNIQUE NOT NULL | 日记日期 `"YYYY-MM-DD"`（每天最多一条）|
| content | TEXT | 可空 | 日记正文 |
| images | TEXT | DEFAULT `'[]'` | 图片 URI 的 JSON 字符串数组；DAO/模型层 `JSON.parse/stringify` 转 `string[]` |
| created_at | INTEGER | NOT NULL | 创建时间戳（ms epoch）|
| updated_at | INTEGER | NOT NULL | 更新时间戳（ms epoch）|

- 索引：`date` 由 `UNIQUE` 隐式建唯一索引。
- DAO（DiaryDao）：`insert`、`queryByDate`、`queryByMonth`、`search`（`content LIKE`）、`update`、`queryDatesWithDiary`。**缺 `queryAll`、`delete`（见 §4 缺口#3/#4）**。
- 关联：与 `check_in`/`todo`/`happy_thing`/`extra_thing` 通过 `date` 逻辑关联（同一天聚合展示）。

### 表2 · check_in（打卡签到表）
| 列 | SQL 类型 | 约束 / 默认 | 含义 |
|----|---------|-------------|------|
| id | INTEGER | PK AUTOINCREMENT | 主键 |
| date | TEXT | UNIQUE NOT NULL | 打卡日期 `"YYYY-MM-DD"` |
| created_at | INTEGER | NOT NULL | 打卡时间戳 |

- 语义：**行存在 = 该日已打卡**（无 `is_checked` 列）；撤销打卡 = `deleteByDate` 删行。
- DAO（CheckInDao）：`insert`、`exists`、`queryStreak`（遍历倒序算连续天数，跨月跨年断签正确）、`queryByMonth`、`deleteByDate`。

### 表3 · todo（待办表）
| 列 | SQL 类型 | 约束 / 默认 | 含义 |
|----|---------|-------------|------|
| id | INTEGER | PK AUTOINCREMENT | 主键 |
| date | TEXT | NOT NULL | 关联日期 `"YYYY-MM-DD"` |
| type | TEXT | NOT NULL DEFAULT `'today'` | `'today'` / `'tomorrow'` |
| title | TEXT | NOT NULL | 待办内容 |
| completed | INTEGER | NOT NULL DEFAULT 0 | 是否完成 (0/1) |
| sort_order | INTEGER | NOT NULL DEFAULT 0 | 分组内排序序号 |
| source_task_id | INTEGER | 可空 | 来源提取任务 id（NULL=手动创建）|
| created_at | INTEGER | NOT NULL | 创建时间戳 |
| updated_at | INTEGER | NOT NULL | 更新时间戳 |

- 索引：`idx_todo_date_type(date,type)`、`idx_todo_source_task(source_task_id)`。
- DAO（TodoDao）：`insert`、`update`、`delete`、`queryByDateAndType`、`toggleComplete`、`searchByTitle`、`queryBySourceTaskId`、`getMaxSortOrder`（最完整 CRUD）。
- 关联：`source_task_id → extracted_task.id`（逻辑外键，来源提取任务）。

### 表4 · happy_thing（开心的事表）
| 列 | SQL 类型 | 约束 / 默认 | 含义 |
|----|---------|-------------|------|
| id | INTEGER | PK AUTOINCREMENT | 主键 |
| date | TEXT | NOT NULL | 关联日期 |
| content | TEXT | NOT NULL | 文字内容 |
| emoji_id | TEXT | NOT NULL | 心情 emoji 标识（本设计中逻辑指向 `custom_emoji.emoji_key`，见 §4 缺口#8）|
| image | TEXT | 可空 | 图片沙箱 URI |
| created_at | INTEGER | NOT NULL | 创建时间戳 |

- 索引：`idx_happy_thing_date(date)`。
- DAO（HappyThingDao）：`insert`、`delete`、`queryByDate`、`searchByContent`、`countByEmoji`（统计心情分布）。

### 表5 · extra_thing（多做的事表）
| 列 | SQL 类型 | 约束 / 默认 | 含义 |
|----|---------|-------------|------|
| id | INTEGER | PK AUTOINCREMENT | 主键 |
| date | TEXT | NOT NULL | 关联日期 |
| content | TEXT | NOT NULL | 事项内容 |
| created_at | INTEGER | NOT NULL | 创建时间戳 |

- 索引：`idx_extra_thing_date(date)`。
- DAO（ExtraThingDao）：`insert`、`delete`、`queryByDate`、`searchByContent`。

### 表6 · extracted_task（提取任务表）
| 列 | SQL 类型 | 约束 / 默认 | 含义 |
|----|---------|-------------|------|
| id | INTEGER | PK AUTOINCREMENT | 主键 |
| source | TEXT | NOT NULL | 来源 `'share'/'clipboard'/'voice'/'floating'` |
| category | TEXT | NOT NULL DEFAULT `'general'` | 分类 `'exam'/'homework'/'meeting'/'deadline'/'general'` |
| title | TEXT | NOT NULL | 任务标题 |
| description | TEXT | 可空 | 原始文本 / 补充描述 |
| task_date | TEXT | 可空 | 提取的任务日期 `"YYYY-MM-DD"` |
| task_time | TEXT | 可空 | 提取的任务时间 `"HH:mm"` |
| location | TEXT | 可空 | 提取的活动地点 |
| priority | INTEGER | 可空 | 提取的优先级 |
| is_converted | INTEGER | NOT NULL DEFAULT 0 | 是否已转待办 (0/1) |
| converted_todo_id | INTEGER | 可空 | 关联的待办 id |
| created_at | INTEGER | NOT NULL | 创建时间戳 |

- 索引：`idx_extracted_task_converted(is_converted)`、`idx_extracted_task_created(created_at)`。
- DAO（ExtractedTaskDao）：`insert`、`convertToTodo`（回写 `is_converted=1`+`converted_todo_id`）、`queryUnconverted`、`queryBySource`、`queryAll(limit,offset)`、`searchByTitle`、`delete`。
- 关联：`converted_todo_id → todo.id`（与 `todo.source_task_id` 构成双向关联 1:1）。

### 表7 · quote（名言表）
| 列 | SQL 类型 | 约束 / 默认 | 含义 |
|----|---------|-------------|------|
| id | INTEGER | PK AUTOINCREMENT | 主键 |
| content | TEXT | NOT NULL | 名言内容 |
| author | TEXT | NOT NULL DEFAULT `'Unknown'` | 作者 |
| is_builtin | INTEGER | NOT NULL DEFAULT 1 | 是否内置 (0/1) |
| last_shown_date | TEXT | 可空 | 上次展示日期（实现「同日不重复」）|
| created_at | INTEGER | NOT NULL | 创建时间戳 |

- 索引：`idx_quote_last_shown(last_shown_date)`。
- DAO（QuoteDao）：`random(excludeDate)`（同日不重复随机）、`insertCustom`、`markShown`、`batchInsert`（120 条内置种子）、`count`。

### 表8 · pomodoro_session（番茄钟会话表）
| 列 | SQL 类型 | 约束 / 默认 | 含义 |
|----|---------|-------------|------|
| id | INTEGER | PK AUTOINCREMENT | 主键 |
| date | TEXT | NOT NULL | 会话日期 |
| preset_type | TEXT | NOT NULL DEFAULT `'focus'` | `'focus'/'short_break'/'long_break'` |
| duration_minutes | INTEGER | NOT NULL | 预设时长（分钟）|
| actual_seconds | INTEGER | 可空 | 实际计时秒数 |
| completed | INTEGER | NOT NULL DEFAULT 0 | 是否完成 (0/1) |
| created_at | INTEGER | NOT NULL | 开始时间戳 |
| ended_at | INTEGER | 可空 | 结束时间戳 |

- 索引：`idx_pomodoro_date_type(date,preset_type)`。
- DAO（PomodoroDao）：`insert`、`queryByDateRange`、`countCompleted`、`sumFocusSeconds`。**表已含 `actual_seconds/completed/ended_at`，但缺回写方法（见 §4 缺口#5）**。

### 表9 · section_config（分区配置表）
| 列 | SQL 类型 | 约束 / 默认 | 含义 |
|----|---------|-------------|------|
| id | INTEGER | PK AUTOINCREMENT | 主键 |
| section_key | TEXT | UNIQUE NOT NULL | 分区标识 `'today_todo'/'tomorrow_todo'/'extra'/'happy'/'extracted'` |
| title | TEXT | NOT NULL | 自定义标题 |
| is_visible | INTEGER | NOT NULL DEFAULT 1 | 是否显示 (0/1) |
| sort_order | INTEGER | NOT NULL | 排序位置 |
| updated_at | INTEGER | NOT NULL | 更新时间戳 |

- 索引：`idx_section_config_sort(sort_order)`。
- DAO（SectionConfigDao）：`loadAll`、`saveAll`（事务 upsert）、`deleteByKey`。

### 表10 · app_settings（应用设置表 · KV）
| 列 | SQL 类型 | 约束 / 默认 | 含义 |
|----|---------|-------------|------|
| id | INTEGER | PK AUTOINCREMENT | 主键 |
| key | TEXT | UNIQUE NOT NULL | 设置键 |
| value | TEXT | NOT NULL | 设置值（纯文本或 JSON 字符串）|
| updated_at | INTEGER | NOT NULL | 更新时间戳 |

- 索引：`key` 由 `UNIQUE` 隐式建唯一索引。
- DAO（AppSettingsDao）：`get`、`set`（upsert）、`delete`、`getAll`、`getTyped<T>`、`setTyped`、`batchSet`（事务）。
- 用途：提醒开关/时间/方式、字体大小、手势灵敏度、PIN（加密串）、锁定状态等散设置的统一 KV 落库。

### 2.1 现有索引全清单（9 条 · 照实）
```
idx_todo_date_type            ON todo(date, type)
idx_todo_source_task          ON todo(source_task_id)
idx_happy_thing_date          ON happy_thing(date)
idx_extra_thing_date          ON extra_thing(date)
idx_extracted_task_converted  ON extracted_task(is_converted)
idx_extracted_task_created    ON extracted_task(created_at)
idx_quote_last_shown          ON quote(last_shown_date)
idx_pomodoro_date_type        ON pomodoro_session(date, preset_type)
idx_section_config_sort       ON section_config(sort_order)
```
（`diary.date` / `check_in.date` / `app_settings.key` / `section_config.section_key` 的唯一索引由 `UNIQUE` 约束隐式创建。）

---

## 3. 全库通用约定（供新增字段/表复用）

### 3.1 主键与自增
- 一律 `id INTEGER PRIMARY KEY AUTOINCREMENT`。

### 3.2 类型与格式约定（新增字段必须遵守）
| 语义 | SQL 列类型 | 取值格式 | 示例 |
|------|-----------|---------|------|
| 日期 | `TEXT` | `"YYYY-MM-DD"`（本地时区，`DateUtils`/`formatLocalDate` 生成）| `"2026-07-11"` |
| 时间 | `TEXT` | `"HH:mm"` | `"09:30"` |
| 时间戳 | `INTEGER` | `Date.now()` 毫秒 epoch | `1752230400000` |
| 布尔 | `INTEGER` | `0` / `1`，默认写 `DEFAULT 0` 或 `1` | `completed INTEGER NOT NULL DEFAULT 0` |
| 结构化集合 | `TEXT` | JSON 字符串，DAO 层转换 | `images '["uri1"]'` |
| 计数/秒/分/优先级 | `INTEGER` | 整数（**禁 REAL**）| `actual_seconds 1487` |

### 3.3 关系耦合方式（重要）
- 现有 10 表**未声明任何 SQL `FOREIGN KEY ... REFERENCES`**；`PRAGMA foreign_keys=ON` 虽开启但因无 FK 列声明而实际不生效。
- 表间关系全部为**逻辑关联**：日期聚合用 `date` 字符串匹配；任务↔待办用 `source_task_id`/`converted_todo_id` 的 id 匹配。
- **本设计延续此松耦合策略**（不引入硬 FK 约束），原因：① 避免删除父行受阻导致运行时异常；② 与既有 DAO 全部按值查询的实现一致；③ 迁移 `ALTER TABLE` 更安全（SQLite 对含 FK 的表 ALTER 有额外限制）。引用完整性由 DAO/ViewModel 层保证。

---

## 4. 8 个缺口的设计（在现有基础上补全）

> 汇总：**需改 schema 的仅 2 类**（diary 加 2 列；新增 custom_emoji 表），其余为 **DAO 方法层 / KV 键层** 补全（不动表结构）。所有 schema 变更由 §5 的 v1→v2 迁移承载。

### 缺口#1、#2 · diary 表新增 `title`、`mood` 字段
- 背景：前端日记轮播 T-FEAT-001 需要标题；统计「心情分布」需按日绑定心情。
- 设计（`ALTER TABLE`，非重建）：
```sql
ALTER TABLE diary ADD COLUMN title TEXT;         -- 日记标题，可空（老数据 NULL，前端兜底用正文首行/日期）
ALTER TABLE diary ADD COLUMN mood  TEXT;         -- 当日心情标识，可空；逻辑指向 custom_emoji.emoji_key 或内置心情键
```
- 约束选择：均**可空（不加 NOT NULL / DEFAULT）**。理由：`ALTER TABLE ADD COLUMN` 对既有行按 NULL 填充；若加 `NOT NULL` 而不给 `DEFAULT` 会导致既有行冲突。老数据语义安全。
- 模型对齐（供 DEV）：`data/Diary.ets` 增 `title: string = ''`、`mood: string = ''`；`DiaryDao.rowToDiary` 增 `isColumnNull` 判空读取；`insert/update` 的 valueBucket 增两键。
- 索引（统计场景 · 已采纳审判建议4，由「可选」提为**必建**）：`CREATE INDEX IF NOT EXISTS idx_diary_mood ON diary(mood);`。理由：需求 §8「心情分布柱状图」按 mood 分组聚合属高频统计查询，数据量增大后无索引会全表扫描退化。

### 缺口#3、#4 · DiaryDao 补 `queryAll`、`delete`（表层已支持，仅补方法）
- **无需改表**：diary 表结构已足够；补的是 DAO 查询/删除方法（设计签名，供 DEV 实现）：
  - `queryAll(): Promise<Diary[]>` → `SELECT * FROM diary ORDER BY date DESC`（日记轮播「全部日记倒序」）。
  - `deleteById(id: number): Promise<number>` → `predicates.equalTo('id', id)` + `store.delete`。
  - `deleteByDate(date: string): Promise<number>` → 与 `check_in.deleteByDate` 同风格，删整篇日记。
- 关联清理约定（DAO/VM 层，非 FK）：删日记时是否级联删除同日 happy_thing/extra_thing/todo 由业务决定；**建议默认不级联**（日记与打卡/待办是独立实体，仅同日展示），只删 diary 行。

### 缺口#5 · 番茄钟 `actual_seconds` / `completed` / `ended_at` 回写
- **无需改表**：三列 DDL 已存在。缺的是回写方法 + VM 调用。
- 设计补 DAO 方法（供 DEV 实现）：
  - `finishSession(id: number, actualSeconds: number, completed: number, endedAt: number): Promise<void>`
    → `update({actual_seconds, completed, ended_at}, predicates.equalTo('id', id))`。
- 语义规范：`insert` 在 start 时先落一行（`actual_seconds=NULL, completed=0, ended_at=NULL`）→ stop/onComplete 时 `finishSession` 回写实际秒数、完成标志、结束时间。回写后 `sumFocusSeconds`/`countCompleted` 才能取到真实值（修复审计 §4#5）。

### 缺口#6 · 昵称持久化（用 app_settings，不新增表）
- 设计：落 `app_settings` 一个键，**不建新表**。
  - key：`app_user_nickname`（沿用现有会话键名，统一到 DB 层持久化）
  - value：昵称字符串（纯文本）
  - 读写：`AppSettingsDao.get('app_user_nickname')` / `set('app_user_nickname', name)`。
- 效果：重启不丢（修复审计 §4#6「仅存 AppStorage 会话级」）。
- 附带建议（同为资料区，可一并纳入 KV，避免为每项建列）：`app_user_avatar`（头像 URI）等资料项同法入 `app_settings`。

### 缺口#8 · 自定义 emoji 库持久化（新增表 custom_emoji）
- 背景：需求 §3「心情 emoji 可自定义导入添加」；现 `happy_thing` 只存单条 `emoji_id`，未存**用户导入的 emoji 集合**。
- 决策：**新增独立表 `custom_emoji`**（优于塞 app_settings JSON）。理由：emoji 是可增删排序、需按序展示的**结构化集合**，独立表便于排序/唯一约束/查询，且 `happy_thing.emoji_id` 可逻辑指向其 `emoji_key`。
- 设计 DDL（已采纳审判建议1「type 改 TEXT」+ 建议2「补 updated_at」）：
```sql
CREATE TABLE IF NOT EXISTS custom_emoji (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  emoji_key   TEXT UNIQUE NOT NULL,          -- 唯一标识；被 happy_thing.emoji_id 逻辑引用。★内置项须=现有 emoji 原始字符（见下「值域对齐红线」）
  label       TEXT NOT NULL,                 -- 心情标签/显示名（如「开心」「难过」）
  type        TEXT NOT NULL DEFAULT 'emoji', -- 'emoji'=Unicode表情字符 / 'image'=用户导入图片（TEXT 枚举，贴合 todo.type/extracted_task.source 等惯例）
  value       TEXT NOT NULL,                 -- type='emoji':表情字符（与 emoji_key 同值）; type='image':图片沙箱URI
  sort_order  INTEGER NOT NULL DEFAULT 0,    -- 展示排序
  is_builtin  INTEGER NOT NULL DEFAULT 0,    -- 是否内置默认emoji (0/1)
  created_at  INTEGER NOT NULL,              -- 创建时间戳
  updated_at  INTEGER NOT NULL               -- 更新时间戳（支持 updateSort，与 todo/diary/section_config 可变行表一致）
);
CREATE INDEX IF NOT EXISTS idx_custom_emoji_sort ON custom_emoji(sort_order);
```
- 🔴 **值域对齐红线（审判必改2 · 已去源码核实）**：`happy_thing.emoji_id` 现存的是**原始 Unicode 表情字符**（如 `😊`、`⭐`），**非符号键**。证据链（源码逐环核实）：
  - `EmojiPicker.onSelect(emoji: string)` 回传的是**原始 emoji 字符**——取自 5 分类（mood/activity/food/animal/nature）共 100 个原始字符网格（`EmojiPicker.ets:25-76` 的 `EMOJI_CATEGORIES`、`:141-143` `onSelect(emoji)`）；
  - `HappyThingViewModel.add(content, emojiId, image?)` 直接 `new HappyThing(date, content, emojiId)` 原样落库，**无任何键化转换**（`HappyThingViewModel.ets:33-39`）；
  - `HappyThingItem` 直接 `Text(this.emoji)` 渲染该字符（`HappyThingItem.ets:60`）。
  - ⇒ **`emoji_id` 值域 = 那 100 个原始 emoji 字符**。
  - **对齐要求**：`seedBuiltins()` 的内置行必须满足 `emoji_key = value = 原始 emoji 字符`、`type='emoji'`、`is_builtin=1`，且 `emoji_key` 集合 ⊇ 现有 EmojiPicker 100 字符集。如此存量 `happy_thing.emoji_id` 可直接 join 到 `custom_emoji.emoji_key`，**老数据心情不丢**。
  - 若产品未来改用符号键（如 `mood_happy`）：必须配套一次性**数据回填**（把老 `emoji_id` 原始字符映射为新键），否则历史「开心的事」emoji 变空/错位。**本设计采「emoji_key = 原始字符」路线规避回填**。
  - 用户导入图片项：`emoji_key` 用生成的稳定键（如 `img_<createdAt>`），`value` = 图片沙箱 URI，`type='image'`，`is_builtin=0`。
- DAO（供 DEV 实现，设计签名）：`CustomEmojiDao` → `queryAll()`（按 sort_order 升序）、`insert(emoji)`、`delete(id)`、`updateSort(configs)`、`seedBuiltins()`（首次内置默认心情集，emoji_key 须对齐上文值域）。
- 关联：`happy_thing.emoji_id (=原始字符=emoji_key) → custom_emoji.emoji_key`（逻辑关联，N:1）。
- 备选（若产品简化为「只存一组用户 emoji、不需排序/统计」）：退化为 `app_settings` 键 `app_custom_emoji`（JSON 数组），`setTyped/getTyped` 读写。**本设计推荐独立表**，备选留档。

### 4.1 缺口设计小结（改动矩阵）
| # | 缺口 | 改 schema? | 承载方式 | 版本 |
|---|------|-----------|---------|------|
| 1 | diary.title | ✅ | `ALTER TABLE diary ADD COLUMN title TEXT` | v2 |
| 2 | diary.mood | ✅ | `ALTER TABLE diary ADD COLUMN mood TEXT` | v2 |
| 3 | DiaryDao.queryAll | ❌ | 新增 DAO 方法（表已支持）| — |
| 4 | DiaryDao.delete | ❌ | 新增 DAO 方法（表已支持）| — |
| 5 | 番茄钟回写 | ❌ | 新增 `PomodoroDao.finishSession`（列已存在）| — |
| 6 | 昵称持久化 | ❌ | `app_settings` 键 `app_user_nickname` | — |
| 8 | 自定义 emoji 库 | ✅ | 新增表 `custom_emoji` + 索引 | v2 |
| 7 | **DB 版本迁移机制** | ✅（机制）| 见 §5（本次核心）| — |

> 结论：**总表数 10 → 11**（新增 `custom_emoji`）；**改动表 1 个**（diary 加 title/mood 两列）；DAO 层补 4 处方法；KV 补 1 键。

---

## 5. 🔴 DB 版本迁移机制（本次核心缺口）

### 5.1 现状问题（为什么必须建）
- `DatabaseHelper.DATABASE_VERSION = 1` 只是 **JS 常量，从未写入数据库**（初始化只跑 `CREATE TABLE IF NOT EXISTS` + 建索引，从不 `store.version = ...`）。
- 因此**所有已安装设备上 `store.version` 恒为 0**（RelationalStore 新建库默认版本 0，且代码从没 set 过）。
- 只有 `CREATE IF NOT EXISTS` → 加新字段（#1/#2）时**老库不会自动升级**：`CREATE TABLE IF NOT EXISTS diary(... title ...)` 对已存在的 diary 表是**整条无操作**，不会补列 → 老用户库永远缺 title/mood，DAO 读该列报错。这正是审计 §4#7 缺口。

### 5.2 API 24 正确范式（据本地 .d.ts）
HarmonyOS RelationalStore **没有 `onUpgrade` 回调**（§0.2 已证）。正确做法 = **手动版本步进**：
1. `getRdbStore()` 拿到 store（自动建库文件）。
2. 读旧版本 `const oldVersion = store.version`（老库=0）。
3. 若 `oldVersion < CURRENT`：按 `oldVersion → CURRENT` **逐版本**执行迁移 SQL（`ALTER/CREATE`，用 `executeSql`）。
4. 迁移成功后写新版本 `store.version = CURRENT`。
5. 全过程包在事务 + 迁移前 `backup()`，失败 `restore()` 回滚整库。

### 5.3 版本定义
| 版本 | 内容 | 说明 |
|------|------|------|
| **v1（基线，冻结）** | 现有 10 表 + 9 索引（**基线 DDL 保持现状，不内嵌任何 v2 列/表**）| 当前线上 schema。设备上物理 `store.version` 因历史原因为 0，迁移器把「0 或 1」都归一化视为基线 |
| **v2（本次）** | diary 加 `title`/`mood`；新增 `custom_emoji` 表 + `idx_custom_emoji_sort`；新增 `idx_diary_mood`（必建）| 加字段/加表，纯向前兼容，不删不改列。**全部 v2 变更只走迁移器，不写进基线 DDL** |

- `DatabaseHelper.DATABASE_VERSION` 由 `1` → **`2`**。
- 🔴 **基线冻结原则（采纳审判建议5）**：`createBaselineTables` 的 CREATE 语句**冻结在 v1 原始 schema**（diary 不含 title/mood、不建 custom_emoji）。所有 v2 及以后的 schema 变更**只**由迁移器承载。好处：新装库经「基线建 v1 → 迁移器 v1→v2」路径，与老库走**完全相同**的 ALTER/CREATE 路径，`ALTER ADD COLUMN` 在首次运行天然不撞「列已存在」，版本模型清晰。守卫（§5.4）仅为「崩溃自愈重跑」保留。

### 5.4 迁移机制设计（`MigrationManager`，供 DEV 实现 · 本文给设计流程非落地代码）

**核心数据结构**：一张有序「迁移步骤表」，每步 = `{ fromVersion, toVersion, statements: string[] }`，按 `toVersion` 升序注册。

> 🔴 **原子性红线（审判必改1 · 落地必读）**：迁移全程**每一条异步调用都必须显式 `await`**（`backup` / `executeSql` / PRAGMA 查询 / `restore` 逐条 await），确保「DDL 全部完成 → 才写 `store.version`」的严格时序。
> **反例（禁止照抄）**：现有 `DatabaseHelper.ets` 的 `initialize()`（:165-166 `this.store.executeSql('PRAGMA ...')`）与 `createTablesAndIndexes()`（:186-191 循环 `this.store.executeSql(ddl)`）**全部 fire-and-forget（未 await）**。DEV 若沿用该风格实现迁移，会出现「`store.version=2` 在 ALTER 尚未落地前就写入」或「backup 与 DDL 竞态」→ 破坏「成功才升版本」，真机偶发「no such column」且难复现。迁移器**必须逐条 await**，不得沿用现有未 await 写法。

**执行流程（伪流程，说明规则；基线冻结于 v1）**：
```
initialize(context):
  store = await getRdbStore(context, STORE_CONFIG)     // API 24: 无 onUpgrade
  await store.executeSql('PRAGMA journal_mode=WAL')    // ← await（现有代码未 await，反例）
  const isFreshInstall = await notExists(store,'diary')// 迁移前 diary 表是否存在（PRAGMA/查 sqlite_master）
  await createBaselineTables(store)                    // v1 冻结 DDL：CREATE IF NOT EXISTS（不含任何 v2 列/表）
  let old = store.version                              // 老库/新库均=0
  if (old === 0) old = 1                               // 归一化为基线；禁写 store.version=0（setter 要求>0）
  if (old < DATABASE_VERSION):
    const bak = 'HuaweiDiary.pre_v' + old + '.bak'
    if (!isFreshInstall):                              // 真正新装无需备份（建议6：省一次 backup）
      await store.backup(bak)                          // 迁移前整库备份（.d.ts:6905）· 必 await
    try:
      store.beginTransaction()
      for step in MIGRATIONS where step.toVersion > old:    // 逐版本步进
        for sql in step.statements:
          await guardedExec(store, sql)               // 每条 DDL 必 await（含内部 PRAGMA 查询 await）
      store.commit()
      store.version = DATABASE_VERSION                // 全部 await 完成后才写版本（.d.ts:4515，值恒>0）
      if (!isFreshInstall): await deleteFile(bak)     // 成功后清理备份（建议6：不留冗余库文件）
    catch e:
      store.rollBack()
      if (!isFreshInstall): await store.restore(bak)  // 失败回滚整库（.d.ts:7011）· 必 await
      throw e
```

**幂等守卫 `guardedExec`（保留，用于崩溃自愈）**：SQLite **不支持 `ADD COLUMN IF NOT EXISTS`**。基线冻结于 v1 后，首次迁移时 diary 必无 title/mood（新老库都如此），ALTER 天然安全；守卫的价值收敛为**「commit 后、`store.version=2` 写入前崩溃」的重启自愈**——重跑时 diary 已有 title/mood，需靠守卫跳过重复 ALTER。守卫策略二选一：
- **方案A（推荐）· PRAGMA 预检**：`ALTER TABLE diary ADD COLUMN title` 前先 `await store.querySql('PRAGMA table_info(diary)')` 检查是否已有 `title` 列，已有则跳过（PRAGMA 查询同样必 await）。
- **方案B · try/catch 吞重复列错**：捕获「duplicate column name」错误并忽略。
- `CREATE TABLE IF NOT EXISTS custom_emoji` / `CREATE INDEX IF NOT EXISTS` 本身幂等，无需守卫。

### 5.5 v1 → v2 迁移示例（可直接作为迁移步骤规格）
```sql
-- MIGRATION v1 -> v2  (statements, 由 guardedExec 逐条执行 · 每条必 await)
-- 1) diary 加标题（PRAGMA table_info(diary) 无 'title' 时执行）
ALTER TABLE diary ADD COLUMN title TEXT;
-- 2) diary 加心情（PRAGMA table_info(diary) 无 'mood' 时执行）
ALTER TABLE diary ADD COLUMN mood TEXT;
-- 3) 自定义 emoji 库（幂等）· type=TEXT + updated_at（对齐 §4#8 最终 DDL）
CREATE TABLE IF NOT EXISTS custom_emoji (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  emoji_key TEXT UNIQUE NOT NULL,
  label TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'emoji',
  value TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_builtin INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
-- 4) emoji 排序索引（幂等）
CREATE INDEX IF NOT EXISTS idx_custom_emoji_sort ON custom_emoji(sort_order);
-- 5) 心情统计索引（必建，幂等）
CREATE INDEX IF NOT EXISTS idx_diary_mood ON diary(mood);
-- 完成后：seedBuiltins() 灌入内置心情（emoji_key=value=原始字符，见 §4#8 值域对齐红线）
-- 完成后：store.version = 2（值恒 >0；全部 await 落地后才写）
```
数据回填：老 diary 行 `title/mood` 为 NULL —— 前端读取用兜底（标题回退为正文首行或日期，心情回退为空/默认）。番茄钟/昵称无 schema 变更，不在迁移内。

### 5.6 迁移约束与红线（沿用架构 §5.4 精神 + API 24 校正）
- **允许**：`ALTER TABLE ... ADD COLUMN`（加列）、`CREATE TABLE IF NOT EXISTS`（加表）、`CREATE INDEX IF NOT EXISTS`（加索引）。
- **禁止**：`DROP TABLE`、`RENAME TABLE`、`DROP COLUMN`、改列类型 —— 如需重构，走「新表 + 数据迁移 + 切换」而非破坏性 DDL。
- **单向不可逆**：不设计 `onDowngrade`（API 无此回调）；`DATABASE_VERSION` 只增不减。
- **加列必须可空或带 DEFAULT**：避免既有行 `NOT NULL` 冲突（本次 title/mood 取可空）。
- **每步版本自增**：未来 v3 只需追加一个 `{from:2,to:3,...}` 步骤，`DATABASE_VERSION=3`，迁移器自动从任意旧版本步进补齐。

### 5.7 迁移测试策略（供 TST 验收）
1. **老库升级路径**：造一个 v1（0 版）含真实数据的库 → 启动 → 断言 `store.version==2`、diary 有 title/mood 列、custom_emoji 存在、**原有行数与关键字段值不变**；备份 `.bak` 生成且成功后被清理。
2. **新装路径**：全新库 → 启动 → createBaseline 建 v1 冻结 schema（diary **不含** title/mood）→ 迁移器 ALTER 加 title/mood + 建 custom_emoji → `store.version==2`；`isFreshInstall=true` 故**跳过 backup**、无 `.bak`、无「列已存在」崩溃。
3. **失败回滚**：注入一条错误迁移 SQL → 断言 `restore` 后数据与迁移前一致、`store.version` 未推进、`.bak` 处理正确。
4. **重复启动幂等**：连续冷启动两次 → 第二次 `old==2==CURRENT` 直接跳过迁移，无副作用。
5. **崩溃自愈**：模拟「commit 后、`store.version=2` 写入前」中断 → 重启 → old 仍归一化触发 v1→v2 → PRAGMA 守卫跳过已存在的 title/mood、CREATE no-op → `store.version==2`，无「列已存在」崩溃。
6. **emoji 值域对齐**：升级前 happy_thing 存有原始字符 emoji_id（如 `😊`）→ 升级 + `seedBuiltins` 后，断言该 `emoji_id` 能 join 到 `custom_emoji.emoji_key`（老数据心情不丢）。
7. **await 时序**：断言迁移过程中 `store.version` 只在所有 DDL 落地后才变为 2（不出现「版本已升但列未加」的中间态）。

---

## 6. 全功能实体覆盖核对（功能 → 表 映射）

> 对照 `HARMONYOS_REQUIREMENTS.md` 逐功能核对。状态：✅ 已覆盖（现有）/ 🆕 本次新增或补全 / ⚙️ 非 DB 表（Preferences/PersistentStorage）。

| # | 功能需求 | 承载表 / 存储 | 关键字段 | 状态 |
|---|---------|--------------|---------|------|
| 1 | 打卡签到 + 连续天数 | `check_in` | date, created_at（行存在=已打卡）| ✅ |
| 2 | 日记（正文+图片） | `diary` | date, content, images | ✅ |
| 3 | **日记标题（轮播 T-FEAT-001）** | `diary.title` | title | 🆕 v2 加列 |
| 4 | **日记心情 / 统计心情分布** | `diary.mood`（日心情主源）| mood | 🆕 v2 加列 |
| 5 | 日记全部倒序 / 删除 | `diary`（DAO 补 queryAll/delete）| — | 🆕 DAO 方法 |
| 6 | 今日/明日待办（增删改查、完成切换、排序）| `todo` | date, type, title, completed, sort_order | ✅ |
| 7 | 多做的事 | `extra_thing` | date, content | ✅ |
| 8 | 开心的事（文字+emoji+图片，折叠）| `happy_thing` | date, content, emoji_id, image | ✅ |
| 9 | **心情 emoji 自定义导入库** | `custom_emoji`（新表）| emoji_key(=原始字符), label, type('emoji'/'image'), value, sort_order, updated_at | 🆕 v2 新表 |
| 10 | 任务提取（4 来源 + 5 分类 + 时间/地点/优先级）| `extracted_task` | source, category, task_date, task_time, location, priority | ✅ |
| 11 | 提取任务转待办（双向关联）| `extracted_task.converted_todo_id` ↔ `todo.source_task_id` | is_converted, converted_todo_id, source_task_id | ✅ |
| 12 | 番茄钟会话 + 三预设 | `pomodoro_session` | date, preset_type, duration_minutes | ✅ |
| 13 | **番茄钟实际时长/完成回写** | `pomodoro_session`（DAO 补 finishSession）| actual_seconds, completed, ended_at | 🆕 DAO 方法（列已在）|
| 14 | 统计（打卡率/心情/待办完成率/专注时长）| `check_in`+`diary.mood`/`happy_thing`+`todo`+`pomodoro_session` | 聚合查询 | ✅（心情源随 #4 增强）|
| 15 | 名言（120 内置 + 自定义 + 同日不重复）| `quote` | content, author, is_builtin, last_shown_date | ✅ |
| 16 | 分区配置（排序/显隐/自定义标题）| `section_config` | section_key, title, is_visible, sort_order | ✅ |
| 17 | 每日提醒（开关/时间/方式/铃声）| `app_settings`（KV）| key `app_reminder_*` | ✅ |
| 18 | 字体大小三档 | `app_settings`（KV）| key `app_font_size` | ✅ |
| 19 | 手势日记设置（开关/灵敏度/入口）| `app_settings`（KV）| key `app_gesture_*` | ✅ |
| 20 | 安全锁 PIN + 错误次数 | `app_settings`（KV，PIN 加密串）| key `app_pin_*` | ✅ |
| 21 | **用户昵称/头像持久化** | `app_settings`（KV）| key `app_user_nickname` | 🆕 落 KV（原会话级）|
| 22 | 主题（5 预设/深浅色/自定义背景模糊） | ⚙️ Preferences / PersistentStorage | theme_id, is_dark, custom_theme | ⚙️ 非 DB 表 |
| 23 | 高对比开关 | ⚙️ Preferences | app_high_contrast | ⚙️ 非 DB 表 |
| 24 | 数据导出/导入（加密 ZIP，9 表）| 全表（BackupUtils 事务导入）| — | ✅ |
| 25 | 搜索历史（§6.4）| ⚙️ Preferences（store 内键 `search_history`，JSON 数组，cap 5）| — | ⚙️ 非 DB 表（现状已持久化，SearchViewModel）|
| 26 | 浮动书签位置（§1.4 可拖拽调整）| 🆕 `app_settings`（KV）| key `app_bookmark_pos`（JSON `{offsetX,offsetY}`）| 🆕 落 KV（现状仅 `@State`，重启丢失）|

> **心情分布口径澄清（采纳审判建议3）**：统计「心情分布」**以 `diary.mood` 为日心情主源**（每日 1 条，粒度对齐柱状图）；`happy_thing.emoji_id` 仅用于「开心的事」列表逐条展示与 `countByEmoji` 明细，**不与 diary.mood 混算**，避免双源重复计数。DEV 实现统计聚合时以 diary.mood 为准。

> 覆盖结论：**26 项功能实体全部有落点**（原 24 项 + 补录搜索历史/浮动书签位置 2 项）。DB 层新增/补全共 **7 处**：schema 3 处（diary.title、diary.mood、custom_emoji 表）；非 schema/KV 4 处（DiaryDao queryAll/delete、Pomodoro finishSession、nickname KV 键、bookmark KV 键）。搜索历史/主题/高对比属 Preferences 持久化，非 DB 缺口（与审计 §4 注一致）。

---

## 7. ER 关系

### 7.1 关系总览（逻辑关联，非硬 FK）
```
                         app_settings (KV: 提醒/字体/手势/PIN/昵称)   —— 独立，无关联
                         section_config (分区排序/显隐)               —— 独立配置
                         quote (名言, 内置+自定义)                     —— 独立
                         pomodoro_session (番茄钟会话)                 —— 独立(按 date 聚合统计)

            ┌───────────────── date(YYYY-MM-DD) 为逻辑聚合键 ─────────────────┐
            │                                                                 │
      check_in(1/天) ── diary(0..1/天) ── todo(N/天) ── happy_thing(N/天) ── extra_thing(N/天)
            │                │                                │
       行存在=已打卡      title/mood(新)                emoji_id ─┐(逻辑)
                                                                 ▼
                                                        custom_emoji(自定义心情库, N)
                                                          emoji_key = 原始表情字符 (= happy_thing.emoji_id)

      extracted_task(提取任务, N) ──1:1──▶ todo
          converted_todo_id ───────────────┘  (todo.source_task_id 反向指回)
```

### 7.2 关系明细
| 关系 | 基数 | 关联列 | 类型 |
|------|------|--------|------|
| diary ↔ 当天 check_in/todo/happy_thing/extra_thing | 1 : N（按天聚合）| `date` 字符串匹配 | 逻辑关联 |
| check_in ↔ 日期 | 1 : 1（每天最多一条，UNIQUE date）| `date` | 唯一约束 |
| diary ↔ 日期 | 1 : 1（每天最多一条，UNIQUE date）| `date` | 唯一约束 |
| extracted_task ↔ todo | 1 : 1（转待办后）| `converted_todo_id` / `source_task_id` 双向 | 逻辑关联 |
| happy_thing ↔ custom_emoji（新）| N : 1 | `happy_thing.emoji_id` = `custom_emoji.emoji_key`（均为原始表情字符）| 逻辑关联 |
| diary.mood ↔ custom_emoji（新）| N : 1 | `diary.mood` = `custom_emoji.emoji_key`（或内置心情键）| 逻辑关联 |
| quote / pomodoro_session / section_config / app_settings | — | 无跨表关联 | 独立实体 |

> 均为**逻辑关联**（无 SQL FOREIGN KEY 声明，见 §3.3），引用完整性由 DAO/ViewModel 保证。

---

## 8. 落地清单（供 DEV / PLN 排期 · 本文不改代码）

| 项 | 文件 | 动作（设计规格）| 类型 |
|----|------|----------------|------|
| L1 | `DatabaseHelper.ets` | `DATABASE_VERSION` 1→2。**基线 DDL 冻结（采纳建议5）：diary 建表 DDL 不加 title/mood、DDL 数组不加 custom_emoji**——v2 列/表全部由迁移器负责 | schema |
| L2 | `DatabaseHelper.ets` / 新 `migrations/MigrationManager.ets` | 实现 §5.4 版本步进（读/写 `store.version`、backup/restore、guardedExec + PRAGMA 守卫）；注册 v1→v2 步骤。🔴 **全程逐条 `await`（backup/executeSql/PRAGMA 查询/version 写入），禁止照抄现有 initialize 的 fire-and-forget executeSql**；成功后清理 `.bak`、对真正新装跳过 backup；`store.version` 恒 >0 | 机制 |
| L3 | `data/Diary.ets` | 增 `title/mood` 字段 | model |
| L4 | `dao/DiaryDao.ets` | `rowToDiary`/`insert`/`update` 纳入 title/mood；新增 `queryAll`、`deleteById`、`deleteByDate` | DAO |
| L5 | `dao/PomodoroDao.ets` | 新增 `finishSession(id, actualSeconds, completed, endedAt)` | DAO |
| L6 | 新 `data/CustomEmoji.ets` + `dao/CustomEmojiDao.ets` | 自定义 emoji 模型（`type: 'emoji'\|'image'` TEXT、含 `updated_at`）+ `queryAll/insert/delete/updateSort/seedBuiltins`。🔴 `seedBuiltins` 的 `emoji_key` 须 = 现有 EmojiPicker 100 原始字符集（护老数据，见 §4#8） | 新 DAO |
| L7 | `dao/AppSettingsDao.ets`（无需改）| 约定键 `app_user_nickname` 由 SettingsViewModel 读写落库 | KV 约定 |
| L8 | `dao/AppSettingsDao.ets`（无需改）+ `FloatingBookmark`/宿主页 VM | 浮动书签拖拽结束（`onActionEnd`）时把 `{offsetX,offsetY}` `setTyped('app_bookmark_pos', ...)`；`aboutToAppear` 读回。现状仅 `@State` 未持久化 | KV 约定 |

> 表数：10 → **11**（+`custom_emoji`）；索引：9 →（v2）**12**（+`idx_custom_emoji_sort`、+`idx_diary_mood`，均必建）；DAO：10 →（+CustomEmojiDao）**11**。

---

## 9. 引用与验证声明

- **权威真相源**：`@ohos.data.relationalStore.d.ts`（API 24，本机 SDK）—— 已 grep 核实：`StoreConfig` 无 `onUpgrade`、`RdbStore.version:number` 可读写（:4515）、`executeSql(sql,bindArgs?):Promise<void>`（:6471）、`backup(:6905)`/`restore(:7011)`、`getRdbStore(:9198)`。
- **官方文档章节对应**：华为开发者文档 → 应用框架 → 数据管理 → 关系型数据库（RelationalStore）→「数据库版本升级 / 备份恢复」「RdbStore.version」。
- **现状对齐**：现有 10 表 DDL / 10 DAO / 架构 §5.0-§5.4 均已通读，本设计与其字段/命名/类型一致，仅做加法（加 2 列 + 1 表 + 迁移机制 + 4 DAO 方法），不推翻既有设计。
- **审判补充核实（源码逐环，非凭空）**：
  - `emoji_id` 值域：`EmojiPicker.ets`（100 原始 emoji 字符）→ `HappyThingViewModel.ets:33-39`（原样落库）→ `HappyThingItem.ets:60`（`Text(emoji)` 渲染）⇒ 存原始字符。
  - 迁移 await 反例：`DatabaseHelper.ets:165-166 / 186-191` 的 `executeSql` 全部未 await。
  - 搜索历史：`SearchViewModel.ets`（Preferences 键 `search_history`，JSON，cap 5，非 DB 表）。
  - 浮动书签位置：`FloatingBookmark.ets`（`@State offsetX/offsetY`，`onActionEnd` 后不持久化）。
- **规范遵守**：INTEGER 无 FLOAT、boolean=0/1、日期 `YYYY-MM-DD`/时间 `HH:mm`/时间戳 ms epoch、snake_case 命名 —— 全部对齐 PROJECT_SPEC §8.2。
- **dokobot 说明**：本次本地 bridge 未运行、search 需远程 API Key（不可用），已按 PROJECT_SPEC §十「本地 .d.ts > 网页文档」优先级，以本地 SDK 声明为最终裁决依据；该受阻已记入 `workSpace/errors/ARC-001_errors.md`。

---

## 10. 审判补充修订记录（据 JUDGE-001 · v1→v2 文档修订）

> 审判报告：`workSpace/JUDGE-001_review_db_design.md`（结论：通过（有条件））。以下逐条落实，均已写入本文档对应章节。

### 10.1 两项必须补充（已补）
| # | 必改项 | 落实章节 | 补法摘要 |
|---|--------|---------|---------|
| 必改1 | 迁移全程显式 `await` + 原子性红线 | §5.4（红线框）、§5.7（测试#7）、§8 L2 | 明确每条 backup/executeSql/PRAGMA/version 写入必 await；点名现有 `DatabaseHelper.initialize`（:165-166/:186-191）未 await 为**禁止照抄的反例**；保证「DDL 全落地才写 version」 |
| 必改2 | `custom_emoji` 内置 emoji_key 对齐 `happy_thing.emoji_id` 值域 | §4#8（值域对齐红线）、§5.7（测试#6）、§8 L6 | 去源码核实 `emoji_id` 存**原始 Unicode 字符**（EmojiPicker→VM→Item 证据链）；规定 `seedBuiltins` 的 `emoji_key=value=原始字符`、集合⊇现有 100 字符，老数据可直接 join 不丢 |

### 10.2 七项建议评估
| # | 建议 | 处理 | 说明 |
|---|------|------|------|
| 1 | `custom_emoji.type` INTEGER→TEXT | ✅ 采纳 | 改 `TEXT('emoji'/'image')`，贴合 todo.type/extracted_task.source 等 TEXT 枚举惯例（§4#8、§5.5） |
| 2 | `custom_emoji` 补 `updated_at` | ✅ 采纳 | 加 `updated_at INTEGER`，与 todo/diary/section_config 可变行表一致（§4#8、§5.5） |
| 3 | 心情分布双源口径歧义 | ✅ 采纳 | 明确统计**以 `diary.mood` 为日心情主源**，`happy_thing.emoji_id` 仅列表展示不混算（§6 口径澄清脚注） |
| 4 | `idx_diary_mood` 可选→必建 | ✅ 采纳 | 提为必建（§4#1-2、§5.3、§5.5、§8 计数） |
| 5 | baseline 不内嵌 v2 列（守卫降为非强依赖）| ✅ 采纳 | 基线 DDL 冻结在 v1，所有 v2 变更只走迁移器；守卫保留用于崩溃自愈（§5.3、§5.4、§8 L1） |
| 6 | 迁移备份文件清理 | ✅ 采纳 | 成功后删 `.bak`；真正新装跳过 backup（§5.4 流程、§5.7 测试#1-2） |
| 7 | 覆盖表补搜索历史 + 浮动书签位置 | ✅ 采纳 | 补 #25 搜索历史（Preferences，非 DB）、#26 浮动书签位置（新落 `app_settings` KV 键 `app_bookmark_pos`）（§6、§8 L8） |

> 采纳率：必改 2/2、建议 7/7 全部采纳。JUDGE 已注明建议5、6、7 为轻微/可选，本设计仍全部纳入以提升清晰度与健壮性。
