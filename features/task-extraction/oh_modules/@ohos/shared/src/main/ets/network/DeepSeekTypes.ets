// <!-- agentID: DEV-004 -->
// 文件: shared/src/main/ets/network/DeepSeekTypes.ets
// 任务: T101 DeepSeek OpenAI 兼容协议全局契约类型（阶段 1A 全局解锁点）
// 说明: 纯类型/常量文件，零实现、零网络调用。ArkTS 严格模式 §8.3：无 any、无索引签名。
// 冻结声明: 本文件落地后即冻结——它是 1A/1B/1C 全部并行任务的共同类型基础，改动需回 PLN 重排。
//
// ========== 全局契约注释 ==========
// 【契约① · S5-3 + P1】tool 循环安全上限 = 8 轮（见常量 DS_MAX_TOOL_ROUNDS）。
//   正常终止条件: finishReason !== 'tool_calls'。
//   达到 8 轮上限时，末轮请求必须强制不携带 tools 字段（DSChatRequest.tools 不赋值），
//   迫使模型以纯文本收尾，杜绝无限工具循环。
// 【契约② · S5-4】assistant 消息中的每一个 tool_call，必须有一一对应、顺序正确的
//   role:"tool" 回包消息（其 tool_call_id 与对应 DSToolCall.id 严格相等，顺序与
//   tool_calls 数组一致），全部回包补齐后才能发起下一轮 chat 请求；缺失或乱序会被服务端拒绝。

// ========== 常量 ==========

/** 契约①：tool 循环安全上限（轮） */
export const DS_MAX_TOOL_ROUNDS: number = 8;

// ========== OpenAI 兼容协议类型 ==========

/** 消息角色（OpenAI 兼容封闭字面量联合） */
export type DSRole = 'system' | 'user' | 'assistant' | 'tool';

/** 函数调用体（模型发起）：arguments 为 JSON 字符串（可能分片累积） */
export interface DSFunctionCall {
  name: string;
  arguments: string;
}

/** assistant 消息中的一次工具调用；type 恒为 'function' */
export interface DSToolCall {
  id: string;
  type: string;
  function: DSFunctionCall;
}

/** 会话消息。role='tool' 时必须携带 tool_call_id（契约②）；role='assistant' 且发起工具调用时携带 tool_calls */
export interface DSMessage {
  role: DSRole;
  content?: string;
  tool_calls?: DSToolCall[];
  tool_call_id?: string;
}

/** JSON Schema 单属性描述（无索引签名，供 Record 值使用） */
export interface DSSchemaProp {
  type: string;
  description?: string;
  enum?: string[];
  items?: DSSchemaProp;
}

/** 函数参数 JSON Schema：properties 用 Record<string, DSSchemaProp> 规避 ArkTS 禁索引签名 */
export interface DSJsonSchema {
  type: string;
  properties?: Record<string, DSSchemaProp>;
  required?: string[];
}

/** 函数定义（工具声明侧） */
export interface DSFunctionDef {
  name: string;
  description: string;
  parameters: DSJsonSchema;
}

/** 请求侧工具声明；type 恒为 'function' */
export interface DSTool {
  type: string;
  function: DSFunctionDef;
}

/** 流式分片中的函数调用增量（name/arguments 均可能分片） */
export interface DSStreamFunctionCall {
  name?: string;
  arguments?: string;
}

/** 流式分片中的工具调用增量：index 用于按位聚合同一次 tool_call 的分片 */
export interface DSStreamToolCall {
  index: number;
  id?: string;
  type?: string;
  function?: DSStreamFunctionCall;
}

/** 流式增量体 */
export interface DSDelta {
  role?: string;
  content?: string;
  tool_calls?: DSStreamToolCall[];
}

/** 流式分片中的单选择 */
export interface DSStreamChoice {
  index?: number;
  delta: DSDelta;
  finish_reason?: string;
}

/** SSE 流式分片（data: {...} 反序列化结果） */
export interface DSStreamChunk {
  id?: string;
  model?: string;
  choices: DSStreamChoice[];
}

/** chat/completions 请求体。契约①：末轮（第 8 轮）强制不携带 tools 字段 */
export interface DSChatRequest {
  model: string;
  messages: DSMessage[];
  stream?: boolean;
  tools?: DSTool[];
  tool_choice?: string;
  temperature?: number;
  max_tokens?: number;
}

/** token 用量统计（非流式响应携带） */
export interface DSUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
}

/** 非流式响应中的单选择 */
export interface DSChoice {
  index?: number;
  message: DSMessage;
  finish_reason?: string;
}

/** chat/completions 非流式响应体 */
export interface DSChatResponse {
  id?: string;
  model?: string;
  choices: DSChoice[];
  usage?: DSUsage;
}

/** 封闭错误枚举【S5-2】：http_402 = DeepSeek 余额不足 */
export enum DSErrorKind {
  NO_KEY = 'no_key',
  NETWORK = 'network',
  HTTP_401 = 'http_401',
  HTTP_402 = 'http_402',
  HTTP_429 = 'http_429',
  HTTP_5XX = 'http_5xx',
  TIMEOUT = 'timeout',
  PARSE = 'parse',
  CANCELLED = 'cancelled'
}

/** 单轮聊天归一化结果：ok=true 时 message/finishReason 有效；ok=false 时 errorKind/errorText 有效 */
export interface DSChatResult {
  ok: boolean;
  message?: DSMessage;
  finishReason?: string;
  errorKind?: DSErrorKind;
  errorText?: string;
}

// ========== 工具执行回传（AIIntentHandler → AIChatSession） ==========

/** 单个工具执行结果：resultJson 为序列化后的 JSON 字符串，回填为 role:"tool" 消息（契约②） */
export interface ToolExecResult {
  toolCallId: string;
  name: string;
  resultJson: string;
}

// ========== 会话回调（AIChatSession → UI） ==========

/**
 * 会话生命周期回调。
 * 【S5-1】onDone 是流结束/气泡固化的唯一信号：onAiText/onAiDelta 只做过程渲染，
 * UI 仅在 onDone(fullText) 到达时才将气泡固化落库。
 */
export interface SessionCallbacks {
  /** 全量文本更新（每次覆盖式推送当前累计全文） */
  onAiText: (fullText: string) => void;
  /** 可选增量片段（打字机效果用） */
  onAiDelta?: (fragment: string) => void;
  /** 流结束/气泡固化唯一信号【S5-1】 */
  onDone: (fullText: string) => void;
  /** 错误终态 */
  onError: (errorKind: DSErrorKind, errorText: string) => void;
  /** 忙碌状态变更（发送中/工具循环中 = true） */
  onBusyChanged: (busy: boolean) => void;
}
