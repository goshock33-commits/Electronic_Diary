// <!-- agentID: DEV-031 -->
// 页面：搜索页（路由入口点，转发到 features/search 模块的真实实现）
// 修复：DEV-031 - 修复编译错误
//   ERROR 3: SearchPageComponent 未导出，实际导出的是 SearchPage
//   ERROR 4: 组件名错误，改为 SearchPage
// 原因：features/search/Index.ets 导出的是 SearchPage，不是 SearchPageComponent

import { SearchPage as SearchPageReal } from 'features/search';

/**
 * 搜索页路由入口
 *
 * 这是一个薄壳页面，仅用于路由注册（main_pages.json）。
 * 实际搜索功能由 features/search 模块的 SearchPage 实现（包含 FTS5 全文检索）。
 */
@Entry
@Component
export struct SearchPage {
  build() {
    Stack() {
      SearchPageReal()
    }
    .width('100%')
    .height('100%')
  }
}
