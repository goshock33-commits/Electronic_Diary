// <!-- agentID: HUI-050 -->
// 页面：时光探索容器页（顶部青色分段控件 + 统计/检索二级切换）
// 关联计划：PLN-003 P1-02（时光探索容器页 ExploreView）
// 关联设计：UX-001 §2.8 ExploreView（分段控件 rounded-full 青底白字激活）
// 关联规范：PROJECT_SPEC §9 崩溃防范 / §10 图标本地库 / §1.4 模块名三者一致
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 图标：CHART_BAR(star_fill, 库 L257)/SEARCH(magnifyingglass, 项目实证 MainPage L35)，禁 emoji
// 崩溃防范：@StorageLink 判空回退 / build 无 getter / 字段初值无 $r() / @Component 非 @Entry
// 无障碍：accessibilityText 非空 + 触控热区 >= 44vp

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-026：引入手绘字体助手（全局黑白手绘换肤）——分段控件标签走 SKETCH_BODY=清松手写体2；仅补 fontFamily。
import { IconMapper, SKETCH_BODY } from '@ohos/shared';
import { StatisticsPage } from './StatisticsPage';
import { SearchPage } from './SearchPage';

/**
 * 时光探索容器页
 *
 * 顶部青色分段控件（rounded-full 圆角胶囊）：
 *   - 段 0「时光统计」图标 CHART_BAR（star_fill）
 *   - 段 1「时光检索」图标 SEARCH（magnifyingglass）
 * 激活段青底白字，未激活段透明底灰字；
 * 下方按 @State segment 用 if/else 渲染现有 StatisticsPage / SearchPage 壳（已挂载验证）。
 *
 * 说明（PROJECT_SPEC §9）：@StorageLink tokens 读取全判空回退；
 * build 中不调用 private getter；分段图标 SymbolGlyph 在 build 内引用 IconMapper 静态资源，
 * 不写入 struct 字段初始值，避免首帧资源上下文未就绪导致闪退。
 */
@Component
export struct ExploreView {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** 分段索引：0=时光统计，1=时光检索 */
  @State segment: number = 0;

  build() {
    Column() {
      // ═══════════════════════════════════════════
      // 顶部青色分段控件（rounded-full 圆角胶囊，两段均分）
      // 外层 Column 提供左右 16vp 内边距，内层轨道 width 100% 避免溢出
      // ═══════════════════════════════════════════
      Column() {
        Row() {
          this.SegmentButton(0, '时光统计', IconMapper.CHART_BAR)
          this.SegmentButton(1, '时光检索', IconMapper.SEARCH)
        }
        .width('100%')
        .padding(4)
        .borderRadius(999)
        .backgroundColor(this.tokens ? this.tokens.bgCard : '#F2F2F2')
        .border({ width: 1, color: this.tokens ? this.tokens.border : '#E0E0E0' })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      // ═══════════════════════════════════════════
      // 下方按分段渲染统计/检索壳（子壳自带滚动与自身内边距）
      // ═══════════════════════════════════════════
      Column() {
        if (this.segment === 0) {
          StatisticsPage()
        } else {
          SearchPage()
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens ? this.tokens.bg : '#F5F5F5')
  }

  /**
   * 分段控件单段按钮
   * @param index 段索引（与 @State segment 比对判定激活）
   * @param label 段文案
   * @param icon  段图标（SymbolGlyph 资源，build 内传入非字段初值，符合 §9.3）
   */
  @Builder
  SegmentButton(index: number, label: string, icon: Resource) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(18)
        // HUI-036：选中态图标改交互色前景 btnPrimaryText 白（配合雾霾蓝底），未选中态灰不变
        .fontColor([
          this.segment === index
            ? (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
            : (this.tokens ? this.tokens.textSecondary : '#999999')
        ])
      Text(label)
        .fontSize(14)
        .fontWeight(this.segment === index ? 700 : 500)
        // HUI-036：选中态文字改交互色前景 btnPrimaryText 白（配合雾霾蓝底），未选中态灰不变
        .fontColor(
          this.segment === index
            ? (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
            : (this.tokens ? this.tokens.textSecondary : '#999999')
        )
        .margin({ left: 6 })
        .attributeModifier(SKETCH_BODY) // HUI-026：分段控件标签→清松手写体2
    }
    .layoutWeight(1)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .borderRadius(999)
    // HUI-041：分段未选中态底由死白 #FFFFFF 改读 surface token（浅色 #F7F7F7 / 深色 #242424），修深色白底浅灰字不可见
    .backgroundColor(
      this.segment === index
        ? (this.tokens ? this.tokens.btnPrimary : '#738A9C')
        : (this.tokens ? this.tokens.surface : '#FFFFFF')
    )
    .accessibilityText(this.segment === index ? label + '，已选中' : label)
    .onClick(() => {
      this.segment = index;
    })
  }
}
