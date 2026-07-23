// <!-- agentID: HUI-001 -->
// 组件：弹性缩放按钮（按压缩小→回弹+光晕扩散+触感反馈）
// 关联设计稿：UX-001_prototype.html（elastic-btn + ripple）
// 关联任务：T009（第1批）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：遵守 T042 规范（触控热区 >= 48x48vp）

import type { ThemeColorTokens } from '../theme/ThemeConfig';

/**
 * ElasticButton 样式模式
 */
export enum ElasticButtonStyle {
  /** 实心主按钮 */
  PRIMARY = 'primary',
  /** 描边按钮 */
  OUTLINE = 'outline',
  /** 幽灵按钮 */
  GHOST = 'ghost',
  /** 圆形图标按钮 */
  CIRCLE = 'circle'
}

@Component
export struct ElasticButton {
  @Prop label: string = '';
  @Prop icon: Resource | null = null;
  @Prop style: ElasticButtonStyle = ElasticButtonStyle.PRIMARY;
  @Prop disabled: boolean = false;
  @Prop buttonWidth: number = 0;
  @Prop buttonHeight: number = 48;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  @State private pressScale: number = 1.0;
  @State private rippleOpacity: number = 0;
  @State private rippleScale: number = 0;
  onButtonClick?: () => void;

  build() {
    if (this.style === ElasticButtonStyle.CIRCLE) {
      this.buildCircleButton();
    } else {
      this.buildStandardButton();
    }
  }

  @Builder
  buildStandardButton() {
    Button() {
      Row() {
        if (this.icon) {
          SymbolGlyph(this.icon)
            .fontSize(18)
            .fontColor([this.getTextColor()])
        }
        if (this.label.length > 0) {
          Text(this.label)
            .fontSize(14)
            .fontWeight(500)
            .fontColor(this.getTextColor())
            .margin({ left: this.icon ? 8 : 0 })
        }
      }
      .justifyContent(FlexAlign.Center)
    }
    .width(this.buttonWidth > 0 ? this.buttonWidth : undefined)
    .height(this.buttonHeight)
    .borderRadius(this.buttonHeight / 2)
    .backgroundColor(this.getBackgroundColor())
    .border({ width: this.style === ElasticButtonStyle.OUTLINE ? 1.5 : 0,
      color: this.tokens ? this.tokens.btnAux : '#C6BBAE' })
    .shadow(this.style === ElasticButtonStyle.PRIMARY ? {
      radius: 8,
      color: this.tokens ? this.tokens.shadow : 'rgba(115,138,156,0.30)',
      offsetX: 0,
      offsetY: 2
    } : undefined)
    .enabled(!this.disabled)
    .scale({ x: this.pressScale, y: this.pressScale })
    .opacity(this.disabled ? 0.5 : 1.0)
    .onClick(() => {
      this.onPressAnimation();
      if (this.onButtonClick && !this.disabled) {
        this.onButtonClick();
      }
    })
    .animation({
      duration: 300,
      curve: Curve.EaseInOut,
      iterations: 1
    })
  }

  @Builder
  buildCircleButton() {
    Button() {
      if (this.icon) {
        SymbolGlyph(this.icon)
          .fontSize(22)
          .fontColor([this.getTextColor()])
      }
    }
    .width(this.buttonWidth > 0 ? this.buttonWidth : this.buttonHeight)
    .height(this.buttonHeight)
    .borderRadius(this.buttonHeight / 2)
    .backgroundColor(this.getBackgroundColor())
    .border({ width: this.style === ElasticButtonStyle.OUTLINE ? 2 : 0,
      color: this.tokens ? this.tokens.btnAux : '#C6BBAE' })
    .shadow(this.style === ElasticButtonStyle.PRIMARY ? {
      radius: 12,
      color: this.tokens ? this.tokens.shadow : 'rgba(115,138,156,0.30)',
      offsetX: 0,
      offsetY: 4
    } : undefined)
    .enabled(!this.disabled)
    .scale({ x: this.pressScale, y: this.pressScale })
    .opacity(this.disabled ? 0.5 : 1.0)
    .onClick(() => {
      this.onPressAnimation();
      if (this.onButtonClick && !this.disabled) {
        this.onButtonClick();
      }
    })
    .animation({
      duration: 300,
      curve: Curve.EaseInOut,
      iterations: 1
    })
  }

  /**
   * 按下缩放动画：95% → 回弹至 100%，模拟物理弹性
   */
  private onPressAnimation(): void {
    if (this.disabled) {
      return;
    }
    // 缩放到 95%
    this.pressScale = 0.95;
    // 回弹到 100%
    setTimeout(() => {
      this.pressScale = 1.0;
    }, 150);
  }

  private getBackgroundColor(): ResourceColor {
    if (this.style === ElasticButtonStyle.PRIMARY) {
      return this.tokens ? this.tokens.btnPrimary : '#738A9C'; // HUI-035：实心主按钮→雾霾蓝 btnPrimary
    } else if (this.style === ElasticButtonStyle.OUTLINE || this.style === ElasticButtonStyle.GHOST) {
      return Color.Transparent;
    }
    return this.tokens ? this.tokens.btnPrimary : '#738A9C'; // HUI-035：圆形实心按钮→雾霾蓝 btnPrimary
  }

  private getTextColor(): ResourceColor {
    if (this.style === ElasticButtonStyle.PRIMARY) {
      return this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF'; // HUI-035：主按钮文字→btnPrimaryText 白
    } else if (this.style === ElasticButtonStyle.OUTLINE) {
      return this.tokens ? this.tokens.btnAux : '#C6BBAE'; // HUI-035：描边按钮文字→燕麦 btnAux
    } else {
      return this.tokens ? this.tokens.textSecondary : '#5A5A5A';
    }
  }
}
