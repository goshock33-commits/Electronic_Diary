// agentID: DEV-D2
// File: VoiceFocusManager.ets
// Task: ASR <-> TTS 互斥焦点状态机（speaking 时不启 ASR；listening 时强停 TTS）
// Architecture: ARC-001 4.5 / 4.6 事件可靠性策略（经 EventBus 字符串事件同步状态）
// SDK: HarmonyOS 6.1.1 (API 24)
//
// 设计说明：
// - 三态：IDLE / LISTENING(ASR 占用) / SPEAKING(TTS 占用)，单一持有者 token 制。
// - 规则 1（speaking 时不启 ASR）：state === SPEAKING 时 requestListen() 返回 0（硬拒绝），
//   防止 TTS 播报音被麦克风回采造成回声误识别。
// - 规则 2（listening 时停止 TTS）：进入 LISTENING 时无条件广播 EVENT_TTS_STOP（防御性强停，
//   覆盖 TTS 完成回调丢失导致的状态漂移）；且 LISTENING 期间 requestSpeak() 返回 0。
// - EventBus 同步：状态每次变更广播 EVENT_FOCUS_CHANGED（flat payload：state/previous/source），
//   TTS 强停广播 EVENT_TTS_STOP（payload：reason/source），订阅方（TTS 引擎持有页）收到后须
//   调 engine.stop() 并 releaseSpeak(token)。
// - watchdog：持有者异常未释放（引擎崩溃/回调丢失）时超时自动回收，避免语音链路永久死锁。
//
// 用法：
//   // ASR 侧（长按说话）：
//   const token = VoiceFocusManager.requestListen('AIChatView');
//   if (token === 0) { /* TTS 播报中，提示用户稍候 */ return; }
//   ... startListening ...
//   VoiceFocusManager.releaseListen(token); // onComplete/onError/onCancel
//
//   // TTS 侧（AI 回复播报）：
//   const token = VoiceFocusManager.requestSpeak('AIChatView');
//   if (token === 0) { /* 正在录音，跳过/排队 */ return; }
//   EventBus.on(VoiceFocusManager.EVENT_TTS_STOP, () => { engine.stop(); });
//   ... engine.speak ...
//   VoiceFocusManager.releaseSpeak(token); // onComplete/onStop/onError

import { hilog } from '@kit.PerformanceAnalysisKit';
import { EventBus } from './EventBus';

const TAG = 'VoiceFocusManager';

/** ASR 持有焦点的 watchdog 上限：60s（短语音识别场景远小于此，仅防回调丢失死锁） */
const LISTEN_WATCHDOG_MS = 60000;
/** TTS 持有焦点的 watchdog 上限：120s（长文本播报上限，仅防回调丢失死锁） */
const SPEAK_WATCHDOG_MS = 120000;

/**
 * 语音焦点状态（互斥）。
 */
export enum VoiceFocusState {
  /** 空闲：ASR 与 TTS 均可申请 */
  IDLE = 'idle',
  /** ASR 录音识别中：TTS 申请被拒，进入时广播 EVENT_TTS_STOP 强停残留播报 */
  LISTENING = 'listening',
  /** TTS 播报中：ASR 申请被拒（防回声误识别） */
  SPEAKING = 'speaking'
}

/**
 * VoiceFocusManager - ASR/TTS 互斥焦点状态机（应用级单例，静态类，风格对齐 EventBus）。
 *
 * 状态迁移：
 *   IDLE --requestListen()--> LISTENING --releaseListen()--> IDLE
 *   IDLE --requestSpeak()---> SPEAKING  --releaseSpeak()---> IDLE
 *   SPEAKING 期间 requestListen() 拒绝（返回 0）
 *   LISTENING 期间 requestSpeak() 拒绝（返回 0）
 *   SPEAKING --stopSpeaking()--> IDLE（广播 EVENT_TTS_STOP，持有方收到后停引擎）
 */
export class VoiceFocusManager {
  /** 焦点状态变更事件（payload: state/previous/source 均为 string） */
  static readonly EVENT_FOCUS_CHANGED: string = 'event:voice:focus-changed';
  /** TTS 强停指令事件（payload: reason/source 均为 string）——TTS 引擎持有页订阅后须 stop() */
  static readonly EVENT_TTS_STOP: string = 'event:voice:tts-stop';

  /** 当前焦点状态 */
  private static state: VoiceFocusState = VoiceFocusState.IDLE;
  /** 当前持有者 token（0 = 无持有者） */
  private static ownerToken: number = 0;
  /** 当前持有者标识（调试用来源名） */
  private static ownerSource: string = '';
  /** token 发号器 */
  private static nextToken: number = 1;
  /** watchdog 定时器 id（-1 = 未启动） */
  private static watchdogTimer: number = -1;

  // ==================== 查询 ====================

  /** 当前状态 */
  static getState(): VoiceFocusState {
    return VoiceFocusManager.state;
  }

  /** TTS 是否播报中 */
  static isSpeaking(): boolean {
    return VoiceFocusManager.state === VoiceFocusState.SPEAKING;
  }

  /** ASR 是否录音中 */
  static isListening(): boolean {
    return VoiceFocusManager.state === VoiceFocusState.LISTENING;
  }

  /** 当前是否允许启动 ASR（规则 1：speaking 时不启 ASR） */
  static canStartAsr(): boolean {
    return VoiceFocusManager.state === VoiceFocusState.IDLE;
  }

  /** 当前是否允许启动 TTS（规则 2：listening 时不播 TTS） */
  static canSpeak(): boolean {
    return VoiceFocusManager.state === VoiceFocusState.IDLE;
  }

  // ==================== ASR 侧 ====================

  /**
   * 申请 ASR 录音焦点。
   * - SPEAKING 时硬拒绝（返回 0），调用方不得启动 ASR；
   * - 成功进入 LISTENING 时防御性广播 EVENT_TTS_STOP（清残留播报），再广播 EVENT_FOCUS_CHANGED。
   *
   * @param source 申请方标识（页面/组件名，用于日志与事件溯源）
   * @returns 焦点 token（>0 成功；0 = 被拒绝，禁止启动 ASR）
   */
  static requestListen(source: string): number {
    if (VoiceFocusManager.state === VoiceFocusState.SPEAKING) {
      hilog.warn(0x0000, TAG,
        'requestListen denied (SPEAKING, held by %{public}s): source=%{public}s',
        VoiceFocusManager.ownerSource, source);
      return 0;
    }
    if (VoiceFocusManager.state === VoiceFocusState.LISTENING) {
      hilog.warn(0x0000, TAG,
        'requestListen denied (already LISTENING, held by %{public}s): source=%{public}s',
        VoiceFocusManager.ownerSource, source);
      return 0;
    }
    const token = VoiceFocusManager.acquire(VoiceFocusState.LISTENING, source, LISTEN_WATCHDOG_MS);
    // 规则 2：进入 listening 时停止 TTS（防御性强停，覆盖状态漂移场景）
    VoiceFocusManager.emitTtsStop('enter-listening', source);
    return token;
  }

  /**
   * 释放 ASR 录音焦点（onComplete/onError/onCancel 均须调用）。
   * token 不匹配时忽略（防旧会话误释放新会话）。
   */
  static releaseListen(token: number): void {
    VoiceFocusManager.release(VoiceFocusState.LISTENING, token, 'releaseListen');
  }

  // ==================== TTS 侧 ====================

  /**
   * 申请 TTS 播报焦点。
   * - LISTENING 时硬拒绝（返回 0），调用方不得启动播报（可选择丢弃或排队重试）。
   *
   * @param source 申请方标识
   * @returns 焦点 token（>0 成功；0 = 被拒绝，禁止启动 TTS）
   */
  static requestSpeak(source: string): number {
    if (VoiceFocusManager.state === VoiceFocusState.LISTENING) {
      hilog.warn(0x0000, TAG,
        'requestSpeak denied (LISTENING, held by %{public}s): source=%{public}s',
        VoiceFocusManager.ownerSource, source);
      return 0;
    }
    if (VoiceFocusManager.state === VoiceFocusState.SPEAKING) {
      hilog.warn(0x0000, TAG,
        'requestSpeak denied (already SPEAKING, held by %{public}s): source=%{public}s',
        VoiceFocusManager.ownerSource, source);
      return 0;
    }
    return VoiceFocusManager.acquire(VoiceFocusState.SPEAKING, source, SPEAK_WATCHDOG_MS);
  }

  /**
   * 释放 TTS 播报焦点（onComplete/onStop/onError 均须调用）。
   * token 不匹配时忽略。
   */
  static releaseSpeak(token: number): void {
    VoiceFocusManager.release(VoiceFocusState.SPEAKING, token, 'releaseSpeak');
  }

  /**
   * 主动强停 TTS（UI 停止按钮 / 页面退出等）：
   * 广播 EVENT_TTS_STOP（持有方收到后停引擎并 releaseSpeak），并立即回收焦点到 IDLE。
   * 非 SPEAKING 状态下为 no-op。
   */
  static stopSpeaking(reason: string): void {
    if (VoiceFocusManager.state !== VoiceFocusState.SPEAKING) {
      return;
    }
    const source = VoiceFocusManager.ownerSource;
    VoiceFocusManager.emitTtsStop(reason, source);
    VoiceFocusManager.transition(VoiceFocusState.IDLE, 'stopSpeaking:' + reason);
  }

  // ==================== 复位 ====================

  /**
   * 强制复位到 IDLE（异常恢复 / 页面销毁清理）。
   * SPEAKING 期间复位会先广播 EVENT_TTS_STOP。
   */
  static reset(reason: string): void {
    if (VoiceFocusManager.state === VoiceFocusState.IDLE) {
      return;
    }
    if (VoiceFocusManager.state === VoiceFocusState.SPEAKING) {
      VoiceFocusManager.emitTtsStop('reset:' + reason, VoiceFocusManager.ownerSource);
    }
    VoiceFocusManager.transition(VoiceFocusState.IDLE, 'reset:' + reason);
  }

  // ==================== 内部实现 ====================

  /** 占用焦点：发 token、切状态、启动 watchdog、广播状态变更 */
  private static acquire(target: VoiceFocusState, source: string, watchdogMs: number): number {
    const token = VoiceFocusManager.nextToken++;
    VoiceFocusManager.ownerToken = token;
    VoiceFocusManager.ownerSource = source;
    VoiceFocusManager.transitionState(target, source);
    VoiceFocusManager.startWatchdog(token, target, watchdogMs);
    hilog.info(0x0000, TAG, 'acquire %{public}s: source=%{public}s, token=%{public}d',
      target, source, token);
    return token;
  }

  /** 释放焦点：校验状态与 token，匹配才回 IDLE */
  private static release(expected: VoiceFocusState, token: number, api: string): void {
    if (VoiceFocusManager.state !== expected) {
      hilog.warn(0x0000, TAG, '%{public}s ignored: state=%{public}s (expected %{public}s)',
        api, VoiceFocusManager.state, expected);
      return;
    }
    if (token !== VoiceFocusManager.ownerToken) {
      hilog.warn(0x0000, TAG, '%{public}s ignored: stale token=%{public}d (owner=%{public}d)',
        api, token, VoiceFocusManager.ownerToken);
      return;
    }
    VoiceFocusManager.transition(VoiceFocusState.IDLE, api);
  }

  /** 切到目标状态并清持有者（IDLE）/保持有者（占用态），广播 EVENT_FOCUS_CHANGED */
  private static transition(target: VoiceFocusState, source: string): void {
    VoiceFocusManager.clearWatchdog();
    if (target === VoiceFocusState.IDLE) {
      VoiceFocusManager.ownerToken = 0;
      VoiceFocusManager.ownerSource = '';
    }
    VoiceFocusManager.transitionState(target, source);
  }

  /** 仅切状态 + 广播（不动持有者字段） */
  private static transitionState(target: VoiceFocusState, source: string): void {
    const previous: VoiceFocusState = VoiceFocusManager.state;
    VoiceFocusManager.state = target;
    if (previous !== target) {
      const payload: Record<string, Object> = {};
      payload['state'] = target as string;
      payload['previous'] = previous as string;
      payload['source'] = source;
      EventBus.emit(VoiceFocusManager.EVENT_FOCUS_CHANGED, payload);
      hilog.info(0x0000, TAG, 'state %{public}s -> %{public}s (source=%{public}s)',
        previous, target, source);
    }
  }

  /** 广播 TTS 强停指令 */
  private static emitTtsStop(reason: string, source: string): void {
    const payload: Record<string, Object> = {};
    payload['reason'] = reason;
    payload['source'] = source;
    EventBus.emit(VoiceFocusManager.EVENT_TTS_STOP, payload);
  }

  /** 启动 watchdog：持有者超时未释放则强制回收（防语音链路死锁） */
  private static startWatchdog(token: number, held: VoiceFocusState, watchdogMs: number): void {
    VoiceFocusManager.clearWatchdog();
    VoiceFocusManager.watchdogTimer = setTimeout(() => {
      VoiceFocusManager.watchdogTimer = -1;
      if (VoiceFocusManager.state === held && VoiceFocusManager.ownerToken === token) {
        hilog.error(0x0000, TAG,
          'watchdog fired: %{public}s held by %{public}s over %{public}d ms, force reset',
          held, VoiceFocusManager.ownerSource, watchdogMs);
        VoiceFocusManager.reset('watchdog-timeout');
      }
    }, watchdogMs);
  }

  /** 清除 watchdog 定时器 */
  private static clearWatchdog(): void {
    if (VoiceFocusManager.watchdogTimer !== -1) {
      clearTimeout(VoiceFocusManager.watchdogTimer);
      VoiceFocusManager.watchdogTimer = -1;
    }
  }
}
