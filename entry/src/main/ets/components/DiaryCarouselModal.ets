// <!-- agentID: HUI-001 -->
// agentID: HUI-041（T-D05：页头返回箭头统一 — 裸 arrow_left 加粗 ICON.navBack；翻页箭头不属返回，保留）
// 组件：日记本 · 翻书式日记卡片（居中浮卡，无黑遮罩）
// HUI-001 本次追加：长按卡片删除交互——长按=卡片小幅 z 轴抖动 + 右上角浮现黑白灰中性叉号(44vp)；
//   点叉号→FrostedDialog「是否确认删除」（中性按钮）→ 确认调 DEV 契约 DiaryViewModel.deleteDiary(id)
//   → Swiper 数据源(@State displayList)删项平滑过渡 + onDeleted 通知父级；再点卡/再长按/翻页均退出删除态。
//   已 grep 本地 API24 .d.ts 验证：gesture.d.ts:2234 LongPressGesture(options?)；common.d.ts:3841 AnimateParam
//   (iterations:4014/playMode:4053)；enums.d.ts PlayMode.Alternate；common.d.ts:7419/7443/7477 TransitionEffect
//   rotate/scale/opacity + :7571 animation + :7593 combine。图标 sys.symbol.xmark（本地图标库 L293，IconMapper.CLOSE）。
// 关联设计稿：workSpace/UX-001_diary_card_mockup.html + workSpace/UX-001_diary_card_design.md（用户已审查通过）
// 关联需求：主 Agent 锁定 6 点（无黑遮罩 / 居中浮卡 / 66:34 版面 / 翻书翻页 / 点卡进详情 / 最近30最新在前）
//   用户真机反馈修正：① 整屏铺满→居中浮卡（宽328vp，浮于主页之上，无大块黑遮罩）；② 底色米白#F7F3EA太黄→#FAFAFA，深色#26231D→#1C1C1E
// 关联规范：PROJECT_SPEC §8 ArkTS 严格模式 / §9 崩溃防范 / §10 图标本地库
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式（Stage 模型）
// 系统组件：Column / Row / Stack / Swiper / SwiperController / Image / SymbolGlyph / Text / Button / Divider / Blank
// 翻书动画：Swiper.customContentTransition + rotate({ y, angle, centerX:'0%', perspective:1600 })（硬翻页/书脊转轴）。
//   已 grep 本地 API24 .d.ts 验证签名：
//   · swiper.d.ts:2432 customContentTransition(transition: SwiperContentAnimatedTransition)
//   · swiper.d.ts:2515/2537 SwiperContentAnimatedTransition{ timeout?; transition: Callback<SwiperContentTransitionProxy> }
//   · swiper.d.ts:2548/2578 SwiperContentTransitionProxy{ selectedIndex; index; position; mainAxisLength; finishTransition() }
//   · common.d.ts:6553 RotateOptions{ x?; y?; z?; centerX?; centerY?; perspective?; angle }（perspective 自 API10，本机 API24 支持）
//   转场逐帧写入并列 @State 数组（flipAngle/flipOpacity），各卡直接读下标；层级 zIndex 由 currentIndex+转角推导 —— 官方 Swiper 自定义动画同款范式。
// 封面取图：调 DEV 契约 resolveDiaryCover(diary: Diary, index): string | Resource（@ohos/shared），返回值直接喂 Image()。本组件不写取图逻辑。
// 数据：diaries 由父组件（HomePage）传入 Diary[]（最近约30、最新在前）。标题由 content 首行派生（Diary 无 title 字段，纯展示派生）。
// 崩溃防范（PROJECT_SPEC §9）：
//   · §9.1 无 getter-in-build：日期/标题/颜色均为普通方法，build 内显式调用；
//   · §9.2/§9.3 无字段初值内联 $r()：图标走 IconMapper 静态常量，封面为 build 内运行时调用 resolveDiaryCover；
//   · diaries 用「无装饰成员」接收（同 onClose/onOpenDetail 约定）而非 @Prop —— 规避 @Prop 深拷贝丢失 Diary.getImageList() 方法致崩。
// 配色：极浅白 #FAFAFA / 深暖炭 #1C1C1E（用户确认替代原小麦白 #F7F3EA/#26231D），随 theme_is_dark 翻转。
// 无障碍：卡片/返回/翻页均含 accessibilityText；翻页为用户手动（无自动轮播），不引入常驻/环境动效。

import { Diary, resolveDiaryCover, IconMapper, EmptyStateView, RADIUS, FONT, ICON, SKETCH_BODY, FrostedDialog } from '@ohos/shared';
// HUI-001：长按删除——调 DEV 契约 DiaryViewModel.deleteDiary(id): Promise<boolean>（本组件只做 UI 与调用，不写业务）
import { DiaryViewModel } from 'features/diary';

// ── 卡底色（用户确认：浅 #FAFAFA 极浅白 / 深 #1C1C1E 暖炭）────────────
const CARD_LIGHT: string = '#FAFAFA';
const CARD_DARK: string = '#1C1C1E';
const FADE_TRANSPARENT_LIGHT: string = 'rgba(250,250,250,0)';
const FADE_TRANSPARENT_DARK: string = 'rgba(28,28,30,0)';
const INK_LIGHT: string = '#1A1A1A';          // 主文字（极浅白底上近黑）
const INK_DARK: string = '#F0F0F0';           // 主文字（深底上浅）
const INK2_LIGHT: string = '#5A5A5A';         // 次文字
const INK2_DARK: string = '#A0A0A0';
const INK3_LIGHT: string = '#999999';         // 三级/eyebrow
const INK3_DARK: string = '#7A7A7A';
const ACCENT_TAUPE: string = '#C6BBAE';       // 单一暖点缀：日期分隔线（深浅同值）
const SLATE_LIGHT: string = '#738A9C';        // 详情链接
const SLATE_DARK: string = '#93A6B5';
const SPINE_LIGHT: string = '#E0DED8';        // 书脊装订
const SPINE_DARK: string = '#2A2A2E';
const SHADOW_LIGHT: string = 'rgba(0,0,0,0.12)';
const SHADOW_DARK: string = 'rgba(0,0,0,0.45)';

// ── 翻书参数 ─────────────────────────────────────────────────────────
const FLIP_DURATION: number = 700;   // 翻页时长(ms)，约 0.7s
const FLIP_MAX_ANGLE: number = 165;  // 硬翻页最大转角(deg)
const FLIP_PERSPECTIVE: number = 1600;
const FADE_HEIGHT: number = 78;      // 封面底部渐隐带高度(vp，档 48/78/118，取中)
const RECENT_LIMIT: number = 30;     // 展示最近约 30 篇
const WEEKDAY_LABELS: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

// ── HUI-001 长按删除参数 ──────────────────────────────────────────────
const SHAKE_ANGLE: number = 1.6;     // 抖动摆幅(deg)，小幅往复
const SHAKE_PERIOD: number = 110;    // 抖动半周期(ms)
// 叉号钮黑白灰中性（浅色深灰钮白叉 / 深色浅灰钮黑叉，对比度≥4.5:1，禁大红）
const DEL_BTN_BG_LIGHT: string = '#3C3C3C';
const DEL_BTN_BG_DARK: string = '#D8D8D8';
const DEL_BTN_INK_LIGHT: string = '#FFFFFF';
const DEL_BTN_INK_DARK: string = '#1C1C1E';

@Component
export struct DiaryCarouselModal {
  // 无装饰成员：由父组件构造时传入（同 onClose/onOpenDetail），保持 Diary 类实例引用（含 getImageList 方法）不被深拷贝丢失。
  diaries: Diary[] = [];
  /** 返回主页（点返回按钮 或 点卡外背景） */
  onClose?: () => void;
  /** 打开某篇日记详情（参数为日期串，父组件负责 router 跳转） */
  onOpenDetail?: (date: string) => void;
  /** HUI-001：某篇日记删除成功后通知父组件（父级同步剔除其数据源，防重开模态回显已删卡） */
  onDeleted?: (id: number) => void;

  /** 全局深浅色（驱动卡色/文字色翻转） */
  @StorageLink('theme_is_dark') isDark: boolean = false;

  /** 当前正面卡索引（页码 & 翻页控件状态） */
  @State private currentIndex: number = 0;
  /** 翻书转场：各卡转角(deg)，转场回调逐帧写入，卡片 rotate 读下标 */
  @State private flipAngle: number[] = [];
  /** 翻书转场：各卡透明度（过半后淡出，避免露出镜像背面） */
  @State private flipOpacity: number[] = [];
  /** 浮卡入场缩放（aboutToAppear 弹入 0.92 → 1） */
  @State private cardScale: number = 0.92;

  // ── HUI-001 长按删除态 ──────────────────────────────────────
  /** 处于删除态（抖动+叉号）的卡片下标；-1=无 */
  @State private deleteModeIndex: number = -1;
  /** 抖动摆角(deg)，animateTo 无限交替驱动 */
  @State private shakeAngle: number = 0;

  /** 展示列表（最近约 30、最新在前）；HUI-001：删除需删项刷新 Swiper 数据源，升级为 @State */
  @State private displayList: Diary[] = [];
  /** Swiper 控制器（翻页按钮驱动 showNext/showPrevious） */
  private swiperController: SwiperController = new SwiperController();

  // ── HUI-001 删除接线（UI 只调契约，不写业务）────────────────
  /** DEV 契约 VM：deleteDiary(id): Promise<boolean> */
  private diaryVm: DiaryViewModel = new DiaryViewModel();
  /** 待确认删除的日记 id / 卡堆下标（叉号点击暂存，弹窗确认时读取） */
  private pendingDeleteId: number = -1;
  private pendingDeleteIndex: number = -1;
  /** 删除确认弹窗（FrostedDialog 中性黑白灰按钮，无大红） */
  private deleteConfirmController: CustomDialogController = new CustomDialogController({
    builder: FrostedDialog({
      title: '是否确认删除',
      message: '删除后该篇日记将从卡堆移除',
      confirmText: '删除',
      cancelText: '取消',
      neutralButtons: true,
      onConfirm: () => {
        this.confirmDeleteAsync();
      },
      onCancel: () => {
        this.exitDeleteMode();
      }
    }),
    autoCancel: true,
    customStyle: true,
    alignment: DialogAlignment.Center,
    // HUI-001 修停抖 bug（同待办）：点遮罩/返回键关闭不走按钮 onCancel，controller 级 cancel 兜底
    //   （API24 custom_dialog_controller.d.ts:96），保证所有关闭路径均退出抖动删除态
    cancel: () => {
      this.pendingDeleteId = -1;
      this.pendingDeleteIndex = -1;
      this.exitDeleteMode();
    }
  });

  aboutToAppear(): void {
    // 取最近约 30（沿用父组件已按 date DESC 传入的顺序，仅截断展示层）
    this.displayList = this.diaries.slice(0, RECENT_LIMIT);
    // 并列转场数组定型为展示条数（下标恒有效，防越界读 undefined）
    const angles: number[] = [];
    const ops: number[] = [];
    for (let i = 0; i < this.displayList.length; i++) {
      angles.push(0);
      ops.push(1);
    }
    this.flipAngle = angles;
    this.flipOpacity = ops;
    // 浮卡入场轻弹（缩放 0.92 → 1）
    animateTo({ duration: 260, curve: Curve.EaseOut }, () => {
      this.cardScale = 1;
    });
  }

  build() {
    // 全屏透明层 + 居中卡片（无黑遮罩；点卡外透明背景关闭）
    Stack({ alignContent: Alignment.Center }) {
      // 背景触碰区（透明全屏，点击关闭；卡区在上层，不会穿透触发）
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.close();
        })

      // ── 居中浮卡容器 ──
      Column() {
        this.buildHeader()
        this.buildBody()
      }
      .onClick(() => {
        // 吸收卡片区域内非交互区的点击，防止穿透到背景透明层触发关闭
      })
      .width(288)
      .borderRadius(32)
      .clip(true)
      .backgroundColor(this.cardBg())
      .shadow({
        radius: 48,
        color: this.isDark ? SHADOW_DARK : SHADOW_LIGHT,
        offsetX: 0,
        offsetY: 18
      })
      // 避开底部导航栏(~64vp)：底 margin 64vp 将卡片中心上移约32vp，居中于可见区域
      .margin({ bottom: 64 })
      // 入场弹缩（aboutToAppear 驱动 0.92 → 1）
      .scale({ x: this.cardScale, y: this.cardScale })
    }
    .width('100%')
    .height('100%')
  }

  // ═══════════════════════════════════════════════════════════
  // 页头：返回 ｜ 日记本 ｜ 计数
  // 图标来源：IconMapper.ARROW_BACK = arrow_left（本地图标库 L377 已验证，HUI-041 统一）
  // ═══════════════════════════════════════════════════════════
  @Builder
  buildHeader() {
    Row() {
      Button() {
        SymbolGlyph(IconMapper.ARROW_BACK)
          .fontSize(ICON.navBack)
          .fontWeight(FontWeight.Bold) // HUI-041：系统裸箭头加粗
          .fontColor([this.ink()])
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.close();
      })
      .accessibilityText('返回主页')

      Text('日记本')
        .fontSize(22)
        .fontWeight(800)
        .letterSpacing(1)
        .fontColor(this.ink())
        .margin({ left: 4 })
        .attributeModifier(SKETCH_BODY)

      Blank()

      if (this.displayList.length > 0) {
        Text((this.currentIndex + 1).toString() + ' / ' + this.displayList.length.toString())
          .fontSize(12)
          .fontWeight(600)
          .letterSpacing(1)
          .fontColor(this.ink3())
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 18, right: 18, top: 12, bottom: 8 })
  }

  // ═══════════════════════════════════════════════════════════
  // 正文：有数据→翻书卡堆 + 翻页控件；无数据→空态
  // ═══════════════════════════════════════════════════════════
  @Builder
  buildBody() {
    if (this.displayList.length > 0) {
      Column() {
        // 卡堆（书脊 + Swiper 翻书；固定高度保持 66/34 比例）
        Stack({ alignContent: Alignment.Start }) {
          this.buildSwiper()
          // 书脊：左侧装订边（装饰，触摸透传）
          Column()
            .width(12)
            .height(378)
            .borderRadius({ topLeft: 6, bottomLeft: 6, topRight: 3, bottomRight: 3 })
            .linearGradient({
              angle: 90,
              colors: [
                [this.spine(), 0.0],
                [this.isDark ? FADE_TRANSPARENT_DARK : FADE_TRANSPARENT_LIGHT, 1.0]
              ]
            })
            .margin({ top: 31 })
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .height(440)

        this.buildFlipControls()
      }
      .width('100%')
      .padding({ left: 8, right: 8, bottom: 14 })
    } else {
      Column() {
        EmptyStateView({
          icon: IconMapper.NAV_DIARY,
          title: '还没有日记',
          description: '去写下第一篇，记录此刻的心情吧'
        })
      }
      .width('100%')
      .padding({ top: 40, bottom: 40 })
      .justifyContent(FlexAlign.Center)
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Swiper 翻书：硬翻页/书脊转轴（customContentTransition + rotate perspective）
  // ═══════════════════════════════════════════════════════════
  @Builder
  buildSwiper() {
    Swiper(this.swiperController) {
      ForEach(this.displayList, (item: Diary, index: number) => {
        this.buildCard(item, index)
      }, (item: Diary, index: number) => item.id.toString() + '_' + index.toString())
    }
    .width('100%')
    .height('100%')
    .loop(false)
    .duration(FLIP_DURATION)
    .curve(Curve.FastOutSlowIn)
    .indicator(false)
    .index(this.currentIndex)
    .onChange((idx: number) => {
      this.currentIndex = idx;
      // HUI-001：翻页落定后退出删除态（抖动/叉号不跨卡遗留）
      if (this.deleteModeIndex !== -1) {
        this.exitDeleteMode();
      }
    })
    .customContentTransition({
      timeout: FLIP_DURATION,
      transition: (proxy: SwiperContentTransitionProxy) => {
        this.applyFlip(proxy);
      }
    })
  }

  // ── 逐帧转场：绕左脊硬翻页 ────────────────────────────────
  // position ≈ [-1,1]：本卡在主轴上相对起点的移动比。
  //   [-1,0]：处于「翻动/左脊」槽位（前进时的离场页 / 后退时的开合页）——绕左脊转 angle=pos*165；过半后淡出隐背面。
  //   (0,1] ：下一张，保持平展、压在下层，待翻动页转走/淡出后自然露出。
  private applyFlip(proxy: SwiperContentTransitionProxy): void {
    const i: number = proxy.index;
    if (i < 0 || i >= this.flipAngle.length) {
      return;
    }
    // HUI-001：翻书一旦启动即退出删除态（rotate 槽位让位给翻页动画）
    if (this.deleteModeIndex !== -1) {
      this.exitDeleteMode();
    }
    const pos: number = proxy.position;
    if (pos <= -1 || pos >= 1) {
      this.flipAngle[i] = 0;
      this.flipOpacity[i] = 1;
    } else if (pos <= 0) {
      this.flipAngle[i] = pos * FLIP_MAX_ANGLE;
      if (pos > -0.5) {
        this.flipOpacity[i] = 1;
      } else {
        const t: number = (pos + 1) / 0.5;
        this.flipOpacity[i] = t < 0 ? 0 : t;
      }
    } else {
      this.flipAngle[i] = 0;
      this.flipOpacity[i] = 1;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 单张日记卡：上 66% 封面（cover 铺满 + 底部渐隐）+ 下 34%（日期 + 标题）
  // HUI-001（五轮·停抖硬修，同待办四轮）：抖动 rotate 不再与翻书共用常驻根节点（cardRotate 二选一已废）——
  //   真机证实 iterations:-1 无限动画挂在常驻节点上任何改状态/表达式开关都杀不死；抖动改挂 if/else
  //   删除态独立 Column 包装节点，退出删除态该节点整个销毁（节点亡=动画必死）；根 Stack 恒挂翻书
  //   rotate（flipAngle 有限动画，无此问题），翻书/封面/短按进详情不动。主体抽 @Builder 两分支复用。
  // ═══════════════════════════════════════════════════════════
  @Builder
  buildCard(item: Diary, index: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.deleteModeIndex === index) {
        // 删除态分支：独立抖动包装节点（退出即销毁，杀死无限抖动动画）
        Column() {
          this.buildCardBody(item, index)
        }
        .width('100%')
        .height('100%')
        .rotate({
          x: 0,
          y: 0,
          z: 1,
          angle: this.shakeAngle,
          centerX: '50%',
          centerY: '50%'
        })
      } else {
        this.buildCardBody(item, index)
      }

      // ── HUI-001：删除态右上角叉号（黑白灰中性小圆钮，44vp 热区；浮现/退场 200ms 缩放渐隐）──
      if (this.deleteModeIndex === index) {
        Button() {
          SymbolGlyph(IconMapper.CLOSE)
            .fontSize(18)
            .fontColor([this.isDark ? DEL_BTN_INK_DARK : DEL_BTN_INK_LIGHT])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(this.isDark ? DEL_BTN_BG_DARK : DEL_BTN_BG_LIGHT)
        .shadow({ radius: 12, color: this.isDark ? SHADOW_DARK : SHADOW_LIGHT, offsetX: 0, offsetY: 4 })
        .margin({ top: 10, right: 10 })
        .transition(
          TransitionEffect.opacity(0)
            .animation({ duration: 200, curve: Curve.EaseOut })
            .combine(TransitionEffect.scale({ x: 0.6, y: 0.6 }))
        )
        .onClick(() => {
          this.requestDelete(item, index);
        })
        .accessibilityText('删除该篇日记：' + this.deriveTitle(item.content))
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(RADIUS.card)
    .clip(true)
    .backgroundColor(this.cardBg())
    // HUI-001（五轮）：根节点恒挂翻书 rotate（有限动画）——抖动已移至删除态 if/else 独立包装节点
    .rotate({
      x: 0,
      y: 1,
      z: 0,
      angle: this.flipAngle[index],
      centerX: '0%',
      centerY: '50%',
      perspective: FLIP_PERSPECTIVE
    })
    .opacity(this.flipOpacity[index])
    // 层级：当前卡置顶(100)、其后未读卡依次下沉；正在翻动(转角≠0)的卡 +200 临时置顶
    .zIndex((index >= this.currentIndex ? (100 - (index - this.currentIndex)) : (index - this.currentIndex)) + (this.flipAngle[index] !== 0 ? 200 : 0))
    .onClick(() => {
      // HUI-001：删除态下点击卡片其他区域=退出删除态（不进详情）；平时短按进详情
      if (this.deleteModeIndex === index) {
        this.exitDeleteMode();
        return;
      }
      this.openDetail(item.date);
    })
    // HUI-001：长按进入/退出删除态（LongPressGesture 与 onClick、Swiper 平移翻书手势共存互不干扰）
    //   API24 gesture.d.ts:2234 (options?: LongPressGestureHandlerOptions)
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.toggleDeleteMode(index);
        })
    )
    .accessibilityText(this.deriveTitle(item.content) + '，' + this.ymOf(item.date) + this.dayOf(item.date) + '日，' + this.weekdayOf(item.date) + '，点击查看该篇日记详情，长按进入删除模式')
  }

  // ═══ 卡片主体 @Builder（删除态/常态两分支复用；抖动 rotate 由删除态包装层承担）═══
  @Builder
  buildCardBody(item: Diary, index: number) {
    Column() {
      // ── 封面 66%：Image cover + 底部线性渐隐过渡到卡底色 ──
      Stack({ alignContent: Alignment.Bottom }) {
        Image(this.coverOf(item, index))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .backgroundColor(this.cardBg())

        Column()
          .width('100%')
          .height(FADE_HEIGHT)
          .linearGradient({
            angle: 180,
            colors: [
              [this.isDark ? FADE_TRANSPARENT_DARK : FADE_TRANSPARENT_LIGHT, 0.0],
              [this.cardBg(), 0.92]
            ]
          })
      }
      .width('100%')
      .height('66%')

      // ── 文字区 34%：日期（镜像主页大卡片）在上，标题在下 ──
      Column() {
        // 日期行：大日号 + 竖排年月 eyebrow + 24 分隔线 + 星期
        Row() {
          Text(this.dayOf(item.date))
            .fontSize(46)
            .fontWeight(900)
            .fontFamily(FONT.monoExtraBold)
            .letterSpacing(-2)
            .lineHeight(46)
            .fontColor(this.ink())

          Column() {
            Text(this.ymOf(item.date))
              .fontSize(11)
              .fontWeight(700)
              .letterSpacing(2)
              .fontColor(this.ink3())
            Divider()
              .width(24)
              .strokeWidth(2)
              .color(ACCENT_TAUPE)
              .margin({ top: 6 })
            Text(this.weekdayOf(item.date))
              .fontSize(11)
              .fontWeight(600)
              .letterSpacing(1)
              .fontColor(this.ink3())
              .margin({ top: 5 })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 8, top: 6 })

          Blank()
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        // 标题（content 首行派生）+ 详情提示
        Column() {
          Text(this.deriveTitle(item.content))
            .fontSize(21)
            .fontWeight(800)
            .lineHeight(28)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.ink())
            .attributeModifier(SKETCH_BODY)

          Row() {
            Text('点击查看详情')
              .fontSize(12)
              .fontWeight(600)
              .letterSpacing(0.5)
              .fontColor(this.slate())
              .attributeModifier(SKETCH_BODY)
            SymbolGlyph(IconMapper.FORWARD)
              .fontSize(13)
              .fontColor([this.slate()])
              .margin({ left: 2 })
          }
          .alignItems(VerticalAlign.Center)
          .margin({ top: 9 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('34%')
      .padding({ left: 22, right: 22, top: 14, bottom: 18 })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  // ═══════════════════════════════════════════════════════════
  // 翻页控件：上一篇（较新）｜ 页码 ｜ 下一篇（较旧）
  // ═══════════════════════════════════════════════════════════
  @Builder
  buildFlipControls() {
    Row({ space: 22 }) {
      Button() {
        SymbolGlyph(IconMapper.BACK)
          .fontSize(20)
          .fontColor([this.ink()])
      }
      .width(46)
      .height(46)
      .borderRadius(23)
      .backgroundColor(this.cardBg())
      .opacity(this.currentIndex > 0 ? 1 : 0.3)
      .shadow({ radius: 16, color: this.isDark ? SHADOW_DARK : SHADOW_LIGHT, offsetX: 0, offsetY: 6 })
      .onClick(() => {
        this.goPrev();
      })
      .accessibilityText('上一篇，较新')

      Text(this.pageLabel())
        .fontSize(12)
        .fontWeight(600)
        .letterSpacing(1)
        .fontColor(this.ink2())
        .constraintSize({ minWidth: 56 })
        .textAlign(TextAlign.Center)

      Button() {
        SymbolGlyph(IconMapper.FORWARD)
          .fontSize(20)
          .fontColor([this.ink()])
      }
      .width(46)
      .height(46)
      .borderRadius(23)
      .backgroundColor(this.cardBg())
      .opacity(this.currentIndex < this.displayList.length - 1 ? 1 : 0.3)
      .shadow({ radius: 16, color: this.isDark ? SHADOW_DARK : SHADOW_LIGHT, offsetX: 0, offsetY: 6 })
      .onClick(() => {
        this.goNext();
      })
      .accessibilityText('下一篇，较旧')
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .margin({ top: 12 })
  }

  // ── 日期/标题 派生（普通方法，非 build getter · §9.1）──────────
  private dayOf(dateStr: string): string {
    return dateStr.length >= 10 ? dateStr.slice(8, 10) : dateStr;
  }

  private ymOf(dateStr: string): string {
    if (dateStr.length < 10) {
      return dateStr;
    }
    return dateStr.slice(0, 4) + '年' + dateStr.slice(5, 7) + '月';
  }

  private weekdayOf(dateStr: string): string {
    const d: Date = new Date(dateStr);
    const wd: number = d.getDay();
    if (Number.isNaN(wd) || wd < 0 || wd > 6) {
      return '';
    }
    return WEEKDAY_LABELS[wd];
  }

  private deriveTitle(content: string): string {
    const trimmed: string = content.trim();
    if (trimmed.length === 0) {
      return '（无标题）';
    }
    const nl: number = trimmed.indexOf('\n');
    return nl >= 0 ? trimmed.slice(0, nl) : trimmed;
  }

  private pageLabel(): string {
    if (this.currentIndex === 0) {
      return '最新';
    }
    if (this.currentIndex === this.displayList.length - 1) {
      return '最早';
    }
    return '第 ' + (this.currentIndex + 1).toString() + ' 篇';
  }

  // ── 封面：调 DEV 契约，直接喂 Image（本组件不写取图逻辑）──────
  private coverOf(item: Diary, index: number): string | Resource {
    return resolveDiaryCover(item, index);
  }

  // ── 局部色（随 theme_is_dark；普通方法非 getter）──────────────
  private cardBg(): string {
    return this.isDark ? CARD_DARK : CARD_LIGHT;
  }

  private ink(): string {
    return this.isDark ? INK_DARK : INK_LIGHT;
  }

  private ink2(): string {
    return this.isDark ? INK2_DARK : INK2_LIGHT;
  }

  private ink3(): string {
    return this.isDark ? INK3_DARK : INK3_LIGHT;
  }

  private slate(): string {
    return this.isDark ? SLATE_DARK : SLATE_LIGHT;
  }

  private spine(): string {
    return this.isDark ? SPINE_DARK : SPINE_LIGHT;
  }

  // ── 交互 ────────────────────────────────────────
  // ── HUI-001 长按删除交互 ─────────────────────────
  // （五轮）cardRotate「rotate 槽位二选一」已废：真机证实无限抖动动画挂常驻节点杀不死；
  //   翻书 rotate 恒挂卡片根节点、抖动 rotate 挂删除态 if/else 独立包装节点（见 buildCard）。

  /** 长按：进入删除态（抖动+叉号）；已在删除态再长按=退出 */
  private toggleDeleteMode(index: number): void {
    if (this.deleteModeIndex === index) {
      this.exitDeleteMode();
      return;
    }
    this.deleteModeIndex = index;
    // 小幅往复抖动：先置负摆角，再无限交替动画到正摆角（API24 AnimateParam iterations:-1 + PlayMode.Alternate）
    this.shakeAngle = -SHAKE_ANGLE;
    animateTo({
      duration: SHAKE_PERIOD,
      curve: Curve.Linear,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, () => {
      this.shakeAngle = SHAKE_ANGLE;
    });
  }

  /** 退出删除态：摆角归零（新动画顶掉无限抖动）+ 叉号经 transition 缩放渐隐 */
  private exitDeleteMode(): void {
    this.deleteModeIndex = -1;
    animateTo({ duration: SHAKE_PERIOD, curve: Curve.Linear }, () => {
      this.shakeAngle = 0;
    });
  }

  /** 点叉号：暂存待删卡，弹「是否确认删除」确认弹窗 */
  private requestDelete(item: Diary, index: number): void {
    this.pendingDeleteId = item.id;
    this.pendingDeleteIndex = index;
    this.deleteConfirmController.open();
  }

  /** 确认删除：调 DEV 契约 deleteDiary，成功后卡堆删项平滑过渡 + 通知父组件 */
  private async confirmDeleteAsync(): Promise<void> {
    const id: number = this.pendingDeleteId;
    const idx: number = this.pendingDeleteIndex;
    this.pendingDeleteId = -1;
    this.pendingDeleteIndex = -1;
    if (id < 0 || idx < 0 || idx >= this.displayList.length) {
      this.exitDeleteMode();
      return;
    }
    const ok: boolean = await this.diaryVm.deleteDiary(id);
    if (!ok) {
      this.exitDeleteMode();
      return;
    }
    this.exitDeleteMode();
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.displayList.splice(idx, 1);
      this.flipAngle.splice(idx, 1);
      this.flipOpacity.splice(idx, 1);
      if (this.currentIndex >= this.displayList.length && this.currentIndex > 0) {
        this.currentIndex = this.displayList.length - 1;
      }
    });
    if (this.onDeleted) {
      this.onDeleted(id);
    }
  }

  private goPrev(): void {
    if (this.currentIndex > 0) {
      this.swiperController.showPrevious();
    }
  }

  private goNext(): void {
    if (this.currentIndex < this.displayList.length - 1) {
      this.swiperController.showNext();
    }
  }

  private close(): void {
    if (this.onClose) {
      this.onClose();
    }
  }

  private openDetail(date: string): void {
    if (this.onOpenDetail) {
      this.onOpenDetail(date);
    }
  }
}
