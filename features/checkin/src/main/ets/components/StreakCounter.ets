// <!-- agentID: HUI-021 -->
// 组件：连续打卡天数计数器（火焰图标 + 数字翻转动画）
// 关联设计稿：UX-001_prototype.html（checkin-streak）
// 关联任务：F03（PLN-002 阶段2 打卡签到UI）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText + 触控热区 >= 48x48vp
// 深色适配：ThemeColorTokens + 硬编码回退色
// mock：硬编码连续7天，点击打卡后+1

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_BODY=清松手写体2（"天"单位标签）；连续天数走 FONT.monoBold 保留不动。
import { IconMapper, FONT, SKETCH_BODY } from '@ohos/shared';

/**
 * StreakCounter — 连续打卡天数计数器
 * 火焰图标 + 连续天数数字（翻转动画）+ "天" 单位
 */
@Component
export struct StreakCounter {
  @Watch('onStreakChanged')
  @Prop streak: number = 0;
  /** HUI-001：今天是否已打卡（父组件传；false=熄灭灰态显示上一轮天数，true=正常火焰橙亮色） */
  @Prop dimmed: boolean = false;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  /** 是否已完成首次渲染 */
  private hasInitialized: boolean = false;

  /** 当前显示的天数 */
  @State private displayStreak: number = 0;
  /** 前一个天数值（用于翻转过渡） */
  @State private prevStreak: number = 0;
  /** 翻转动画相位 0→1 */
  @State private flipPhase: number = 0;
  /** 是否正在播放翻转 */
  @State private flipping: boolean = false;
  /** 火焰缩放（打卡成功放大动画 1→1.3→1.0） */
  @State private flameScale: number = 1.0;

  aboutToAppear(): void {
    this.displayStreak = this.streak;
    this.prevStreak = this.streak;
    this.hasInitialized = true;
  }

  /**
   * 当父组件更新 streak Prop 时，自动触发翻转动画
   */
  onStreakChanged(): void {
    if (this.hasInitialized) {
      this.updateStreak(this.streak);
    }
  }

  build() {
    Row() {
      // 火焰图标
      SymbolGlyph(IconMapper.STREAK_FIRE)
        .fontSize(24)
        .fontColor([this.getFlameColor()])
        .scale({ x: this.flameScale, y: this.flameScale })
        .accessibilityLevel('no')

      // 翻转数字区域
      Stack({ alignContent: Alignment.Center }) {
        // 旧数字（翻出 — 向上滑出并淡出）
        if (this.flipping) {
          Text(this.prevStreak.toString())
            .fontSize(28)
            .fontWeight(700)
            .fontFamily(FONT.monoBold)
            .fontColor(this.getAccentColor())
            .opacity(1 - this.flipPhase)
            .translate({ x: 0, y: -20 * this.flipPhase })
            .accessibilityLevel('no')
        }

        // 新数字（翻入 — 从下方滑入并淡入）
        Text(this.displayStreak.toString())
          .fontSize(28)
          .fontWeight(700)
          .fontFamily(FONT.monoBold)
          .fontColor(this.getAccentColor())
          .opacity(this.flipping ? this.flipPhase : 1.0)
          .translate({ x: 0, y: this.flipping ? (20 * (1 - this.flipPhase)) : 0 })
          .accessibilityLevel('no')
      }
      .width(48)
      .height(40)
      .margin({ left: 8 })

      // "天"单位文字
      Text('天')
        .fontSize(16)
        .fontWeight(500)
        .fontColor(this.getUnitColor())
        .margin({ left: 4 })
        .accessibilityLevel('no')
        .attributeModifier(SKETCH_BODY) // HUI-029：天数单位→清松手写体2
    }
    .justifyContent(FlexAlign.Center)
    .height(48)
    .padding({ left: 12, right: 12 })
    .borderRadius(24)
    // HUI-040：修复 alpha 后拼 bug——ArkUI 8位hex 为 #AARRGGBB（alpha 在前），
    // 原 primary+'10' 深色下拼成 #FFFF10 = 不透明纯黄 #FFFF10（黄胶囊根因），改用前置 alpha
    .backgroundColor(this.tokens ?
      this.withAlpha(this.dimmed ? this.tokens.textTertiary : this.tokens.primary, '10') :
      'rgba(76,175,80,0.06)')
    .accessibilityGroup(true)
    .accessibilityText('连续打卡 ' + this.displayStreak.toString() + ' 天' +
      (this.dimmed ? '，已中断' : ''))
  }

  /** HUI-040：半透明版本：ArkUI hex-alpha 为 #AARRGGBB，需前置 alpha */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  /**
   * 获取火焰和数字的强调色
   * HUI-001：dimmed=true（未打卡熄灭灰）→ textTertiary 灰；否则正常 token primary
   */
  private getAccentColor(): string {
    if (this.dimmed) {
      return this.tokens ? this.tokens.textTertiary : '#8A8A8A';
    }
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  /**
   * 获取火焰图标颜色
   * HUI-001：dimmed=true（未打卡熄灭灰）→ textTertiary 灰；否则火焰橙 #FF6B35（燃烧态语义色）
   */
  private getFlameColor(): string {
    if (this.dimmed) {
      return this.tokens ? this.tokens.textTertiary : '#8A8A8A';
    }
    return '#FF6B35'; // 燃烧态：火焰橙（语义色，非青色，保留）
  }

  /** HUI-001：获取"天"单位文字色（未打卡灰 / 正常 textSecondary） */
  private getUnitColor(): string {
    if (this.dimmed) {
      return this.tokens ? this.tokens.textTertiary : '#8A8A8A';
    }
    return this.tokens ? this.tokens.textSecondary : '#5A7A5A';
  }

  /**
   * 更新连续天数并触发数字翻转动画
   * @param newStreak 新的连续天数
   */
  updateStreak(newStreak: number): void {
    if (newStreak === this.displayStreak) {
      return;
    }

    // 记录旧值并启动翻转
    this.prevStreak = this.displayStreak;
    this.flipPhase = 0;
    this.flipping = true;

    // 打卡成功：火焰 Scale 放大动画 1 → 1.3 → 1.0
    animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.flameScale = 1.3;
    });
    setTimeout(() => {
      animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
        this.flameScale = 1.0;
      });
    }, 180);

    // 翻转动画：分阶段驱动相位 0→0.5→1.0
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.flipPhase = 0.5;
    });

    setTimeout(() => {
      // 在半程时切换显示值
      this.displayStreak = newStreak;
      animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.flipPhase = 1.0;
      });
    }, 200);

    // 动画完成后清理状态
    setTimeout(() => {
      this.flipping = false;
    }, 450);
  }
}
