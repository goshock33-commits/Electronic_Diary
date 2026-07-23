// <!-- agentID: HUI-062 -->
// 组件：LiveWindowDisplay — 实况窗 UI（锁屏/通知实况窗预览层）
// P2-10 薄荷青皮肤统一：环形进度主色 primary，轨道 accent，无三色阈值，FONT.monoBold 计时数字
// 关联任务：F22（实况窗 UI 层，仅 UI，不含后端）
// 关联后端：entry/src/main/ets/utils/LiveViewManager.ets（DEV-012，仅参考，本任务不改后端）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式（Stage 模型）
//
// === 三状态 ===
//   1. POMODORO_RUNNING 番茄钟进行中：Canvas 倒计时环 + MM:SS + 暂停按钮
//   2. POMODORO_PAUSED  番茄钟暂停：暗化环 + 剩余时间 + 继续按钮
//   3. DIARY_REMINDER   日记提醒：铃铛图标 + 提醒文案 + 去写日记 / 忽略
//
// === Mock 计时 ===
//   运行态用 setInterval 本地倒计时（1s/跳），aboutToDisappear 清理（§9 防泄漏）。
//   状态切换用 @Watch 联动启停计时器。
//
// === 图标来源（本地 resource/HarmonyOS_全量图标库.md，已 grep 逐一验证存在）===
//   | 图标资源                          | 用途       | 库中位置        |
//   |-----------------------------------|------------|-----------------|
//   | sys.symbol.clock_fill             | 番茄钟标识 | 系统UI 区段     |
//   | sys.symbol.play_fill              | 继续       | line 1219       |
//   | sys.symbol.pause                  | 暂停       | line 1207       |
//   | sys.symbol.arrow_counterclockwise | 停止/重置  | line 15 附近    |
//   | sys.symbol.bell_fill              | 日记提醒   | line 43         |
//   | sys.symbol.square_and_pencil      | 去写日记   | line 1598       |
//   | sys.symbol.xmark                  | 忽略/关闭  | line 293        |
//   注：本地库中【无 pause_fill】，故暂停统一使用 sys.symbol.pause。
//
// === 崩溃防范（PROJECT_SPEC §9）===
//   §9.1 无 getter-in-build：派生值一律普通方法 getXxx() 在 build 中显式调用
//   §9.2 @Prop 默认值不含 $r()：state / presetLabel / totalSeconds 均为原始类型
//   §9.3 字段初值不含 $r()：所有 private 字段为原始类型，$r() 仅内联于 build
//   §9.4 @StorageLink('theme_tokens') 判空：this.tokens ? this.tokens.x : '#fallback'
//   定时器：aboutToDisappear 清理 setInterval，防内存泄漏与野回调崩溃
//
// === 无障碍 ===
//   触控热区 >= 48x48vp，按钮含 accessibilityText，根节点 accessibilityGroup。

import type { ThemeColorTokens } from '@ohos/shared';
import { FONT, RADIUS, IconMapper } from '@ohos/shared';

/**
 * 实况窗三状态枚举。
 */
export enum LiveWindowState {
  /** 番茄钟进行中（倒计时环滚动） */
  POMODORO_RUNNING = 'pomodoro_running',
  /** 番茄钟已暂停 */
  POMODORO_PAUSED = 'pomodoro_paused',
  /** 日记提醒 */
  DIARY_REMINDER = 'diary_reminder'
}

@Component
export struct LiveWindowDisplay {
  /** 当前实况窗状态（§9.2 默认值为枚举，无 $r()） */
  @Watch('onStateChanged') @Prop state: LiveWindowState = LiveWindowState.POMODORO_RUNNING;
  /** 番茄钟预设标签（专注 / 短休息 / 长休息） */
  @Prop presetLabel: string = '专注';
  /** 倒计时总秒数（默认 25min = 1500s） */
  @Prop totalSeconds: number = 1500;
  /** 初始剩余秒数（默认 24:35，便于预览环形进度） */
  @Prop initialRemaining: number = 1475;

  /** 暂停 / 继续回调 */
  onToggle?: () => void;
  /** 停止 / 重置回调 */
  onStop?: () => void;
  /** 去写日记回调 */
  onWriteDiary?: () => void;
  /** 忽略提醒回调 */
  onDismiss?: () => void;

  /** 剩余秒数（mock 计时驱动，UI 内部状态） */
  @State remainingSeconds: number = 1475;
  /** 主题 token（AppStorage 注入，可能为 null，读取前必判空 §9.4） */
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  // ── Canvas 上下文（倒计时环，§9.3 无 $r()） ──
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  // ── mock 计时器句柄 ──
  private timerId: number = -1;
  // ── 环形画布尺寸（vp） ──
  private readonly ringSize: number = 52;

  aboutToAppear(): void {
    this.remainingSeconds = this.initialRemaining;
    if (this.state === LiveWindowState.POMODORO_RUNNING) {
      this.startMockTimer();
    }
  }

  aboutToDisappear(): void {
    // §9 定时器清理：组件销毁必须停止 setInterval，防泄漏/野回调崩溃
    this.stopMockTimer();
  }

  // ════════════════════════════════════════════════════════════
  // Mock 计时逻辑（setInterval 本地倒计时）
  // ════════════════════════════════════════════════════════════

  /** 状态变化联动：进入运行态启动计时，否则停止 */
  onStateChanged(): void {
    if (this.state === LiveWindowState.POMODORO_RUNNING) {
      this.startMockTimer();
    } else {
      this.stopMockTimer();
    }
    // 重绘环形进度
    this.drawTimerRing();
  }

  private startMockTimer(): void {
    this.stopMockTimer();
    this.timerId = setInterval(() => {
      if (this.remainingSeconds <= 0) {
        this.remainingSeconds = 0;
        this.stopMockTimer();
        return;
      }
      this.remainingSeconds--;
      this.drawTimerRing();
    }, 1000);
  }

  private stopMockTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  // ════════════════════════════════════════════════════════════
  // 派生值（§9.1 全部普通方法，禁 getter-in-build）
  // ════════════════════════════════════════════════════════════

  /** 剩余秒数格式化为 MM:SS */
  private getTimeText(): string {
    const m: number = Math.floor(this.remainingSeconds / 60);
    const s: number = this.remainingSeconds % 60;
    return String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
  }

  /** 顶部状态标题文字 */
  private getTitleText(): string {
    if (this.state === LiveWindowState.POMODORO_RUNNING) {
      return '番茄钟 · ' + this.presetLabel;
    }
    if (this.state === LiveWindowState.POMODORO_PAUSED) {
      return '番茄钟 · 已暂停';
    }
    return '日记提醒';
  }

  /** 副标题文字 */
  private getSubtitleText(): string {
    if (this.state === LiveWindowState.POMODORO_RUNNING) {
      return '专注中，保持节奏';
    }
    if (this.state === LiveWindowState.POMODORO_PAUSED) {
      return '已暂停，点击继续';
    }
    return '记录今天的心情吧';
  }

  /** 进度比例 0~1 */
  private getProgress(): number {
    return this.totalSeconds > 0 ? this.remainingSeconds / this.totalSeconds : 0;
  }

  /** 环形进度颜色：运行态统一薄荷青 primary，暂停态灰（§6.4 全时段薄荷青，无三色阈值） */
  private getRingColor(): string {
    if (this.state === LiveWindowState.POMODORO_PAUSED) {
      return this.tokens ? this.tokens.textTertiary : '#B0B0B0';
    }
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  /** 主色（提醒态图标背景等，薄荷青统一） */
  private getPrimaryColor(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  /** 卡片背景色 */
  private getCardBg(): string {
    return this.tokens ? this.tokens.bgCard : '#FFFFFF';
  }

  /** 主要文字色 */
  private getTextPrimary(): string {
    return this.tokens ? this.tokens.textPrimary : '#1A1A1A';
  }

  /** 次要文字色 */
  private getTextSecondary(): string {
    return this.tokens ? this.tokens.textSecondary : '#8A8A8A';
  }

  /** accent 色（环轨道底 / fallback #E6F9F8） */
  private getAccent(): string {
    return this.tokens ? this.tokens.accent : '#E6F9F8';
  }

  /** 表面色（次级按钮底） */
  private getSurface(): string {
    return this.tokens ? this.tokens.surface : '#F2F3F5';
  }

  /** 阴影色 */
  private getShadowColor(): string {
    return this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.10)';
  }

  /** 根节点无障碍描述 */
  private getA11yText(): string {
    if (this.state === LiveWindowState.DIARY_REMINDER) {
      return '实况窗：日记提醒，记录今天的心情';
    }
    const stateWord: string =
      this.state === LiveWindowState.POMODORO_RUNNING ? '进行中' : '已暂停';
    return '实况窗：番茄钟' + this.presetLabel + stateWord + '，剩余' + this.getTimeText();
  }

  // ════════════════════════════════════════════════════════════
  // Canvas 倒计时环绘制
  // ════════════════════════════════════════════════════════════

  private drawTimerRing(): void {
    const size: number = this.ringSize;
    const cx: number = size / 2;
    const cy: number = size / 2;
    const lineWidth: number = 5;
    const radius: number = (size - lineWidth) / 2 - 1;

    this.ctx.clearRect(0, 0, size, size);

    // 背景环（薄荷青浅底 accent #E6F9F8）
    this.ctx.beginPath();
    this.ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
    this.ctx.strokeStyle = this.getAccent();
    this.ctx.lineWidth = lineWidth;
    this.ctx.lineCap = 'round';
    this.ctx.stroke();

    // 前景进度弧（12 点钟方向顺时针）
    const progress: number = this.getProgress();
    if (progress > 0) {
      const startAngle: number = -Math.PI / 2;
      const endAngle: number = startAngle + (2 * Math.PI * progress);
      this.ctx.beginPath();
      this.ctx.arc(cx, cy, radius, startAngle, endAngle);
      this.ctx.strokeStyle = this.getRingColor();
      this.ctx.lineWidth = lineWidth;
      this.ctx.lineCap = 'round';
      this.ctx.stroke();
    }
  }

  // ════════════════════════════════════════════════════════════
  // 子视图 Builder
  // ════════════════════════════════════════════════════════════

  /** 番茄钟态（运行 / 暂停共用布局） */
  @Builder
  PomodoroView() {
    Row() {
      // ── 左：倒计时环 + 中央 MM:SS ──
      Stack({ alignContent: Alignment.Center }) {
        Canvas(this.ctx)
          .width(this.ringSize)
          .height(this.ringSize)
          .onReady(() => {
            this.drawTimerRing();
          })

        Text(this.getTimeText())
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getTextPrimary())
          .fontFamily(FONT.monoBold)
      }
      .width(this.ringSize)
      .height(this.ringSize)

      // ── 中：标题 + 副标题 ──
      Column() {
        Row() {
          SymbolGlyph(IconMapper.CLOCK)
            .fontSize(14)
            .fontColor([this.getRingColor()])
          Text(this.getTitleText())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getTextPrimary())
            .margin({ left: 6 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(VerticalAlign.Center)

        Text(this.getSubtitleText())
          .fontSize(12)
          .fontColor(this.getTextSecondary())
          .margin({ top: 3 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12, right: 8 })

      // ── 右：停止 + 暂停/继续 ──
      Row() {
        // 停止 / 重置（次级按钮）
        Button() {
          SymbolGlyph(IconMapper.STOP)
            .fontSize(18)
            .fontColor([this.getTextSecondary()])
        }
        .type(ButtonType.Circle)
        .width(48)
        .height(48)
        .backgroundColor(this.getSurface())
        .onClick(() => {
          this.remainingSeconds = this.totalSeconds;
          this.drawTimerRing();
          if (this.onStop) {
            this.onStop();
          }
        })
        .accessibilityText('停止番茄钟')

        // 暂停 / 继续（主操作）
        Button() {
          SymbolGlyph(this.state === LiveWindowState.POMODORO_RUNNING
            ? IconMapper.PAUSE
            : IconMapper.PLAY)
            .fontSize(20)
            // HUI-038：主操作圆按钮图标→btnPrimaryText（配 btnPrimary 底）
            .fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF'])
        }
        .type(ButtonType.Circle)
        .width(48)
        .height(48)
        // HUI-038：暂停/继续主操作圆按钮（漏网）→ btnPrimary 雾霾蓝底（原 primary 兜底青 #00C2B8）
        .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
        .margin({ left: 10 })
        .onClick(() => {
          if (this.onToggle) {
            this.onToggle();
          }
        })
        .accessibilityText(
          this.state === LiveWindowState.POMODORO_RUNNING ? '暂停' : '继续'
        )
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 日记提醒态 */
  @Builder
  DiaryReminderView() {
    Row() {
      // ── 左：铃铛图标（主色圆底） ──
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(IconMapper.BELL)
          .fontSize(24)
          .fontColor([Color.White])
      }
      .width(this.ringSize)
      .height(this.ringSize)
      .borderRadius(this.ringSize / 2)
      .backgroundColor(this.getPrimaryColor())

      // ── 中：标题 + 副标题 ──
      Column() {
        Text(this.getTitleText())
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getTextPrimary())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.getSubtitleText())
          .fontSize(12)
          .fontColor(this.getTextSecondary())
          .margin({ top: 3 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12, right: 8 })

      // ── 右：忽略 + 去写日记 ──
      Row() {
        // 忽略（次级按钮）
        Button() {
          SymbolGlyph(IconMapper.CLOSE)
            .fontSize(18)
            .fontColor([this.getTextSecondary()])
        }
        .type(ButtonType.Circle)
        .width(48)
        .height(48)
        .backgroundColor(this.getSurface())
        .onClick(() => {
          if (this.onDismiss) {
            this.onDismiss();
          }
        })
        .accessibilityText('忽略提醒')

        // 去写日记（主操作）
        Button() {
          SymbolGlyph(IconMapper.BOOKMARK)
            .fontSize(20)
            // HUI-038：主操作圆按钮图标→btnPrimaryText（配 btnPrimary 底）
            .fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF'])
        }
        .type(ButtonType.Circle)
        .width(48)
        .height(48)
        // HUI-038：去写日记主操作圆按钮（漏网）→ btnPrimary 雾霾蓝底（原 primary 兜底青 #00C2B8）
        .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
        .margin({ left: 10 })
        .onClick(() => {
          if (this.onWriteDiary) {
            this.onWriteDiary();
          }
        })
        .accessibilityText('去写日记')
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // ════════════════════════════════════════════════════════════
  // 主构建
  // ════════════════════════════════════════════════════════════

  build() {
    Column() {
      if (this.state === LiveWindowState.DIARY_REMINDER) {
        this.DiaryReminderView()
      } else {
        this.PomodoroView()
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .borderRadius(RADIUS.cardMd)
    .backgroundColor(this.getCardBg())
    .shadow({ radius: 16, color: this.getShadowColor(), offsetX: 0, offsetY: 4 })
    .accessibilityGroup(true)
    .accessibilityText(this.getA11yText())
  }
}
