// <!-- agentID: DEV-004 -->
// [remind_member] DEV：新增第五工具 remind_member（提醒家庭成员）——member 按昵称/别名匹配
//   （FamilyManager.findMemberByName，第一跳即 FamilyMemberDao.findByNickname），执行侧见
//   AIIntentHandler.handleRemindMember：建提醒待办 + time 合法时发系统提醒；systemPrompt 同步告知。
// 文件: features/voice-diary/src/main/ets/service/AITools.ets
// 任务: T201 AI_TOOLS 四工具 JSON Schema + buildSystemPrompt（日期注入 + 追加语义告知）
// 关联架构: PLN-001_ai_plan §3 T201 / T101 契约 shared/network/DeepSeekTypes（DSTool/DSFunctionDef/DSJsonSchema/DSSchemaProp）
// Owner: DEV（HUI 禁改，S4 Owner 矩阵）
// Skill 参考：frontend-design / ui-ux-pro-max
//
// 【三方一致契约】工具名与参数结构以 T101 契约类型为骨架，且必须与 T202 AIIntentHandler
// 的 execute() 四分支逐字对齐：add_todo / create_diary / query_diary / extract_task。
// 任何一侧改名/改参必须回 PLN 重排，不允许单侧偷改。
//
// 【ArkTS §8.3①】JSON Schema properties 是 Record<string, DSSchemaProp>（索引签名类型），
// 构造必须「空字面量起手 + 括号逐键赋值」；普通接口字面量必须带显式类型声明（§8.2），
// 禁止匿名对象字面量嵌在函数调用参数里靠推断。

import { DateUtils } from '@ohos/shared';
import type { DSTool, DSFunctionDef, DSJsonSchema, DSSchemaProp } from '@ohos/shared';

// ════════════════════════════════════════════════════════
// 内部构造工具（全部带显式类型，规避 arkts-no-untyped-obj-literals）
// ════════════════════════════════════════════════════════

/** 构造单个 JSON Schema 属性描述（enum 可选） */
function makeProp(type: string, description: string, enumValues?: string[]): DSSchemaProp {
  const p: DSSchemaProp = { type: type, description: description };
  if (enumValues !== undefined) {
    p.enum = enumValues;
  }
  return p;
}

/** 构造 object 型参数 Schema（properties 已按 §8.3① 逐键构造完毕后传入） */
function makeSchema(properties: Record<string, DSSchemaProp>, required: string[]): DSJsonSchema {
  const schema: DSJsonSchema = { type: 'object', properties: properties, required: required };
  return schema;
}

/** 构造一个 OpenAI 兼容工具声明（type 恒为 'function'，见 T101 DSTool 契约） */
function makeTool(name: string, description: string, parameters: DSJsonSchema): DSTool {
  const fn: DSFunctionDef = { name: name, description: description, parameters: parameters };
  const tool: DSTool = { type: 'function', function: fn };
  return tool;
}

// ════════════════════════════════════════════════════════
// 四工具 Schema 构造（§8.3①：空字面量 + 括号逐键赋值）
// ════════════════════════════════════════════════════════

/** add_todo：添加待办（today/tomorrow 两种归属，category 可选） */
function buildAddTodoTool(): DSTool {
  const props: Record<string, DSSchemaProp> = {};
  props['title'] = makeProp('string', '待办事项标题，简洁的动宾短语，如「买牛奶」「交周报」');
  props['type'] = makeProp('string', '待办归属日期：today 表示今天的待办，tomorrow 表示明天的待办', ['today', 'tomorrow']);
  props['category'] = makeProp('string', '可选的分类标签，如「工作」「学习」「生活」，用户未提及时省略');
  const schema: DSJsonSchema = makeSchema(props, ['title', 'type']);
  return makeTool(
    'add_todo',
    '为用户添加一条待办事项。当用户表达「提醒我」「记一下要做」「今天/明天要做某事」等安排类意图时调用。',
    schema
  );
}

/** create_diary：为今天写日记（当天已有日记 → 分隔线追加，不覆盖，S3 prompt 侧双保险之外的 Schema 侧说明） */
function buildCreateDiaryTool(): DSTool {
  const props: Record<string, DSSchemaProp> = {};
  props['content'] = makeProp('string', '日记正文，以用户第一人称撰写的中文内容');
  const schema: DSJsonSchema = makeSchema(props, ['content']);
  return makeTool(
    'create_diary',
    '为用户保存今天的日记。注意：如果当天已有日记，新内容会以分隔线追加到原有日记之后，不会覆盖原文；工具结果会回报是否为追加（appended）。',
    schema
  );
}

/** query_diary：查询日记/记录（日期 + 关键词双维度，可单用可组合，与 T202 DAO 通路对齐） */
function buildQueryDiaryTool(): DSTool {
  const props: Record<string, DSSchemaProp> = {};
  props['keyword'] = makeProp('string', '内容关键词，对日记与记录做模糊匹配；与 date 至少提供一个');
  props['date'] = makeProp('string', '要查询的日期，格式 YYYY-MM-DD，如 2026-07-16；与 keyword 至少提供一个');
  const schema: DSJsonSchema = makeSchema(props, []);
  return makeTool(
    'query_diary',
    '查询用户过去的日记与记录。支持两种维度：按日期（date）查某一天的内容，按关键词（keyword）搜索相关内容，两者可组合使用；调用时 keyword 与 date 至少提供一个。',
    schema
  );
}

/** extract_task：从文本提取任务（复用 F5-v2 任务提取链路，T202 迁移执行） */
function buildExtractTaskTool(): DSTool {
  const props: Record<string, DSSchemaProp> = {};
  props['text'] = makeProp('string', '需要提取任务的原始文本，保持用户原话，不要改写');
  const schema: DSJsonSchema = makeSchema(props, ['text']);
  return makeTool(
    'extract_task',
    '从一段文本中提取可执行的任务清单，供用户确认后转为待办。当用户粘贴一段长文本（如聊天记录、会议纪要、消息）并希望整理出要做的事时调用。',
    schema
  );
}

/** query_todo：查询某天的待办列表 */
function buildQueryTodoTool(): DSTool {
  const props: Record<string, DSSchemaProp> = {};
  props['date'] = makeProp('string', '要查询的日期，格式 YYYY-MM-DD；不传则查今天');
  const schema: DSJsonSchema = makeSchema(props, []);
  return makeTool(
    'query_todo',
    '查询用户某天的待办事项列表。当用户问「今天有什么待办」「明天有什么安排」「今天要做的事」等时调用，返回该日期的所有待办及完成状态。',
    schema
  );
}

/** [remind_member] remind_member：提醒家庭成员做某事（昵称/别名匹配成员 → 建提醒待办 + 可选系统提醒） */
function buildRemindMemberTool(): DSTool {
  const props: Record<string, DSSchemaProp> = {};
  props['member'] = makeProp('string', '要提醒的家庭成员称呼，如「妈妈」「老爸」「小明」，按昵称或别名匹配已添加的成员');
  props['title'] = makeProp('string', '提醒事项内容，简洁的动宾短语，如「吃药」「带伞」「开家长会」');
  props['type'] = makeProp('string', '提醒归属日期：today 表示今天，tomorrow 表示明天，未提及时用 today', ['today', 'tomorrow']);
  props['time'] = makeProp('string', '可选的提醒时刻，24 小时制 HH:mm，如 09:00、18:30；用户未提及具体时间时省略');
  const schema: DSJsonSchema = makeSchema(props, ['member', 'title']);
  return makeTool(
    'remind_member',
    '提醒某位家庭成员做某事。当用户表达「提醒妈妈吃药」「让爸爸明天九点开会」等指向他人的提醒意图时调用；会按称呼匹配已添加的家庭成员并创建提醒待办，提供 time 时到点发系统提醒。若该成员已绑定账号并加入家庭，提醒还会同步推送到对方的设备（对方手机收到通知并语音播报），结果 hint 会说明是否已提醒对方设备。',
    schema
  );
}

// ════════════════════════════════════════════════════════
// 对外导出
// ════════════════════════════════════════════════════════

/**
 * 五工具声明常量（OpenAI 兼容 tools 数组，挂到 DSChatRequest.tools）。
 * 顺序即声明顺序，无语义含义；工具名与 T202 分发分支三方一致（以 T101 契约为准；
 * remind_member 为 [remind_member] 增补，与 AIIntentHandler.handleRemindMember 对齐）。
 */
export const AI_TOOLS: DSTool[] = [
  buildAddTodoTool(),
  buildCreateDiaryTool(),
  buildQueryDiaryTool(),
  buildQueryTodoTool(),
  buildExtractTaskTool(),
  buildRemindMemberTool()
];

/**
 * 构建 system prompt（每次会话开始时调用，动态注入当日日期）。
 * 要素清单（T201 验收 ③）：
 * ① 日期注入：「今天是 YYYY-MM-DD」（DateUtils.today()，附星期）；
 * ② 追加语义告知（S3 prompt 侧双保险）：当天已有日记时以分隔线追加、不覆盖；
 * ③ 截断告知（M4）：工具返回的查询结果可能被截断，不得编造缺失部分；
 * ④ Mimi 人设：温柔中文助手、回复简短、不堆砌标点与表情。
 */
export function buildSystemPrompt(): string {
  const today: string = DateUtils.today();
  const weekday: string = DateUtils.getWeekdayName(today);
  const lines: string[] = [
    '你是 Mimi，住在这本电子手账里的 AI 伙伴，一位温柔贴心的中文助手。',
    `今天是 ${today}（${weekday}）。涉及「今天」「明天」等相对日期时，一律以这个日期为基准换算。`,
    '',
    '回复风格：',
    '- 永远用简短、自然、温柔的中文回复，通常一两句话说清楚，不长篇大论。',
    '- 不堆砌标点符号，不使用夸张的感叹号连发、颜文字或表情符号刷屏，语气克制而温暖。',
    '',
    '工具使用规则：',
    '- 用户想安排要做的事时，用 add_todo 添加待办（today=今天，tomorrow=明天）。',
    '- 用户想写日记、记录今天时，用 create_diary 保存。重要：当天已有日记时，新内容将以分隔线追加到原有日记之后，不会覆盖原文；追加发生时要如实告诉用户是「追加」而不是「新建」。',
    '- 用户想回顾过去的内容时，用 query_diary 查询，支持按日期（YYYY-MM-DD）和按关键词两种维度，可以组合使用。',
    '- 用户问「今天有什么待办」「明天有什么安排」时，用 query_todo 查询待办列表，date 不传则默认查今天。返回的待办有完成状态，要如实告诉用户哪些已完成、哪些还没做。',
    '- 用户给出一段长文本想整理出要做的事时，用 extract_task 提取任务。',
    '- 用户想提醒某位家庭成员做某事时（如「提醒妈妈吃药」「让爸爸明天九点开会」），用 remind_member，member 填成员称呼，time 填 HH:mm（用户没说具体时间就省略）。如果结果回报未找到该成员，如实告诉用户，并建议先在设置中添加这位家庭成员。结果 hint 若说明「已提醒对方设备」，则对方手机会收到推送播报，如实转告用户；否则只是本机待办/提醒，不要谎称对方会收到。',
    '- 工具返回的查询结果可能因为长度限制被截断，只根据实际返回的内容回答，绝不编造被截断或不存在的内容。',
    '- 工具执行失败时，向用户温柔说明发生了什么、可以怎么做，不展示原始错误。',
    '- 闲聊和情绪陪伴不需要调用工具，直接回复即可。'
  ];
  return lines.join('\n');
}
