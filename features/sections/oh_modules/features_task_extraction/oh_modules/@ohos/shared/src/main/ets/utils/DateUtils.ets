// <!-- agentID: HUI-001 -->
// 模块：日期格式化工具类
// 关联设计稿：需求 6.1 日历视图 / 打卡签到 / 待办管理
// 关联任务：T007a-c（HUI 部分）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 国际化：使用 Intl API，预留 i18n 扩展能力

/**
 * 日期格式化工具类
 *
 * 提供日期格式化、区间计算、星期推算、跨月跨年边界处理。
 * 所有日期输入输出统一使用 ISO 格式 "YYYY-MM-DD"。
 */

interface DateParts {
  year: number;
  month: number;
  day: number;
}

interface CalendarDayInfo {
  day: number;
  date: string;
  isToday: boolean;
  isCurrentMonth: boolean;
  hasCheckIn: boolean;
  hasDiary: boolean;
  hasTodo: boolean;
}

interface DateRange {
  start: string;
  end: string;
}

interface WeekRange {
  start: string;
  end: string;
  weekNumber: number;
}

interface MonthInfo {
  year: number;
  month: number;
  days: number;
  firstDayOfWeek: number;
}

interface GridDayInfo {
  date: string;
  day: number;
  isCurrentMonth: boolean;
  isToday: boolean;
}

interface YearMonth {
  year: number;
  month: number;
}

export class DateUtils {

  // ════════════════════════════════════════════════════════
  // 日期格式化
  // ════════════════════════════════════════════════════════

  /** 标准日期格式 YYYY-MM-DD */
  static readonly FORMAT_DATE: string = 'YYYY-MM-DD';

  /** 中文日期格式 YYYY年MM月DD日 */
  static readonly FORMAT_DATE_CN: string = 'YYYY年MM月DD日';

  /** 月份格式 YYYY年MM月 */
  static readonly FORMAT_MONTH_CN: string = 'YYYY年MM月';

  /**
   * 获取今天的日期字符串 YYYY-MM-DD
   */
  static today(): string {
    return DateUtils.formatDate(new Date());
  }

  /**
   * 格式化 Date 为 YYYY-MM-DD 字符串
   * @param date Date 对象
   * @returns 格式化的日期字符串
   */
  static formatDate(date: Date): string {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  /**
   * 格式化 Date 为中文日期字符串 YYYY年MM月DD日
   * @param dateStr ISO日期字符串 YYYY-MM-DD
   * @returns 中文日期字符串
   */
  static formatDateCN(dateStr: string): string {
    const parts = dateStr.split('-');
    if (parts.length !== 3) {
      return dateStr;
    }
    return `${parts[0]}年${parts[1]}月${parts[2]}日`;
  }

  /**
   * 格式化 Date 为中文月份字符串 YYYY年MM月
   * @param year 年
   * @param month 月 (1-12)
   * @returns 中文月份字符串
   */
  static formatMonthCN(year: number, month: number): string {
    return `${year}年${String(month).padStart(2, '0')}月`;
  }

  /**
   * 格式化为展示用短日期 MM月DD日
   * @param dateStr ISO日期字符串 YYYY-MM-DD
   * @returns 短日期字符串
   */
  static formatShortCN(dateStr: string): string {
    const parts = dateStr.split('-');
    if (parts.length !== 3) {
      return dateStr;
    }
    return `${parseInt(parts[1])}月${parseInt(parts[2])}日`;
  }

  /**
   * 格式化为时间字符串 HH:mm
   * @param date Date 对象
   * @returns 时间字符串
   */
  static formatTime(date: Date): string {
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    return `${hours}:${minutes}`;
  }

  // ════════════════════════════════════════════════════════
  // 日期解析
  // ════════════════════════════════════════════════════════

  /**
   * 解析 YYYY-MM-DD 字符串为 Date 对象
   * @param dateStr ISO日期字符串
   * @returns Date 对象，解析失败返回当前日期
   */
  static parseDate(dateStr: string): Date {
    const d = new Date(dateStr + 'T00:00:00');
    if (isNaN(d.getTime())) {
      return new Date();
    }
    return d;
  }

  /**
   * 获取日期字符串的年/月/日分量
   * @param dateStr ISO日期字符串 YYYY-MM-DD
   * @returns { year, month, day }
   */
  static parseDateParts(dateStr: string): DateParts {
    const parts = dateStr.split('-');
    if (parts.length === 3) {
      return {
        year: parseInt(parts[0]),
        month: parseInt(parts[1]),
        day: parseInt(parts[2])
      };
    }
    const today = new Date();
    return {
      year: today.getFullYear(),
      month: today.getMonth() + 1,
      day: today.getDate()
    };
  }

  // ════════════════════════════════════════════════════════
  // 日期计算
  // ════════════════════════════════════════════════════════

  /**
   * 计算 N 天前的日期
   * @param days 天数偏移（负数为未来）
   * @param fromDate 基准日期，默认为今天
   * @returns YYYY-MM-DD 格式日期字符串
   */
  static daysAgo(days: number, fromDate?: string): string {
    const base = fromDate ? DateUtils.parseDate(fromDate) : new Date();
    base.setDate(base.getDate() - days);
    return DateUtils.formatDate(base);
  }

  /**
   * 计算 N 天后的日期
   * @param days 天数偏移
   * @param fromDate 基准日期，默认为今天
   * @returns YYYY-MM-DD 格式日期字符串
   */
  static daysFromNow(days: number, fromDate?: string): string {
    return DateUtils.daysAgo(-days, fromDate);
  }

  /**
   * 获取某月的第一天
   * @param year 年
   * @param month 月 (1-12)
   * @returns YYYY-MM-DD 格式日期字符串
   */
  static firstDayOfMonth(year: number, month: number): string {
    return `${year}-${String(month).padStart(2, '0')}-01`;
  }

  /**
   * 获取某月的最后一天
   * @param year 年
   * @param month 月 (1-12)
   * @returns YYYY-MM-DD 格式日期字符串
   */
  static lastDayOfMonth(year: number, month: number): string {
    const lastDay = new Date(year, month, 0).getDate();
    return `${year}-${String(month).padStart(2, '0')}-${String(lastDay).padStart(2, '0')}`;
  }

  /**
   * 获取某月的天数
   * @param year 年
   * @param month 月 (1-12)
   * @returns 该月天数
   */
  static daysInMonth(year: number, month: number): number {
    return new Date(year, month, 0).getDate();
  }

  /**
   * 计算两个日期之间的天数差
   * @param dateStr1 日期1 YYYY-MM-DD
   * @param dateStr2 日期2 YYYY-MM-DD
   * @returns 天数差（dateStr2 - dateStr1，可能为负）
   */
  static daysBetween(dateStr1: string, dateStr2: string): number {
    const d1 = DateUtils.parseDate(dateStr1);
    const d2 = DateUtils.parseDate(dateStr2);
    const diffMs = d2.getTime() - d1.getTime();
    return Math.floor(diffMs / (1000 * 60 * 60 * 24));
  }

  // ════════════════════════════════════════════════════════
  // 星期推算
  // ════════════════════════════════════════════════════════

  /** 中文星期名称（周日-周六） */
  static readonly WEEKDAY_NAMES: string[] = ['日', '一', '二', '三', '四', '五', '六'];

  /** 完整中文星期名称 */
  static readonly WEEKDAY_NAMES_FULL: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

  /**
   * 获取某日期是星期几（0=周日, 1=周一, ..., 6=周六）
   * @param dateStr ISO日期字符串 YYYY-MM-DD
   * @returns 星期数字 (0-6)
   */
  static getWeekday(dateStr: string): number {
    return DateUtils.parseDate(dateStr).getDay();
  }

  /**
   * 获取某日期是星期几的中文名称
   * @param dateStr ISO日期字符串 YYYY-MM-DD
   * @returns 星期中文名称
   */
  static getWeekdayName(dateStr: string): string {
    const wd = DateUtils.getWeekday(dateStr);
    return DateUtils.WEEKDAY_NAMES_FULL[wd];
  }

  /**
   * 获取某月第一天是星期几（0=周日）
   * @param year 年
   * @param month 月 (1-12)
   * @returns 星期数字 (0-6)
   */
  static firstWeekdayOfMonth(year: number, month: number): number {
    return new Date(year, month - 1, 1).getDay();
  }

  // ════════════════════════════════════════════════════════
  // 日历视图工具（月视图网格 33-42 格标准日历布局）
  // ════════════════════════════════════════════════════════

  /**
   * 获取月视图日历网格数据
   * 返回 35 (5行x7列) 或 42 (6行x7列) 个日期条目
   *
   * @param year 年
   * @param month 月 (1-12)
   * @returns 日历格子数组
   */
  static getCalendarGrid(year: number, month: number): GridDayInfo[] {
    const today = DateUtils.today();
    const firstDay = DateUtils.firstWeekdayOfMonth(year, month);
    const totalDays = DateUtils.daysInMonth(year, month);
    const grid: GridDayInfo[] = [];

    // 上月补位
    const prevMonth = month === 1 ? 12 : month - 1;
    const prevYear = month === 1 ? year - 1 : year;
    const prevMonthDays = DateUtils.daysInMonth(prevYear, prevMonth);

    // 起始周日：上月末几天
    // 如果 firstDay 是周日(0)，则不需要上月补位
    // 如果 firstDay 是周一(1)，则需要 1 个上月格子
    for (let i = firstDay - 1; i >= 0; i--) {
      const day = prevMonthDays - i;
      const date = `${prevYear}-${String(prevMonth).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
      grid.push({
        date: date,
        day: day,
        isCurrentMonth: false,
        isToday: date === today
      });
    }

    // 当月所有日期
    for (let d = 1; d <= totalDays; d++) {
      const date = `${year}-${String(month).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
      grid.push({
        date: date,
        day: d,
        isCurrentMonth: true,
        isToday: date === today
      });
    }

    // 下月补位（补齐到 42 格 = 6 行 x 7 列）
    const nextMonth = month === 12 ? 1 : month + 1;
    const nextYear = month === 12 ? year + 1 : year;
    let nextDay = 1;
    while (grid.length < 42) {
      const date = `${nextYear}-${String(nextMonth).padStart(2, '0')}-${String(nextDay).padStart(2, '0')}`;
      grid.push({
        date: date,
        day: nextDay,
        isCurrentMonth: false,
        isToday: date === today
      });
      nextDay++;
    }

    return grid;
  }

  // ════════════════════════════════════════════════════════
  // 跨月/跨年导航
  // ════════════════════════════════════════════════════════

  /**
   * 获取上个月的年月
   * @param year 当前年
   * @param month 当前月 (1-12)
   * @returns { year, month }
   */
  static prevMonth(year: number, month: number): YearMonth {
    if (month === 1) {
      return { year: year - 1, month: 12 };
    }
    return { year: year, month: month - 1 };
  }

  /**
   * 获取下个月的年月
   * @param year 当前年
   * @param month 当前月 (1-12)
   * @returns { year, month }
   */
  static nextMonth(year: number, month: number): YearMonth {
    if (month === 12) {
      return { year: year + 1, month: 1 };
    }
    return { year: year, month: month + 1 };
  }

  // ════════════════════════════════════════════════════════
  // 打卡连续天数工具
  // ════════════════════════════════════════════════════════

  /**
   * 判断 twoDates 是否连续（twoDates=基准日期的前一天）
   * @param dateStr 当前日期 YYYY-MM-DD
   * @param prevDateStr 上一个日期 YYYY-MM-DD
   * @returns 是否连续
   */
  static isConsecutiveDay(dateStr: string, prevDateStr: string): boolean {
    const diff = DateUtils.daysBetween(prevDateStr, dateStr);
    return diff === 1;
  }

  /**
   * 判断是否为今天
   * @param dateStr ISO日期字符串 YYYY-MM-DD
   * @returns 是否为今天
   */
  static isToday(dateStr: string): boolean {
    return dateStr === DateUtils.today();
  }

  /**
   * 判断日期是否在指定区间内
   * @param dateStr 要检查的日期
   * @param startStr 区间开始日期 YYYY-MM-DD
   * @param endStr 区间结束日期 YYYY-MM-DD
   * @returns 是否在区间内（含边界）
   */
  static isInRange(dateStr: string, startStr: string, endStr: string): boolean {
    return dateStr >= startStr && dateStr <= endStr;
  }

  // ════════════════════════════════════════════════════════
  // 时间戳工具
  // ════════════════════════════════════════════════════════

  /**
   * 获取当前毫秒级时间戳
   * @returns Unix 时间戳（毫秒）
   */
  static nowTimestamp(): number {
    return Date.now();
  }

  /**
   * 时间戳转日期字符串
   * @param timestamp Unix 时间戳（毫秒）
   * @returns YYYY-MM-DD 格式日期字符串
   */
  static timestampToDate(timestamp: number): string {
    return DateUtils.formatDate(new Date(timestamp));
  }

  /**
   * 日期字符串转时间戳（当天 00:00:00 对应的毫秒值）
   * @param dateStr ISO日期字符串 YYYY-MM-DD
   * @returns Unix 时间戳（毫秒）
   */
  static dateToTimestamp(dateStr: string): number {
    return DateUtils.parseDate(dateStr).getTime();
  }
}
