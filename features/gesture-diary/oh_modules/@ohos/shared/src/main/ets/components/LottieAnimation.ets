// <!-- agentID: HUI-017 -->
// 组件：LottieAnimation 可复用 Lottie 动画组件
// 关联任务：T-LT02（Lottie 动画集成 · 基础设施）
// 关联规划：workSpace/PLN_sketch_global_plan.md（批次 LT · T-LT02）
// 关联审判：workSpace/JUDGE_review_pln_lottie_v2.md（F2/F3/F4/S5 通过版解法）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式（Stage 模型）
//
// 硬约束落地：
//   F2 触摸透传：内部 Canvas + 组件根 Stack 均 hitTestBehavior(HitTestMode.None)，
//               手势交给父容器独占，杜绝 FloatingTabBar「AI Tab 点击失灵」回归。
//   F3 能耗/无障碍：respectReduceMotion（系统/应用「关闭动画」时降级为静态首帧 goToAndStop(0)）；
//               shouldPlay 响应式门控（父组件在后台/非当前页 pause）；60fps 动画可传 frameRate 限流。
//   F4 内存安全：每实例唯一 name；aboutToDisappear / aboutToReuse 均 stop + lottie.destroy(name) + 置空；
//               animItem 使用普通私有字段（严禁 @State，见库 README「防止动画内存泄漏」）。
//   S5 懒加载：autoplay=false，onReady + DOMLoaded 后再按需 play；onVisibleAreaChange 出屏停播；autoSkip=true。

import lottie, { AnimationItem } from '@ohos/lottie';
import type { ThemeColorTokens } from '../theme/ThemeConfig';

// 模块级自增序列，保证每个组件实例的动画 name 全局唯一（F4 防止 play/destroy 串扰）。
let __lottieInstanceSeq: number = 0;

function nextLottieSuffix(): string {
  __lottieInstanceSeq = __lottieInstanceSeq + 1;
  return __lottieInstanceSeq.toString() + '_' + Date.now().toString();
}

/**
 * LottieAnimation —— Lottie JSON 动画的可复用渲染组件。
 *
 * 典型用法（首页猫动画 / 导航 TalkBot）：
 *   LottieAnimation({
 *     animPath: 'animations/cat-loader.json',   // rawfile 相对路径（部署于 entry/src/main/resources/rawfile/）
 *     loop: true,
 *     autoPlay: true,
 *     animName: 'home-cat',                      // 可选可读前缀，内部仍会拼接唯一后缀
 *     accessibilityLabel: '猫咪加载动画',
 *     shouldPlay: this.isCurrentPage             // 父组件后台/非当前页时置 false 暂停（F3）
 *   })
 *     .width(120).height(120)
 *
 * 说明：
 *   - 主控制面（父组件驱动）为响应式 @Prop（shouldPlay / animPath / respectReduceMotion）+ 组件内 onVisibleAreaChange 自管；
 *   - 另暴露命令式 play()/pause()/stop() 供控制器式场景补充调用。
 */
@Reusable
@Component
export struct LottieAnimation {
  // ===== 基础属性 =====
  /** rawfile 相对路径，如 'animations/cat-loader.json'（path 优先查沙箱 file，未命中降级 rawfile，见库 README 说明 10）。 */
  @Prop @Watch('onPathChange') animPath: string = '';
  /** 可读 name 前缀（可选）；内部会拼接唯一后缀，F4 隔离用途。 */
  @Prop animName: string = '';
  /** 是否循环播放。 */
  @Prop loop: boolean = true;
  /** 是否自动播放。S5：默认 false，onReady/DOMLoaded 后按需 play。 */
  @Prop autoPlay: boolean = false;
  /** 填充模式：Fill / Top / Bottom / Cover / Contain（默认 Contain，等比不裁剪）。 */
  @Prop contentMode: string = 'Contain';
  /** 帧率限制（1~120，0 表示不限制）。60fps 动画（如 talkbot）可传 30 降能耗（F3）。 */
  @Prop frameRate: number = 0;
  /** 无障碍朗读文本；为空视为纯装饰，屏幕阅读器跳过。 */
  @Prop accessibilityLabel: string = '';

  // ===== F3：能耗 / 无障碍门控 =====
  /** 是否尊重「减弱动效」偏好。true 时系统/应用关闭动画则降级为静态首帧。 */
  @Prop @Watch('onReduceMotionChange') respectReduceMotion: boolean = true;
  /** 父组件运行时播放门控：后台 / 非当前页 / spring 变换期间置 false 暂停（F3 / T-LT04）。 */
  @Prop @Watch('onShouldPlayChange') shouldPlay: boolean = true;

  // ===== 尺寸（0 表示占满父容器）=====
  @Prop animWidth: number = 0;
  @Prop animHeight: number = 0;

  // ===== 系统 / 应用「减弱动效」信号 =====
  // 说明（对齐 JUDGE N3）：鸿蒙 API 12+ 暂无公开确证的「减弱动效」系统查询接口，
  // 故以应用内开关作为兜底触发源——应用在设置页写 AppStorage['reduce_motion']，本组件响应式降级。
  @StorageProp('reduce_motion') @Watch('onReduceMotionChange') systemReduceMotion: boolean = false;

  // ===== 主题（用于加载失败占位的中性配色）=====
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  // ===== 加载完成回调（父组件可选传入）=====
  onLoaded: (() => void) | null = null;
  // ===== 播放完成回调（loop=false 时，动画播完触发）=====
  onComplete: (() => void) | null = null;

  // ===== 内部状态 =====
  /** 仅此字段用 @State 驱动占位渲染；animItem 严禁 @State。 */
  @State loadFailed: boolean = false;

  // 画布上下文（每实例独立）。
  private renderSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderSettings);
  // 动画实例：普通私有字段，严禁 @State（库 README「防止动画内存泄漏」）。
  private animItem: AnimationItem | null = null;
  // 全局唯一动画 name（F4）。
  private instanceName: string = '';
  private canvasReady: boolean = false;
  private isLoaded: boolean = false;
  private isVisibleNow: boolean = true;

  aboutToAppear(): void {
    this.instanceName = (this.animName.length > 0 ? this.animName : 'lottie') + '_' + nextLottieSuffix();
    this.isVisibleNow = true;
  }

  // F4：页面销毁时停止 + 销毁 + 置空，防泄漏。
  aboutToDisappear(): void {
    this.cleanup();
  }

  // F4：复用池取用前，先销毁旧动画，再按新 @Prop 重新加载（@Prop 在回调前已刷新）。
  aboutToReuse(): void {
    this.cleanup();
    this.loadFailed = false;
    if (this.canvasReady) {
      this.loadAnimation();
    }
  }

  // ===== 响应式回调 =====
  onPathChange(): void {
    // 切换动画：stop 旧 → destroy 旧 → load 新（供轮播/换 Tab 复用）。
    this.cleanup();
    this.loadFailed = false;
    if (this.canvasReady) {
      this.loadAnimation();
    }
  }

  onShouldPlayChange(): void {
    this.reconcilePlayback();
  }

  onReduceMotionChange(): void {
    this.reconcilePlayback();
  }

  private isReduceMotionActive(): boolean {
    return this.respectReduceMotion && this.systemReduceMotion;
  }

  // 根据 播放意图 × 可见性 × 减弱动效 协调实际播放状态；仅在动画加载完成后生效。
  private reconcilePlayback(): void {
    if (this.animItem === null || !this.isLoaded) {
      return;
    }
    if (this.isReduceMotionActive()) {
      // F3：静态首帧，不循环。
      this.animItem.goToAndStop(0, true);
      return;
    }
    const wantPlay: boolean = this.autoPlay && this.shouldPlay && this.isVisibleNow;
    if (wantPlay) {
      this.animItem.play();
    } else {
      this.animItem.pause();
    }
  }

  private loadAnimation(): void {
    if (!this.canvasReady || this.animPath.length === 0) {
      return;
    }
    // 加载前先销毁同名残留（库 README 建议先 destroy(name) 再 load）。
    try {
      lottie.destroy(this.instanceName);
    } catch (err) {
      // 无同名动画时忽略。
    }
    this.isLoaded = false;
    this.loadFailed = false;

    try {
      // 直接内联对象字面量传入 loadAnimation（参数类型 AnimationConfigWithPath 提供上下文类型，
      // 与库 README 官方 ArkTS 用法一致，满足 ArkTS 严格模式）。
      const item: AnimationItem = lottie.loadAnimation({
        container: this.canvasCtx,
        renderer: 'canvas',        // Canvas 渲染，复杂矢量稳帧
        loop: this.loop,
        autoplay: false,           // S5：统一 false，加载完成后再由 reconcile 决定
        name: this.instanceName,
        contentMode: this.contentMode,
        autoSkip: true,            // S5/能耗：不可见时跳过绘制
        path: this.animPath
      });
      this.animItem = item;

      // DOMLoaded 后动画完全解析，此时操作才有效（库 README 说明二）。
      item.addEventListener('DOMLoaded', () => {
        this.onDomLoaded();
      });
      // 播放完成事件（loop=false 时播完触发）
      item.addEventListener('complete', () => {
        if (this.onComplete !== null) {
          this.onComplete();
        }
      });
      // 加载失败降级为静态占位，不崩溃。
      item.addEventListener('data_failed', () => {
        this.handleLoadError();
      });
      item.addEventListener('error', () => {
        this.handleLoadError();
      });
    } catch (err) {
      this.handleLoadError();
    }
  }

  private onDomLoaded(): void {
    this.isLoaded = true;
    this.loadFailed = false;
    // F3 能耗：加载完成后按需限流（如 60fps 的 talkbot 降到 30fps）。
    if (this.frameRate > 0 && this.animItem !== null) {
      this.animItem.setFrameRate(this.frameRate);
    }
    this.reconcilePlayback();
    if (this.onLoaded !== null) {
      this.onLoaded();
    }
  }

  private handleLoadError(): void {
    this.loadFailed = true;
    this.isLoaded = false;
  }

  // F4：停止 + 按 name 销毁 + 置空。不手动 removeEventListener('destroy')（会破坏库内部释放流程）。
  private cleanup(): void {
    try {
      if (this.animItem !== null) {
        this.animItem.stop();
      }
      lottie.destroy(this.instanceName);
    } catch (err) {
      // 忽略销毁异常，确保引用置空。
    }
    this.animItem = null;
    this.isLoaded = false;
  }

  private onVisibilityChange(currentRatio: number): void {
    this.isVisibleNow = currentRatio > 0;
    this.reconcilePlayback();
  }

  // ===== 命令式接口（控制器式场景补充；主控制面为响应式 @Prop）=====
  play(): void {
    if (this.animItem !== null && this.isLoaded && !this.isReduceMotionActive()) {
      this.animItem.play();
    }
  }

  pause(): void {
    if (this.animItem !== null && this.isLoaded) {
      this.animItem.pause();
    }
  }

  stop(): void {
    if (this.animItem !== null && this.isLoaded) {
      this.animItem.stop();
    }
  }

  build() {
    Stack() {
      Canvas(this.canvasCtx)
        .width('100%')
        .height('100%')
        // F2：内部 Canvas 触摸透传，手势交父容器（防 FloatingTabBar 点击失灵回归）。
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel(this.accessibilityLabel.length > 0 ? 'yes' : 'no')
        .accessibilityText(this.accessibilityLabel)
        .onReady(() => {
          // 抗锯齿（库 README 注意事项 3）。
          this.canvasCtx.imageSmoothingEnabled = true;
          this.canvasCtx.imageSmoothingQuality = 'medium';
          this.canvasReady = true;
          if (this.animItem === null) {
            this.loadAnimation();
          } else {
            // 复用后画布重新就绪，刷新布局尺寸。
            this.animItem.resize();
          }
        })
        .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number) => {
          this.onVisibilityChange(currentRatio);
        })

      // 加载失败静态占位：中性圆点，纯装饰不拦截触摸。
      if (this.loadFailed) {
        this.buildErrorPlaceholder()
      }
    }
    .width(this.animWidth > 0 ? this.animWidth : '100%')
    .height(this.animHeight > 0 ? this.animHeight : '100%')
    // F2：组件根同样触摸透传，整体不消费手势。
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  buildErrorPlaceholder() {
    Column() {
      Circle()
        .width('36%')
        .height('36%')
        .fill(this.tokens ? this.tokens.border : '#D8D8D8')
        .opacity(0.5)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }
}
