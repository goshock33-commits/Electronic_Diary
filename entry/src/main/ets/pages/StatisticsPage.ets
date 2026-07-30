// <!-- agentID: HUI-007 -->
// fix: HUI-016
// fix: HUI-FRONTEND
// 页面：统计页 — HarmonyOS 蓝白卡片风格
// 关联任务：T-SKETCH 统计页（已迁移至蓝白卡片主题）
// 开发范式：ArkTS 声明式开发范式 (Stage 模型)
// 崩溃防范：PROJECT_SPEC §9.4 @StorageLink tokens 全判空
// HUI-040：深色模式 P0 修复——dayDot/分隔线/周期 pill 前景死值全部 token 化（darkmode_audit 问题2）
// 改版：全部 SketchIcon→SymbolGlyph（IconMapper 已验证常量）；手绘边框→均匀细边框读 token；硬编码色→主题 token。
// HUI-001：顶部 2×2 数据卡整块替换为 TrendLineChart 四线趋势曲线图（"笔画出来"入场动画，图例带总数承接原卡数字；
//   数据走 DEV-004 契约 StatisticsViewModel.getDailySeries(7|30)，loadStats/事件订阅刷新时同步刷新并重播画线）。

import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper, RADIUS, SPACING, TYPO, FONT, ICON, EventBus, getThemeManager } from '@ohos/shared';
import { TodoProgressBar, StatisticsViewModel, TrendLineChart, StatsPeriod } from 'features_statistics';
import type { TrendChartData, MonthStats } from 'features_statistics';
import { router } from '@kit.ArkUI';

interface DayDot {
  dateStr: string;
  dayNum: string;
  status: 'done' | 'miss' | 'today';
}

interface MonthStatsData {
  checkedDays: number;
  totalDays: number;
  diaryCount: number;
  pomodoroCount: number;
  completedTodos: number;
  totalTodos: number;
  label: string;
}

enum PageLoadState { LOADING = 'loading', LOADED = 'loaded', ERROR = 'error', EMPTY = 'empty' }

@Entry
@Component
export struct StatisticsPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  // fix: HUI-016 · T-D01复测 —— 与 HomePage 同款补挂深色标记 @StorageLink（主题翻转显式刷新信号，全局写法统一）
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @State currentData: MonthStatsData = {
    checkedDays: 0, totalDays: 0, diaryCount: 0, pomodoroCount: 0,
    completedTodos: 0, totalTodos: 0, label: '本周'
  };

  private statsVm: StatisticsViewModel = new StatisticsViewModel();
  @State sevenDays: DayDot[] = [];
  // HUI-001：四线趋势图数据（DEV-004 契约 getDailySeries；版本号驱动图表重播画线动画）
  @State chartDays: number = 7;
  @State chartSeries: TrendChartData = {
    dates: [], checkIn: [], diary: [], pomodoro: [], todoDone: [],
    totalCheckInDays: 0, totalDiary: 0, totalPomodoro: 0, totalTodoDone: 0
  };
  @State chartVersion: number = 0;
  @State loadState: PageLoadState = PageLoadState.LOADING;
  @State pageEnterAnimated: boolean = false;

  // fix: HUI-016 · T-D01复测 —— 删除 c_* 私有 getter 中转（PROJECT_SPEC §9.1 getter-in-build 风险区：
  //   本页经 getter 间接读 @StorageLink 时未随 theme_tokens 变更刷新，深色下卡片文字保持黑色；
  //   HomePage 直接内联读 token 则正常翻转）。取色全部改为 build 内直接内联
  //   this.tokens ? this.tokens.xxx : '兜底'，与 HomePage 写法完全一致，兜底值沿用原 getter 兜底不变。

  aboutToAppear(): void {
    this.sevenDays = this.buildSevenDays();
    // DEV-003 Bug修复：订阅打卡变更事件 —— 此前本页仅 aboutToAppear 一次性拉数，
    //   Tab 常驻（MainPage TabContent 不销毁重建）导致首页打卡后本页"打卡天数"不刷新。
    //   注意：不在 aboutToDisappear 调 EventBus.off —— off 按事件名全量退订，
    //   会连带移除 HomePage 对 CHECKIN_CHANGED 的订阅；本页与 HomePage 同为 Tab 常驻组件，
    //   生命周期与应用一致，无泄漏风险（与 HomePage T103 订阅模式对齐）。
    EventBus.on(EventBus.EventNames.CHECKIN_CHANGED, (data: Record<string, Object>) => {
      this.loadStats();
    });
    // DEV-003 ①：待办进度实时刷新 —— 与 CHECKIN_CHANGED 同款病同款修（Tab 常驻 + 一次性拉数）：
    //   订阅待办全生命周期事件（新增/勾选/删除/编辑），任一变更后重拉统计。
    //   TODO_UPDATED 为本次新增事件（EventBus.ets），TodoViewModel.update 编辑保存后发射；
    //   TaskExtractionViewModel.convertToTodo 已补发 TODO_CREATED。同因不退订（off 按事件名全量退订）。
    EventBus.on(EventBus.EventNames.TODO_CREATED, (data: Record<string, Object>) => {
      this.loadStats();
    });
    EventBus.on(EventBus.EventNames.TODO_COMPLETED, (data: Record<string, Object>) => {
      this.loadStats();
    });
    EventBus.on(EventBus.EventNames.TODO_DELETED, (data: Record<string, Object>) => {
      this.loadStats();
    });
    EventBus.on(EventBus.EventNames.TODO_UPDATED, (data: Record<string, Object>) => {
      this.loadStats();
    });
    // fix: HUI-016 · T-D01复测实证 —— 后台 TabContent 的 @StorageLink 收不到 theme_tokens 变更：
    //   模拟器实测（切深色时本页处于后台 tab）：主页正常翻转，本页与"我的"页均保持旧色板，
    //   回到前台也不再同步；页内 @State 重渲染时 this.tokens 仍是旧对象 → 链路断在后台链接值未更新。
    //   与上方 CHECKIN_CHANGED 同因同修（Tab 常驻 + 事件自愈，DEV-003 先例）：订阅 THEME_CHANGED
    //  （ThemeManager 每次换肤必发，架构 4.6），从 ThemeManager 真相源回读色板写回链接，触发本页重渲染。
    //   同因不退订（off 按事件名全量退订会误伤其他订阅者；本页 Tab 常驻与应用同生命周期）。
    EventBus.on(EventBus.EventNames.THEME_CHANGED, (data: Record<string, Object>) => {
      this.tokens = getThemeManager().getTokens();
      this.isDark = getThemeManager().isDarkMode();
    });
    this.loadStats();
    animateTo({ duration: 300, curve: Curve.EaseOut }, () => { this.pageEnterAnimated = true; });
  }

  private async loadStats(): Promise<void> {
    this.loadState = PageLoadState.LOADING;
    // HUI-001：趋势图与主统计同步刷新（事件订阅重拉时也走这里；数据到达后图表重播画线属正常）
    this.loadChartSeries();
    try {
      const now: Date = new Date();
      const year: number = now.getFullYear();
      const month: number = now.getMonth() + 1;
      this.statsVm.setMonth(year, month);

      const weekStats: MonthStats = await this.statsVm.loadPeriod(StatsPeriod.WEEK);
      this.currentData = this.mapStats(weekStats, '本周');
      this.loadState = PageLoadState.LOADED;
    } catch (e) {
      this.loadState = PageLoadState.ERROR;
    }
  }

  // fix: HUI-FRONTEND — F6：VM MonthStats → 页面渲染结构（直用 stats.checkedDays/totalDays，删客户端反推）
  private mapStats(stats: MonthStats, label: string): MonthStatsData {
    const mapped: MonthStatsData = {
      checkedDays: stats.checkedDays, totalDays: stats.totalDays, diaryCount: 0,
      pomodoroCount: stats.pomodoroStats.focusCount,
      completedTodos: stats.todoStats.completed, totalTodos: stats.todoStats.total, label: label
    };
    return mapped;
  }

  // HUI-001：拉取四线逐日序列（DEV-004 契约 getDailySeries(7|30)，Index 已导出）。
  //   成功后版本号 +1 → TrendLineChart @Watch 重播画线；失败保持旧数据，不打断页面其余加载。
  // fix: DEV-010 · 修复模块名与类型错误——显式声明 getDailySeries 返回类型避免 any 推断
  // fix: DEV-011 · 修复结构化类型错误（arkts-no-structural-typing Line 138）
  // fix: DEV-012 · TrendChartData 类型实例化修正——interface 不能 new，直接用对象字面量
  private async loadChartSeries(): Promise<void> {
    try {
      const s = await this.statsVm.getDailySeries(this.chartDays);
      const mapped: TrendChartData = {
        dates: s.dates,
        checkIn: s.checkIn,
        diary: s.diary,
        pomodoro: s.pomodoro,
        todoDone: s.todoDone,
        totalCheckInDays: s.totalCheckInDays,
        totalDiary: s.totalDiary,
        totalPomodoro: s.totalPomodoro,
        totalTodoDone: s.totalTodoDone
      };
      this.chartSeries = mapped;
      this.chartVersion = this.chartVersion + 1;
      this.refreshSevenDays();
    } catch (e) {
      // 静默保留旧曲线（契约实现内部已兜底补 0）
    }
  }

  private buildSevenDays(): DayDot[] {
    const result: DayDot[] = [];
    const base: Date = new Date();
    for (let i = 6; i >= 0; i--) {
      const d: Date = new Date(base.getFullYear(), base.getMonth(), base.getDate() - i);
      const dayNum: string = String(d.getDate()).padStart(2, '0');
      let status: 'done' | 'miss' | 'today' = 'miss';
      if (i === 0) {
        status = 'today';
      }
      result.push({ dateStr: (d.getMonth() + 1).toString() + '/' + dayNum, dayNum: dayNum, status: status });
    }
    return result;
  }

  // 加载趋势数据后，用 checkIn[] 0/1 序列刷新近七日签到状态
  private refreshSevenDays(): void {
    const checkIn: number[] = this.chartSeries.checkIn;
    const updated: DayDot[] = [];
    for (let i = 0; i < this.sevenDays.length; i++) {
      const dot: DayDot = this.sevenDays[i];
      let status: 'done' | 'miss' | 'today' = dot.status;
      // checkIn 数组按时间正序排列，最旧在前；sevenDays 也是正序（旧→新）
      if (i < checkIn.length && checkIn[i] === 1) {
        status = 'done';
      }
      updated.push({ dateStr: dot.dateStr, dayNum: dot.dayNum, status: status });
    }
    this.sevenDays = updated;
  }

  // ══════════════════════════════════════════════════
  // @Builder
  // ══════════════════════════════════════════════════

  // HUI-001：statCard @Builder 已随 2×2 数据卡整块移除（顶部改为 TrendLineChart 四线趋势图，
  //   打卡/日记/番茄钟/完成待办四数改由图表图例「名称 · 总数」承接）。

  @Builder dayDot(d: DayDot) {
    Column() {
      if (d.status === 'done') {
        Stack() {
          Circle().width(32).height(32).fill(this.tokens ? this.tokens.primary : '#0A59F7')
            .stroke(this.tokens ? this.tokens.primary : '#0A59F7').strokeWidth(1)
          SymbolGlyph(IconMapper.CHECKMARK)
            .fontSize(16)
            .fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF'])
        }.width(32).height(32)
      } else if (d.status === 'today') {
        Stack() {
          Circle().width(32).height(32).fill(Color.Transparent)
            // HUI-040：墨色死值 #000000 → 读 token／fix: HUI-016 内联化
            .stroke(this.tokens ? this.tokens.textPrimary : '#1A1A1A').strokeWidth(1.5).strokeDashArray([4, 3])
          Text(d.dayNum).fontFamily(FONT.monoBold).fontSize(TYPO.eyebrow.size)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        }.width(32).height(32)
      } else {
        Stack() {
          Circle().width(32).height(32).fill(Color.Transparent)
            // HUI-040：浅灰死值 #CCCCCC → 读 token（border 弱描边 / textTertiary 弱文字）／fix: HUI-016 内联化
            .stroke(this.tokens ? this.tokens.border : '#E0E6ED').strokeWidth(1.5).strokeDashArray([4, 4])
          Text(d.dayNum).fontFamily(FONT.mono).fontSize(TYPO.eyebrow.size)
            .fontColor(this.tokens ? this.tokens.textTertiary : '#999999')
        }.width(32).height(32)
      }
      Text(d.dateStr)
        .fontSize(TYPO.eyebrow.size).fontColor(this.tokens ? this.tokens.textTertiary : '#999999')
        .fontFamily(FONT.mono).margin({ top: 6 }).textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder dotLineSeparator() {
    // HUI-040：分隔线死值 #CCCCCC → 读 token border／fix: HUI-016 内联化
    Divider().width('100%').height(1.5).color(this.tokens ? this.tokens.border : '#E0E6ED')
      .margin({ top: 4, bottom: 8 })
  }

  build() {
    Scroll() {
      Column() {
        // ─── 顶部导航栏（返回按钮 + 标题）───
        Row() {
          Button() {
            SymbolGlyph(IconMapper.BACK)
              .fontSize(ICON.navBack)
              .fontWeight(FontWeight.Bold)
              .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(Color.Transparent)
          .onClick(() => router.back())
          .accessibilityText('返回')

          Text('统计')
            .fontSize(TYPO.cardTitle.size)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            .margin({ left: 8 })
        }
        .width('100%')
        .height(56)
        .padding({ left: SPACING.pageH, right: SPACING.pageH })
        .alignItems(VerticalAlign.Center)

        // ─── Zone A: 四线趋势曲线图（HUI-001：原 2×2 数据卡整块替换；7/30 切档回调重拉数据后重播画线）───
        TrendLineChart({
          chartData: this.chartSeries,
          dataVersion: this.chartVersion,
          selectedDays: this.chartDays,
          onRangeChange: (days: number): void => {
            this.chartDays = days;
            this.loadChartSeries();
          }
        })
          .width('100%')

        // ─── Zone B: 近七日签到 ───
        Column() {
          Text('近七日签到轨迹')
            .fontSize(TYPO.sectionTitle.size).fontWeight(TYPO.sectionTitle.weight)
            .fontFamily(FONT.sketchTitle + ', HarmonyOS Sans, sans-serif')
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            .width('100%').margin({ bottom: SPACING.cardGap })
          Row({ space: 0 }) {
            ForEach(this.sevenDays, (d: DayDot) => { this.dayDot(d) })
          }.width('100%').justifyContent(FlexAlign.SpaceEvenly)
        }
        .width('100%').borderRadius(RADIUS.card).padding(SPACING.cardPadLg)
        .backgroundColor(this.tokens ? this.tokens.surface : '#FFFFFF')
        // HUI-032：不均匀加粗手绘边框 → 均匀细边框读 token，与其他页面卡片统一
        .border({ width: 1, color: this.tokens ? this.tokens.border : '#E0E6ED' })
        .margin({ top: SPACING.sectionGap })

        // ─── Zone C: 待办进度 ───
        TodoProgressBar({ completed: this.currentData.completedTodos, total: this.currentData.totalTodos })
          .margin({ top: SPACING.sectionGap })

        Column().height(SPACING.pageBottom)
      }
      .width('100%')
      .padding({ left: SPACING.pageH, right: SPACING.pageH, top: SPACING.pageTop })
    }
    .width('100%').height('100%')
    .backgroundColor(this.tokens ? this.tokens.bg : '#F5F7FA')
    .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    // fix: HUI-FRONTEND — F6：本页为 Tab/分段常驻 @Component（无 onPageShow 生命周期），
    //   用可见性回调等价实现「页面重新显示时重拉数据」：切回本段/本 Tab 时 isVisible=true → loadStats
    .onVisibleAreaChange([0.0], (isVisible: boolean, currentRatio: number) => {
      if (isVisible) { this.loadStats(); }
    })
  }
}
