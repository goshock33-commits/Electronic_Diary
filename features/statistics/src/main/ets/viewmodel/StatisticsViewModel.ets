// <!-- agentID: DEV-010 -->
// fix: HUI-FRONTEND
// File: StatisticsViewModel.ets
// Task: M09 Statistics business logic - AppStorage writes (checkInRate/moodDistribution/todoCompletionRate)
// Architecture: ARC-001 S4 statistics / 4.1 DAO aggregation queries
// DAOs referenced: CheckInDao, TodoDao, HappyThingDao, PomodoroDao (already async-ified by other modules)

import { CheckInDao } from '@ohos/shared';
import { TodoDao } from '@ohos/shared';
import { HappyThingDao } from '@ohos/shared';
import { PomodoroDao } from '@ohos/shared';
import { PomodoroSession } from '@ohos/shared';
// agentID: DEV-004 — 曲线图逐日聚合新增依赖：DiaryDao(日记逐日/总数)、DailyCount(GROUP BY 返回行)、
//   CheckIn/TodoItem(显式类型标注)、DateUtils(日期序列，全库统一 "YYYY-MM-DD")
import { DiaryDao } from '@ohos/shared';
import { DailyCount } from '@ohos/shared';
import { CheckIn } from '@ohos/shared';
import { TodoItem } from '@ohos/shared';
import { DateUtils } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'StatisticsViewModel';

export enum StatsPeriod { WEEK = 'week', MONTH = 'month' }
export interface MoodDistribution { emoji: string; count: number; }
export interface TodoStats { total: number; completed: number; rate: number; }
export interface PomodoroStats { sessions: number; totalMinutes: number; focusCount: number; }
export interface MonthStats { checkInRate: number; checkedDays: number; totalDays: number; moodDistribution: MoodDistribution[]; todoStats: TodoStats; pomodoroStats: PomodoroStats; }
interface DateRange { start: string; end: string; totalDays: number; }

// agentID: DEV-004 — 统计页曲线图契约（与 HUI 并行约定，字段/语义不可变更）
/**
 * 按天聚合的统计序列（最近 days 天，含今天，升序）。
 * 四条曲线数组与 dates 严格等长对齐，缺数据日补 0。
 * totals 口径 = 原统计页四卡（load() 现算法）：
 *   totalCheckInDays=本月打卡天数 / totalDiary=日记总数(全量) /
 *   totalPomodoro=本月 focus 会话数 / totalTodoDone=今日('today'型)已完成待办数。
 */
export interface DailyStatsSeries {
  dates: string[];        // "YYYY-MM-DD" 升序，长度 = days
  checkIn: number[];      // 每日打卡 0/1
  diary: number[];        // 每日日记篇数
  pomodoro: number[];     // 每日完成番茄钟个数
  todoDone: number[];     // 每日完成待办数
  totalCheckInDays: number;  // 累计打卡天数（原卡片口径）
  totalDiary: number;        // 日记总数
  totalPomodoro: number;     // 番茄钟总数
  totalTodoDone: number;     // 完成待办总数
}

export class StatisticsViewModel {
  private period: StatsPeriod = StatsPeriod.MONTH;
  private year: number = new Date().getFullYear();
  private month: number = new Date().getMonth() + 1;
  private data: MonthStats | null = null;

  setPeriod(period: StatsPeriod): void { this.period = period; }
  setMonth(year: number, month: number): void { this.year = year; this.month = month; }
  getCurrentPeriod(): StatsPeriod { return this.period; }
  getData(): MonthStats | null { return this.data; }

  /** F6: 按周期加载统计（WEEK=最近7天含今天 / MONTH=当月），统计页周/月切换分别调用 */
  async loadPeriod(period: StatsPeriod): Promise<MonthStats> {
    this.period = period;
    return this.load();
  }

  async load(): Promise<MonthStats> {
    const range: DateRange = this.getDateRange();
    const start = range.start;
    const end = range.end;
    const totalDays = range.totalDays;
    try {
      // F6: 打卡改按周期范围查询（WEEK=最近7天 / MONTH=当月），替代恒按月查询
      const checkIns = await CheckInDao.queryByDateRange(start, end);
      const checkInRate = totalDays > 0 ? Math.round((checkIns.length / totalDays) * 100) : 0;

      const moodMap = new Map<string, number>();
      const todayTodos = await TodoDao.queryByDateAndType(this.getTodayDate(), 'today');
      for (const ci of checkIns) {
        const items = await HappyThingDao.queryByDate(ci.date);
        for (const h of items) { moodMap.set(h.emoji_id, (moodMap.get(h.emoji_id) ?? 0) + 1); }
      }
      const moodDist: MoodDistribution[] = [];
      moodMap.forEach((count, emoji) => moodDist.push({ emoji, count }));
      moodDist.sort((a, b) => b.count - a.count);

      let todoTotal = 0, todoCompleted = 0;
      // Collect todo stats across all days in range (simplified: use today)
      todoTotal = todayTodos.length;
      todoCompleted = todayTodos.filter((t) => t.completed === 1).length;
      const todoStats: TodoStats = { total: todoTotal, completed: todoCompleted, rate: todoTotal > 0 ? Math.round((todoCompleted / todoTotal) * 100) : 0 };

      const sessions = await PomodoroDao.queryByDateRange(start, end);
      const focusSessions = sessions.filter((s: PomodoroSession) => s.preset_type === 'focus');
      const totalMinutes = focusSessions.reduce((sum: number, s: PomodoroSession) => sum + (s.actual_seconds ?? s.duration_minutes * 60), 0) / 60;
      const pomodoroStats: PomodoroStats = { sessions: sessions.length, totalMinutes: Math.round(totalMinutes), focusCount: focusSessions.length };

      this.data = { checkInRate, checkedDays: checkIns.length, totalDays, moodDistribution: moodDist, todoStats, pomodoroStats };
      // M09: Write stats to AppStorage for cross-module reactive access
      AppStorage.setOrCreate('checkInRate', checkInRate);
      AppStorage.setOrCreate('moodDistribution', moodDist);
      AppStorage.setOrCreate('todoCompletionRate', todoStats.rate);
      return this.data;
    } catch (err) { hilog.error(0x0000, TAG, 'Load failed: %{public}s', (err as BusinessError).message); return { checkInRate: 0, checkedDays: 0, totalDays: totalDays, moodDistribution: [], todoStats: { total: 0, completed: 0, rate: 0 }, pomodoroStats: { sessions: 0, totalMinutes: 0, focusCount: 0 } }; }
  }

  // agentID: DEV-004 — 统计页曲线图按天聚合（打卡/日记/番茄钟/完成待办 最近 days 天逐日数值）
  /**
   * 拉取最近 days 天（含今天，升序）的四源逐日序列 + 原四卡口径 totals。
   * 查询全部走 DAO → DatabaseExecutor（就绪门闩），缺数据日补 0 对齐 dates。
   * @param days 天数窗口（7 | 30；非法值兜底 7）
   */
  async getDailySeries(days: number): Promise<DailyStatsSeries> {
    const n: number = days > 0 ? days : 7;
    // 日期轴：升序，末位=今天（DateUtils 统一 "YYYY-MM-DD"）
    const dates: string[] = [];
    for (let i = n - 1; i >= 0; i--) { dates.push(DateUtils.daysAgo(i)); }
    const checkIn: number[] = [];
    const diary: number[] = [];
    const pomodoro: number[] = [];
    const todoDone: number[] = [];
    for (let i = 0; i < n; i++) { checkIn.push(0); diary.push(0); pomodoro.push(0); todoDone.push(0); }
    const indexMap = new Map<string, number>();
    for (let i = 0; i < n; i++) { indexMap.set(dates[i], i); }
    const start: string = dates[0];
    const end: string = dates[n - 1];
    try {
      // ① 打卡：范围查询（date >= ? AND date <= ?），命中日置 1
      const checkIns: CheckIn[] = await CheckInDao.queryByDateRange(start, end);
      for (let i = 0; i < checkIns.length; i++) {
        const idx: number | undefined = indexMap.get(checkIns[i].date);
        if (idx !== undefined) { checkIn[idx] = 1; }
      }
      // ② 日记：GROUP BY date 一次出逐日篇数
      const diaryCounts: DailyCount[] = await DiaryDao.countByDateRange(start, end);
      for (let i = 0; i < diaryCounts.length; i++) {
        const idx: number | undefined = indexMap.get(diaryCounts[i].date);
        if (idx !== undefined) { diary[idx] = diaryCounts[i].count; }
      }
      // ③ 番茄钟：复用现有范围查询，口径同 load()（preset_type==='focus' 计数，不加 completed 过滤）
      const sessions: PomodoroSession[] = await PomodoroDao.queryByDateRange(start, end);
      for (let i = 0; i < sessions.length; i++) {
        if (sessions[i].preset_type === 'focus') {
          const idx: number | undefined = indexMap.get(sessions[i].date);
          if (idx !== undefined) { pomodoro[idx] = pomodoro[idx] + 1; }
        }
      }
      // ④ 完成待办：GROUP BY date（type='today' AND completed=1，口径同 load() 今日卡片）
      const todoCounts: DailyCount[] = await TodoDao.countCompletedByDateRange(start, end);
      for (let i = 0; i < todoCounts.length; i++) {
        const idx: number | undefined = indexMap.get(todoCounts[i].date);
        if (idx !== undefined) { todoDone[idx] = todoCounts[i].count; }
      }

      // ── totals：原四卡口径（load() 现算法同源） ──
      const nowDate: Date = new Date();
      const y: number = nowDate.getFullYear();
      const m: number = nowDate.getMonth() + 1;
      // 打卡天数 = 本月打卡记录数（原卡片 checkInRate 反算的真值，双取整可证恒等）
      const monthCheckIns: CheckIn[] = await CheckInDao.queryByMonth(y, m);
      const totalCheckInDays: number = monthCheckIns.length;
      // 日记总数 = 全量 COUNT（原卡片为未实现存根 0，按契约字段语义实现真值）
      const totalDiary: number = await DiaryDao.countAll();
      // 番茄钟 = 本月 focus 会话数（同 load() 的 focusCount 口径）
      const monthSessions: PomodoroSession[] = await PomodoroDao.queryByDateRange(
        DateUtils.firstDayOfMonth(y, m), DateUtils.lastDayOfMonth(y, m));
      let totalPomodoro: number = 0;
      for (let i = 0; i < monthSessions.length; i++) {
        if (monthSessions[i].preset_type === 'focus') { totalPomodoro = totalPomodoro + 1; }
      }
      // 完成待办 = 今日 'today' 型已完成数（同 load() 的 todoStats.completed 口径）
      const todayTodos: TodoItem[] = await TodoDao.queryByDateAndType(DateUtils.today(), 'today');
      let totalTodoDone: number = 0;
      for (let i = 0; i < todayTodos.length; i++) {
        if (todayTodos[i].completed === 1) { totalTodoDone = totalTodoDone + 1; }
      }

      const result: DailyStatsSeries = {
        dates: dates, checkIn: checkIn, diary: diary, pomodoro: pomodoro, todoDone: todoDone,
        totalCheckInDays: totalCheckInDays, totalDiary: totalDiary,
        totalPomodoro: totalPomodoro, totalTodoDone: totalTodoDone
      };
      return result;
    } catch (err) {
      hilog.error(0x0000, TAG, 'getDailySeries failed: %{public}s', (err as BusinessError).message);
      // 兜底：日期轴保留、数值全 0（与 load() 失败兜底同策略，UI 不崩且可渲染空曲线）
      const fallback: DailyStatsSeries = {
        dates: dates, checkIn: checkIn, diary: diary, pomodoro: pomodoro, todoDone: todoDone,
        totalCheckInDays: 0, totalDiary: 0, totalPomodoro: 0, totalTodoDone: 0
      };
      return fallback;
    }
  }

  private getDateRange(): DateRange {
    // F6: WEEK 周期 = 最近 7 天（含今天）；MONTH 周期 = 当月
    if (this.period === StatsPeriod.WEEK) {
      const weekDays: number = 7;
      const result: DateRange = { start: DateUtils.daysAgo(weekDays - 1), end: DateUtils.today(), totalDays: weekDays };
      return result;
    }
    const y = this.year; const m = String(this.month).padStart(2, '0');
    const start = `${y}-${m}-01`;
    const lastDay = new Date(y, this.month, 0).getDate();
    const end = `${y}-${m}-${String(lastDay).padStart(2, '0')}`;
    const result: DateRange = { start, end, totalDays: lastDay };
    return result;
  }

  private getTodayDate(): string {
    const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
  }
}
