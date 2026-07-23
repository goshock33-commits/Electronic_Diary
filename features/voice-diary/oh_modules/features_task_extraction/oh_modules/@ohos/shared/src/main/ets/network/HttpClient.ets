// agentID: DEV-004
// 文件: shared/src/main/ets/network/HttpClient.ets
// 任务: T103 shared 网络层——@kit.NetworkKit http 封装（本任务只做 postJson/getJson 非流式；postStream 留给 T301）
// 关联架构: PLN-001_ai_plan T103 / JUDGE F1/M2/M8
// Skill 参考：frontend-design / ui-ux-pro-max（本任务为纯业务网络层，无 UI 输出点，按 DEV 规范调用备案）
// API 依据（本地 SDK API 24 @ohos.net.http.d.ts）:
//   createHttp() L84 / request(url, options): Promise<HttpResponse> L1718
//   HttpRequestOptions{ method L154 / extraData L179 / expectDataType L201 / header L267 / readTimeout L289 / connectTimeout L311 }
//   HttpDataType.STRING L3546 / HttpResponse.result L3632 / responseCode L3682
//   错误码: 201 权限拒绝 / 2300006 DNS 失败 / 2300007 连接失败 / 2300028 超时

import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DSErrorKind } from './DeepSeekTypes';

const TAG: string = 'HttpClient';
const LOG_DOMAIN: number = 0xFF00;

/** 默认超时（毫秒）：读取与连接共用 */
const DEFAULT_TIMEOUT_MS: number = 30000;

/** libcurl 错误码：操作超时（@ohos.net.http.d.ts 注释 2300028 Operation timeout） */
const ERR_CODE_TIMEOUT: number = 2300028;

/**
 * HTTP 文本响应归一化结果。
 * ok=true 表示传输层成功拿到 HTTP 响应（不代表 2xx，status 由上层裁决）；
 * ok=false 表示传输层失败（断网/超时/DNS 等），errorKind/errorText 有效，status 恒为 0。
 */
export interface HttpTextResponse {
  ok: boolean;
  status: number;
  body: string;
  errorKind?: DSErrorKind;
  errorText?: string;
  /** 传输层原始错误码（ok=false 时有效，如 2300006 DNS 解析失败），供上层做精细提示 */
  errorCode?: number;
}

/**
 * HttpClient —— @kit.NetworkKit http 的最小非流式封装。
 * 生命周期：每次请求 createHttp() → request() → finally destroy()，不复用实例。
 */
export class HttpClient {
  /**
   * POST JSON 文本请求。
   * @param url 完整 URL（必须 https，@ohos.net.http 无自动升级，明文 http 命中 2300997）
   * @param headers 请求头（调用方注入 Authorization / Content-Type）
   * @param body 已序列化的 JSON 字符串
   * @param timeoutMs 可选超时（读取+连接共用），默认 30000ms
   */
  static async postJson(url: string, headers: Record<string, string>, body: string,
    timeoutMs?: number): Promise<HttpTextResponse> {
    return HttpClient.requestText(url, http.RequestMethod.POST, headers, body, timeoutMs);
  }

  /**
   * GET 文本请求（T103 testConnection GET /models 用；同样走统一错误映射）。
   */
  static async getJson(url: string, headers: Record<string, string>,
    timeoutMs?: number): Promise<HttpTextResponse> {
    return HttpClient.requestText(url, http.RequestMethod.GET, headers, undefined, timeoutMs);
  }

  /**
   * 统一请求核心：createHttp → request → finally destroy。
   * 异常按 error.code 分类映射为 DSErrorKind（2300028→TIMEOUT，其余→NETWORK）。
   */
  private static async requestText(url: string, method: http.RequestMethod,
    headers: Record<string, string>, body?: string, timeoutMs?: number): Promise<HttpTextResponse> {
    const httpRequest: http.HttpRequest = http.createHttp();
    const timeout: number = timeoutMs ?? DEFAULT_TIMEOUT_MS;
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: timeout,
        connectTimeout: timeout
      };
      if (body !== undefined) {
        options.extraData = body;
      }
      const response: http.HttpResponse = await httpRequest.request(url, options);
      const bodyText: string = typeof response.result === 'string' ? response.result as string : '';
      const okResult: HttpTextResponse = {
        ok: true,
        status: response.responseCode,
        body: bodyText
      };
      return okResult;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      const kind: DSErrorKind = HttpClient.mapTransportError(e.code);
      hilog.error(LOG_DOMAIN, TAG, 'request failed code=%{public}d msg=%{public}s',
        e.code, e.message ?? '');
      const failResult: HttpTextResponse = {
        ok: false,
        status: 0,
        body: '',
        errorKind: kind,
        errorText: HttpClient.transportErrorText(e.code, e.message ?? ''),
        errorCode: e.code
      };
      return failResult;
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * POST JSON 流式请求（SSE）：逐行读取 data: 行，通过 onData 回调推送分片。
   * @param onData 每收到一行 `data: {...}` 的 JSON 片段时调用（已去除 `data: ` 前缀）。
   *   data: [DONE] 不触发 onData（流结束由 Promise resolve 表示）。
   * @returns 传输层结果（ok=true 仅表示流正常结束；HTTP 错误时 body 含错误体）
   */
  static async postStream(
    url: string,
    headers: Record<string, string>,
    body: string,
    onData: (chunk: string) => void,
    timeoutMs?: number
  ): Promise<HttpTextResponse> {
    const httpRequest: http.HttpRequest = http.createHttp();
    const timeout: number = timeoutMs ?? DEFAULT_TIMEOUT_MS;
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: timeout,
        connectTimeout: timeout
      };
      options.extraData = body;

      // 注册流式数据接收回调
      httpRequest.on('dataReceive', (data: ArrayBuffer | string) => {
        if (typeof data === 'string') {
          HttpClient.parseSSEChunk(data, onData);
        } else {
          // ArrayBuffer → 解码 UTF-8 字符串
          const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
          const text: string = decoder.decodeToString(new Uint8Array(data));
          HttpClient.parseSSEChunk(text, onData);
        }
      });

      const response: http.HttpResponse = await httpRequest.request(url, options);
      const bodyText: string = typeof response.result === 'string' ? response.result as string : '';
      return {
        ok: true,
        status: response.responseCode,
        body: bodyText
      };
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      const kind: DSErrorKind = HttpClient.mapTransportError(e.code);
      hilog.error(LOG_DOMAIN, TAG, 'postStream failed code=%{public}d msg=%{public}s',
        e.code, e.message ?? '');
      return {
        ok: false,
        status: 0,
        body: '',
        errorKind: kind,
        errorText: HttpClient.transportErrorText(e.code, e.message ?? ''),
        errorCode: e.code
      };
    } finally {
      try {
        httpRequest.off('dataReceive');
      } catch (_e) {
        // off 可能已随 destroy 失效，忽略
      }
      httpRequest.destroy();
    }
  }

  /**
   * SSE 分片解析：将接收到的文本按 \n 分行，提取 `data: ` 前缀的行。
   * 跨 chunk 的不完整行通过 buffer 累积（静态变量）。
   */
  private static sseBuffer: string = '';

  private static parseSSEChunk(raw: string, onData: (chunk: string) => void): void {
    HttpClient.sseBuffer += raw;
    const lines: string[] = HttpClient.sseBuffer.split('\n');
    // 最后一段可能不完整，保留到 buffer
    HttpClient.sseBuffer = lines[lines.length - 1] ?? '';
    for (let i = 0; i < lines.length - 1; i++) {
      const line: string = lines[i].trim();
      if (line.startsWith('data:')) {
        const payload: string = line.substring(5).trim();
        if (payload === '[DONE]' || payload.length === 0) {
          continue;
        }
        onData(payload);
      }
    }
  }

  /** 传输层错误码 → DSErrorKind 封闭枚举映射 */
  private static mapTransportError(code: number): DSErrorKind {
    if (code === ERR_CODE_TIMEOUT) {
      return DSErrorKind.TIMEOUT;
    }
    return DSErrorKind.NETWORK;
  }

  /** 传输层错误可读文案（201 权限缺失单独提示，便于 M9 排障） */
  private static transportErrorText(code: number, message: string): string {
    if (code === 201) {
      return '网络权限未授予（201）：请确认 ohos.permission.INTERNET 已声明且 App 已重新安装';
    }
    if (code === ERR_CODE_TIMEOUT) {
      return `请求超时（${code}）`;
    }
    return `网络请求失败（${code}）：${message}`;
  }
}
