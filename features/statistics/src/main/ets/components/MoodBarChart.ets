// <!-- agentID: HUI-007 -->
// fix: HUI-016
// 组件：黑白手绘心情气象分布条（Canvas）
// 关联任务：T-SKETCH 统计页黑白手绘风格
// API 24 Canvas：RenderingContextSettings 模式
// HUI-040：深色模式 P0 修复——Canvas 画笔读 token + tokens @Watch 显式重绘（darkmode_audit 问题2）

import type { ThemeColorTokens } from '@ohos/shared';
import { SPACING, TYPO, FONT, EventBus, getThemeManager } from '@ohos/shared';

// fix: HUI-016 · T-D03 —— 移除 MoodDataItem/ComputedBar 的 color 死字段（darkmode_audit A-5 埋雷）：
//   该字段从未参与绘制（黑白手绘主题下条形/图标一律走 tokens.textPrimary，语义区分由 label+手绘图标承担，
//   见 ThemePresets HUI-021 设计说明），仅由 StatisticsPage.mapEmojiToMood 灌入固定深灰死值。
//   若未来需要按心情着色，必须按 theme_tokens 换肤方案取色，禁止恢复硬编码（PROJECT_SPEC §8.2）。
export interface MoodDataItem {
  label: string;
  count: number;
  icon: Resource;
}

interface ComputedBar {
  label: string;
  countStr: string;
  barPercent: number;
}

@Component
export struct MoodBarChart {
  @Prop @Watch('refreshComputed') data: MoodDataItem[] = [];
  // HUI-040：@StorageLink 变更不会自动重画 Canvas，必须 @Watch 显式触发重绘（Canvas 换肤两件套之二）
  @StorageLink('theme_tokens') @Watch('onThemeChange') tokens: ThemeColorTokens | null = null;
  @State private computedBars: ComputedBar[] = [];
  @State private animateFill: boolean = false;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private readonly ROW_HEIGHT: number = 44;
  private readonly ICON_RADIUS: number = 7;
  private readonly BAR_HEIGHT: number = 10;

  aboutToAppear(): void {
    this.refreshComputed();
    // fix: HUI-016 · T-D01复测实证 —— 后台 TabContent 的 @StorageLink 收不到 theme_tokens 变更
    //   （详见 StatisticsPage.aboutToAppear 同款注释）：订阅 THEME_CHANGED 从 ThemeManager 真相源
    //   回读色板写回链接并显式重绘（Canvas 换肤两件套之二）。Tab 常驻组件不退订（DEV-003 先例）。
    EventBus.on(EventBus.EventNames.THEME_CHANGED, (data: Record<string, Object>) => {
      this.tokens = getThemeManager().getTokens();
      this.drawAllMoodBars();
    });
    animateTo({ duration: 650, curve: Curve.Friction }, () => { this.animateFill = true; });
  }

  private refreshComputed(): void {
    const maxCount: number = Math.max(1, ...this.data.map((d: MoodDataItem): number => d.count));
    const items: ComputedBar[] = [];
    for (let i = 0; i < this.data.length; i++) {
      const d: MoodDataItem = this.data[i];
      items.push({
        label: d.label,
        countStr: d.count.toString(),
        barPercent: Math.round(Math.max(6, d.count / maxCount * 100))
      });
    }
    this.computedBars = items;
    this.drawAllMoodBars();
  }

  // HUI-040：主题切换显式重绘（Canvas 不随 @StorageLink 变更自动刷新）
  private onThemeChange(): void { this.drawAllMoodBars(); }

  private getAccessibilitySummary(): string {
    let summary: string = '心情气象分布：';
    for (let i = 0; i < this.computedBars.length; i++) {
      const cb: ComputedBar = this.computedBars[i];
      summary += cb.label + cb.countStr + '次';
      if (i < this.computedBars.length - 1) { summary += '，'; }
    }
    return summary;
  }

  private drawAllMoodBars(): void {
    const ctx: CanvasRenderingContext2D = this.ctx;
    const rows: ComputedBar[] = this.computedBars;
    const canvasW: number = 310;
    const canvasH: number = rows.length * this.ROW_HEIGHT;
    const barStartX: number = 68;
    const barMaxW: number = canvasW - barStartX - 36;

    ctx.clearRect(0, 0, canvasW, canvasH);

    for (let i = 0; i < rows.length; i++) {
      const row: ComputedBar = rows[i];
      const y: number = i * this.ROW_HEIGHT;
      const cy: number = y + this.ROW_HEIGHT / 2;

      // 手绘心情图标
      this.drawSketchMoodIcon(ctx, 12, cy, this.ICON_RADIUS, row.label);

      // 心情标签
      ctx.font = '14px HarmonyOS Sans';
      // HUI-040：标签死值 #000000 → tokens.textPrimary
      ctx.fillStyle = this.tokens ? this.tokens.textPrimary : '#000000';
      ctx.textAlign = 'left';
      ctx.textBaseline = 'middle';
      ctx.fillText(row.label, 28, cy);

      // 背景轨道
      const barY: number = cy - this.BAR_HEIGHT / 2;
      // HUI-040：轨道死值 #CCCCCC → tokens.border
      ctx.strokeStyle = this.tokens ? this.tokens.border : '#CCCCCC';
      ctx.lineWidth = 1;
      ctx.beginPath();
      this.wobbleRoundRect(ctx, barStartX, barY, barMaxW, this.BAR_HEIGHT, 5);
      ctx.stroke();

      // 填充条
      const fillPercent: number = this.animateFill ? row.barPercent : 0;
      const fillW: number = Math.max(6, Math.round(barMaxW * fillPercent / 100));
      if (fillW > 0) {
        // HUI-040：填充条死值 #000000 → tokens.textPrimary（深色翻白）
        ctx.fillStyle = this.tokens ? this.tokens.textPrimary : '#000000';
        ctx.globalAlpha = 0.75;
        ctx.beginPath();
        this.wobbleRoundRect(ctx, barStartX, barY, fillW, this.BAR_HEIGHT, 4);
        ctx.fill();
        ctx.globalAlpha = 1.0;

        // 排线纹理
        // HUI-040：纹理死值 #FFFFFF → tokens.surface（在墨条上透出卡片底色，深浅两用）
        ctx.strokeStyle = this.tokens ? this.tokens.surface : '#FFFFFF';
        ctx.lineWidth = 0.6;
        ctx.globalAlpha = 0.25;
        for (let x: number = barStartX + 4; x < barStartX + fillW - 3; x += 5) {
          ctx.beginPath();
          ctx.moveTo(x, barY + 1);
          ctx.lineTo(x + 6, barY + this.BAR_HEIGHT - 1);
          ctx.stroke();
        }
        ctx.globalAlpha = 1.0;
      }

      // count 数字
      ctx.font = 'bold 14px HarmonyOS Sans';
      // HUI-040：count 死值 #000000 → tokens.textPrimary
      ctx.fillStyle = this.tokens ? this.tokens.textPrimary : '#000000';
      ctx.textAlign = 'right';
      ctx.fillText(row.countStr, canvasW - 4, cy);
    }
  }

  private drawSketchMoodIcon(
    ctx: CanvasRenderingContext2D, cx: number, cy: number,
    r: number, label: string
  ): void {
    // HUI-040：手绘图标死值 #000000 → tokens.textPrimary
    ctx.strokeStyle = this.tokens ? this.tokens.textPrimary : '#000000';
    ctx.lineWidth = 1.5;
    ctx.globalAlpha = 0.8;
    if (label === '开心') {
      ctx.beginPath(); ctx.arc(cx, cy, r * 0.65, 0, 2 * Math.PI); ctx.stroke();
      for (let j = 0; j < 4; j++) {
        const a: number = (j / 4) * 2 * Math.PI;
        ctx.beginPath();
        ctx.moveTo(cx + Math.cos(a) * r * 1.1, cy + Math.sin(a) * r * 1.1);
        ctx.lineTo(cx + Math.cos(a) * r * 1.5, cy + Math.sin(a) * r * 1.5);
        ctx.stroke();
      }
    } else if (label === '愉快') {
      ctx.beginPath();
      ctx.moveTo(cx, cy - r); ctx.lineTo(cx, cy + r);
      ctx.moveTo(cx - r, cy); ctx.lineTo(cx + r, cy);
      ctx.moveTo(cx - r * 0.7, cy - r * 0.7); ctx.lineTo(cx + r * 0.7, cy + r * 0.7);
      ctx.moveTo(cx + r * 0.7, cy - r * 0.7); ctx.lineTo(cx - r * 0.7, cy + r * 0.7);
      ctx.stroke();
    } else if (label === '甜蜜') {
      ctx.beginPath();
      ctx.moveTo(cx, cy + r * 0.5);
      ctx.arc(cx - r * 0.4, cy - r * 0.1, r * 0.4, Math.PI * 0.8, Math.PI * 2.2);
      ctx.arc(cx + r * 0.4, cy - r * 0.1, r * 0.4, Math.PI * 0.8, Math.PI * 2.2, true);
      ctx.closePath(); ctx.stroke();
    } else if (label === '平淡') {
      ctx.beginPath();
      ctx.arc(cx - r * 0.3, cy, r * 0.5, 0, 2 * Math.PI); ctx.stroke();
      ctx.beginPath(); ctx.arc(cx + r * 0.3, cy, r * 0.6, 0, 2 * Math.PI); ctx.stroke();
      ctx.beginPath(); ctx.arc(cx, cy - r * 0.3, r * 0.55, 0, 2 * Math.PI); ctx.stroke();
    } else if (label === '难过') {
      ctx.beginPath();
      ctx.moveTo(cx, cy + r);
      ctx.arc(cx, cy - r * 0.2, r * 0.5, Math.PI * 0.3, Math.PI * 0.7, true);
      ctx.closePath(); ctx.stroke();
    } else {
      ctx.beginPath(); ctx.arc(cx, cy, r * 0.65, 0, 2 * Math.PI); ctx.stroke();
    }
    ctx.globalAlpha = 1.0;
  }

  // 手绘圆角矩形（带抖动，模拟手绘涂色边缘）
  private wobbleRoundRect(
    ctx: CanvasRenderingContext2D,
    x: number, y: number, w: number, h: number, r: number
  ): void {
    const wob: number = 2.5;
    ctx.moveTo(x + r + Math.sin(x * 0.5) * wob, y + Math.cos(y * 0.6) * wob);
    ctx.lineTo(x + w - r + Math.sin((x + w) * 0.4) * wob, y + Math.cos(y * 0.5) * wob);
    ctx.arcTo(x + w + Math.sin((x + w) * 3) * wob * 0.5, y, x + w, y + r + Math.cos(y * 3) * wob * 0.5, r);
    ctx.lineTo(x + w + Math.sin((x + w) * 2) * wob, y + h - r + Math.cos((y + h) * 2) * wob);
    ctx.arcTo(x + w + Math.sin((x + w) * 3) * wob * 0.5, y + h, x + w - r + Math.cos((y + h) * 3) * wob * 0.5, y + h, r);
    ctx.lineTo(x + r + Math.sin(x * 0.7) * wob, y + h + Math.cos((y + h) * 0.5) * wob);
    ctx.arcTo(x + Math.sin(x * 3) * wob * 0.5, y + h, x, y + h - r + Math.cos((y + h) * 3) * wob * 0.5, r);
    ctx.lineTo(x + Math.sin(x * 2) * wob, y + r + Math.cos(y * 2) * wob);
    ctx.arcTo(x + Math.sin(x * 3) * wob * 0.5, y, x + r + Math.cos(y * 3) * wob * 0.5, y, r);
    ctx.closePath();
  }

  build() {
    Column() {
      Text('心情气象分布')
        .fontSize(TYPO.sectionTitle.size)
        .fontWeight(TYPO.sectionTitle.weight)
        .fontFamily(FONT.sketchTitle + ', HarmonyOS Sans, sans-serif')
        .fontColor(this.tokens ? this.tokens.textPrimary : '#000000')
        .width('100%')
        .margin({ bottom: SPACING.cardGap })

      Canvas(this.ctx)
        .width(310)
        .height(this.computedBars.length * this.ROW_HEIGHT)
        .onReady(() => { this.drawAllMoodBars(); })
        .accessibilityGroup(true)
        .accessibilityText(this.getAccessibilitySummary())
        .accessibilityLevel('yes')
    }
    .width('100%')
    .borderRadius(14)
    .padding(SPACING.cardPadLg)
    .backgroundColor(this.tokens ? this.tokens.surface : '#FFFFFF')
    // HUI-032：不均匀加粗手绘边框 → 均匀细边框读 token，与其他页面卡片统一
    .border({ width: 1, color: this.tokens ? this.tokens.border : '#CCCCCC' })
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.15)', offsetX: 2, offsetY: 4 })
    .accessibilityGroup(true)
    .accessibilityText('心情气象分布')
  }
}
