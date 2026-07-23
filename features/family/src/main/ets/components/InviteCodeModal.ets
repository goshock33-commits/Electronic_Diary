// <!-- agentID: HUI-069 -->
// 组件：邀请码输入弹窗（居中毛玻璃 · TextInput 自动转大写）
// UI 模式复用本模块 MemberNicknameModal（同一先例链：features/settings NicknameEditModal），
// 差异：输入限 6 位邀请码字符集，格式校验通过才允许保存。
// 关联规范：PROJECT_SPEC §8 ArkTS 严格模式 / §9 崩溃防范（@StorageLink 判空、无 getter-in-build）
// 配色：黑白灰令牌，无青色（用户设计偏好 memory）
// 无障碍：遮罩/输入/取消/加入均含 accessibilityText；触控热区 >= 48vp。

import type { ThemeColorTokens } from '@ohos/shared';
import { RADIUS, SPACING, TYPO, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';

@Component
export struct InviteCodeModal {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** 确认回调（回传大写后的 6 位邀请码） */
  onConfirm?: (code: string) => void;
  /** 取消回调 */
  onCancel?: () => void;

  /** 输入草稿（始终保持大写） */
  @State private draft: string = '';
  /** 卡片入场缩放 */
  @State private cardScale: number = 0.92;

  aboutToAppear(): void {
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
        Text('加入家庭')
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .margin({ bottom: 4 })
          .accessibilityText('加入家庭')
          .attributeModifier(SKETCH_TITLE)

        Text('输入家人分享的 6 位邀请码')
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .margin({ bottom: 18 })
          .attributeModifier(SKETCH_BODY)

        TextInput({ text: this.draft, placeholder: '如 A2B3C4' })
          .maxLength(6)
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
            // 自动转大写，避免用户切换大小写键盘
            this.draft = value.toUpperCase();
          })
          .accessibilityText('邀请码输入框，6 位字母数字')

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

          Button('加入')
            .fontSize(TYPO.body.size)
            .fontWeight(600)
            .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
            .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
            .layoutWeight(1)
            .height(48)
            .borderRadius(RADIUS.item)
            .margin({ left: 12 })
            .enabled(FamilyViewModel.isValidInviteCode(this.draft))
            .opacity(FamilyViewModel.isValidInviteCode(this.draft) ? 1 : 0.5)
            .onClick(() => {
              this.confirm();
            })
            .accessibilityText('加入家庭')
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
    const code: string = this.draft.trim().toUpperCase();
    if (!FamilyViewModel.isValidInviteCode(code)) {
      return;
    }
    if (this.onConfirm) {
      this.onConfirm(code);
    }
  }
}
