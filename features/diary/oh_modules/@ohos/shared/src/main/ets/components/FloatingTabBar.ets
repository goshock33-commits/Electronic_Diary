// <!-- agentID: HUI-001 · P1-04 滑移 by HUI-053 · AI 页浮球收缩 by HUI-078 · 非浮球态点击修复 by HUI-080 · 非浮球态触摸命中修复 by HUI-082 · 导航栏消失回归修复 by HUI-001 · AI Tab 偶发点击失灵根治(层3手势改条件渲染)+陈旧收缩定时器修复 by HUI-001 · 手绘换肤 5 Tab SymbolGlyph→SketchIcon(不碰手势/收缩逻辑) by HUI-016 · AI 伙伴 Tab/浮球/平板图标→TalkBotAnimation(T-LT04, 仅替换图标节点·不碰手势/收缩/激活背景) by HUI-019 · TalkBot 放大(胶囊36/浮球54/平板38, clip不变仅裁空白角)+浮球态去青色圆底(背景透明/无blur/无shadow/无border) by HUI-019 · 胶囊 AI Tab 去可见文字+动画放大至52vp占满列(无障碍靠Column.accessibilityText保留AI伙伴语义, 仅改AI Tab不动其余4Tab) by HUI-019 · 手机选中态黑底青球→骑栏白圆气泡(去青底/圆=栏高×1.2上下双凸/白渐变+黑图标/光影四件套+栏面接触影/spring 滑移; 未选中图标改中性灰; 仅改选中态指示器·isBallMode/TalkBot 浮球收缩一行未动) by HUI-001 · 手绘换回系统图标：4 Tab SketchIcon→SymbolGlyph(IconMapper NAV_* 历史常量, 手机24/平板22, 选中黑/未选中灰同语义; AI Tab Lottie/浮球收缩/骑栏白圆一行不动) by HUI-001 · AI 页再次进入不收缩修复(isManuallyExpanded 进入时清除) by HUI-043 -->
// 平板 MiniBar 选中态同款改为骑栏白圆（复用 buildRidingBubble，竖向滑移），与手机一致 by HUI-001。
// 组件：自适应悬浮导航胶囊（激活青球 spring 平滑滑移 + AI 页收缩为可拖拽浮球）
// 关联设计稿：UX-001_redesign_report.md §1.6 / §2.1（激活 Tab 共享元素滑移 layoutId）
// 关联计划：PLN-003 P1-04（FloatingTabBar 激活球共享元素滑移，spring 350/25）
// 关联架构：3.2 shared/components / FloatingTabBar
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 无障碍：遵守 T042 规范（触控热区 >= 48x48vp, accessibilityText 不为空）
// 适配：手机（水平胶囊，AI 页收缩浮球）/ 平板（竖向 MiniBar 图标无文字）/ 折叠屏（跟随断点）
// 崩溃防范（PROJECT_SPEC §9）：
//   · @StorageLink tokens 判空回退（全部经普通方法 c* 兜底）；
//   · getActiveIndex / currentX / currentY / barWidthVp 均为普通方法（非 build 内 getter）；
//   · @Prop selectedTabIndex 默认值为 number 0，不含 $r()；PanGesture 处理不涉及 $r() 字段初值。
// AI 页浮球交互（HUI-078）：
//   · selectedTab 切到 'ai' → 胶囊从两侧向中间收缩成青球（animateTo springMotion）并滑到屏幕右缘中部；
//   · 浮球可拖拽跟手（PanGesture 实时），松手吸附最近的左/右边缘，上下限位（避开顶部与底部输入框）；
//   · 再次点击浮球 → 回到原位并展开恢复完整导航栏；离开 AB Tab 自动恢复胶囊。

import type { ThemeColorTokens, TabItemConfig } from '../theme/ThemeConfig';
import { RADIUS } from '../theme/LayoutTokens';
import { curves } from '@kit.ArkUI';
// HUI-001 · 手绘换回系统图标：4 Tab 图标 SketchIcon→SymbolGlyph（IconMapper NAV_* 历史常量，图标名均经本地全量图标库 grep 验证）；
//   AI Tab 仍走 TalkBotAnimation（Lottie），不涉本次改动。SketchIcon 组件本体保留（统计页对号仍在用）。
import { IconMapper } from '../utils/IconMapper';
// HUI-019 · T-LT04：导航 AI 伙伴 Lottie 动画（TalkBotAnimation 循环），同模块相对引入（LottieAnimation 内部 Canvas 已 hitTestBehavior(None)，触摸透传给父容器，防 HUI-001 点击失灵回归）
import { LottieAnimation } from './LottieAnimation';

/** 单 Tab 水平步距（列宽 56vp，无水平间隙）— 青球 x 位移 = index * 步距 */
const MOBILE_ITEM_STRIDE: number = 56;
/** 单 Tab 竖向步距（列高 56vp + 底间距 4vp）— 青球 y 位移 = index * 步距 */
const TABLET_ITEM_STRIDE: number = 60;
/** 胶囊左右内边距合计（left 4 + right 4） */
const MOBILE_BAR_PADDING: number = 8;
/** 胶囊高度（内容 56 + 上下内边距 8） */
const MOBILE_BAR_HEIGHT: number = 64;
/** 胶囊悬浮底距 */
const MOBILE_BAR_BOTTOM_GAP: number = 28;
/** 激活球滑移曲线：interpolatingSpring(velocity=0, mass=1, stiffness=350, damping=25) */
const SLIDE_SPRING: ICurve = curves.interpolatingSpring(0, 1, 350, 25);
/** 浮球收缩/展开/吸边曲线：springMotion(response=0.55, dampingFraction=0.72) —— 自然弹性不生硬 */
const BALL_SPRING: ICurve = curves.springMotion(0.55, 0.72);

// ── 骑栏白圆气泡（选中态指示器 · 黑白锁定 v4，UX-001_navbar_bubble_design.md §3/§4）─────────
/** 气泡直径比例（栏高 ×1.2，用户四轮锁定值） */
const BUBBLE_RATIO: number = 1.2;
/** 气泡直径（vp）= 栏高 64 × 1.2 = 76.8；完整圆，上下各凸出 (D−64)/2 ≈ 6.4vp（双凸不裁切） */
const BUBBLE_DIAMETER: number = MOBILE_BAR_HEIGHT * BUBBLE_RATIO;
/** 气泡居中偏移（vp）：气泡比 Tab 列(56)大，需左移/上移 (56−D)/2 ≈ −10.4，使圆心对齐 Tab 中心且垂直居中于栏 */
const BUBBLE_CENTER_OFFSET: number = (MOBILE_ITEM_STRIDE - BUBBLE_DIAMETER) / 2;
/**
 * 圆填充/图标为「恒浅圆 + 恒黑图标」固定设计常量（= surface/白、textPrimary/黑 的浅色语义值）：
 * 任务点 5 明确「深色下圆仍浅、图标黑仍在浅圆上高对比」，而 surface/textPrimary token 在深色会反相
 * （surface→深、textPrimary→浅），故此二者按用户锁定的固定浅色实现（深浅一致），不写死任何青色。
 * 栏体/未选中图标/未选中文字仍走 this.tokens（cCardBg / cTextTertiary），随主题自适应。
 */
const BUBBLE_FILL_TOP: string = '#0A59F7';
const BUBBLE_ICON_COLOR: string = '#FFFFFF';
const BUBBLE_RIM: string = 'rgba(10,89,247,0.25)';
const BUBBLE_SHADOW_DROP: string = 'rgba(10,89,247,0.30)';
const BUBBLE_SHADOW_NEAR: string = 'rgba(10,89,247,0.18)';
const BUBBLE_CONTACT: string = 'rgba(10,89,247,0.12)';
const BUBBLE_INNER_HI: string = 'rgba(255,255,255,0.25)';
const BUBBLE_INNER_LO: string = 'rgba(0,0,0,0.12)';
const BUBBLE_TRANS_W: string = 'rgba(255,255,255,0)';
const BUBBLE_TRANS_K: string = 'rgba(0,0,0,0)';

/**
 * FloatingTabBar 配置接口
 */
export interface FloatingTabBarConfig {
  /** Tab 项列表 */
  tabs: TabItemConfig[];
  /** 当前激活的 Tab key */
  activeKey: string;
  /** 布局方向：mobile=水平胶囊 | tablet=竖向 MiniBar */
  layoutDirection: 'mobile' | 'tablet';
  /** Tab 切换回调 */
  onTabChange: (key: string) => void;
}

@Component
export struct FloatingTabBar {
  @Prop tabs: TabItemConfig[] = [];
  @Prop activeKey: string = '';
  @Prop layoutDirection: string = 'mobile';
  /** MainPage 传入的当前选中 Tab 索引（HUI-078）：用于判断是否进入 AI 页触发浮球收缩 */
  @Prop @Watch('onSelectedTabIndexChange') selectedTabIndex: number = 0;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  onTabChange?: (key: string) => void;

  // ── 浮球形态状态（HUI-078）─────────────────────────────
  /** 当前是否为浮球形态（true=已收缩为球） */
  @State private isBallMode: boolean = false;
  /** AI 页手动展开覆盖：点击浮球展开后，即使仍在 AI 页也保持胶囊，直到离开再回来 */
  @State private isManuallyExpanded: boolean = false;
  /**
   * HUI-019 · T-LT04：浮球「收缩/展开」spring 进行中标志。
   * spring 期间置 true → 门控 TalkBotAnimation 的 shouldPlay 暂停播放（F2：避免变换×重绘叠加掉帧），
   * spring 结束（animateTo onFinish）复位 false 恢复播放。仅影响 Lottie 播放门控，不参与手势/命中测试。
   */
  @State private isSpringAnimating: boolean = false;
  /** 浮球相对「右缘中部」锚点的位移（拖拽 + 吸边动画驱动） */
  @State private ballOffsetX: number = 0;
  @State private ballOffsetY: number = 0;
  /** 屏幕可用区尺寸（vp，onAreaChange 实测刷新；含安全默认值防首帧异常） */
  @State private screenWidthVp: number = 360;
  @State private screenHeightVp: number = 780;
  // HUI-001：导航栏猫语音聆听态（AIChatView startVoiceInput/stopVoiceInput 同步 AppStorage → 驱动波纹动画）
  @StorageProp('ai_voice_listening') @Watch('onVoiceListeningChange') aiVoiceListening: boolean = false;
  // HUI-001：波纹相位（setInterval 驱动 ripplePhase++ → 三圈不同偏移走循环 animateTo）
  @State private voiceRipplePhase: number = 0;
  private voiceRippleTimer: number = -1;

  // 拖拽基准 & 判定
  private dragBaseX: number = 0;
  private dragBaseY: number = 0;
  private hasDragged: boolean = false;

  // 浮球几何常量
  private readonly BALL_SIZE: number = 60;
  private readonly BALL_EDGE_GAP: number = 14;
  private readonly BALL_MIN_TOP: number = 100;
  /** 底部预留高度（避免浮球压住 AI 对话输入框） */
  private readonly BALL_BOTTOM_SAFE: number = 150;

  aboutToAppear(): void {
    // 初始若已处于 AI 页，直接以浮球形态呈现（无需入场动画）
    if (this.isAiSelected()) {
      this.isBallMode = true;
    }
  }

  aboutToDisappear(): void {
    // 清理 AI 收缩延迟定时器
    if (this.aiCollapseTimerId !== -1) {
      clearTimeout(this.aiCollapseTimerId);
      this.aiCollapseTimerId = -1;
    }
    // HUI-001：清理语音波纹定时器
    if (this.voiceRippleTimer !== -1) {
      clearInterval(this.voiceRippleTimer);
      this.voiceRippleTimer = -1;
    }
  }

  /** HUI-001：aiVoiceListening 变化 → 启动/停止波纹 setInterval */
  private onVoiceListeningChange(): void {
    if (this.aiVoiceListening && this.voiceRippleTimer === -1) {
      this.voiceRippleTimer = setInterval(() => {
        this.voiceRipplePhase = (this.voiceRipplePhase + 50) % 600;
      }, 50);
    } else if (!this.aiVoiceListening && this.voiceRippleTimer !== -1) {
      clearInterval(this.voiceRippleTimer);
      this.voiceRippleTimer = -1;
      this.voiceRipplePhase = 0;
    }
  }

  build() {
    if (this.layoutDirection === 'tablet') {
      // 平板模式：竖向 MiniBar（不参与 AI 浮球收缩）
      this.buildTabletBar();
    } else {
      // 手机/折叠屏模式：全屏透传浮层 + 可形变胶囊/浮球
      this.buildMobileOverlay();
    }
  }

  /**
   * 手机模式：胶囊态与浮球态统一使用同一「全屏透传浮层」容器（HUI-001 修复 HUI-082 导致的导航栏消失）
   *
   * ⛔ 回归根因（HUI-082 引入）：
   *   HUI-082 把非浮球态容器从「全屏 Stack（原点=屏幕左上角）」改成「底部对齐、0 高的 Column」，
   *   但 buildMorphCapsule 仍以 .position({ y: currentY() }) 做绝对定位，且 currentY() 返回的是
   *   「相对屏幕左上角」的绝对坐标（screenHeightVp - 64 - 28 ≈ 688）。改容器后该坐标变成「相对贴底
   *   Column 原点（≈屏幕底部）」，叠加后胶囊被推到屏幕下方约 688vp → 完全移出可视区，导航栏「消失」；
   *   且非浮球态无 onAreaChange，screenWidthVp/screenHeightVp 恒为默认值 360/780，真机横向居中亦失准。
   *
   * ✅ 修复：两态统一挂在同一全屏 Stack 浮层（原点=屏幕左上角），使 currentX()/currentY() 的绝对
   *   坐标在两态下都相对同一原点，胶囊回到底部居中、浮球正常吸右缘：
   *   · onAreaChange 实测屏幕尺寸，供胶囊居中与浮球拖拽/吸边定位（两态共用）；
   *   · HitTestMode.None → 浮层自身不吞触摸：空白区触摸透传给下方 Tab 内容（兄弟节点），
   *     胶囊内 Tab 按钮（子节点，HitTestMode.Block）正常响应；
   *   · HUI-080 的「层 3 手势门控」（非浮球态 Tab 点击不灵敏修复）保持不变，触摸灵敏度不回退。
   */
  @Builder
  buildMobileOverlay() {
    Stack() {
      this.buildMorphCapsule()
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .hitTestBehavior(HitTestMode.None)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.screenWidthVp = newValue.width as number;
      this.screenHeightVp = newValue.height as number;
    })
  }

  /**
   * 可形变容器：胶囊态 ↔ 浮球态由 isBallMode 驱动，宽/高/圆角/背景/位置/子层透明度
   * 全部绑定 isBallMode，切换时用 animateTo(BALL_SPRING) 包裹 → 一次 spring 同时完成
   * 「从两侧向中间收缩成球」+「滑到右缘中部」。拖拽时直接更新 ballOffset（不经动画）实时跟手。
   */
  @Builder
  buildMorphCapsule() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 层 1：骑栏白圆气泡（选中态指示器）—— 替换原「56×56 青色实心球」
      //   去青底 → 完整圆上下双凸 + 纯黑白光影浮起 + spring 滑移。位于 Tab 行之下（沿用原层 1 的 z 位与
      //   hitTestBehavior(None)，不入手势竞技场）；⛔ AI 浮球收缩(isBallMode/TalkBot) 逻辑完全不碰。
      this.buildRidingBubble()

      // 层 2：Tab 项行（图标 + 标签）—— 胶囊态可交互，浮球态禁用并淡出
      Row() {
        ForEach(this.tabs, (tab: TabItemConfig, idx: number) => {
          Column() {
            // HUI-019 · T-LT04（F2 共享 ForEach + if 分支）：仅 AI 伙伴 Tab 的图标节点替换为 TalkBotAnimation，
            //   其余 4 Tab 走 SymbolGlyph（HUI-001 手绘换回系统图标；点击/激活态不受影响）。仅替换图标节点，Column 尺寸、
            //   .onClick 点击逻辑、层级手势一律不动。TalkBot 自带配色，不随深浅/激活态染色（激活态背景由层1青球控制）。
            //   限流（F3 + JUDGE N1）：胶囊态播放；浮球态本层被 opacity(0) 隐藏 → shouldPlay=false 暂停隐藏实例；
            //   收缩/展开 spring 期间 shouldPlay=false 暂停。
            //   HUI-019 · 用户视觉调整：AI Tab 去掉可见 Text 文字标签（见下方 if(tab.key!=='ai')），动画放大至 52vp
            //   占满 56vp 列并垂直居中；无障碍语义靠 LottieAnimation.accessibilityLabel + Column.accessibilityText 兜住。
            if (tab.key === 'ai') {
              // HUI-001：Lottie + 语音聆听波纹（青色，往外扩→渐隐消失）
              Stack() {
                // HUI-001：波纹圈（3 圈青色，从猫中心往外扩→渐隐，不裁切）
                if (this.aiVoiceListening) {
                  ForEach([0, 1, 2], (ripple: number) => {
                    Column()
                      .width(72)
                      .height(72)
                      .borderRadius(36)
                      .border({ width: 1.5, color: 'rgba(79,216,206,' + (0.5 - ripple * 0.15).toFixed(2) + ')' })
                      .scale({ x: 1 + (this.voiceRipplePhase % 600) / 600 * 2.5, y: 1 + (this.voiceRipplePhase % 600) / 600 * 2.5 })
                      .opacity(Math.max(0, 0.55 - ripple * 0.18 - (this.voiceRipplePhase % 600) / 600 * 0.5))
                      .animation({ duration: 500 + ripple * 150, curve: Curve.EaseOut })
                  }, (ripple: number) => ripple.toString())
                }
                LottieAnimation({
                  animPath: 'animations/talkbot.json',
                  animName: 'nav-talkbot-tab',
                  loop: true,
                  autoPlay: true,
                  frameRate: 30,
                  contentMode: 'Contain',
                  animWidth: 52,
                  animHeight: 52,
                  accessibilityLabel: tab.label,
                  shouldPlay: !this.isBallMode && !this.isSpringAnimating
                })
              }
            } else {
              // 标准 Tab 图标：选中蓝色，未选中灰色
              SymbolGlyph(this.tabKeyToSymbol(tab.key))
                .fontSize(24)
                .fontColor([this.isActive(tab.key) ?
                  (this.tokens ? this.tokens.btnPrimary : '#0A59F7') :
                  (this.tokens ? this.tokens.textTertiary : '#999999')])
            }
            // 所有 Tab 始终显示文字标签
            Text(tab.label)
              .fontSize(10)
              .fontWeight(this.isActive(tab.key) ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.isActive(tab.key) ?
                (this.tokens ? this.tokens.btnPrimary : '#0A59F7') :
                (this.tokens ? this.tokens.textTertiary : '#999999'))
              .margin({ top: 2 })
          }
          .width(56)
          .height(56)
          .constraintSize({ minWidth: 56, minHeight: 48 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.handleTabClick(tab.key);
          })
          // HUI-001：AI 伙伴 Tab 长按触发语音输入（400ms，与短按切换共存）。
          //   跨组件信号：写 AppStorage → AIChatView @StorageProp @Watch → startVoiceInput / stopVoiceInput。
          .gesture(
            LongPressGesture({ repeat: false, duration: 400 })
              .onAction(() => {
                if (tab.key === 'ai') {
                  if (!this.isActive(tab.key)) {
                    this.handleTabClick(tab.key);
                  }
                  AppStorage.setOrCreate('ai_voice_trigger', Date.now());
                }
              })
              .onActionEnd(() => {
                if (tab.key === 'ai') {
                  AppStorage.setOrCreate('ai_voice_stop', Date.now());
                }
              })
              .onActionCancel(() => {
                if (tab.key === 'ai') {
                  AppStorage.setOrCreate('ai_voice_stop', Date.now());
                }
              })
          )
          .accessibilityText(tab.label + '标签，' + (this.isActive(tab.key) ? '已选中，长按可语音输入' : '未选中'))
          .clip(tab.key !== 'ai' || !this.aiVoiceListening) // HUI-001：AI Tab 聆听态不裁切，允许波纹溢出
        }, (tab: TabItemConfig, idx: number) => tab.key)
      }
      .opacity(this.isBallMode ? 0 : 1)
      .enabled(!this.isBallMode)

      // 层 3：浮球中心图标 + 浮球态交互
      // 🔴 HUI-001 根治「AI Tab 偶发点击失灵」：由「常驻 + hitTestBehavior 门控」改为「仅浮球态条件渲染」。
      //   根因：旧版本层始终存在且以 width/height 100% 覆盖整条胶囊，携带 GestureGroup(Parallel:
      //     TapGesture + PanGesture)，仅靠反应式 hitTestBehavior(isBallMode ? Block : None) 休眠手势。
      //     PanGesture(distance=10) 在触摸按下时会开启「移动消歧窗口」，物理点击常伴随微小位移；
      //     该手势识别器对象仍挂在覆盖 Tab 行的顶层兄弟节点上，消歧窗口内会与 Tab 子项 onClick 的
      //     点击识别在手势竞技场中非确定性竞争，偶发把点击「吃掉」→ 约半数概率点了没反应。
      //     （SDK 语义 None=自身不响应但子节点响应，然而“门控一个已绑定的并行复合手势”并非逐帧原子，
      //       动画/重渲染帧内竞技场消歧仍会偏移，故不能依赖 hitTestBehavior 休眠手势。）
      //   修复：胶囊态本层（含手势）根本不进入组件树 → 无任何手势节点覆盖 Tab 行 → Tab onClick 100% 可靠；
      //        浮球态本层才渲染并置顶 Block 接管拖拽/点击。两态互斥，彻底消除跨态手势竞争。
      if (this.isBallMode && this.tabs.length > 0) {
        Column() {
          // HUI-019 · T-LT04：浮球中心图标 → TalkBotAnimation。浮球仅 AI 页出现（isBallMode 仅 isAiSelected 时置真，
          //   见 aboutToAppear/collapseToBall），故此处恒为 AI，无条件替换。⚠️ 仅替换图标节点：本层的
          //   hitTestBehavior(Block) 与下方 GestureGroup(TapGesture+PanGesture) 手势/条件渲染绝不触碰
          //   （HUI-001「两态互斥」根治保持不变；LottieAnimation 内部 Canvas 为 HitTestMode.None，不入手势竞技场）。
          //   限流：本层仅浮球态渲染，收缩/展开 spring 期间 shouldPlay=false 暂停（F2 变换×重绘不叠加）。
          LottieAnimation({
            animPath: 'animations/talkbot.json',
            animName: 'nav-talkbot-ball',
            loop: true,
            autoPlay: true,
            frameRate: 30,
            contentMode: 'Contain',
            animWidth: 54,
            animHeight: 54,
            accessibilityLabel: this.tabs[this.getActiveIndex()].label,
            shouldPlay: this.isBallMode && !this.isSpringAnimating
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .gesture(
          GestureGroup(GestureMode.Parallel,
            TapGesture({ count: 1, distanceThreshold: 10 })
              .onAction(() => {
                this.onBallTap();
              }),
            PanGesture({ distance: 10 })
              .onActionStart(() => {
                this.hasDragged = false;
                this.dragBaseX = this.ballOffsetX;
                this.dragBaseY = this.ballOffsetY;
              })
              .onActionUpdate((event: GestureEvent) => {
                this.hasDragged = true;
                // 实时跟手（vp）：直接更新位移，不经动画
                this.ballOffsetX = this.dragBaseX + event.offsetX;
                this.ballOffsetY = this.dragBaseY + event.offsetY;
              })
              .onActionEnd(() => {
                this.snapToEdge();
              })
          )
        )
      }
    }
    .width(this.isBallMode ? this.BALL_SIZE : this.barWidthVp())
    .height(this.isBallMode ? this.BALL_SIZE : MOBILE_BAR_HEIGHT)
    .borderRadius(this.isBallMode ? this.BALL_SIZE / 2 : RADIUS.card)
    .padding(this.isBallMode ? 0 : 4)
    .backgroundColor(this.isBallMode ? Color.Transparent : this.cCardBg())
    .backdropBlur(this.isBallMode ? 0 : 12)
    .shadow({
      radius: this.isBallMode ? 0 : 24,
      color: this.cShadow(),
      offsetX: 0,
      offsetY: 4
    })
    .clip(this.isBallMode)
    .position({ x: this.currentX(), y: this.currentY() })
    // 交互职责拆分（HUI-001 根治 AI Tab 偶发点击失灵）：
    //   · 胶囊态：容器与 Tab 行均不含手势节点，Tab 点击纯靠子项 onClick（子项 HitTestMode.Block）；层 3 不渲染；
    //   · 浮球态：层 3 才渲染并置顶（Block）承载拖拽/点击。两态手势节点互斥，杜绝并行手势抢占触摸序列。
    .accessibilityText(this.isBallMode ? '导航浮球，点击展开导航栏，可拖拽移动' : '底部导航栏')
  }

  /**
   * 滑动小圆点指示器（选中态）—— spring 滑移跟随当前 Tab。
   * 手机(横栏)/平板(竖栏 MiniBar) 共用。
   */
  @Builder
  buildRidingBubble() {
    Column()
      .width(6)
      .height(6)
      .borderRadius(3)
      .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#0A59F7')
      .translate({ x: this.bubbleTranslateX() + 25, y: this.bubbleTranslateY() - 4 })
      .animation({ curve: SLIDE_SPRING })
      .opacity(this.isBubbleVisible() ? 1 : 0)
      .hitTestBehavior(HitTestMode.None)
  }

  /**
   * 平板模式：竖向 MiniBar
   * 位于屏幕左侧，仅显示图标无文字；骑栏白圆气泡随 index 竖向 spring 滑移（与手机同款，复用 buildRidingBubble）。
   */
  @Builder
  buildTabletBar() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 层 1：骑栏白圆气泡（选中态指示器）—— 替换原竖向青色实心球，与手机同款。
      //   竖栏「厚度」= 宽 64（== 手机栏高 64）→ 复用 BUBBLE_DIAMETER(=64×1.2=76.8)，骑左右缘各凸 ≈6.4vp；
      //   随 getActiveIndex() 以 SLIDE_SPRING 竖向滑移（bubbleTranslateY）。父 Stack 未 clip(默认 false) → 凸出不裁。
      this.buildRidingBubble()

      Column() {
        ForEach(this.tabs, (tab: TabItemConfig, idx: number) => {
          Column() {
            // HUI-019 · T-LT04（F2 共享 ForEach + if 分支）：平板 MiniBar 仅 AI 图标替换为 TalkBotAnimation，
            //   其余 4 Tab 走 SymbolGlyph（HUI-001 手绘换回系统图标）。平板无浮球/spring，常驻播放；出屏由 LottieAnimation 内部
            //   onVisibleAreaChange 自暂停（S5）。仅替换图标节点，Column 尺寸/onClick/激活态不动。
            if (tab.key === 'ai') {
              LottieAnimation({
                animPath: 'animations/talkbot.json',
                animName: 'nav-talkbot-tablet',
                loop: true,
                autoPlay: true,
                frameRate: 30,
                contentMode: 'Contain',
                animWidth: 38,
                animHeight: 38,
                accessibilityLabel: tab.label,
                shouldPlay: true
              })
            } else {
              // 标准 Tab 图标：选中蓝色，未选中灰色
              SymbolGlyph(this.tabKeyToSymbol(tab.key))
                .fontSize(22)
                .fontColor([this.isActive(tab.key) ?
                  (this.tokens ? this.tokens.btnPrimary : '#0A59F7') :
                  (this.tokens ? this.tokens.textTertiary : '#999999')])
            }
          }
          .width(56)
          .height(56)
          .constraintSize({ minWidth: 56, minHeight: 48 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .margin({ bottom: 4 })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.handleTabClick(tab.key);
          })
          .accessibilityText(tab.label + '标签，' + (this.isActive(tab.key) ? '已选中' : '未选中'))
        }, (tab: TabItemConfig, idx: number) => tab.key)
      }
    }
    .width(64)
    .borderRadius(RADIUS.cardMd)
    .padding({ top: 8, bottom: 8, left: 4, right: 4 })
    .backgroundColor(this.cCardBg())
    .backdropBlur(12)
    .shadow({ radius: 24, color: this.cShadow(), offsetX: 0, offsetY: 4 })
    // 🔴 z-order 修复（与手机同款）：移除竖栏 1px border(cBorder) —— 骑栏白圆为本 Stack 子层，
    //   容器 border 绘制于子层之上会横穿凸出左右缘的白圆。去掉后栏缘由 shadow+backdropBlur+底色对比 定义。
    .position({ left: 20, top: '50%' })
    .translate({ x: 0, y: '-50%' })
  }

  // ════════════════════════════════════════════════════════════
  // 浮球定位 / 交互（普通方法，非 build 内 getter）
  // ════════════════════════════════════════════════════════════

  /** 胶囊内容宽度（vp）：列宽 * Tab 数 + 左右内边距 */
  private barWidthVp(): number {
    return this.tabs.length * MOBILE_ITEM_STRIDE + MOBILE_BAR_PADDING;
  }

  /** 容器左上角 X（vp）：浮球态锚右缘 + 拖拽位移；胶囊态水平居中 */
  private currentX(): number {
    if (this.isBallMode) {
      return this.ballAnchorLeft() + this.ballOffsetX;
    }
    return (this.screenWidthVp - this.barWidthVp()) / 2;
  }

  /** 容器左上角 Y（vp）：浮球态锚竖直居中 + 拖拽位移；胶囊态贴底 */
  private currentY(): number {
    if (this.isBallMode) {
      return this.ballAnchorTop() + this.ballOffsetY;
    }
    return this.screenHeightVp - MOBILE_BAR_HEIGHT - MOBILE_BAR_BOTTOM_GAP;
  }

  /** 浮球「右缘中部」锚点：左上角 X */
  private ballAnchorLeft(): number {
    return this.screenWidthVp - this.BALL_SIZE - this.BALL_EDGE_GAP;
  }

  /** 浮球「右缘中部」锚点：左上角 Y */
  private ballAnchorTop(): number {
    return (this.screenHeightVp - this.BALL_SIZE) / 2;
  }

  /** 松手吸边：左右吸附到最近边缘；上下限位（避开顶部与底部输入框） */
  private snapToEdge(): void {
    const anchorLeft: number = this.ballAnchorLeft();
    const centerX: number = anchorLeft + this.ballOffsetX + this.BALL_SIZE / 2;
    const targetLeft: number = centerX >= this.screenWidthVp / 2
      ? this.screenWidthVp - this.BALL_SIZE - this.BALL_EDGE_GAP
      : this.BALL_EDGE_GAP;
    const targetOffsetX: number = targetLeft - anchorLeft;

    const anchorTop: number = this.ballAnchorTop();
    let targetTop: number = anchorTop + this.ballOffsetY;
    const minTop: number = this.BALL_MIN_TOP;
    const maxTop: number = this.screenHeightVp - this.BALL_SIZE - this.BALL_BOTTOM_SAFE;
    if (targetTop < minTop) {
      targetTop = minTop;
    }
    if (maxTop >= minTop && targetTop > maxTop) {
      targetTop = maxTop;
    }
    const targetOffsetY: number = targetTop - anchorTop;

    animateTo({ curve: BALL_SPRING }, () => {
      this.ballOffsetX = targetOffsetX;
      this.ballOffsetY = targetOffsetY;
    });
  }

  /**
   * HUI-019 · T-LT04：包裹「浮球收缩/展开」spring —— spring 进行中置 isSpringAnimating=true
   * 暂停 TalkBotAnimation（F2：避免 spring 变换 × Lottie 每帧重绘叠加掉帧），animateTo onFinish 复位
   * 恢复播放。仅新增播放门控与结束回调，收缩/展开的 BALL_SPRING 曲线与 mutator 几何逻辑保持不变。
   */
  private animateBallSpring(mutator: () => void): void {
    this.isSpringAnimating = true;
    animateTo({
      curve: BALL_SPRING,
      onFinish: () => {
        this.isSpringAnimating = false;
      }
    }, mutator);
  }

  /** 点击浮球：拖拽后不误触展开；纯点击 → 回到原位并展开胶囊 */
  private onBallTap(): void {
    if (this.hasDragged) {
      this.hasDragged = false;
      return;
    }
    this.expandFromBall();
  }

  /** 浮球 → 胶囊：回原位 + 展开（一次 spring 完成） */
  private expandFromBall(): void {
    this.isManuallyExpanded = true;
    // HUI-019 · T-LT04：spring 期间暂停 TalkBot（曲线/几何不变，仅包裹播放门控）
    this.animateBallSpring(() => {
      this.isBallMode = false;
      this.ballOffsetX = 0;
      this.ballOffsetY = 0;
    });
  }

  /** 胶囊 → 浮球：从两侧向中间收缩成球并滑到右缘中部（一次 spring 完成） */
  private collapseToBall(): void {
    this.ballOffsetX = 0;
    this.ballOffsetY = 0;
    // HUI-019 · T-LT04：spring 期间暂停 TalkBot（曲线/几何不变，仅包裹播放门控）
    this.animateBallSpring(() => {
      this.isBallMode = true;
    });
  }

  /** selectedTabIndex 变化：进入 AI 页收缩为球；离开 AI 页恢复胶囊 */
  private aiCollapseTimerId: number = -1;

  private onSelectedTabIndexChange(): void {
    if (this.isAiSelected()) {
      // fix: HUI-043 —— 每次进入 AI 页时清除手动展开标志，确保再次进入时收缩定时器不会被跳过。
      //   根因：expandFromBall() 设置 isManuallyExpanded=true；若离开 AI 时 else 分支因时序未执行，
      //   再次进入 AI 时 !isManuallyExpanded 为 false，收缩定时器被跳过 → 胶囊不再收缩。
      //   修复：在进入分支入口强制复位该标志（兜底；else 分支的清除保留为双层防御）。
      this.isManuallyExpanded = false;
      if (!this.isBallMode) {
        // 先让 Tab 正常切换完成，短暂延迟后再收缩，避免收缩动画与切换同帧
        if (this.aiCollapseTimerId !== -1) { clearTimeout(this.aiCollapseTimerId); }
        this.aiCollapseTimerId = setTimeout(() => {
          this.aiCollapseTimerId = -1;
          // 定时器兜底复检（HUI-001）：500ms 后可能已离开 AI 页或已手动展开，
          // 避免陈旧定时器把非 AI 页误收缩为浮球
          if (this.isAiSelected() && !this.isManuallyExpanded && !this.isBallMode) {
            this.collapseToBall();
          }
        }, 500);
      }
    } else {
      // 离开 AI 页：必须清除待触发的收缩定时器（HUI-001），否则陈旧定时器会在非 AI 页误收缩为浮球
      if (this.aiCollapseTimerId !== -1) {
        clearTimeout(this.aiCollapseTimerId);
        this.aiCollapseTimerId = -1;
      }
      this.isManuallyExpanded = false;
      if (this.isBallMode) {
        // HUI-019 · T-LT04：离开 AI 页展开 spring 期间暂停 TalkBot（曲线/几何不变，仅包裹播放门控）
        this.animateBallSpring(() => {
          this.isBallMode = false;
          this.ballOffsetX = 0;
          this.ballOffsetY = 0;
        });
      }
    }
  }

  /** 当前选中 Tab 是否为 AI 伙伴页 */
  private isAiSelected(): boolean {
    return this.selectedTabIndex >= 0
      && this.selectedTabIndex < this.tabs.length
      && this.tabs[this.selectedTabIndex].key === 'ai';
  }

  // ════════════════════════════════════════════════════════════
  // 主题色兜底（普通方法，@StorageLink 判空回退，PROJECT_SPEC §9.4）
  // 注（HUI-001 · 黑白 v4）：原 cPrimary/cPrimaryLight（青色 #00C2B8/#4FD8CE 兜底）已随手机+平板
  //   选中态青球移除而无引用，一并删除 → 全组件不再残留任何青色选中填充。
  // ════════════════════════════════════════════════════════════
  private cCardBg(): string {
    return this.tokens ? this.tokens.bgCard : 'rgba(255,255,255,0.85)';
  }

  private cBorder(): string {
    return this.tokens ? this.tokens.border : '#E0E6ED';
  }

  private cShadow(): string {
    return this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.08)';
  }

  private cTextTertiary(): string {
    return this.tokens ? this.tokens.textTertiary : '#999999';
  }

  /**
   * 当前激活 Tab 的索引（普通方法，非 build 内 getter；未命中回退 0）
   * PROJECT_SPEC §9.1：避免 getter-in-build，青球位移由此普通方法驱动。
   */
  private getActiveIndex(): number {
    const idx: number = this.tabs.findIndex((t: TabItemConfig) => t.key === this.activeKey);
    return idx >= 0 ? idx : 0;
  }

  /**
   * 判断 Tab 是否为激活状态
   */
  private isActive(key: string): boolean {
    return this.activeKey === key;
  }

  /**
   * 骑栏白圆气泡是否可见（普通方法，非 build 内 getter，PROJECT_SPEC §9.1）。
   * · 平板 MiniBar：无浮球态，选中项（含 AI）恒显示骑栏白圆（忠实替换原青球，每个选中项都有指示）。
   * · 手机横栏：展开胶囊态下全部 5 个标签(含 AI)选中均显示骑栏白圆（与平板一致）；
   *   仅浮球/收缩态(isBallMode)隐藏（收缩态无胶囊栏、变浮球，白圆随之隐藏；收缩/手势逻辑不变）。
   *   注：AI 图标为 TalkBot(Lottie)，位于 Tab 行(层2)、白圆(层1)之上，故白圆出现时 TalkBot 自然落在圆内。
   * 数组越界防护：tabs 为空直接 false。
   */
  private isBubbleVisible(): boolean {
    if (this.tabs.length === 0) {
      return false;
    }
    if (this.layoutDirection === 'tablet') {
      return true;
    }
    return !this.isBallMode;
  }

  /**
   * 骑栏白圆气泡的 translate X（vp，普通方法非 build 内 getter）。
   * 手机横栏：随 index 横向滑移（步距 56）+ 居中偏移；平板竖栏：仅水平居中于栏厚（居中偏移）。
   */
  private bubbleTranslateX(): number {
    if (this.layoutDirection === 'tablet') {
      return BUBBLE_CENTER_OFFSET;
    }
    return this.getActiveIndex() * MOBILE_ITEM_STRIDE + BUBBLE_CENTER_OFFSET;
  }

  /**
   * 骑栏白圆气泡的 translate Y（vp，普通方法非 build 内 getter）。
   * 平板竖栏：随 index 竖向滑移（步距 60）+ 居中偏移；手机横栏：仅垂直居中于栏厚（居中偏移）。
   */
  private bubbleTranslateY(): number {
    if (this.layoutDirection === 'tablet') {
      return this.getActiveIndex() * TABLET_ITEM_STRIDE + BUBBLE_CENTER_OFFSET;
    }
    return BUBBLE_CENTER_OFFSET;
  }

  /**
   * Tab key → 自定义 PNG 图标资源映射（替换原 SymbolGlyph）
   */
  private tabKeyToImage(key: string): Resource {
    switch (key) {
      case 'home':
        return $r('app.media.icon_diary');
      case 'diary':
        return $r('app.media.icon_diary');
      case 'todo':
        return $r('app.media.icon_timeline');
      case 'profile':
        return $r('app.media.icon_profile');
      default:
        return $r('app.media.icon_diary');
    }
  }

  /**
   * HUI-001 · 手绘换回系统图标：Tab key → SymbolGlyph 资源本地映射表（原 tabKeyToSketchType 同位替换，
   * 不改 TabItemConfig；IconMapper NAV_* 历史常量复用，图标名均经本地全量图标库 grep 验证，见 IconMapper 注释）。
   * 映射：diary→NAV_DIARY(book_open_fill) · timeline→NAV_TIMELINE(list_bullet) ·
   *      explore→NAV_EXPLORE(magnifyingglass) · profile→NAV_PROFILE(person)；未知 key 回退 NAV_DIARY。
   * 注（HUI-019 · T-LT04）：'ai' 三处渲染路径（胶囊层2 / 浮球层3 / 平板 MiniBar）均走
   *      LottieAnimation(TalkBot) 渲染，不走本映射；case 'ai'→AI_COMPANION(face_smiling) 仅作防御性兜底保留。
   */
  private tabKeyToSymbol(key: string): Resource {
    switch (key) {
      case 'home':
        return IconMapper.NAV_DIARY;
      case 'diary':
        return IconMapper.NAV_DIARY;
      case 'ai':
        return IconMapper.AI_COMPANION;
      case 'todo':
        return IconMapper.NAV_TIMELINE;
      case 'profile':
        return IconMapper.NAV_PROFILE;
      default:
        return IconMapper.NAV_DIARY;
    }
  }

  /**
   * 处理 Tab 点击
   */
  private handleTabClick(key: string): void {
    if (this.activeKey === key) {
      // fix: HUI-043 —— AI Tab 再次点击收缩：已在 AI 页且胶囊展开时，再次点击 AI tab 直接收缩为浮球
      //   无需经由 onTabChange 路由，避免因 activeKey===key 早返导致“点了没反应”。
      if (key === 'ai' && !this.isBallMode) {
        this.isManuallyExpanded = false;
        this.collapseToBall();
      }
      return;
    }
    if (this.onTabChange) {
      this.onTabChange(key);
    }
  }
}
