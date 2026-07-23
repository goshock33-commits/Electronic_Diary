// <!-- agentID: HUI-001 -->
// 文件: PawClickEffect.ets
// 任务: 全局"猫爪"点击特效（纯页面树内方案：捕获 + 视觉同树）
// 关联架构: 各 @Entry 页根容器接入（捕获 onTouch + 视觉 PawOverlayLayer 子层）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
//
// ── 架构（两次红线事故后定稿：零窗口级悬浮节点）──────────────────────────
// 教训（errors/HUI-001_errors.md）：OverlayManager 的 overlay 是独立命中子树，
// 层内 Transparent 会吞事件；且框架包裹的 overlay 容器外壳本身可命中，层内
// 全 None 也管不到外壳 —— 真机实证：任何窗口级悬浮节点都不可信。
// 因此彻底放弃窗口级挂载，捕获与视觉全部放进页面树：
// 【捕获】各 @Entry 页根容器 .onTouch(reportPawTouch)：
//   挂在页面树内已有根节点上，冒泡监听不消费（不调 stopPropagation、
//   不参与手势仲裁）→ 按钮/滑动/长按/输入照常。
// 【视觉】PawOverlayLayer 作为各页根 Stack 的最上层子节点（同树叠加）：
//   整层 hitTestBehavior(HitTestMode.None) —— 同树 None 是本项目已验证的
//   安全模式（骑栏白圆层先例）；爪印子树逐节点 None（None 不覆盖子节点）。
// 【链路】页面 onTouch(Down) → AppStorage['paw_click_signal'] = "seq:x:y"
//   （seq 自增保证值必变）→ 本页 PawOverlayLayer @StorageProp + @Watch → 画爪。
//   坐标用 TouchObject.x/y（相对挂点根容器），爪层是同一根容器的满屏子层，
//   原点重合，坐标零换算（沉浸式/避让下也不偏移）。
//
// ── 深浅色 ───────────────────────────────────────────────────────────────
// 跟随项目现有 ThemeManager 机制：@StorageProp('theme_is_dark')（boolean）。
// 浅色=深爪印 rgba(0,0,0,0.35)，深色=浅爪印 rgba(255,255,255,0.40)。
// 不用资源限定符（base/dark 跟随系统 colorMode，会与 App 内手动切换主题脱节）。

// ── 视觉与节奏常量（vp / ms）────────────────────────────────────────────
const PAW_SIZE: number = 44;                 // 爪印整体画布边长（vp）
const PAW_MAX_CONCURRENT: number = 8;        // 并发上限，超出丢最旧
const PAW_APPEAR_MS: number = 140;           // 快速 scale-in
const PAW_HOLD_MS: number = 180;             // 停留
const PAW_FADE_MS: number = 320;             // 渐隐消失（总时长 140+180+320=640ms < 700ms）
const PAW_ANGLE_RANGE: number = 50;          // 随机旋转角范围（-25° ~ +25°）
const PAW_COLOR_ON_LIGHT: string = 'rgba(0, 0, 0, 0.35)';       // 浅色模式=深爪印
const PAW_COLOR_ON_DARK: string = 'rgba(255, 255, 255, 0.40)';  // 深色模式=浅爪印
const PAW_SIGNAL_KEY: string = 'paw_click_signal';              // 捕获→视觉 信号 key

// ── 页面树内触摸捕获（各 @Entry 页根容器一行接入：.onTouch(reportPawTouch)）──
// 仅监听不消费：不调 stopPropagation，事件照常冒泡/分发。
// 坐标用 touch.x/y（相对挂点根容器，vp）：视觉爪层是同一根容器的满屏子层，
// 原点重合，无需窗口坐标换算。
let pawSignalSeq: number = 0;

export function reportPawTouch(event: TouchEvent): void {
  if (event.type !== TouchType.Down || event.changedTouches.length === 0) {
    return;
  }
  const touch = event.changedTouches[0];
  pawSignalSeq += 1;
  // "seq:x:y"，seq 自增保证 @Watch 必触发；坐标保留 1 位小数足够
  const signal: string = pawSignalSeq + ':' +
    (Math.round(touch.x * 10) / 10) + ':' +
    (Math.round(touch.y * 10) / 10);
  AppStorage.setOrCreate(PAW_SIGNAL_KEY, signal);
}

// 单个爪印数据
interface PawStamp {
  id: number;
  x: number;
  y: number;
  angle: number;
}

// ── 单个爪印视觉（矢量 Ellipse 组合：1 大肉垫 + 4 趾，无位图）───────────────
// 出现/消失动画用 TransitionEffect.asymmetric（common.d.ts L7527）：
// 插入 = opacity 0→1 + scale 0.3→1（Sharp 140ms）；移除 = opacity→0 + scale→1.15（EaseOut 320ms）。
// 无自持定时器/帧回调，动画随节点移除由系统接管，无泄漏。
// 红线：本组件所有节点 HitTestMode.None（None 不覆盖子节点，逐节点显式设置）。
@Component
struct PawStampView {
  centerX: number = 0;
  centerY: number = 0;
  angle: number = 0;
  // @Prop：允许被父组件 @StorageProp 初始化（regular 字段不允许，编译实证）；默认值纯 boolean 合规 §9.2
  @Prop isDark: boolean = false;

  // §9.1：普通方法而非 getter，build 中显式调用
  private pawColor(): string {
    return this.isDark ? PAW_COLOR_ON_DARK : PAW_COLOR_ON_LIGHT;
  }

  build() {
    Stack() {
      // 四趾（左外 / 左内 / 右内 / 右外），外趾略低并外倾
      Ellipse({ width: 9, height: 12 })
        .fill(this.pawColor())
        .position({ x: 2.5, y: 9 })
        .rotate({ angle: -24 })
        .hitTestBehavior(HitTestMode.None)
      Ellipse({ width: 9.5, height: 13 })
        .fill(this.pawColor())
        .position({ x: 12, y: 3 })
        .rotate({ angle: -8 })
        .hitTestBehavior(HitTestMode.None)
      Ellipse({ width: 9.5, height: 13 })
        .fill(this.pawColor())
        .position({ x: 22.5, y: 3 })
        .rotate({ angle: 8 })
        .hitTestBehavior(HitTestMode.None)
      Ellipse({ width: 9, height: 12 })
        .fill(this.pawColor())
        .position({ x: 32.5, y: 9 })
        .rotate({ angle: 24 })
        .hitTestBehavior(HitTestMode.None)
      // 大肉垫
      Ellipse({ width: 24, height: 19 })
        .fill(this.pawColor())
        .position({ x: 10, y: 21 })
        .hitTestBehavior(HitTestMode.None)
    }
    .width(PAW_SIZE)
    .height(PAW_SIZE)
    .position({ x: this.centerX - PAW_SIZE / 2, y: this.centerY - PAW_SIZE / 2 })
    .rotate({ angle: this.angle })
    .transition(
      TransitionEffect.asymmetric(
        TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.3, y: 0.3 }))
          .animation({ duration: PAW_APPEAR_MS, curve: Curve.Sharp }),
        TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 1.15, y: 1.15 }))
          .animation({ duration: PAW_FADE_MS, curve: Curve.EaseOut })
      )
    )
    .hitTestBehavior(HitTestMode.None)
  }
}

// ── 页面内纯视觉爪印叠加层（各页根 Stack 最上层子节点，同树 None 不挡交互）───
// 接入：根是 Stack 的页面直接追加子节点 PawOverlayLayer()；
//       根不是 Stack 的页面用最小包装 Stack{ 原根; PawOverlayLayer() }。
@Component
export struct PawOverlayLayer {
  @State paws: PawStamp[] = [];
  @StorageProp('theme_is_dark') isDark: boolean = false;
  // 捕获端信号："seq:x:y"。@Watch 仅在值变化时触发，seq 自增保证必变。
  @StorageProp('paw_click_signal') @Watch('onPawSignal') pawSignal: string = '';
  private nextId: number = 1;
  private removalTimers: number[] = [];

  // §8/§9：页面销毁时清理全部未决定时器，无泄漏
  aboutToDisappear(): void {
    for (const timerId of this.removalTimers) {
      clearTimeout(timerId);
    }
    this.removalTimers = [];
  }

  // 解析 "seq:x:y" 并落爪
  onPawSignal(): void {
    const parts: string[] = this.pawSignal.split(':');
    if (parts.length !== 3) {
      return;
    }
    const x: number = Number(parts[1]);
    const y: number = Number(parts[2]);
    if (Number.isNaN(x) || Number.isNaN(y)) {
      return;
    }
    this.spawnPaw(x, y);
  }

  private spawnPaw(x: number, y: number): void {
    if (this.paws.length >= PAW_MAX_CONCURRENT) {
      this.paws.shift(); // 超出并发上限：丢最旧（其消失过渡由 TransitionEffect 接管）
    }
    const id: number = this.nextId;
    this.nextId += 1;
    const stamp: PawStamp = {
      id: id,
      x: x,
      y: y,
      angle: Math.round((Math.random() - 0.5) * PAW_ANGLE_RANGE)
    };
    this.paws.push(stamp);
    // 出现+停留后移除节点，移除瞬间触发 disappear 过渡（渐隐+微放大）
    const timerId: number = setTimeout(() => {
      const idx = this.paws.findIndex((p: PawStamp): boolean => p.id === id);
      if (idx >= 0) {
        this.paws.splice(idx, 1);
      }
      const ti = this.removalTimers.indexOf(timerId);
      if (ti >= 0) {
        this.removalTimers.splice(ti, 1);
      }
    }, PAW_APPEAR_MS + PAW_HOLD_MS);
    this.removalTimers.push(timerId);
  }

  build() {
    Stack() {
      ForEach(this.paws, (paw: PawStamp) => {
        PawStampView({
          centerX: paw.x,
          centerY: paw.y,
          angle: paw.angle,
          isDark: this.isDark
        })
      }, (paw: PawStamp): string => paw.id.toString())
    }
    .width('100%')
    .height('100%')
    // 红线：纯视觉层，同树 None（本项目骑栏白圆层验证过的安全模式）；层内无任何 onTouch。
    .hitTestBehavior(HitTestMode.None)
    // 双保险：响应区域收缩为零，即使命中模式被未来改动破坏也无可命中面积
    .responseRegion({ x: 0, y: 0, width: 0, height: 0 })
  }
}
