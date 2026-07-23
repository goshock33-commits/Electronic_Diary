// <!-- agentID: HUI-001 -->
// 组件：昵称编辑弹窗（居中毛玻璃 · TextInput）—— T-BUG-004
// 关联需求：HARMONYOS_REQUIREMENTS §11 弹窗背景毛玻璃
// 关联规范：PROJECT_SPEC §8 ArkTS 严格模式 / §9 崩溃防范 / §10 图标本地库
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 系统组件：Stack / Column / Row / TextInput / Button / Text
// 崩溃防范：@StorageLink tokens 判空回退；无 getter-in-build；@Prop 默认值不含 $r()。
// 无障碍：遮罩/输入/取消/保存均含 accessibilityText；触控热区 >= 48vp。

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_TITLE=猫啃什锦黑（弹窗标题）、SKETCH_BODY=清松手写体2（中文说明）；Button('取消'/'保存') 不动。
import { RADIUS, SPACING, TYPO, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';

@Component
export struct NicknameEditModal {
  /** 初始昵称（父组件传入当前值） */
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
        Text('编辑昵称')
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .margin({ bottom: 4 })
          .accessibilityText('编辑昵称')
          .attributeModifier(SKETCH_TITLE) // HUI-029：弹窗标题→猫啃什锦黑

        Text('给自己起个喜欢的名字')
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .margin({ bottom: 18 })
          .attributeModifier(SKETCH_BODY) // HUI-029：中文说明文案→清松手写体2

        TextInput({ text: this.draft, placeholder: '输入昵称' })
          .maxLength(20)
          .type(InputType.Normal)
          .fontSize(TYPO.body.size)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .placeholderColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .caretColor(this.tokens ? this.tokens.primary : '#00C2B8')
          .backgroundColor(this.tokens ? this.tokens.surface : '#F2F4F3')
          .height(48)
          .borderRadius(RADIUS.input)
          .padding({ left: 14, right: 14 })
          .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)' })
          .onChange((value: string) => {
            this.draft = value;
          })
          .accessibilityText('昵称输入框')

        Row() {
          Button('取消')
            .fontSize(TYPO.body.size)
            .fontWeight(500)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .backgroundColor(this.tokens ? this.tokens.surface : '#F2F4F3')
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
            // HUI-038：保存主按钮（漏网）→ btnPrimaryText 白字 + btnPrimary 雾霾蓝底（原 primary 兜底青 #00C2B8）
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
      .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)' })
      .shadow({
        radius: 48,
        color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.15)',
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
