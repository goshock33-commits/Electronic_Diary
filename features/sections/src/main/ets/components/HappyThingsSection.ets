// <!-- agentID: HUI-023 -->
// agentID: HUI-041（T-D05：新增加号按钮统一 — 空心描边圆圈+粗加号）
// 组件：开心的事分区（列表 + 新增入口 + EmojiPicker集成）
// 关联设计稿：UX-001_prototype.html
// 关联任务：F06（PLN-002 阶段3 开心的事UI）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText + 触控热区 >= 48x48vp
// 深色适配：ThemeColorTokens + 硬编码回退色
// Mock：硬编码 3 条开心事

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_TITLE=猫啃什锦黑（分区标题）、SKETCH_BODY=清松手写体2（提示文案）；「X件」计数保留不动，Button('保存') 不动。
import { IconMapper, ICON, EmptyStateView, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';
import { HappyThingItem, type HappyThingItemData } from './HappyThingItem';
import { EmojiPicker } from './EmojiPicker';

let happyThingNextId: number = 600;

function generateHappyThingId(): number {
  happyThingNextId += 1;
  return happyThingNextId;
}

@Component
export struct HappyThingsSection {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  @State items: HappyThingItemData[] = [
    { id: 1, emoji: '😊', content: '今天天气真好，阳光明媚适合散步', date: '2026-07-08' },
    { id: 2, emoji: '🎉', content: '收到了一份意外的礼物，太开心了！', date: '2026-07-08' },
    { id: 3, emoji: '🍜', content: '午餐吃到了最喜欢的牛肉面', date: '2026-07-08' }
  ];

  @State private showEmojiPicker: boolean = false;
  @State private addContent: string = '';
  @State private selectedEmoji: string = '⭐';
  @State private showAddInput: boolean = false;

  onDelete?: (id: number) => void;
  onAdd?: (content: string, emoji: string) => void;

  build() {
    Column() {
      // 分区标题行
      Row() {
        SymbolGlyph(IconMapper.MOOD_HEART)
          .fontSize(18)
          .fontColor([this.tokens ? this.tokens.primary : '#000000']) // HUI-023：死值蓝灰 #90A4AE → 墨色 token
          .margin({ right: 10 })
        Text('开心的事')
          .fontSize(16)
          .fontWeight(600)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#333333')
          .attributeModifier(SKETCH_TITLE) // HUI-029：分区标题→猫啃什锦黑
        Text(' ' + this.items.length + '件')
          .fontSize(13)
          .fontWeight(400)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
        Blank()
        // 新增入口（HUI-041：空心描边圆圈 + 粗加号）
        Button() {
          Stack() {
            SymbolGlyph(IconMapper.PLUS)
              .fontSize(ICON.plus)
              .fontWeight(FontWeight.Bold)
              .fontColor([this.tokens ? this.tokens.btnPrimary : '#738A9C'])
          }
          .width(ICON.plusRing)
          .height(ICON.plusRing)
          .borderRadius(ICON.plusRing / 2)
          .border({
            width: ICON.ringStroke,
            color: this.tokens ? this.tokens.btnPrimary : '#738A9C'
          })
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showAddInput = true;
        })
        .accessibilityText('添加开心的事')
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 4 })

      if (this.items.length > 0 || this.showAddInput) {
        Divider()
          .strokeWidth(0.5)
          .color(this.tokens ? this.tokens.divider : '#F0F0F0')
          .margin({ left: 12, right: 12 })
      }

      // 新增区域
      if (this.showAddInput) {
        Column() {
          // Emoji 选择器触发按钮
          Row() {
            Text(this.selectedEmoji)
              .fontSize(32)
              .onClick(() => {
                this.showEmojiPicker = !this.showEmojiPicker;
              })
              .accessibilityText('当前表情：' + this.selectedEmoji + '，点击更换')

            Text('点击上方表情更换')
              .fontSize(12)
              .fontColor(this.tokens ? this.tokens.textTertiary : '#BBBBBB')
              .margin({ left: 10 })
              .attributeModifier(SKETCH_BODY) // HUI-029：提示文案→清松手写体2
          }
          .margin({ bottom: 10 })

          // Emoji 选择器（展开/折叠）
          if (this.showEmojiPicker) {
            Column() {
              EmojiPicker({
                onSelect: (emoji: string) => {
                  this.selectedEmoji = emoji;
                  this.showEmojiPicker = false;
                }
              })
            }
            .width('100%')
            .margin({ bottom: 10 })
            .animation({ duration: 250, curve: Curve.EaseInOut })
          }

          // 内容输入框
          Row() {
            TextInput({ text: this.addContent, placeholder: '记录今天开心的事...' })
              .fontSize(14)
              .layoutWeight(1)
              .height(42)
              .backgroundColor(this.tokens ? this.tokens.border : '#F0F0F0')
              .borderRadius(10)
              .padding({ left: 12, right: 12 })
              .placeholderColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
              .onChange((value: string) => {
                this.addContent = value;
              })
              .onSubmit(() => {
                this.commitAdd();
              })

            Button('保存')
              .fontSize(13)
              .fontWeight(500)
              .fontColor(this.addContent.trim().length > 0 ?
                (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF') :
                (this.tokens ? this.tokens.textTertiary : '#BDBDBD'))
              .backgroundColor(this.addContent.trim().length > 0 ?
                (this.tokens ? this.tokens.btnPrimary : '#738A9C') :
                (this.tokens ? this.tokens.border : '#E0E0E0')) // HUI-035：保存主按钮→雾霾蓝 btnPrimary（禁用留灰）
              .borderRadius(10)
              .height(42)
              .padding({ left: 16, right: 16 })
              .margin({ left: 8 })
              .onClick(() => {
                this.commitAdd();
              })
              .accessibilityText('保存开心事')

            Button() {
              SymbolGlyph(IconMapper.CLOSE)
                .fontSize(14)
                .fontColor([this.tokens ? this.tokens.textTertiary : '#BBBBBB'])
            }
            .width(36)
            .height(36)
            .backgroundColor(Color.Transparent)
            .margin({ left: 4 })
            .onClick(() => {
              this.showAddInput = false;
              this.addContent = '';
              this.showEmojiPicker = false;
            })
            .accessibilityText('取消添加')
          }
          .width('100%')
          .padding({ left: 0, right: 4 })
        }
        .width('100%')
        .padding({ left: 16, right: 12, top: 10, bottom: 14 })
      }

      // 列表项
      if (this.items.length > 0) {
        Column() {
          ForEach(this.items, (item: HappyThingItemData, index: number) => {
            Column() {
              HappyThingItem({
                itemId: item.id,
                emoji: item.emoji,
                content: item.content,
                onDelete: (itemId: number) => {
                  this.handleDelete(itemId);
                }
              })
            }
            .transition(
              TransitionEffect.OPACITY
                .animation({ duration: 300, curve: Curve.EaseOut })
                .combine(TransitionEffect.translate({ y: -20 })
                  .animation({ duration: 300, curve: Curve.EaseOut }))
            )
          }, (item: HappyThingItemData) => item.id.toString())
        }
        .width('100%')
      } else {
        Column() {
          EmptyStateView({
            icon: IconMapper.MOOD_HEART,
            title: '今天还没有开心的事',
            description: '点击上方加号记录一件开心的事吧',
            showAction: true,
            actionText: '记录开心事',
            onAction: () => {
              this.showAddInput = true;
            }
          })
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  private handleDelete(id: number): void {
    animateTo({ duration: 300, curve: Curve.EaseIn }, () => {
      this.items = this.items.filter((item: HappyThingItemData) => item.id !== id);
    });
    if (this.onDelete) {
      this.onDelete(id);
    }
  }

  private commitAdd(): void {
    if (this.addContent.trim().length === 0) {
      return;
    }
    const newItem: HappyThingItemData = {
      id: generateHappyThingId(),
      emoji: this.selectedEmoji,
      content: this.addContent.trim(),
      date: '2026-07-08'
    };
    animateTo({ duration: 350, curve: Curve.EaseOut }, () => {
      this.items = [newItem, ...this.items];
    });
    this.addContent = '';
    this.selectedEmoji = '⭐';
    this.showEmojiPicker = false;
    this.showAddInput = false;
    if (this.onAdd) {
      this.onAdd(newItem.content, newItem.emoji);
    }
  }
}
