// agentID: HUI-076
// 页面：明日日程页（@Entry 独立路由）
// 说明：菜单「明日日程」入口 → router.pushUrl('pages/TomorrowPage')。
//       与待办页交互完全一致，复用 TodoBoard，区别为默认日期为明天（dayOffset=1）、标题「明日日程」。
//       进入动画为从右侧滑入（pageTransition .slide(SlideEffect.Right)）+ TodoBoard 内部 spring 弹性微动。
// 关联任务：HUI-076（待办页 + 明日日程页 · 菜单入口独立路由）
// 开发范式：ArkTS 声明式开发范式
// 令牌驱动：颜色读 @StorageLink('theme_tokens')（判空回退）
// 崩溃防范（PROJECT_SPEC §9）：@StorageLink tokens 判空回退；无字段初值 $r()；无 getter-in-build。
// 注意（PROJECT_SPEC §8.2）：@Entry 不与 export 共存；本页仅作路由入口，可复用内容在 TodoBoard。

import type { ThemeColorTokens } from '@ohos/shared';
import { reportPawTouch, PawOverlayLayer } from '@ohos/shared';
import { TodoBoard } from './TodoBoard';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'TomorrowPage';

@Entry
@Component
struct TomorrowPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      TodoBoard({
        pageTitle: '明日日程',
        dayOffset: 1,
        onBack: () => {
          this.goBack();
        }
      })
      // HUI-001: 猫爪视觉层（同树最上层子节点，整层 None 不参与命中，不挡交互）
      // PawOverlayLayer()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens ? this.tokens.bg : '#FAF8F5')
    // HUI-001: 猫爪特效触摸捕获（页面树内监听 Down，不消费；视觉层在本页根 Stack 顶层）
    .onTouch((event: TouchEvent) => reportPawTouch(event))
  }

  /** 从右侧滑入 / 退出（route push/pop） */
  pageTransition() {
    PageTransitionEnter({ duration: 320, curve: Curve.Friction })
      .slide(SlideEffect.Right)
    PageTransitionExit({ duration: 260, curve: Curve.Friction })
      .slide(SlideEffect.Right)
  }

  private goBack(): void {
    router.back();
    hilog.info(0x0000, TAG, 'router.back from TomorrowPage');
  }
}
