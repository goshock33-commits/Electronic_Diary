// <!-- agentID: HUI-007 -->
// fix: HUI-016
// 组件：黑白手绘待办进度条（Canvas）
// 关联任务：T-SKETCH 统计页黑白手绘风格
// API 24 Canvas：RenderingContextSettings 模式
// HUI-040：深色模式 P0 修复——Canvas 画笔读 token + tokens @Watch 显式重绘（darkmode_audit 问题2）

import type { ThemeColorTokens } from '@ohos/shared';
import { SPACING, TYPO, FONT, EventBus, getThemeManager } from '@ohos/shared';

@Component
export struct TodoProgressBar {
  @Prop @Watch('onDataChange') completed: number = 0;
  @Prop @Watch('onDataChange') total: number = 0;
  // HUI-040：@StorageLink 变更不会自动重画 Canvas，必须 @Watch 显式触发重绘（Canvas 换肤两件套之二）
  @StorageLink('theme_tokens') @Watch('onThemeChange') tokens: ThemeColorTokens | null = null;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private readonly BAR_HEIGHT: number = 12;
  private readonly CANVAS_WIDTH: number = 320;

  // fix: HUI-016 · T-D01复测实证 —— 后台 TabContent 的 @StorageLink 收不到 theme_tokens 变更
  //   （详见 StatisticsPage.aboutToAppear 同款注释）：订阅 THEME_CHANGED 从 ThemeManager 真相源
  //   回读色板写回链接并显式重绘（Canvas 换肤两件套之二）。Tab 常驻组件不退订（DEV-003 先例）。
  aboutToAppear(): void {
    EventBus.on(EventBus.EventNames.THEME_CHANGED, (data: Record<string, Object>) => {
      this.tokens = getThemeManager().getTokens();
      this.drawBar();
    });
  }

  private getPercentage(): number {
    if (this.total <= 0) { return 0; }
    return Math.round((this.completed / this.total) * 100);
  }

  private getPercentageText(): string { return this.getPercentage().toString() + '%'; }

  private getCompletedText(): string {
    return '已完成 ' + this.completed.toString() + ' / ' + this.total.toString() + ' 项';
  }

  private getAccessibilityDescription(): string {
    return '待办完成率' + this.getPercentageText() + '，已完成' +
      this.completed.toString() + '项，共' + this.total.toString() + '项';
  }

  private drawBar(): void {
    const ctx: CanvasRenderingContext2D = this.ctx;
    const w: number = this.CANVAS_WIDTH;
    const h: number = this.BAR_HEIGHT;
    const ratio: number = this.total > 0 ? this.completed / this.total : 0;
    const fillW: number = Math.max(0, Math.min(w, Math.round(w * ratio)));

    ctx.clearRect(0, 0, w, h);

    // 背景轨道
    // HUI-040：轨道死值 #CCCCCC → tokens.border
    ctx.strokeStyle = this.tokens ? this.tokens.border : '#CCCCCC';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    this.drawSketchRoundRect(ctx, 0, 0, w, h, 5);
    ctx.stroke();

    // 填充矩形
    if (fillW > 0) {
      // HUI-040：填充死值 #000000 → tokens.textPrimary（深色翻白）
      ctx.fillStyle = this.tokens ? this.tokens.textPrimary : '#000000';
      ctx.globalAlpha = 0.85;
      ctx.beginPath();
      this.drawSketchRoundRect(ctx, 0, 0, fillW, h, 4);
      ctx.fill();
      ctx.globalAlpha = 1.0;

      // HUI-040：填充描边死值 #000000 → tokens.textPrimary
      ctx.strokeStyle = this.tokens ? this.tokens.textPrimary : '#000000';
      ctx.lineWidth = 2;
      ctx.beginPath();
      this.drawSketchRoundRect(ctx, 0, 0, fillW, h, 4);
      ctx.stroke();

      // 排线纹理
      // HUI-040：纹理死值 #FFFFFF → tokens.surface（在墨条上透出卡片底色，深浅两用）
      ctx.strokeStyle = this.tokens ? this.tokens.surface : '#FFFFFF';
      ctx.lineWidth = 0.8;
      ctx.globalAlpha = 0.3;
      for (let x: number = 4; x < fillW - 4; x += 5) {
        ctx.beginPath();
        ctx.moveTo(x, 1);
        ctx.lineTo(x + 8, h - 1);
        ctx.stroke();
      }
      ctx.globalAlpha = 1.0;
    }
  }

  // 手绘圆角矩形（带抖动）
  private drawSketchRoundRect(
    ctx: CanvasRenderingContext2D,
    x: number, y: number, w: number, h: number, r: number
  ): void {
    const wob: number = 2.5;
    ctx.moveTo(x + r + Math.sin(x * 0.5) * wob, y + Math.cos(y * 0.6) * wob);
    ctx.lineTo(x + w - r + Math.sin((x + w) * 0.4) * wob, y + Math.cos(y * 0.5) * wob);
    ctx.arcTo(x + w, y, x + w, y + r, r);
    ctx.lineTo(x + w + Math.sin((x + w) * 2) * wob, y + h - r + Math.cos((y + h) * 2) * wob);
    ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
    ctx.lineTo(x + r + Math.sin(x * 0.7) * wob, y + h + Math.cos((y + h) * 0.5) * wob);
    ctx.arcTo(x, y + h, x, y + h - r, r);
    ctx.lineTo(x + Math.sin(x * 2) * wob, y + r + Math.cos(y * 2) * wob);
    ctx.arcTo(x, y, x + r, y, r);
    ctx.closePath();
  }

  private onDataChange(): void { this.drawBar(); }

  // HUI-040：主题切换显式重绘（Canvas 不随 @StorageLink 变更自动刷新）
  private onThemeChange(): void { this.drawBar(); }

  build() {
    Column() {
      Row() {
        Text('待办完成')
          .fontSize(TYPO.sectionTitle.size)
          .fontWeight(TYPO.sectionTitle.weight)
          .fontFamily(FONT.sketchTitle + ', HarmonyOS Sans, sans-serif')
          .fontColor(this.tokens ? this.tokens.textPrimary : '#000000')
        Blank()
        Text(this.getPercentageText())
          .fontFamily(FONT.sketchTitle + ', HarmonyOS Sans, sans-serif')
          .fontSize(TYPO.numCard.size)
          .fontWeight(TYPO.numCard.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#000000')
      }
      .width('100%')
      .margin({ bottom: 12 })

      Canvas(this.ctx)
        .width(this.CANVAS_WIDTH)
        .height(this.BAR_HEIGHT)
        .onReady(() => { this.drawBar(); })
        .accessibilityText(this.getAccessibilityDescription())
        .accessibilityLevel('yes')

      Text(this.getCompletedText())
        .fontSize(TYPO.eyebrow.size)
        .fontFamily(FONT.sketchBody + ', HarmonyOS Sans, sans-serif')
        .fontColor(this.tokens ? this.tokens.textTertiary : '#888888')
        .margin({ top: 8 })
    }
    .width('100%')
    .borderRadius(14)
    .padding(SPACING.cardPadLg)
    .backgroundColor(this.tokens ? this.tokens.surface : '#FFFFFF')
    // HUI-032：不均匀加粗手绘边框 → 均匀细边框读 token，与其他页面卡片统一
    .border({ width: 1, color: this.tokens ? this.tokens.border : '#CCCCCC' })
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.15)', offsetX: 2, offsetY: 4 })
    .accessibilityGroup(true)
    .accessibilityText(this.getAccessibilityDescription())
  }
}
