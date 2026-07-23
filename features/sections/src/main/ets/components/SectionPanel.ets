// <!-- agentID: HUI-023 -->
// 组件：通用分区容器（标题可自定义+折叠展开箭头动画+内容区+长按拖拽排序手柄）
// 关联设计稿：UX-001_prototype.html（section-container）
// 关联任务：F05（PLN-002 阶段3 五个分区UI）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText + 触控热区 >= 48x48vp
// 深色适配：ThemeColorTokens + 硬编码回退色

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_TITLE=猫啃什锦黑（分区标题）、SKETCH_BODY=清松手写体2（占位内容正文）。
import { IconMapper, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';

@Component
export struct SectionPanel {
  @Prop title: string = '分区';
  @Prop icon: Resource | null = null;
  @Prop iconColor: string = '#738A9C'; // HUI-035：区块图标兜底色同步雾霾蓝 btnPrimary
  @Prop isCollapsed: boolean = false;
  @Prop showManage: boolean = false;
  @Prop showDragHandle: boolean = false;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  @BuilderParam content: () => void = this.defaultContent;
  onToggleCollapse?: () => void;
  onManage?: () => void;
  onPanelDragStart?: () => void;
  onPanelDragEnd?: () => void;

  @State private dragHandleScale: number = 1;
  @State private collapseArrowRotation: number = 0;

  aboutToAppear(): void {
    this.collapseArrowRotation = this.isCollapsed ? -90 : 0;
  }

  @Builder
  defaultContent() {
    Text('分区内容占位')
      .fontSize(14)
      .fontColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
      .width('100%')
      .padding(16)
      .textAlign(TextAlign.Center)
      .attributeModifier(SKETCH_BODY) // HUI-029：占位内容→清松手写体2
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        // 拖拽排序手柄（SectionManager 模式展示）
        if (this.showDragHandle) {
          Column() {
            SymbolGlyph(IconMapper.DRAG_HANDLE)
              .fontSize(18)
              .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .scale({ x: this.dragHandleScale, y: this.dragHandleScale })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .gesture(
            LongPressGesture({ repeat: false, duration: 300 })
              .onAction(() => {
                this.dragHandleScale = 1.2;
                if (this.onPanelDragStart) {
                  this.onPanelDragStart();
                }
              })
          )
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.dragHandleScale = 1.0;
              if (this.onPanelDragEnd) {
                this.onPanelDragEnd();
              }
            }
          })
          .animation({ duration: 150, curve: Curve.EaseInOut })
          .accessibilityText('长按拖拽排序' + this.title)
          .accessibilityLevel('yes')
        }

        // 分区图标
        SymbolGlyph(this.icon ?? IconMapper.EMPTY)
          .fontSize(18)
          .fontColor([this.iconColor])
          .margin({ left: this.showDragHandle ? 8 : 0, right: 10 })
          .accessibilityLevel('no')

        // 分区标题
        Text(this.title)
          .fontSize(16)
          .fontWeight(600)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#333333')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .accessibilityLevel('no')
          .attributeModifier(SKETCH_TITLE) // HUI-029：分区标题→猫啃什锦黑

        // 管理按钮（齿轮）
        if (this.showManage) {
          Button() {
            SymbolGlyph(IconMapper.SECTION_MANAGE)
              .fontSize(16)
              .fontColor([this.tokens ? this.tokens.textSecondary : '#999999'])
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(this.tokens ? this.tokens.btnAux : '#C6BBAE') // HUI-035：管理齿轮辅助钮→燕麦 btnAux
          .type(ButtonType.Circle)
          .margin({ right: 8 })
          .onClick(() => {
            if (this.onManage) {
              this.onManage();
            }
          })
          .accessibilityText('管理' + this.title)
          .accessibilityLevel('yes')
        }

        // 折叠/展开箭头（带动画）
        Button() {
          SymbolGlyph(IconMapper.EXPAND)
            .fontSize(14)
            .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
            .rotate({ angle: this.collapseArrowRotation })
            .animation({ duration: 200, curve: Curve.EaseInOut })
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(Color.Transparent)
        .type(ButtonType.Circle)
        .onClick(() => {
          this.collapseArrowRotation = this.isCollapsed ? 0 : -90;
          if (this.onToggleCollapse) {
            this.onToggleCollapse();
          }
        })
        .accessibilityText(this.isCollapsed ? '展开' + this.title : '折叠' + this.title)
        .accessibilityLevel('yes')
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 4 })

      // 内容区（带折叠过渡动画）
      if (!this.isCollapsed) {
        Column() {
          this.content()
        }
        .width('100%')
        .padding({ left: 0, right: 0, bottom: 8 })
        .transition(
          TransitionEffect.OPACITY
            .animation({ duration: 200, curve: Curve.EaseInOut })
            .combine(TransitionEffect.scale({ y: 0.95 })
              .animation({ duration: 200, curve: Curve.EaseInOut }))
        )
      }
    }
    .width('100%')
    .borderRadius(14)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FAFAFA')
    .border({ width: 1, color: this.tokens ? this.tokens.border : '#E0E0E0' })
    .margin({ bottom: 14 })
    .accessibilityGroup(true)
    .accessibilityText(this.title + (this.isCollapsed ? '已折叠' : '已展开'))
  }
}
