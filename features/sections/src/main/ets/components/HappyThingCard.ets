// <!-- agentID: HUI-001 -->
// 组件：开心的事卡片（表情符号+文字+图片缩略图+删除）
// 关联设计稿：UX-001_prototype.html（happy-item）
// 关联任务：T015（第2批-组C, HUI部分）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_BODY=清松手写体2（开心事内容正文）；emoji 字符不套手绘。
import { IconMapper, SKETCH_BODY } from '@ohos/shared';

export interface HappyThingData {
  id: number;
  content: string;
  emojiId: string;
  image?: string;
  date: string;
}

@Component
export struct HappyThingCard {
  @ObjectLink item: HappyThingData;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  onDelete?: (id: number) => void;
  onImageClick?: (image: string) => void;

  build() {
    Row() {
      // 表情符号
      Text(this.item.emojiId || '⭐')
        .fontSize(28)
        .flexShrink(0)

      // 文字内容
      Text(this.item.content)
        .fontSize(14)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#333333')
        .layoutWeight(1)
        .margin({ left: 12 })
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .attributeModifier(SKETCH_BODY) // HUI-029：开心事内容→清松手写体2

      // 图片缩略图
      if (this.item.image && this.item.image.length > 0) {
        Image(this.item.image)
          .width(40)
          .height(40)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .margin({ left: 8 })
          .onClick(() => {
            if (this.onImageClick) {
              this.onImageClick(this.item.image!);
            }
          })
          .accessibilityText('查看大图')
      }

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
      .margin({ left: 4 })
      .onClick(() => {
        if (this.onDelete) {
          this.onDelete(this.item.id);
        }
      })
      .accessibilityText('删除这条开心事')
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 16, right: 8 })
    .border({ width: { bottom: 0.5 }, color: this.tokens ? this.tokens.divider : '#F0F0F0' })
    .accessibilityText('开心事：' + this.item.content)
  }
}
