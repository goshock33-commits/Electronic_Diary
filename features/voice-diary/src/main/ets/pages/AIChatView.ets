// <!-- agentID: HUI-001 -->
// T204（HUI-001）：AIChatView 接真实会话【S4/M3/M5 · PLN-001 阶段 1B】T203 已合并。
// fix: F5-v2 —— 用户审查变更：任务提取入口整合进 AI 伙伴对话（原 FloatingEntry 浮球已移除）。
//   聊天消息命中任务意图关键词（提取任务/加到待办/添加待办/提取到待办）→ TaskExtractionViewModel
//   receiveFromShare(正文, 'ai_chat') 提取落库（VM 内 emit TASK_EXTRACTED）→ convertToTodo(今日, 'today')
//   （VM 内 emit TASK_CONVERTED + TODO_CREATED，同 TaskConfirmPage 约定）→ AI 气泡自然回复结果。
//   【M3】此链路是已交付真功能，T204 不删；待 1B 联调通过后移入 AIIntentHandler.execute(extract_task)。
//   不命中关键词 → session.send() 走真实会话（当前为 stub 接线）。
// 页面：AI 伙伴 Mimi 聊天页（内容层 @Component，壳由 P1-01 MainPage 接线）
// 关联计划：PLN-003 P1-03（AIChatView 新增·品牌本地化）
// 关联设计稿：UX-001_redesign_report.md §2.8 AIChatView / 原型 src/components/AIChatView.tsx
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 品牌红线（UX §2.8）：禁 Gemini 品牌字样；eyebrow 用 AI_COMPANION 图标，禁宠物爪印 emoji
// 图标来源（grep 本地 resource/HarmonyOS_全量图标库.md 逐项验证，禁上网）：
//   AI_COMPANION → face_smiling（L1825 [OK] 已验证，IconMapper 常量）
//   SEND         → paperplane（L513/648 [OK] 已验证，IconMapper 常量）
//   chip 帮我写日记 → book_open_fill（L844 [OK]）
//   chip 总结今日   → doc_text（L884 [OK]；原型 leaf 叶 不在本地库，语义降级为「文档=总结」）
//   chip 开心的事   → star_fill（L257 [OK]；原型 sparkles 闪 不在本地库，按 UX §3.2 备选）
//   chip 提取任务   → ellipsis_bubble（L1277 [OK]；task 建议的 ellipsis_message_1 不在库，故直接用 ellipsis_bubble）
// 运行时崩溃防范（PROJECT_SPEC §9）：无 getter-in-build；字段初值不含 $r()（$r 仅出现在 build/@Builder 内）；
//   @StorageLink 判空兜底；@Prop 无内置属性重名；对象字面量均有接口类型（§8.2）；FontWeight 用 TYPO 令牌无 Light。
// 开发范式：ArkTS 声明式开发范式（Stage 模型）
// HUI-028：引入手绘字体助手——SKETCH_TITLE=猫啃(eyebrow/H1「AI 伙伴 Mimi」)，SKETCH_BODY=清松(AI 药丸/气泡正文/chip 标签)。
// HUI-001（长按猫语音输入）：长按任一 Mimi 猫头像 400ms → CoreSpeechKit 端侧语音转文字 → 松手 finish → 转写填输入框（不自动发送）。
//   API 已 grep 本地 hms .d.ts 逐项验证（@hms.ai.speechRecognizer.d.ts）：createEngine(params):Promise L68 /
//   setListener L84 / startListening(StartParams) L140 / finish(sessionId) L167 / cancel L179 / shutdown L196 /
//   RecognitionListener.onStart/onEvent/onResult/onComplete/onError L205-252 / SpeechRecognitionResult{isFinal,isLast,result} L389。
//   注意：SDK 无 on('result')/stopListening —— 正确 API 为 setListener + finish（本地 .d.ts 实证，§8.3⑦）。
//   权限：ohos.permission.MICROPHONE（entry/module.json5 已声明 + reason）；运行时 abilityAccessCtrl.requestPermissionsFromUser
//   （@ohos.abilityAccessCtrl.d.ts L292 Promise 版），拒权 Toast 引导设置。Context 取自 this.getUIContext().getHostContext()
//   （@ohos.arkui.UIContext.d.ts L4757）。LongPressGesture(gesture.d.ts L3323，duration:400 同 DiaryEditPage 先例)。
//   extraParams 具体 key（recognitionMode/vadBegin/vadEnd/maxAudioDuration，Record<string,Object> 类型 .d.ts L336 已证）
//   按官方 Core Speech Kit 实时识别示例填写，构造遵守 §8.3①（空字面量+括号逐键赋值）。
import { RADIUS, SPACING, TYPO, IconMapper, SKETCH_TITLE, SKETCH_BODY, DateUtils, DSErrorKind, PersistentState, LottieAnimation } from '@ohos/shared';
import type { ThemeColorTokens, ExtractedTask, SessionCallbacks } from '@ohos/shared';
import { promptAction } from '@kit.ArkUI';
// HUI-001 长按语音：CoreSpeechKit 端侧识别 + 运行时麦克风权限
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { abilityAccessCtrl } from '@kit.AbilityKit';
import type { Permissions, PermissionRequestResult } from '@kit.AbilityKit';
// fix: F5-v2 —— 跨模块引任务提取 VM（§1.4 三者一致；voice-diary oh-package.json5 已加依赖 key）
import { TaskExtractionViewModel, type ExtractionResult } from 'features_task_extraction';
// T203 已合并：真实会话编排
import { AIChatSession } from '../service/AIChatSession';

/** 单条聊天消息（role: 'ai'=AI 左气泡 / 'user'=用户右气泡） */
interface ChatMessage {
  readonly role: string;
  readonly text: string;
}

// fix: F5-v2 —— 任务提取意图关键词（命中即走提取链路；'提取聊天任务' 覆盖既有快捷 chip 文案）
//   模块级 const（同 MainPage TAB_CONFIGS 模式，非 struct 字段初值，§9 安全）
//   【M3】待 1B 联调通过后移入 AIIntentHandler.execute(extract_task)。
const TASK_INTENT_KEYWORDS: string[] = ['提取任务', '加到待办', '添加待办', '提取到待办', '提取聊天任务'];

@Component
export struct AIChatView {
  // 对话消息流（T204：仅 1 条 AI 欢迎语在 aboutToAppear 填充，mock seed 已删）
  @State messages: ChatMessage[] = [];
  // 底部输入框内容
  @State inputText: string = '';
  // T204：会话忙碌态（session onBusyChanged 驱动；发送按钮禁用+「Mimi 正在思考…」指示）
  @State busy: boolean = false;
  // T302：流式打字机——正在生成的 AI 气泡文本（onAiDelta 逐字累加，onDone 时固化到 messages）
  @State streamingText: string = '';
  // 用户正在击键（onChange 触发时置 true，停敲 1.5s 后自动回 false；驱动倾听背景动画）
  @State isTyping: boolean = false;
  private typingTimer: number = -1;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  // HUI-001：深色感知（用户气泡红褐色深浅两档切换；ThemeManager 维护 AppStorage['theme_is_dark']，单向只读，缺省 false 安全兜底）
  @StorageProp('theme_is_dark') isDark: boolean = false;
  // HUI-001：导航栏猫长按语音信号（FloatingTabBar 写 AppStorage → 触发 startVoiceInput / stopVoiceInput）
  @StorageProp('ai_voice_trigger') @Watch('onAiVoiceTrigger') aiVoiceTrigger: number = 0;
  @StorageProp('ai_voice_stop') @Watch('onAiVoiceStop') aiVoiceStop: number = 0;

  // 气泡圆角（1.4rem≈22vp，单角收窄到 8vp 形成指向头像的小尖角；非 RADIUS 令牌，命名常量避免魔数散落）
  private readonly BUBBLE_RADIUS: number = 22;
  private readonly BUBBLE_TAIL: number = 8;
  // T204：会话实例（aboutToAppear 创建，aboutToDisappear cancel+detach【M5】）
  private session: AIChatSession | null = null;

  // ==== HUI-001 长按语音输入状态 ====
  // 聆听态（猫头像放大+光环 & 输入栏上方「聆听中…」指示；全局态——Mimi 在聆听，所有猫头像同步反馈）
  @State listening: boolean = false;
  // 识别引擎（首次长按懒创建后复用；aboutToDisappear shutdown 释放）
  private speechEngine: speechRecognizer.SpeechRecognitionEngine | null = null;
  // 当前识别会话 ID（每次长按重新生成）
  private voiceSessionId: string = '';
  // 已终结句子的累计转写 + 当前句实时转写（onResult isFinal 驱动，onComplete 时合并填输入框）
  private voiceFinalText: string = '';
  private voiceSegmentText: string = '';
  // 手指仍按住标志（权限弹窗/引擎创建为异步，期间松手则中止启动，防「松手后仍在录」）
  private voicePressing: boolean = false;

  aboutToAppear(): void {
    // T204：欢迎语固定在 Scroll 外渲染，messages 初始为空（单条 Scroll 居中已根治）
    this.messages = [];
    // T203 已合并——接缝就这一行
    this.session = new AIChatSession(this.buildCallbacks());
  }

  /** 【M5】页面退出/切 Tab：取消在途请求 + 解绑回调，对话中途退出再进入不崩溃 */
  aboutToDisappear(): void {
    if (this.session) {
      this.session.cancel();
      this.session.detach();
      this.session = null;
    }
    // 清除击键检测定时器
    if (this.typingTimer !== -1) {
      clearTimeout(this.typingTimer);
      this.typingTimer = -1;
    }
    // HUI-001：释放语音识别引擎（cancel 在途会话 + shutdown，防资源泄漏）
    this.releaseVoiceEngine();
    AppStorage.setOrCreate('ai_voice_listening', false);
  }

  // ==== T204 会话回调（T101 契约 SessionCallbacks，对象字面量显式接口类型 §8.2）====

  private buildCallbacks(): SessionCallbacks {
    const cbs: SessionCallbacks = {
      onAiText: (fullText: string): void => {
        // 打字机结束：清空 streamingText（onDone 会追加正式气泡）
        this.streamingText = '';
      },
      onAiDelta: (fragment: string): void => {
        // T302 打字机：逐字累加到 streamingText，实时渲染
        this.streamingText += fragment;
      },
      onDone: (fullText: string): void => {
        // 【S5-1】onDone 是气泡固化唯一信号：清空 streamingText + 追加正式气泡
        this.streamingText = '';
        this.appendAiReply(fullText);
      },
      onError: (errorKind: DSErrorKind, errorText: string): void => {
        if (errorKind === DSErrorKind.CANCELLED) {
          return; // 用户主动取消/页面退出，不追加气泡
        }
        // 【L2】错误 → 普通 AI 气泡样式追加（不做大红），文案说清发生了什么+怎么办
        this.appendAiReply(this.mapErrorText(errorKind));
      },
      onBusyChanged: (busy: boolean): void => {
        this.busy = busy;
      }
    };
    return cbs;
  }

  /** 【L2】errorKind → 用户可读文案（发生了什么 + 怎么办；CANCELLED 在 onError 处静默不进此函数） */
  private mapErrorText(kind: DSErrorKind): string {
    if (kind === DSErrorKind.NO_KEY) {
      return '还没有配置 AI 服务的 API Key，我暂时没法回复你。去「设置 → AI 服务设置」填好 Key，再来找我聊天吧。';
    }
    if (kind === DSErrorKind.HTTP_401) {
      return '这个 API Key 好像无效了。去「设置 → AI 服务设置」检查一下 Key 是否填写正确。';
    }
    if (kind === DSErrorKind.HTTP_402) {
      return 'DeepSeek 账户余额不足了。前往 DeepSeek 开放平台充值后，就能继续和我聊天。';
    }
    if (kind === DSErrorKind.HTTP_429) {
      return '消息发得有点快，服务那边限流了。稍等几秒再发一次就好。';
    }
    if (kind === DSErrorKind.HTTP_5XX) {
      return 'AI 服务那边暂时开小差了。休息一下，稍后再试。';
    }
    if (kind === DSErrorKind.TIMEOUT) {
      return '这次等得有点久，请求超时了。检查一下网络，然后再发一次吧。';
    }
    if (kind === DSErrorKind.NETWORK) {
      return '网络好像不太顺畅，我没能联系上 AI 服务。检查网络连接后再试一次。';
    }
    if (kind === DSErrorKind.PARSE) {
      return '我收到了回复，但没能读懂它（解析失败）。再发一次试试。';
    }
    return '出了点小状况，稍后再试一次好吗？';
  }

  // ==== 主题色兜底（普通方法，非 getter；@StorageLink 判空）====
  private getBg(): string {
    return this.tokens ? this.tokens.bg : '#FAF8F5';
  }

  private getPrimary(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  private getCardBg(): string {
    return this.tokens ? this.tokens.bgCard : '#FFFFFF';
  }

  private getTextPrimary(): string {
    return this.tokens ? this.tokens.textPrimary : '#1A1A1A';
  }

  private getTextSecondary(): string {
    return this.tokens ? this.tokens.textSecondary : '#5A5A5A';
  }

  private getSurface(): string {
    return this.tokens ? this.tokens.surface : '#F2F2F0';
  }

  // HUI-035：交互色专用 token（雾霾蓝主按钮 / 燕麦辅助 / 白按钮文字）
  private getBtnPrimary(): string {
    return this.tokens ? this.tokens.btnPrimary : '#738A9C';
  }

  private getBtnAux(): string {
    return this.tokens ? this.tokens.btnAux : '#C6BBAE';
  }

  private getBtnPrimaryText(): string {
    return this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF';
  }

  private getShadow(): string {
    return this.tokens ? this.tokens.shadow : '#1A00C2B8';
  }

  // HUI-001：用户气泡复古红褐（旧书脊/印章色）——浅色 #96473A（白卡上 6.4:1），深色提亮 #C9826B（#1C1C1C 卡上 5.6:1，均 ≥4.5:1）
  private getUserBrown(): string {
    return this.isDark ? '#C9826B' : '#96473A';
  }

  /** 半透明版本：ArkUI hex-alpha 为 #AARRGGBB，需前置 alpha */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  // ==== 交互驱动 ====

  /**
   * 发送一条用户消息：
   * - 命中任务意图 → F5-v2 本地提取链路（【M3】保留，见 handleTaskExtraction）；
   * - 未命中 → 用户气泡上屏 + session.send() 走真实会话（当前 stub 接线，T203 合并后即真实 API）；
   * - busy 中直接忽略（发送按钮已禁用，此处兜住键盘 onSubmit / chip 双入口）。
   */
  private pushExchange(userText: string): void {
    const trimmed: string = userText.trim();
    if (trimmed.length === 0) {
      return;
    }
    if (this.busy) {
      return;
    }
    // fix: F5-v2 —— 任务提取意图：先上屏用户气泡，异步提取完成后由 AI 气泡回复结果
    if (this.isTaskIntent(trimmed)) {
      const pending: ChatMessage[] = this.messages.slice();
      pending.push({ role: 'user', text: trimmed });
      this.messages = pending;
      this.handleTaskExtraction(trimmed);
      return;
    }
    // T204：mock 回复已删——用户气泡上屏后交给会话，AI 回复经 onDone 固化上屏【S5-1】
    const next: ChatMessage[] = this.messages.slice();
    next.push({ role: 'user', text: trimmed });
    this.messages = next;
    if (this.session) {
      this.session.send(trimmed);
    }
  }

  // fix: F5-v2 ==== 任务提取整合（用户审查：不用单独浮窗，在 AI 伙伴里说「提取任务到待办」即可）====
  // 【M3·T204 不删】isTaskIntent/handleTaskExtraction 为已交付真功能，原调用链保持不动；
  // 待 1B 联调通过后整体移入 AIIntentHandler.execute(extract_task)，移除前后行为须一致。

  /** 意图识别：关键词匹配（命中走提取，不命中走原有对话逻辑） */
  private isTaskIntent(text: string): boolean {
    return TASK_INTENT_KEYWORDS.some((kw: string) => text.includes(kw));
  }

  /** 追加一条 AI 回复气泡（提取链路异步回包用） */
  private appendAiReply(text: string): void {
    const next: ChatMessage[] = this.messages.slice();
    next.push({ role: 'ai', text: text });
    this.messages = next;
  }

  /**
   * 任务提取链路（后端契约 features_task_extraction）：
   * 1) 去掉指令词/引导词得到任务正文；
   * 2) vm.receiveFromShare(正文, 'ai_chat')：清洗 + 三级降级提取 + saveTask 落库（VM 内 emit TASK_EXTRACTED）；
   * 3) vm.convertToTodo(id, DateUtils.today(), 'today')：转今日待办（VM 内 emit TASK_CONVERTED + TODO_CREATED，
   *    同 TaskConfirmPage「全部添加」约定）；
   * 4) AI 气泡自然回复结果；提取不到内容回复引导语。全链路 try-catch，不阻塞对话。
   */
  private async handleTaskExtraction(userText: string): Promise<void> {
    // 剥离指令词，剩余为任务正文（如「提取任务 周五下午3点交作业」→「周五下午3点交作业」）
    let content: string = userText;
    TASK_INTENT_KEYWORDS.forEach((kw: string) => {
      content = content.replace(kw, '');
    });
    // 去掉首部引导词与两端标点空白（帮我/请/把 等）
    content = content.replace(/^[帮我请你把将，。,.:：;；!！?？、\s]+/, '')
      .replace(/[，。,.:：;；!！?？、\s]+$/, '')
      .trim();
    if (content.length === 0) {
      this.appendAiReply('想提取什么任务呀？把事情和时间一起告诉我，比如：「提取任务 周五下午3点交作业」。');
      return;
    }
    try {
      const vm: TaskExtractionViewModel = new TaskExtractionViewModel();
      const result: ExtractionResult | null = await vm.receiveFromShare(content, 'ai_chat');
      if (!result || result.title.trim().length === 0) {
        this.appendAiReply('我没能识别出任务内容，换个说法试试？比如：「提取任务 周五下午3点交作业」。');
        return;
      }
      // saveTask 在 VM 内 unshift，最新提取项在首位；insert 失败时列表为空 → 只报提取成功不转待办
      const savedList: ExtractedTask[] = vm.getAllTasks();
      let converted: boolean = false;
      const savedId: number = savedList.length > 0 ? savedList[0].id : 0;
      if (savedId > 0) {
        converted = await vm.convertToTodo(savedId, DateUtils.today(), 'today');
      }
      if (converted) {
        this.appendAiReply('已提取任务：「' + result.title + '」，已加入今日待办 ✓');
      } else {
        this.appendAiReply('已提取任务：「' + result.title + '」，不过加入今日待办没成功，可以稍后在时光轴手动添加。');
      }
    } catch (err) {
      this.appendAiReply('提取任务时出了点小差错，稍后再试一次好吗？');
    }
  }

  // ==== HUI-001 长按语音输入（CoreSpeechKit 端侧识别，API 逐项对照本地 @hms.ai.speechRecognizer.d.ts）====

  /**
   * 运行时麦克风权限：requestPermissionsFromUser（已授权时系统直接放行不弹窗；
   * 永久拒绝时系统直接返回 -1 不弹窗）→ 拒权 Toast 引导去设置页开。
   */
  private async ensureMicPermission(): Promise<boolean> {
    const ctx = this.getUIContext().getHostContext();
    if (!ctx) {
      return false;
    }
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const perms: Array<Permissions> = ['ohos.permission.MICROPHONE'];
      const result: PermissionRequestResult = await atManager.requestPermissionsFromUser(ctx, perms);
      const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
      if (!granted) {
        promptAction.showToast({ message: '麦克风权限未开启，去「设置 → 应用」里打开后再长按 Mimi 说话', duration: 2500 });
      }
      return granted;
    } catch (err) {
      promptAction.showToast({ message: '麦克风权限请求失败', duration: 1500 });
      return false;
    }
  }

  /** 懒创建识别引擎（复用；language zh-CN + online:1 端侧，.d.ts L276：0=在线 1=离线端侧） */
  private async getVoiceEngine(): Promise<speechRecognizer.SpeechRecognitionEngine | null> {
    if (this.speechEngine) {
      return this.speechEngine;
    }
    try {
      // §8.3①：Record<string,Object> 必须空字面量起手 + 括号逐键赋值
      const engineExtra: Record<string, Object> = {};
      engineExtra['locate'] = 'CN';
      engineExtra['recognizerMode'] = 'short';
      const createParams: speechRecognizer.CreateEngineParams = {
        language: 'zh-CN',
        online: 1,
        extraParams: engineExtra
      };
      const engine: speechRecognizer.SpeechRecognitionEngine = await speechRecognizer.createEngine(createParams);
      // setListener 必须先于 startListening（.d.ts L131 note）；引擎级一次绑定，闭包捕获 this
      const listener: speechRecognizer.RecognitionListener = {
        onStart: (sessionId: string, eventMessage: string): void => {
        },
        onEvent: (sessionId: string, eventCode: number, eventMessage: string): void => {
        },
        onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult): void => {
          // result.result 为当前句累计文本；isFinal=true 该句终结 → 并入已完成段
          if (result.isFinal) {
            this.voiceFinalText = this.voiceFinalText + result.result;
            this.voiceSegmentText = '';
          } else {
            this.voiceSegmentText = result.result;
          }
        },
        onComplete: (sessionId: string, eventMessage: string): void => {
          this.flushVoiceTranscript();
        },
        onError: (sessionId: string, errorCode: number, errorMessage: string): void => {
          this.listening = false;
          AppStorage.setOrCreate('ai_voice_listening', false);
          this.voiceFinalText = '';
          this.voiceSegmentText = '';
          promptAction.showToast({ message: '语音识别失败，再试一次吧', duration: 1500 });
        }
      };
      engine.setListener(listener);
      this.speechEngine = engine;
      return engine;
    } catch (err) {
      promptAction.showToast({ message: '语音识别暂不可用', duration: 1500 });
      return null;
    }
  }

  /** HUI-001：导航栏猫长按信号（FloatingTabBar→AppStorage→@StorageProp @Watch）触发语音输入 */
  private onAiVoiceTrigger(): void {
    if (this.aiVoiceTrigger > 0 && !this.listening && !this.busy) {
      this.startVoiceInput();
    }
  }

  /** HUI-001：导航栏猫松手信号 → 停止语音输入 */
  private onAiVoiceStop(): void {
    if (this.aiVoiceStop > 0 && this.listening) {
      this.stopVoiceInput();
    }
  }

  /** 长按触发（LongPressGesture onAction）：权限 → 引擎 → startListening；异步各阶段校验 voicePressing，松手即中止 */
  private async startVoiceInput(): Promise<void> {
    if (this.listening) {
      return;
    }
    this.voicePressing = true;
    const granted: boolean = await this.ensureMicPermission();
    if (!granted || !this.voicePressing) {
      return; // 拒权（Toast 已给）或权限弹窗期间已松手
    }
    const engine: speechRecognizer.SpeechRecognitionEngine | null = await this.getVoiceEngine();
    if (!engine || !this.voicePressing) {
      return;
    }
    try {
      this.voiceSessionId = 'aichat_voice_' + Date.now().toString();
      this.voiceFinalText = '';
      this.voiceSegmentText = '';
      // 音频参数 + 实时录音识别模式（官方实时识别示例参数；类型 .d.ts L315/L345 已证）
      const audio: speechRecognizer.AudioInfo = {
        audioType: 'pcm',
        sampleRate: 16000,
        soundChannel: 1,
        sampleBit: 16
      };
      const startExtra: Record<string, Object> = {}; // §8.3①
      startExtra['recognitionMode'] = 0; // 0=实时录音识别（引擎自采麦克风，无需 writeAudio）
      startExtra['vadBegin'] = 2000;
      startExtra['vadEnd'] = 3000;
      startExtra['maxAudioDuration'] = 20000;
      const startParams: speechRecognizer.StartParams = {
        sessionId: this.voiceSessionId,
        audioInfo: audio,
        extraParams: startExtra
      };
      engine.startListening(startParams);
      this.listening = true;
      AppStorage.setOrCreate('ai_voice_listening', true);
    } catch (err) {
      this.listening = false;
      promptAction.showToast({ message: '语音识别失败，再试一次吧', duration: 1500 });
    }
  }

  /** 松手/手势取消（onActionEnd/onActionCancel）：finish 结束采音，最终结果经 onResult/onComplete 回流 */
  private stopVoiceInput(): void {
    this.voicePressing = false;
    if (!this.listening || !this.speechEngine) {
      return;
    }
    this.listening = false;
    AppStorage.setOrCreate('ai_voice_listening', false);
    try {
      this.speechEngine.finish(this.voiceSessionId);
    } catch (err) {
      // finish 失败（如引擎已复位）：直接把已到手的转写落输入框，不丢用户的话
      this.flushVoiceTranscript();
    }
  }

  /** 转写落输入框：已有内容则「空格 + 新文本」追加；不自动发送，留给用户确认后点发送 */
  private flushVoiceTranscript(): void {
    this.listening = false;
    const text: string = (this.voiceFinalText + this.voiceSegmentText).trim();
    this.voiceFinalText = '';
    this.voiceSegmentText = '';
    if (text.length === 0) {
      promptAction.showToast({ message: '没听清楚，长按 Mimi 再说一次吧', duration: 1500 });
      return;
    }
    const existing: string = this.inputText.trim();
    this.inputText = existing.length > 0 ? existing + ' ' + text : text;
  }

  /** 页面退出释放引擎（cancel 在途 + shutdown，.d.ts L179/L196） */
  private releaseVoiceEngine(): void {
    this.voicePressing = false;
    this.listening = false;
    if (!this.speechEngine) {
      return;
    }
    try {
      if (this.voiceSessionId.length > 0) {
        this.speechEngine.cancel(this.voiceSessionId);
      }
      this.speechEngine.shutdown();
    } catch (err) {
      // 释放兜底：引擎已失效时忽略
    }
    this.speechEngine = null;
  }

  /** 底部输入栏发送 */
  private onSend(): void {
    // T204：busy 中不发送也不清空输入（保住用户已敲的文字；按钮已禁用，此处兜键盘 onSubmit）
    if (this.busy) {
      promptAction.showToast({ message: 'Mimi 正在思考，稍等一下…', duration: 1200 });
      return;
    }
    if (this.inputText.trim().length === 0) {
      promptAction.showToast({ message: '说点什么再发送吧', duration: 1200 });
      return;
    }
    this.pushExchange(this.inputText);
    this.inputText = '';
  }

  /** 点击快捷提问 chip = 直接把该问题发给 Mimi */
  private onChip(question: string): void {
    this.pushExchange(question);
  }

  build() {
    Column() {
      this.Header()

      // 聊天区域 + 背景动画（Stack 叠层：动画在消息列表后面）
      Stack({ alignContent: Alignment.Center }) {
        // 前景：消息流 + chips + 聆听指示
        Column() {
          this.MessageArea()
          this.ChipsBar()
          if (this.listening) {
            this.ListeningIndicator()
          }
        }
        .width('100%')
        .height('100%')

        // 背景动画：打字（AI 正在回复时播放）
        LottieAnimation({
          animPath: 'animations/打字.json',
          loop: true,
          autoPlay: true,
          animWidth: 300,
          animHeight: 300,
          frameRate: 12,
          shouldPlay: this.busy
        })
          .width(300)
          .height(300)
          .opacity(this.busy ? 0.15 : 0)
          .accessibilityLevel('no')

        // 背景动画：倾听（用户输入时播放，AI 回复时不播）
        LottieAnimation({
          animPath: 'animations/倾听.json',
          loop: true,
          autoPlay: true,
          animWidth: 300,
          animHeight: 300,
          frameRate: 12,
          shouldPlay: this.isTyping && !this.busy
        })
          .width(300)
          .height(300)
          .opacity(this.isTyping && !this.busy ? 0.15 : 0)
          .accessibilityLevel('no')
      }
      .layoutWeight(1)
      .width('100%')

      this.InputBar()
    }
    .width('100%').height('100%')
    .backgroundColor(this.getBg())
  }

  // ==== HUI-001：聆听中指示行（LoadingProgress + 灰字，深浅色随 token）====
  @Builder
  ListeningIndicator() {
    Row() {
      LoadingProgress()
        .width(14)
        .height(14)
        .color(this.getTextSecondary())
      Text('聆听中…松开手指结束')
        .fontSize(TYPO.eyebrow.size)
        .fontWeight(TYPO.body.weight)
        .fontColor(this.getTextSecondary())
        .attributeModifier(SKETCH_BODY)
        .margin({ left: 6 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: SPACING.pageH, right: SPACING.pageH, bottom: 4 })
    .accessibilityText('聆听中，松开手指结束语音输入')
  }

  // ==== 顶部：Mimi 居中 ====
  @Builder
  Header() {
    Text('Mimi')
      .fontSize(TYPO.h1.size)
      .fontWeight(TYPO.h1.weight)
      .fontColor(this.getPrimary())
      .attributeModifier(SKETCH_TITLE)
      .width('100%')
      .textAlign(TextAlign.Center)
      .padding({ top: SPACING.pageTop, bottom: 8 })
  }

  // ==== 中部：消息流（可滚动，撑满剩余空间）====
  @Builder
  MessageArea() {
    List() {
      ForEach(this.messages.length > 0 ? this.messages : [{ role: 'ai', text: '你好呀，我是 Mimi～今天想记录点什么？我可以帮你写日记、总结今日，或整理聊天里的待办。' }], (item: ChatMessage) => {
        ListItem() {
          this.Bubble(item)
        }
      }, (item: ChatMessage, index: number) => index.toString() + '_' + (item.role as string))
      // T302：流式打字机气泡——onAiDelta 期间实时渲染正在生成的文本
      if (this.busy && this.streamingText.length > 0) {
        ListItem() {
          this.StreamingBubble()
        }
      } else if (this.messages.length > 0 && this.busy) {
        ListItem() {
          this.BusyIndicator()
        }
      }
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: SPACING.pageH, right: SPACING.pageH })
  }

  // ==== T204：busy 思考指示行（复用 Avatar；LoadingProgress+灰字，样式贴近 AI 气泡但更轻）====
  @Builder
  BusyIndicator() {
    Row() {
      Row() {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(this.getTextSecondary())
        Text('Mimi 正在思考…')
          .fontSize(TYPO.body.size)
          .fontWeight(TYPO.body.weight)
          .fontColor(this.getTextSecondary())
          .attributeModifier(SKETCH_BODY)
          .margin({ left: 8 })
      }
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.getCardBg())
      .border({ width: 1.5, color: this.withAlpha(this.getTextSecondary(), '33') })
      .borderRadius({
        topLeft: this.BUBBLE_TAIL,
        topRight: this.BUBBLE_RADIUS,
        bottomLeft: this.BUBBLE_RADIUS,
        bottomRight: this.BUBBLE_RADIUS
      })
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .margin({ left: 8 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(VerticalAlign.Top)
    .accessibilityText('Mimi 正在思考')
  }

  // ==== 单条气泡（AI 左对齐圆角边框 / 用户右对齐圆角边框，宽高随文字自适应）====
  @Builder
  Bubble(msg: ChatMessage) {
    Row() {
      Text(msg.text)
        .fontSize(TYPO.body.size)
        .fontWeight(TYPO.body.weight)
        .fontColor(msg.role === 'ai' ? this.getTextPrimary() : this.getUserBrown())
        .lineHeight(TYPO.body.size + 8)
        .attributeModifier(SKETCH_BODY)
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .borderRadius({
          topLeft: msg.role === 'ai' ? this.BUBBLE_TAIL : this.BUBBLE_RADIUS,
          topRight: msg.role === 'ai' ? this.BUBBLE_RADIUS : this.BUBBLE_TAIL,
          bottomLeft: this.BUBBLE_RADIUS,
          bottomRight: this.BUBBLE_RADIUS
        })
        .border({
          width: 1.5,
          color: msg.role === 'ai' ? this.withAlpha(this.getPrimary(), '59') : this.getUserBrown()
        })
        .backgroundColor(this.getCardBg())
        .constraintSize({ maxWidth: '74%' })
    }
    .width('100%')
    .justifyContent(msg.role === 'ai' ? FlexAlign.Start : FlexAlign.End)
    .alignItems(VerticalAlign.Top)
    .padding({
      left: msg.role === 'ai' ? 0 : 8,
      right: msg.role === 'ai' ? 8 : 0
    })
    .accessibilityText((msg.role === 'ai' ? 'Mimi：' : '我：') + msg.text)
  }

  // ==== T302：流式打字机气泡（圆角边框，末尾闪烁光标）====
  @Builder
  StreamingBubble() {
    Row() {
      Text(this.streamingText)
        .fontSize(TYPO.body.size)
        .fontWeight(TYPO.body.weight)
        .fontColor(this.getTextPrimary())
        .lineHeight(TYPO.body.size + 8)
        .attributeModifier(SKETCH_BODY)
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .borderRadius({
          topLeft: this.BUBBLE_TAIL,
          topRight: this.BUBBLE_RADIUS,
          bottomLeft: this.BUBBLE_RADIUS,
          bottomRight: this.BUBBLE_RADIUS
        })
        .border({ width: 1.5, color: this.withAlpha(this.getPrimary(), '59') })
        .backgroundColor(this.getCardBg())
        .constraintSize({ maxWidth: '74%' })
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(VerticalAlign.Top)
  }

  // ==== 快捷提问 chips（一排横滑）====
  @Builder
  ChipsBar() {
    Scroll() {
      Row({ space: 10 }) {
        this.ChipButton('帮我写日记', $r('sys.symbol.book_open_fill'))
        this.ChipButton('总结今日', $r('sys.symbol.doc_text'))
        this.ChipButton('开心的事有哪些', $r('sys.symbol.star_fill'))
        this.ChipButton('提取聊天任务', $r('sys.symbol.ellipsis_bubble'))
      }
      .padding({ left: SPACING.pageH, right: SPACING.pageH })
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .margin({ bottom: 10 })
  }

  @Builder
  ChipButton(label: string, icon: Resource) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(14)
        .fontColor([this.getPrimary()])
      Text(label)
        .fontSize(TYPO.eyebrow.size)
        .fontWeight(TYPO.cardTitle.weight)
        .fontColor(this.getTextPrimary())
        .margin({ left: 6 })
        .maxLines(1)
        .attributeModifier(SKETCH_BODY) // HUI-028：快捷提问 chip 标签→清松手写体2
    }
    .height(36)
    .padding({ left: 14, right: 14 })
    .borderRadius(RADIUS.input)
    .backgroundColor(this.getCardBg())
    .border({ width: 1, color: this.withAlpha(this.getBtnAux(), '33') })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.onChip(label); })
    .accessibilityText('快捷提问：' + label)
  }

  // ==== 底部输入栏：胶囊输入 + 青色发送按钮 ====
  @Builder
  InputBar() {
    Row() {
      TextInput({ text: this.inputText, placeholder: '和 Mimi 聊聊今天…' })
        .layoutWeight(1)
        .height(48)
        .borderRadius(24)
        .backgroundColor(this.getCardBg())
        .border({ width: 1, color: this.withAlpha(this.getPrimary(), '33') })
        .padding({ left: 16, right: 16 })
        .fontSize(TYPO.body.size)
        .fontColor(this.getTextPrimary())
        .placeholderColor(this.getTextSecondary())
        .placeholderFont({ size: TYPO.body.size })
        .onChange((value: string) => {
          this.inputText = value;
          // 检测击键：置 isTyping=true，停敲 1.5s 后自动回 false
          this.isTyping = true;
          if (this.typingTimer !== -1) {
            clearTimeout(this.typingTimer);
          }
          this.typingTimer = setTimeout(() => {
            this.isTyping = false;
            this.typingTimer = -1;
          }, 1500);
        })
        .onSubmit(() => { this.onSend(); })

      Button() {
        SymbolGlyph(IconMapper.SEND)
          .fontSize(20)
          .fontColor([this.getBtnPrimaryText()])
      }
      .width(48).height(48)
      .borderRadius(24)
      .backgroundColor(this.getBtnPrimary()) // HUI-035：发送主按钮→雾霾蓝 btnPrimary
      .margin({ left: 10 })
      .shadow({ radius: 8, color: this.withAlpha(this.getBtnPrimary(), '4D'), offsetX: 0, offsetY: 3 })
      // T204：busy 期间禁用发送并降透明（可见反馈；pushExchange 内另有挡板兜 onSubmit/chip）
      .enabled(!this.busy)
      .opacity(this.busy ? 0.4 : 1)
      .onClick(() => { this.onSend(); })
      .accessibilityText(this.busy ? 'Mimi 正在思考，暂不可发送' : '发送')
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: SPACING.pageH,
      right: SPACING.pageH,
      top: 10,
      bottom: SPACING.pageTop
    })
  }
}

// === @Preview mock 组件（DevEco Studio Previewer 预览） ===

@Preview
@Component
struct AIChatViewPreview {
  build() {
    Column() {
      AIChatView()
    }.width('100%').height('100%')
  }
}
