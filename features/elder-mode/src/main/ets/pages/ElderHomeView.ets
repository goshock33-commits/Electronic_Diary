// <!-- agentID: HUI -->
// fix: HUI-T105 —— 点通知拉起 + TTS 复述消费侧：@StorageLink('elder_tts_seq') @Watch 收 EntryAbility
//   解析 want 后写入的复述载荷（elder_tts_text），经 TtsService.enqueue 排队播报；
//   消费标记 elder_tts_consumed_seq 防组件重建（换肤/页面重挂载）重播；冷启动载荷早于组件构建，
//   aboutToAppear 主动消费一次（@Watch 不触发初值）。
// 组件：ElderHomeView 长辈模式首页（内容层 @Component，壳由 MainPage 接线）
// 关联模块：features/elder-mode（HAR）
// 视觉：全屏柔和渐变背景（theme_tokens.gradientHero，缺省暖米色兜底）+ 居中语音猫（Lottie）
// 交互：点击猫咪触发 onVoiceTap 回调（语音入口由宿主接线）；isListening 时三层同心圆扩散脉冲
//       （对齐 VoiceListenRing §1.6 ping/pulse 范式）
// 适老化：大字号（24vp+）、高对比主文字、点击热区 >= 220vp 大目标
// 运行时崩溃防范（PROJECT_SPEC §9）：无 getter-in-build 返回 Resource；字段初值不含 $r()；
//       @StorageLink 判空；@Prop 不与内置属性重名；对象字面量均有接口类型声明（§8.2）
// 触摸链路（F2）：LottieAnimation 内部 hitTestBehavior(None) 全透传，onClick 挂在父 Stack 上
// 开发范式：ArkTS 声明式开发范式（Stage 模型）

import { LottieAnimation, SPACING, TtsService } from '@ohos/shared';
import type { ThemeColorTokens } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'ElderHomeView';
const DOMAIN = 0x0000;

/** 猫咪 Lottie 资源（rawfile 相对路径，纯字符串顶层 const，无 $r() → 不触 §9.3） */
const ELDER_CAT_ANIM_PATH: string = 'animations/talkbot.json';
/** 猫咪渲染尺寸(vp)——长辈模式放大主体（HomePage cat-pookie 150vp 基础上加码） */
const ELDER_CAT_SIZE: number = 80;
/** 点击热区直径(vp)——适老化大目标（含脉冲环留白） */
const ELDER_TAP_AREA: number = 120;
/** 脉冲扩散周期(ms)（对齐 VoiceListenRing 1600ms 节拍） */
const PULSE_DURATION: number = 1600;
/** 兜底渐变（暖米色 → 柔杏色，无青色；theme_tokens 未注入时使用） */
const FALLBACK_GRADIENT_TOP: string = '#FDF6EC';
const FALLBACK_GRADIENT_BOTTOM: string = '#F3E2CC';
/** 兜底主文字色（高对比近黑） */
const FALLBACK_TEXT_PRIMARY: string = '#1A1A1A';
/** 兜底次要文字色 */
const FALLBACK_TEXT_SECONDARY: string = '#5C5C5C';
/** 兜底脉冲环色（暖灰，避免大红/青色） */
const FALLBACK_RING_COLOR: string = '#C9B8A0';

/** 渐变色标（§8.2：对象字面量须有接口类型声明；[string, number] 元组数组由方法组装） */
type GradientStop = [string, number];

/**
 * ElderHomeView —— 长辈模式首页内容层。
 *
 * 典型用法（宿主壳接线）：
 *   ElderHomeView({
 *     isListening: this.voiceListening,
 *     onVoiceTap: () => { this.toggleVoice(); }
 *   })
 */
@Component
export struct ElderHomeView {
  /** 语音监听态（true=猫咪周围脉冲扩散；父组件驱动） */
  @Prop @Watch('onListeningChanged') isListening: boolean = false;
  /** 主题令牌（未注入时走暖米色兜底，§9 判空使用） */
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** HUI-T105: 复述请求序号——EntryAbility 解析通知 want 后自增写入，@Watch 触发消费 */
  @StorageLink('elder_tts_seq') @Watch('onTtsSeqChanged') ttsSeq: number = 0;
  /** 点击语音猫回调（语音会话由宿主接线，本组件只发意图） */
  onVoiceTap?: () => void;

  // 三层脉冲：缩放放大 + 透明度递减（字段初值纯数字，§9）
  @State private ring1Scale: number = 1;
  @State private ring2Scale: number = 1;
  @State private ring3Scale: number = 1;
  @State private ring1Opacity: number = 0;
  @State private ring2Opacity: number = 0;
  @State private ring3Opacity: number = 0;

  aboutToAppear(): void {
    if (this.isListening) {
      this.startPulse();
    }
    // HUI-T105: 冷启动点通知——want 解析早于本组件构建，序号已就位（@Watch 不触发初值），主动消费一次
    this.consumePendingTts();
  }

  /** 监听态切换：驱动脉冲动画启停 */
  onListeningChanged(): void {
    if (this.isListening) {
      this.startPulse();
    } else {
      this.stopPulse();
    }
  }

  /** HUI-T105: 序号变化（热启动点通知，EntryAbility 已写入新载荷）→ 消费复述 */
  onTtsSeqChanged(): void {
    this.consumePendingTts();
  }

  /**
   * HUI-T105: 消费 AppStorage 复述载荷——elder_tts_seq 大于已消费标记时播报 elder_tts_text。
   * · 消费标记存 AppStorage（elder_tts_consumed_seq）：组件因换肤/页面重建重挂载时不重播；
   * · 先标记后播：防 @Watch 与 aboutToAppear 双入口重复消费；
   * · enqueue 排队模式（queueMode=0）不打断在播语音；失败仅记日志不外抛（§9 崩溃防范）。
   */
  private consumePendingTts(): void {
    try {
      const seq: number = this.ttsSeq;
      if (seq <= 0) {
        return;
      }
      const consumedRaw: number | undefined = AppStorage.get<number>('elder_tts_consumed_seq');
      const consumed: number = consumedRaw !== undefined ? consumedRaw : 0;
      if (seq <= consumed) {
        return;
      }
      const text: string | undefined = AppStorage.get<string>('elder_tts_text');
      if (text === undefined || text.length === 0) {
        return;
      }
      AppStorage.setOrCreate('elder_tts_consumed_seq', seq);
      TtsService.getInstance().enqueue(text).then((ok: boolean) => {
        hilog.info(DOMAIN, TAG, 'HUI-T105: respeak enqueued seq=%{public}d ok=%{public}d', seq, ok ? 1 : 0);
      }).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'HUI-T105: respeak enqueue failed: %{public}s', err.message);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'HUI-T105: consumePendingTts failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 三层错峰扩散（radar 脉冲，iterations=-1 无限循环，§1.6 ping/pulse） */
  private startPulse(): void {
    this.ring1Opacity = 0.45;
    this.ring2Opacity = 0.45;
    this.ring3Opacity = 0.45;
    animateTo({ duration: PULSE_DURATION, curve: Curve.EaseOut, iterations: -1, playMode: PlayMode.Normal }, () => {
      this.ring1Scale = 1.7;
      this.ring1Opacity = 0;
    });
    animateTo({
      duration: PULSE_DURATION, curve: Curve.EaseOut, iterations: -1, delay: 530, playMode: PlayMode.Normal
    }, () => {
      this.ring2Scale = 1.7;
      this.ring2Opacity = 0;
    });
    animateTo({
      duration: PULSE_DURATION, curve: Curve.EaseOut, iterations: -1, delay: 1060, playMode: PlayMode.Normal
    }, () => {
      this.ring3Scale = 1.7;
      this.ring3Opacity = 0;
    });
  }

  private stopPulse(): void {
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.ring1Scale = 1;
      this.ring2Scale = 1;
      this.ring3Scale = 1;
      this.ring1Opacity = 0;
      this.ring2Opacity = 0;
      this.ring3Opacity = 0;
    });
  }

  // ==== 取色（普通方法非 getter-in-build 返回 Resource；此处均为 string，判空兜底 §9）====
  private getGradientColors(): GradientStop[] {
    const top: string = this.tokens !== null ? this.tokens.gradientHero[0] : FALLBACK_GRADIENT_TOP;
    const bottom: string = this.tokens !== null ? this.tokens.gradientHero[1] : FALLBACK_GRADIENT_BOTTOM;
    const stops: GradientStop[] = [[top, 0.0], [bottom, 1.0]];
    return stops;
  }

  private getTextPrimary(): string {
    return this.tokens !== null ? this.tokens.textPrimary : FALLBACK_TEXT_PRIMARY;
  }

  private getTextSecondary(): string {
    return this.tokens !== null ? this.tokens.textSecondary : FALLBACK_TEXT_SECONDARY;
  }

  private getRingColor(): string {
    return this.tokens !== null ? this.tokens.border : FALLBACK_RING_COLOR;
  }

  private getHintText(): string {
    return this.isListening ? '我在听，请慢慢说' : '点一点猫咪，说说今天的事';
  }

  build() {
    Column() {
      // 上 Blank 把文字推到中间
      Blank().layoutWeight(1)

      // 大字号引导文案（屏幕中间）
      Text(this.getHintText())
        .fontSize(26).fontWeight(FontWeight.Bold)
        .fontColor(this.getTextPrimary()).textAlign(TextAlign.Center)

      Text('说完的话会帮您记进日记')
        .fontSize(20).fontColor(this.getTextSecondary())
        .textAlign(TextAlign.Center).margin({ top: SPACING.cardGap })

      // 下 Blank 把猫推到底部 ====
      Blank().layoutWeight(1)

      // 语音猫（底部，比导航栏猫 52vp 大一点）
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(ELDER_CAT_SIZE).height(ELDER_CAT_SIZE).fill(Color.Transparent)
          .stroke(this.getRingColor()).strokeWidth(3)
          .scale({ x: this.ring1Scale, y: this.ring1Scale }).opacity(this.ring1Opacity)
          .hitTestBehavior(HitTestMode.None)
        Circle().width(ELDER_CAT_SIZE).height(ELDER_CAT_SIZE).fill(Color.Transparent)
          .stroke(this.getRingColor()).strokeWidth(3)
          .scale({ x: this.ring2Scale, y: this.ring2Scale }).opacity(this.ring2Opacity)
          .hitTestBehavior(HitTestMode.None)
        Circle().width(ELDER_CAT_SIZE).height(ELDER_CAT_SIZE).fill(Color.Transparent)
          .stroke(this.getRingColor()).strokeWidth(3)
          .scale({ x: this.ring3Scale, y: this.ring3Scale }).opacity(this.ring3Opacity)
          .hitTestBehavior(HitTestMode.None)
        LottieAnimation({
          animPath: ELDER_CAT_ANIM_PATH, loop: true, autoPlay: true,
          animName: 'elder-voice-cat', accessibilityLabel: '语音猫咪，点击开始说话',
          animWidth: ELDER_CAT_SIZE, animHeight: ELDER_CAT_SIZE
        })
      }
      .width(ELDER_TAP_AREA).height(ELDER_TAP_AREA)
      .margin({ bottom: 40 })
      .onClick(() => { if (this.onVoiceTap) { this.onVoiceTap(); } })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    // 全屏柔和渐变（theme gradientHero；未注入主题时暖米色兜底，无青色）
    .linearGradient({
      angle: 180,
      colors: this.getGradientColors()
    })
  }
}
