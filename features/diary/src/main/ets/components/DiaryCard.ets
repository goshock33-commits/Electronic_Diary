// <!-- agentID: HUI-055 -->
// 组件：日记卡片（mood 图标 + 日期 + 内容预览）—— 复刻原型日记查看器/结果卡（薄荷青 bento）
// 关联设计稿：UX-001_redesign_report.md §2.4 选中日日记查看器 / §2.6 结果卡 / §3.1 5 心情
// 关联计划：PLN-003 P2-02（日历下钻查看器）/ P2-04（检索结果卡复用）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 复刻要点：RADIUS.cardMd bento + tokens.shadow 青染；左上 mood 图标（5 心情 SymbolGlyph + 青浅底 RADIUS.input）；
//           日期 mono + 已签到青药丸；内容预览；底部图片数 + 查看详情。
// 令牌驱动：RADIUS / SPACING / TYPO / FONT 全引用；心情语义色（晴 amber/星 yellow/心 rose/云 slate/雨 blue）
//           无对应 token，按 UX-001 §3.1 硬编码。
// 崩溃防范（PROJECT_SPEC §9）：无 getter-in-build；无字段初值写 $r()（图标由方法返回 IconMapper 常量）；判空。
// 图标合规（PROJECT_SPEC §10）：仅用 IconMapper 已验证 sys.symbol.*；无 emoji。

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-027：引入手绘正文字体助手 SKETCH_BODY=清松手写体2(mood 标签/正文/动作字)；日期 mono、图片计数保留不动。
import { DateUtils, IconMapper, RADIUS, SPACING, TYPO, FONT, SKETCH_BODY } from '@ohos/shared';

/**
 * 日记卡片数据
 * mood：心情键（'happy'|'star'|'heart'|'cloudy'|'rainy'），空/未知 → 兜底平静。
 */
export interface DiaryCardData {
  id: number;
  date: string;
  content: string;
  imageCount: number;
  isCheckedIn: boolean;
  mood: string;
}

@Component
export struct DiaryCard {
  @Prop diary: DiaryCardData | null = null;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  onCardClick?: (diary: DiaryCardData) => void;

  build() {
    if (this.diary) {
      Column() {
        // ═══════════════════════════════════════════
        // 顶部：mood 图标徽标 + 日期(mono) + 已签到青药丸
        // ═══════════════════════════════════════════
        Row() {
          // mood 图标徽标（5 心情 SymbolGlyph + 青浅底 RADIUS.input）
          Stack() {
            SymbolGlyph(this.getMoodIcon(this.diary!.mood))
              .fontSize(22)
              .fontColor([this.getMoodColor(this.diary!.mood)])
          }
          .width(44)
          .height(44)
          .borderRadius(RADIUS.input)
          .backgroundColor(this.tokens ? this.tokens.accent : '#E6F9F8')

          Column() {
            // mood 文案 eyebrow
            Text(this.getMoodLabel(this.diary!.mood))
              .fontSize(TYPO.eyebrow.size)
              .fontWeight(TYPO.eyebrow.weight)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
              .attributeModifier(SKETCH_BODY) // HUI-027：心情中文文案→清松手写体2
            // 日期（mono 数字）
            Text(DateUtils.formatShortCN(this.diary!.date))
              .fontFamily(FONT.monoBold)
              .fontSize(TYPO.cardTitle.size)
              .fontWeight(TYPO.cardTitle.weight)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: SPACING.cardPadSm })

          Blank()

          if (this.diary!.isCheckedIn) {
            Row() {
              SymbolGlyph(IconMapper.CHECKIN_DONE)
                .fontSize(13)
                .fontColor([Color.White])
              Text('已签到')
                .fontSize(TYPO.eyebrow.size)
                .fontWeight(TYPO.cardTitle.weight)
                .fontColor(Color.White)
                .margin({ left: 4 })
                .attributeModifier(SKETCH_BODY) // HUI-027：签到药丸中文标签→清松手写体2
            }
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(999)
            .backgroundColor(this.tokens ? this.tokens.primary : '#00C2B8')
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ bottom: SPACING.cardPadSm })

        // ═══════════════════════════════════════════
        // 正文预览
        // ═══════════════════════════════════════════
        Text(this.getContentPreview())
          .fontSize(TYPO.body.size)
          .fontWeight(TYPO.body.weight)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
          .lineHeight(23)
          .width('100%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ bottom: SPACING.cardPadSm })
          .attributeModifier(SKETCH_BODY) // HUI-027：正文预览(中文)→清松手写体2

        // ═══════════════════════════════════════════
        // 底部：图片数 + 查看详情
        // ═══════════════════════════════════════════
        Row() {
          if (this.diary!.imageCount > 0) {
            Row() {
              SymbolGlyph(IconMapper.CAMERA)
                .fontSize(14)
                .fontColor([this.tokens ? this.tokens.textTertiary : '#BDBDBD'])
              Text(this.diary!.imageCount.toString() + ' 张图片')
                .fontSize(TYPO.eyebrow.size)
                .fontWeight(TYPO.eyebrow.weight)
                .fontColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
                .margin({ left: 4 })
            }
          }

          Blank()

          Row() {
            Text('查看详情')
              .fontSize(TYPO.eyebrow.size)
              .fontWeight(TYPO.cardTitle.weight)
              .fontColor(this.tokens ? this.tokens.primary : '#00C2B8')
              .attributeModifier(SKETCH_BODY) // HUI-027：查看详情动作字→清松手写体2
            SymbolGlyph(IconMapper.FORWARD)
              .fontSize(13)
              .fontColor([this.tokens ? this.tokens.primary : '#00C2B8'])
              .margin({ left: 2 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding(SPACING.cardPadMd)
      .borderRadius(RADIUS.cardMd)
      .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
      .shadow({
        radius: 20,
        color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
        offsetX: 0,
        offsetY: 6
      })
      .onClick(() => {
        if (this.onCardClick && this.diary) {
          this.onCardClick(this.diary!);
        }
      })
      .accessibilityText(
        DateUtils.formatShortCN(this.diary!.date) +
        ' ' + this.getMoodLabel(this.diary!.mood) +
        ' 日记卡片，内容摘要：' + this.getContentPreview()
      )
      .accessibilityLevel('yes')
    }
  }

  /**
   * 内容预览（截取前 60 字）
   */
  private getContentPreview(): string {
    if (!this.diary) {
      return '';
    }
    const content = this.diary.content;
    if (content.length > 60) {
      return content.substring(0, 60) + '...';
    }
    return content;
  }

  /**
   * mood 键 → 5 心情 SymbolGlyph 图标（UX-001 §3.1）
   */
  private getMoodIcon(mood: string): Resource {
    if (mood === 'happy') {
      return IconMapper.MOOD_HAPPY;
    }
    if (mood === 'star') {
      return IconMapper.MOOD_PLEASANT;
    }
    if (mood === 'heart') {
      return IconMapper.MOOD_HEART;
    }
    if (mood === 'cloudy') {
      return IconMapper.MOOD_CLOUDY;
    }
    if (mood === 'rainy') {
      return IconMapper.MOOD_RAINY;
    }
    return IconMapper.MOOD_NEUTRAL;
  }

  /**
   * mood 键 → 语义色（晴 amber / 星 yellow / 心 rose / 云 slate / 雨 blue / 兜底 primary）
   */
  private getMoodColor(mood: string): ResourceColor {
    if (mood === 'happy') {
      return '#E0BE72';
    }
    if (mood === 'star') {
      return '#E6D98A';
    }
    if (mood === 'heart') {
      return '#78909C';
    }
    if (mood === 'cloudy') {
      return '#94A3B8';
    }
    if (mood === 'rainy') {
      return '#4FC3F7';
    }
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  /**
   * mood 键 → 中文文案（eyebrow / 无障碍）
   */
  private getMoodLabel(mood: string): string {
    if (mood === 'happy') {
      return '风和日丽';
    }
    if (mood === 'star') {
      return '繁星点点';
    }
    if (mood === 'heart') {
      return '心生欢喜';
    }
    if (mood === 'cloudy') {
      return '云淡风轻';
    }
    if (mood === 'rainy') {
      return '微雨清凉';
    }
    return '平平淡淡';
  }
}
