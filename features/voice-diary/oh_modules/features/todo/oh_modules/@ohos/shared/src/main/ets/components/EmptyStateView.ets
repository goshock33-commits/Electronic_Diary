// <!-- agentID: HUI-001 -->
// 组件：空数据占位状态组件
// 关联设计稿：UX-001_prototype.html（empty-state）
// 关联任务：T009（第1批）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：遵守 T042 规范

import type { ThemeColorTokens } from '../theme/ThemeConfig';
import { IconMapper } from '../utils/IconMapper';
// HUI-028：shared 组件不能 import @ohos/shared 自身，改用相对路径引手绘正文字体 modifier（SKETCH_BODY=清松手写体2）。
import { SKETCH_BODY } from '../theme/SketchTextModifiers';
import { LottieAnimation } from './LottieAnimation';

@Component
export struct EmptyStateView {
  @Prop icon: Resource | null = null;
  /** 可选 Lottie 动画路径（设置后替代 icon 渲染） */
  @Prop animPath: string = '';
  @Prop title: string = '暂无数据';
  @Prop description: string = '';
  @Prop showAction: boolean = false;
  @Prop actionText: string = '去添加';
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  onAction?: () => void;

  build() {
    Column() {
      // 图标：有 animPath 则渲染 Lottie，否则 SymbolGlyph
      if (this.animPath.length > 0) {
        LottieAnimation({
          animPath: this.animPath,
          loop: true,
          autoPlay: true,
          animWidth: 160,
          animHeight: 160,
          frameRate: 12,
          shouldPlay: true
        })
          .width(160)
          .height(160)
          .accessibilityLevel('no')
      } else {
        SymbolGlyph(this.icon ?? IconMapper.EMPTY)
          .fontSize(48)
          .fontColor([this.tokens ? this.tokens.textTertiary : '#BDBDBD'])
          .opacity(0.4)
          .accessibilityLevel('no')
      }

      // 标题
      Text(this.title)
        .fontSize(16)
        .fontWeight(500)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
        .margin({ top: 16 })
        .accessibilityText(this.title)
        .attributeModifier(SKETCH_BODY) // HUI-028：空态标题→清松手写体2

      // 描述
      if (this.description.length > 0) {
        Text(this.description)
          .fontSize(14)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .margin({ top: 8 })
          .textAlign(TextAlign.Center)
          .maxLines(3)
          .accessibilityText(this.description)
          .attributeModifier(SKETCH_BODY) // HUI-028：空态说明→清松手写体2
      }

      // 操作按钮
      if (this.showAction) {
        Button(this.actionText)
          .fontSize(14)
          .fontWeight(500)
          .fontColor(this.tokens ? this.tokens.btnAux : '#C6BBAE') // HUI-035：辅助按钮文字→燕麦 btnAux
          .backgroundColor(Color.Transparent)
          .border({ width: 1.5, color: this.tokens ? this.tokens.btnAux : '#C6BBAE' }) // HUI-035：辅助按钮描边→燕麦 btnAux
          .borderRadius(22)
          .height(44)
          .padding({ left: 24, right: 24 })
          .margin({ top: 24 })
          .onClick(() => {
            if (this.onAction) {
              this.onAction();
            }
          })
          .accessibilityText(this.actionText)
      }
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .accessibilityGroup(true)
  }
}
