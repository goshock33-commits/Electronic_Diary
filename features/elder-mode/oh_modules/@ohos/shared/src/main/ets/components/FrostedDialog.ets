// <!-- agentID: HUI-001 -->
// 组件：毛玻璃弹窗（3 级模糊可选）
// 关联设计稿：UX-001_prototype.html（dialog-overlay + dialog）
// 关联任务：T009（第1批）
// 关联需求：需求 11 全局设计要求（沉浸光感材质）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：遵守 T042 规范

import type { ThemeColorTokens } from '../theme/ThemeConfig';
import { FrostedBlurLevel } from '../theme/ThemeConfig';
import { FrostedGlassUtils } from '../theme/FrostedGlassUtils';
import { RADIUS, SPACING } from '../theme/LayoutTokens';
import { TYPO } from '../theme/TypographyTokens';
// HUI-028：shared 组件不能 import @ohos/shared 自身，改用相对路径引手绘字体 modifier（SKETCH_TITLE=猫啃标题·SKETCH_BODY=清松正文）。
import { SKETCH_TITLE, SKETCH_BODY } from '../theme/SketchTextModifiers';

/**
 * FrostedDialog 配置参数
 */
export interface FrostedDialogConfig {
  /** 弹窗标题 */
  title?: string;
  /** 弹窗内容文本 */
  message?: string;
  /** 模糊等级 (1-3) */
  blurLevel?: number;
  /** 确认按钮文字 */
  confirmText?: string;
  /** 取消按钮文字 */
  cancelText?: string;
  /** HUI-001：中性按钮模式（黑白灰，删除确认等场景） */
  neutralButtons?: boolean;
  /** 确认回调 */
  onConfirm?: () => void;
  /** 取消回调 */
  onCancel?: () => void;
}

@CustomDialog
export struct FrostedDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: FrostedDialog({})
  });
  @Prop title: string = '';
  @Prop message: string = '';
  @Prop blurLevel: number = FrostedBlurLevel.MEDIUM;
  @Prop confirmText: string = '确认';
  @Prop cancelText: string = '取消';
  // HUI-001：中性按钮模式（删除确认等场景）——按钮改黑白灰中性（浅色深灰钮白字/深色浅灰钮黑字，
  //   走 tokens.textPrimary/bgCard 随主题翻转，对比度≥4.5:1），禁大红。默认 false 不影响既有调用方。
  @Prop neutralButtons: boolean = false;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  onConfirm?: () => void;
  onCancel?: () => void;

  build() {
    Column() {
      // 标题
      if (this.title.length > 0) {
        Text(this.title)
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .margin({ bottom: 12 })
          .accessibilityText(this.title)
          .attributeModifier(SKETCH_TITLE) // HUI-028：弹窗标题→猫啃什锦黑
      }

      // 内容
      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(16)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
          .lineHeight(24)
          .margin({ bottom: 24 })
          .accessibilityText(this.message)
          .attributeModifier(SKETCH_BODY) // HUI-028：弹窗正文→清松手写体2
      }

      // 按钮区
      Row() {
        // 取消按钮
        Button(this.cancelText)
          .fontSize(14)
          .fontWeight(500)
          // HUI-001：中性模式取消钮文字→textSecondary 灰（默认仍为燕麦 btnAux）
          .fontColor(this.neutralButtons ?
            (this.tokens ? this.tokens.textSecondary : '#5A5A5A') :
            (this.tokens ? this.tokens.btnAux : '#C6BBAE')) // HUI-035：辅助按钮文字→燕麦 btnAux
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .height(44)
          .borderRadius(22)
          .onClick(() => {
            if (this.onCancel) {
              this.onCancel();
            }
            this.controller.close();
          })
          .accessibilityText(this.cancelText + '按钮')

        // 确认按钮
        Button(this.confirmText)
          .fontSize(14)
          .fontWeight(600)
          // HUI-001：中性模式确认钮→深浅灰底+反色字（textPrimary 底 / bgCard 字，随主题翻转）
          .fontColor(this.neutralButtons ?
            (this.tokens ? this.tokens.bgCard : '#FFFFFF') :
            (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')) // HUI-035：主按钮文字→btnPrimaryText 白
          .backgroundColor(this.neutralButtons ?
            (this.tokens ? this.tokens.textPrimary : '#3C3C3C') :
            (this.tokens ? this.tokens.btnPrimary : '#738A9C')) // HUI-035：主按钮底→雾霾蓝 btnPrimary
          .layoutWeight(1)
          .height(44)
          .borderRadius(22)
          .shadow({
            radius: 8,
            color: this.neutralButtons ? 'rgba(0,0,0,0.18)' :
              (this.tokens ? this.tokens.shadow : 'rgba(115,138,156,0.30)'), // HUI-035：兜底阴影→雾霾蓝 30%
            offsetX: 0,
            offsetY: 2
          })
          .margin({ left: 12 })
          .onClick(() => {
            if (this.onConfirm) {
              this.onConfirm();
            }
            this.controller.close();
          })
          .accessibilityText(this.confirmText + '按钮')
      }
      .width('100%')
    }
    .width('85%')
    .padding(SPACING.cardPadLg)
    .borderRadius(RADIUS.cardLg)
    .backgroundColor(this.tokens ? this.tokens.bgCard : 'rgba(255,255,255,0.85)')
    .backdropBlur(FrostedGlassUtils.getBackdropBlurRadius(this.blurLevel))
    .shadow({
      radius: 48,
      color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.15)',
      offsetX: 0,
      offsetY: 16
    })
    .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)' })
    .accessibilityGroup(true)
  }
}
