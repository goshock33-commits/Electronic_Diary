// <!-- agentID: HUI-069 -->
// @Entry 家庭成员页「壳」（eyebrow「FAMILY MEMBERS」+ H1「家庭成员」+ features_family FamilyPage）
// 壳页模式复刻 PomodoroPage：返回按钮 + eyebrow + H1 + feature 内容主体 + 猫爪特效层
// §1.4 三者一致：模块 name = features_family = 依赖 key = import 路径
// §9.4：@StorageLink tokens 读取全部判空兜底（黑白手绘风格中性兜底）
// 图标：person(NAV_PROFILE✅) / arrow_left(ARROW_BACK✅)
// 令牌：IconMapper / SPACING / TYPO / ICON —— 全引用，禁散写魔数

import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper, SPACING, TYPO, ICON, SKETCH_TITLE, reportPawTouch, PawOverlayLayer } from '@ohos/shared';
import { FamilyPage } from 'features_family';
import { router } from '@kit.ArkUI';

@Entry
@Component
struct FamilyPageEntry {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  build() {
    // 最小外包 Stack——同树叠加猫爪视觉层（先例：PomodoroPage HUI-001）
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // ── 顶部：返回按钮 ──
        Row() {
          Button() {
            SymbolGlyph(IconMapper.ARROW_BACK)
              .fontSize(ICON.navBack)
              .fontWeight(FontWeight.Bold) // HUI-041：系统裸箭头加粗
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

        // ── Eyebrow：FAMILY MEMBERS（大写英文 + 成员图标 + 宽字距） ──
        Row() {
          SymbolGlyph(IconMapper.NAV_PROFILE)
            .fontSize(14)
            .fontColor([this.tokens ? this.tokens.primary : '#000000'])
            .margin({ right: 6 })
          Text('FAMILY MEMBERS')
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(TYPO.eyebrow.weight)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .opacity(0.6)
            .letterSpacing(3)
            .attributeModifier(SKETCH_TITLE)
        }

        // ── H1：家庭成员 ──
        Text('家庭成员')
          .fontSize(TYPO.h1.size)
          .fontWeight(TYPO.h1.weight)
          .fontColor(this.tokens ? this.tokens.primary : '#000000')
          .width('100%')
          .margin({ top: 4, bottom: SPACING.sectionGap })
          .attributeModifier(SKETCH_TITLE)

        // ── 内容主体：成员列表 + 添加按钮 + 昵称编辑弹窗（features_family） ──
        FamilyPage()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({
        left: SPACING.pageH,
        right: SPACING.pageH,
        top: SPACING.pageTop
      })
      .backgroundColor(this.tokens ? this.tokens.bg : '#FAF8F5')
      .accessibilityGroup(true)
      .accessibilityText('家庭成员页面')
      // 猫爪特效触摸捕获（页面树内监听 Down，不消费；视觉层在外包 Stack 顶层）
      .onTouch((event: TouchEvent) => reportPawTouch(event))

      // 猫爪视觉层（同树最上层子节点，不参与命中，不挡交互）
      PawOverlayLayer()
    }
    .width('100%')
    .height('100%')
  }
}
