// <!-- agentID: HUI-069 -->
// 组件：成员昵称编辑弹窗（居中毛玻璃 · TextInput）
// UI 模式复用 features/settings NicknameEditModal（T-BUG-004 先例），
// 差异：标题/说明可配（添加成员 / 编辑昵称两用）。
// 关联规范：PROJECT_SPEC §8 ArkTS 严格模式 / §9 崩溃防范（@StorageLink 判空、无 getter-in-build）
// 无障碍：遮罩/输入/取消/保存均含 accessibilityText；触控热区 >= 48vp。

import type { ThemeColorTokens } from '@ohos/shared';
import { RADIUS, SPACING, TYPO, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';

@Component
export struct MemberNicknameModal {
  /** 弹窗标题（添加成员 / 编辑昵称） */
  @Prop titleText: string = '编辑昵称';
  /** 说明文案 */
  @Prop hintText: string = '给家人起个亲切的称呼';
  /** 初始昵称（编辑态回显；添加态为空） */
  @Prop initialName: string = '';
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** 保存回调（回传去空格后的昵称） */
  onConfirm?: (name: string) => void;
  /** 取消回调 */
  onCancel?: () => void;

  /** 输入草稿 */
  @State private draft: string = '';
  /** 卡片入场缩放 */
  @State private cardScale: number = 0.92;

  aboutToAppear(): void {
    this.draft = this.initialName;
    animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.cardScale = 1;
    });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 遮罩：半透明黑 + 毛玻璃（点击取消）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .backdropBlur(10)
        .onClick(() => {
          this.cancel();
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
        .accessibilityText('弹窗遮罩，点击取消')

      // 弹窗卡片
      Column() {
        Text(this.titleText)
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .margin({ bottom: 4 })
          .accessibilityText(this.titleText)
          .attributeModifier(SKETCH_TITLE)

        Text(this.hintText)
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .margin({ bottom: 18 })
          .attributeModifier(SKETCH_BODY)

        TextInput({ text: this.draft, placeholder: '输入昵称' })
          .maxLength(20)
          .type(InputType.Normal)
          .fontSize(TYPO.body.size)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .placeholderColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .caretColor(this.tokens ? this.tokens.primary : '#000000')
          .backgroundColor(this.tokens ? this.tokens.surface : '#F7F7F7')
          .height(48)
          .borderRadius(RADIUS.input)
          .padding({ left: 14, right: 14 })
          .border({ width: 1, color: this.tokens ? this.tokens.border : '#CCCCCC' })
          .onChange((value: string) => {
            this.draft = value;
          })
          .accessibilityText('昵称输入框')

        Row() {
          Button('取消')
            .fontSize(TYPO.body.size)
            .fontWeight(500)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .backgroundColor(this.tokens ? this.tokens.surface : '#F7F7F7')
            .layoutWeight(1)
            .height(48)
            .borderRadius(RADIUS.item)
            .onClick(() => {
              this.cancel();
            })
            .accessibilityText('取消')

          Button('保存')
            .fontSize(TYPO.body.size)
            .fontWeight(600)
            .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
            .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
            .layoutWeight(1)
            .height(48)
            .borderRadius(RADIUS.item)
            .margin({ left: 12 })
            .enabled(this.draft.trim().length > 0)
            .opacity(this.draft.trim().length > 0 ? 1 : 0.5)
            .onClick(() => {
              this.confirm();
            })
            .accessibilityText('保存昵称')
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width('84%')
      .constraintSize({ maxWidth: 420 })
      .padding(SPACING.cardPadLg)
      .borderRadius(RADIUS.cardLg)
      .backgroundColor(this.tokens ? this.tokens.bgCard : 'rgba(255,255,255,0.9)')
      .backdropBlur(24)
      .border({ width: 1, color: this.tokens ? this.tokens.border : '#CCCCCC' })
      .shadow({
        radius: 48,
        color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.15)',
        offsetX: 0,
        offsetY: 16
      })
      .alignItems(HorizontalAlign.Start)
      .scale({ x: this.cardScale, y: this.cardScale })
      .transition(
        TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }))
          .animation({ duration: 240, curve: Curve.EaseOut })
      )
    }
    .width('100%')
    .height('100%')
  }

  private cancel(): void {
    if (this.onCancel) {
      this.onCancel();
    }
  }

  private confirm(): void {
    const name: string = this.draft.trim();
    if (name.length === 0) {
      return;
    }
    if (this.onConfirm) {
      this.onConfirm(name);
    }
  }
}
