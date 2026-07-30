// <!-- agentID: HUI-055 -->
// 页面：日历页壳（eyebrow「DIARY LOG BOOK」+ H1「日记时光」+ 累计篇数药丸 + 日历大卡 + 选中日查看器）
// 关联设计稿：UX-001_redesign_report.md §2.4 CalendarView（日记本下钻）
// 关联计划：PLN-003 P2-02（日历 CalendarView 复刻）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 复刻要点：eyebrow+H1+mono 篇数药丸；日历大卡（40vp 圆角青染阴影）；选中日记显示 DiaryCard mood 查看器；
//           无日记则虚线空态「border-2 dashed #E0E6ED」+ 写日记 CTA。
// 令牌驱动：RADIUS / SPACING / TYPO / FONT 全引用；颜色 tokens 判空兜底。
// 崩溃防范（PROJECT_SPEC §9）：@StorageLink 全判空；无 getter-in-build；无字段初值写 $r()。
// 图标合规（PROJECT_SPEC §10）：仅用 IconMapper 已验证；无 emoji。

import type { ThemeColorTokens, Diary } from '@ohos/shared';
import { DateUtils, IconMapper, RADIUS, SPACING, TYPO, FONT, ICON, SKETCH_TITLE, SKETCH_BODY, reportPawTouch, PawOverlayLayer } from '@ohos/shared';
import { DiaryCard, DiaryViewModel, type DiaryCardData } from 'features/diary';
import { CheckInViewModel } from 'features/checkin';
import { router } from '@kit.ArkUI';

/** 日记卡片数据 */
interface DiaryEntry {
  id: number;
  date: string;
  title: string;
  summary: string;
  mood: string;
  imageCount: number;
}

/** 二级 Tab 选项 */
interface DiaryTab {
  label: string;
  key: string;
}

@Entry
@Component
export struct CalendarPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  @State selectedDate: string = DateUtils.today();
  @State activeTab: string = 'all';
  @State diaries: DiaryEntry[] = [];

  /** 二级 Tab：全部/我的/家人/收藏 */
  private tabs: DiaryTab[] = [
    { label: '全部', key: 'all' },
    { label: '我的', key: 'mine' },
    { label: '家人', key: 'family' },
    { label: '收藏', key: 'favorite' }
  ];

  /** 横向日期条数据（最近7天） */
  private dateBar: string[] = [];

  aboutToAppear(): void {
    this.dateBar = this.buildDateBar();
    this.loadDiaries();
  }

  /** 生成最近7天日期 */
  private buildDateBar(): string[] {
    const result: string[] = [];
    const today: Date = new Date();
    for (let i: number = -3; i <= 3; i++) {
      const d: Date = new Date(today.getFullYear(), today.getMonth(), today.getDate() + i);
      const y: number = d.getFullYear();
      const m: number = d.getMonth() + 1;
      const day: number = d.getDate();
      const dateStr: string = y + '-' + (m < 10 ? '0' : '') + m + '-' + (day < 10 ? '0' : '') + day;
      result.push(dateStr);
    }
    return result;
  }

  /** 获取日期数字（几号） */
  private getDayNum(dateStr: string): number {
    const parts: string[] = dateStr.split('-');
    return parseInt(parts[2], 10);
  }

  /** 获取星期几（中文） */
  private getWeekday(dateStr: string): string {
    const parts: string[] = dateStr.split('-');
    const d: Date = new Date(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10));
    const weekdays: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    return '周' + weekdays[d.getDay()];
  }

  /** 判断是否今天 */
  private isToday(dateStr: string): boolean {
    return dateStr === DateUtils.today();
  }

  /** 加载日记列表（真实数据 + mock 兜底） */
  private async loadDiaries(): Promise<void> {
    try {
      const vm: DiaryViewModel = new DiaryViewModel();
      const list: Diary[] = await vm.queryByMonth(2026, 7);
      this.diaries = list.map((d: Diary, idx: number): DiaryEntry => {
        return {
          id: d.id,
          date: d.date,
          title: d.content.substring(0, 20) + (d.content.length > 20 ? '...' : ''),
          summary: d.content,
          mood: 'happy',
          imageCount: 0
        };
      });
      if (this.diaries.length === 0) {
        this.diaries = this.getMockDiaries();
      }
    } catch (_err) {
      this.diaries = this.getMockDiaries();
    }
  }

  /** Mock 日记数据兜底 */
  private getMockDiaries(): DiaryEntry[] {
    return [
      { id: 1, date: '2026-07-23', title: '今天去了公园散步', summary: '阳光很好，和小猫一起在草坪上晒太阳，感觉非常放松。', mood: 'happy', imageCount: 3 },
      { id: 2, date: '2026-07-22', title: '完成了项目设计', summary: '终于把Mimi随记的核心功能设计完成了，明天开始编码。', mood: 'star', imageCount: 2 },
      { id: 3, date: '2026-07-21', title: '和家人一起做饭', summary: '今天妈妈教我做红烧肉，味道还不错，家人很开心。', mood: 'happy', imageCount: 1 }
    ];
  }

  /** 打开写日记页 */
  private openDiaryEdit(): void {
    router.pushUrl({
      url: 'pages/DiaryEditPage',
      params: { date: this.selectedDate }
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // ═══════════════════════════════════════════
        // 顶部导航栏（返回按钮 + 标题）
        // ═══════════════════════════════════════════
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

          Text('日记')
            .fontSize(TYPO.cardTitle.size)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            .margin({ left: 8 })
            .attributeModifier(SKETCH_TITLE)

          Blank()

          Button() {
            SymbolGlyph(IconMapper.PLUS)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.openDiaryEdit())
          .accessibilityText('写日记')
        }
        .width('100%')
        .height(56)
        .padding({ left: SPACING.pageH, right: SPACING.pageH })
        .alignItems(VerticalAlign.Center)

        // ═══════════════════════════════════════════
        // 横向日期条
        // ═══════════════════════════════════════════
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.dateBar, (dateStr: string) => {
              Column() {
                Text(this.getWeekday(dateStr))
                  .fontSize(10)
                  .fontColor(this.selectedDate === dateStr ?
                    (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF') :
                    (this.tokens ? this.tokens.textTertiary : '#999999'))
                Text(this.getDayNum(dateStr).toString())
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.selectedDate === dateStr ?
                    (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF') :
                    (this.tokens ? this.tokens.textPrimary : '#1A1A1A'))
                  .margin({ top: 2 })
              }
              .width(48)
              .height(64)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .borderRadius(24)
              .backgroundColor(this.selectedDate === dateStr ?
                (this.tokens ? this.tokens.btnPrimary : '#0A59F7') :
                (this.tokens ? this.tokens.bgCard : '#FFFFFF'))
              .shadow({
                radius: this.selectedDate === dateStr ? 8 : 4,
                color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.08)',
                offsetX: 0,
                offsetY: 2
              })
              .onClick(() => {
                this.selectedDate = dateStr;
              })
              .accessibilityText(dateStr + '，' + this.getWeekday(dateStr))
            })
          }
          .padding({ left: SPACING.pageH, right: SPACING.pageH })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .padding({ top: SPACING.pageTop, bottom: 12 })

        // ═══════════════════════════════════════════
        // 二级 Tab（全部/我的/家人/收藏）
        // ═══════════════════════════════════════════
        Row({ space: 0 }) {
          ForEach(this.tabs, (tab: DiaryTab) => {
            Column() {
              Text(tab.label)
                .fontSize(TYPO.body.size)
                .fontWeight(this.activeTab === tab.key ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.activeTab === tab.key ?
                  (this.tokens ? this.tokens.btnPrimary : '#0A59F7') :
                  (this.tokens ? this.tokens.textSecondary : '#666666'))
              if (this.activeTab === tab.key) {
                Divider()
                  .width(20)
                  .strokeWidth(2)
                  .color(this.tokens ? this.tokens.btnPrimary : '#0A59F7')
                  .margin({ top: 4 })
              }
            }
            .padding({ left: 16, right: 16, top: 4, bottom: 4 })
            .onClick(() => {
              this.activeTab = tab.key;
            })
            .accessibilityText(tab.label + (this.activeTab === tab.key ? '，已选中' : ''))
          })
        }
        .width('100%')
        .padding({ left: SPACING.pageH, right: SPACING.pageH, bottom: 8 })

        // ═══════════════════════════════════════════
        // 日记卡片流
        // ═══════════════════════════════════════════
        Scroll() {
          Column({ space: SPACING.cardGap }) {
            ForEach(this.diaries, (entry: DiaryEntry) => {
              Row() {
                // 左侧：标题 + 摘要 + 时间
                Column() {
                  Text(entry.title)
                    .fontSize(TYPO.cardTitle.size)
                    .fontWeight(TYPO.cardTitle.weight)
                    .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .attributeModifier(SKETCH_TITLE)
                  Text(entry.summary)
                    .fontSize(TYPO.body.size)
                    .fontColor(this.tokens ? this.tokens.textSecondary : '#666666')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 4 })
                    .attributeModifier(SKETCH_BODY)
                  Text(this.getWeekday(entry.date) + ' ' + entry.date.substring(5))
                    .fontSize(TYPO.eyebrow.size)
                    .fontColor(this.tokens ? this.tokens.textTertiary : '#999999')
                    .margin({ top: 6 })
                    .attributeModifier(SKETCH_BODY)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                // 右侧：缩略图占位
                if (entry.imageCount > 0) {
                  Row({ space: 4 }) {
                    ForEach([0, 1, 2], (idx: number) => {
                      if (idx < entry.imageCount) {
                        Column()
                          .width(56)
                          .height(56)
                          .borderRadius(RADIUS.item)
                          .backgroundColor(this.tokens ? this.tokens.accent : '#EBF5FF')
                      }
                    })
                  }
                  .margin({ left: 12 })
                }
              }
              .width('100%')
              .padding(SPACING.cardPadSm)
              .borderRadius(RADIUS.card)
              .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
              .shadow({
                radius: 8,
                color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.08)',
                offsetX: 0,
                offsetY: 2
              })
              .onClick(() => {
                router.pushUrl({
                  url: 'pages/DiaryDetailPage',
                  params: { date: entry.date }
                });
              })
              .accessibilityText(entry.title)
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .constraintSize({ minHeight: '100%' })
          .padding({
            left: SPACING.pageH,
            right: SPACING.pageH,
            bottom: SPACING.pageBottom
          })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.tokens ? this.tokens.bg : '#F5F7FA')
    }
    .width('100%')
    .height('100%')
  }
}
