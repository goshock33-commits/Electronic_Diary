// @Entry 家庭成员详情页壳（返回按钮 + 内容主体）
// 主题：HarmonyOS 蓝白卡片风格
// 令牌：IconMapper / SPACING / TYPO / ICON 全引用

import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper, SPACING, TYPO, ICON } from '@ohos/shared';
import { FamilyMemberDetailPage } from 'features_family';
import { router } from '@kit.ArkUI';

@Entry
@Component
struct FamilyMemberDetailPageEntry {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // ── 顶部导航栏 ──
        Row() {
          Button() {
            SymbolGlyph(IconMapper.BACK)
              .fontSize(ICON.navBack)
              .fontWeight(FontWeight.Bold)
              .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(Color.Transparent)
          .onClick(() => router.back())
          .accessibilityText('返回')

          Blank()

          Text('家人详情')
            .fontSize(TYPO.cardTitle.size)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')

          Blank()

          // 右侧占位（与返回按钮等宽保持标题居中）
          Row().width(40)
        }
        .width('100%')
        .height(56)
        .padding({ left: SPACING.pageH, right: SPACING.pageH })
        .alignItems(VerticalAlign.Center)

        // ── 内容主体 ──
        FamilyMemberDetailPage()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.tokens ? this.tokens.bg : '#F5F7FA')
    }
    .width('100%')
    .height('100%')
  }
}
