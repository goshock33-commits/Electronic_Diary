// <!-- agentID: DEV-004 -->
// <!-- agentID: DEV-021 --> extract_task 日期接线：convertToTodo 的 date 不再硬编码今天——
//   task_date 非空且可归一化（TaskExtractionViewModel.normalizeTaskDate → YYYY-MM-DD）则用它，
//   否则 fallback DateUtils.today()；type 推导：目标日期=今天→'today'，否则→'tomorrow'。
// [extract_task AI 升级] handleExtractTask：本地关键词 heuristicExtract → DeepSeekClient.chat() 语义解析——
//   AI 输出结构化 JSON（title/date/time/location/category，相对日期基于今天换算为 YYYY-MM-DD），
//   经现有 saveTask + convertToTodo 流程创建待办并填入 TodoItem.due_date/due_time/location（DEV-021 接线）；
//   AI 失败（无 Key/断网/JSON 解析失败）降级走原 receiveFromShare 本地链路，工具不因网络问题瘫痪。
// [remind_member] DEV：新增第五分支 handleRemindMember——member 称呼经 FamilyManager.findMemberByName
//   定位成员（第一跳即 FamilyMemberDao.findByNickname，未命中回退别名 matchesName），未找到如实回报；
//   找到 → TodoViewModel.add 建提醒待办（标题「提醒{昵称}：{事项}」），time 合法且为未来时刻 →
//   经 TodoReminderOptions.remindAt 发系统提醒（add 内部 syncReminder 链路，DEV-013）。
//   注：todo.assignee_member_id 列存在但 TodoDao 未接线（DEV-FAMILY 逻辑引用），本工具不越界改 shared，
//   成员语义由标题承载。
// 文件: AIIntentHandler.ets
// 任务: T202 四分支执行器（S3 追加防线 / S2 直连 shared DAO / M3 迁移真实链路 / M4 截断 / P3 写路径）
// 关联架构: PLN-001_ai_plan.md T202 任务卡 + JUDGE S2/S3/M3/M4 + 二审 P3；契约以 T101 DeepSeekTypes.ets 为准
// Skill 参考：frontend-design / ui-ux-pro-max
// 图标: 本文件为纯业务逻辑 service，无 UI、无 $r('sys.symbol.*')（0 处，无需图标验证）
//
// ========== API 取证（本地源码级，禁凭记忆） ==========
// - DSToolCall / ToolExecResult          ← shared/src/main/ets/network/DeepSeekTypes.ets（T101 冻结契约 L33/L168）
// - DiaryDao.queryByDate(L47)/search(L90)、HappyThingDao.queryByDate(L54)/searchByContent(L75)、
//   ExtraThingDao.queryByDate(L52)/searchByContent(L73) ← shared/src/main/ets/database/dao/*.ets（均已存在，未新增 DAO 方法）
// - DiaryViewModel.init(L52)/save(L124)  ← features/diary/.../DiaryViewModel.ets（save 内部 UPSERT + emit DIARY_SAVED L174）
// - TodoViewModel.init(L38)/add(L70)     ← features/todo/.../TodoViewModel.ets（add 依赖 init 注入的 currentDate L72，必须先 init）
// - TaskExtractionViewModel.receiveFromShare(L39)/getAllTasks(L157)/convertToTodo(L129)
//   ← features/task-extraction/.../TaskExtractionViewModel.ets（M3：调用序列迁移自 AIChatView.ets L172-208，行为一致）
//
// ========== 工具入参契约（与 T201 AITools Schema 三方对齐，以 T101 为准） ==========
// add_todo     { title: string, type?: 'today'|'tomorrow', category?: string }
// create_diary { content: string, date?: string(YYYY-MM-DD，缺省今天) }
// query_diary  { date?: string, keyword?: string }（二选一，date 优先）
// extract_task { text: string }
// remind_member { member: string, title: string, type?: 'today'|'tomorrow', time?: string(HH:mm) }（[remind_member] 增补）
//
// ========== 红线声明 ==========
// 【S2】本文件禁止 import SearchViewModel（其签名无日期参数且会污染搜索页 AppStorage）——查询直走 shared DAO。
// 【S3】create_diary 为代码级追加防线：当天已有日记 → 原文 + "\n\n---\n\n" + 新内容，禁止静默覆盖，resultJson 回报 appended:true。
// 【P3】create_diary 写路径必须经 DiaryViewModel.init(date)+save(...) 落库（emit DIARY_SAVED 驱动首页/日历刷新）；
//       禁止 DiaryDao.insert/update 直写（不 emit 事件，页面不刷新）。
// 【M4】resultJson 单条 ≤ 2K 字符：每源截前 3 条、正文逐级压缩（150→60→30 字）。
// 通用：每分支 try-catch，失败序列化为 {success:false,error:"..."}，绝不抛异常打断会话（契约② role:tool 回包不可缺）。

import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DiaryDao, HappyThingDao, ExtraThingDao, TodoDao, DateUtils, DeepSeekClient, FamilyManager, VoiceReminderSender } from '@ohos/shared';
import type { DSToolCall, ToolExecResult, Diary, HappyThing, ExtraThing, TodoItem, ExtractedTask,
  DSMessage, DSChatResult, DSChatOptions, FamilyMember, Result, VoiceReminderSendOptions } from '@ohos/shared';
import { TodoViewModel } from 'features/todo';
import type { TodoReminderOptions } from 'features/todo';
import { DiaryViewModel } from 'features/diary';
import { TaskExtractionViewModel, TaskCategory } from 'features_task_extraction';
import type { ExtractionResult } from 'features_task_extraction';

const TAG = 'AIIntentHandler';

/** 【M4】resultJson 单条上限（字符） */
const MAX_RESULT_CHARS: number = 2048;
/** 【M4】query_diary 每数据源最多返回条数 */
const MAX_ITEMS_PER_SOURCE: number = 3;
/** 【M4】正文截断逐级压缩档位（首档 150 字，超 2K 逐级降档重打包） */
const CLIP_LEVELS: number[] = [150, 60, 30];
/** 【S3】追加分隔线（与任务卡约定字面一致） */
const APPEND_SEPARATOR: string = '\n\n---\n\n';
/** [AI 升级] extract_task 语义解析生成参数：低温度求确定性，短输出限流 */
const EXTRACT_TEMPERATURE: number = 0.1;
const EXTRACT_MAX_TOKENS: number = 256;

// ========== 工具入参类型（JSON.parse as 目标，字段全可选做健壮性防御） ==========

interface AddTodoArgs {
  title?: string;
  type?: string;
  category?: string;
}

interface CreateDiaryArgs {
  content?: string;
  date?: string;
}

interface QueryDiaryArgs {
  date?: string;
  keyword?: string;
}

/** query_todo 工具入参 */
interface QueryTodoArgs {
  date?: string;
}

interface ExtractTaskArgs {
  text?: string;
}

/** [remind_member] remind_member 工具入参（字段全可选做健壮性防御） */
interface RemindMemberArgs {
  member?: string;
  title?: string;
  type?: string;
  time?: string;
}

/** [AI 升级] extract_task 语义解析产物（DeepSeek 返回 JSON，字段全可选做健壮性防御） */
interface AIExtractedFields {
  title?: string;
  date?: string;
  time?: string;
  location?: string;
  category?: string;
}

// ========== resultJson 载荷类型（典型化字面量，规避 §8.3-① Record 构造限制） ==========

interface FailPayload {
  success: boolean;
  error: string;
}

interface AddTodoPayload {
  success: boolean;
  todoId: number;
  date: string;
  type: string;
  title: string;
}

interface CreateDiaryPayload {
  success: boolean;
  date: string;
  /** 【S3】true = 当天已有日记，本次为分隔线追加（模型须如实告知用户，禁止说成覆盖） */
  appended: boolean;
  contentLength: number;
}

interface DiaryHit {
  date: string;
  title: string;
  content: string;
}

interface ThingHit {
  date: string;
  content: string;
}

/** query_todo 单条待办展示项 */
interface TodoHit {
  id: number;
  title: string;
  completed: boolean;
  type: string;
  dueTime: string;
}

/** query_todo 结果载荷 */
interface QueryTodoPayload {
  success: boolean;
  date: string;
  todos: TodoHit[];
  totalCount: number;
  completedCount: number;
}

interface QueryDiaryPayload {
  success: boolean;
  /** 'date' | 'keyword' */
  mode: string;
  diaries: DiaryHit[];
  happyThings: ThingHit[];
  extraThings: ThingHit[];
  /** true = 存在被截断的正文/条目（M4 告知模型结果可能不完整） */
  truncated: boolean;
}

interface ExtractTaskPayload {
  success: boolean;
  title: string;
  /** 待办落库日期 YYYY-MM-DD（AI 解析 date 归一化，空/失败 fallback 今天） */
  dueDate: string;
  /** 待办时间 HH:mm，未识别为 '' */
  dueTime: string;
  /** 地点，未识别为 '' */
  location: string;
  convertedToTodo: boolean;
  hint: string;
}

/** [remind_member] remind_member 成功载荷 */
interface RemindMemberPayload {
  success: boolean;
  todoId: number;
  /** 匹配到的成员昵称（可能与用户口头称呼不同，如「老妈」匹配到昵称「妈妈」） */
  memberNickname: string;
  /** 提醒待办落库日期 YYYY-MM-DD */
  date: string;
  /** 提醒待办标题（含成员昵称） */
  title: string;
  /** 提醒时刻 HH:mm，未提供为 '' */
  remindTime: string;
  /** true = 系统提醒已发布，到点会通知 */
  reminderScheduled: boolean;
  hint: string;
}

/**
 * T202 · AI 工具调用执行器（四分支 + [remind_member] 第五分支 remind_member）。
 * 无状态：每次执行按需 new 各 feature ViewModel（VM 内部自带 EventBus 事件契约，跨页刷新由 VM 负责）。
 * 唯一入口 execute(call)：任何分支失败都以 {success:false,error} 序列化回报，永不抛异常（保证 role:tool 回包齐全，契约②）。
 */
export class AIIntentHandler {

  /**
   * 执行一次模型发起的工具调用，返回可直接回填 role:"tool" 消息的执行结果。
   * @param call T101 契约 DSToolCall（call.function.arguments 为 JSON 字符串）
   */
  static async execute(call: DSToolCall): Promise<ToolExecResult> {
    const toolName: string = call.function ? call.function.name : '';
    const rawArgs: string = call.function ? call.function.arguments : '';
    // 模型可能发空参（'' / 空白），归一为 '{}' 防 JSON.parse 直接抛错
    const argsJson: string = rawArgs.trim().length > 0 ? rawArgs : '{}';
    let resultJson: string = '';
    if (toolName === 'add_todo') {
      resultJson = await AIIntentHandler.handleAddTodo(argsJson);
    } else if (toolName === 'create_diary') {
      resultJson = await AIIntentHandler.handleCreateDiary(argsJson);
    } else if (toolName === 'query_diary') {
      resultJson = await AIIntentHandler.handleQueryDiary(argsJson);
    } else if (toolName === 'query_todo') {
      resultJson = await AIIntentHandler.handleQueryTodo(argsJson);
    } else if (toolName === 'extract_task') {
      resultJson = await AIIntentHandler.handleExtractTask(argsJson);
    } else if (toolName === 'remind_member') {
      resultJson = await AIIntentHandler.handleRemindMember(argsJson);
    } else {
      resultJson = AIIntentHandler.fail('未知工具: ' + toolName);
    }
    // 【M4】最终兜底：任何分支产物超 2K 一律硬截（正常路径在各分支内已按语义截断，不应走到这里）
    if (resultJson.length > MAX_RESULT_CHARS) {
      hilog.warn(0x0000, TAG, 'resultJson overflow after branch clip: %{public}d chars, hard cut', resultJson.length);
      resultJson = AIIntentHandler.fail('结果过长已截断，请缩小查询范围（如指定日期）');
    }
    const result: ToolExecResult = {
      toolCallId: call.id,
      name: toolName,
      resultJson: resultJson
    };
    return result;
  }

  // ========== ① add_todo ==========

  /**
   * add_todo → TodoViewModel.add(title, type, category)。
   * 取证：add() 用 init(date) 注入的 currentDate 计算落库日期（TodoViewModel.ets L72），故必须先 init 再 add。
   */
  private static async handleAddTodo(argsJson: string): Promise<string> {
    try {
      const args: AddTodoArgs | null = JSON.parse(argsJson) as AddTodoArgs | null;
      if (args === null) {
        return AIIntentHandler.fail('add_todo 参数解析失败');
      }
      const title: string = (args.title ?? '').trim();
      if (title.length === 0) {
        return AIIntentHandler.fail('缺少待办标题 title');
      }
      const todoType: string = args.type === 'tomorrow' ? 'tomorrow' : 'today';
      const vm: TodoViewModel = new TodoViewModel();
      await vm.init(DateUtils.today());
      const created: TodoItem | null = await vm.add(title, todoType, args.category);
      if (created === null) {
        return AIIntentHandler.fail('待办落库失败');
      }
      hilog.info(0x0000, TAG, 'add_todo ok: id=%{public}d date=%{public}s', created.id, created.date);
      const payload: AddTodoPayload = {
        success: true,
        todoId: created.id,
        date: created.date,
        type: todoType,
        title: title
      };
      return JSON.stringify(payload);
    } catch (err) {
      return AIIntentHandler.failFromError('add_todo', (err as BusinessError).message);
    }
  }

  // ========== ② create_diary【S3 代码级防线 + P3 写路径】 ==========

  /**
   * create_diary：
   * 查路径【S3】：先 DiaryDao.queryByDate(date) 只读判存——当天无日记 → 新内容即最终 content；
   *   当天已有 → 原content + "\n\n---\n\n" + 新content 固定追加，禁止静默覆盖，resultJson 回报 appended:true。
   * 写路径【P3】：最终 content 必须经 DiaryViewModel.init(date)+save(...) 落库
   *   （save 内部 UPSERT + emit DIARY_SAVED，DiaryViewModel.ets L174，驱动首页/日历跨页刷新）；
   *   禁止 DiaryDao.insert/update 直写。
   * 注：save 会整体覆写图片字段（setImageList），故沿用 existing.getImageList() 传入——
   *   传 [] 会清空用户已附图片，等于对图片静默覆盖，与 S3 防线精神相悖。title/mood 不传参即不覆写（save L135-140）。
   */
  private static async handleCreateDiary(argsJson: string): Promise<string> {
    try {
      const args: CreateDiaryArgs | null = JSON.parse(argsJson) as CreateDiaryArgs | null;
      if (args === null) {
        return AIIntentHandler.fail('create_diary 参数解析失败');
      }
      const content: string = (args.content ?? '').trim();
      if (content.length === 0) {
        return AIIntentHandler.fail('缺少日记内容 content');
      }
      const date: string = (args.date ?? '').trim().length > 0 ? (args.date ?? '').trim() : DateUtils.today();
      // 【S3】只读判存
      const existing: Diary | null = await DiaryDao.queryByDate(date);
      let finalContent: string = content;
      let appended: boolean = false;
      if (existing !== null && existing.content.trim().length > 0) {
        finalContent = existing.content + APPEND_SEPARATOR + content;
        appended = true;
      }
      const keepImages: string[] = existing !== null ? existing.getImageList() : [];
      // 【P3】唯一合法写路径
      const vm: DiaryViewModel = new DiaryViewModel();
      await vm.init(date);
      // fix: MAIN-001 · T-M01 一天多篇新语义适配（用户明示授权本处改动）：
      //   续写场景（existing 非空）必须传 editingId=当日最新篇 id → 原地更新该篇；
      //   不传则 save 缺省"永远 insert 新行"，会把续写内容存成新增一篇（语义漂移）。
      //   新写场景（existing 为空）不传 id，正常新增。
      const editingId: number | undefined = (appended && existing !== null && existing.id > 0)
        ? existing.id : undefined;
      const ok: boolean = await vm.save(finalContent, keepImages, undefined, undefined, undefined, editingId);
      if (!ok) {
        return AIIntentHandler.fail('日记保存失败: ' + vm.getLastSaveError());
      }
      hilog.info(0x0000, TAG, 'create_diary ok: date=%{public}s appended=%{public}d', date, appended ? 1 : 0);
      const payload: CreateDiaryPayload = {
        success: true,
        date: date,
        appended: appended,
        contentLength: finalContent.length
      };
      return JSON.stringify(payload);
    } catch (err) {
      return AIIntentHandler.failFromError('create_diary', (err as BusinessError).message);
    }
  }

  // ========== ③ query_diary【S2 直走 shared DAO】 ==========

  /**
   * query_diary：按日期 → DiaryDao.queryByDate / HappyThingDao.queryByDate / ExtraThingDao.queryByDate；
   * 按关键词 → DiaryDao.search / HappyThingDao.searchByContent / ExtraThingDao.searchByContent。
   * 【S2】禁止经 SearchViewModel（签名无日期参数 + 污染搜索页 AppStorage）。
   * 【M4】每源截前 3 条、正文按 150→60→30 逐级压缩至整包 ≤2K。
   */
  private static async handleQueryDiary(argsJson: string): Promise<string> {
    try {
      const args: QueryDiaryArgs | null = JSON.parse(argsJson) as QueryDiaryArgs | null;
      if (args === null) {
        return AIIntentHandler.fail('query_diary 参数解析失败');
      }
      const date: string = (args.date ?? '').trim();
      const keyword: string = (args.keyword ?? '').trim();
      let diaries: Diary[] = [];
      let happyList: HappyThing[] = [];
      let extraList: ExtraThing[] = [];
      let mode: string = '';
      if (date.length > 0) {
        mode = 'date';
        const one: Diary | null = await DiaryDao.queryByDate(date);
        if (one !== null) {
          diaries.push(one);
        }
        happyList = await HappyThingDao.queryByDate(date);
        extraList = await ExtraThingDao.queryByDate(date);
      } else if (keyword.length > 0) {
        mode = 'keyword';
        diaries = await DiaryDao.search(keyword);
        happyList = await HappyThingDao.searchByContent(keyword);
        extraList = await ExtraThingDao.searchByContent(keyword);
      } else {
        return AIIntentHandler.fail('query_diary 需要 date 或 keyword 至少一个参数');
      }
      // 【M4】每源截前 3 条
      const overCount: boolean = diaries.length > MAX_ITEMS_PER_SOURCE ||
        happyList.length > MAX_ITEMS_PER_SOURCE || extraList.length > MAX_ITEMS_PER_SOURCE;
      const dTop: Diary[] = diaries.slice(0, MAX_ITEMS_PER_SOURCE);
      const hTop: HappyThing[] = happyList.slice(0, MAX_ITEMS_PER_SOURCE);
      const eTop: ExtraThing[] = extraList.slice(0, MAX_ITEMS_PER_SOURCE);
      // 【M4】首档 150 字打包，超 2K 逐级降档重打包
      let json: string = AIIntentHandler.buildQueryJson(mode, dTop, hTop, eTop, CLIP_LEVELS[0], overCount);
      for (let i = 1; i < CLIP_LEVELS.length && json.length > MAX_RESULT_CHARS; i++) {
        json = AIIntentHandler.buildQueryJson(mode, dTop, hTop, eTop, CLIP_LEVELS[i], true);
      }
      hilog.info(0x0000, TAG, 'query_diary ok: mode=%{public}s d=%{public}d h=%{public}d e=%{public}d len=%{public}d',
        mode, dTop.length, hTop.length, eTop.length, json.length);
      return json;
    } catch (err) {
      return AIIntentHandler.failFromError('query_diary', (err as BusinessError).message);
    }
  }

  /** 按指定正文截断档位打包 query_diary 结果（M4：日记正文给摘要=前 N 字） */
  private static buildQueryJson(mode: string, diaries: Diary[], happyList: HappyThing[],
    extraList: ExtraThing[], clipLen: number, overCount: boolean): string {
    let clipped: boolean = overCount;
    const dHits: DiaryHit[] = [];
    for (let i = 0; i < diaries.length; i++) {
      const d: Diary = diaries[i];
      if (d.content.length > clipLen) {
        clipped = true;
      }
      const hit: DiaryHit = {
        date: d.date,
        title: AIIntentHandler.clip(d.title, 30),
        content: AIIntentHandler.clip(d.content, clipLen)
      };
      dHits.push(hit);
    }
    const hHits: ThingHit[] = [];
    for (let i = 0; i < happyList.length; i++) {
      const h: HappyThing = happyList[i];
      if (h.content.length > clipLen) {
        clipped = true;
      }
      const hit: ThingHit = {
        date: h.date,
        content: AIIntentHandler.clip(h.content, clipLen)
      };
      hHits.push(hit);
    }
    const eHits: ThingHit[] = [];
    for (let i = 0; i < extraList.length; i++) {
      const e: ExtraThing = extraList[i];
      if (e.content.length > clipLen) {
        clipped = true;
      }
      const hit: ThingHit = {
        date: e.date,
        content: AIIntentHandler.clip(e.content, clipLen)
      };
      eHits.push(hit);
    }
    const payload: QueryDiaryPayload = {
      success: true,
      mode: mode,
      diaries: dHits,
      happyThings: hHits,
      extraThings: eHits,
      truncated: clipped
    };
    return JSON.stringify(payload);
  }

  // ========== ③b query_todo【查待办列表】 ==========

  /**
   * query_todo：查询某天的待办列表（TodoDao.queryByDate）。
   * date 不传或空 → 查今天。返回待办标题、完成状态、类型、时间。
   */
  private static async handleQueryTodo(argsJson: string): Promise<string> {
    try {
      const args: QueryTodoArgs | null = JSON.parse(argsJson) as QueryTodoArgs | null;
      if (args === null) {
        return AIIntentHandler.fail('query_todo 参数解析失败');
      }
      const date: string = (args.date ?? '').trim().length > 0 ? (args.date ?? '').trim() : DateUtils.today();
      const todos: TodoItem[] = await TodoDao.queryByDate(date);
      const hits: TodoHit[] = [];
      let completedCount: number = 0;
      for (let i = 0; i < todos.length; i++) {
        const t: TodoItem = todos[i];
        const isDone: boolean = t.completed === 1;
        if (isDone) {
          completedCount++;
        }
        const hit: TodoHit = {
          id: t.id,
          title: AIIntentHandler.clip(t.title, 60),
          completed: isDone,
          type: t.type ?? 'today',
          dueTime: t.due_time ?? ''
        };        hits.push(hit);
      }
      hilog.info(0x0000, TAG, 'query_todo ok: date=%{public}s total=%{public}d done=%{public}d',
        date, todos.length, completedCount);
      const payload: QueryTodoPayload = {
        success: true,
        date: date,
        todos: hits,
        totalCount: todos.length,
        completedCount: completedCount
      };
      return JSON.stringify(payload);
    } catch (err) {
      return AIIntentHandler.failFromError('query_todo', (err as BusinessError).message);
    }
  }

  // ========== ④ extract_task【AI 升级：DeepSeekClient.chat 语义解析】 ==========

  /**
   * extract_task：【AI 升级】本地关键词 heuristicExtract → DeepSeekClient.chat() 语义解析。
   * 1) aiExtractTask(text)：低温度二次调用 DeepSeek，system 提示注入今天日期（相对日期换算锚点），
   *    模型输出纯 JSON {title,date,time,location,category} → 解析映射为 ExtractionResult；
   * 2) 成功 → vm.saveTask(result,'ai_chat','ai_high') 落库（VM 内 unshift + emit TASK_EXTRACTED）；
   *    AI 失败（无 Key/断网/JSON 不合法）→ 降级 vm.receiveFromShare(text,'ai_chat') 原本地链路，
   *    工具不因网络问题瘫痪，行为与迁移前一致；
   * 3) convertToTodo(id, date, type)：【DEV-021】date=task_date 归一化结果（YYYY-MM-DD），空/解析失败
   *    fallback DateUtils.today()；type：date=今天→'today'，否则→'tomorrow'；task_time/location 在
   *    convertToTodo 内接线到 TodoItem.due_date/due_time/location 全字段落库（VM 内 emit TASK_CONVERTED +
   *    TODO_CREATED，同 TaskConfirmPage 约定）。
   */
  private static async handleExtractTask(argsJson: string): Promise<string> {
    try {
      const args: ExtractTaskArgs | null = JSON.parse(argsJson) as ExtractTaskArgs | null;
      if (args === null) {
        return AIIntentHandler.fail('extract_task 参数解析失败');
      }
      const text: string = (args.text ?? '').trim();
      if (text.length === 0) {
        return AIIntentHandler.fail('缺少待提取文本 text');
      }
      const vm: TaskExtractionViewModel = new TaskExtractionViewModel();
      // ① AI 语义解析（替换本地关键词 heuristicExtract）
      const aiResult: ExtractionResult | null = await AIIntentHandler.aiExtractTask(text);
      let title: string = '';
      let savedTask: ExtractedTask | null = null;
      if (aiResult !== null) {
        title = aiResult.title;
        savedTask = await vm.saveTask(aiResult, 'ai_chat', 'ai_high');
      } else {
        // ② 降级：原本地链路（receiveFromShare 内部 heuristic + saveTask，最新项在 getAllTasks()[0]）
        hilog.warn(0x0000, TAG, 'extract_task ai parse unavailable, fallback to local heuristic');
        const fallback: ExtractionResult | null = await vm.receiveFromShare(text, 'ai_chat');
        if (fallback === null || fallback.title.trim().length === 0) {
          return AIIntentHandler.fail('未能从文本中识别出任务内容，请换个说法（如「周五下午3点交作业」）');
        }
        title = fallback.title;
        const savedList: ExtractedTask[] = vm.getAllTasks();
        savedTask = savedList.length > 0 ? savedList[0] : null;
      }
      // ③ 转待办：due_date/due_time/location 经 convertToTodo 接线到 TodoItem（DEV-021 链路）
      let converted: boolean = false;
      let todoDate: string = DateUtils.today();
      let dueTime: string = '';
      let location: string = '';
      if (savedTask !== null && savedTask.id > 0) {
        if (savedTask.task_date !== null && savedTask.task_date.length > 0) {
          const normalized: string | null = TaskExtractionViewModel.normalizeTaskDate(savedTask.task_date);
          if (normalized !== null) { todoDate = normalized; }
        }
        if (savedTask.task_time !== null && savedTask.task_time.length > 0) { dueTime = savedTask.task_time; }
        if (savedTask.location !== null && savedTask.location.length > 0) { location = savedTask.location; }
        const todoType: string = todoDate === DateUtils.today() ? 'today' : 'tomorrow';
        converted = await vm.convertToTodo(savedTask.id, todoDate, todoType);
      }
      hilog.info(0x0000, TAG, 'extract_task ok: title=%{public}s ai=%{public}d converted=%{public}d date=%{public}s',
        title, aiResult !== null ? 1 : 0, converted ? 1 : 0, todoDate);
      const isTodayTodo: boolean = todoDate === DateUtils.today();
      const payload: ExtractTaskPayload = {
        success: true,
        title: title,
        dueDate: todoDate,
        dueTime: dueTime,
        location: location,
        convertedToTodo: converted,
        hint: converted
          ? (isTodayTodo ? '已提取任务并加入今日待办' : '已提取任务并加入 ' + todoDate + ' 的待办')
          : '已提取任务，但加入待办未成功，可稍后在时光轴手动添加'
      };
      return JSON.stringify(payload);
    } catch (err) {
      return AIIntentHandler.failFromError('extract_task', (err as BusinessError).message);
    }
  }

  /**
   * [AI 升级] DeepSeek 语义解析：text → ExtractionResult。
   * system 提示注入今天日期+星期（相对日期"明天/周五/下周三"换算锚点），要求模型只输出纯 JSON；
   * 低温度 0.1 + max_tokens 256（结构化短输出）。任何失败（未配置 Key/网络/HTTP/JSON 不合法/title 空）
   * 一律返回 null，由调用方降级本地链路——本方法自身绝不抛异常。
   */
  private static async aiExtractTask(text: string): Promise<ExtractionResult | null> {
    try {
      const today: string = DateUtils.today();
      const weekday: string = DateUtils.getWeekdayName(today);
      const systemPrompt: string = '你是任务信息提取器。从用户输入中提取一条待办任务，只输出一个 JSON 对象，' +
        '禁止输出任何解释文字或 Markdown 代码块。字段：' +
        'title（必填，简洁动宾短语标题，不超过30字）、' +
        'date（任务日期，格式 YYYY-MM-DD；"明天/后天/周五/下周三"等相对日期基于今天换算；未提及则为空字符串）、' +
        'time（24小时制 HH:mm；未提及则为空字符串）、' +
        'location（地点；未提及则为空字符串）、' +
        'category（任务类别，取 exam/homework/meeting/deadline/general 之一）。' +
        '今天是 ' + today + '（' + weekday + '）。';
      const messages: DSMessage[] = [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: text }
      ];
      const options: DSChatOptions = {
        temperature: EXTRACT_TEMPERATURE,
        maxTokens: EXTRACT_MAX_TOKENS
      };
      const chatResult: DSChatResult = await DeepSeekClient.chat(messages, undefined, options);
      if (!chatResult.ok || chatResult.message === undefined) {
        hilog.warn(0x0000, TAG, 'aiExtractTask chat failed: %{public}s', chatResult.errorText ?? 'unknown');
        return null;
      }
      const content: string = (chatResult.message.content ?? '').trim();
      const fields: AIExtractedFields | null = AIIntentHandler.parseExtractJson(content);
      if (fields === null) {
        hilog.warn(0x0000, TAG, 'aiExtractTask json invalid, len=%{public}d', content.length);
        return null;
      }
      const title: string = (fields.title ?? '').trim();
      if (title.length === 0) {
        return null;
      }
      const result: ExtractionResult = {
        title: AIIntentHandler.clip(title, 100),
        category: AIIntentHandler.mapCategory((fields.category ?? '').trim()),
        confidence: 0.9
      };
      const taskDate: string = (fields.date ?? '').trim();
      if (taskDate.length > 0) { result.taskDate = taskDate; }
      const taskTime: string = (fields.time ?? '').trim();
      if (taskTime.length > 0) { result.taskTime = taskTime; }
      const loc: string = (fields.location ?? '').trim();
      if (loc.length > 0) { result.location = loc; }
      return result;
    } catch (err) {
      hilog.warn(0x0000, TAG, 'aiExtractTask error: %{public}s', (err as BusinessError).message);
      return null;
    }
  }

  /** [AI 升级] 宽容解析模型输出：截取首个 '{' 到末个 '}'（容忍模型违规包 ```json 围栏/前后缀文字） */
  private static parseExtractJson(content: string): AIExtractedFields | null {
    const start: number = content.indexOf('{');
    const end: number = content.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return null;
    }
    try {
      return JSON.parse(content.substring(start, end + 1)) as AIExtractedFields;
    } catch (err) {
      return null;
    }
  }

  /** [AI 升级] 模型 category 字符串 → TaskCategory 封闭枚举（未知值兜底 GENERAL） */
  private static mapCategory(raw: string): TaskCategory {
    if (raw === 'exam') { return TaskCategory.EXAM; }
    if (raw === 'homework') { return TaskCategory.HOMEWORK; }
    if (raw === 'meeting') { return TaskCategory.MEETING; }
    if (raw === 'deadline') { return TaskCategory.DEADLINE; }
    return TaskCategory.GENERAL;
  }

  // ========== ⑤ remind_member【[remind_member] 昵称/别名定位成员 → 建提醒待办 + 系统提醒】 ==========

  /**
   * remind_member：提醒某位家庭成员做某事。
   * ① FamilyManager.findMemberByName(member)：第一跳 FamilyMemberDao.findByNickname 精确匹配昵称，
   *    未命中回退遍历 queryAll 按别名 matchesName（「老妈」→ 昵称「妈妈」）；未找到 → fail 如实回报，
   *    模型据 systemPrompt 话术建议用户先在设置中添加成员。
   * ② TodoViewModel.init(今天)+add(...) 建提醒待办：标题「提醒{昵称}：{事项}」，type today/tomorrow 同 add_todo；
   *    time 合法（HH:mm）→ due_date/due_time 一并落库；且时刻为未来 → TodoReminderOptions.remindAt
   *    走 add 内部 syncReminder 发布系统提醒并写回 reminder_id（DEV-013 链路）。
   * ③ 时刻已过/未提供 time/发布失败 → 仅建待办，hint 向模型说明差别（不得谎称会发提醒）。
   * 注：todo.assignee_member_id 列 TodoDao 未接线，成员语义由标题承载（不越界改 shared）。
   */
  private static async handleRemindMember(argsJson: string): Promise<string> {
    try {
      const args: RemindMemberArgs | null = JSON.parse(argsJson) as RemindMemberArgs | null;
      if (args === null) {
        return AIIntentHandler.fail('remind_member 参数解析失败');
      }
      const memberName: string = (args.member ?? '').trim();
      if (memberName.length === 0) {
        return AIIntentHandler.fail('缺少成员称呼 member');
      }
      const rawTitle: string = (args.title ?? '').trim();
      if (rawTitle.length === 0) {
        return AIIntentHandler.fail('缺少提醒内容 title');
      }
      // ① 定位成员（findByNickname 精确匹配 → 别名回退，业务层统一入口）
      const found: Result<FamilyMember> = await FamilyManager.getInstance().findMemberByName(memberName);
      if (!found.success || found.data === null) {
        return AIIntentHandler.fail('未找到家庭成员「' + memberName + '」，请先在设置中添加该成员');
      }
      const member: FamilyMember = found.data;
      // ② 建提醒待办（落库日期由 type 决定，与 add_todo 语义一致）
      const todoType: string = args.type === 'tomorrow' ? 'tomorrow' : 'today';
      const targetDate: string = todoType === 'tomorrow'
        ? DateUtils.formatDate(new Date(Date.now() + 86400000))
        : DateUtils.today();
      const remindTime: string = AIIntentHandler.normalizeHHmm((args.time ?? '').trim());
      const remindAt: number = remindTime.length > 0 ? AIIntentHandler.toTimestamp(targetDate, remindTime) : 0;
      const options: TodoReminderOptions = {};
      if (remindTime.length > 0) {
        options.dueDate = targetDate;
        options.dueTime = remindTime;
        const nowMs: number = new Date().getTime();
        if (remindAt > nowMs) {
          options.remindAt = remindAt;
        }
      }
      const todoTitle: string = '提醒' + member.nickname + '：' + rawTitle;
      const vm: TodoViewModel = new TodoViewModel();
      await vm.init(DateUtils.today());
      const created: TodoItem | null = await vm.add(todoTitle, todoType, undefined, undefined, options);
      if (created === null) {
        return AIIntentHandler.fail('提醒待办落库失败');
      }
      // 补 assignee_member_id（DB 列已就位，DAO 已接线）
      if (created.id > 0) {
        created.assignee_member_id = member.id;
        await vm.update(created, todoType);
      }
      // add 内 syncReminder 成功发布才会写回 reminder_id，以它为准回报调度结果
      const scheduled: boolean = created.reminder_id !== null && created.reminder_id !== 0;
      // [T309-A] 云升级：目标成员已绑账号且非本机 → 写 VoiceReminder 云表（status=pending，
      //   云函数 voice_push 定时扫描推送对方设备）。工具名/参数/回包结构不变，仅 hint 改述；
      //   未登录/未入家庭/断网等由 sendReminder 内部收敛为 fail → 静默降级保持二期本机行为。
      let cloudSent: boolean = false;
      if (member.uid !== null && member.uid.length > 0 && !member.isSelf()) {
        const sendOpts: VoiceReminderSendOptions = {};
        if (remindAt > 0) {
          sendOpts.scheduledAt = remindAt;
        }
        const cloudRes: Result<string> =
          await VoiceReminderSender.getInstance().sendReminder(member, rawTitle, sendOpts);
        cloudSent = cloudRes.success;
        if (!cloudRes.success) {
          hilog.warn(0x0000, TAG, 'remind_member cloud send degraded to local: %{public}s', cloudRes.message);
        }
      }
      hilog.info(0x0000, TAG, 'remind_member ok: id=%{public}d member=%{public}s date=%{public}s scheduled=%{public}d cloud=%{public}d',
        created.id, member.nickname, created.date, scheduled ? 1 : 0, cloudSent ? 1 : 0);
      let hint: string = '';
      if (cloudSent) {
        // [T309-A] 回包改述「已提醒对方设备」（对方手机将收到推送并播报）
        if (remindTime.length > 0) {
          hint = '已提醒' + member.nickname + '的设备：' + created.date + ' ' + remindTime + '「' + rawTitle +
            '」到点推送播报；本机也已建提醒待办';
        } else {
          hint = '已提醒' + member.nickname + '的设备（对方将收到「' + rawTitle + '」的推送播报）；本机也已建待办';
        }
      } else if (remindTime.length > 0) {
        hint = '已为' + member.nickname + '设置提醒：' + created.date + ' ' + remindTime + '「' + rawTitle + '」';
      } else {
        hint = '已为' + member.nickname + '创建待办「' + todoTitle + '」（未指定具体时间）';
      }
      const payload: RemindMemberPayload = {
        success: true,
        todoId: created.id,
        memberNickname: member.nickname,
        date: created.date,
        title: todoTitle,
        remindTime: remindTime,
        reminderScheduled: scheduled,
        hint: hint
      };
      return JSON.stringify(payload);
    } catch (err) {
      return AIIntentHandler.failFromError('remind_member', (err as BusinessError).message);
    }
  }

  /** [remind_member] 归一化 HH:mm（宽容 "9:00"/"09:00"；非法返回 ''） */
  private static normalizeHHmm(raw: string): string {
    if (raw.length === 0) { return ''; }
    const parts: string[] = raw.split(':');
    if (parts.length !== 2) { return ''; }
    const h: number = parseInt(parts[0], 10);
    const m: number = parseInt(parts[1], 10);
    if (isNaN(h) || isNaN(m) || h < 0 || h > 23 || m < 0 || m > 59) { return ''; }
    return String(h).padStart(2, '0') + ':' + String(m).padStart(2, '0');
  }

  /** [remind_member] "YYYY-MM-DD" + "HH:mm" → 本地毫秒时间戳（先例：TimelineTodoView.toTimestamp；非法返回 0） */
  private static toTimestamp(dateStr: string, timeStr: string): number {
    const dp: string[] = dateStr.split('-');
    const tp: string[] = timeStr.split(':');
    if (dp.length < 3 || tp.length < 2) { return 0; }
    const y: number = parseInt(dp[0], 10);
    const mo: number = parseInt(dp[1], 10);
    const d: number = parseInt(dp[2], 10);
    const h: number = parseInt(tp[0], 10);
    const mi: number = parseInt(tp[1], 10);
    if (isNaN(y) || isNaN(mo) || isNaN(d) || isNaN(h) || isNaN(mi)) { return 0; }
    return new Date(y, mo - 1, d, h, mi, 0).getTime();
  }

  // ========== 通用工具 ==========

  /** 失败载荷序列化（不抛异常打断会话——保证契约② role:tool 回包齐全） */
  private static fail(message: string): string {
    const payload: FailPayload = {
      success: false,
      error: message
    };
    return JSON.stringify(payload);
  }

  /** 异常捕获统一出口：记日志 + 序列化失败载荷 */
  private static failFromError(branch: string, message: string): string {
    const msg: string = message !== undefined && message !== null && message.length > 0 ? message : '未知错误';
    hilog.error(0x0000, TAG, '%{public}s failed: %{public}s', branch, msg);
    return AIIntentHandler.fail(branch + ' 执行失败: ' + msg);
  }

  /** 正文截断：超长取前 max 字 + 省略号（M4 摘要语义） */
  private static clip(text: string, max: number): string {
    if (text.length <= max) {
      return text;
    }
    return text.substring(0, max) + '…';
  }
}
