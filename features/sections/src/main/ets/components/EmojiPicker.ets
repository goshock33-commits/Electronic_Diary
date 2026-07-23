// <!-- agentID: HUI-023 -->
// 组件：Emoji 选择器（5分类Tab + 网格选择 + 点击回传）
// 关联设计稿：UX-001_prototype.html
// 关联任务：F06（PLN-002 阶段3 开心的事UI）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText + 触控热区 >= 48x48vp
// 深色适配：ThemeColorTokens + 硬编码回退色
// 分类：心情/活动/食物/动物/自然

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：引入手绘正文字体助手 SKETCH_BODY=清松手写体2（分类 Tab 中文标签）；emoji 字符不套手绘。
import { SKETCH_BODY } from '@ohos/shared';

/**
 * Emoji 分类定义
 */
interface EmojiCategory {
  key: string;
  title: string;
  emojis: string[];
}

/**
 * 5 大 Emoji 分类数据
 */
const EMOJI_CATEGORIES: EmojiCategory[] = [
  {
    key: 'mood',
    title: '心情',
    emojis: [
      '😊', '😄', '🥳', '😍', '😎',
      '🤩', '😇', '🥰', '😌', '🤗',
      '😆', '😂', '🤣', '😁', '🙂',
      '😉', '😋', '😜', '😝', '🫠'
    ]
  },
  {
    key: 'activity',
    title: '活动',
    emojis: [
      '🎉', '🎊', '🎂', '🎈', '🎀',
      '🎁', '🏆', '🥇', '🌟', '⭐',
      '💪', '🎯', '🏃', '🚴', '🏊',
      '📚', '✏️', '🎨', '🎵', '🎬'
    ]
  },
  {
    key: 'food',
    title: '食物',
    emojis: [
      '🍕', '🍔', '🍜', '🍰', '🍩',
      '🍓', '🍉', '🍫', '🍿', '🧋',
      '☕', '🍵', '🥤', '🍦', '🍪',
      '🥗', '🍱', '🍣', '🥩', '🧁'
    ]
  },
  {
    key: 'animal',
    title: '动物',
    emojis: [
      '🐶', '🐱', '🐰', '🐼', '🐨',
      '🐸', '🦊', '🐯', '🐮', '🐷',
      '🐤', '🦄', '🐝', '🦋', '🐙',
      '🐳', '🐬', '🦜', '🐿️', '🦦'
    ]
  },
  {
    key: 'nature',
    title: '自然',
    emojis: [
      '🌸', '🌺', '🌻', '🌹', '🌷',
      '🌈', '☀️', '🌙', '⭐', '🔥',
      '🌊', '⛰️', '🌲', '🍀', '🌿',
      '🍂', '❄️', '☁️', '🌍', '💧'
    ]
  }
];

@Component
export struct EmojiPicker {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  /** 当前选中的分类索引 */
  @State private activeCategoryIndex: number = 0;
  /** 当前选中分类 */
  private currentCategory: EmojiCategory = EMOJI_CATEGORIES[0];

  onSelect?: (emoji: string) => void;

  /** HUI-040：半透明版本：ArkUI hex-alpha 为 #AARRGGBB，需前置 alpha（修复 alpha 后拼致选中底发脏 bug） */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  build() {
    Column() {
      // 分类 Tab 栏
      Row() {
        ForEach(EMOJI_CATEGORIES, (category: EmojiCategory, idx: number) => {
          Column() {
            Text(category.title)
              .fontSize(13)
              .fontWeight(this.activeCategoryIndex === idx ? 600 : 400)
              .fontColor(
                this.activeCategoryIndex === idx ?
                  (this.tokens ? this.tokens.btnPrimary : '#738A9C') :
                  (this.tokens ? this.tokens.textSecondary : '#999999')
              )
              .attributeModifier(SKETCH_BODY) // HUI-029：分类中文标签→清松手写体2
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor(
            this.activeCategoryIndex === idx ?
              // HUI-040：alpha 后拼 → withAlpha 前置（#AARRGGBB），fallback 同步改前置
              (this.tokens ? this.withAlpha(this.tokens.btnPrimary, '1A') : '#1A738A9C') :
              '#FFFFFF'
          ) // HUI-035：分类分段选中→雾霾蓝 btnPrimary tint / 未选→白
          .onClick(() => {
            this.activeCategoryIndex = idx;
            this.currentCategory = EMOJI_CATEGORIES[idx];
          })
          .margin({ right: idx < EMOJI_CATEGORIES.length - 1 ? 4 : 0 })
          .accessibilityText(category.title + '分类，共' + category.emojis.length + '个表情')
          .accessibilityLevel('yes')
        }, (category: EmojiCategory) => category.key)
      }
      .width('100%')
      .padding({ left: 4, right: 4, top: 4, bottom: 8 })

      // 分割线
      Divider()
        .strokeWidth(0.5)
        .color(this.tokens ? this.tokens.divider : '#F0F0F0')

      // Emoji 网格
      Grid() {
        ForEach(EMOJI_CATEGORIES[this.activeCategoryIndex].emojis, (emoji: string, idx: number) => {
          GridItem() {
            Button() {
              Text(emoji)
                .fontSize(28)
            }
            .width(52)
            .height(52)
            .borderRadius(12)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              if (this.onSelect) {
                this.onSelect(emoji);
              }
            })
            .backgroundBlurStyle(BlurStyle.NONE)
            .hoverEffect(HoverEffect.Scale)
            .accessibilityText('选择表情：' + emoji)
            .accessibilityLevel('yes')
          }
        }, (emoji: string, idx: number) => emoji + '_' + idx.toString())
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
      .rowsGap(4)
      .columnsGap(4)
      .width('100%')
      .height(200)
      .padding({ top: 10, left: 4, right: 4, bottom: 4 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .borderRadius(14)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .border({
      width: 1,
      color: this.tokens ? this.tokens.border : '#E0E0E0'
    })
    .accessibilityGroup(true)
    .accessibilityText('表情选择器，当前分类：' + EMOJI_CATEGORIES[this.activeCategoryIndex].title)
  }
}
