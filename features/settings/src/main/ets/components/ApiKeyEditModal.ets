// <!-- agentID: HUI-001 -->
// 组件：DeepSeek API Key 录入弹窗（居中毛玻璃 · TextInput）—— T104
// 关联计划：PLN-001 T104（设置页「AI 伙伴」卡片 · Key 录入弹窗）
// 关联规范：PROJECT_SPEC §8 ArkTS 严格模式 / §9 崩溃防范 / §10 图标本地库
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 系统组件：Stack / Column / Row / TextInput / Button / Text
//
// ── 复用说明（M6 红字）───────────────────────────────────────────
//   仅复用 NicknameEditModal 的「弹窗 UI 模式」（遮罩 + 标题 + TextInput + 取消/保存）；
//   持久化不在本组件内做——onConfirm 回传明文，由 SettingsPage 走 T102 加密通路
//   PersistentState.saveApiKey()（先例昵称弹窗只落 AppStorage 会话级，其坑不复用）。
// ── 无青色（用户偏好 + T104 红字 L3）─────────────────────────────
//   新元素 fallback 一律中性灰（#1A1A1A/#5A5A5A/#8A8A8A），不复制旧组件的 #00C2B8 兜底。
// 崩溃防范：@StorageLink tokens 判空回退；无 getter-in-build；字段初始值不含 $r()。
// 无障碍：遮罩/输入/取消/保存均含 accessibilityText；按钮高 48vp 触控热区。

import type { ThemeColorTokens } from '@ohos/shared';
import { RADIUS, SPACING, TYPO, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';

@Component
export struct ApiKeyEditModal {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** 保存回调（回传去空格后的明文 Key，由父组件走 T102 加密持久化） */
  onConfirm?: (key: string) => void;
  /** 取消回调 */
  onCancel?: () => void;

  /** 输入草稿（安全考量：不回显已存明文 Key，重填即覆盖） */
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
        Text('DeepSeek API Key')
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .margin({ bottom: 4 })
          .accessibilityText('DeepSeek API Key')
          .attributeModifier(SKETCH_TITLE)

        Text('密钥仅在本机加密保存')
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .margin({ bottom: 18 })
          .attributeModifier(SKETCH_BODY)

        TextInput({ text: this.draft, placeholder: 'sk-...' })
          .maxLength(128)
          .type(InputType.Normal)
          .fontSize(TYPO.body.size)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .placeholderColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .caretColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .backgroundColor(this.tokens ? this.tokens.surface : '#F2F4F3')
          .height(48)
          .borderRadius(RADIUS.input)
          .padding({ left: 14, right: 14 })
          .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,0,0,0.12)' })
          .onChange((value: string) => {
            this.draft = value;
          })
          .accessibilityText('API Key 输入框')

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
            .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
            .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#1A1A1A')
            .layoutWeight(1)
            .height(48)
            .borderRadius(RADIUS.item)
            .margin({ left: 12 })
            .enabled(this.draft.trim().length > 0)
            .opacity(this.draft.trim().length > 0 ? 1 : 0.5)
            .onClick(() => {
              this.confirm();
            })
            .accessibilityText('保存 API Key')
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
      .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,0,0,0.12)' })
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
    const key: string = this.draft.trim();
    if (key.length === 0) {
      return;
    }
    if (this.onConfirm) {
      this.onConfirm(key);
    }
  }
}
