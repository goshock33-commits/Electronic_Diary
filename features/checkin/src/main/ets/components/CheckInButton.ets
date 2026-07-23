// <!-- agentID: HUI-021 -->
// 组件：圆形打卡按钮（默认灰描边→已打卡渐变填充+对勾SymbolGlyph+弹性缩放+光晕扩散+触觉反馈+粒子庆祝）
// 关联设计稿：UX-001_prototype.html（checkin-btn + checkin-spark）
// 关联任务：F03（PLN-002 阶段2 打卡签到UI）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText + 触控热区 >= 48x48vp
// 深色适配：ThemeColorTokens + 硬编码回退色
// SDK 6.1.1：Curve.EaseInOut 替代 Curve.Spring
// HUI-039：打卡成功三段式——①打卡环弹性收缩到 0 消失 ②小猫欢呼 Lottie 独占登场（mascot.json
//          60fps/100帧，只播 1 轮≈1.7s，92vp 大尺寸）③环从 0 弹性放大回归显示对勾态。
//          reduce_motion 时跳过收缩与小猫直达对勾；定时器随组件销毁清理。

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_BODY=清松手写体2（"打卡"动作标签）。
// HUI-039：追加 LottieAnimation（小猫欢呼庆祝动画）。
import { IconMapper, SKETCH_BODY, LottieAnimation } from '@ohos/shared';
import { vibrator } from '@kit.SensorServiceKit';

/**
 * 粒子数据接口
 */
interface ParticleData {
  id: number;
  angle: number;
  distance: number;
  color: string;
  size: number;
  delay: number;
}

/**
 * CheckInButton — 圆形打卡按钮
 * 默认态: 灰色描边圆圈 + "打卡" 文字
 * 已打卡态(HUI-039 三段式): 环弹性收缩消失 → 小猫欢呼 Lottie 独占登场(1轮≈1.7s) →
 *                          环从 0 弹性放大回归(雾霾蓝底白勾)，不可重复点击
 * 点击动画: 环收缩即点击反馈 + 光晕扩散 + 触觉反馈
 * 粒子庆祝: 12 颗粒子从中心飞出 + 旋转，持续 1.5s（与小猫欢呼同期编排）
 */
@Component
export struct CheckInButton {
  @Watch('onIsCheckedChanged')
  @Prop isChecked: boolean = false;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  onCheckIn?: () => void;

  /** 是否已完成首次渲染（防止 @Watch 初始化时误触发） */
  private hasInitialized: boolean = false;

  /** 按钮缩放状态 */
  // HUI-039：pressScale 弹跳升级为 ringScale 三段式（1→0 收缩消失，小猫播完 0→1 弹性回归）
  @State private ringScale: number = 1.0;
  /** 光晕是否显示 */
  @State private showGlow: boolean = false;
  /** 光晕缩放 */
  @State private glowScale: number = 1.0;
  /** 光晕透明度 */
  @State private glowOpacity: number = 0;
  /** 是否显示粒子庆祝 */
  @State private celebrating: boolean = false;

  // ===== HUI-039：小猫欢呼动画状态 =====
  /** 是否正在播放小猫欢呼动画（环已收缩消失，小猫独占舞台） */
  @State private showMascotAnim: boolean = false;
  /** 减弱动效开关（与 shared/LottieAnimation 同源：应用设置页写 AppStorage['reduce_motion']） */
  @StorageProp('reduce_motion') reduceMotion: boolean = false;
  /** 小猫动画精确结束定时器（onLoaded 锚定后调度，播满 1 轮） */
  private mascotEndTimerId: number = -1;
  /** 小猫动画兜底定时器（Lottie 加载失败/onLoaded 未回调时保证环回归对勾） */
  private mascotFallbackTimerId: number = -1;
  /** 三段式编排链定时器（环收缩/小猫登场/环回归过冲），统一收编便于清理 */
  private phaseTimerIds: number[] = [];
  /** mascot.json：100 帧 @60fps ≈ 1667ms/轮，只播 1 轮（+缓冲） */
  private readonly mascotOneLoopMs: number = 1700;
  /** 兜底时长：覆盖加载耗时 + 1 轮播放，超时强制环回归对勾（环消失态不可久留） */
  private readonly mascotFallbackMs: number = 2800;

  /** 按钮直径（>=80vp） */
  private readonly buttonSize: number = 96;
  /** HUI-039：小猫独占舞台边长——环收缩消失后放大登场，接近按钮直径 96vp */
  private readonly mascotSoloSize: number = 92;

  /** 12 颗粒子配置 — 以按钮中心为原点，向外扩散 */
  // HUI-023：清除硬编码彩色死值 → 手绘黑白墨点（黑/深灰/中灰/浅灰混排，浅色深色两种主题均有可见粒子）
  private readonly particles: ParticleData[] = [
    { id: 1, angle: 0, distance: 48, color: '#000000', size: 8, delay: 0 },
    { id: 2, angle: 30, distance: 52, color: '#666666', size: 6, delay: 40 },
    { id: 3, angle: 60, distance: 44, color: '#8A8A8A', size: 7, delay: 80 },
    { id: 4, angle: 90, distance: 50, color: '#CCCCCC', size: 8, delay: 20 },
    { id: 5, angle: 120, distance: 46, color: '#000000', size: 6, delay: 100 },
    { id: 6, angle: 150, distance: 54, color: '#666666', size: 7, delay: 60 },
    { id: 7, angle: 180, distance: 42, color: '#8A8A8A', size: 8, delay: 30 },
    { id: 8, angle: 210, distance: 56, color: '#CCCCCC', size: 6, delay: 90 },
    { id: 9, angle: 240, distance: 48, color: '#000000', size: 7, delay: 50 },
    { id: 10, angle: 270, distance: 52, color: '#666666', size: 8, delay: 70 },
    { id: 11, angle: 300, distance: 44, color: '#8A8A8A', size: 6, delay: 110 },
    { id: 12, angle: 330, distance: 50, color: '#CCCCCC', size: 7, delay: 10 }
  ];

  /**
   * 页面显示时刷新打卡状态（父组件负责）
   */
  aboutToAppear(): void {
    this.hasInitialized = true;
  }

  /**
   * HUI-039：组件销毁时清理小猫动画定时器，防止销毁后 setState
   */
  aboutToDisappear(): void {
    this.clearMascotTimers();
  }

  /**
   * 监听 isChecked 变化，当从未打卡变为已打卡时自动触发庆祝动画
   */
  onIsCheckedChanged(): void {
    if (this.hasInitialized && this.isChecked) {
      // HUI-039：三段式启动——段①环收缩 → 段②小猫登场（reduce_motion 时直达对勾）
      this.startCheckedSequence();
      setTimeout(() => {
        this.triggerCelebration();
      }, 450);
    } else if (!this.isChecked) {
      // HUI-039：状态回退（跨天刷新等）→ 复位环与小猫、清理定时器
      this.resetMascotPhase();
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // ===== 光晕扩散层 =====
      if (this.showGlow) {
        Circle({ width: this.buttonSize, height: this.buttonSize })
          .fill(this.getCheckedColor())
          .opacity(this.glowOpacity)
          .scale({ x: this.glowScale, y: this.glowScale })
          .accessibilityLevel('no')
      }

      // ===== 粒子庆祝层 =====
      if (this.celebrating) {
        Stack({ alignContent: Alignment.Center }) {
          ForEach(this.particles, (p: ParticleData) => {
            Circle({ width: p.size, height: p.size })
              .fill(p.color)
              .opacity(this.celebrating ? 0 : 1.0)
              .offset({
                x: this.celebrating ? this.calcOffsetX(p) : 0,
                y: this.celebrating ? this.calcOffsetY(p) : 0
              })
              .rotate({ angle: this.celebrating ? p.angle + 180 : 0 })
              .animation({
                duration: 1200,
                curve: Curve.EaseOut,
                delay: p.delay,
                iterations: 1
              })
              .accessibilityLevel('no')
          }, (p: ParticleData) => p.id.toString())
        }
        .width(this.buttonSize + 24)
        .height(this.buttonSize + 24)
        .accessibilityLevel('no')
      }

      // ===== 按钮主体 =====
      Column() {
        if (this.isChecked) {
          // 已打卡态：白色对勾 SymbolGlyph（HUI-039：随环 0→1 弹性放大整体登场）
          SymbolGlyph(IconMapper.CHECKIN_DONE)
            .fontSize(36)
            // HUI-034：完成态勾选套 btnPrimaryText 白勾（与 btnPrimary 底成对比）
            .fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF'])
            .accessibilityLevel('no')
        } else {
          // 未打卡态：文字"打卡"
          Text('打卡')
            .fontSize(17)
            .fontWeight(600)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A7A5A')
            .accessibilityLevel('no')
            .attributeModifier(SKETCH_BODY) // HUI-029：打卡动作标签→清松手写体2
        }
      }
      .width(this.buttonSize)
      .height(this.buttonSize)
      .borderRadius(this.buttonSize / 2)
      .backgroundColor(this.isChecked ?
        this.getCheckedColor() :
        (this.tokens ? this.tokens.surface : '#FFFFFF'))
      .border({
        width: this.isChecked ? 0 : 3,
        color: this.isChecked ?
          Color.Transparent :
          (this.tokens ? this.tokens.border : 'rgba(76,175,80,0.20)')
      })
      .shadow(this.isChecked ? {
        radius: 24,
        // HUI-040：修复 alpha 后拼 bug——ArkUI 8位hex 为 #AARRGGBB（alpha 在前），
        // 原 primaryLight+'80' 深色下拼成 #FFFFFF80 = 不透明淡黄光圈，改用前置 alpha
        color: this.withAlpha(this.tokens ? this.tokens.primaryLight : '#4FD8CE', '80'),
        offsetX: 0,
        offsetY: 8
      } : {
        radius: 8,
        color: (this.tokens ? this.tokens.shadow : 'rgba(76,175,80,0.08)'),
        offsetX: 0,
        offsetY: 2
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      // HUI-039：环缩放三段式（点击后 1→1.06→0 收缩消失，小猫播完 0→1.08→1.0 弹性回归）
      .scale({ x: this.ringScale, y: this.ringScale })
      .onClick(() => {
        if (!this.isChecked && this.onCheckIn) {
          this.handleCheckIn();
        }
      })
      .hitTestBehavior(this.isChecked ? HitTestMode.None : HitTestMode.Default)
      .animation({
        duration: 350,
        curve: Curve.EaseInOut,
        iterations: 1
      })

      // ===== HUI-039：小猫欢呼独占舞台层（环收缩消失后单独登场，只播 1 轮） =====
      if (this.showMascotAnim) {
        Stack() {
          LottieAnimation({
            animPath: 'animations/mascot.json',
            animName: 'checkin-mascot',
            loop: false,
            autoPlay: true,
            contentMode: 'Contain',
            accessibilityLabel: '', // 外层 Stack 统一朗读，Lottie 置装饰不重复朗读
            onLoaded: (): void => this.onMascotLoaded()
          })
        }
        .width(this.mascotSoloSize)
        .height(this.mascotSoloSize)
        .hitTestBehavior(HitTestMode.None)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.7, y: 0.7 }))
          .animation({ duration: 200, curve: Curve.EaseOut }))
        .accessibilityLevel('no')
      }
    }
    .width(this.buttonSize + 32)
    .height(this.buttonSize + 32)
    .accessibilityGroup(true)
    // HUI-039：小猫欢呼期间朗读语义带庆祝上下文，播完回到"已打卡"
    .accessibilityText(this.isChecked ?
      (this.showMascotAnim ?
        '打卡签到按钮，当前状态：已打卡，小猫欢呼庆祝中' :
        '打卡签到按钮，当前状态：已打卡') :
      '打卡签到按钮，当前状态：未打卡')
  }

  /**
   * 计算粒子 X 偏移（基于角度和距离）
   */
  private calcOffsetX(p: ParticleData): number {
    const rad = p.angle * Math.PI / 180;
    return Math.cos(rad) * p.distance;
  }

  /**
   * 计算粒子 Y 偏移（基于角度和距离）
   */
  private calcOffsetY(p: ParticleData): number {
    const rad = p.angle * Math.PI / 180;
    return Math.sin(rad) * p.distance;
  }

  /**
   * 获取已打卡态的填充色（主题色，带硬编码回退）
   */
  private getCheckedColor(): string {
    // HUI-034：打卡完成态套 btnPrimary 雾霾蓝（大动作按钮/勾选完成底）
    return this.tokens ? this.tokens.btnPrimary : '#738A9C';
  }

  /** HUI-040：半透明版本：ArkUI hex-alpha 为 #AARRGGBB，需前置 alpha */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  /**
   * 处理打卡点击：触觉反馈 + 光晕扩散
   * HUI-039：原地弹跳(0.92→1.06→1.0)移除——环收缩消失（startCheckedSequence）即点击动效，
   *          由父组件置 isChecked=true 后经 @Watch 统一驱动。
   */
  private handleCheckIn(): void {
    // 触觉反馈
    try {
      vibrator.startVibration({
        type: 'time',
        duration: 15
      }, {
        id: 0,
        usage: 'touch'
      });
    } catch (e) {
      // 忽略振动失败
      console.info('[CheckInButton] vibrator not available, skipping haptic');
    }

    // 光晕扩散动画
    this.triggerGlow();

    // 触发父组件回调（父组件会更新 isChecked）
    if (this.onCheckIn) {
      this.onCheckIn();
    }
  }

  /**
   * 光晕扩散：从中心向外扩大并淡出
   */
  private triggerGlow(): void {
    this.glowScale = 1.0;
    this.glowOpacity = 0.45;
    this.showGlow = true;

    animateTo({ duration: 500, curve: Curve.EaseOut }, () => {
      this.glowScale = 2.5;
      this.glowOpacity = 0;
    });

    // 动画完成后隐藏光晕层
    setTimeout(() => {
      this.showGlow = false;
      this.glowScale = 1.0;
    }, 520);
  }

  /**
   * 触发粒子庆祝动画（父组件在打卡成功后调用）
   * 12 颗粒子从中心向四周飞出，持续 1.5s
   */
  triggerCelebration(): void {
    this.celebrating = true;

    // 1.5s 后自动停止
    setTimeout(() => {
      this.celebrating = false;
    }, 1500);
  }

  // ===== HUI-039：打卡成功三段式编排 =====
  // 段①环弹性收缩消失(1→1.06→0) → 段②小猫独占登场播 1 轮 → 段③环 0→1.08→1.0 弹性回归对勾态

  /**
   * 段①+段②：环收缩 → 小猫登场。
   * reduce_motion 开启时全程跳过（环不收缩，isChecked 分支直接渲染对勾）。
   */
  private startCheckedSequence(): void {
    if (this.reduceMotion) {
      this.clearMascotTimers();
      this.showMascotAnim = false;
      this.ringScale = 1.0; // 减弱动效：环保持原位，直达对勾
      return;
    }
    this.clearMascotTimers();
    // 段①：环弹性收缩——先 1.06 蓄力过冲，再缩到 0 消失
    animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
      this.ringScale = 1.06;
    });
    this.phaseTimerIds.push(setTimeout(() => {
      animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
        this.ringScale = 0;
      });
    }, 120));
    // 段②：环缩没后小猫登场，同时调度兜底（加载失败也能回归对勾）
    this.phaseTimerIds.push(setTimeout(() => {
      this.showMascotAnim = true;
      this.mascotFallbackTimerId = setTimeout(() => {
        this.endMascotPhase();
      }, this.mascotFallbackMs);
    }, 320));
  }

  /**
   * Lottie DOMLoaded 锚点：取消兜底，改用精确定时（自加载完成起播满 1 轮）
   */
  private onMascotLoaded(): void {
    if (!this.showMascotAnim) {
      return; // 已被提前结束（组件状态回退等），忽略迟到回调
    }
    if (this.mascotFallbackTimerId >= 0) {
      clearTimeout(this.mascotFallbackTimerId);
      this.mascotFallbackTimerId = -1;
    }
    this.mascotEndTimerId = setTimeout(() => {
      this.endMascotPhase();
    }, this.mascotOneLoopMs);
  }

  /**
   * 段③：小猫退场（transition 淡出）→ 环从 0 弹性放大回归（0→1.08 过冲→1.0），显示对勾态
   */
  private endMascotPhase(): void {
    this.clearMascotTimers();
    if (!this.showMascotAnim) {
      return; // 幂等：已结束/未开始时不重复回归
    }
    this.showMascotAnim = false;
    animateTo({ duration: 280, curve: Curve.EaseOut }, () => {
      this.ringScale = 1.08;
    });
    this.phaseTimerIds.push(setTimeout(() => {
      animateTo({ duration: 160, curve: Curve.EaseInOut }, () => {
        this.ringScale = 1.0;
      });
    }, 280));
  }

  /**
   * 复位三段式（状态回退/跨天刷新）：清定时器 + 小猫下场 + 环复位原尺寸
   */
  private resetMascotPhase(): void {
    this.clearMascotTimers();
    this.showMascotAnim = false;
    this.ringScale = 1.0;
  }

  /**
   * 清理三段式全部定时器（aboutToDisappear / 状态回退 / 幂等结束共用）
   */
  private clearMascotTimers(): void {
    if (this.mascotFallbackTimerId >= 0) {
      clearTimeout(this.mascotFallbackTimerId);
      this.mascotFallbackTimerId = -1;
    }
    if (this.mascotEndTimerId >= 0) {
      clearTimeout(this.mascotEndTimerId);
      this.mascotEndTimerId = -1;
    }
    for (const id of this.phaseTimerIds) {
      clearTimeout(id);
    }
    this.phaseTimerIds = [];
  }
}
