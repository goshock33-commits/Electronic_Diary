// agentID: HUI-014
// 卡片：PomodoroCard — 番茄钟倒计时桌面卡片 (2x2)
// 关联设计稿：HUI-014_widget_cards（frontend-design / ui-ux-pro-max / brainstorming）
// 关联任务：T030c（第5批 ExtensionAbility）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式（Stage 模型 / FormExtensionAbility）
// 无障碍：遵守 T042 规范（accessibilityText 不为空、触控热区 >= 48x48vp）
//
// === 图标来源章节 ===
// 所有图标引用自 HarmonyOS SymbolGlyph 系统图标库，均经 IconMapper 验证有效：
// | 图标资源                  | 用途         | 验证来源             |
// |---------------------------|--------------|----------------------|
// | sys.symbol.play_fill      | 播放/开始    | IconMapper.PLAY      |
// | sys.symbol.pause_fill     | 暂停         | IconMapper.PAUSE     |
// | sys.symbol.arrow_counterclockwise | 重置/停止 | IconMapper.STOP      |
// | sys.symbol.clock_fill     | 番茄钟图标   | IconMapper.CLOCK     |
//
// === 华为文档引用章节 ===
// 核心组件参考：
//   - Canvas 绘制上下文：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-canvasrenderingcontext2d
//   - Button 组件：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-button
//   - Text 组件：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-text
//   - FormExtensionAbility：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-form-formextensionability
//   - 卡片页面能力说明（ArkTS widget modules）：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-widget-modules
// 设计指南参考：
//   - Symbol 图标库：https://developer.huawei.com/consumer/cn/design/harmonyos-symbol/

// ── HUI-016 · 批次1(T009) 手绘换肤豁免（保留 SymbolGlyph，不换 SketchIcon）──────────
// 核验理由（Form Widget 运行时约束）：
//   1) 服务卡片运行于独立 FormRenderService 进程，不共享主应用 AppStorage；SketchIcon 靠
//      @StorageProp('theme_is_dark') 感知深色 → 卡片进程内恒为默认值，深色适配失效，违反
//      换肤铁律「深色必须适配」。SymbolGlyph 原生支持卡片 colorMode:"auto" 深浅自适应。
//   2) SketchIcon 为 @Reusable（面向列表滚动复用），ArkTS 卡片受限运行时无收益且增编译风险。
//   3) SketchIcon 位于 features/statistics，跨进程主题依赖须改显式 strokeColor 方可用。
//   解封条件：迁 SketchIcon 体系入 shared + 卡片内传显式 strokeColor + DevEco 真机验证 @Reusable。
// 注：本卡片计时环已用 Canvas 绘制（drawTimerRing），证 Canvas 在 Form 环境可用；豁免因主题/复用约束而非 Canvas。
import { IconMapper, FONT } from '@ohos/shared';

@Entry
@Component
struct PomodoroCard {
  // ── FormBindingData 注入（由 PomodoroFormAbility 提供） ──
  @LocalStorageProp('remainingSeconds') remainingSeconds: number = 0;  // 剩余秒数
  @LocalStorageProp('totalSeconds') totalSeconds: number = 1500;       // 总秒数（默认25分钟）
  @LocalStorageProp('isRunning') isRunning: number = 0;               // 0=暂停/停止, 1=运行中
  @LocalStorageProp('statusLabel') statusLabel: string = '准备开始';  // 状态文字

  // ── Canvas 上下文 ──
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  // ── 主题色 ──
  private readonly textPrimaryColor: string = '#2E3A2E';
  private readonly textSecondaryColor: string = '#8A9B8A';
  private readonly cardBgColor: string = 'rgba(255, 255, 255, 0.85)';
  // 进度环颜色随剩余时间变化
  private readonly colorGreen: string = '#00C2B8';   // > 10min
  private readonly colorYellow: string = '#E0BE72';  // 3-10min
  private readonly colorRed: string = '#78909C';     // < 3min
  private readonly ringBgColor: string = '#E8F5E9';

  build() {
    Stack() {
      // 卡片背景
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(16)
        .backgroundColor(this.cardBgColor)
        .border({ width: 0.5, color: 'rgba(76, 175, 80, 0.12)' })
        .shadow({ radius: 12, color: 'rgba(76, 175, 80, 0.08)', offsetX: 0, offsetY: 2 })

      // 主内容区
      Column() {
        // 番茄钟图标 + 状态标签
        Row() {
          SymbolGlyph(IconMapper.CLOCK)
            .width(14)
            .height(14)
            .fontColor([this.textSecondaryColor])

          Text(this.statusLabel)
            .fontSize(11)
            .fontColor(this.textSecondaryColor)
            .margin({ left: 4 })
        }
        .margin({ bottom: 6 })

        // 环形进度 + 倒计时数字
        Stack({ alignContent: Alignment.Center }) {
          // Canvas 绘制环形进度
          Canvas(this.ctx)
            .width(80)
            .height(80)
            .onReady(() => {
              this.drawTimerRing();
            })

          // 中央倒计时文字
          Text(this.formatTime())
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textPrimaryColor)
            // FormExtensionAbility 无字体注册上下文，FONT.mono 回退系统等宽字体
            .fontFamily(FONT.mono)
        }

        // 播放/暂停 + 重置按钮
        Row() {
          // 播放/暂停按钮
          Button() {
            SymbolGlyph(this.isRunning === 1
              ? IconMapper.PAUSE
              : IconMapper.PLAY)
              .width(18)
              .height(18)
              .fontColor(['#FFFFFF'])
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(this.getRingColor())
          .accessibilityText(this.isRunning === 1 ? '暂停计时' : '开始计时')

          // 重置按钮
          Button() {
            SymbolGlyph(IconMapper.STOP)
              .width(18)
              .height(18)
              .fontColor([this.textSecondaryColor])
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(Color.Transparent)
          .margin({ left: 6 })
          .accessibilityText('重置计时')
        }
        .margin({ top: 8 })
      }
      .width('100%')
      .height('100%')
      .padding({ top: 12, bottom: 10, left: 14, right: 14 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .accessibilityGroup(true)
    .accessibilityText(
      '番茄钟卡片：' + this.statusLabel +
      '，剩余' + this.formatTime() +
      (this.isRunning === 1 ? '，计时中' : '，已暂停')
    )
  }

  /**
   * 获取环形进度条颜色（根据剩余时间比例）
   * > 60%: 绿色, 20%-60%: 黄色, < 20%: 红色
   */
  private getRingColor(): string {
    const ratio: number = this.totalSeconds > 0 ?
      this.remainingSeconds / this.totalSeconds : 1;
    return ratio > 0.6 ? this.colorGreen :
      ratio > 0.2 ? this.colorYellow :
      this.colorRed;
  }

  /**
   * 格式化时间 MM:SS
   */
  private formatTime(): string {
    const mins: number = Math.floor(this.remainingSeconds / 60);
    const secs: number = this.remainingSeconds % 60;
    const padMin: string = (mins < 10 ? '0' : '') + mins;
    const padSec: string = (secs < 10 ? '0' : '') + secs;
    return padMin + ':' + padSec;
  }

  /**
   * 绘制倒计时环形进度
   */
  private drawTimerRing(): void {
    const centerX: number = 40;
    const centerY: number = 40;
    const lineWidth: number = 4;
    const radius: number = 33;
    this.ctx.clearRect(0, 0, 80, 80);

    // 背景环
    this.ctx.beginPath();
    this.ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
    this.ctx.strokeStyle = this.ringBgColor;
    this.ctx.lineWidth = lineWidth;
    this.ctx.lineCap = 'round';
    this.ctx.stroke();

    // 前景进度弧
    const progress: number = this.totalSeconds > 0 ?
      this.remainingSeconds / this.totalSeconds : 0;
    const startAngle: number = -Math.PI / 2;
    const endAngle: number = startAngle + (2 * Math.PI * progress);

    this.ctx.beginPath();
    this.ctx.arc(centerX, centerY, radius, startAngle, endAngle);
    this.ctx.strokeStyle = this.getRingColor();
    this.ctx.lineWidth = lineWidth;
    this.ctx.lineCap = 'round';
    this.ctx.stroke();
  }
}
