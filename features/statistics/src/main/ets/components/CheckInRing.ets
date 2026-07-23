// <!-- agentID: HUI-007 -->
// fix: HUI-016
// 组件：黑白手绘环形仪表盘（Canvas）
// 关联任务：T-SKETCH 统计页黑白手绘风格
// API 24 Canvas：RenderingContextSettings 模式
// HUI-040：深色模式 P0 修复——Canvas 画笔读 token + tokens @Watch 显式重绘 + 补 surface 卡片底（darkmode_audit 问题2）

import type { ThemeColorTokens } from '@ohos/shared';
import { SPACING, TYPO, FONT, EventBus, getThemeManager } from '@ohos/shared';

@Component
export struct CheckInRing {
  @Prop @Watch('onDataChange') checkedDays: number = 0;
  @Prop @Watch('onDataChange') totalDays: number = 30;
  // HUI-040：@StorageLink 变更不会自动重画 Canvas，必须 @Watch 显式触发重绘（Canvas 换肤两件套之二）
  @StorageLink('theme_tokens') @Watch('onThemeChange') tokens: ThemeColorTokens | null = null;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private readonly CANVAS_SIZE: number = 140;

  // fix: HUI-016 · T-D01复测实证 —— 后台 TabContent 的 @StorageLink 收不到 theme_tokens 变更
  //   （详见 StatisticsPage.aboutToAppear 同款注释）：订阅 THEME_CHANGED 从 ThemeManager 真相源
  //   回读色板写回链接并显式重绘（Canvas 换肤两件套之二）。Tab 常驻组件不退订（DEV-003 先例）。
  aboutToAppear(): void {
    EventBus.on(EventBus.EventNames.THEME_CHANGED, (data: Record<string, Object>) => {
      this.tokens = getThemeManager().getTokens();
      this.drawRing();
    });
  }

  private getPercentage(): string {
    if (this.totalDays <= 0) { return '0%'; }
    return Math.round(this.checkedDays / this.totalDays * 100).toString() + '%';
  }

  private getRatioText(): string {
    return this.checkedDays.toString() + '/' + this.totalDays.toString();
  }

  private getAccessibilityLabel(): string {
    return '打卡完成率' + this.getPercentage() + '，已打卡' +
      this.checkedDays.toString() + '天，共' + this.totalDays.toString() + '天';
  }

  // 手绘抖动弧线（用小线段+半径微扰模拟手绘不完美感）
  private wobbleArc(ctx: CanvasRenderingContext2D, cx: number, cy: number,
                    r: number, startAngle: number, endAngle: number, wobbleAmp: number): void {
    const steps: number = Math.max(30, Math.floor(Math.abs(endAngle - startAngle) / 0.05));
    const angleStep: number = (endAngle - startAngle) / steps;
    let first: boolean = true;
    for (let i = 0; i <= steps; i++) {
      const a: number = startAngle + i * angleStep;
      // 正弦扰动模拟运笔不稳，配合步进相位制造变化
      const wobble: number = Math.sin(a * 5.3 + i * 0.37) * wobbleAmp + Math.sin(a * 11.7 + i * 0.19) * wobbleAmp * 0.4;
      const rr: number = r + wobble;
      const x: number = cx + Math.cos(a) * rr;
      const y: number = cy + Math.sin(a) * rr;
      if (first) { ctx.moveTo(x, y); first = false; }
      else { ctx.lineTo(x, y); }
    }
  }

  private drawRing(): void {
    const ctx: CanvasRenderingContext2D = this.ctx;
    const cx: number = this.CANVAS_SIZE / 2;
    const cy: number = this.CANVAS_SIZE / 2;
    const outerR: number = 56;
    const ratio: number = this.totalDays > 0 ? this.checkedDays / this.totalDays : 0;

    ctx.clearRect(0, 0, this.CANVAS_SIZE, this.CANVAS_SIZE);

    // 背景圈（手绘抖动，加大振幅）
    // HUI-040：画笔死值 → 读 token（背景圈用 border 弱描边）
    ctx.strokeStyle = this.tokens ? this.tokens.border : '#CCCCCC';
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    ctx.beginPath();
    this.wobbleArc(ctx, cx, cy, outerR, 0, 2 * Math.PI, 1.5);
    ctx.stroke();

    // 进度弧线（抖动+粗细变化，加大振幅）
    if (ratio > 0) {
      const endAngle: number = ratio * 2 * Math.PI;
      const segCount: number = 6;
      const anglePerSeg: number = (ratio * 2 * Math.PI) / segCount;
      for (let i = 0; i < segCount; i++) {
        const startA: number = i * anglePerSeg - Math.PI / 2;
        const endA: number = startA + anglePerSeg + 0.02;
        let lw: number = 9;
        if (i === 0 || i === segCount - 1) { lw = 13; }
        else if (i === 1 || i === segCount - 2) { lw = 8; }
        // HUI-040：进度弧死值 #000000 → tokens.textPrimary（深色翻白，黑底可见）
        ctx.strokeStyle = this.tokens ? this.tokens.textPrimary : '#000000';
        ctx.lineWidth = lw;
        ctx.lineCap = 'round';
        ctx.beginPath();
        this.wobbleArc(ctx, cx, cy, outerR, startA, endA, 2.0);
        ctx.stroke();
      }
      // 收笔——浓墨重按
      // HUI-040：收笔死值 #000000 → tokens.textPrimary
      ctx.strokeStyle = this.tokens ? this.tokens.textPrimary : '#000000';
      ctx.lineWidth = 15;
      ctx.lineCap = 'round';
      ctx.beginPath();
      this.wobbleArc(ctx, cx, cy, outerR, endAngle - Math.PI / 2 - 0.10, endAngle - Math.PI / 2 + 0.06, 2.5);
      ctx.stroke();
    }

    // 百分比数字
    ctx.font = 'bold 28px HarmonyOS Sans';
    // HUI-040：数字死值 #000000 → tokens.textPrimary
    ctx.fillStyle = this.tokens ? this.tokens.textPrimary : '#000000';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(this.getPercentage(), cx, cy - 6);

    // 比值文字
    ctx.font = '12px HarmonyOS Sans';
    // HUI-040：次要文字死值 #666666 → tokens.textSecondary
    ctx.fillStyle = this.tokens ? this.tokens.textSecondary : '#666666';
    ctx.fillText(this.getRatioText(), cx, cy + 16);
  }

  private onDataChange(): void { this.drawRing(); }

  // HUI-040：主题切换显式重绘（Canvas 不随 @StorageLink 变更自动刷新）
  private onThemeChange(): void { this.drawRing(); }

  build() {
    // HUI-040：补 surface 卡片底，与 MoodBarChart/TodoProgressBar 卡片层级统一（深色下环不再裸画在页面 bg 上）
    Column() {
      Canvas(this.ctx)
        .width(this.CANVAS_SIZE)
        .height(this.CANVAS_SIZE)
        .onReady(() => { this.drawRing(); })
        .accessibilityText(this.getAccessibilityLabel())
        .accessibilityLevel('yes')

      Progress({
        value: this.totalDays > 0 ? this.checkedDays : 0,
        total: this.totalDays > 0 ? this.totalDays : 1,
        type: ProgressType.Ring
      })
        .visibility(Visibility.Hidden)
        .width(0).height(0)
        .accessibilityText('打卡率' + this.getPercentage())
    }
    .width('100%')
    .borderRadius(14)
    .padding(SPACING.cardPadLg)
    .backgroundColor(this.tokens ? this.tokens.surface : '#FFFFFF')
    .border({ width: 1, color: this.tokens ? this.tokens.border : '#CCCCCC' })
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.15)', offsetX: 2, offsetY: 4 })
    .alignItems(HorizontalAlign.Center)
  }
}
