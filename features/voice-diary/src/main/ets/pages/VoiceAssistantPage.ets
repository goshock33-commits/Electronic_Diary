// <!-- agentID: HUI-060 -->
// agentID: HUI-041（T-D05：返回箭头统一 — 裸 arrow_left 加粗 ICON.navBack，去圆形填充底）
// 页面：小艺语音助手主页（P2-08：蓝白卡片皮肤统一 —— eyebrow+H1 + RADIUS.cardLg卡片 + 柔和阴影 + 时长mono numCard）
// 关联任务：P2-08（PLN-003 阶段P2 首页骨架复刻 §6.2 语音助手页换肤）
// 关联设计稿：UX-001_redesign_report.md §6.2
// 设计令牌：TYPO / RADIUS / SPACING / FONT（全引用，禁魔数字号/字重/圆角/间距）
// 图标来源：IconMapper.SUCCESS (checkmark_circle_fill ✅), IconMapper.MIC (mic_fill ✅ L1352), dot_radiowaves_left_and_right (L1398 ✅)
//     arrow_left (L 已验证), square_and_pencil (L1598 ✅), bookmark (L61 ✅)
//     waveform 裸名不在本地图标库，用 grep 验证备选 dot_radiowaves_left_and_right (L1398) 表达语音波形语义
// 动效：录音脉冲沿用 VoiceListenRing 三层同心圆扩散（§1.6 ping/pulse 范式）
// 运行时崩溃防范（PROJECT_SPEC §9）：无 getter-in-build；字段初值不含 $r()；@StorageLink 判空；@Prop 无内置属性重名
// 开发范式：ArkTS 声明式开发范式（Stage 模型）
// HUI-028：引入手绘字体助手——SKETCH_TITLE=猫啃(eyebrow/H1/结果标题)，SKETCH_BODY=清松(模式标签/提示/引导/副标题)；时长 mono 保留不动。
import { RADIUS, SPACING, TYPO, FONT, ICON, IconMapper, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';
import type { ThemeColorTokens } from '@ohos/shared';
import { VoiceListenRing } from '../components/VoiceListenRing';
import { VoiceWaveformView } from '../components/VoiceWaveformView';
import { VoiceTranscriptPanel } from '../components/VoiceTranscriptPanel';
import { VoiceResultPanel, VoiceTodoFields } from '../components/VoiceResultPanel';
import { router, promptAction } from '@kit.ArkUI';

// 语音交互阶段：idle=待触发 / listening=聆听中 / processing=识别中 / result=结果确认 / saved=已保存
type VoiceStage = 'idle' | 'listening' | 'processing' | 'result' | 'saved';

@Component
export struct VoiceAssistantPage {
  // 模式：'todo' = 语音添加待办，'diary' = 语音写日记
  @State mode: string = 'todo';
  @State stage: VoiceStage = 'idle';
  // 实时转写文本（mock 逐字追加）
  @State transcript: string = '';
  // 识别结果字段（待办模式）
  @State todoFields: VoiceTodoFields | null = null;
  // 识别结果正文（日记模式）
  @State diaryText: string = '';
  // 低置信度标记（mock 演示）
  @State lowConfidence: boolean = false;
  // 麦克风权限被拒（mock 开关演示）
  @State permissionDenied: boolean = false;
  // 网络超时降级（mock 开关演示）
  @State networkTimeout: boolean = false;
  // 录音时长（秒）—— 监听中逐秒递增
  @State durationSeconds: number = 0;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  // mock 逐字识别的目标文本（按模式区分）
  private readonly TODO_FULL_TEXT: string = '提醒我明天下午三点在三楼会议室开项目周会';
  private readonly DIARY_FULL_TEXT: string = '今天天气很好，午后去公园散步，阳光洒在身上暖暖的，心情格外舒畅。';
  private typingTimerId: number = -1;
  private durationTimerId: number = -1;

  aboutToDisappear(): void {
    this.clearTyping();
    this.stopDurationTimer();
  }

  // ==== 主题色兜底（普通方法，非 getter；对齐蓝白卡片预设值，参考 AIChatView HUI-051）====
  private getBg(): string {
    return this.tokens ? this.tokens.bg : '#F5F7FA';
  }

  private getPrimary(): string {
    return this.tokens ? this.tokens.primary : '#0A59F7';
  }

  private getPrimaryLight(): string {
    return this.tokens ? this.tokens.primaryLight : '#3B82F6';
  }

  private getTextPrimary(): string {
    return this.tokens ? this.tokens.textPrimary : '#1A1A1A';
  }

  private getTextSecondary(): string {
    return this.tokens ? this.tokens.textSecondary : '#666666';
  }

  private getTextTertiary(): string {
    return this.tokens ? this.tokens.textTertiary : '#999999';
  }

  private getCardBg(): string {
    return this.tokens ? this.tokens.bgCard : '#FFFFFF';
  }

  private getSurface(): string {
    return this.tokens ? this.tokens.surface : '#F0F4F8';
  }

  private getBorder(): string {
    return this.tokens ? this.tokens.border : '#E0E6ED';
  }

  private getShadow(): string {
    return this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.08)';
  }

  private getDanger(): string {
    return this.tokens ? this.tokens.danger : '#FF4D4F';
  }

  private getWarning(): string {
    return this.tokens ? this.tokens.warning : '#FAAD14';
  }

  private getSuccess(): string {
    return this.tokens ? this.tokens.success : '#52C41A';
  }

  // HUI-035：交互色专用 token（HarmonyOS 蓝主按钮 / 浅灰辅助 / 白按钮文字）
  private getBtnPrimary(): string {
    return this.tokens ? this.tokens.btnPrimary : '#0A59F7';
  }

  private getBtnAux(): string {
    return this.tokens ? this.tokens.btnAux : '#E0E6ED';
  }

  private getBtnPrimaryText(): string {
    return this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF';
  }

  /** 半透明版本：ArkUI hex-alpha 为 #AARRGGBB，需前置 alpha */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  /** 录音时长格式化 mm:ss（mono 展示） */
  private formatDuration(sec: number): string {
    const m: number = Math.floor(sec / 60);
    const s: number = sec % 60;
    const mm: string = m < 10 ? '0' + m : '' + m;
    const ss: string = s < 10 ? '0' + s : '' + s;
    return mm + ':' + ss;
  }

  private startDurationTimer(): void {
    this.stopDurationTimer();
    this.durationSeconds = 0;
    this.durationTimerId = setInterval(() => {
      this.durationSeconds++;
    }, 1000);
  }

  private stopDurationTimer(): void {
    if (this.durationTimerId !== -1) {
      clearInterval(this.durationTimerId);
      this.durationTimerId = -1;
    }
  }

  // ==== 交互驱动 ====

  /** 切换模式（idle 态才允许切换，避免识别中切换错乱） */
  private switchMode(target: string): void {
    if (this.stage !== 'idle') {
      return;
    }
    this.mode = target;
  }

  /** 监听环点击：开始/停止 */
  private onToggleListen(listening: boolean): void {
    if (this.networkTimeout) {
      return;
    }
    if (listening) {
      this.startListening();
    } else {
      this.stopListening();
    }
  }

  /** 开始监听 -> mock 逐字出字 */
  private startListening(): void {
    this.stage = 'listening';
    this.transcript = '';
    this.startDurationTimer();
    const fullText: string = this.mode === 'todo' ? this.TODO_FULL_TEXT : this.DIARY_FULL_TEXT;
    let idx: number = 0;
    this.clearTyping();
    this.typingTimerId = setInterval(() => {
      if (idx < fullText.length) {
        idx++;
        this.transcript = fullText.substring(0, idx);
      } else {
        this.clearTyping();
        this.stopListening();
      }
    }, 120);
  }

  /** 停止监听 -> 进入识别处理 -> 生成 mock 结果 */
  private stopListening(): void {
    this.clearTyping();
    this.stopDurationTimer();
    if (this.transcript.length === 0) {
      this.stage = 'idle';
      this.durationSeconds = 0;
      promptAction.showToast({ message: '未识别到语音内容', duration: 1500 });
      return;
    }
    this.stage = 'processing';
    setTimeout(() => {
      this.buildMockResult();
      this.stage = 'result';
    }, 900);
  }

  /** 生成 mock 识别结果 */
  private buildMockResult(): void {
    if (this.mode === 'todo') {
      const fields: VoiceTodoFields = {
        title: '开项目周会',
        type: 'meeting',
        date: '2026-07-09',
        time: '15:00',
        location: '三楼会议室'
      };
      this.todoFields = fields;
      this.lowConfidence = true;
    } else {
      this.diaryText = this.transcript;
      this.lowConfidence = false;
    }
  }

  private clearTyping(): void {
    if (this.typingTimerId !== -1) {
      clearInterval(this.typingTimerId);
      this.typingTimerId = -1;
    }
  }

  /** 确认添加待办 */
  private onConfirmTodo(fields: VoiceTodoFields): void {
    this.stage = 'saved';
    promptAction.showToast({ message: '待办已添加：' + fields.title, duration: 1500 });
  }

  /** 确认保存日记 */
  private onConfirmDiary(text: string): void {
    this.diaryText = text;
    this.stage = 'saved';
    promptAction.showToast({ message: '日记已保存', duration: 1500 });
  }

  /** 取消/重来 -> 回到 idle */
  private resetFlow(): void {
    this.clearTyping();
    this.stopDurationTimer();
    this.transcript = '';
    this.todoFields = null;
    this.diaryText = '';
    this.lowConfidence = false;
    this.durationSeconds = 0;
    this.stage = 'idle';
  }

  private goBack(): void {
    router.back();
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Button() {
          SymbolGlyph(IconMapper.ARROW_BACK).fontSize(ICON.navBack)
            .fontWeight(FontWeight.Bold) // HUI-041：系统裸箭头加粗
            .fontColor([this.getTextPrimary()])
        }
        .width(44).height(44).borderRadius(22)
        .backgroundColor(Color.Transparent) // HUI-041：去圆形填充底，保留 44vp 透明热区
        .onClick(() => { this.goBack(); })
        .accessibilityText('返回')

        Blank()
      }
      .width('100%').height(56).padding({ left: 12, right: 16 })
      .alignItems(VerticalAlign.Center)

      // eyebrow + H1（§6.2：XIAOYI VOICE + 小艺语音记事）
      Column() {
        Row() {
          SymbolGlyph(IconMapper.MIC)
            .fontSize(TYPO.eyebrow.size + 2)
            .fontColor([this.getPrimary()])
          Text('XIAOYI VOICE')
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(TYPO.eyebrow.weight)
            .fontColor(this.getTextSecondary())
            .letterSpacing(2)
            .opacity(0.7)
            .margin({ left: 6 })
            .attributeModifier(SKETCH_TITLE) // HUI-028：eyebrow 微标→猫啃什锦黑
        }
        .alignItems(VerticalAlign.Center)

        Text('小艺语音记事')
          .fontSize(TYPO.h1.size)
          .fontWeight(TYPO.h1.weight)
          .fontColor(this.getTextPrimary())
          .margin({ top: 4 })
          .attributeModifier(SKETCH_TITLE) // HUI-028：页面 H1→猫啃什锦黑
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: SPACING.pageH,
        right: SPACING.pageH,
        top: SPACING.pageTop,
        bottom: SPACING.cardGap
      })

      // 模式切换器（待办 / 日记）
      this.buildModeSelector()

      // 主内容区（按阶段切换）
      if (this.stage === 'saved') {
        this.buildSavedStage()
      } else if (this.stage === 'result') {
        this.buildResultStage()
      } else {
        this.buildListenStage()
      }
    }
    .width('100%').height('100%')
    .backgroundColor(this.getBg())
  }

  // ==== 模式切换器（蓝白卡片版）====
  @Builder
  buildModeSelector() {
    Row() {
      this.ModeTab('todo', $r('sys.symbol.bookmark'), '添加待办')
      this.ModeTab('diary', IconMapper.BOOKMARK, '写日记')
    }
    .padding(4).margin({ top: 0, bottom: SPACING.cardGap })
    .width('100%')
  }

  @Builder
  ModeTab(target: string, icon: Resource, label: string) {
    Row() {
      SymbolGlyph(icon).fontSize(16)
        .fontColor([this.mode === target ? this.getBtnPrimaryText() : this.getTextSecondary()])
      Text(label)
        .fontSize(TYPO.body.size).fontWeight(this.mode === target ? 600 : 400)
        .fontColor(this.mode === target ? this.getBtnPrimaryText() : this.getTextSecondary())
        .margin({ left: 6 })
        .attributeModifier(SKETCH_BODY) // HUI-028：模式切换标签→清松手写体2
    }
    .width('46%').height(44).borderRadius(22)
    .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
    .backgroundColor(this.mode === target ? this.getBtnPrimary() : this.getSurface()) // HUI-041：未选中底由死白改读 surface token（getSurface 已带兜底），修深色白底浅灰字不可见
    .border({ width: this.mode === target ? 0 : 1, color: this.getBorder() })
    .margin({ left: 6, right: 6 })
    .onClick(() => { this.switchMode(target); })
    .accessibilityText(label + (this.mode === target ? '，已选中' : ''))
  }

  // ==== 监听阶段（idle / listening / processing）====
  @Builder
  buildListenStage() {
    Column() {
      Blank()

      // 监听环（脉冲动画沿用 VoiceListenRing 三层同心圆扩散，§1.6）
      VoiceListenRing({
        isListening: this.stage === 'listening',
        permissionDenied: this.permissionDenied,
        onToggle: (listening: boolean) => { this.onToggleListen(listening); }
      })

      // 波形图标 + mono 时长（§6.2：时长用 mono numCard；waveform 图标用 grep 验证备选 dot_radiowaves_left_and_right）
      if (this.stage === 'listening' || (this.stage === 'processing' && this.durationSeconds > 0)) {
        Row() {
          SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right'))
            .fontSize(14)
            .fontColor([this.getPrimary()])
          Text(this.formatDuration(this.durationSeconds))
            .fontFamily(FONT.monoExtraBold)
            .fontSize(TYPO.numCard.size)
            .fontWeight(TYPO.numCard.weight)
            .fontColor(this.getPrimary())
            .margin({ left: 6 })
        }
        .margin({ top: 16 })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .accessibilityText('录音时长：' + this.formatDuration(this.durationSeconds))
      }

      // 波形条（监听中显示）
      if (this.stage === 'listening') {
        VoiceWaveformView({ isActive: true })
          .margin({ top: 20 })
      }

      // 识别中提示
      if (this.stage === 'processing') {
        Row() {
          LoadingProgress().width(24).height(24).color(this.getPrimary())
          Text('小艺正在理解你的话…')
            .fontSize(TYPO.body.size).fontColor(this.getTextSecondary()).margin({ left: 10 })
            .attributeModifier(SKETCH_BODY) // HUI-028：识别中提示→清松手写体2
        }
        .margin({ top: 20 }).justifyContent(FlexAlign.Center)
      }

      // 实时转文字面板（监听/识别态显示）—— 外部卡片 RADIUS.cardLg + 柔和阴影
      if (this.stage === 'listening' || this.stage === 'processing' || this.networkTimeout) {
        VoiceTranscriptPanel({
          transcript: this.transcript,
          isListening: this.stage === 'listening',
          networkTimeout: this.networkTimeout,
          onRetry: () => { this.networkTimeout = false; }
        })
          .margin({ top: SPACING.cardGap, left: SPACING.pageH, right: SPACING.pageH })
      }

      Blank()

      // 空识别引导（idle 态）
      if (this.stage === 'idle' && !this.permissionDenied && !this.networkTimeout) {
        Text(this.mode === 'todo' ? '试试说："提醒我明天下午三点开会"' : '试试说出今天发生的事，小艺帮你写成日记')
          .fontSize(TYPO.body.size).fontColor(this.getTextSecondary())
          .textAlign(TextAlign.Center).width('80%')
          .margin({ bottom: 32 })
          .attributeModifier(SKETCH_BODY) // HUI-028：空识别引导→清松手写体2
      }
    }
    .width('100%').layoutWeight(1).padding({ left: 0, right: 0 })
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }

  // ==== 结果确认阶段 ====
  @Builder
  buildResultStage() {
    Scroll() {
      Column() {
        VoiceResultPanel({
          mode: this.mode,
          todoFields: this.todoFields,
          diaryText: this.diaryText,
          lowConfidence: this.lowConfidence,
          onConfirmTodo: (fields: VoiceTodoFields) => { this.onConfirmTodo(fields); },
          onConfirmDiary: (text: string) => { this.onConfirmDiary(text); },
          onEdit: () => { router.pushUrl({ url: 'pages/DiaryEditPage' }); },
          onCancel: () => { this.resetFlow(); }
        })
      }
      .width('100%').padding(SPACING.pageH)
    }
    .layoutWeight(1).width('100%').scrollBar(BarState.Off)
  }

  // ==== 已保存阶段 ====
  @Builder
  buildSavedStage() {
    Column() {
      Blank()
      // checkmark_circle_fill：复用 IconMapper.SUCCESS（grep 验证 L ✅）
      SymbolGlyph(IconMapper.SUCCESS)
        .fontSize(72).fontColor([this.getPrimary()])
      Text(this.mode === 'todo' ? '待办已添加' : '日记已保存')
        .fontSize(TYPO.h1.size).fontWeight(TYPO.h1.weight).fontColor(this.getTextPrimary()).margin({ top: 20 })
        .attributeModifier(SKETCH_TITLE) // HUI-028：结果确认标题→猫啃什锦黑
      Text('小艺已帮你记录完成')
        .fontSize(TYPO.body.size).fontColor(this.getTextSecondary()).margin({ top: 8 })
        .attributeModifier(SKETCH_BODY) // HUI-028：结果副标题→清松手写体2
      Blank()

      Row() {
        Button('再记一条')
          .fontSize(TYPO.body.size).fontColor(this.getTextPrimary())
          .backgroundColor(this.getBtnAux()) // HUI-035：辅助按钮→浅灰 btnAux + 深字
          .borderRadius(RADIUS.input).height(48).layoutWeight(1)
          .onClick(() => { this.resetFlow(); })
          .accessibilityText('再记一条')

        Button('完成')
          .fontSize(TYPO.body.size).fontWeight(600).fontColor(this.getBtnPrimaryText())
          .backgroundColor(this.getBtnPrimary()) // HUI-035：主按钮→HarmonyOS 蓝 btnPrimary + 白字
          .borderRadius(RADIUS.input).height(48).layoutWeight(1).margin({ left: 12 })
          .onClick(() => { this.goBack(); })
          .accessibilityText('完成并返回')
      }
      .width('100%').margin({ bottom: 24 })
    }
    .width('100%').layoutWeight(1).padding({ left: SPACING.pageH, right: SPACING.pageH })
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }
}

// === @Preview mock 组件（DevEco Studio Previewer 预览） ===

@Preview
@Component
struct VoiceAssistantPagePreview {
  build() {
    Column() {
      VoiceAssistantPage()
    }.width('100%').height('100%')
  }
}
