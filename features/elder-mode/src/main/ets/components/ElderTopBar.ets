// <!-- agentID: HUI -->
// 组件：ElderTopBar 长辈模式顶栏（左上角菜单按钮 + 长按3秒退出长辈模式）
// 关联模块：features/elder-mode（HAR）
// 交互：菜单按钮 56x56vp 大热区——点按 onMenuTap（宿主开待办抽屉）；
//       长按持续 3 秒触发 onExitElder（LongPressGesture duration:3000 为权威触发源，
//       onTouch Down/Up 仅驱动进度条视觉，提前松手取消归零）
// 适老化：触控热区 >= 56vp、大字号（20vp+）、高对比；退出走"长按3秒"防误触
// 视觉：黑白中性 + 暖色兜底（与 ElderHomeView 同族，无青色/无大红——用户偏好）
// 运行时崩溃防范（PROJECT_SPEC §9）：普通方法非 getter；字段初值不含 $r()；
//       @StorageLink 判空；对象字面量均有声明类型（§8.2）
// 开发范式：ArkTS 声明式开发范式（Stage 模型）

import { IconMapper } from '@ohos/shared';
import type { ThemeColorTokens } from '@ohos/shared';

/** 长按退出所需时长(ms)——需求锁定 3 秒 */
const HOLD_EXIT_DURATION: number = 3000;
/** 菜单按钮边长(vp)——适老化触控热区 >= 56vp */
const MENU_BTN_SIZE: number = 56;
/** 进度条收回动画时长(ms) */
const HOLD_RESET_DURATION: number = 150;
/** 兜底主文字色（高对比近黑，与 ElderHomeView 一致） */
const FALLBACK_TEXT_PRIMARY: string = '#1A1A1A';
/** 兜底次要文字色 */
const FALLBACK_TEXT_SECONDARY: string = '#5C5C5C';
/** 兜底按钮底色 */
const FALLBACK_BG_CARD: string = '#FFFFFF';
/** 兜底边框色（暖灰，与 ElderHomeView 脉冲环同族） */
const FALLBACK_BORDER: string = '#C9B8A0';
/** 兜底进度条轨道色 */
const FALLBACK_DIVIDER: string = '#EDE5D8';

/**
 * ElderTopBar —— 长辈模式顶栏。
 *
 * 典型用法（宿主壳接线）：
 *   ElderTopBar({
 *     title: '今天',
 *     onMenuTap: () => { this.drawerVisible = true; },
 *     onExitElder: () => { this.leaveElderMode(); }
 *   })
 */
@Component
export struct ElderTopBar {
  /** 顶栏标题（大字号；空串则不占位显示） */
  @Prop title: string = '';
  /** 主题令牌（未注入时走暖色兜底，§9 判空使用） */
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** 点按菜单回调（宿主开待办抽屉等） */
  onMenuTap?: () => void;
  /** 长按满 3 秒退出长辈模式回调（模式切换由宿主接线，本组件只发意图） */
  onExitElder?: () => void;

  /** 是否正在长按（驱动进度条/提示文案显隐） */
  @State private holding: boolean = false;
  /** 长按进度条宽度百分数 0-100（linear 3s 动画驱动） */
  @State private holdPercent: number = 0;

  // ==== 取色（普通方法非 getter，§9.1；均为 string，判空兜底）====
  private getTextPrimary(): string {
    return this.tokens !== null ? this.tokens.textPrimary : FALLBACK_TEXT_PRIMARY;
  }

  private getTextSecondary(): string {
    return this.tokens !== null ? this.tokens.textSecondary : FALLBACK_TEXT_SECONDARY;
  }

  private getBtnBg(): string {
    return this.tokens !== null ? this.tokens.bgCard : FALLBACK_BG_CARD;
  }

  private getBorder(): string {
    return this.tokens !== null ? this.tokens.border : FALLBACK_BORDER;
  }

  private getTrack(): string {
    return this.tokens !== null ? this.tokens.divider : FALLBACK_DIVIDER;
  }

  /** 按下：进度条 0 → 100 线性 3s（与 LongPressGesture duration 同步） */
  private startHold(): void {
    this.holding = true;
    this.holdPercent = 0;
    animateTo({ duration: HOLD_EXIT_DURATION, curve: Curve.Linear }, () => {
      this.holdPercent = 100;
    });
  }

  /** 提前松手/触发完成：进度条收回归零 */
  private cancelHold(): void {
    this.holding = false;
    animateTo({ duration: HOLD_RESET_DURATION, curve: Curve.EaseOut }, () => {
      this.holdPercent = 0;
    });
  }

  build() {
    Column() {
      Row() {
        // ===== 左上角菜单按钮（56x56 大热区：点按=菜单，长按3s=退出）=====
        Column() {
          // 菜单图标——line_3_horizontal 在库（IconMapper.SORT/DRAG_HANDLE 同图标已实证渲染）
          SymbolGlyph($r('sys.symbol.line_3_horizontal'))
            .fontSize(28)
            .fontColor([this.getTextPrimary()])
        }
        .width(MENU_BTN_SIZE)
        .height(MENU_BTN_SIZE)
        .borderRadius(16)
        .backgroundColor(this.getBtnBg())
        .border({ width: 1.5, color: this.getBorder() })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .scale({
          x: this.holding ? 0.92 : 1,
          y: this.holding ? 0.92 : 1
        })
        .animation({ duration: 200, curve: Curve.EaseOut })
        .onClick(() => {
          if (this.onMenuTap !== undefined) {
            this.onMenuTap();
          }
        })
        // 长按满 3 秒 → 退出长辈模式（权威触发源；repeat:false 只触发一次）
        .gesture(
          LongPressGesture({ repeat: false, duration: HOLD_EXIT_DURATION })
            .onAction(() => {
              this.cancelHold();
              if (this.onExitElder !== undefined) {
                this.onExitElder();
              }
            })
        )
        // 按压视觉反馈：Down 启动进度动画，Up/Cancel 提前松手归零（仅视觉，不做触发判定）
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.startHold();
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.cancelHold();
          }
        })
        .accessibilityText('菜单，点击打开今日待办；长按三秒退出长辈模式')

        // ===== 标题 / 长按提示（大字号，高对比）=====
        Text(this.holding ? '按住 3 秒退出长辈模式' : this.title)
          .fontSize(this.holding ? 20 : 26)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.holding ? this.getTextSecondary() : this.getTextPrimary())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 16 })
          .layoutWeight(1)
          .accessibilityLevel('no')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // ===== 长按进度条（仅按住时显示：满宽轨道 + 线性推进的近黑指示条）=====
      if (this.holding) {
        Row() {
          Row()
            .width(this.holdPercent + '%')
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.getTextPrimary())
        }
        .width('100%')
        .height(6)
        .borderRadius(3)
        .backgroundColor(this.getTrack())
        .margin({ top: 10 })
        .justifyContent(FlexAlign.Start)
        .transition(TransitionEffect.opacity(0).animation({ duration: 150, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor(Color.Transparent)
  }
}
