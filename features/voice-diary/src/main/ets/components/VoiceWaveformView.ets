// <!-- agentID: HUI-060 -->
// 组件：语音波形条动画（P2-08：薄荷青皮肤统一 —— mint 色板 + TYPO 令牌引用）
// 关联任务：P2-08（PLN-003 阶段P2 §6.2 语音助手页换肤）
// 关联设计稿：UX-001_redesign_report.md §6.2
// 图标来源：无（纯几何波形 bar，不使用系统图标）
// 设计令牌：FONT.monoExtraBold numCard（预留）；TYPO / RADIUS / SPACING（令牌全引用，禁魔数）
// 动效：8 轨随机振幅 bar（mock: setInterval 160ms），原有逻辑完整保留
// 运行时崩溃防范（PROJECT_SPEC §9）：无 getter-in-build；字段初值不含 $r()；@StorageLink 判空；@Prop 无内置属性重名
// 开发范式：ArkTS 声明式开发范式（Stage 模型）
import { RADIUS, TYPO } from '@ohos/shared';
import type { ThemeColorTokens } from '@ohos/shared';

@Component
export struct VoiceWaveformView {
  // 是否正在监听（true=波形跳动，false=静止低平）
  @Prop @Watch('onActiveChanged') isActive: boolean = false;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  // 8 轨波形高度（vp）——字段初值为纯数字数组，符合 §9 规范
  @State private barHeights: number[] = [8, 8, 8, 8, 8, 8, 8, 8];
  private timerId: number = -1;
  private readonly BAR_COUNT: number = 8;
  private readonly MIN_HEIGHT: number = 8;
  private readonly MAX_HEIGHT: number = 44;
  private readonly REST_HEIGHT: number = 8;

  aboutToAppear(): void {
    if (this.isActive) {
      this.startAnimating();
    }
  }

  aboutToDisappear(): void {
    this.stopAnimating();
  }

  /** 监听态切换：开始/停止波形动画 */
  onActiveChanged(): void {
    if (this.isActive) {
      this.startAnimating();
    } else {
      this.stopAnimating();
      this.resetBars();
    }
  }

  private startAnimating(): void {
    if (this.timerId !== -1) {
      return;
    }
    this.timerId = setInterval(() => {
      this.barHeights = this.randomHeights();
    }, 160);
  }

  private stopAnimating(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  /** mock：随机生成 8 轨高度，中间轨偏高模拟人声能量分布 */
  private randomHeights(): number[] {
    const result: number[] = [];
    for (let i = 0; i < this.BAR_COUNT; i++) {
      const centerWeight: number = 1 - Math.abs(i - (this.BAR_COUNT - 1) / 2) / ((this.BAR_COUNT - 1) / 2);
      const base: number = this.MIN_HEIGHT + (this.MAX_HEIGHT - this.MIN_HEIGHT) * (0.4 + 0.6 * centerWeight);
      const jitter: number = Math.random() * (this.MAX_HEIGHT - this.MIN_HEIGHT) * 0.5;
      result.push(Math.round(Math.min(this.MAX_HEIGHT, this.MIN_HEIGHT + (base - this.MIN_HEIGHT) * Math.random() + jitter)));
    }
    return result;
  }

  private resetBars(): void {
    const result: number[] = [];
    for (let i = 0; i < this.BAR_COUNT; i++) {
      result.push(this.REST_HEIGHT);
    }
    this.barHeights = result;
  }

  /** mint 主色兜底（对齐 Preset morning-dew Light primary: #00C2B8） */
  private getBarColor(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  build() {
    Row() {
      ForEach(this.barHeights, (h: number, index: number) => {
        Column()
          .width(5)
          .height(h)
          .borderRadius(3)
          .backgroundColor(this.getBarColor())
          .opacity(this.isActive ? 1 : 0.35)
          .margin({ left: 3, right: 3 })
          .animation({ duration: 180, curve: Curve.EaseInOut })
      }, (h: number, index: number) => index.toString())
    }
    .height(this.MAX_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .accessibilityText(this.isActive ? '正在采集语音波形' : '语音波形静止')
    .accessibilityLevel('no')
  }
}

// === @Preview mock 组件（DevEco Studio Previewer 预览） ===

@Preview
@Component
struct VoiceWaveformViewPreview {
  build() {
    Column({ space: 24 }) {
      VoiceWaveformView({ isActive: true })
      VoiceWaveformView({ isActive: false })
    }
    .width('100%').padding(32).justifyContent(FlexAlign.Center)
    .backgroundColor('#FAF8F5')
  }
}
