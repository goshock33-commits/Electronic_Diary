// <!-- agentID: HUI-001 -->
// 组件：多做的事卡片（文字内容+删除+快速新增）
// 关联设计稿：UX-001_prototype.html
// 关联任务：T015（第2批-组C, HUI部分）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_BODY=清松手写体2（多做的事内容正文）。
import { IconMapper, SKETCH_BODY } from '@ohos/shared';

export interface ExtraThingData {
  id: number;
  content: string;
  date: string;
}

@Component
export struct ExtraThingCard {
  @ObjectLink item: ExtraThingData;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  onDelete?: (id: number) => void;

  build() {
    Row() {
      // Bullet 圆点标记
      Circle({ width: 6, height: 6 })
        .fill(this.tokens ? this.tokens.textTertiary : '#CCCCCC')
        .flexShrink(0)

      // 文字内容
      Text(this.item.content)
        .fontSize(14)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#333333')
        .layoutWeight(1)
        .margin({ left: 12 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .attributeModifier(SKETCH_BODY) // HUI-029：多做的事内容→清松手写体2

      // 删除按钮
      Button() {
        SymbolGlyph(IconMapper.DELETE)
          .fontSize(14)
          .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(Color.Transparent)
      .type(ButtonType.Circle)
      .onClick(() => {
        if (this.onDelete) {
          this.onDelete(this.item.id);
        }
      })
      .accessibilityText('删除')
    }
    .width('100%')
    .padding({ top: 8, bottom: 8, left: 16, right: 8 })
    .border({ width: { bottom: 0.5 }, color: this.tokens ? this.tokens.divider : '#F0F0F0' })
    .accessibilityText(this.item.content)
  }
}
