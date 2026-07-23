// <!-- agentID: 鸿蒙DEV (TTS 语音播报服务) -->
// 文件: shared/src/main/ets/utils/TtsService.ets
// 任务: 单例封装 @kit.CoreSpeechKit textToSpeech —— init/enqueue/interrupt/stopAll/shutdown。
// 技术路线: CoreSpeechKit 离线 TTS(当前 SDK 仅支持 online:1 离线模式 + zh-CN + person:0 聆小珊)。
//   speak 的 extraParams.queueMode 控制播报策略: 0=排队(enqueue), 1=抢占打断(interrupt)。
//   requestId 在同一引擎实例内必须唯一 → 内部自增序号拼接生成。
// API 核实来源(D:\Program Files\Huawei\DevEco Studio\sdk\default\hms\ets\):
//   · kits/@kit.CoreSpeechKit.d.ts: export { speechRecognizer, textToSpeech }
//   · api/@hms.ai.textToSpeech.d.ts:
//     - createEngine(params): Promise<TextToSpeechEngine>                  (L88)
//     - TextToSpeechEngine.setListener(listener: SpeakListener): void      (L120)
//     - TextToSpeechEngine.speak(text: string, params: SpeakParams): void  (L148)
//     - TextToSpeechEngine.stop(): void                                    (L208)
//     - TextToSpeechEngine.isBusy(): boolean                               (L226)
//     - TextToSpeechEngine.shutdown(): void                                (L240)
//     - SpeakListener.onStart/onComplete/onStop/onError            (L275/293/311/331)
//     - CreateEngineParams { language; person; online; extraParams? }      (L377)
//     - SpeakParams { requestId; extraParams?: Record<string, Object> }    (L452)
// 编译坑对照 后端开发文档.md §十一: Record<string,Object> 用「空字面量+逐键赋值」;无 any/unknown;
//   无解构/spread;局部变量显式类型;对象字面量对应显式声明的接口(SpeakListener 用具名类实现)。

import { textToSpeech } from '@kit.CoreSpeechKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'TtsService';
const DOMAIN = 0x0000;

// speak 单次文本上限(官方约束: 不超过 10000 字符)。
const MAX_TEXT_LENGTH = 10000;

/**
 * 播报监听(具名类实现 textToSpeech.SpeakListener,规避 ArkTS 对象字面量限制)。
 * 仅记日志与回传播报态;onData 为可选合成音频流回调,播报场景不实现。
 */
class TtsSpeakListener implements textToSpeech.SpeakListener {
  onStart(requestId: string, response: textToSpeech.StartResponse): void {
    hilog.info(DOMAIN, TAG, 'onStart: requestId=%{public}s audioType=%{public}s',
      requestId, response.audioType);
  }

  onComplete(requestId: string, response: textToSpeech.CompleteResponse): void {
    // type: 0=合成完成 1=播报完成
    hilog.info(DOMAIN, TAG, 'onComplete: requestId=%{public}s type=%{public}d msg=%{public}s',
      requestId, response.type, response.message);
  }

  onStop(requestId: string, response: textToSpeech.StopResponse): void {
    hilog.info(DOMAIN, TAG, 'onStop: requestId=%{public}s type=%{public}d msg=%{public}s',
      requestId, response.type, response.message);
  }

  onError(requestId: string, errorCode: number, errorMessage: string): void {
    hilog.error(DOMAIN, TAG, 'onError: requestId=%{public}s code=%{public}d msg=%{public}s',
      requestId, errorCode, errorMessage);
  }
}

/**
 * TtsService —— CoreSpeechKit 文本转语音单例服务。
 *
 * 用法:
 *   const tts: TtsService = TtsService.getInstance();
 *   await tts.init();                 // 幂等,可多次调用;enqueue/interrupt 也会自动补 init
 *   await tts.enqueue('第一句');       // 排队播报(queueMode=0):当前有播报则排队等待
 *   await tts.interrupt('紧急插播');   // 抢占播报(queueMode=1):立即打断当前播报
 *   tts.stopAll();                    // 停止当前播报并清空队列
 *   tts.shutdown();                   // 释放引擎(页面/应用退出时调用;之后可再 init 重建)
 *
 * 约束(SDK 现状): 仅离线模式(online=1)、仅中文 zh-CN、仅音色 person=0(聆小珊);
 * 单次文本 ≤ 10000 字符;requestId 引擎实例内唯一(内部自动生成)。
 * 所有失败路径 hilog.error + 返回 false,不外抛异常。
 */
export class TtsService {
  private static instance: TtsService | null = null;

  // TTS 引擎(init 成功后非空;shutdown 后置空可重建)。
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  // 并发 init 合流:进行中的 createEngine Promise,避免重复建引擎。
  private initPromise: Promise<boolean> | null = null;
  // requestId 自增序号(同一引擎实例内唯一;掺入时间戳防重建引擎后碰撞)。
  private reqSeq: number = 0;
  private readonly listener: TtsSpeakListener = new TtsSpeakListener();

  private constructor() {
  }

  /**
   * 获取全局单例。
   */
  static getInstance(): TtsService {
    if (TtsService.instance === null) {
      TtsService.instance = new TtsService();
    }
    return TtsService.instance;
  }

  /**
   * 初始化 TTS 引擎(幂等:已初始化直接返回 true;进行中则合流等待同一 Promise)。
   * @returns 引擎就绪返回 true;创建失败 hilog.error 并返回 false。
   */
  init(): Promise<boolean> {
    if (this.engine !== null) {
      return Promise.resolve(true);
    }
    if (this.initPromise !== null) {
      return this.initPromise;
    }
    this.initPromise = this.doCreateEngine();
    return this.initPromise;
  }

  /**
   * 排队播报:当前有播报则排到队尾,播完自动接续(queueMode=0)。
   * @param text 待播报文本(非空且 ≤ 10000 字符)。
   * @returns 成功派发返回 true;文本非法/引擎不可用/speak 抛错返回 false。
   */
  async enqueue(text: string): Promise<boolean> {
    return this.speakInner(text, 0);
  }

  /**
   * 抢占播报:立即打断当前播报并播报本条(queueMode=1)。
   * @param text 待播报文本(非空且 ≤ 10000 字符)。
   * @returns 成功派发返回 true;文本非法/引擎不可用/speak 抛错返回 false。
   */
  async interrupt(text: string): Promise<boolean> {
    return this.speakInner(text, 1);
  }

  /**
   * 停止当前播报并清空待播队列(未初始化时为空操作,幂等)。
   */
  stopAll(): void {
    const eng: textToSpeech.TextToSpeechEngine | null = this.engine;
    if (eng === null) {
      return;
    }
    try {
      eng.stop();
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'stopAll: stop failed: code=%{public}d msg=%{public}s', e.code, e.message);
    }
  }

  /**
   * 引擎是否正在播报/合成中(未初始化返回 false)。
   */
  isBusy(): boolean {
    const eng: textToSpeech.TextToSpeechEngine | null = this.engine;
    if (eng === null) {
      return false;
    }
    try {
      return eng.isBusy();
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'isBusy failed: code=%{public}d msg=%{public}s', e.code, e.message);
      return false;
    }
  }

  /**
   * 释放引擎资源(先 stop 再 shutdown;幂等)。之后可再次 init 重建引擎。
   * 页面销毁/应用退后台不再播报时调用,避免引擎常驻。
   */
  shutdown(): void {
    const eng: textToSpeech.TextToSpeechEngine | null = this.engine;
    this.engine = null;
    this.initPromise = null;
    if (eng === null) {
      return;
    }
    try {
      eng.stop();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'shutdown: stop failed: %{public}s', (err as BusinessError).message);
    }
    try {
      eng.shutdown();
      hilog.info(DOMAIN, TAG, 'shutdown: engine released');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'shutdown failed: code=%{public}d msg=%{public}s', e.code, e.message);
    }
  }

  /**
   * 创建引擎 + 挂监听(内部;失败置空 initPromise 允许下次重试)。
   */
  private async doCreateEngine(): Promise<boolean> {
    // 设备能力守卫: AI.TextToSpeech 非全设备支持(编译期 syscap WARN 对应项),不支持则优雅降级。
    if (!canIUse('SystemCapability.AI.TextToSpeech')) {
      hilog.error(DOMAIN, TAG, 'init: SystemCapability.AI.TextToSpeech not supported on this device');
      this.initPromise = null;
      return false;
    }
    // SDK 现状: 仅支持 zh-CN / person=0 聆小珊 / online=1 离线。
    const params: textToSpeech.CreateEngineParams = {
      language: 'zh-CN',
      person: 0,
      online: 1
    };
    try {
      const eng: textToSpeech.TextToSpeechEngine = await textToSpeech.createEngine(params);
      eng.setListener(this.listener);
      this.engine = eng;
      hilog.info(DOMAIN, TAG, 'init: engine created (offline zh-CN person=0)');
      return true;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'init: createEngine failed: code=%{public}d msg=%{public}s', e.code, e.message);
      this.initPromise = null; // 允许下次 init 重试
      return false;
    }
  }

  /**
   * speak 公共路径(内部)。
   * @param queueMode 0=排队 1=抢占打断。
   */
  private async speakInner(text: string, queueMode: number): Promise<boolean> {
    const trimmed: string = text.trim();
    if (trimmed.length === 0) {
      hilog.warn(DOMAIN, TAG, 'speak: empty text, skip');
      return false;
    }
    if (trimmed.length > MAX_TEXT_LENGTH) {
      hilog.error(DOMAIN, TAG, 'speak: text too long (%{public}d > %{public}d)', trimmed.length, MAX_TEXT_LENGTH);
      return false;
    }
    // 未初始化自动补 init。
    const ready: boolean = await this.init();
    const eng: textToSpeech.TextToSpeechEngine | null = this.engine;
    if (!ready || eng === null) {
      hilog.error(DOMAIN, TAG, 'speak: engine not ready, drop text (queueMode=%{public}d)', queueMode);
      return false;
    }
    // Record<string,Object> 禁对象字面量平铺 → 空字面量 + 逐键赋值(§十一.1)。
    const extra: Record<string, Object> = {};
    extra['queueMode'] = queueMode; // 0=排队 1=抢占
    extra['playType'] = 1;          // 1=边合成边播报(0 为仅合成走 onData)
    const requestId: string = this.nextRequestId();
    const speakParams: textToSpeech.SpeakParams = {
      requestId: requestId,
      extraParams: extra
    };
    try {
      eng.speak(trimmed, speakParams);
      hilog.info(DOMAIN, TAG, 'speak: dispatched requestId=%{public}s queueMode=%{public}d len=%{public}d',
        requestId, queueMode, trimmed.length);
      return true;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'speak failed: code=%{public}d msg=%{public}s', e.code, e.message);
      return false;
    }
  }

  /**
   * 生成引擎实例内唯一 requestId(时间戳 + 自增序号)。
   */
  private nextRequestId(): string {
    ++this.reqSeq;
    return 'tts-' + Date.now().toString() + '-' + this.reqSeq.toString();
  }
}
