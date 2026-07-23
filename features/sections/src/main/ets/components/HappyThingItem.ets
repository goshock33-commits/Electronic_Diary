// <!-- agentID: HUI-023 -->
// 组件：开心事物项（Emoji表情+文字+左滑删除）
// 关联设计稿：UX-001_prototype.html（happy-item）
// 关联任务：F06（PLN-002 阶段3 开心的事UI）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText + 触控热区 >= 48x48vp
// 深色适配：ThemeColorTokens + 硬编码回退色
// 注意：Emoji 仅用于内容展示（开心事表情），UI图标使用 SymbolGlyph

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_BODY=清松手写体2（开心事内容正文）；emoji 字符不套手绘。
import { IconMapper, SKETCH_BODY } from '@ohos/shared';

export interface HappyThingItemData {
  id: number;
  emoji: string;
  content: string;
  date: string;
}

@Component
export struct HappyThingItem {
  @Prop emoji: string = '⭐';
  @Prop content: string = '';
  @Prop itemId: number = 0;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  @State private offsetX: number = 0;
  @State private showDelete: boolean = false;

  onDelete?: (itemId: number) => void;

  build() {
    Stack({ alignContent: Alignment.End }) {
      // 左滑露出的红色删除背景
      if (this.showDelete) {
        Row() {
          Blank()
          Button() {
            SymbolGlyph(IconMapper.DELETE)
              .fontSize(20)
              .fontColor([Color.White])
          }
          .width(72)
          .height('100%')
          .backgroundColor('#666666') // HUI-023：死值蓝灰 #78909C → 手绘深灰（配白色删除图标，浅深两色主题均可见）
          .borderRadius(0)
          .onClick(() => {
            this.handleDelete();
          })
          .accessibilityText('删除开心事：' + this.content)
        }
        .width('100%')
        .height('100%')
      }

      // 内容主体（带左滑手势）
      Row() {
        // Emoji 大号显示
        Text(this.emoji)
          .fontSize(32)
          .flexShrink(0)

        // 文字内容
        Text(this.content)
          .fontSize(15)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#333333')
          .layoutWeight(1)
          .margin({ left: 14 })
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .accessibilityLevel('no')
          .attributeModifier(SKETCH_BODY) // HUI-029：开心事内容→清松手写体2
      }
      .width('100%')
      .padding({ top: 12, bottom: 12, left: 16, right: 16 })
      .backgroundColor(this.tokens ? this.tokens.bgCard : '#FAFAFA')
      .offset({ x: this.offsetX })
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
          .onActionUpdate((event: GestureEvent) => {
            if (event.offsetX < 0) {
              this.offsetX = Math.max(event.offsetX, -72);
              this.showDelete = this.offsetX < -30;
            }
          })
          .onActionEnd(() => {
            if (this.offsetX < -40) {
              this.offsetX = -72;
              this.showDelete = true;
            } else {
              this.offsetX = 0;
              this.showDelete = false;
            }
          })
      )
      .animation({ duration: 250, curve: Curve.EaseOut })
      .accessibilityGroup(true)
      .accessibilityText('开心事：' + this.emoji + ' ' + this.content)
    }
    .width('100%')
    .border({
      width: { bottom: 0.5 },
      color: this.tokens ? this.tokens.divider : '#F0F0F0'
    })
  }

  private handleDelete(): void {
    this.offsetX = 0;
    this.showDelete = false;
    if (this.onDelete) {
      this.onDelete(this.itemId);
    }
  }
}
