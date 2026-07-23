// <!-- agentID: HUI-055 -->
// 组件：日历大卡（日记本下钻）—— 复刻原型 CalendarView（薄荷青 bento）
// 关联设计稿：UX-001_redesign_report.md §2.4 CalendarView / §1.3 圆角 / §7.5 黑白重彩
// 关联计划：PLN-003 P2-02（日历 CalendarView 复刻）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 复刻要点：RADIUS.cardLg(40) 大卡 + tokens.shadow 青染；月切换箭头 + 2026年07月(mono数字)；
//           7 列星期标头(周末红)；6×7 日格 numCard mono bold；今日青浅底+青虚线框、选中日青实心缩放 1.05；
//           日格底部双色点：日记橙 / 签到青；图例行(青签到·橙日记)。
// 令牌驱动：圆角 RADIUS、间距 SPACING、字号字重 TYPO、mono 字体族 FONT，均引用 @ohos/shared。
// 崩溃防范（PROJECT_SPEC §9）：无 getter-in-build（用普通方法）；无字段初值写 $r()；@StorageLink 判空。
// 图标合规（PROJECT_SPEC §10）：仅用 IconMapper 已验证 sys.symbol.*；无 emoji。

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-028：引入手绘正文字体助手 SKETCH_BODY=清松手写体2（年/月单位·星期标头·图例·回到今天）；年/月/日 mono 数字保留不动。
import { DateUtils, IconMapper, RADIUS, SPACING, TYPO, FONT, SKETCH_BODY } from '@ohos/shared';

/** 日记标记点（HUI-024：原青色死值 #80CBC4 改铅笔灰 #666666，随黑白手绘主题；模块级常量无 this.tokens，与签到点 tokens.primary 墨黑/白区分，深浅色下均可见） */
const DIARY_DOT_COLOR: string = '#666666';

/**
 * 日历日期格子数据
 */
interface CalendarCell {
  date: string;
  day: number;
  isCurrentMonth: boolean;
  isToday: boolean;
}

@Component
export struct CalendarView {
  @State year: number = new Date().getFullYear();
  @State month: number = new Date().getMonth() + 1;
  @State selectedDate: string = DateUtils.today();
  @State private swipeOffsetX: number = 0;
  @State private isSwiping: boolean = false;
  /** 有日记的日期（橙点） */
  @Prop diaryDates: string[] = [];
  /** 已签到的日期（青点） */
  @Prop checkinDates: string[] = [];
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  onDateSelect?: (date: string) => void;
  onMonthChange?: (year: number, month: number) => void;

  /** 星期标头（0=日、6=六 为周末，红色） */
  private readonly weekdays: string[] = ['日', '一', '二', '三', '四', '五', '六'];

  aboutToAppear(): void {
    if (this.onMonthChange) {
      this.onMonthChange(this.year, this.month);
    }
  }

  build() {
    Column() {
      // ═══════════════════════════════════════════
      // 月份导航：◀ 2026年07月(mono数字) ▶
      // ═══════════════════════════════════════════
      Row() {
        Button() {
          SymbolGlyph(IconMapper.BACK)
            .fontSize(20)
            .fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF']) // HUI-035：翻页图标→白
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C') // HUI-035：月份翻页调节钮→雾霾蓝 btnPrimary
        .onClick(() => this.navigatePrevMonth())
        .accessibilityText('上个月')
        .accessibilityLevel('yes')

        // 月份 label：数字走 mono，中文「年/月」走系统 sans
        Row() {
          Text(this.year.toString())
            .fontFamily(FONT.monoBold)
            .fontSize(TYPO.sectionTitle.size)
            .fontWeight(TYPO.sectionTitle.weight)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          Text('年')
            .fontSize(TYPO.body.size)
            .fontWeight(TYPO.body.weight)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .margin({ left: 1, right: 3 })
            .attributeModifier(SKETCH_BODY) // HUI-028：单位「年」→清松手写体2（数字保留 mono）
          Text(this.monthPad())
            .fontFamily(FONT.monoBold)
            .fontSize(TYPO.sectionTitle.size)
            .fontWeight(TYPO.sectionTitle.weight)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          Text('月')
            .fontSize(TYPO.body.size)
            .fontWeight(TYPO.body.weight)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .margin({ left: 1 })
            .attributeModifier(SKETCH_BODY) // HUI-028：单位「月」→清松手写体2（数字保留 mono）
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)

        Button() {
          SymbolGlyph(IconMapper.FORWARD)
            .fontSize(20)
            .fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF']) // HUI-035：翻页图标→白
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C') // HUI-035：月份翻页调节钮→雾霾蓝 btnPrimary
        .onClick(() => this.navigateNextMonth())
        .accessibilityText('下个月')
        .accessibilityLevel('yes')
      }
      .width('100%')
      .margin({ bottom: SPACING.cardPadSm })

      // ═══════════════════════════════════════════
      // 星期标头（周末红）
      // ═══════════════════════════════════════════
      Row() {
        ForEach(this.weekdays, (day: string, index: number) => {
          Text(day)
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(TYPO.cardTitle.weight)
            .fontColor(this.getWeekdayColor(index))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .height(28)
            .attributeModifier(SKETCH_BODY) // HUI-028：星期标头→清松手写体2
        })
      }
      .width('100%')

      // ═══════════════════════════════════════════
      // 6×7 日历网格（左右滑动切换月）
      // ═══════════════════════════════════════════
      Column() {
        Grid() {
          ForEach(this.getCurrentGrid(), (cell: CalendarCell) => {
            GridItem() {
              Column() {
                // 日数字：numCard mono 900（黑白重彩数据感）— monoExtraBold(800) 为实际注册最重级
                Text(cell.day.toString())
                  .fontFamily(FONT.monoExtraBold)
                  .fontSize(TYPO.numCard.size)
                  .fontWeight(TYPO.numCard.weight)
                  .fontColor(this.getCellTextColor(cell.isCurrentMonth, cell.isToday, cell.date))
                  .maxLines(1)

                // 底部双色点：日记橙 / 签到青（选中态转白）
                Row() {
                  if (this.hasDiary(cell.date) && cell.isCurrentMonth) {
                    Circle({ width: 5, height: 5 })
                      .fill(cell.date === this.selectedDate
                        ? Color.White
                        : DIARY_DOT_COLOR)
                  }
                  if (this.hasCheckin(cell.date) && cell.isCurrentMonth) {
                    Circle({ width: 5, height: 5 })
                      .fill(cell.date === this.selectedDate
                        ? Color.White
                        : (this.tokens ? this.tokens.primary : '#00C2B8'))
                      .margin({ left: 3 })
                  }
                }
                .height(7)
                .margin({ top: 2 })
                .justifyContent(FlexAlign.Center)
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .borderRadius(RADIUS.item)
              .backgroundColor(this.getCellBgColor(cell.isCurrentMonth, cell.isToday, cell.date))
              .border(this.isTodayRing(cell.isCurrentMonth, cell.isToday, cell.date)
                ? { width: 2, color: this.tokens ? this.tokens.btnAux : '#C6BBAE', style: BorderStyle.Dashed }
                : { width: 0 })
              .scale(cell.date === this.selectedDate && cell.isCurrentMonth
                ? { x: 1.05, y: 1.05 }
                : { x: 1, y: 1 })
              .onClick(() => {
                if (cell.isCurrentMonth) {
                  this.selectedDate = cell.date;
                  if (this.onDateSelect) {
                    this.onDateSelect(cell.date);
                  }
                }
              })
              .accessibilityText(cell.isCurrentMonth
                ? (cell.isToday ? '今天 ' : '') + this.month + '月' + cell.day + '日' +
                  (this.hasDiary(cell.date) ? ' 有日记' : '') +
                  (this.hasCheckin(cell.date) ? ' 已签到' : '') +
                  (cell.date === this.selectedDate ? ' 已选中' : '')
                : '其他月份')
              .animation({ duration: 200, curve: Curve.EaseInOut })
            }
            .height(46)
          })
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
        .rowsGap(4)
        .columnsGap(4)
        .width('100%')
        .height(300)
        .padding({ top: 6, bottom: 6 })
        .offset({ x: this.isSwiping ? this.swipeOffsetX : 0, y: 0 })
        .opacity(this.isSwiping ? 0.85 : 1.0)
      }
      .width('100%')
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 10 })
          .onActionStart(() => {
            this.isSwiping = true;
            this.swipeOffsetX = 0;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.swipeOffsetX = event.offsetX;
          })
          .onActionEnd((event: GestureEvent) => {
            this.isSwiping = false;
            this.swipeOffsetX = 0;
            if (event.offsetX > 60) {
              this.navigatePrevMonth();
            } else if (event.offsetX < -60) {
              this.navigateNextMonth();
            }
          })
          .onActionCancel(() => {
            this.isSwiping = false;
            this.swipeOffsetX = 0;
          })
      )

      // ═══════════════════════════════════════════
      // 图例行（青签到 · 橙日记）+ 回到今天
      // ═══════════════════════════════════════════
      Row() {
        Row() {
          Circle({ width: 7, height: 7 })
            .fill(this.tokens ? this.tokens.primary : '#00C2B8')
          Text('签到')
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(TYPO.eyebrow.weight)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .margin({ left: 6 })
            .attributeModifier(SKETCH_BODY) // HUI-028：图例标签→清松手写体2
        }
        .margin({ right: 18 })

        Row() {
          Circle({ width: 7, height: 7 })
            .fill(DIARY_DOT_COLOR)
          Text('日记')
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(TYPO.eyebrow.weight)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .margin({ left: 6 })
            .attributeModifier(SKETCH_BODY) // HUI-028：图例标签→清松手写体2
        }

        Blank()

        // 「回到今天」—— 保留原有便捷功能，仅在离开今天时显示
        if (this.selectedDate !== DateUtils.today()) {
          Text('回到今天')
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(TYPO.cardTitle.weight)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A') // HUI-035：辅助 pill 文字→深字（燕麦底上）
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(999)
            .backgroundColor(this.tokens ? this.tokens.btnAux : '#C6BBAE') // HUI-035：回到今天辅助 pill→燕麦 btnAux
            .onClick(() => this.goToToday())
            .accessibilityText('回到今天')
            .accessibilityLevel('yes')
            .attributeModifier(SKETCH_BODY) // HUI-028：便捷动作字→清松手写体2
        }
      }
      .width('100%')
      .margin({ top: SPACING.cardPadSm })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({
      left: SPACING.cardPadSm,
      right: SPACING.cardPadSm,
      top: SPACING.cardPadLg,
      bottom: SPACING.cardPadMd
    })
    .borderRadius(RADIUS.cardLg)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .shadow({
      radius: 24,
      color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
      offsetX: 0,
      offsetY: 8
    })
  }

  /**
   * 获取当前月份日历网格数据（6×7=42 格）
   */
  private getCurrentGrid(): CalendarCell[] {
    return DateUtils.getCalendarGrid(this.year, this.month);
  }

  /**
   * 月份两位补零字符串（供 mono 渲染）
   */
  private monthPad(): string {
    return this.month < 10 ? '0' + this.month : this.month.toString();
  }

  /**
   * 星期标头颜色：周末（日/六）红，其余次要灰
   */
  private getWeekdayColor(index: number): ResourceColor {
    if (index === 0 || index === 6) {
      return this.tokens ? this.tokens.danger : '#78909C';
    }
    return this.tokens ? this.tokens.textSecondary : '#5A5A5A';
  }

  /**
   * 计算日期格子的文字颜色
   */
  private getCellTextColor(isCurrentMonth: boolean, isToday: boolean, date: string): ResourceColor {
    if (date === this.selectedDate && isCurrentMonth) {
      return Color.White;
    }
    if (!isCurrentMonth) {
      return this.tokens ? this.tokens.textTertiary : '#CCCCCC';
    }
    if (isToday) {
      return this.tokens ? this.tokens.primary : '#00C2B8';
    }
    return this.tokens ? this.tokens.textPrimary : '#1A1A1A';
  }

  /**
   * 计算日期格子的背景色：选中日青实心；今日青浅底；其余透明
   */
  private getCellBgColor(isCurrentMonth: boolean, isToday: boolean, date: string): ResourceColor {
    if (date === this.selectedDate && isCurrentMonth) {
      return this.tokens ? this.tokens.btnPrimary : '#738A9C'; // HUI-035：选中日→雾霾蓝 btnPrimary（白字）
    }
    if (isToday && isCurrentMonth) {
      return this.tokens ? this.tokens.btnAux : '#C6BBAE'; // HUI-035：今日底→燕麦 btnAux
    }
    return Color.Transparent;
  }

  /**
   * 是否给今日格子加青色虚线框（今日且非选中态）
   */
  private isTodayRing(isCurrentMonth: boolean, isToday: boolean, date: string): boolean {
    return isToday && isCurrentMonth && date !== this.selectedDate;
  }

  /**
   * 判断某日期是否有日记
   */
  private hasDiary(date: string): boolean {
    return this.diaryDates.indexOf(date) >= 0;
  }

  /**
   * 判断某日期是否已签到
   */
  private hasCheckin(date: string): boolean {
    return this.checkinDates.indexOf(date) >= 0;
  }

  /**
   * 导航到上个月
   */
  private navigatePrevMonth(): void {
    const prev = DateUtils.prevMonth(this.year, this.month);
    this.year = prev.year;
    this.month = prev.month;
    if (this.onMonthChange) {
      this.onMonthChange(this.year, this.month);
    }
  }

  /**
   * 导航到下个月
   */
  private navigateNextMonth(): void {
    const next = DateUtils.nextMonth(this.year, this.month);
    this.year = next.year;
    this.month = next.month;
    if (this.onMonthChange) {
      this.onMonthChange(this.year, this.month);
    }
  }

  /**
   * 回到今天
   */
  private goToToday(): void {
    this.selectedDate = DateUtils.today();
    const today = new Date();
    this.year = today.getFullYear();
    this.month = today.getMonth() + 1;
    if (this.onDateSelect) {
      this.onDateSelect(this.selectedDate);
    }
  }
}
