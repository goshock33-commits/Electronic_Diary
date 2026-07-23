// <!-- agentID: HUI-018 -->
// HUI-018 (T-LT03 · 主页大卡片猫 Lottie 动画轮播)：日期封面大卡片中央 160vp 装饰区，
//   原「128vp 渐变光晕 + 60s 慢转虚线环 + NAV_DIARY 图标」替换为 7 个彩色猫 Lottie 动画轮播池
//   （cat-in-box / cat-sleeping-rolling / cat-playing / loader-cat / cat-playing-animation / cat-pookie / cat-typing）。
//   切换方式：与名言共用同一 7s 节拍（HUI-001 合并：QUOTE_SWITCH_INTERVAL 单一定时源 beatTimerId，tick 同拍推进名言+猫，
//   出屏暂停猫推进/回屏下个 tick 恢复/卸载清理）+ 左右滑动/点击手动切换（手动切猫不重置节拍，下个 tick 继续同步）。
//   产品决策：猫保留原彩色（不 changeColor 单色化）——彩色猫为首页唯一 signature（JUDGE S7 方案B）。
//   硬约束：F1+F4 任一时刻仅 1 个已解析实例（7 只为可切换池，切换走 animPath 变化 → 组件内 stop旧→destroy旧→load新，绝不并存）；
//          S5 出屏停播（LottieAnimation 内建 onVisibleAreaChange 停播 + 本页 Stack onVisibleAreaChange 暂停自动轮播）；
//          要点2 手势隔离（显式 SwipeGesture(Horizontal) 与父 Scroll 竖向轴正交，点击命中区限定 160vp 装饰 Stack 内，不碰 CTA/名言）。
//   单实例内存约束下不做双层 crossfade，改用轻量 opacity 淡出→换 animPath→淡入（复用名言轮播同款过渡）。
//   HUI-018 调整：误加的 cat-loader（Cat 双空格 loader）换为 loader-cat（Loader cat）；新增 cat-playing-animation/cat-pookie/cat-typing；加定时自动轮播。
//   随本次替换退休：原虚线环慢转（ringAngle/ringTimerId/startRingSpin/RING_SPIN_DURATION）与光晕 glowColor()——
//   遵循「单一 hero 动画」（ui-ux-pro-max 行7 Excessive Motion：Single hero animation），去除与猫竞争的常驻旋转动效。
// HUI-001 (微任务 · 猫轮播与名言轮播同节拍)：删除猫独立 CAT_AUTO_INTERVAL 定时器，改由名言 7s tick 单一节拍源
//   （beatTimerId / startBeatTimer）同拍驱动「名言推进 + 猫推进」——名言换句那一刻猫同步淡出换只淡入；
//   自动同拍切换双方淡出淡入统一 QUOTE_FADE_DURATION=800ms（视觉同呼吸），手动切猫仍用 CAT_FADE_DURATION=180ms 快反馈；
//   S5 出屏仅暂停 tick 内猫推进（isCardVisible 门控，名言 tick 照旧），回屏下个 tick 自然恢复；手动切猫不重置节拍。
// <!-- agentID: HUI-072 · 深色模式 CTA 白底白字对比度修复 by HUI-001 (T-BUG-002) -->
// HUI-077 修订：左侧抽屉菜单删除「设置」项；「今日待办」改名为「待办」。
// HUI-001 (T103 · 批次1接线)：打卡环由本地 mock 改接 CheckInViewModel —— aboutToAppear 内 await init(today)
//   拉真实打卡态 + 连续天数填 @State，handleCheckIn 调 vm.checkIn() 真实写库，订阅 CHECKIN_CHANGED 跨页同步。
// HUI-006 (T104 · 名言已接 QuoteViewModel)：QuoteViewModel §8.3① 对象字面量坑已由 DEV 修复（emit 改「空字面量+
//   括号逐键赋值」、AppStorage import 已删、主 Agent 核实编译通过），本页已 import 该 VM 接入真实每日名言。
//   aboutToAppear 内 await quoteVm.init() 拉 DB 当日名言写入 @State currentQuote（getCurrentQuote() 返回 Quote|null 判空），
//   DB 当日名言优先、本地 HOME_QUOTES 轮播作 DB 不可用时兜底；订阅 QUOTE_CHANGED（自定义/跨页名言变更时）重读同步。
// 页面：首页（薄荷青极简 · 巨型日期封面 + 内嵌名言轮播 + 打卡签到卡 + 左侧半宽抽屉菜单）
// 关联设计稿：UX-001_redesign_report §2.2（HomeView P1-05 bento 巨型日期封面）
// 关联计划：HUI-072（复原巨型日期封面 / 名言嵌入大卡片文字区 / 功能入口移入左侧菜单）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 令牌驱动：颜色读 @StorageLink('theme_tokens')；圆角 RADIUS / 间距 SPACING / 排版 TYPO / 字体族 FONT
//
// 本次重构（HUI-072）:
//   1. 保留并复原「巨型日期封面卡」(P1-05 bento)：60fp 青数字日期 + 「YYYY年MM月」eyebrow
//      + 128vp 圆形渐变光晕 + 60s 慢转虚线环 + book_open_fill + 黑色「开始记录时光」CTA。
//   2. 名言嵌入大卡片文字区：原「你好，用心记录每一天」问候位置 → 改为 10 条内置名言定时轮播，
//      setInterval 7s 自动切换，opacity 淡入淡出 800ms 过渡（不再有独立名言卡片）。
//   3. 「打卡签到卡」(CheckInButton + StreakCounter) 置于日期封面卡下方。
//   4. 番茄钟 / 待办 / 明日日程 —— 3 个入口移入左侧抽屉菜单，首页不再直接展示。
//   5. 顶栏：左汉堡(line_3_horizontal) ｜ 中「日记本」药丸(进日历) ｜ 右深色/浅色一键切换(moon_fill↔sun_max_fill)。
//   6. 左侧抽屉菜单：width 50% + translateX 滑入 + 全屏 backdropBlur(8) 遮罩，点击遮罩关闭。
//   7. 删除：五分区 / FloatingBookmark / 顶部写日记图标 / 独立 QuoteCard。
//
// 配色约束（HUI-072）：仅薄荷青(primary #00C2B8 / accent #E6F9F8) + 中性灰白体系，
//   本页禁用 #78909C(红) / #80CBC4(橙) / #90A4AE(紫) 等高饱和色。
//
// 崩溃防范（PROJECT_SPEC §9）：
//   · §9.1 无 getter-in-build：名言经 @State currentQuote 取值（HOME_QUOTES[0] 兜底初值，§9.1 方案B），非 private getter；
//   · §9.2/§9.3 无字段初值内联 $r()：全部图标走 IconMapper 静态常量（含 menuItems）；
//   · §9.4 @StorageLink tokens 读取全判空回退。
// 定时器清理：统一节拍 setInterval（名言+猫同拍 · HUI-001）/ 名言淡出 setTimeout / 猫淡出 setTimeout 均在 aboutToDisappear 清理，
//   防 setState-after-unmount 与内存泄漏。
// 无障碍：accessibilityText 不为空 + 触控热区 >= 44x44vp。

import type { ThemeColorTokens, Quote } from '@ohos/shared';
// HUI-026：引入集中手绘字体助手（全局黑白手绘换肤）——SKETCH_TITLE=猫啃什锦黑(标题/kicker)，SKETCH_BODY=清松手写体2(正文/标签/按钮)；仅补 fontFamily，不动字号/字重/布局。
import { Diary, IconMapper, RADIUS, SPACING, TYPO, FONT, getThemeManager, EventBus, DateUtils, LottieAnimation, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';
import { CheckInButton, StreakCounter, CheckInViewModel } from 'features/checkin';
import { QuoteViewModel } from 'features/quote';
import { DiaryViewModel } from 'features/diary';
import { router, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DiaryCarouselModal } from '../components/DiaryCarouselModal';

const TAG: string = 'HomePage';

/** 左侧抽屉菜单条目 */
interface MenuItemConfig {
  key: string;
  icon: Resource;
  label: string;
  desc: string;
}

/** 每日名言条目 */
interface HomeQuoteItem {
  content: string;
  author: string;
}

/**
 * 中央装饰区猫 Lottie 动画条目（T-LT03）。
 * PROJECT_SPEC §8.2/§8.3：对象字面量须有接口类型声明；path 为 rawfile 相对路径（§9.3：纯字符串，无 $r() 上下文风险）。
 */
interface CatLottieItem {
  /** rawfile 相对路径，如 'animations/cat-in-box.json' */
  path: string;
  /** 无障碍朗读名（当前猫动画描述） */
  label: string;
  /**
   * 单只猫渲染尺寸(vp，方形 animWidth=animHeight)。每只 Lottie 画布内主体占比不同，
   * Contain 同尺寸渲染时留白多的猫显小，故按只独立配尺寸补偿视觉主体大小（HUI-018 调整，可逐只微调）。
   * 上限受 160vp 装饰 Stack 约束（Contain 永不裁切）。
   */
  displaySize: number;
}

/** 跳转日记详情页的路由参数（PROJECT_SPEC §8.2：对象字面量须有接口类型声明） */
interface DiaryDetailNavParams {
  date: string;
}

/** 名言库（本地内置 10 条，定时轮播嵌入巨型日期封面文字区） */
const HOME_QUOTES: HomeQuoteItem[] = [
  { content: '千里之行，始于足下。', author: '老子' },
  { content: '学而不思则罔，思而不学则殆。', author: '孔子' },
  { content: '天行健，君子以自强不息。', author: '《周易》' },
  { content: '业精于勤，荒于嬉；行成于思，毁于随。', author: '韩愈' },
  { content: '宝剑锋从磨砺出，梅花香自苦寒来。', author: '《警世贤文》' },
  { content: '长风破浪会有时，直挂云帆济沧海。', author: '李白' },
  { content: '山重水复疑无路，柳暗花明又一村。', author: '陆游' },
  { content: '不忘初心，方得始终。', author: '《华严经》' },
  { content: '会当凌绝顶，一览众山小。', author: '杜甫' },
  { content: '纸上得来终觉浅，绝知此事要躬行。', author: '陆游' }
];

/** 统一轮播节拍间隔(ms)——单一定时源，tick 同拍驱动「名言切换 + 猫动画切换」（HUI-001 合并，≥4s 给猫 destroy/load 留时间） */
const QUOTE_SWITCH_INTERVAL: number = 7000;
/** 名言淡入淡出时长(ms)；自动同拍切换时猫的淡出淡入也用此值（视觉同呼吸 · HUI-001） */
const QUOTE_FADE_DURATION: number = 800;
/** 猫动画手动切换（点/滑）淡入淡出时长(ms)——微交互区间 150-300ms（ui-ux-pro-max 行8 Duration Timing）；自动同拍切换对齐 QUOTE_FADE_DURATION */
const CAT_FADE_DURATION: number = 180;
/** 抽屉滑入水平位移(vp)，须 >= 抽屉宽度以保证起始完全离屏 */
const DRAWER_SLIDE_X: number = -500;

/**
 * 中央装饰区 7 猫 Lottie 动画池（T-LT03 · HUI-018 调整）。彩色保留（不单色化）——彩色猫为首页唯一 signature（JUDGE S7 方案B，产品拍板）。
 * 顶层 const、纯字符串路径，无 $r() → 不触 §9.3 字段初值 $r() 崩溃坑。
 * 「可切换池子」：同时只渲染 1 个 LottieAnimation（单实例内存 F1+F4），切换走 animPath 变化 → 组件内 destroy 旧 → load 新，绝不并存。
 * 修订：移除误加的 cat-loader（Cat 双空格 loader），换为 loader-cat（Loader cat）；新增 cat-playing-animation / cat-pookie / cat-typing。
 * displaySize（HUI-018 调整）：cat-in-box 主体占比大，保持 120vp（用户认可）；其余 6 只画布留白多、主体显小，
 *   首轮统一放大至 150vp（≈+25%，受 160vp Stack 约束的安全上限，Contain 不裁切）使视觉主体接近第一只，后续可逐只微调。
 */
const HOME_CAT_ANIMS: CatLottieItem[] = [
  { path: 'animations/cat-in-box.json', label: '盒中猫咪', displaySize: 120 },
  { path: 'animations/cat-sleeping-rolling.json', label: '猫咪酣睡翻滚', displaySize: 150 },
  { path: 'animations/cat-playing.json', label: '猫咪戏耍', displaySize: 150 },
  { path: 'animations/loader-cat.json', label: '猫咪加载中', displaySize: 150 },
  { path: 'animations/cat-playing-animation.json', label: '猫咪嬉戏', displaySize: 150 },
  { path: 'animations/cat-pookie.json', label: '猫咪 Pookie', displaySize: 150 },
  { path: 'animations/cat-typing.json', label: '猫咪打字', displaySize: 150 }
];

@Component
export struct HomePage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** 当前深色态（驱动顶栏切换图标 moon/sun） */
  @StorageLink('theme_is_dark') isDark: boolean = false;

  /** 招牌大日期（日） */
  @State private dayStr: string = '';
  /** eyebrow 年月串「YYYY年MM月」 */
  @State private yearMonthStr: string = '';

  /** 左侧抽屉菜单可见性 */
  @State private showMenu: boolean = false;

  /** 当前名言索引 */
  @State private quoteIndex: number = 0;
  /** 名言淡入淡出透明度 */
  @State private quoteOpacity: number = 1;
  /** 当前展示名言（T104：DB 当日名言优先，写入此 @State；HOME_QUOTES[0] 为首帧兜底初值防空白 · §9.1 方案B） */
  @State private currentQuote: HomeQuoteItem = HOME_QUOTES[0];

  /** 当前展示的猫动画索引（0~6，驱动 LottieAnimation animPath 单实例切换 · T-LT03） */
  @State private catIndex: number = 0;
  /** 猫动画切换淡入淡出透明度（单实例约束下以 opacity 过渡代替双层 crossfade） */
  @State private catOpacity: number = 1;

  /** 打卡态（T103：由 CheckInViewModel 拉取真实 DB 状态，见 loadCheckIn） */
  @State private checkedIn: boolean = false;
  /** 连续打卡天数（T103：CheckInViewModel.getStreakDays 真实值；初值 0，异步回填） */
  @State private streak: number = 0;

  /** 日记轮播模态框可见性（顶部「日记本▾」入口，T-FEAT-001） */
  @State private showDiaryModal: boolean = false;
  /** 日记本卡片数据（from DiaryViewModel.getAllDiaries，aboutToAppear 异步填充，DIARY_SAVED 事件即时刷新） */
  @State private diaryItems: Diary[] = [];

  /** 侧边栏拉绳子动画路径 */
  @State private ropeAnimPath: string = 'animations/拉绳子1.json';

  /** 统一轮播节拍 interval id（名言+猫同拍单一定时源 · HUI-001；-1=无） */
  private beatTimerId: number = -1;
  /** 名言淡出 setTimeout id（-1=无） */
  private quoteFadeTimerId: number = -1;
  /** 猫动画切换淡出 setTimeout id（-1=无，防切换叠加 + 卸载泄漏 · T-LT03） */
  private catFadeTimerId: number = -1;
  /** 大卡片装饰区是否在视口内（S5：门控 tick 内猫推进，出屏暂停/回屏下个 tick 恢复，避免出屏 destroy/load 空转） */
  private isCardVisible: boolean = true;

  /** 打卡 ViewModel（T103：默认空构造，aboutToAppear 内 await init 拉数；同实例供 checkIn 写库） */
  private checkInVm: CheckInViewModel = new CheckInViewModel();

  /** 名言 ViewModel（T104：aboutToAppear 内 await init 拉 DB 当日名言；QUOTE_CHANGED 时读 getCurrentQuote 同步） */
  private quoteVm: QuoteViewModel = new QuoteViewModel();
  /** 名言 VM 是否已 init（幂等 + 防 QUOTE_CHANGED 回调重入 init→refresh→emit 造成无限递归） */
  private quoteInited: boolean = false;

  /** 左侧抽屉菜单条目（图标走 IconMapper 静态常量，避免字段初值内联 $r()） */
  private menuItems: MenuItemConfig[] = [
    { key: 'pomodoro', icon: $r('app.media.icon_pomodoro'), label: '番茄钟', desc: '专注计时，提升效率' },
    { key: 'today', icon: $r('app.media.icon_todo'), label: '待办', desc: '查看今天的安排' },
    { key: 'tomorrow', icon: $r('app.media.icon_schedule'), label: '明日日程', desc: '提前规划明天' }
  ];

  private diaryVm: DiaryViewModel = new DiaryViewModel();

  // ── 生命周期 ────────────────────────────────────────

  aboutToAppear(): void {
    const d: Date = new Date();
    this.dayStr = String(d.getDate()).padStart(2, '0');
    this.yearMonthStr = d.getFullYear().toString() + '年' + String(d.getMonth() + 1).padStart(2, '0') + '月';
    this.quoteIndex = Math.floor(Math.random() * HOME_QUOTES.length);
    this.currentQuote = HOME_QUOTES[this.quoteIndex];
    this.diaryItems = [];
    this.loadDiaries();
    this.startBeatTimer(); // HUI-001：单一节拍源，7s tick 同拍推进名言 + 猫（出屏门控猫推进/卸载清理）
    // T103：订阅打卡变更事件（撤销/跨页打卡时同步），并异步拉取真实打卡态（不阻塞首帧）
    EventBus.on(EventBus.EventNames.CHECKIN_CHANGED, (data: Record<string, Object>) => {
      this.loadCheckIn();
    });
    // fix: HUI-FRONTEND-1 · 订阅 DIARY_SAVED —— 写日记页保存后主页轮播即时刷新
    EventBus.on(EventBus.EventNames.DIARY_SAVED, (data: Record<string, Object>) => {
      this.loadDiaries();
    });
    this.loadCheckIn();
    // T104：订阅名言变更事件（自定义名言/跨页刷新时同步），并异步拉取 DB 当日名言（不阻塞首帧，失败保留本地兜底）
    EventBus.on(EventBus.EventNames.QUOTE_CHANGED, (data: Record<string, Object>) => {
      this.loadQuote();
    });
    this.loadQuote();
  }

  aboutToDisappear(): void {
    // 定时器清理（防 setState-after-unmount / 内存泄漏）
    if (this.beatTimerId !== -1) {
      clearInterval(this.beatTimerId);
      this.beatTimerId = -1;
    }
    if (this.quoteFadeTimerId !== -1) {
      clearTimeout(this.quoteFadeTimerId);
      this.quoteFadeTimerId = -1;
    }
    // T-LT03：清理猫动画切换淡出定时器（防 setState-after-unmount / 内存泄漏）
    if (this.catFadeTimerId !== -1) {
      clearTimeout(this.catFadeTimerId);
      this.catFadeTimerId = -1;
    }
    // T103：取消打卡事件订阅（防 setState-after-unmount / 内存泄漏）
    EventBus.off(EventBus.EventNames.CHECKIN_CHANGED);
    // T104：取消名言事件订阅（防 setState-after-unmount / 内存泄漏）
    EventBus.off(EventBus.EventNames.QUOTE_CHANGED);
  }

  // ── UI 构建 ────────────────────────────────────────

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: SPACING.sectionGap }) {
          this.buildTopBar()
          this.buildDateCoverCard()
          this.buildCheckInCard()
        }
        .width('100%')
        .padding({
          left: SPACING.pageH,
          right: SPACING.pageH,
          top: SPACING.pageTop,
          bottom: SPACING.pageBottom
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.tokens ? this.tokens.bg : '#FAF8F5')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // 左侧半宽抽屉菜单 + 全屏遮罩模糊（覆盖层）
      if (this.showMenu) {
        this.buildDrawer()
      }

      // 日记本翻书卡片（顶部「日记本▾」入口）—— 整页米白卡堆，无模态遮罩（组件内自带页面式进出场）
      if (this.showDiaryModal) {
        DiaryCarouselModal({
          diaries: this.diaryItems,
          onClose: () => {
            this.showDiaryModal = false;
          },
          onOpenDetail: (date: string) => {
            this.showDiaryModal = false;
            this.goDiaryDetail(date);
          },
          // HUI-001：卡堆内删除成功后同步剔除主页数据源，防重开模态回显已删卡
          onDeleted: (id: number) => {
            this.diaryItems = this.diaryItems.filter((d: Diary) => d.id !== id);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // ═══════════════════════════════════════════════════════════
  // 顶栏：左汉堡（开抽屉） ｜ 中「日记本」标题 ｜ 右深色/浅色切换
  // ═══════════════════════════════════════════════════════════
  @Builder
  buildTopBar() {
    Row() {
      // 左：汉堡菜单（line_3_horizontal，打开左侧抽屉）
      Button() {
        SymbolGlyph(IconMapper.SORT)
          .fontSize(20)
          .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
      .onClick(() => {
        this.openMenu();
      })
      .accessibilityText('打开菜单')

      // 中：日记本标题药丸（打开日记轮播模态框）
      Row() {
        Text('日记本')
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .attributeModifier(SKETCH_BODY) // HUI-026：卡片标题→清松手写体2
        SymbolGlyph(IconMapper.ARROW_DOWN)
          .fontSize(13)
          .fontColor([this.tokens ? this.tokens.textSecondary : '#5A5A5A'])
          .margin({ left: 4 })
      }
      .height(40)
      .padding({ left: 16, right: 14 })
      .borderRadius(20)
      .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
      .onClick(() => {
        this.openDiaryModal();
      })
      .accessibilityText('日记本，点击查看所有日记')

      // 右：深色 / 浅色一键切换（moon_fill ↔ sun_max_fill）
      Button() {
        SymbolGlyph(this.isDark ? IconMapper.THEME_LIGHT : IconMapper.THEME_DARK)
          .fontSize(20)
          .fontColor([this.tokens ? this.tokens.primary : '#00C2B8'])
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor(this.tokens ? this.tokens.accent : '#E6F9F8')
      .onClick(() => {
        this.toggleDarkMode();
      })
      .accessibilityText(this.isDark ? '切换到浅色模式' : '切换到深色模式')
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
  }

  // ═══════════════════════════════════════════════════════════
  // 巨型日期封面卡（P1-05 bento）
  //   招牌大日期 + eyebrow 年月 + 128vp 光晕 + 慢转虚线环 + 名言轮播文字区 + 黑色 CTA
  // ═══════════════════════════════════════════════════════════
  @Builder
  buildDateCoverCard() {
    Column() {
      // ── 日期面板：60fp 青数字（font-sans，非 mono）+ 竖排年月 eyebrow ──
      Row() {
        Text(this.dayStr)
          .fontSize(TYPO.numHero.size + 12)
          .fontWeight(900)
          .fontColor(this.tokens ? this.tokens.primary : '#00C2B8')
          .letterSpacing(-2)
          .lineHeight(TYPO.numHero.size + 12)

        Column() {
          Text(this.yearMonthStr)
            .fontSize(TYPO.eyebrow.size - 2)
            .fontWeight(700)
            .fontColor(this.tokens ? this.tokens.textTertiary : '#B0B0B0')
            .letterSpacing(2)
          Divider()
            .width(24)
            .strokeWidth(2)
            .color(this.tokens ? this.tokens.primary : '#00C2B8')
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 8, top: 6 })

        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // ── 中央 hero：7 猫 Lottie 动画轮播（与名言同 7s 节拍自动 + 左右滑动 / 点击手动切换 · T-LT03 · HUI-001）──
      // F1+F4 单实例内存：仅渲染 1 个 LottieAnimation；切换只改 catIndex → animPath @Prop 变化 →
      //   组件内部 stop旧→destroy旧→load新，任一时刻内存中仅 1 个已解析猫动画（7 只为可切换池，绝不并存）。
      // S5 出屏停播：LottieAnimation 内建 onVisibleAreaChange([0,1]) 停播画面；本 Stack 另挂 onVisibleAreaChange
      //   置 isCardVisible 门控统一节拍 tick 内的猫推进（出屏暂停/回屏下个 tick 恢复，避免后台空转），二者互不干扰。
      // 要点2 手势隔离：onClick + 显式 SwipeGesture(Horizontal) 绑本 160vp 装饰 Stack；内层猫容器与指示点
      //   hitTestBehavior(None) → 触摸统一交本 Stack；竖向拖动因方向正交仍由父 Scroll 接管（不被吞）。
      //   手动切换（点/滑）不重置节拍，下个 tick 继续与名言同步（HUI-001）。
      Stack({ alignContent: Alignment.Center }) {
        // 猫动画（Contain 等比不裁切；方形盒子按只用 displaySize，补偿各画布主体占比差异 · HUI-018）；opacity 承载切换淡入淡出
        Column() {
          LottieAnimation({
            animPath: HOME_CAT_ANIMS[this.catIndex].path,
            loop: true,
            autoPlay: true,
            contentMode: 'Contain',
            accessibilityLabel: '' // 外层 Stack 统一朗读，猫 Canvas 置装饰不重复朗读
          })
        }
        .width(HOME_CAT_ANIMS[this.catIndex].displaySize)
        .height(HOME_CAT_ANIMS[this.catIndex].displaySize)
        .opacity(this.catOpacity)
        .hitTestBehavior(HitTestMode.None) // 触摸透传给外层装饰 Stack（与 F2 一致）

        // 轮播位置指示点（跟随池子数量，非交互指示器；底部内嵌不改外层布局高度）
        Column() {
          Row({ space: 6 }) {
            ForEach(HOME_CAT_ANIMS, (item: CatLottieItem, idx: number) => {
              Circle()
                .width(idx === this.catIndex ? 7 : 6)
                .height(idx === this.catIndex ? 7 : 6)
                .fill(idx === this.catIndex
                  ? (this.tokens ? this.tokens.primary : '#00C2B8')
                  : (this.tokens ? this.tokens.border : '#A2ECE9'))
                .opacity(idx === this.catIndex ? 1 : 0.5)
            }, (item: CatLottieItem) => item.path)
          }
          .margin({ bottom: 2 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height(160)
      .margin({ top: 4, bottom: 4 })
      .onClick(() => {
        // 命中区严格限定本 160vp 装饰 Stack（不与底部 CTA / 名言点击区重叠）→ 手动切下一只（重置自动计时）
        this.handleManualSwitchCat(1);
      })
      .gesture(
        // 要点2：显式水平 Swipe，与父 Scroll 竖向轴正交 → 竖向拖动不被吞
        SwipeGesture({ direction: SwipeDirection.Horizontal })
          .onAction((event: GestureEvent) => {
            // 水平滑：|angle|<90 近 0°=右滑（上一只）；|angle|>=90 近 ±180°=左滑（下一只）
            if (Math.abs(event.angle) >= 90) {
              this.handleManualSwitchCat(1);
            } else {
              this.handleManualSwitchCat(-1);
            }
          })
      )
      // HUI-001：装饰区出屏置 isCardVisible=false 暂停 tick 内猫推进、回屏下个 tick 恢复（与 LottieAnimation 内建停播互补）
      .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number) => {
        this.onCardVisibilityChange(currentRatio > 0);
      })
      .accessibilityGroup(true)
      .accessibilityText('猫咪动画：' + HOME_CAT_ANIMS[this.catIndex].label + '，共 ' + HOME_CAT_ANIMS.length + ' 只，自动轮播，点按或左右滑动手动切换')

      // ── 名言轮播文字区（原「你好，用心记录每一天」位置）──
      Column() {
        Text(this.currentQuote.content)
          .fontSize(TYPO.body.size + 1)
          .lineHeight(24)
          .fontFamily(FONT.serif)
          .fontStyle(FontStyle.Italic)
          .fontWeight(600)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .textAlign(TextAlign.Center)
          .width('100%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .opacity(this.quoteOpacity)

        Text('—— ' + this.currentQuote.author)
          .fontSize(TYPO.eyebrow.size)
          .fontWeight(500)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 8 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .opacity(this.quoteOpacity)
      }
      .width('100%')
      .padding({ left: 8, right: 8 })
      .margin({ top: 4, bottom: 16 })
      .accessibilityGroup(true)
      .accessibilityText('每日名言：' + this.currentQuote.content + ' —— ' + this.currentQuote.author)

      // ── 反色实心 CTA：开始记录时光（底=textPrimary 会随深浅色翻转，故文字/图标须用与之对比的 surface 反色 token）──
      // T-BUG-002 修复（HUI-001）：底色 textPrimary 浅色=#1A1A1A/深色=#F5F5F5 会翻转；原文字硬编码 '#FFFFFF'
      //   在深色模式下与近白底色形成「白底白字」不可见。改用 surface（浅=#FFFFFF/深=#0F172A），
      //   与 textPrimary 底色恒为反色 → 两种模式均高对比可读；图标同理由 primary(青，深色底下对比不足) 改 surface。
      Row() {
        SymbolGlyph(IconMapper.BOOKMARK)
          .fontSize(16)
          .fontColor([this.tokens ? this.tokens.surface : '#FFFFFF'])
        Text('开始记录时光')
          .fontSize(TYPO.body.size)
          .fontWeight(700)
          .fontColor(this.tokens ? this.tokens.surface : '#FFFFFF')
          .margin({ left: 8 })
          .attributeModifier(SKETCH_BODY) // HUI-026：按钮字→清松手写体2
      }
      .width('100%')
      .height(48)
      .justifyContent(FlexAlign.Center)
      .borderRadius(24)
      .backgroundColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
      .onClick(() => {
        this.goEdit();
      })
      .accessibilityText('开始记录时光，进入写日记')
    }
    .width('100%')
    .padding(SPACING.cardPadLg)
    .borderRadius(RADIUS.card)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .border({
      width: 1,
      color: this.tokens ? this.tokens.border : '#A2ECE9'
    })
    .shadow({
      radius: 20,
      color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
      offsetX: 0,
      offsetY: 6
    })
  }

  // ═══════════════════════════════════════════════════════════
  // 打卡签到卡（CheckInButton + StreakCounter），置于日期封面卡下方
  // ═══════════════════════════════════════════════════════════
  @Builder
  buildCheckInCard() {
    Column() {
      // 头部：标题 + 状态药丸
      Row() {
        Text('每日签到')
          .fontSize(TYPO.eyebrow.size)
          .fontWeight(700)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
          .letterSpacing(1)
          .attributeModifier(SKETCH_TITLE) // HUI-026：卡片 kicker→猫啃什锦黑

        Blank()

        Text(this.checkedIn ? '已签到' : '待签到')
          .fontSize(TYPO.eyebrow.size - 1)
          .fontWeight(700)
          .fontColor(this.tokens ? this.tokens.primary : '#00C2B8')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .borderRadius(12)
          .backgroundColor(this.tokens ? this.tokens.accent : '#E6F9F8')
          .attributeModifier(SKETCH_BODY) // HUI-026：状态标签→清松手写体2
      }
      .width('100%')

      // 主体：打卡按钮 + 连续天数计数器
      Row() {
        CheckInButton({
          isChecked: this.checkedIn,
          onCheckIn: () => {
            this.handleCheckIn();
          }
        })

        Blank()

        Column() {
          // HUI-001：dimmed 灰/焰色由 checkedIn 决定（未打卡=灰，已打卡=火焰橙亮）
          StreakCounter({ streak: this.streak, dimmed: !this.checkedIn })
          Text('连续打卡天数')
            .fontSize(TYPO.eyebrow.size - 1)
            .fontWeight(600)
            // HUI-001：已打卡=正常副文字；未打卡=熄灭灰 textTertiary（与火焰熄灭同步）
            .fontColor(this.checkedIn ?
              (this.tokens ? this.tokens.textSecondary : '#5A5A5A') :
              (this.tokens ? this.tokens.textTertiary : '#B0B0B0'))
            .margin({ top: 8 })
            .attributeModifier(SKETCH_BODY) // HUI-026：说明标签→清松手写体2
        }
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      .margin({ top: 4 })

      // 底部提示
      Text(this.checkedIn ? '今日已打卡，连续自律达成' : '点击圆形，完成今日时光签到')
        .fontSize(TYPO.eyebrow.size)
        .fontColor(this.tokens ? this.tokens.textTertiary : '#B0B0B0')
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 12 })
        .attributeModifier(SKETCH_BODY) // HUI-026：提示文案→清松手写体2
    }
    .width('100%')
    .padding(SPACING.cardPadLg)
    .borderRadius(RADIUS.cardLg)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .shadow({
      radius: 16,
      color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
      offsetX: 0,
      offsetY: 4
    })
  }

  // ═══════════════════════════════════════════════════════════
  // 左侧半宽抽屉菜单 + 全屏遮罩模糊
  //   width 50% + translateX 滑入 + backdropBlur(8) 遮罩（点击关闭）
  // ═══════════════════════════════════════════════════════════
  @Builder
  buildDrawer() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 遮罩层（半透明 + backdropBlur，点击关闭）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.35)')
        .backdropBlur(8)
        .onClick(() => {
          this.closeMenu();
        })
        .transition(
          TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseInOut })
        )

      // 抽屉主体（半宽 50%，从左滑入）
      Column() {
        // 抽屉头部
        Row() {
          Image($rawfile('logo.jpg'))
            .width(48)
            .height(48)
            .objectFit(ImageFit.Contain)
            .borderRadius(24)

          Column() {
            Text('电子日记')
              .fontSize(TYPO.cardTitle.size)
              .fontWeight(700)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .attributeModifier(SKETCH_BODY) // HUI-026：抽屉品牌名→清松手写体2
            Text('用心记录每一天')
              .fontSize(TYPO.eyebrow.size)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
              .margin({ top: 2 })
              .attributeModifier(SKETCH_BODY) // HUI-026：副标题→清松手写体2
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 12 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ top: 8, bottom: 20 })

        Divider()
          .strokeWidth(0.5)
          .color(this.tokens ? this.tokens.divider : '#EEEEEE')
          .margin({ bottom: 8 })

        // 菜单条目：番茄钟 / 待办 / 明日日程
        ForEach(this.menuItems, (item: MenuItemConfig) => {
          Row() {
            Stack() {
              Circle()
                .width(40)
                .height(40)
                .fill('#FFFFFF')
                .shadow({ radius: 4, color: 'rgba(0,0,0,0.08)', offsetX: 0, offsetY: 2 })
              Image(item.icon)
                .width(56)
                .height(56)
                .objectFit(ImageFit.Contain)
            }
            .width(40)
            .height(40)
            .margin({ left: 8, right: 8 })

            Column() {
              Text(item.label)
                .fontSize(TYPO.body.size)
                .fontWeight(600)
                .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                .attributeModifier(SKETCH_BODY) // HUI-026：菜单项名→清松手写体2
              Text(item.desc)
                .fontSize(TYPO.eyebrow.size - 1)
                .fontColor(this.tokens ? this.tokens.textTertiary : '#B0B0B0')
                .margin({ top: 2 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .attributeModifier(SKETCH_BODY) // HUI-026：菜单项说明→清松手写体2
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 12 })

            SymbolGlyph(IconMapper.FORWARD)
              .fontSize(14)
              .fontColor([this.tokens ? this.tokens.textTertiary : '#B0B0B0'])
          }
          .width('100%')
          .height(60)
          .padding({ left: 4, right: 4 })
          .onClick(() => {
            this.handleMenuTap(item.key);
          })
          .accessibilityText(item.label + '，' + item.desc)
        }, (item: MenuItemConfig) => item.key)

        Blank()

        // 底部装饰动画（透明底，拉绳子动画）
        LottieAnimation({
          animPath: this.ropeAnimPath,
          loop: false,
          autoPlay: true,
          animWidth: 200,
          animHeight: 200,
          frameRate: 12,
          shouldPlay: this.showMenu
        })
          .width(200)
          .height(200)
          .margin({ bottom: 60, left: -10 })
      }
      .width('50%')
      .height('100%')
      .padding({
        left: SPACING.cardPadMd,
        right: SPACING.cardPadMd,
        top: 56,
        bottom: SPACING.cardPadMd
      })
      .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
      .shadow({
        radius: 24,
        color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.18)',
        offsetX: 4,
        offsetY: 0
      })
      .transition(
        TransitionEffect.translate({ x: DRAWER_SLIDE_X })
          .animation({ duration: 300, curve: Curve.EaseOut })
          .combine(TransitionEffect.OPACITY.animation({ duration: 200 }))
      )
    }
    .width('100%')
    .height('100%')
  }

  // ── 名言逻辑 ────────────────────────────────────────

  /**
   * 拉取 DB 当日名言写入展示 @State currentQuote（T104）。
   * DB 当日名言优先；init 可能 throw → try/catch 兜底；getCurrentQuote() 返回 Quote|null → 判空。
   * quoteInited 守卫在 await init 前先置位：防 QUOTE_CHANGED 回调（init 内部 refresh 会 emit 该事件）重入 init 造成无限递归。
   * 失败/为空时保留 currentQuote 本地兜底名言，不崩、不清空；失败置回未初始化以便后续事件重试。
   */
  private async loadQuote(): Promise<void> {
    try {
      if (!this.quoteInited) {
        this.quoteInited = true;
        await this.quoteVm.init();
      }
      const q: Quote | null = this.quoteVm.getCurrentQuote();
      if (q !== null) {
        this.currentQuote = { content: q.content, author: q.author };
      }
    } catch (err) {
      this.quoteInited = false;
      hilog.error(0x0000, TAG, 'loadQuote failed: %{public}s', (err as Error).message);
    }
  }

  /**
   * 启动统一轮播节拍定时器（幂等：已启动则不重复 · HUI-001 单一节拍源，替代原「名言/猫」双定时器防漂移）。
   * 每 QUOTE_SWITCH_INTERVAL(7s) tick 同拍推进「名言 + 猫」：同一时刻双双淡出淡入（淡出时长统一 QUOTE_FADE_DURATION，视觉同呼吸）。
   * 边角：若名言处于「DB 每日一句固定不轮播」模式（tick 内名言无变化），猫仍照常按本 tick 推进。
   * S5：出屏（isCardVisible=false）仅暂停猫推进（避免出屏 destroy/load 空转），名言 tick 照旧；回屏下个 tick 自然恢复同步。
   */
  private startBeatTimer(): void {
    if (this.beatTimerId !== -1) {
      return;
    }
    this.beatTimerId = setInterval(() => {
      this.switchQuote();
      if (this.isCardVisible) {
        this.switchCat(1, QUOTE_FADE_DURATION);
      }
    }, QUOTE_SWITCH_INTERVAL);
  }

  /**
   * 切换名言：淡出 → 换内容 → 淡入（opacity 800ms 过渡）
   */
  private switchQuote(): void {
    animateTo({ duration: QUOTE_FADE_DURATION, curve: Curve.EaseInOut }, () => {
      this.quoteOpacity = 0;
    });
    this.quoteFadeTimerId = setTimeout(() => {
      this.quoteFadeTimerId = -1;
      this.quoteIndex = (this.quoteIndex + 1) % HOME_QUOTES.length;
      // 本地轮播作兜底内容源：推进到下一条 HOME_QUOTES 写入展示 @State（DB 当日名言由 loadQuote/QUOTE_CHANGED 覆盖优先）
      this.currentQuote = HOME_QUOTES[this.quoteIndex];
      animateTo({ duration: QUOTE_FADE_DURATION, curve: Curve.EaseInOut }, () => {
        this.quoteOpacity = 1;
      });
    }, QUOTE_FADE_DURATION);
  }

  /**
   * 切换猫动画（delta=+1 下一只 / -1 上一只 · T-LT03）。
   * F1+F4 单实例：仅推进 catIndex → LottieAnimation animPath @Prop 变化 → 组件内 stop旧→destroy旧→load新，
   *   任一时刻仅 1 个已解析实例；本方法绝不新建/并存 Lottie 实例。
   * 过渡：单实例约束下不做双层 crossfade，改用轻量 opacity 淡出→换 index→淡入。
   * fadeMs（HUI-001）：自动同拍切换传 QUOTE_FADE_DURATION(800ms) 与名言同呼吸；手动切换传 CAT_FADE_DURATION(180ms) 快反馈。
   * 防抖：淡出进行中（catFadeTimerId!==-1）忽略新切换，避免定时器叠加与残留。
   */
  private switchCat(delta: number, fadeMs: number): void {
    if (this.catFadeTimerId !== -1) {
      return;
    }
    const len: number = HOME_CAT_ANIMS.length;
    const next: number = (this.catIndex + delta + len) % len;
    if (next === this.catIndex) {
      return;
    }
    animateTo({ duration: fadeMs, curve: Curve.EaseInOut }, () => {
      this.catOpacity = 0;
    });
    this.catFadeTimerId = setTimeout(() => {
      this.catFadeTimerId = -1;
      this.catIndex = next; // 触发 animPath 变化 → LottieAnimation 内部单实例重载
      animateTo({ duration: fadeMs, curve: Curve.EaseInOut }, () => {
        this.catOpacity = 1;
      });
    }, fadeMs);
  }

  /**
   * 手动切换猫动画（点击 / 左右滑触发）：快过渡切换即可（HUI-001）。
   * 不重置统一节拍——下个 tick 名言与猫继续同拍推进，节拍不乱。
   */
  private handleManualSwitchCat(delta: number): void {
    this.switchCat(delta, CAT_FADE_DURATION);
  }

  /**
   * 装饰区可见性变化（S5 · HUI-001）：置 isCardVisible 门控统一节拍 tick 内的猫推进——
   * 出屏暂停猫换只（避免后台 destroy/load 空转，名言 tick 照旧）、回屏下个 tick 自然恢复同步。
   */
  private onCardVisibilityChange(visible: boolean): void {
    this.isCardVisible = visible;
  }

  // ── 抽屉 / 深色切换 ────────────────────────────────

  private openMenu(): void {
    // 重置拉绳子动画，每次打开菜单从拉绳子1开始
    this.ropeAnimPath = 'animations/拉绳子1.json';
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.showMenu = true;
    });
  }

  private closeMenu(): void {
    animateTo({ duration: 250, curve: Curve.EaseIn }, () => {
      this.showMenu = false;
    });
  }

  /**
   * 点击抽屉菜单项：关闭抽屉并按 key 导航（未注册页面降级 toast）
   */
  private handleMenuTap(key: string): void {
    this.closeMenu();
    if (key === 'pomodoro') {
      this.goPomodoro();
    } else if (key === 'today') {
      this.goTodo();
    } else if (key === 'tomorrow') {
      this.goTomorrow();
    }
  }

  /**
   * 一键切换深色 / 浅色模式（走全局 ThemeManager，AppStorage 联动全 App 刷新）
   */
  private toggleDarkMode(): void {
    getThemeManager().toggleDarkMode().catch((err: Error) => {
      hilog.error(0x0000, TAG, 'toggleDarkMode failed: %{public}s', err.message);
    });
  }

  // ── 打卡逻辑（T103：接 CheckInViewModel 真实读写）──────

  /**
   * 异步拉取今日打卡状态 + 连续天数（aboutToAppear / CHECKIN_CHANGED 时调用）。
   * R1：写入的是 @State checkedIn/streak，触发 UI 及子组件（CheckInButton/StreakCounter）@Prop 下流刷新。
   * R3：VM getter 已返回前端期望类型（getTodayStatus:boolean / getStreakDays:number），无需二次映射。
   * §0.1/§9：try/catch 兜底，DB 失败保持默认（未打卡 / 0）不崩。
   */
  private async loadCheckIn(): Promise<void> {
    try {
      await this.checkInVm.init(DateUtils.today());
      this.checkedIn = this.checkInVm.getTodayStatus();
      this.streak = this.checkInVm.getStreakDays();
    } catch (err) {
      hilog.error(0x0000, TAG, 'loadCheckIn failed: %{public}s', (err as Error).message);
    }
  }

  /**
   * 处理打卡：调 CheckInViewModel.checkIn() 真实写库，随后以 VM 真实态回读 @State。
   * checkIn() 内部：已打卡返回 false；成功 insert 后回读 streak 并 emit CHECKIN_CHANGED
   * （本页已订阅该事件，会再同步一次，保证跨入口一致）。
   */
  private async handleCheckIn(): Promise<void> {
    if (this.checkedIn) {
      return;
    }
    try {
      const ok: boolean = await this.checkInVm.checkIn();
      // 无论成功 / 已打卡，都以 VM 真实态回读，避免本地态与 DB 不一致
      this.checkedIn = this.checkInVm.getTodayStatus();
      this.streak = this.checkInVm.getStreakDays();
      if (!ok) {
        promptAction.showToast({ message: '今日已签到', duration: 1200 });
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'handleCheckIn failed: %{public}s', (err as Error).message);
      promptAction.showToast({ message: '签到失败，请稍后重试', duration: 1200 });
    }
  }

  // ── 导航 ────────────────────────────────────────

  private goEdit(): void {
    router.pushUrl({ url: 'pages/DiaryEditPage' }).catch((err: Error) => {
      hilog.error(0x0000, TAG, 'pushUrl DiaryEditPage failed: %{public}s', err.message);
    });
  }

  /** 打开日记轮播模态框（顶部「日记本▾」入口，替换原跳日历行为，T-FEAT-001） */
  private openDiaryModal(): void {
    this.showDiaryModal = true;
  }

  /** 跳转某篇日记详情页（复用既有路由契约：params { date }，见 CalendarPage 导航） */
  private goDiaryDetail(date: string): void {
    const params: DiaryDetailNavParams = { date: date };
    router.pushUrl({ url: 'pages/DiaryDetailPage', params: params }).catch((err: Error) => {
      hilog.error(0x0000, TAG, 'pushUrl DiaryDetailPage failed: %{public}s', err.message);
      promptAction.showToast({ message: '打开日记失败', duration: 1200 });
    });
  }

  /**
   * 构造日记本卡片数据（Diary[]，最新在前）。
   * ⚠️ TODO(DEV Agent)：当前为「类型化 mock」占位，UI 已就绪，需接入真实仓储（详见交付报告「数据源接入」）：
   *   1) DiaryDao 暂无 queryAll（仅 queryByMonth/search）→ 需新增「查询全部日记」方法
   *      （建议 DiaryViewModel.getAllDiaries(): Promise<Diary[]>，SELECT * FROM diary ORDER BY date DESC）；
   *   2) 接入后：本方法改 async 拉取，或由 aboutToAppear await 填充 this.diaryItems（真实 Diary[]，含 id/date/content/images）；
   *   3) 卡片封面由 shared/DiaryCoverResolver.resolveDiaryCover(diary, index) 解析（DEV 契约，UI 直接喂 Image）；
   *      标题由 Diary.content 首行派生（Diary 无 title 字段，纯展示派生，见 DiaryCarouselModal.deriveTitle）。
   * 说明：mock 未设 images（默认 '[]'）→ resolveDiaryCover 按 id%19 取内置封面，各篇错开不撞图。
   */
  private async loadDiaries(): Promise<void> {
    try {
      this.diaryItems = await this.diaryVm.getAllDiaries();
    } catch (err) {
      hilog.error(0x0000, TAG, 'loadDiaries failed: %{public}s', (err as Error).message);
    }
  }

  private goPomodoro(): void {
    router.pushUrl({ url: 'pages/PomodoroPage' }).catch((err: Error) => {
      hilog.error(0x0000, TAG, 'pushUrl PomodoroPage failed: %{public}s', err.message);
    });
  }

  private goTodo(): void {
    router.pushUrl({ url: 'pages/TodoPage' }).catch((err: Error) => {
      hilog.error(0x0000, TAG, 'pushUrl TodoPage failed: %{public}s', err.message);
      promptAction.showToast({ message: '待办', duration: 1200 });
    });
  }

  private goTomorrow(): void {
    router.pushUrl({ url: 'pages/TomorrowPage' }).catch((err: Error) => {
      hilog.error(0x0000, TAG, 'pushUrl TomorrowPage failed: %{public}s', err.message);
      promptAction.showToast({ message: '明日日程', duration: 1200 });
    });
  }
}
