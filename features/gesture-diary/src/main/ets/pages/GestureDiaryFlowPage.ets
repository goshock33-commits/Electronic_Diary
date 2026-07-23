// <!-- agentID: HUI-061 -->
// fix: HUI-FRONTEND
// agentID: HUI-041（T-D05：返回箭头统一 — 裸 arrow_left 加粗 ICON.navBack）
// 页面：手势日记完整流程页（触发 → 拍照 → AI 建议 → 编辑保存）
// 关联任务：P2-09 手势日记流程页统一薄荷青皮肤（UX-001 §6.3）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 令牌驱动：圆角 RADIUS、间距 SPACING、字号字重 TYPO、图标 IconMapper，均引用 @ohos/shared
// 图标来源：harmonyos-symbol → dot_radiowaves_left_and_right（eyebrow + 摇一摇触发）
// 图标来源：harmonyos-symbol → camera_fill（Stepper step1 + 拍照触发箭头，IconMapper.CAMERA ✅）
// 图标来源：harmonyos-symbol → star_fill（Stepper step2，UI-001 §3 已用 MOOD_PLEASANT/TAB_STATISTICS ✅，替代 absent sparkles）
// 图标来源：harmonyos-symbol → checkmark（Stepper step3 + 使用照片/确认保存，IconMapper.CHECKMARK ✅）
// 图标来源：harmonyos-symbol → hand_point_up_tap_fill_1（右拉/长按手势）
// 图标来源：harmonyos-symbol → arrow_left（返回）
// 图标来源：harmonyos-symbol → checkmark_circle_fill（保存成功）
// 图标来源：harmonyos-symbol → square_and_pencil（编辑）
// 图标来源：harmonyos-symbol → picture（照片预览占位）
// 设计规范：eyebrow「SHAKE & SNAP」+ H1「手势速记日记」
//           3 步进圆点+连接线(1拍照→2识别→3生成)，取景框 RADIUS.cardLg
//           图标 camera_fill / star_fill（替代 sparkles）/ checkmark，步进 spring 动效
//           全令牌引用：TYPO/RADIUS/SPACING/IconMapper
// 运行时崩溃防范（PROJECT_SPEC §9）：无 getter-in-build（普通方法返回颜色/图标）；字段初值不含 $r()；@StorageLink 判空
import type { ThemeColorTokens } from '@ohos/shared';
// HUI-028：引入手绘字体助手——SKETCH_TITLE=猫啃(阶段标题/eyebrow/H1/保存标题)，SKETCH_BODY=清松(步进标签/选项/提示/正文)；步进序号数字不套。
import { IconMapper, RADIUS, SPACING, TYPO, ICON, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';
import { CameraCaptureView } from '../components/CameraCaptureView';
import { AISuggestionView } from '../components/AISuggestionView';
// F4: 接 GestureDiaryViewModel（识别/建议/落库统一走 VM，替换 setTimeout 占位与本地假保存）
import { GestureDiaryViewModel, DiarySuggestion } from '../viewmodel/GestureDiaryViewModel';
import { router } from '@kit.ArkUI';
import { promptAction, curves } from '@kit.ArkUI';

// 流程阶段：触发 → 拍照 → AI 识别中 → AI 建议 → 已保存
type FlowStage = 'trigger' | 'camera' | 'recognizing' | 'suggestion' | 'saved';

@Component
export struct GestureDiaryFlowPage {
  @State stage: FlowStage = 'trigger';
  @State triggerType: string = 'shake';
  @State sceneTags: string[] = [];
  @State suggestionText: string = '';
  @State ocrText: string = '';
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  // F4: 手势日记 ViewModel（识别+建议+确认落库）
  private vm: GestureDiaryViewModel = new GestureDiaryViewModel();

  aboutToAppear(): void {
    this.vm.init(true);
  }

  // ==== 主题色兜底（普通方法，非 getter，避免首帧崩溃）====

  private getBg(): string {
    return this.tokens ? this.tokens.bg : '#FAF8F5';
  }

  private getPrimary(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
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

  private getTextPrimary(): string {
    return this.tokens ? this.tokens.textPrimary : '#1A1A1A';
  }

  private getTextSecondary(): string {
    return this.tokens ? this.tokens.textSecondary : '#5A5A5A';
  }

  private getTextTertiary(): string {
    return this.tokens ? this.tokens.textTertiary : '#8A8A8A';
  }

  private getCardBg(): string {
    return this.tokens ? this.tokens.bgCard : '#FFFFFF';
  }

  private getBorder(): string {
    return this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)';
  }

  private getSurface(): string {
    return this.tokens ? this.tokens.surface : '#FFFFFF';
  }

  /** 半透明版本 */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  /** 获取阶段中文标题（不含英文 eyebrow，用于顶栏辅助） */
  private getStageTitle(): string {
    if (this.stage === 'trigger') { return '手势速记日记'; }
    if (this.stage === 'camera') { return '拍照记录'; }
    if (this.stage === 'recognizing') { return 'AI 识别中'; }
    if (this.stage === 'suggestion') { return 'AI 日记建议'; }
    return '已保存';
  }

  // ==== 步进状态映射 ====
  // 3 步：1 拍照 → 2 识别 → 3 生成日记

  private getCurrentStep(): number {
    if (this.stage === 'trigger') { return 0; }
    if (this.stage === 'camera') { return 1; }
    if (this.stage === 'recognizing') { return 2; }
    if (this.stage === 'suggestion') { return 3; }
    if (this.stage === 'saved') { return 3; }
    return 0;
  }

  private isStepDone(step: number): boolean {
    return this.getCurrentStep() > step;
  }

  private isStepActive(step: number): boolean {
    return this.getCurrentStep() === step;
  }

  /** Stepper 步进图标（step 1/2/3，均为 IconMapper ✅ 图标） */
  private getStepIcon(step: number): Resource {
    switch (step) {
      case 1: return IconMapper.CAMERA;       // camera_fill
      case 2: return IconMapper.MOOD_PLEASANT; // star_fill（替代 sparkles，§3 verified）
      case 3: return IconMapper.CHECKMARK;     // checkmark
      default: return IconMapper.CHECKMARK;
    }
  }

  /** Stepper 步进文字 */
  private getStepLabel(step: number): string {
    switch (step) {
      case 1: return '拍照';
      case 2: return '识别';
      case 3: return '生成';
      default: return '';
    }
  }

  // ==== 流程驱动 ====

  private onTriggered(): void {
    this.stage = 'camera';
  }

  private async onPhotoConfirmed(): Promise<void> {
    this.stage = 'recognizing';
    // F4: 走 GestureDiaryViewModel 识别+生成建议（替换 setTimeout 占位；真 OCR 需真机）
    try {
      const suggestion: DiarySuggestion = await this.vm.buildSuggestionForPhoto(this.vm.getPhotoUri());
      this.sceneTags = suggestion.scenes;
      this.ocrText = '';
      this.suggestionText = suggestion.content;
      this.stage = 'suggestion';
    } catch (err) {
      promptAction.showToast({ message: '识别失败，请重试', duration: 1500 });
      this.resetFlow();
    }
  }

  private async onRegenerate(): Promise<void> {
    this.stage = 'recognizing';
    // F4: 重新生成同样走 VM（复用已存照片 URI）
    try {
      const suggestion: DiarySuggestion = await this.vm.buildSuggestionForPhoto(this.vm.getPhotoUri());
      this.sceneTags = suggestion.scenes;
      this.suggestionText = suggestion.content;
      this.stage = 'suggestion';
    } catch (err) {
      promptAction.showToast({ message: '生成失败，请重试', duration: 1500 });
      this.stage = 'suggestion';
    }
  }

  private async onConfirmSave(text: string): Promise<void> {
    this.suggestionText = text;
    // F4: 走 VM.confirmSave 落库（VM 内 DiaryDao.insert + DIARY_SAVED 事件），页面不直调 DAO
    const saved: boolean = await this.vm.confirmSave(getContext(this).filesDir, text);
    if (saved) {
      this.stage = 'saved';
      promptAction.showToast({ message: '日记已保存', duration: 1500 });
    } else {
      promptAction.showToast({ message: '保存失败，请重试', duration: 1500 });
    }
  }

  private onDiscard(): void {
    this.resetFlow();
    promptAction.showToast({ message: '已丢弃', duration: 1200 });
  }

  private resetFlow(): void {
    // F4: 同步清理 VM 状态（照片/建议/状态机回 idle）
    this.vm.discard();
    this.sceneTags = [];
    this.suggestionText = '';
    this.ocrText = '';
    this.stage = 'trigger';
  }

  private goBack(): void {
    router.back();
  }

  // ==== build ====

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // 顶部导航栏（返回 + 中文标题）
        Row() {
          Button() {
            SymbolGlyph(IconMapper.ARROW_BACK).fontSize(ICON.navBack)
              .fontWeight(FontWeight.Bold) // HUI-041：系统裸箭头加粗
              .fontColor([this.getTextPrimary()])
          }
          .width(44).height(44).borderRadius(22)
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.goBack(); })
          .accessibilityText('返回')

          Text(this.getStageTitle())
            .fontSize(18).fontWeight(600)
            .fontColor(this.getTextPrimary())
            .margin({ left: 8 })
            .attributeModifier(SKETCH_TITLE) // HUI-028：顶栏阶段标题→猫啃什锦黑

          Blank()
        }
        .width('100%').height(56)
        .padding({ left: SPACING.cardPadSm, right: SPACING.cardPadSm })
        .alignItems(VerticalAlign.Center)

        // 主内容区（按阶段切换）
        if (this.stage === 'trigger') {
          this.buildTriggerStage();
        } else if (this.stage === 'suggestion' || this.stage === 'recognizing') {
          this.buildSuggestionStage();
        } else if (this.stage === 'saved') {
          this.buildSavedStage();
        }
      }
      .width('100%').height('100%')
      .backgroundColor(this.getBg())

      // 相机全屏浮层（camera 阶段）
      if (this.stage === 'camera') {
        CameraCaptureView({
          onCapture: () => {},
          onRetake: () => {},
          onUsePhoto: () => { this.onPhotoConfirmed(); },
          onClose: () => { this.resetFlow(); }
        })
      }
    }
    .width('100%').height('100%')
  }

  // ==== 页面头部：eyebrow「SHAKE & SNAP」+ H1「手势速记日记」====
  @Builder
  buildPageHeader() {
    Column() {
      // eyebrow
      Row() {
        SymbolGlyph(IconMapper.MIC)
          .fontSize(11)
          .fontColor([this.getPrimary()])
        Text('SHAKE & SNAP')
          .fontSize(TYPO.eyebrow.size)
          .fontWeight(700)
          .fontColor(this.getTextSecondary())
          .opacity(0.6)
          .letterSpacing(2.5)
          .margin({ left: 4 })
          .attributeModifier(SKETCH_TITLE) // HUI-028：eyebrow 微标→猫啃什锦黑
      }
      // H1
      Text('手势速记日记')
        .fontSize(TYPO.h1.size)
        .fontWeight(TYPO.h1.weight)
        .fontColor(this.getTextPrimary())
        .margin({ top: 4 })
        .attributeModifier(SKETCH_TITLE) // HUI-028：页面 H1→猫啃什锦黑
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ==== 3 步进器：步进圆点 + 连接线 ====
  @Builder
  buildStepper() {
    Row() {
      ForEach(['1', '2', '3'], (stepStr: string, index: number) => {
        Column() {
          // 步进圆点（含图标或序号）
          Stack() {
            Circle({ width: 32, height: 32 })
              .fill(this.getStepFill(Number(stepStr)))
            if (this.isStepDone(Number(stepStr))) {
              // 已完成：显示 checkmark
              SymbolGlyph(IconMapper.CHECKMARK)
                .fontSize(16)
                .fontColor([this.getBtnPrimaryText()])
            } else if (this.isStepActive(Number(stepStr))) {
              // 激活态：显示该步图标（白字雾霾蓝底）
              SymbolGlyph(this.getStepIcon(Number(stepStr)))
                .fontSize(16)
                .fontColor([this.getBtnPrimaryText()])
            } else {
              // 未激活：序号 + 灰色
              Text(stepStr)
                .fontSize(14)
                .fontWeight(700)
                .fontColor(this.getTextTertiary())
            }
          }
          .scale({ x: this.isStepActive(Number(stepStr)) ? 1.1 : 1, y: this.isStepActive(Number(stepStr)) ? 1.1 : 1 })
          .animation({
            duration: 350,
            curve: curves.springMotion(0.35, 0.86, 0.1)
          })

          Text(this.getStepLabel(Number(stepStr)))
            .fontSize(11)
            .fontWeight(this.isStepActive(Number(stepStr)) ? 600 : 400)
            .fontColor(this.isStepActive(Number(stepStr))
              ? this.getPrimary()
              : (this.isStepDone(Number(stepStr)) ? this.getTextSecondary() : this.getTextTertiary()))
            .margin({ top: 4 })
            .attributeModifier(SKETCH_BODY) // HUI-028：步进标签→清松手写体2
            .animation({
              duration: 300,
              curve: Curve.EaseInOut
            })
        }
        .width(56)
        .alignItems(HorizontalAlign.Center)

        // 连接线（最后一步后无连接线）
        if (index < 2) {
          Row()
            .width(36)
            .height(2)
            .borderRadius(1)
            .backgroundColor(this.isStepDone(Number(stepStr))
              ? this.getBtnPrimary()
              : (this.tokens ? this.tokens.divider : '#E0E0E0'))
            .margin({ top: 15, left: 2, right: 2 })
            .layoutWeight(1)
          // animation for line color
            .animation({ duration: 350, curve: Curve.EaseInOut })
        }
      }, (stepStr: string, index: number) => stepStr)
    }
    .width('100%')
    .padding({ left: SPACING.cardPadSm, right: SPACING.cardPadSm })
    .justifyContent(FlexAlign.Center)
  }

  /** Stepper 圆点填充色 */
  private getStepFill(step: number): string {
    if (this.isStepDone(step)) {
      return this.getBtnPrimary();
    }
    if (this.isStepActive(step)) {
      return this.getBtnPrimary();
    }
    // 未激活：token surface 或 灰
    return this.tokens ? this.tokens.surface : '#E8E8E8';
  }

  // ==== 阶段一：触发引导 ====
  @Builder
  buildTriggerStage() {
    Column() {
      // header: eyebrow + H1
      this.buildPageHeader()

      // stepper（触发态：step1 尚未开始，全灰）
      Column() {
        this.buildStepper()
      }
      .width('100%')
      .margin({ top: SPACING.sectionGap })

      // 触发方式选项（保留原有三选一）
      Column() {
        this.TriggerOption('shake', $r('sys.symbol.dot_radiowaves_left_and_right'), '摇一摇触发', '摇动手机快速拍照')
        this.TriggerOption('swipe', $r('sys.symbol.hand_point_up_tap_fill_1'), '右拉手势触发', '从屏幕右边缘向左滑动')
        this.TriggerOption('longpress', $r('sys.symbol.hand_point_up_tap_fill_1'), '长按书签触发', '长按浮动书签快速记录')
      }
      .width('100%')
      .padding({ left: SPACING.pageH, right: SPACING.pageH })
      .margin({ top: SPACING.sectionGap })

      Blank()

      Text('前端演示模式：点击上方任一方式模拟手势触发')
        .fontSize(TYPO.eyebrow.size)
        .fontColor(this.getTextSecondary())
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ bottom: SPACING.sectionGap })
        .attributeModifier(SKETCH_BODY) // HUI-028：演示提示文案→清松手写体2
    }
    .width('100%').layoutWeight(1)
  }

  @Builder
  TriggerOption(type: string, icon: Resource, title: string, subtitle: string) {
    Row() {
      Column() {
        SymbolGlyph(icon).fontSize(24).fontColor([this.getPrimary()])
      }
      .width(48).height(48).borderRadius(24)
      .backgroundColor(this.withAlpha(this.getBtnAux(), '1A'))
      .justifyContent(FlexAlign.Center)

      Column() {
        Text(title).fontSize(16).fontWeight(500).fontColor(this.getTextPrimary())
          .attributeModifier(SKETCH_BODY) // HUI-028：触发选项标题→清松手写体2
        Text(subtitle).fontSize(13).fontColor(this.getTextSecondary()).margin({ top: 2 })
          .attributeModifier(SKETCH_BODY) // HUI-028：触发选项说明→清松手写体2
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 12 })

      SymbolGlyph(IconMapper.CAMERA).fontSize(20)
        .fontColor([this.getTextSecondary()])
    }
    .width('100%').padding(SPACING.cardPadSm).borderRadius(RADIUS.item)
    .backgroundColor(this.getCardBg())
    .margin({ bottom: 12 })
    .onClick(() => {
      this.triggerType = type;
      this.onTriggered();
    })
    .accessibilityText(title + '，' + subtitle)
  }

  // ==== 阶段二/三：AI 识别中 / AI 建议 ====
  @Builder
  buildSuggestionStage() {
    Scroll() {
      Column() {
        // stepper 在上（progress indicator）
        Column() {
          this.buildStepper()
        }
        .width('100%')
        .margin({ top: SPACING.cardPadSm })

        // 拍摄照片预览占位（取景框：RADIUS.cardLg）
        Stack() {
          Column()
            .width('100%').aspectRatio(4 / 3)
            .borderRadius(RADIUS.cardLg)
            .backgroundColor(this.tokens ? this.tokens.surface : '#E8E8E8')
          Column() {
            SymbolGlyph(IconMapper.IMAGE)
              .fontSize(44)
              .fontColor([this.getTextSecondary()])
            Text('已拍摄照片')
              .fontSize(TYPO.body.size)
              .fontColor(this.getTextSecondary())
              .margin({ top: 8 })
              .attributeModifier(SKETCH_BODY) // HUI-028：照片占位说明→清松手写体2
          }
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .width('100%').aspectRatio(4 / 3)
        }
        .width('100%')
        .borderRadius(RADIUS.cardLg)
        .margin({ top: SPACING.cardGap })

        // AI 建议面板
        AISuggestionView({
          sceneTags: this.sceneTags,
          suggestionText: this.suggestionText,
          ocrText: this.ocrText,
          isProcessing: this.stage === 'recognizing',
          onConfirm: (text: string) => { this.onConfirmSave(text); },
          onEdit: (text: string) => { this.onConfirmSave(text); },
          onRegenerate: () => { this.onRegenerate(); },
          onDiscard: () => { this.onDiscard(); }
        })
          .margin({ top: SPACING.cardGap })
      }
      .width('100%').padding({ left: SPACING.pageH, right: SPACING.pageH })
    }
    .layoutWeight(1).width('100%').scrollBar(BarState.Off)
  }

  // ==== 阶段四：已保存（stepper 全绿 + checkmark_circle_fill）====
  @Builder
  buildSavedStage() {
    Column() {
      // stepper（全绿 done）
      Column() {
        this.buildStepper()
      }
      .width('100%')
      .margin({ top: SPACING.cardPadSm })

      SymbolGlyph(IconMapper.SUCCESS)
        .fontSize(72).fontColor([this.getPrimary()])
        .margin({ top: 48 })
      Text('日记已保存')
        .fontSize(20).fontWeight(600)
        .fontColor(this.getTextPrimary())
        .margin({ top: 20 })
        .attributeModifier(SKETCH_TITLE) // HUI-028：保存成功标题→猫啃什锦黑
      Text('手势日记已成功记录到今天')
        .fontSize(TYPO.body.size)
        .fontColor(this.getTextSecondary())
        .margin({ top: 8 })
        .attributeModifier(SKETCH_BODY) // HUI-028：保存成功副标题→清松手写体2

      // 内容预览卡片
      Column() {
        Row() {
          SymbolGlyph(IconMapper.EDIT).fontSize(16)
            .fontColor([this.getPrimary()])
          Text('日记内容')
            .fontSize(TYPO.body.size).fontWeight(500)
            .fontColor(this.getTextPrimary()).margin({ left: 6 })
            .attributeModifier(SKETCH_BODY) // HUI-028：内容卡标签→清松手写体2
        }.width('100%').margin({ bottom: 8 })
        Text(this.suggestionText)
          .fontSize(TYPO.body.size)
          .fontColor(this.getTextSecondary())
          .maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%').textAlign(TextAlign.Start)
          .attributeModifier(SKETCH_BODY) // HUI-028：日记内容正文→清松手写体2
      }
      .width('100%').padding(SPACING.cardPadSm).borderRadius(RADIUS.item)
      .backgroundColor(this.getCardBg()).margin({ top: 28 })
      .alignItems(HorizontalAlign.Start)

      Blank()

      Row() {
        Button('再记一条')
          .fontSize(15).fontColor(this.getTextPrimary())
          .backgroundColor(this.getBtnAux()) // HUI-035：辅助按钮→燕麦 btnAux + 深字
          .borderRadius(24).height(48).layoutWeight(1)
          .onClick(() => { this.resetFlow(); })
          .accessibilityText('再记一条手势日记')

        Button('完成')
          .fontSize(15).fontWeight(600).fontColor(this.getBtnPrimaryText())
          .backgroundColor(this.getBtnPrimary()) // HUI-035：主按钮→雾霾蓝 btnPrimary
          .borderRadius(24).height(48).layoutWeight(1).margin({ left: 12 })
          .onClick(() => { this.goBack(); })
          .accessibilityText('完成并返回')
      }
      .width('100%').margin({ bottom: SPACING.sectionGap })
    }
    .width('100%').layoutWeight(1)
    .padding({ left: SPACING.pageH, right: SPACING.pageH, top: 0 })
    .justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Center)
  }
}

// === @Preview mock 组件（DevEco Studio Previewer 预览） ===

@Preview
@Component
struct GestureDiaryFlowPagePreview {
  build() {
    Column() {
      GestureDiaryFlowPage()
    }.width('100%').height('100%')
  }
}
