// <!-- agentID: HUI-062 -->
// 组件：番茄钟圆形倒计时进度环（复刻 P2-10 薄荷青皮肤）
// 关联任务：F13 第6批 → P2-10 重做（eyebrow+H1 shell 在 PomodoroPage）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 令牌：IconMapper / RADIUS / SPACING / TYPO / FONT —— 全引用，禁散写魔数
// 图标：play_fill(PLAY✅) / pause(PAUSE✅) / arrow_counterclockwise(STOP✅) / clock_fill(CLOCK✅)
//   注：本地库无 stop_circle_fill（grep 0 命中，ERROR_PREVENTION#4），停止改用 arrow_counterclockwise。
//
// === 皮肤 §6.4（薄荷青统一）===
//   环形进度主色 tokens.primary（晨露 #00C2B8），轨道 tokens.accent（#E6F9F8）
//   不再使用三色阈值（绿/黄/红）；全时段薄荷青。
//   中央倒计时：60fp / 900 / FONT.monoExtraBold / primary 色（numHero 放大到 60fp）
//
// === Canvas 绘制 ===
//   环形进度使用 CanvasRenderingContext2D 绘制，12 点钟方向顺时针。
//   drawTimerRing() 在 remainingSeconds 变更时重绘（startTimer 内 decrement 后、
//   handleReset / handlePlayPause 后调用），配合 .onReady 首帧绘制。
//   画布尺寸放大到 280vp（对齐「巨型青环形进度」要求）。
//
// === 完成 ping 动效 ===
//   remainingSeconds 归零时触发：在圆环后方渲染一枚青色半透明圆，从 scale 1→2 扩散并 0.35→0 淡出
//   （animateTo 900ms EaseOut），原型「双层 ping+pulse」简化版。
//
// === 按钮组 ===
//   停止按钮（左，arrow_counterclockwise / IconMapper.STOP，48vp 圆，secondary 底）
//   播放/暂停切换按钮（中右，play_fill / pause，56vp 圆，primary 底 + primary 染色阴影）
//
// === 统计 ===
//   本轮番茄数（currentRound）+ 累计番茄数（cumulativeCount），FONT.monoBold 加粗数字。
//
// === 崩溃防范（PROJECT_SPEC §9）===
//   §9.1 无 getter-in-build：formatTime/getStatusText 为普通方法显式调用
//   §9.2 @Prop 默认值不含 $r()：均为原始类型
//   §9.3 字段初值不含 $r()：$r() 仅内联于 build 或 aboutToAppear
//   §9.4 @StorageLink('theme_tokens') 判空：this.tokens ? this.tokens.x : '#fallback'
//   定时器：aboutToDisappear 清理 setInterval
//   无障碍：按钮触控热区 >= 48x48vp，含 accessibilityText

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-027：引入手绘正文字体助手 SKETCH_BODY=清松手写体2(状态字/统计标签)；倒计时 MM:SS 与统计数字保留 FONT.mono*(等宽) 不动。
import { IconMapper, RADIUS, SPACING, TYPO, FONT, SKETCH_BODY } from '@ohos/shared';

@Component
export struct PomodoroTimer {
  /** 倒计时总秒数（默认 25min = 1500s）
   *  HUI-001：加 @Watch —— 同一实例上 totalSeconds 变化（如自定义分钟改值）时重置计时，
   *  行为对齐现有「切预设组件重建 → aboutToAppear 重新初始化」通路（停表、回满、重绘）。 */
  @Prop @Watch('onTotalSecondsChange') totalSeconds: number = 1500;
  /** 本轮已完成番茄数（父组件传入 mock 值） */
  @Prop currentRound: number = 1;
  /** 累计番茄数（父组件传入 mock 值） */
  @Prop cumulativeCount: number = 12;
  /** 当前剩余秒数 */
  @State remainingSeconds: number = 1500;
  /** 是否正在运行 */
  @State isRunning: boolean = false;
  /** 是否暂停 */
  @State isPaused: boolean = false;

  /** 开始回调 */
  onStart?: () => void;
  /** 暂停回调 */
  onPause?: () => void;
  /** 重置回调 */
  onReset?: () => void;
  /** 计时完成回调 */
  onComplete?: () => void;

  /** 主题 token（从 AppStorage 注入） */
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  // ── Canvas 上下文 ──
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  // ── 计时器 ──
  private timerId: number = -1;

  // ── 完成 ping 动效状态 ──
  @State pingScale: number = 1;
  @State pingOpacity: number = 0;
  /** 是否刚完成一次（用于短暂展示「完成」文案） */
  @State justCompleted: boolean = false;
  private clearCompleteId: number = -1;

  // ════════════════════════════════════════════════════════════
  // 生命周期
  // ════════════════════════════════════════════════════════════

  aboutToAppear(): void {
    this.remainingSeconds = this.totalSeconds;
  }

  aboutToDisappear(): void {
    this.stopTimer();
    if (this.clearCompleteId >= 0) {
      clearTimeout(this.clearCompleteId);
      this.clearCompleteId = -1;
    }
  }

  /**
   * HUI-001：@Watch 回调 —— totalSeconds 在同一实例上变更（自定义分钟改值）时重置计时。
   * 语义对齐现有切预设：组件重建后 isRunning=false / remaining=total / 环回满。
   * 不触发 onReset 回调（与重建通路一致，重建也不会回调）。
   */
  onTotalSecondsChange(): void {
    this.stopTimer();
    this.isRunning = false;
    this.isPaused = false;
    this.justCompleted = false;
    this.remainingSeconds = this.totalSeconds;
    this.drawTimerRing();
  }

  // ════════════════════════════════════════════════════════════
  // 派生值（§9.1 全部普通方法，禁 getter-in-build）
  // ════════════════════════════════════════════════════════════

  /** 获取主色（primary / fallback #00C2B8） */
  private getPrimary(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  /** 获取 accent 色（轨道底 / fallback #E6F9F8） */
  private getAccent(): string {
    return this.tokens ? this.tokens.accent : '#E6F9F8';
  }

  /** 获取次要文字色（textSecondary / fallback #5A5A5A） */
  private getTextSecondary(): string {
    return this.tokens ? this.tokens.textSecondary : '#5A5A5A';
  }

  /** 获取主要文字色（textPrimary / fallback #1A1A1A） */
  private getTextPrimary(): string {
    return this.tokens ? this.tokens.textPrimary : '#1A1A1A';
  }

  /** 获取表面色（surface / fallback #F5F5F5） */
  private getSurface(): string {
    return this.tokens ? this.tokens.surface : '#F5F5F5';
  }

  /** 获取阴影色（shadow / fallback rgba primary tint） */
  private getShadowColor(): string {
    return this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)';
  }

  /** 格式化剩余秒数为 MM:SS */
  private formatTime(): string {
    const m: number = Math.floor(this.remainingSeconds / 60);
    const s: number = this.remainingSeconds % 60;
    return String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
  }

  /** 状态描述文字 */
  private getStatusText(): string {
    if (this.justCompleted) {
      return '完成！';
    }
    if (this.isRunning && !this.isPaused) {
      return '专注中';
    }
    if (this.isPaused) {
      return '已暂停';
    }
    return '准备开始';
  }

  // ════════════════════════════════════════════════════════════
  // Canvas 环形进度绘制（薄荷青统一，无三色阈值）
  // ════════════════════════════════════════════════════════════

  /**
   * 绘制倒计时环形进度。
   * 背景环 accent（#E6F9F8）+ 前景弧 primary（#00C2B8），从 12 点钟顺时针。
   * 画布 280vp，线宽 14vp，薄荷青统一。
   */
  private drawTimerRing(): void {
    const canvasSize: number = 280;
    const centerX: number = canvasSize / 2;
    const centerY: number = canvasSize / 2;
    const strokeWidth: number = 14;
    const radius: number = (canvasSize - strokeWidth) / 2 - 6;

    this.ctx.clearRect(0, 0, canvasSize, canvasSize);

    // 背景环：accent（薄荷青浅底 #E6F9F8）
    this.ctx.beginPath();
    this.ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
    this.ctx.strokeStyle = this.getAccent();
    this.ctx.lineWidth = strokeWidth;
    this.ctx.lineCap = 'round';
    this.ctx.stroke();

    // 前景进度弧（从顶部顺时针）：primary 薄荷青 #00C2B8
    const progress: number = this.totalSeconds > 0
      ? this.remainingSeconds / this.totalSeconds
      : 0;
    const startAngle: number = -Math.PI / 2;
    const endAngle: number = startAngle + (2 * Math.PI * progress);

    if (progress > 0.001) {
      this.ctx.beginPath();
      this.ctx.arc(centerX, centerY, radius, startAngle, endAngle);
      this.ctx.strokeStyle = this.getPrimary();
      this.ctx.lineWidth = strokeWidth;
      this.ctx.lineCap = 'round';
      this.ctx.stroke();
    }
  }

  // ════════════════════════════════════════════════════════════
  // 计时逻辑（mock setInterval）
  // ════════════════════════════════════════════════════════════

  private startTimer(): void {
    this.stopTimer();
    this.timerId = setInterval(() => {
      if (!this.isRunning || this.isPaused) {
        return;
      }
      this.remainingSeconds--;
      // 每次秒数变更后重绘环形进度
      this.drawTimerRing();
      if (this.remainingSeconds <= 0) {
        this.remainingSeconds = 0;
        this.stopTimer();
        this.isRunning = false;
        this.isPaused = false;
        this.drawTimerRing();
        // 触发完成 ping 动效
        this.triggerPingEffect();
        // 短暂展示「完成」文案（1.2s 后恢复为「准备开始」）
        this.justCompleted = true;
        if (this.clearCompleteId >= 0) {
          clearTimeout(this.clearCompleteId);
        }
        this.clearCompleteId = setTimeout(() => {
          this.justCompleted = false;
        }, 1200);
        if (this.onComplete) {
          this.onComplete();
        }
      }
    }, 1000);
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  // ════════════════════════════════════════════════════════════
  // 完成 ping 动效（青色圆缩放 + 淡出，900ms EaseOut）
  // ════════════════════════════════════════════════════════════

  private triggerPingEffect(): void {
    // 起始状态
    this.pingScale = 0.85;
    this.pingOpacity = 0.35;
    // 动画扩散
    animateTo({ duration: 900, curve: Curve.EaseOut }, () => {
      this.pingScale = 2.0;
      this.pingOpacity = 0;
    });
  }

  // ════════════════════════════════════════════════════════════
  // 事件处理
  // ════════════════════════════════════════════════════════════

  private handlePlayPause(): void {
    if (this.isRunning && !this.isPaused) {
      // 运行中 → 暂停
      this.isPaused = true;
      this.stopTimer();
      if (this.onPause) {
        this.onPause();
      }
    } else {
      // 未开始 或 暂停中 → 运行
      this.justCompleted = false;
      this.isRunning = true;
      this.isPaused = false;
      if (this.remainingSeconds <= 0) {
        // 倒计时已归零，重置
        this.remainingSeconds = this.totalSeconds;
        this.drawTimerRing();
      }
      this.startTimer();
      if (this.onStart) {
        this.onStart();
      }
    }
  }

  private handleStop(): void {
    this.isRunning = false;
    this.isPaused = false;
    this.justCompleted = false;
    this.remainingSeconds = this.totalSeconds;
    this.stopTimer();
    this.drawTimerRing();
    if (this.onReset) {
      this.onReset();
    }
  }

  // ════════════════════════════════════════════════════════════
  // @Builder：统计行（本轮 / 累计）
  // ════════════════════════════════════════════════════════════

  @Builder
  statItem(value: number, label: string) {
    Column() {
      Text(value.toString())
        .fontFamily(FONT.monoBold)
        .fontSize(TYPO.numCard.size)
        .fontWeight(TYPO.numCard.weight)
        .fontColor(this.getTextPrimary())
      Text(label)
        .fontSize(TYPO.eyebrow.size)
        .fontWeight(TYPO.eyebrow.weight)
        .fontColor(this.getTextSecondary())
        .margin({ top: 2 })
        .attributeModifier(SKETCH_BODY) // HUI-027：统计中文标签(本轮/累计)→清松手写体2；上方数字保留 mono
    }
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 20, right: 20 })
  }

  // ════════════════════════════════════════════════════════════
  // 主 build
  // ════════════════════════════════════════════════════════════

  build() {
    Column() {
      // ── 巨型环形进度 + 中央倒计时 + ping 动效圈 ──
      Stack({ alignContent: Alignment.Center }) {
        // 完成 ping 扩散圆（环形后方、淡出）
        if (this.pingOpacity > 0.001) {
          Stack()
            .width(280)
            .height(280)
            .borderRadius(140)
            .backgroundColor(this.getPrimary())
            .opacity(this.pingOpacity)
            .scale({ x: this.pingScale, y: this.pingScale })
            .hitTestBehavior(HitTestMode.None)
        }

        // Canvas 绘制薄荷青渐进色圆环
        Canvas(this.ctx)
          .width(280)
          .height(280)
          .onReady(() => {
            this.drawTimerRing();
          })

        // 中央：大号 MM:SS（60fp / 900 / FONT.monoExtraBold / primary 青）
        //       + 状态文字（12fp / secondary）
        Column() {
          Text(this.formatTime())
            .fontFamily(FONT.monoExtraBold)
            .fontSize(60)
            .fontWeight(900)
            .fontColor(this.getPrimary())
            .opacity(this.justCompleted ? 0.8 : 1.0)
            .animation({ duration: 200, curve: Curve.EaseInOut })

          Text(this.getStatusText())
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(TYPO.eyebrow.weight)
            .fontColor(this.getTextSecondary())
            .margin({ top: 4 })
            .animation({ duration: 150, curve: Curve.EaseInOut })
            .attributeModifier(SKETCH_BODY) // HUI-027：倒计时状态中文字→清松手写体2；上方 MM:SS 保留 mono
        }
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }
      .width(280)
      .height(280)

      // ── 控制按钮组：停止（左）+ 播放/暂停（中右） ──
      Row() {
        // 停止/重置按钮 — IconMapper.STOP(arrow_counterclockwise)，48vp 圆，secondary 底
        Button() {
          SymbolGlyph(IconMapper.STOP)
            .fontSize(24)
            .fontColor([this.getTextSecondary()])
        }
        .type(ButtonType.Circle)
        .width(48)
        .height(48)
        // HUI-034：停止/重置次要按钮套 btnAux 燕麦底（原 getSurface；不动 getPrimary 以保 Canvas 环/数字为墨色）
        .backgroundColor(this.tokens ? this.tokens.btnAux : '#C6BBAE')
        .onClick(() => {
          this.handleStop();
        })
        .accessibilityText('停止计时')
        .animation({ duration: 200, curve: Curve.EaseInOut })

        // 播放/暂停切换按钮 — play_fill(PLAY) / pause(PAUSE)，56vp 圆，primary 底 + primary 染色阴影
        Button() {
          SymbolGlyph(this.isRunning && !this.isPaused
            ? IconMapper.PAUSE
            : IconMapper.PLAY)
            .fontSize(28)
            // HUI-034：主控按钮图标套 btnPrimaryText 白
            .fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF'])
        }
        .type(ButtonType.Circle)
        .width(56)
        .height(56)
        // HUI-034：播放/暂停主控按钮套 btnPrimary 雾霾蓝底（原 getPrimary；getPrimary 仍用于 Canvas 环/数字，保持墨色）
        .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
        .shadow({
          radius: this.isRunning ? 20 : 12,
          color: this.tokens ? this.tokens.primaryLight : '#4FD8CE',
          offsetX: 0,
          offsetY: this.isRunning ? 6 : 2
        })
        .margin({ left: 24 })
        .onClick(() => {
          this.handlePlayPause();
        })
        .accessibilityText(this.isRunning && !this.isPaused ? '暂停计时' : '开始计时')
        .animation({ duration: 200, curve: Curve.EaseInOut })
      }
      .margin({ top: 40 })

      // ── 番茄统计（本轮 / 累计） ──
      Row() {
        this.statItem(this.currentRound, '本轮')
        this.statItem(this.cumulativeCount, '累计')
      }
      .margin({ top: 28 })
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 32, bottom: 28, left: SPACING.cardPadMd, right: SPACING.cardPadMd })
    .borderRadius(RADIUS.cardLg)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .shadow({
      radius: 16,
      color: this.getShadowColor(),
      offsetX: 0,
      offsetY: 4
    })
    .accessibilityGroup(true)
    .accessibilityText('番茄钟，剩余' + this.formatTime())
  }
}
