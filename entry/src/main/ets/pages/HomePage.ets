// 页面：首页壳（@Entry 薄包装 → HomeContentView）
// 关联设计稿：家庭消息流首页（HarmonyOS 蓝白卡片风格）
// 开发范式：ArkTS 声明式开发范式
// 说明：本文件为 @Entry 入口壳，实际 UI 在 HomeContentView 组件中。
//       MainPage 通过 TabContent 加载本组件，底部 Tab 由 FloatingTabBar 提供。
// 崩溃防范（PROJECT_SPEC §9）：无 @StorageLink 在壳层（内容组件自管 tokens）

import { HomeContentView } from '../components/HomeContentView';

/**
 * 首页入口壳
 *
 * 薄包装模式：@Entry 标记页面入口，build 直接委托给 HomeContentView。
 * 与 CalendarPage / FamilyPage 等壳页模式一致。
 */
@Entry
@Component
export struct HomePage {
  build() {
    Stack() {
      HomeContentView()
    }
    .width('100%')
    .height('100%')
  }
}
