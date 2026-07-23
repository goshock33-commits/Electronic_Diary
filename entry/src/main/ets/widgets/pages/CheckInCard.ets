// agentID: HUI-014
// 卡片：CheckInCard — 打卡进度环桌面卡片 (2x2)
// 关联设计稿：HUI-014_widget_cards（frontend-design / ui-ux-pro-max / brainstorming）
// 关联任务：T030a（第5批 ExtensionAbility）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式（Stage 模型 / FormExtensionAbility）
// 无障碍：遵守 T042 规范（accessibilityText 不为空、触控热区 >= 48x48vp）
//
// === 图标来源章节 ===
// 所有图标引用自 HarmonyOS SymbolGlyph 系统图标库，均经 IconMapper 验证有效：
// | 图标资源                          | 用途             | 验证来源                  |
// |-----------------------------------|------------------|---------------------------|
// | sys.symbol.flame_fill             | 连续打卡天数火焰 | IconMapper.STREAK_FIRE    |
// | sys.symbol.checkmark_circle_fill  | 已打卡对勾图标   | IconMapper.CHECKIN_DONE   |
//
// === 华为文档引用章节 ===
// 核心组件参考：
//   - Canvas 绘制上下文：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-canvasrenderingcontext2d
//   - Text 组件：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-text
//   - Stack/Column/Row 容器：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-stack
//   - FormExtensionAbility：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-form-formextensionability
//   - 卡片页面能力说明（ArkTS widget modules）：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-widget-modules
// 设计指南参考：
//   - Symbol 图标库：https://developer.huawei.com/consumer/cn/design/harmonyos-symbol/

// ── HUI-016 · 批次1(T008) 手绘换肤豁免（保留 SymbolGlyph，不换 SketchIcon）──────────
// 核验理由（Form Widget 运行时约束）：
//   1) 服务卡片运行于独立 FormRenderService 进程，不共享主应用 AppStorage；SketchIcon 靠
//      @StorageProp('theme_is_dark') 感知深色 → 卡片进程内恒为默认值，深色适配失效，违反
//      换肤铁律「深色必须适配」。SymbolGlyph 原生支持卡片 colorMode:"auto" 深浅自适应。
//   2) SketchIcon 为 @Reusable（面向列表滚动复用），ArkTS 卡片受限运行时无收益且增编译风险。
//   3) SketchIcon 位于 features/statistics，跨进程主题依赖须改显式 strokeColor 方可用。
//   解封条件：迁 SketchIcon 体系入 shared + 卡片内传显式 strokeColor + DevEco 真机验证 @Reusable。
// 注：本卡片打卡进度环已用 Canvas 绘制（drawRing），证 Canvas 在 Form 环境可用；豁免因主题/复用约束而非 Canvas。
import { IconMapper } from '@ohos/shared';

@Entry
@Component
struct CheckInCard {
  // ── FormBindingData 注入（由 CheckInFormAbility 提供） ──
  @LocalStorageProp('checkedIn') checkedIn: number = 0;       // 0=未打卡, 1=已打卡
  @LocalStorageProp('streakDays') streakDays: number = 0;      // 连续打卡天数
  @LocalStorageProp('monthlyRate') monthlyRate: number = 0;    // 当月打卡率 0-100
  @LocalStorageProp('checkinLabel') checkinLabel: string = '打卡'; // 打卡按钮文字

  // ── Canvas 上下文 ──
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  // ── 主题色（绿调，与 ThemeColorTokens 对齐） ──
  private readonly ringBgColor: string = '#E8F5E9';
  private readonly ringActiveColor: string = '#00C2B8';
  private readonly ringActiveDark: string = '#00A89F';
  private readonly textPrimaryColor: string = '#2E3A2E';
  private readonly textSecondaryColor: string = '#8A9B8A';

  build() {
    Stack() {
      // 卡片背景（毛玻璃效果通过半透背景 + 边框模拟）
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(16)
        .backgroundColor('rgba(255, 255, 255, 0.85)')
        .border({ width: 0.5, color: 'rgba(76, 175, 80, 0.12)' })
        .shadow({ radius: 12, color: 'rgba(76, 175, 80, 0.08)', offsetX: 0, offsetY: 2 })

      // 主内容区
      Column() {
        // 打卡状态图标区 + 环形进度
        Stack({ alignContent: Alignment.Center }) {
          // Canvas 绘制环形进度
          Canvas(this.ctx)
            .width(88)
            .height(88)
            .onReady(() => {
              this.drawRing();
            })

          // 中心图标区域
          Column() {
            // 已打卡 vs 未打卡图标
            SymbolGlyph(this.checkedIn === 1
              ? IconMapper.CHECKIN_DONE
              : IconMapper.CHECKMARK)
              .width(28)
              .height(28)
              .fontColor([this.checkedIn === 1 ? '#00C2B8' : '#BDBDBD'])

            // 打卡文字
            Text(this.checkinLabel)
              .fontSize(11)
              .fontColor(this.checkedIn === 1 ? '#00C2B8' : '#9E9E9E')
              .margin({ top: 2 })
          }
        }
        .width(88)
        .height(88)

        // 连续天数 + 火焰
        Row() {
          SymbolGlyph(IconMapper.STREAK_FIRE)
            .width(16)
            .height(16)
            .fontColor([this.streakDays > 0 ? '#80CBC4' : '#E0E0E0'])

          Text('' + this.streakDays + ' 天')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textPrimaryColor)
            .margin({ left: 4 })
        }
        .margin({ top: 8 })

        // 当月打卡率文字
        Text('本月打卡率 ' + (this.monthlyRate).toFixed(0) + '%')
          .fontSize(11)
          .fontColor(this.textSecondaryColor)
          .margin({ top: 4 })
      }
      .width('100%')
      .height('100%')
      .padding({ top: 12, bottom: 12, left: 14, right: 14 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .accessibilityGroup(true)
    .accessibilityText(
      '打卡进度卡片：' +
      (this.checkedIn === 1 ? '今日已打卡' : '今日未打卡') +
      '，连续' + this.streakDays + '天，' +
      '本月打卡率' + (this.monthlyRate).toFixed(0) + '%'
    )
  }

  /**
   * 绘制环形进度
   * 背景环（浅灰绿）+ 前景弧（绿色，按 monthlyRate 百分比）
   */
  private drawRing(): void {
    const centerX: number = 44;
    const centerY: number = 44;
    const lineWidth: number = 5;
    const radius: number = 36;
    this.ctx.clearRect(0, 0, 88, 88);

    // 背景环
    this.ctx.beginPath();
    this.ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
    this.ctx.strokeStyle = this.ringBgColor;
    this.ctx.lineWidth = lineWidth;
    this.ctx.lineCap = 'round';
    this.ctx.stroke();

    // 前景进度弧（从顶部 12 点方向顺时针绘制）
    const progress: number = this.monthlyRate / 100;
    const contentColor: string = this.checkedIn === 1 ? this.ringActiveColor : this.ringActiveDark;
    const startAngle: number = -Math.PI / 2; // 12 点方向
    const endAngle: number = startAngle + (2 * Math.PI * progress);

    this.ctx.beginPath();
    this.ctx.arc(centerX, centerY, radius, startAngle, endAngle);
    this.ctx.strokeStyle = contentColor;
    this.ctx.lineWidth = lineWidth;
    this.ctx.lineCap = 'round';
    this.ctx.stroke();
  }
}
