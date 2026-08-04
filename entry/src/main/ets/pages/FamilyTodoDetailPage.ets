// agentID: HUI-004
// @Entry 家庭待办详情页壳（返回按钮 + 内容主体）
// 主题：HarmonyOS 蓝白卡片风格
// 令牌：IconMapper / SPACING / TYPO / ICON 全引用
// §1.4 三者一致：模块 name = features_family_message = 依赖 key = import 路径
// §9.4：@StorageLink tokens 读取全部判空兜底
// T047 路由参数契约：router.getParams() 在主组件 aboutToAppear 中解析

import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper, SPACING, TYPO, ICON } from '@ohos/shared';
import { FamilyTodoDetailPage } from 'features_family_message';
import { router } from '@kit.ArkUI';

@Entry
@Component
struct FamilyTodoDetailPageEntry {
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

          Text('待办详情')
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

        // ── 内容主体（T047：路由参数在 FamilyTodoDetailPage.aboutToAppear 中解析）──
        FamilyTodoDetailPage()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.tokens ? this.tokens.bg : '#F5F7FA')
    }
    .width('100%')
    .height('100%')
  }
}
