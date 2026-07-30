// <!-- agentID: HUI-069 -->
// @Entry 家庭通知页「壳」（返回按钮 + eyebrow + H1 + features_family FamilyNotificationPage）
// 壳页模式复刻 PomodoroPage：返回按钮 + eyebrow + H1 + feature 内容主体
// §1.4 三者一致：模块 name = features_family = 依赖 key = import 路径
// §9.4：@StorageLink tokens 读取全部判空兜底（HarmonyOS 蓝白卡片风格中性兜底）
// 主题：HarmonyOS 蓝白卡片风格（primary=#0A59F7, bg=#F5F7FA, bgCard=#FFFFFF）
// 令牌：IconMapper / SPACING / TYPO / ICON —— 全引用，禁散写魔数

import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper, SPACING, TYPO, ICON, SKETCH_TITLE, reportPawTouch } from '@ohos/shared';
import { FamilyNotificationPage } from 'features_family';
import { router } from '@kit.ArkUI';

@Entry
@Component
struct FamilyNotificationPageEntry {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // ── 顶部：返回按钮 ──
        Row() {
          Button() {
            SymbolGlyph(IconMapper.ARROW_BACK)
              .fontSize(ICON.navBack)
              .fontWeight(FontWeight.Bold)
              .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
          }
          .width(48)
          .height(48)
          .borderRadius(24)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            router.back();
          })
          .accessibilityText('返回')
        }
        .width('100%')
        .height(48)
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 12 })

        // ── Eyebrow：NOTIFICATIONS ──
        Row() {
          SymbolGlyph(IconMapper.BELL)
            .fontSize(14)
            .fontColor([this.tokens ? this.tokens.primary : '#0A59F7'])
            .margin({ right: 6 })
          Text('NOTIFICATIONS')
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(TYPO.eyebrow.weight)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .opacity(0.6)
            .letterSpacing(3)
            .attributeModifier(SKETCH_TITLE)
        }

        // ── H1：家庭通知 ──
        Text('家庭通知')
          .fontSize(TYPO.h1.size)
          .fontWeight(TYPO.h1.weight)
          .fontColor(this.tokens ? this.tokens.primary : '#0A59F7')
          .width('100%')
          .margin({ top: 4, bottom: SPACING.sectionGap })
          .attributeModifier(SKETCH_TITLE)

        // ── 内容主体 ──
        FamilyNotificationPage()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({
        left: SPACING.pageH,
        right: SPACING.pageH,
        top: SPACING.pageTop
      })
      .backgroundColor(this.tokens ? this.tokens.bg : '#F5F7FA')
      .accessibilityGroup(true)
      .accessibilityText('家庭通知页面')
      .onTouch((event: TouchEvent) => reportPawTouch(event))
    }
    .width('100%')
    .height('100%')
  }
}
