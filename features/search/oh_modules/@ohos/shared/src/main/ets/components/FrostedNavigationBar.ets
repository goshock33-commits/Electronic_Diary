// <!-- agentID: HUI-001 -->
// 组件：沉浸光感毛玻璃导航栏
// 关联设计稿：UX-001_prototype.html（frosted-nav）
// 关联任务：T009（第1批）
// 关联需求：需求 11 全局设计要求（沉浸光感材质）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：遵守 T042 规范

import type { ThemeColorTokens } from '../theme/ThemeConfig';
import { FrostedGlassUtils } from '../theme/FrostedGlassUtils';
import { FrostedBlurLevel } from '../theme/ThemeConfig';
import { SPACING } from '../theme/LayoutTokens';
import { TYPO } from '../theme/TypographyTokens';

/**
 * 导航栏动作按钮配置
 */
export interface NavAction {
  /** 图标资源 */
  icon: Resource;
  /** 按钮文字（用于 accessibilityText） */
  label: string;
  /** 点击回调 */
  onClick: () => void;
}

@Component
export struct FrostedNavigationBar {
  @Prop title: string = '';
  @Prop actions: NavAction[] = [];
  @Prop blurLevel: number = FrostedBlurLevel.MEDIUM;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  build() {
    Row() {
      // 标题
      Text(this.title)
        .fontSize(TYPO.sectionTitle.size)
        .fontWeight(TYPO.sectionTitle.weight)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .letterSpacing(-0.02)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      // 操作按钮区域
      Row() {
        ForEach(this.actions, (action: NavAction) => {
          Button() {
            SymbolGlyph(action.icon)
              .fontSize(18)
              .fontColor([this.tokens ? this.tokens.textSecondary : '#5A5A5A'])
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(this.tokens ? this.tokens.btnAux : '#C6BBAE') // HUI-035：圆形动作按钮底→燕麦 btnAux
          .type(ButtonType.Circle)
          .onClick(() => {
            action.onClick();
          })
          .accessibilityText(action.label)
          .animation({
            duration: 150,
            curve: Curve.EaseOut
          })
        }, (action: NavAction) => action.label)
      }
      .width('auto')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height(56)
    .padding({ left: SPACING.cardPadSm, right: SPACING.cardPadSm })
    .backgroundColor(this.tokens ? this.tokens.bgOverlay : 'rgba(255,255,255,0.65)')
    .backdropBlur(FrostedGlassUtils.getBackdropBlurRadius(this.blurLevel))
    .border({ width: { bottom: 1 }, color: this.tokens ? this.tokens.divider : 'rgba(0,194,184,0.08)' })
  }
}
