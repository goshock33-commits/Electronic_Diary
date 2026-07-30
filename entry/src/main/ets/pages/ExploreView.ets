// <!-- agentID: HUI-050 -->
// 页面：时光探索页（搜索页 — HarmonyOS 蓝白卡片风格）
// 关联计划：PLN-003 P1-02（时光探索页 ExploreView）
// 关联设计：UX-001 §2.8 ExploreView（HarmonyOS 蓝白卡片搜索页）
// 关联规范：PROJECT_SPEC §9 崩溃防范 / §10 图标本地库 / §1.4 模块名三者一致
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 图标：SEARCH(magnifyingglass, 项目实证 MainPage L35)，禁 emoji
// 崩溃防范：@StorageLink 判空回退 / build 无 getter / 字段初值无 $r() / @Component 非 @Entry
// 无障碍：accessibilityText 非空 + 触控热区 >= 44vp
// 改版说明：原分段容器（统计/检索切换）已移除，统计页 StatisticsPage 作为独立 @Component 可供抽屉菜单使用；
//   本页现为纯搜索页，直接渲染 SearchPage 壳。

import type { ThemeColorTokens } from '@ohos/shared';
import { SearchPage } from '@ohos/search';

/**
 * 时光探索页（搜索页）
 *
 * HarmonyOS 蓝白卡片风格搜索页，直接渲染 SearchPage 壳。
 * 原「时光统计」分段已移除，统计页 StatisticsPage 作为独立导出组件可供抽屉菜单使用。
 *
 * 说明（PROJECT_SPEC §9）：@StorageLink tokens 读取全判空回退；
 * build 中不调用 private getter。
 */
@Component
export struct ExploreView {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  build() {
    Column() {
      // ═══════════════════════════════════════════
      // 直接渲染搜索页壳（壳自带 eyebrow+H1 头部、搜索框、筛选、结果/历史等内容）
      // ═══════════════════════════════════════════
      SearchPage()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens ? this.tokens.bg : '#F5F7FA')
  }
}
