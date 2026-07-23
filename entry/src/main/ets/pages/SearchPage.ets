// <!-- agentID: HUI-057 -->
// 页面：搜索页壳（eyebrow「RETRIEVE TIMEPASSAGES」+ H1「时光检索」+ features/search 内容主体）
// 关联计划：PLN-003 P2-04（检索 SearchView 复刻）
// 关联设计：UX-001 §2.6 SearchView
// 关联规范：PROJECT_SPEC §9 崩溃防范 / §10 图标本地库 / §1.4 三者一致
// 开发范式：ArkTS 声明式开发范式
// 令牌：IconMapper / TYPO / SPACING —— 全引用
// 说明：eyebrow+H1 在壳层，内容主体（搜索框/筛选/结果/历史）在 features/search 内容层。

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-028：引入手绘标题字体助手 SKETCH_TITLE=猫啃什锦黑（eyebrow 微标 + H1 页面大标题）。
import { IconMapper, TYPO, SPACING, SKETCH_TITLE } from '@ohos/shared';
// HUI-001（修跳转）：router 接真实跳转，promptAction 仅留失败 Toast 兜底
import { promptAction, router } from '@kit.ArkUI';
import { SearchPage as SearchPageFeature } from 'features/search';
import type { SearchResultItem } from 'features/search';

/** 日记详情路由参数（契约同 HomePage/CalendarPage：params { date }，DiaryDetailPage.ets:106 getParams().date） */
interface SearchNavParams {
  date: string;
}

@Component
export struct SearchPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  build() {
    Column() {
      // ═══════════════════════════════════════════════
      // 头部：eyebrow「RETRIEVE TIMEPASSAGES」+ H1「时光检索」
      // ═══════════════════════════════════════════════
      Column() {
        Row() {
          SymbolGlyph(IconMapper.SEARCH)
            .fontSize(14)
            .fontColor([this.tokens ? this.tokens.primary : '#00C2B8'])
            .margin({ right: 6 })
          Text('RETRIEVE TIMEPASSAGES')
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(TYPO.eyebrow.weight)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .opacity(0.6)
            .letterSpacing(3)
            .attributeModifier(SKETCH_TITLE) // HUI-028：eyebrow 微标→猫啃什锦黑
        }

        Text('时光检索')
          .fontSize(TYPO.h1.size)
          .fontWeight(TYPO.h1.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .width('100%')
          .margin({ top: 4 })
          .attributeModifier(SKETCH_TITLE) // HUI-028：页面 H1→猫啃什锦黑
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: SPACING.sectionGap })

      // ═══════════════════════════════════════════════
      // 内容主体（features/search SearchPage）
      // ═══════════════════════════════════════════════
      SearchPageFeature({
        // HUI-001（修跳转 bug）：原三回调均为 Toast 占位从未接路由——结果点击现按来源分流真跳转：
        //   日记/开心事/多做事→该日期日记详情（DiaryDetailPage 聚合展示当日记录）；待办/提取→待办页。
        onResultClick: (item: SearchResultItem) => {
          if (item.sourceType === 'todo' || item.sourceType === 'extracted') {
            this.goTodoPage();
            return;
          }
          this.goDiaryDetail(item.date);
        },
        onDateClick: (date: string) => {
          this.goDiaryDetail(date);
        }
        // HUI-001（七轮·DEV-003 接线）：onDatePickerEntry 已移除——"按日期查找"改由 feature 层
        //   内部闭环（DatePicker → SearchViewModel.searchByDate → 复用结果列表渲染），壳层不再拦截。
      })
        .layoutWeight(1)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({
      left: SPACING.pageH,
      right: SPACING.pageH,
      top: SPACING.pageTop
    })
    .backgroundColor(this.tokens ? this.tokens.bg : '#FAF8F5')
  }

  /** 跳某日期日记详情（路由契约同 HomePage.goDiaryDetail：params { date }） */
  private goDiaryDetail(date: string): void {
    const params: SearchNavParams = { date: date };
    router.pushUrl({ url: 'pages/DiaryDetailPage', params: params }).catch((err: Error) => {
      promptAction.showToast({ message: '打开日记失败', duration: 1200 });
    });
  }

  /** 跳待办页（待办/提取任务类结果的落点，main_pages.json 已注册） */
  private goTodoPage(): void {
    router.pushUrl({ url: 'pages/TodoPage' }).catch((err: Error) => {
      promptAction.showToast({ message: '打开待办失败', duration: 1200 });
    });
  }
}
