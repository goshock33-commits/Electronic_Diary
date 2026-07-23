// <!-- agentID: HUI-001 -->
// 组件：加载中状态组件
// 关联设计稿：UX-001_prototype.html（spinner / skeleton 骨架屏）
// 关联任务：T009（第1批）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：遵守 T042 规范

import type { ThemeColorTokens } from '../theme/ThemeConfig';
import { IconMapper } from '../utils/IconMapper';
import { RADIUS } from '../theme/LayoutTokens';
// HUI-028：shared 组件不能 import @ohos/shared 自身，改用相对路径引手绘正文字体 modifier（SKETCH_BODY=清松手写体2）。
import { SKETCH_BODY } from '../theme/SketchTextModifiers';

/**
 * 加载状态样式
 */
export enum LoadingStyle {
  /** 旋转指示器 */
  SPINNER = 'spinner',
  /** 骨架屏卡片 */
  SKELETON_CARD = 'skeleton_card',
  /** 骨架屏文字行 */
  SKELETON_TEXT = 'skeleton_text',
  /** 骨架屏圆形 */
  SKELETON_CIRCLE = 'skeleton_circle'
}

@Component
export struct LoadingView {
  @Prop message: string = '加载中...';
  @Prop style: LoadingStyle = LoadingStyle.SPINNER;
  @Prop viewWidth: number = 0;
  @Prop viewHeight: number = 14;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  build() {
    if (this.style === LoadingStyle.SPINNER) {
      this.buildSpinner();
    } else if (this.style === LoadingStyle.SKELETON_CARD) {
      this.buildSkeletonCard();
    } else if (this.style === LoadingStyle.SKELETON_TEXT) {
      this.buildSkeletonText();
    } else if (this.style === LoadingStyle.SKELETON_CIRCLE) {
      this.buildSkeletonCircle();
    }
  }

  @Builder
  buildSpinner() {
    Column() {
      // 旋转指示器
      LoadingProgress()
        .width(32)
        .height(32)
        .color(this.tokens ? this.tokens.primary : '#00C2B8')

      Text(this.message)
        .fontSize(14)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
        .margin({ top: 16 })
        .accessibilityText(this.message)
        .attributeModifier(SKETCH_BODY) // HUI-028：加载提示→清松手写体2
    }
    .width('100%')
    .height(120)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildSkeletonCard() {
    Column()
      .width(this.viewWidth > 0 ? this.viewWidth : '100%')
      .height(80)
      .borderRadius(RADIUS.input)
      .linearGradient({
        angle: 90,
        colors: [
          [this.tokens ? this.tokens.border : '#E8E8E8', 0.0],
          [this.tokens ? this.tokens.accent : '#F5F5F5', 0.5],
          [this.tokens ? this.tokens.border : '#E8E8E8', 1.0]
        ]
      })
  }

  @Builder
  buildSkeletonText() {
    Column()
      .width(this.viewWidth > 0 ? this.viewWidth : '100%')
      .height(this.viewHeight)
      .borderRadius(4)
      .linearGradient({
        angle: 90,
        colors: [
          [this.tokens ? this.tokens.border : '#E8E8E8', 0.0],
          [this.tokens ? this.tokens.accent : '#F5F5F5', 0.5],
          [this.tokens ? this.tokens.border : '#E8E8E8', 1.0]
        ]
      })
  }

  @Builder
  buildSkeletonCircle() {
    Column()
      .width(this.viewWidth > 0 ? this.viewWidth : 48)
      .height(this.viewWidth > 0 ? this.viewWidth : 48)
      .borderRadius(this.viewWidth > 0 ? this.viewWidth / 2 : 24)
      .linearGradient({
        angle: 90,
        colors: [
          [this.tokens ? this.tokens.border : '#E8E8E8', 0.0],
          [this.tokens ? this.tokens.accent : '#F5F5F5', 0.5],
          [this.tokens ? this.tokens.border : '#E8E8E8', 1.0]
        ]
      })
  }
}
