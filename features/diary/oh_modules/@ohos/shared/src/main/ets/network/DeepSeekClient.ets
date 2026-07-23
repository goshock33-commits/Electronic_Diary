// agentID: DEV-004
// 文件: shared/src/main/ets/network/DeepSeekClient.ets
// 任务: T103 shared 网络层——DeepSeek 客户端（chat 非流式 / testConnection / isConfigured）
// 关联架构: PLN-001_ai_plan T103 / JUDGE F1（模型常量集中）/ M2（testConnection=GET /models）/ M8（统一注入头）
// Skill 参考：frontend-design / ui-ux-pro-max（本任务为纯业务网络层，无 UI 输出点，按 DEV 规范调用备案）
// Key 通路: T102 PersistentState.isApiKeyConfigured() / getApiKey()（AES 加密读取，已与 DEV-T102 对齐签名）

import { hilog } from '@kit.PerformanceAnalysisKit';
import { HttpClient, HttpTextResponse } from './HttpClient';
import {
  DSChatRequest,
  DSChatResult,
  DSErrorKind,
  DSMessage,
  DSTool,
  DSStreamChunk,
  DSStreamChoice,
  DSToolCall,
  DSStreamToolCall,
  DSFunctionCall
} from './DeepSeekTypes';
import { PersistentState } from '../state/PersistentState';

// ========== 集中常量区【F1】：模型 ID / 地址全工程仅此一处，禁止散落 ==========

/** 模型 ID（旧 chat 模型 2026-07-24 停用，本 ID 为官方直接替代；F1：改模型只改这一行） */
export const MODEL_ID: string = 'deepseek-v4-flash';

/** API 基地址（https 硬编码：@ohos.net.http 无自动升级，明文 http 命中 2300997） */
export const BASE_URL: string = 'https://api.deepseek.com';

/** 对话补全路径（OpenAI 兼容） */
export const PATH_CHAT: string = '/v1/chat/completions';

/** 模型列表路径（testConnection 专用，免费轻量） */
export const PATH_MODELS: string = '/models';

const TAG: string = 'DeepSeekClient';
const LOG_DOMAIN: number = 0xFF00;

/** chat 请求超时（毫秒）：非流式全量生成较慢，放宽到 60s */
const CHAT_TIMEOUT_MS: number = 60000;

/** testConnection 超时（毫秒）：轻量 GET，15s 足够 */
const TEST_TIMEOUT_MS: number = 15000;

// ========== 仅本文件使用的宽松解析类型（JSON.parse 防御：字段全可选，ArkTS §8.3 as 到接口） ==========

/** GET /models 响应单条模型 */
interface DSModelItem {
  id?: string;
  object?: string;
}

/** GET /models 响应体 */
interface DSModelsResponse {
  object?: string;
  data?: DSModelItem[];
}

/** 非流式响应 choice（宽松版：运行时字段可能缺失） */
interface DSLooseChoice {
  index?: number;
  message?: DSMessage;
  finish_reason?: string;
}

/** 非流式响应体（宽松版） */
interface DSLooseChatResponse {
  id?: string;
  model?: string;
  choices?: DSLooseChoice[];
}

/** DeepSeek 错误响应体 error 字段 */
interface DSErrorDetail {
  message?: string;
  type?: string;
  code?: string;
}

/** DeepSeek 错误响应体 */
interface DSErrorBody {
  error?: DSErrorDetail;
}

/**
 * chat 可选生成参数（HUI-001 ghost text 内联补全）：
 * 映射到 DSChatRequest 既有 temperature / max_tokens 字段（DeepSeekTypes 冻结文件未动）。
 * 不传保持原行为（服务端默认值），向后兼容全部既有调用方。
 */
export interface DSChatOptions {
  temperature?: number;
  maxTokens?: number;
  model?: string; // HUI-001: ghost text 临时指定模型（deepseek-v4-flash 返回空排查用）
}

/** 流式 tool_calls 聚合缓存项（按 index 累积 name/arguments 分片） */
interface StreamToolCallEntry {
  id: string;
  name: string;
  arguments: string;
}

/**
 * DeepSeekClient —— OpenAI 兼容协议客户端（非流式）。
 * 流式 chatStream 已实现（T301）；本类提供 isConfigured / testConnection / chat / chatStream。
 */
export class DeepSeekClient {
  /** 是否已配置 API Key（T102 加密持久化通路，同步判断密文串非空） */
  static isConfigured(): boolean {
    return PersistentState.isApiKeyConfigured();
  }

  /**
   * 连接测试【M2】：GET /models（免费轻量，200=Key 有效 / 401=无效），禁止用发一条 chat 代替。
   * 加分项：200 时校验 MODEL_ID 是否在返回列表中，提前发现模型下线。
   * 三分支可区分：正确 Key → ok=true；错误 Key → errorKind=HTTP_401；断网 → errorKind=NETWORK/TIMEOUT。
   */
  static async testConnection(): Promise<DSChatResult> {
    const key: string = await DeepSeekClient.readKey();
    if (key === '') {
      return DeepSeekClient.fail(DSErrorKind.NO_KEY, '未配置 API Key，请先在设置中填写');
    }
    const resp: HttpTextResponse = await HttpClient.getJson(
      BASE_URL + PATH_MODELS, DeepSeekClient.buildHeaders(key), TEST_TIMEOUT_MS);
    if (!resp.ok) {
      return DeepSeekClient.fail(resp.errorKind ?? DSErrorKind.NETWORK, resp.errorText ?? '网络请求失败');
    }
    if (resp.status !== 200) {
      return DeepSeekClient.mapHttpFailure(resp.status, resp.body);
    }
    // 200：Key 有效；顺带校验 MODEL_ID 是否在列（解析失败不影响成功判定）
    let modelListed: boolean = false;
    try {
      const models: DSModelsResponse = JSON.parse(resp.body) as DSModelsResponse;
      const list: DSModelItem[] = models.data ?? [];
      for (let i = 0; i < list.length; i++) {
        if (list[i].id === MODEL_ID) {
          modelListed = true;
          break;
        }
      }
    } catch (err) {
      hilog.warn(LOG_DOMAIN, TAG, 'testConnection models parse failed: %{public}s', (err as Error).message);
      modelListed = true; // 解析失败按连接成功处理，不误报模型下线
    }
    const message: DSMessage = {
      role: 'assistant',
      content: modelListed ? '连接成功，模型可用' : `连接成功，但模型 ${MODEL_ID} 不在服务列表中（可能已下线）`
    };
    const result: DSChatResult = {
      ok: true,
      message: message,
      finishReason: 'stop'
    };
    return result;
  }

  /**
   * 非流式对话。组 DSChatRequest → postJson → 解析 → DSChatResult。
   * HTTP 状态码按 DSErrorKind 封闭枚举映射（401/402/429/5xx/超时/解析失败/断网各归其位）。
   * @param messages 会话消息（契约②：tool 回包须一一对应，由上层会话逻辑保证）
   * @param tools 可选工具声明（契约①：末轮强制不传由上层控制）
   * @param options 可选生成参数（HUI-001：ghost text 短补全用 max_tokens/temperature；不传保持原行为）
   */
  static async chat(messages: DSMessage[], tools?: DSTool[], options?: DSChatOptions): Promise<DSChatResult> {
    const key: string = await DeepSeekClient.readKey();
    if (key === '') {
      return DeepSeekClient.fail(DSErrorKind.NO_KEY, '未配置 API Key，请先在设置中填写');
    }
    const request: DSChatRequest = {
      model: MODEL_ID,
      messages: messages,
      stream: false
    };
    if (tools !== undefined && tools.length > 0) {
      request.tools = tools;
    }
    if (options !== undefined) {
      if (options.temperature !== undefined) {
        request.temperature = options.temperature;
      }
      if (options.maxTokens !== undefined) {
        request.max_tokens = options.maxTokens;
      }
      if (options.model !== undefined) {
        request.model = options.model;
      }
    }
    const resp: HttpTextResponse = await HttpClient.postJson(
      BASE_URL + PATH_CHAT, DeepSeekClient.buildHeaders(key), JSON.stringify(request), CHAT_TIMEOUT_MS);
    if (!resp.ok) {
      return DeepSeekClient.fail(resp.errorKind ?? DSErrorKind.NETWORK, resp.errorText ?? '网络请求失败');
    }
    if (resp.status !== 200) {
      return DeepSeekClient.mapHttpFailure(resp.status, resp.body);
    }
    return DeepSeekClient.parseChatBody(resp.body);
  }

  /**
   * 流式对话（T301）：POST /v1/chat/completions with stream:true。
   * 逐 token 通过 onDelta 回调推送分片文本；流结束时 resolve DSChatResult（含完整 message）。
   * @param messages 会话消息
   * @param tools 可选工具声明
   * @param options 可选生成参数
   * @param onDelta 每收到一个文本分片时回调（仅 content 增量；tool_calls 增量内部聚合不外推）
   * @returns DSChatResult — ok=true 时 message.content 为完整文本，finishReason 为流终止原因
   */
  static async chatStream(
    messages: DSMessage[],
    tools: DSTool[] | undefined,
    options: DSChatOptions | undefined,
    onDelta: (fragment: string) => void
  ): Promise<DSChatResult> {
    const key: string = await DeepSeekClient.readKey();
    if (key === '') {
      return DeepSeekClient.fail(DSErrorKind.NO_KEY, '未配置 API Key，请先在设置中填写');
    }
    const request: DSChatRequest = {
      model: MODEL_ID,
      messages: messages,
      stream: true
    };
    if (tools !== undefined && tools.length > 0) {
      request.tools = tools;
    }
    if (options !== undefined) {
      if (options.temperature !== undefined) {
        request.temperature = options.temperature;
      }
      if (options.maxTokens !== undefined) {
        request.max_tokens = options.maxTokens;
      }
      if (options.model !== undefined) {
        request.model = options.model;
      }
    }
    let fullText: string = '';
    let finishReason: string = 'stop';
    // 流式 tool_calls 聚合（按 index 累积 name/arguments 分片）
    const toolCallMap: Map<number, StreamToolCallEntry> = new Map();

    const resp: HttpTextResponse = await HttpClient.postStream(
      BASE_URL + PATH_CHAT,
      DeepSeekClient.buildHeaders(key),
      JSON.stringify(request),
      (chunk: string) => {
        try {
          const parsed: DSStreamChunk = JSON.parse(chunk) as DSStreamChunk;
          const choices: DSStreamChoice[] = parsed.choices ?? [];
          for (let i = 0; i < choices.length; i++) {
            const choice: DSStreamChoice = choices[i];
            if (choice.finish_reason !== undefined && choice.finish_reason !== null) {
              finishReason = choice.finish_reason;
            }
            const delta = choice.delta;
            if (delta === undefined) {
              continue;
            }
            // 文本增量
            if (delta.content !== undefined && delta.content.length > 0) {
              fullText += delta.content;
              onDelta(delta.content);
            }
            // tool_calls 增量聚合
            if (delta.tool_calls !== undefined) {
              for (let j = 0; j < delta.tool_calls.length; j++) {
                const tc: DSStreamToolCall = delta.tool_calls[j];
                let entry: StreamToolCallEntry | undefined = toolCallMap.get(tc.index);
                if (entry === undefined) {
                  const newEntry: StreamToolCallEntry = { id: '', name: '', arguments: '' };
                  toolCallMap.set(tc.index, newEntry);
                  entry = newEntry;
                }
                if (tc.id !== undefined) {
                  entry.id = tc.id;
                }
                if (tc.function !== undefined) {
                  if (tc.function.name !== undefined) {
                    entry.name += tc.function.name;
                  }
                  if (tc.function.arguments !== undefined) {
                    entry.arguments += tc.function.arguments;
                  }
                }
              }
            }
          }
        } catch (err) {
          hilog.warn(LOG_DOMAIN, TAG, 'chatStream chunk parse failed: %{public}s', (err as Error).message);
        }
      },
      CHAT_TIMEOUT_MS
    );

    if (!resp.ok) {
      return DeepSeekClient.fail(resp.errorKind ?? DSErrorKind.NETWORK, resp.errorText ?? '网络请求失败');
    }
    if (resp.status !== 200) {
      return DeepSeekClient.mapHttpFailure(resp.status, resp.body);
    }

    // 组装最终 message
    const message: DSMessage = { role: 'assistant', content: fullText };
    if (toolCallMap.size > 0) {
      const toolCalls: DSToolCall[] = [];
      const indices: number[] = Array.from(toolCallMap.keys()).sort((a: number, b: number): number => a - b);
      for (let k = 0; k < indices.length; k++) {
        const entry: StreamToolCallEntry | undefined = toolCallMap.get(indices[k]);
        if (entry === undefined) {
          continue;
        }
        const fnCall: DSFunctionCall = { name: entry.name, arguments: entry.arguments };
        toolCalls.push({
          id: entry.id,
          type: 'function',
          function: fnCall
        });
      }
      message.tool_calls = toolCalls;
    }
    return { ok: true, message: message, finishReason: finishReason };
  }

  // ========== 私有工具 ==========

  /** 读取 Key（T102 AES 解密通路；未配置/解密失败返回 ''） */
  private static async readKey(): Promise<string> {
    if (!PersistentState.isApiKeyConfigured()) {
      return '';
    }
    return PersistentState.getApiKey();
  }

  /** 统一注入头【M8】：Authorization: Bearer <key> + Content-Type: application/json */
  private static buildHeaders(key: string): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['Authorization'] = 'Bearer ' + key;
    headers['Content-Type'] = 'application/json';
    return headers;
  }

  /** 解析非流式 200 响应体 → DSChatResult（缺 choices/message → PARSE） */
  private static parseChatBody(body: string): DSChatResult {
    try {
      const parsed: DSLooseChatResponse = JSON.parse(body) as DSLooseChatResponse;
      const choices: DSLooseChoice[] = parsed.choices ?? [];
      if (choices.length === 0) {
        return DeepSeekClient.fail(DSErrorKind.PARSE, '响应缺少 choices');
      }
      const first: DSLooseChoice = choices[0];
      const message: DSMessage | undefined = first.message;
      if (message === undefined) {
        return DeepSeekClient.fail(DSErrorKind.PARSE, '响应缺少 message');
      }
      const result: DSChatResult = {
        ok: true,
        message: message,
        finishReason: first.finish_reason ?? 'stop'
      };
      return result;
    } catch (err) {
      return DeepSeekClient.fail(DSErrorKind.PARSE, `响应 JSON 解析失败: ${(err as Error).message}`);
    }
  }

  /** HTTP 非 200 状态码 → DSErrorKind 封闭枚举映射（401→HTTP_401 / 402→HTTP_402 余额不足 / 429→HTTP_429 / 5xx→HTTP_5XX） */
  private static mapHttpFailure(status: number, body: string): DSChatResult {
    let kind: DSErrorKind = DSErrorKind.NETWORK;
    if (status === 401) {
      kind = DSErrorKind.HTTP_401;
    } else if (status === 402) {
      kind = DSErrorKind.HTTP_402;
    } else if (status === 429) {
      kind = DSErrorKind.HTTP_429;
    } else if (status >= 500) {
      kind = DSErrorKind.HTTP_5XX;
    }
    hilog.error(LOG_DOMAIN, TAG, 'http failure status=%{public}d kind=%{public}s', status, kind);
    return DeepSeekClient.fail(kind, DeepSeekClient.httpFailureText(status, body));
  }

  /** 组装可读错误文案：优先取 DeepSeek 错误体 error.message */
  private static httpFailureText(status: number, body: string): string {
    let detail: string = '';
    try {
      const errBody: DSErrorBody = JSON.parse(body) as DSErrorBody;
      const errDetail: DSErrorDetail | undefined = errBody.error;
      if (errDetail !== undefined && errDetail.message !== undefined) {
        detail = errDetail.message;
      }
    } catch (err) {
      detail = '';
    }
    if (status === 401) {
      return detail !== '' ? `API Key 无效（401）：${detail}` : 'API Key 无效（401），请检查设置中的 Key';
    }
    if (status === 402) {
      return detail !== '' ? `账户余额不足（402）：${detail}` : '账户余额不足（402），请前往 DeepSeek 充值';
    }
    if (status === 429) {
      return detail !== '' ? `请求过于频繁（429）：${detail}` : '请求过于频繁（429），请稍后再试';
    }
    if (status >= 500) {
      return detail !== '' ? `服务端错误（${status}）：${detail}` : `DeepSeek 服务端错误（${status}），请稍后再试`;
    }
    return detail !== '' ? `请求失败（HTTP ${status}）：${detail}` : `请求失败（HTTP ${status}）`;
  }

  /** 失败结果构造 */
  private static fail(kind: DSErrorKind, text: string): DSChatResult {
    const result: DSChatResult = {
      ok: false,
      errorKind: kind,
      errorText: text
    };
    return result;
  }
}
