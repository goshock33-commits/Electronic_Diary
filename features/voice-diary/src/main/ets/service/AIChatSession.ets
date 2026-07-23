// agentID: DEV-004
// 文件: features/voice-diary/src/main/ets/service/AIChatSession.ets
// 任务: T203 会话编排——消息历史裁剪(12条/8K) + tool循环(8轮/末轮无tools) + role:tool回填 + busy/cancel/detach
// 关联架构: PLN-001_ai_plan T203 任务卡 + T101 冻结契约（DeepSeekTypes.ets 契约①②）+ JUDGE S5/M4/M5/P1
// Owner: DEV（HUI 禁改，S4 Owner 矩阵）
// Skill 参考：frontend-design / ui-ux-pro-max（本任务为纯业务会话编排层，无 UI 输出点，按 DEV 规范调用备案）
// 图标: 纯业务 service，无 $r('sys.symbol.*')（0 处，无需图标验证）
//
// ========== API 取证（本地源码级，禁凭记忆） ==========
// - DS_MAX_TOOL_ROUNDS(L19)/DSMessage(L40)/DSToolCall(L33)/DSChatResult(L157)/ToolExecResult(L168)/
//   SessionCallbacks(L181)/DSErrorKind(L144) ← shared/src/main/ets/network/DeepSeekTypes.ets（T101 冻结契约）
// - DeepSeekClient.isConfigured(L88)/chat(messages, tools?)(L143) ← shared/src/main/ets/network/DeepSeekClient.ets（T103）
// - AI_TOOLS(L108)/buildSystemPrompt(L123) ← ./AITools.ets（T201，同模块）
// - AIIntentHandler.execute(call): Promise<ToolExecResult>(L136) ← ./AIIntentHandler.ets（T202，同模块）
// - 接缝面: AIChatView.ets StubChatSession（L62-121）——constructor(callbacks)/send/cancel/detach 同构，
//   T204 替换仅动 aboutToAppear 中 new 一行；本类额外提供 reset()（任务卡要求，View 可不接）。
//
// ========== 契约与红线 ==========
// 【契约① · P1】tool 循环安全上限 = DS_MAX_TOOL_ROUNDS(8) 轮 chat 请求；正常终止 = finishReason ≠ 'tool_calls'；
//   达上限的末轮请求强制不带 tools 字段，迫使模型纯文本收尾——防 busy 挂死与 token 无界，且无「工具成功没下文」死尾。
// 【契约② · S5-4】assistant 的每个 tool_call 必须有一一对应、顺序正确的 role:'tool' 回包
//   （tool_call_id === DSToolCall.id，顺序与 tool_calls 数组一致），全部补齐才发起下一轮 chat，缺一即服务端 400。
// 【S5-1】onDone(fullText) 是气泡固化唯一信号；非流式路径 onAiText(全文) → onDone(全文)。
// 【M4】历史裁剪定死：system 恒保留，其余保留最近 12 条或总量 8K 字符预算，二者先到为准；
//   裁剪协议防线：role:'tool' 不得失去其 assistant(tool_calls) 父消息——窗口头部的孤儿 tool 消息一律丢弃。
// 【M5 · 给 T301/T302 看的解绑契约】cancel/detach/reset 共用同一套「generation 代号 + terminated 标志」机制：
//   每次 send 记录当前 generation，cancel()/detach()/reset() 使 generation 自增（在途 await 恢复后经 isStale()
//   判定过期，静默丢弃，不触达 View）；terminated=true（detach）为永久静默。T301 流式 dataReceive 回调入口
//   的 terminated 拦截即复用此标志语义。cancel 幂等：无在途请求时为空操作，连续调用安全。
// 【一致性】失败/取消不提交 working 副本——已提交历史永远停留在「上一次成功收尾」状态，
//   不存在悬空 tool_calls（否则下一轮请求必 400）。
// 【L1】未配置 Key → onError(NO_KEY, 引导文案) 直接返回，全程零网络调用（@Preview 安全）。

import { hilog } from '@kit.PerformanceAnalysisKit';
import { DeepSeekClient, DSErrorKind, DS_MAX_TOOL_ROUNDS } from '@ohos/shared';
import type { DSMessage, DSToolCall, DSChatResult, ToolExecResult, SessionCallbacks } from '@ohos/shared';
import { AI_TOOLS, buildSystemPrompt } from './AITools';
import { AIIntentHandler } from './AIIntentHandler';

const TAG: string = 'AIChatSession';
const LOG_DOMAIN: number = 0x0000;

/** 【M4】历史窗口最大消息条数（不含首条 system） */
const MAX_HISTORY_MESSAGES: number = 12;
/** 【M4】历史窗口字符预算（不含首条 system；与 12 条先到为准） */
const MAX_HISTORY_CHARS: number = 8192;
/** 未配置 Key 引导文案（View 侧 L2 还会按 errorKind 二次映射，此文案兜底可读） */
const NO_KEY_GUIDE: string = '还没有配置 DeepSeek API Key。请前往「设置 → AI 服务设置」填写并测试连接后，再回来找我聊天。';

/**
 * AIChatSession —— 会话编排核心（T203）。
 * 生命周期：View aboutToAppear 时 new AIChatSession(callbacks)；aboutToDisappear 时 cancel() + detach()【M5】。
 * 线程模型：全程主线程 async/await，无并发写 history（busy 门闩保证同一时刻至多一条在途交换）。
 */
export class AIChatSession {
  private readonly callbacks: SessionCallbacks;
  /** 已提交协议历史（首条恒为 system；只在一次交换成功收尾时整体提交） */
  private history: DSMessage[] = [];
  /** busy 门闩：true 期间 send 静默忽略 */
  private busy: boolean = false;
  /** 【M5】detach 永久静默标志（与 T301 流式 terminated 同一语义） */
  private terminated: boolean = false;
  /** 【M5】取消代号：cancel/detach/reset 自增使在途回调过期 */
  private generation: number = 0;

  constructor(callbacks: SessionCallbacks) {
    this.callbacks = callbacks;
    this.seedHistory();
  }

  /**
   * 发送一条用户消息（契约同 StubChatSession.send，fire-and-forget）。
   * busy 时静默忽略；未配置 Key 时 onError(NO_KEY) 且零网络【L1】。
   */
  send(userText: string): void {
    if (this.terminated) {
      return;
    }
    if (this.busy) {
      hilog.info(LOG_DOMAIN, TAG, 'send ignored: busy');
      return;
    }
    const text: string = userText.trim();
    if (text.length === 0) {
      return;
    }
    if (!DeepSeekClient.isConfigured()) {
      // 【L1】不发网络、不置 busy，直接错误终态
      this.callbacks.onError(DSErrorKind.NO_KEY, NO_KEY_GUIDE);
      return;
    }
    this.generation++;
    const gen: number = this.generation;
    this.busy = true;
    this.callbacks.onBusyChanged(true);
    // 工作副本：本次交换的全部消息先进副本，成功收尾才提交（失败/取消自动回滚到发送前状态）
    const working: DSMessage[] = this.history.slice();
    const userMsg: DSMessage = { role: 'user', content: text };
    working.push(userMsg);
    hilog.info(LOG_DOMAIN, TAG, 'send: gen=%{public}d textLen=%{public}d', gen, text.length);
    // fire-and-forget：runToolLoop 内部全量 try-catch，永不 reject
    this.runToolLoop(gen, working);
  }

  /**
   * 取消在途请求【M5 · 幂等】：使在途回调过期并归位 busy；无在途请求时为空操作。
   * 已产生副作用的工具调用（如已落库的待办）不回滚——取消语义只作用于 UI 触达。
   */
  cancel(): void {
    this.generation++;
    if (this.busy) {
      this.busy = false;
      if (!this.terminated) {
        this.callbacks.onBusyChanged(false);
      }
      hilog.info(LOG_DOMAIN, TAG, 'cancel: in-flight invalidated, gen=%{public}d', this.generation);
    }
  }

  /** 解绑回调【M5】：此后本会话对 View 永久静默（页面退出/切 Tab 前调用，配合 cancel 使用） */
  detach(): void {
    this.terminated = true;
    this.generation++;
    this.busy = false;
  }

  /** 重置会话：作废在途请求 + 清空历史并重新注入 system（日期随 buildSystemPrompt 刷新） */
  reset(): void {
    this.generation++;
    if (this.busy) {
      this.busy = false;
      if (!this.terminated) {
        this.callbacks.onBusyChanged(false);
      }
    }
    this.seedHistory();
    hilog.info(LOG_DOMAIN, TAG, 'reset: history reseeded');
  }

  // ========== 私有：会话循环 ==========

  /**
   * tool 循环【契约①】：至多 DS_MAX_TOOL_ROUNDS 轮 chat；正常终止 = finishReason ≠ 'tool_calls'；
   * 末轮强制不带 tools 收尾。每轮 await 恢复后先 isStale(gen) 拦截【M5】。
   * 全量 try-catch：任何异常归一为 onError，永不向上抛（send 侧 fire-and-forget 安全）。
   */
  private async runToolLoop(gen: number, working: DSMessage[]): Promise<void> {
    try {
      for (let round = 1; round <= DS_MAX_TOOL_ROUNDS; round++) {
        const finalRound: boolean = round === DS_MAX_TOOL_ROUNDS;
        const outbound: DSMessage[] = this.trimWindow(working);
        hilog.info(LOG_DOMAIN, TAG,
          'round %{public}d/%{public}d withTools=%{public}d outboundMsgs=%{public}d',
          round, DS_MAX_TOOL_ROUNDS, finalRound ? 0 : 1, outbound.length);
        // 【契约①】末轮强制不带 tools 字段（DeepSeekClient 对 undefined 不赋 request.tools）
        const result: DSChatResult = finalRound
          ? await DeepSeekClient.chat(outbound)
          : await DeepSeekClient.chat(outbound, AI_TOOLS);
        if (this.isStale(gen)) {
          hilog.info(LOG_DOMAIN, TAG, 'stale after chat, drop silently (gen=%{public}d)', gen);
          return;
        }
        if (!result.ok) {
          this.finishError(gen, result.errorKind ?? DSErrorKind.NETWORK, result.errorText ?? '网络请求失败');
          return;
        }
        const assistantMsg: DSMessage | undefined = result.message;
        if (assistantMsg === undefined) {
          this.finishError(gen, DSErrorKind.PARSE, '响应缺少 message');
          return;
        }
        working.push(assistantMsg);
        const toolCalls: DSToolCall[] = assistantMsg.tool_calls ?? [];
        // 以 tool_calls 非空为协议硬依据（finishReason==='tool_calls' 为正常信号；
        // 若 finishReason 异常但挂着 tool_calls，不回包即污染历史 → 下一轮 400，故一并执行）
        const wantsTools: boolean = toolCalls.length > 0;
        if (!wantsTools || finalRound) {
          if (toolCalls.length > 0) {
            // 防御：终局 assistant 不得携带未应答 tool_calls 入历史（末轮无 tools 理论上不会到达）
            const sanitized: DSMessage = { role: 'assistant', content: assistantMsg.content ?? '' };
            working[working.length - 1] = sanitized;
          }
          hilog.info(LOG_DOMAIN, TAG,
            'finish: rounds=%{public}d finishReason=%{public}s contentLen=%{public}d',
            round, result.finishReason ?? '', (assistantMsg.content ?? '').length);
          this.finishText(gen, working, assistantMsg.content ?? '');
          return;
        }
        // 【契约②】逐个执行工具，一一对应、顺序正确回填 role:'tool'（execute 永不抛异常，T202 保证）
        for (let i = 0; i < toolCalls.length; i++) {
          const exec: ToolExecResult = await AIIntentHandler.execute(toolCalls[i]);
          if (this.isStale(gen)) {
            hilog.info(LOG_DOMAIN, TAG, 'stale during tool exec, drop silently (gen=%{public}d)', gen);
            return;
          }
          const toolMsg: DSMessage = {
            role: 'tool',
            content: exec.resultJson,
            tool_call_id: exec.toolCallId
          };
          working.push(toolMsg);
          hilog.info(LOG_DOMAIN, TAG, 'tool %{public}d/%{public}d done: %{public}s',
            i + 1, toolCalls.length, exec.name);
        }
        // 回包齐全 → 进入下一轮 chat
      }
      // finalRound 分支必 return，理论不可达；防御兜底防 busy 挂死
      this.finishError(gen, DSErrorKind.PARSE, '会话循环异常结束，请再试一次');
    } catch (err) {
      const msg: string = (err as Error).message ?? '未知错误';
      hilog.error(LOG_DOMAIN, TAG, 'runToolLoop exception: %{public}s', msg);
      this.finishError(gen, DSErrorKind.NETWORK, '会话处理出错: ' + msg);
    }
  }

  // ========== 私有：终态与历史 ==========

  /** 成功收尾：提交历史 → 客户端模拟打字机逐字推送 onAiDelta → onDone【S5-1】→ busy 归位 */
  private finishText(gen: number, working: DSMessage[], text: string): void {
    if (this.isStale(gen)) {
      return;
    }
    this.history = this.trimWindow(working);
    // 打字机模拟：非流式拿到完整文本后，逐段推送给 UI
    if (this.callbacks.onAiDelta !== undefined && text.length > 0) {
      this.simulateTypewriter(gen, text);
    } else {
      // 无 onAiDelta 或空文本：直接走 onAiText → onDone
      this.callbacks.onAiText(text);
      this.callbacks.onDone(text);
      this.busy = false;
      this.callbacks.onBusyChanged(false);
    }
  }

  /**
   * 客户端打字机模拟：将完整文本按 2-3 字一组、间隔 30ms 逐段推送 onAiDelta。
   * 每次 push 前检查 isStale，取消/切页后立即停止推送。
   */
  private simulateTypewriter(gen: number, text: string): void {
    let pos: number = 0;
    const step: number = 2;
    const intervalMs: number = 30;
    const timer: number = setInterval(() => {
      if (this.isStale(gen)) {
        clearInterval(timer);
        return;
      }
      if (pos >= text.length) {
        clearInterval(timer);
        // 打字机结束 → 固化
        this.callbacks.onAiText(text);
        this.callbacks.onDone(text);
        this.busy = false;
        this.callbacks.onBusyChanged(false);
        return;
      }
      const end: number = Math.min(pos + step, text.length);
      const fragment: string = text.substring(pos, end);
      if (this.callbacks.onAiDelta !== undefined) {
        this.callbacks.onAiDelta(fragment);
      }
      pos = end;
    }, intervalMs);
  }

  /** 错误终态：不提交 working（历史回滚到发送前快照）→ onError → busy 归位 */
  private finishError(gen: number, kind: DSErrorKind, text: string): void {
    if (this.isStale(gen)) {
      return;
    }
    hilog.error(LOG_DOMAIN, TAG, 'finishError: kind=%{public}s text=%{public}s', kind, text);
    this.callbacks.onError(kind, text);
    this.busy = false;
    this.callbacks.onBusyChanged(false);
  }

  /** 【M5】在途回调过期判定：detach 永久静默 / generation 不匹配（cancel/reset/新 send 之后） */
  private isStale(gen: number): boolean {
    return this.terminated || gen !== this.generation;
  }

  /** 历史重置：首条 system = buildSystemPrompt()（T201，动态注入当日日期） */
  private seedHistory(): void {
    const systemMsg: DSMessage = { role: 'system', content: buildSystemPrompt() };
    const seeded: DSMessage[] = [systemMsg];
    this.history = seeded;
  }

  /**
   * 【M4】裁剪窗口：system 恒保留；其余从最新往旧累计，条数 > 12 或字符 > 8K 先到即停
   * （最新一条无条件保留，防单条超长消息把窗口裁空）。
   * 协议防线【契约②】：裁剪边界若落在 assistant(tool_calls) 与其 tool 回包之间，
   * 窗口头部的孤儿 role:'tool' 消息一律丢弃（缺父消息即服务端 400）。
   */
  private trimWindow(msgs: DSMessage[]): DSMessage[] {
    const result: DSMessage[] = [];
    if (msgs.length === 0) {
      return result;
    }
    const system: DSMessage = msgs[0];
    const rest: DSMessage[] = msgs.slice(1);
    const kept: DSMessage[] = [];
    let chars: number = 0;
    for (let i = rest.length - 1; i >= 0; i--) {
      const m: DSMessage = rest[i];
      const len: number = AIChatSession.messageLength(m);
      if (kept.length > 0 && (kept.length >= MAX_HISTORY_MESSAGES || chars + len > MAX_HISTORY_CHARS)) {
        break;
      }
      kept.unshift(m);
      chars += len;
    }
    while (kept.length > 0 && kept[0].role === 'tool') {
      kept.shift();
    }
    if (kept.length < rest.length) {
      hilog.info(LOG_DOMAIN, TAG, 'trimWindow: kept=%{public}d dropped=%{public}d chars=%{public}d',
        kept.length, rest.length - kept.length, chars);
    }
    result.push(system);
    for (let i = 0; i < kept.length; i++) {
      result.push(kept[i]);
    }
    return result;
  }

  /** 消息字符量估算：content + tool_calls(id/name/arguments)（M4 预算口径） */
  private static messageLength(m: DSMessage): number {
    let len: number = m.content !== undefined ? m.content.length : 0;
    const calls: DSToolCall[] = m.tool_calls ?? [];
    for (let i = 0; i < calls.length; i++) {
      len += calls[i].id.length + calls[i].function.name.length + calls[i].function.arguments.length;
    }
    return len;
  }
}
