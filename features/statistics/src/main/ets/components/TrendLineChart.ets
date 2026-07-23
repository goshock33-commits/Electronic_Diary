// <!-- agentID: HUI-001 -->
// 组件：统计页四线趋势曲线图 —— "一支笔画出来"的入场动画
// 关联任务：统计页顶部四卡 → 四线生长曲线图（用户锁定规格）
// Skill 参考：dataviz / frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式 (Stage 模型)
//
// 实现要点：
// - 动画驱动：displaySync 帧回调（@kit.ArkGraphics2D，vsync 对齐，API 24 本地 .d.ts 已验证
//   create/setExpectedFrameRateRange/on('frame')/start/stop/off），aboutToDisappear 必停（PROJECT_SPEC §9 清理）。
// - 曲线：Catmull-Rom → 三次贝塞尔逐段采样为致密折线，progress 0→1 截取部分路径 = 四线同时"生长"，
//   不填充面积；采样点同时给出铅笔尖端坐标（贴打卡主线尖端，固定 45° 执笔角——沿切线旋转在 0/1
//   锯齿线上会疯转，手写观感反而差）。
// - 铅笔：Canvas 简笔（石墨芯+削木锥+六棱笔杆+橡皮头）。本地图标库无独立 pencil
//   （仅 doc_plaintext_and_pencil L872 / pencil_line_1 L1574 / square_and_pencil L1598 等复合图标），
//   且同帧绘制才能精确贴住尖端，故弃 SymbolGlyph 方案。
// - 重播：进页/切 Tab（onVisibleAreaChange 越 0.4 阈值）+ 数据版本变更（7/30 切档、事件订阅刷新）都重播。
// - dataviz 规范落地：2vp 线宽圆角端点；≥2 系列必配图例（图例带总数，文字走 text tokens 不穿数据色，
//   线样承载身份）；网格 hairline 实线内敛；终点标记带 2vp surface 环；灰阶+虚实=次级编码
//   （validate_palette.js 实测：两版对比度均 ≥3:1，CVD floor 依线型次级编码合法化；
//   零色度/亮度带外属项目黑白灰主题既定约束）。
// - 深浅色：双灰阶（浅 #111111/#4D4D4D/#757575/#8A8A8A · 深 #F0F0F0/#C2C2C2/#9A9A9A/#7A7A7A），
//   theme_is_dark + THEME_CHANGED 双通道刷新（Canvas 换肤两件套，MoodBarChart HUI-040 先例）。
// - §9.1：build 内不经 getter 取值，一律方法调用/内联三元。

import type { ThemeColorTokens } from '@ohos/shared';
import { RADIUS, SPACING, TYPO, FONT, EventBus, getThemeManager } from '@ohos/shared';
import { displaySync } from '@kit.ArkGraphics2D';

// 与 DEV-004 DailyStatsSeries 契约字段一致（组件侧独立声明，保持组件可独立编译/预览）
export interface TrendChartData {
  dates: string[];
  checkIn: number[];
  diary: number[];
  pomodoro: number[];
  todoDone: number[];
  totalCheckInDays: number;
  totalDiary: number;
  totalPomodoro: number;
  totalTodoDone: number;
}

interface TipPoint {
  x: number;
  y: number;
}

@Component
export struct TrendLineChart {
  // 数据（页面从 StatisticsViewModel.getDailySeries 映射灌入）
  @Prop chartData: TrendChartData = {
    dates: [], checkIn: [], diary: [], pomodoro: [], todoDone: [],
    totalCheckInDays: 0, totalDiary: 0, totalPomodoro: 0, totalTodoDone: 0
  };
  // 数据版本号：页面每次成功拉数 +1 → 触发重播（同日刷新时 dates 不变，watch 版本号才可靠）
  @Prop @Watch('onDataChange') dataVersion: number = 0;
  // 7/30 档选择（真相源在页面，组件只回调）
  @Prop selectedDays: number = 7;
  onRangeChange: (days: number) => void = (days: number): void => {};

  // Canvas 换肤两件套（MoodBarChart HUI-040 先例）：@StorageLink 变更不会自动重画 Canvas，@Watch 显式重绘
  @StorageLink('theme_tokens') @Watch('onThemeChange') tokens: ThemeColorTokens | null = null;
  @StorageLink('theme_is_dark') @Watch('onThemeChange') isDark: boolean = false;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  // ── 灰阶方案（dataviz validate_palette.js 已验证，对比度两版全 ≥3:1）──
  // 顺序：打卡(纯黑实线) / 日记(深灰实线) / 番茄钟(中灰虚线) / 完成待办(浅灰点线)；深色反相
  private readonly LIGHT_COLORS: string[] = ['#111111', '#4D4D4D', '#757575', '#8A8A8A'];
  private readonly DARK_COLORS: string[] = ['#F0F0F0', '#C2C2C2', '#9A9A9A', '#7A7A7A'];
  private readonly DASHES: number[][] = [[], [], [6, 4], [2, 4]];
  private readonly NAMES: string[] = ['打卡', '日记', '番茄钟', '完成待办'];

  private readonly CHART_H: number = 190;
  private readonly PAD_L: number = 8;
  private readonly PAD_R: number = 16;
  private readonly PAD_T: number = 18;
  private readonly PAD_B: number = 26;
  private readonly SEG_SAMPLES: number = 12;
  private readonly DURATION_MS: number = 1500;

  // 采样缓存（4 条致密折线），plain 字段——Canvas 全程命令式绘制，不走 @State
  private sampX: number[][] = [];
  private sampY: number[][] = [];
  private cachedW: number = 0;

  // 动画驱动
  private dSync: displaySync.DisplaySync | null = null;
  private animStartMs: number = 0;
  private lastPlayMs: number = 0;
  private animating: boolean = false;

  aboutToAppear(): void {
    // Tab 常驻组件后台收不到 @StorageLink 主题变更 → 订阅 THEME_CHANGED 从真相源回读并显式重绘
    //（StatisticsPage / MoodBarChart 同款注释与先例；off 按事件名全量退订会误伤，故不退订）
    EventBus.on(EventBus.EventNames.THEME_CHANGED, (data: Record<string, Object>) => {
      this.tokens = getThemeManager().getTokens();
      this.isDark = getThemeManager().isDarkMode();
      if (!this.animating) { this.drawChart(1); }
    });
  }

  aboutToDisappear(): void {
    // §9 清理：帧回调必停必解绑，防泄漏
    if (this.dSync !== null) {
      this.dSync.stop();
      this.dSync.off('frame');
      this.dSync = null;
    }
    this.animating = false;
  }

  // ══════════════ 数据/主题变更 ══════════════

  private onDataChange(): void {
    this.lastPlayMs = 0; // 数据到达必重播，绕过双触发防抖
    this.startDrawAnimation();
  }

  private onThemeChange(): void {
    if (!this.animating) { this.drawChart(1); }
  }

  // ══════════════ 动画驱动（displaySync 帧回调）══════════════

  private startDrawAnimation(): void {
    if (this.ctx.width <= 0) { return; } // onReady 前无画布尺寸，等 onReady 再启动
    const now: number = Date.now();
    if (now - this.lastPlayMs < 300) { return; } // onReady 与 onVisibleAreaChange 同帧双触发防抖
    this.lastPlayMs = now;
    this.prepareSamples();
    if (this.sampX.length === 0) { this.drawChart(1); return; } // 无数据画静态空态
    this.animStartMs = now;
    this.animating = true;
    if (this.dSync === null) {
      this.dSync = displaySync.create();
      const range: ExpectedFrameRateRange = { expected: 60, min: 30, max: 120 };
      this.dSync.setExpectedFrameRateRange(range);
      this.dSync.on('frame', (info: displaySync.IntervalInfo) => { this.onFrame(); });
    } else {
      this.dSync.stop();
    }
    this.dSync.start();
  }

  private onFrame(): void {
    const t: number = (Date.now() - this.animStartMs) / this.DURATION_MS;
    if (t >= 1) {
      this.animating = false;
      this.drawChart(1);
      if (this.dSync !== null) { this.dSync.stop(); }
      return;
    }
    this.drawChart(this.easeInOutCubic(t));
  }

  private easeInOutCubic(t: number): number {
    return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
  }

  // ══════════════ 采样：Catmull-Rom → 贝塞尔 → 致密折线 ══════════════

  private seriesValues(idx: number): number[] {
    if (idx === 0) { return this.chartData.checkIn; }
    if (idx === 1) { return this.chartData.diary; }
    if (idx === 2) { return this.chartData.pomodoro; }
    return this.chartData.todoDone;
  }

  private seriesTotal(idx: number): number {
    if (idx === 0) { return this.chartData.totalCheckInDays; }
    if (idx === 1) { return this.chartData.totalDiary; }
    if (idx === 2) { return this.chartData.totalPomodoro; }
    return this.chartData.totalTodoDone;
  }

  private seriesColor(idx: number): string {
    return this.isDark ? this.DARK_COLORS[idx] : this.LIGHT_COLORS[idx];
  }

  private prepareSamples(): void {
    this.sampX = [];
    this.sampY = [];
    const w: number = this.ctx.width;
    this.cachedW = w;
    const n: number = this.chartData.dates.length;
    if (n < 2 || w <= this.PAD_L + this.PAD_R) { return; }
    const plotW: number = w - this.PAD_L - this.PAD_R;
    const plotH: number = this.CHART_H - this.PAD_T - this.PAD_B;
    for (let s = 0; s < 4; s++) {
      const values: number[] = this.seriesValues(s);
      const m: number = Math.min(n, values.length);
      if (m < 2) { this.sampX = []; this.sampY = []; return; }
      // 逐系列归一化到各自峰值（无 y 轴刻度、总数由图例承载，四线只讲各自走势——单轴铁律不破）
      let maxV: number = 1;
      for (let i = 0; i < m; i++) { maxV = Math.max(maxV, values[i]); }
      const px: number[] = [];
      const py: number[] = [];
      for (let i = 0; i < m; i++) {
        px.push(this.PAD_L + (plotW * i) / (m - 1));
        py.push(this.PAD_T + (1 - values[i] / maxV) * plotH);
      }
      // Catmull-Rom 平滑：段控制点 c1 = p1+(p2-p0)/6, c2 = p2-(p3-p1)/6，逐段采样
      const outX: number[] = [px[0]];
      const outY: number[] = [py[0]];
      for (let i = 0; i < m - 1; i++) {
        const i0: number = Math.max(i - 1, 0);
        const i3: number = Math.min(i + 2, m - 1);
        const c1x: number = px[i] + (px[i + 1] - px[i0]) / 6;
        const c1y: number = py[i] + (py[i + 1] - py[i0]) / 6;
        const c2x: number = px[i + 1] - (px[i3] - px[i]) / 6;
        const c2y: number = py[i + 1] - (py[i3] - py[i]) / 6;
        for (let k = 1; k <= this.SEG_SAMPLES; k++) {
          const t: number = k / this.SEG_SAMPLES;
          const u: number = 1 - t;
          const bx: number = u * u * u * px[i] + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * px[i + 1];
          let by: number = u * u * u * py[i] + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * py[i + 1];
          // 平滑不越界：夹回绘图区，避免 0/1 锯齿过冲画出轴外
          by = Math.min(Math.max(by, this.PAD_T - 2), this.PAD_T + plotH + 2);
          outX.push(bx);
          outY.push(by);
        }
      }
      this.sampX.push(outX);
      this.sampY.push(outY);
    }
  }

  // ══════════════ 绘制 ══════════════

  private drawChart(progress: number): void {
    const ctx: CanvasRenderingContext2D = this.ctx;
    const w: number = ctx.width;
    const h: number = this.CHART_H;
    if (w <= 0) { return; }
    if (Math.abs(w - this.cachedW) > 1) { this.prepareSamples(); }
    const inkGrid: string = this.tokens ? this.tokens.border : '#CCCCCC';
    const inkHint: string = this.tokens ? this.tokens.textTertiary : '#888888';

    ctx.clearRect(0, 0, w, h);

    // 网格：hairline 实线，内敛（dataviz：1vp、不虚线、退居背景）
    const plotH: number = h - this.PAD_T - this.PAD_B;
    ctx.lineWidth = 1;
    ctx.strokeStyle = inkGrid;
    ctx.globalAlpha = 0.45;
    ctx.setLineDash([]);
    for (let g = 0; g <= 3; g++) {
      const gy: number = this.PAD_T + (plotH * g) / 3;
      ctx.beginPath();
      ctx.moveTo(this.PAD_L, gy);
      ctx.lineTo(w - this.PAD_R, gy);
      ctx.stroke();
    }
    ctx.globalAlpha = 1.0;

    // 空态
    if (this.sampX.length === 0) {
      ctx.font = '12px HarmonyOS Sans';
      ctx.fillStyle = inkHint;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('暂无趋势数据', w / 2, h / 2 - 6);
      this.drawDateLabels(w, h, inkHint);
      return;
    }

    this.drawDateLabels(w, h, inkHint);

    // 四条曲线同时生长（部分路径截取）
    ctx.lineWidth = 2;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    for (let s = 0; s < 4; s++) {
      this.strokePartialPath(s, progress);
    }

    if (progress >= 1) {
      // 终点标记：≥8vp 圆点 + 2vp surface 环（dataviz surface-ring 规则）
      const paper: string = this.tokens ? this.tokens.surface : '#FFFFFF';
      for (let s = 0; s < 4; s++) {
        const xs: number[] = this.sampX[s];
        const ys: number[] = this.sampY[s];
        const last: number = xs.length - 1;
        ctx.setLineDash([]);
        ctx.beginPath();
        ctx.arc(xs[last], ys[last], 4, 0, 2 * Math.PI);
        ctx.fillStyle = this.seriesColor(s);
        ctx.fill();
        ctx.lineWidth = 2;
        ctx.strokeStyle = paper;
        ctx.stroke();
      }
      ctx.lineWidth = 2;
    } else {
      // 铅笔贴打卡主线（series 0）尖端
      const tip: TipPoint = this.tipOf(0, progress);
      this.drawPencil(tip.x, tip.y);
    }
  }

  private drawDateLabels(w: number, h: number, ink: string): void {
    const ctx: CanvasRenderingContext2D = this.ctx;
    const n: number = this.chartData.dates.length;
    if (n < 2) { return; }
    ctx.font = '9px HarmonyOS Sans';
    ctx.fillStyle = ink;
    ctx.textBaseline = 'bottom';
    const ticks: number = n <= 7 ? 3 : 4;
    const plotW: number = w - this.PAD_L - this.PAD_R;
    for (let k = 0; k < ticks; k++) {
      const idx: number = Math.round((k * (n - 1)) / (ticks - 1));
      const x: number = this.PAD_L + (plotW * idx) / (n - 1);
      ctx.textAlign = k === 0 ? 'left' : (k === ticks - 1 ? 'right' : 'center');
      ctx.fillText(this.shortDate(this.chartData.dates[idx]), x, h - 6);
    }
  }

  // "YYYY-MM-DD" → "M/D"（识别失败原样返回）
  private shortDate(d: string): string {
    if (d.length >= 10 && d.charAt(4) === '-') {
      const mm: number = parseInt(d.substring(5, 7), 10);
      const dd: number = parseInt(d.substring(8, 10), 10);
      if (!isNaN(mm) && !isNaN(dd)) { return mm.toString() + '/' + dd.toString(); }
    }
    return d;
  }

  private strokePartialPath(s: number, progress: number): void {
    const ctx: CanvasRenderingContext2D = this.ctx;
    const xs: number[] = this.sampX[s];
    const ys: number[] = this.sampY[s];
    const m: number = xs.length;
    if (m < 2) { return; }
    const kFloat: number = progress * (m - 1);
    const kInt: number = Math.floor(kFloat);
    ctx.strokeStyle = this.seriesColor(s);
    ctx.setLineDash(this.DASHES[s]);
    ctx.beginPath();
    ctx.moveTo(xs[0], ys[0]);
    for (let j = 1; j <= kInt; j++) { ctx.lineTo(xs[j], ys[j]); }
    if (kInt < m - 1) {
      const frac: number = kFloat - kInt;
      ctx.lineTo(xs[kInt] + (xs[kInt + 1] - xs[kInt]) * frac, ys[kInt] + (ys[kInt + 1] - ys[kInt]) * frac);
    }
    ctx.stroke();
    ctx.setLineDash([]);
  }

  private tipOf(s: number, progress: number): TipPoint {
    const xs: number[] = this.sampX[s];
    const ys: number[] = this.sampY[s];
    const m: number = xs.length;
    const kFloat: number = progress * (m - 1);
    const kInt: number = Math.min(Math.floor(kFloat), m - 2);
    const frac: number = kFloat - kInt;
    return {
      x: xs[kInt] + (xs[kInt + 1] - xs[kInt]) * frac,
      y: ys[kInt] + (ys[kInt + 1] - ys[kInt]) * frac
    };
  }

  // Canvas 简笔铅笔：以 (0,0) 为笔尖，固定 45° 执笔角向右上倾斜（手写观感）
  private drawPencil(x: number, y: number): void {
    const ctx: CanvasRenderingContext2D = this.ctx;
    const ink: string = this.tokens ? this.tokens.textPrimary : '#000000';
    const paper: string = this.tokens ? this.tokens.surface : '#FFFFFF';
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(-Math.PI / 4);
    ctx.lineWidth = 1.2;
    ctx.strokeStyle = ink;
    // 削木锥段（纸色填充 + 墨描边）
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(10, -3.5);
    ctx.lineTo(10, 3.5);
    ctx.closePath();
    ctx.fillStyle = paper;
    ctx.fill();
    ctx.stroke();
    // 石墨芯
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(3.5, -1.4);
    ctx.lineTo(3.5, 1.4);
    ctx.closePath();
    ctx.fillStyle = ink;
    ctx.fill();
    // 笔杆
    ctx.beginPath();
    ctx.rect(10, -3.5, 18, 7);
    ctx.fillStyle = paper;
    ctx.fill();
    ctx.stroke();
    // 笔杆棱线（弱化）
    ctx.globalAlpha = 0.3;
    ctx.beginPath();
    ctx.moveTo(10, -1.2);
    ctx.lineTo(28, -1.2);
    ctx.moveTo(10, 1.2);
    ctx.lineTo(28, 1.2);
    ctx.stroke();
    ctx.globalAlpha = 1.0;
    // 橡皮头
    ctx.beginPath();
    ctx.rect(28, -3.5, 4, 7);
    ctx.fillStyle = ink;
    ctx.globalAlpha = 0.5;
    ctx.fill();
    ctx.globalAlpha = 1.0;
    ctx.stroke();
    ctx.restore();
  }

  // ══════════════ 无障碍 ══════════════

  private getA11ySummary(): string {
    return '数据趋势，近' + this.selectedDays.toString() + '天：打卡' + this.chartData.totalCheckInDays.toString() +
      '天，日记' + this.chartData.totalDiary.toString() + '篇，番茄钟' + this.chartData.totalPomodoro.toString() +
      '个，完成待办' + this.chartData.totalTodoDone.toString() + '项';
  }

  // ══════════════ @Builder ══════════════

  @Builder rangePill(label: string, days: number) {
    Text(label)
      .fontSize(11)
      .fontWeight(this.selectedDays === days ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.selectedDays === days
        ? (this.tokens ? this.tokens.surface : '#FFFFFF')
        : (this.tokens ? this.tokens.textSecondary : '#555555'))
      .backgroundColor(this.selectedDays === days
        ? (this.tokens ? this.tokens.textPrimary : '#000000')
        : Color.Transparent)
      .borderRadius(12)
      .border({ width: 1, color: this.selectedDays === days
        ? (this.tokens ? this.tokens.textPrimary : '#000000')
        : (this.tokens ? this.tokens.border : '#CCCCCC') })
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .onClick(() => {
        if (this.selectedDays !== days) { this.onRangeChange(days); }
      })
      .accessibilityText('近' + days.toString() + '天' + (this.selectedDays === days ? '，已选中' : ''))
  }

  @Builder legendItem(idx: number) {
    Row() {
      // 线样示例承载身份（mark 带色），文字走 text tokens（dataviz：文字不穿数据色）
      Line({ width: 20, height: 8 })
        .startPoint([0, 4])
        .endPoint([20, 4])
        .stroke(this.seriesColor(idx))
        .strokeWidth(2)
        .strokeLineCap(LineCapStyle.Round)
        .strokeDashArray(this.DASHES[idx])
      Text(this.NAMES[idx])
        .fontSize(TYPO.eyebrow.size)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#555555')
        .margin({ left: 6 })
      Text(' · ')
        .fontSize(TYPO.eyebrow.size)
        .fontColor(this.tokens ? this.tokens.textTertiary : '#888888')
      Text(this.seriesTotal(idx).toString())
        .fontFamily(FONT.monoBold)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#000000')
    }
    .layoutWeight(1)
    .alignItems(VerticalAlign.Center)
    .accessibilityGroup(true)
    .accessibilityText(this.NAMES[idx] + '：' + this.seriesTotal(idx).toString())
  }

  build() {
    Column() {
      // Header：标题 + 7/30 小胶囊
      Row() {
        Text('数据趋势')
          .fontSize(TYPO.sectionTitle.size)
          .fontWeight(TYPO.sectionTitle.weight)
          .fontFamily(FONT.sketchTitle + ', HarmonyOS Sans, sans-serif')
          .fontColor(this.tokens ? this.tokens.textPrimary : '#000000')
        Blank()
        Row({ space: 6 }) {
          this.rangePill('7天', 7)
          this.rangePill('30天', 30)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Canvas(this.ctx)
        .width('100%')
        .height(this.CHART_H)
        .margin({ top: SPACING.cardGap })
        .onReady(() => { this.startDrawAnimation(); })
        .accessibilityGroup(true)
        .accessibilityText(this.getA11ySummary())
        .accessibilityLevel('yes')

      // 图例 2×2（带总数，承接原四卡数字）
      Row() {
        this.legendItem(0)
        this.legendItem(1)
      }
      .width('100%')
      .margin({ top: SPACING.cardGap })

      Row() {
        this.legendItem(2)
        this.legendItem(3)
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .borderRadius(RADIUS.card)
    .padding(SPACING.cardPadLg)
    .backgroundColor(this.tokens ? this.tokens.surface : '#FFFFFF')
    .border({ width: 1, color: this.tokens ? this.tokens.border : '#CCCCCC' })
    // 进页/切 Tab 重播：Tab 常驻不重建，aboutToAppear 只走一次；以可见面积越 0.4 阈值为"进页"信号
    .onVisibleAreaChange([0.0, 0.4], (isVisible: boolean, currentRatio: number) => {
      if (isVisible && currentRatio >= 0.4) { this.startDrawAnimation(); }
    })
  }
}
