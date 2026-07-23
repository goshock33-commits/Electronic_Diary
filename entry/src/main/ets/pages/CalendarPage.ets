// <!-- agentID: HUI-055 -->
// 页面：日历页壳（eyebrow「DIARY LOG BOOK」+ H1「日记时光」+ 累计篇数药丸 + 日历大卡 + 选中日查看器）
// 关联设计稿：UX-001_redesign_report.md §2.4 CalendarView（日记本下钻）
// 关联计划：PLN-003 P2-02（日历 CalendarView 复刻）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 复刻要点：eyebrow+H1+mono 篇数药丸；日历大卡（40vp 圆角青染阴影）；选中日记显示 DiaryCard mood 查看器；
//           无日记则虚线空态「border-2 dashed #E0E0E0」+ 写日记 CTA。
// 令牌驱动：RADIUS / SPACING / TYPO / FONT 全引用；颜色 tokens 判空兜底。
// 崩溃防范（PROJECT_SPEC §9）：@StorageLink 全判空；无 getter-in-build；无字段初值写 $r()。
// 图标合规（PROJECT_SPEC §10）：仅用 IconMapper 已验证；无 emoji。

import type { ThemeColorTokens, Diary } from '@ohos/shared';
// HUI-028：引入手绘字体助手——SKETCH_TITLE=猫啃(eyebrow/H1)，SKETCH_BODY=清松(单位/标签/正文)；mono 篇数/日期保留不动。
import { DateUtils, IconMapper, RADIUS, SPACING, TYPO, FONT, SKETCH_TITLE, SKETCH_BODY, reportPawTouch, PawOverlayLayer } from '@ohos/shared';
import { CalendarView, DiaryCard, DiaryViewModel, type DiaryCardData } from 'features/diary';
import { CheckInViewModel } from 'features/checkin';
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';

/**
 * 日记摘要数据（Mock 用）
 */
interface DiarySummary {
  date: string;
  content: string;
  checkedIn: boolean;
  mood: string;
}

@Entry
@Component
export struct CalendarPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  @State currentYear: number = 2026;
  @State currentMonth: number = 7;
  @State selectedDate: string = DateUtils.today();
  // T106（审判 G2 修正）：diaryDates 仅「有日记」的日期、checkinDates 仅「已打卡」的日期，两类分开标记、互不混淆。
  // 初始置空 → 挂载/切月经 CalendarView.onMonthChange 异步拉取后回填（R1：@State 才触发刷新）。
  @State diaryDates: string[] = [];
  @State checkinDates: string[] = [];
  @State showDetailPreview: boolean = false;

  /** Mock 日记数据：3 篇完整日记 */
  private mockDiaries: Record<string, DiarySummary> = {
    '2026-07-03': {
      date: '2026-07-03',
      content: '今天开始学习鸿蒙应用开发，了解了ArkTS声明式开发范式和组件化架构。感觉很有意思，状态管理和声明式UI的结合让开发效率非常高。',
      checkedIn: true,
      mood: 'happy'
    },
    '2026-07-08': {
      date: '2026-07-08',
      content: '完成了电子日记本的核心功能设计。确定了五个分区结构、打卡签到系统、待办管理和日记写作功能。用户访谈反馈很积极。',
      checkedIn: true,
      mood: 'star'
    },
    '2026-07-15': {
      date: '2026-07-15',
      content: '今天整理了本周的待办事项，完成了所有计划的任务。重新规划了分区布局，让每天记录更有效率。',
      checkedIn: false,
      mood: 'cloudy'
    }
  };

  aboutToAppear(): void {
    this.currentYear = 2026;
    this.currentMonth = 7;
    // restore selected date viewer state from today
    if (this.diaryDates.indexOf(this.selectedDate) >= 0) {
      this.showDetailPreview = true;
    } else {
      this.showDetailPreview = false;
    }
  }

  /**
   * T106：拉取当月「有日记」「已打卡」两类日期，分别回填标记 @State。
   * - diaryDates：DiaryViewModel.queryByMonth(y,m).map(d=>d.date)（仅日记；不用会把打卡也并进来的
   *   getDatesWithDiary() 合并集，避免纯打卡日被误标为有日记 —— 审判 G2 / PLN R12）。
   * - checkinDates：CheckInViewModel.queryByMonth(y,m)（DEV-006 新补，直接返回该月打卡日期 string[]）。
   * 触发时机：由 CalendarView.onMonthChange 驱动——其子组件 aboutToAppear 挂载即回调一次（首屏加载），
   *   之后每次上/下月、回到今天再回调（切月重拉）。
   */
  private async loadMonthMarks(year: number, month: number): Promise<void> {
    try {
      const diaryVm: DiaryViewModel = new DiaryViewModel();
      const checkInVm: CheckInViewModel = new CheckInViewModel();
      const diaries: Diary[] = await diaryVm.queryByMonth(year, month);
      const diaryDateList: string[] = diaries.map((d: Diary): string => d.date);
      const checkinDateList: string[] = await checkInVm.queryByMonth(year, month);
      this.diaryDates = diaryDateList;
      this.checkinDates = checkinDateList;
    } catch (err) {
      // 错误兜底：清空标记而非崩溃（PLN §5 红线④ async try/catch 空态）
      this.diaryDates = [];
      this.checkinDates = [];
    }
  }

  build() {
    // HUI-001: 最小外包 Stack——原根 Column 原样保留，仅为叠加同树猫爪视觉层
    Stack({ alignContent: Alignment.TopStart }) {
    Column() {
      Scroll() {
        Column() {
          // ═══════════════════════════════════════════
          // 页头：eyebrow「DIARY LOG BOOK」+ H1「日记时光」+ 累计篇数药丸(mono 数字)
          // ═══════════════════════════════════════════
          Row() {
            Column() {
              Text('DIARY LOG BOOK')
                .fontSize(10)
                .fontWeight(TYPO.cardTitle.weight)
                .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                .opacity(0.6)
                .letterSpacing(3)
                .attributeModifier(SKETCH_TITLE) // HUI-028：eyebrow 微标→猫啃什锦黑
              Text('日记时光')
                .fontSize(TYPO.h1.size)
                .fontWeight(TYPO.h1.weight)
                .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                .margin({ top: 2 })
                .attributeModifier(SKETCH_TITLE) // HUI-028：页面 H1→猫啃什锦黑
            }
            .alignItems(HorizontalAlign.Start)

            Blank()

            // 累计篇数药丸：mono 数字 + 中文
            Row() {
              Text(this.diaryDates.length.toString())
                .fontFamily(FONT.monoExtraBold)
                .fontSize(TYPO.numCard.size)
                .fontWeight(TYPO.numCard.weight)
                .fontColor(this.tokens ? this.tokens.primary : '#00C2B8')
                .margin({ right: 4 })
              Text('篇')
                .fontSize(TYPO.body.size)
                .fontWeight(TYPO.cardTitle.weight)
                .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                .attributeModifier(SKETCH_BODY) // HUI-028：单位标签→清松手写体2（数字保留 mono）
            }
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .borderRadius(999)
            .backgroundColor(this.tokens ? this.tokens.accent : '#E6F9F8')
          }
          .width('100%')
          .padding({ left: SPACING.pageH, right: SPACING.pageH, top: 6, bottom: SPACING.cardPadSm })

          // ═══════════════════════════════════════════
          // 日历大卡
          // ═══════════════════════════════════════════
          CalendarView({
            diaryDates: this.diaryDates,
            checkinDates: this.checkinDates,
            onDateSelect: (date: string) => {
              this.selectedDate = date;
              if (this.diaryDates.indexOf(date) >= 0) {
                this.showDetailPreview = true;
              } else {
                this.showDetailPreview = false;
              }
            },
            onMonthChange: (year: number, month: number) => {
              this.currentYear = year;
              this.currentMonth = month;
              this.loadMonthMarks(year, month);
            }
          })
            .margin({ left: SPACING.pageH, right: SPACING.pageH })

          // ═══════════════════════════════════════════
          // 选中日查看器
          // ═══════════════════════════════════════════
          if (this.showDetailPreview && this.mockDiaries[this.selectedDate]) {
            // 有日记：展示 DiaryCard 查看器
            this.buildDiaryViewer(this.mockDiaries[this.selectedDate])
          } else if (this.selectedDate && !this.showDetailPreview) {
            // 无日记：虚线空态
            this.buildEmptyViewer()
          }

          // ═══════════════════════════════════════════
          // 底部分隔 + 安全区
          // ═══════════════════════════════════════════
          Blank()
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens ? this.tokens.bg : '#FAF8F5')
    // HUI-001: 猫爪特效触摸捕获（页面树内监听 Down，不消费；视觉层在外包 Stack 顶层）
    .onTouch((event: TouchEvent) => reportPawTouch(event))

    // HUI-001: 猫爪视觉层（同树最上层子节点，整层 None 不参与命中，不挡交互）
    PawOverlayLayer()
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 选中日有日记时的查看器（DiaryCard）
   */
  @Builder
  buildDiaryViewer(summary: DiarySummary) {
    Column() {
      // 选中的日期简短提示
      Row() {
        Text(DateUtils.formatDateCN(summary.date))
          .fontFamily(FONT.monoBold)
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
        Text(' · 日记详情')
          .fontSize(TYPO.eyebrow.size)
          .fontWeight(TYPO.eyebrow.weight)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
          .margin({ left: 4 })
          .attributeModifier(SKETCH_BODY) // HUI-028：说明标签→清松手写体2
        Blank()
        Button() {
          Text('写新日记')
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(TYPO.cardTitle.weight)
            // HUI-034：描边辅助按钮文字套 btnAux 燕麦
            .fontColor(this.tokens ? this.tokens.btnAux : '#C6BBAE')
            .attributeModifier(SKETCH_BODY) // HUI-028：动作字→清松手写体2
        }
        .backgroundColor(Color.Transparent)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        // HUI-034：描边辅助按钮边框套 btnAux 燕麦
        .border({ width: 1, color: this.tokens ? this.tokens.btnAux : '#C6BBAE', style: BorderStyle.Solid })
        .borderRadius(RADIUS.input)
        .onClick(() => this.openDiaryEdit())
        .accessibilityText('写新日记')
        .accessibilityLevel('yes')
      }
      .width('100%')
      .padding({ left: SPACING.pageH, right: SPACING.pageH, bottom: SPACING.cardGap })
      .margin({ top: SPACING.cardGap })

      DiaryCard({
        diary: {
          id: 0,
          date: summary.date,
          content: summary.content,
          imageCount: 0,
          isCheckedIn: summary.checkedIn,
          mood: summary.mood
        },
        onCardClick: (_d: DiaryCardData) => {
          router.pushUrl({
            url: 'pages/DiaryDetailPage',
            params: { date: summary.date }
          }).catch(() => {
            promptAction.showToast({ message: 'Mock: 打开日记详情', duration: 1500 });
          });
        }
      })
        .margin({ left: SPACING.pageH, right: SPACING.pageH })
    }
  }

  /**
   * 选中日无日记时的虚线空态
   */
  @Builder
  buildEmptyViewer() {
    Column() {
      // 日期标签
      Text(DateUtils.formatDateCN(this.selectedDate))
        .fontFamily(FONT.monoBold)
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(TYPO.cardTitle.weight)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
        .margin({ bottom: SPACING.cardGap })

      // 虚线空态卡
      Column() {
        SymbolGlyph(IconMapper.BOOKMARK)
          .fontSize(36)
          .fontColor([this.tokens ? this.tokens.accent : '#E6F9F8'])

        Text('这一天还没有日记')
          .fontSize(TYPO.body.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
          .margin({ top: 12, bottom: 6 })
          .attributeModifier(SKETCH_BODY) // HUI-028：空态标题→清松手写体2

        Text('记录今日的温暖时光，让回忆有迹可循')
          .fontSize(TYPO.eyebrow.size)
          .fontWeight(TYPO.eyebrow.weight)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#E0E0E0')
          .margin({ bottom: 18 })
          .attributeModifier(SKETCH_BODY) // HUI-028：空态说明→清松手写体2

        Button('写日记')
          .fontSize(TYPO.body.size)
          .fontWeight(TYPO.cardTitle.weight)
          // HUI-034：主按钮套 btnPrimaryText 白字 + btnPrimary 雾霾蓝底
          .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
          .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
          .borderRadius(999)
          .height(44)
          .padding({ left: 32, right: 32 })
          .shadow({
            radius: 12,
            color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.30)', // HUI-024: then 分支原为青色死值（两支同值恒青），改读 tokens.shadow 随黑白手绘主题+深浅适配
            offsetX: 0,
            offsetY: 4
          })
          .onClick(() => this.openDiaryEdit())
          .accessibilityText('写日记')
          .accessibilityLevel('yes')
      }
      .width('100%')
      .padding({ top: 32, bottom: 32 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .border({ width: 2, color: '#E0E0E0', style: BorderStyle.Dashed })
      .borderRadius(RADIUS.cardMd)
      .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    }
    .width('100%')
    .padding({ left: SPACING.pageH, right: SPACING.pageH })
    .margin({ top: SPACING.cardGap })
  }

  /**
   * 打开写日记页
   */
  private openDiaryEdit(): void {
    router.pushUrl({
      url: 'pages/DiaryEditPage',
      params: { date: this.selectedDate }
    }).catch(() => {
      promptAction.showToast({ message: 'Mock: 打开日记写作页', duration: 1500 });
    });
  }
}
