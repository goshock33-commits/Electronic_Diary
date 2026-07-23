// <!-- agentID: HUI-083 -->
// fix: F10
// 组件：安全锁 PIN 设置弹窗（居中毛玻璃 · 两段式 4 位数字输入）—— F10 新建 PIN 设置流程
// 关联需求：F10 安全锁开关 ON → 弹本窗设 PIN → SettingsViewModel.setPin(pin)
// 关联规范：PROJECT_SPEC §8 ArkTS 严格模式 / §9.4 tokens 判空 / §10 图标本地库（本窗无 symbol 图标）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming（沿用 NicknameEditModal 既定弹窗范式）
// 系统组件：Stack / Column / Row / TextInput / Button / Text
// 崩溃防范：@StorageLink tokens 全判空回退；无 getter-in-build；字段初值不含 $r()。
// 交互流程：第 1 步输入 4 位数字（NUMBER_PASSWORD 数字键盘）→ 第 2 步再次输入确认
//           → 一致则 onConfirm(pin) 交父组件落库；不一致回到第 1 步重设；取消 onCancel()。
// 字体：标题 SKETCH_TITLE（猫啃什锦黑）/ 说明与按钮 FONT.sketchBody（清松手写体2）/ PIN 数字 FONT.monoBold
// API 验证（本地 SDK text_input.d.ts）：InputType.NUMBER_PASSWORD(L189) / showPasswordIcon(L2237) / textAlign(L2274)

import type { ThemeColorTokens } from '@ohos/shared';
import { RADIUS, SPACING, TYPO, FONT, SKETCH_TITLE } from '@ohos/shared';

/** PIN 位数 */
const PIN_LENGTH: number = 4;
/** 4 位纯数字校验 */
const PIN_PATTERN: RegExp = /^\d{4}$/;

@Component
export struct PinSetupModal {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** 确认回调（两次输入一致后回传 4 位 PIN，由父组件调 SettingsViewModel.setPin 落库） */
  onConfirm?: (pin: string) => void;
  /** 取消回调（父组件负责把安全锁开关回拨 OFF） */
  onCancel?: () => void;

  /** 当前步骤：1=首次输入，2=确认输入 */
  @State private stage: number = 1;
  /** 第 1 步录入的 PIN */
  @State private firstPin: string = '';
  /** 当前输入草稿 */
  @State private draft: string = '';
  /** 错误提示（空串不显示，占位固定高度防跳动） */
  @State private errorMsg: string = '';
  /** 卡片入场缩放 */
  @State private cardScale: number = 0.92;

  aboutToAppear(): void {
    animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.cardScale = 1;
    });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 遮罩：半透明黑 + 毛玻璃（点击取消 → 开关回拨）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .backdropBlur(10)
        .onClick(() => {
          this.cancel();
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
        .accessibilityText('弹窗遮罩，点击取消设置 PIN')

      // 弹窗卡片
      Column() {
        Text(this.stage === 1 ? '设置 PIN 码' : '确认 PIN 码')
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .margin({ bottom: 4 })
          .accessibilityText(this.stage === 1 ? '设置 PIN 码，第一步共两步' : '确认 PIN 码，第二步共两步')
          .attributeModifier(SKETCH_TITLE) // 弹窗标题→猫啃什锦黑

        Text(this.stage === 1 ? '输入 4 位数字，用于解锁日记' : '再次输入相同的 4 位数字')
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .fontFamily(FONT.sketchBody) // 中文说明→清松手写体2
          .margin({ bottom: 18 })

        // 单个密码输入框：数字键盘 + 密文圆点；onChange 兜底过滤非数字（F10「验证输入为数字」）
        TextInput({ text: this.draft, placeholder: '····' })
          .type(InputType.NUMBER_PASSWORD)
          .maxLength(PIN_LENGTH)
          .showPasswordIcon(false)
          .textAlign(TextAlign.Center)
          .fontSize(TYPO.h1.size)
          .fontFamily(FONT.monoBold) // PIN 数字→JetBrains Mono Bold
          .letterSpacing(8)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .placeholderColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .caretColor(this.tokens ? this.tokens.primary : '#1A1A1A')
          .backgroundColor(this.tokens ? this.tokens.surface : '#F2F4F3')
          .height(56)
          .borderRadius(RADIUS.input)
          .padding({ left: 14, right: 14 })
          .border({ width: 1, color: this.tokens ? this.tokens.border : '#EAEAE6' })
          .onChange((value: string) => {
            // 数字校验：剔除任何非数字字符并截断到 4 位
            const digits: string = value.replace(/\D+/g, '').substring(0, PIN_LENGTH);
            this.draft = digits;
            if (this.errorMsg.length > 0 && digits.length > 0) {
              this.errorMsg = '';
            }
          })
          .accessibilityText((this.stage === 1 ? 'PIN 码输入框' : 'PIN 码确认输入框') +
            '，已输入 ' + this.draft.length + ' 位，共 4 位')

        // 错误提示（固定高度占位，避免布局跳动）
        Text(this.errorMsg)
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.danger : '#78909C')
          .fontFamily(FONT.sketchBody)
          .height(18)
          .margin({ top: 8 })
          .opacity(this.errorMsg.length > 0 ? 1 : 0)
          .accessibilityText(this.errorMsg)

        Row() {
          Button('取消')
            .fontSize(TYPO.body.size)
            .fontWeight(500)
            .fontFamily(FONT.sketchBody)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .backgroundColor(this.tokens ? this.tokens.surface : '#F2F4F3')
            .layoutWeight(1)
            .height(48)
            .borderRadius(RADIUS.item)
            .onClick(() => {
              this.cancel();
            })
            .accessibilityText('取消设置 PIN，安全锁保持关闭')

          Button(this.stage === 1 ? '下一步' : '开启安全锁')
            .fontSize(TYPO.body.size)
            .fontWeight(600)
            .fontFamily(FONT.sketchBody)
            .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
            .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
            .layoutWeight(1)
            .height(48)
            .borderRadius(RADIUS.item)
            .margin({ left: 12 })
            .enabled(this.draft.length === PIN_LENGTH)
            .opacity(this.draft.length === PIN_LENGTH ? 1 : 0.5)
            .onClick(() => {
              this.primaryAction();
            })
            .accessibilityText(this.stage === 1 ? '下一步，确认输入 PIN' : '开启安全锁')
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('84%')
      .constraintSize({ maxWidth: 420 })
      .padding(SPACING.cardPadLg)
      .borderRadius(RADIUS.cardLg)
      .backgroundColor(this.tokens ? this.tokens.bgCard : 'rgba(255,255,255,0.9)')
      .backdropBlur(24)
      .border({ width: 1, color: this.tokens ? this.tokens.border : '#EAEAE6' })
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

  /** 主按钮：第 1 步暂存进入确认；第 2 步比对，一致回传，不一致回到第 1 步重设 */
  private primaryAction(): void {
    if (!PIN_PATTERN.test(this.draft)) {
      this.errorMsg = '请输入 4 位数字';
      return;
    }
    if (this.stage === 1) {
      this.firstPin = this.draft;
      this.draft = '';
      this.errorMsg = '';
      this.stage = 2;
      return;
    }
    if (this.draft !== this.firstPin) {
      // 两次不一致：清空回到第 1 步重新设置
      this.firstPin = '';
      this.draft = '';
      this.stage = 1;
      this.errorMsg = '两次输入不一致，请重新设置';
      return;
    }
    if (this.onConfirm) {
      this.onConfirm(this.draft);
    }
  }
}
