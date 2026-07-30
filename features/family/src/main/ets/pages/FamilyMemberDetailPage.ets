// 页面组件：家庭成员详情（用户信息卡 + 数据统计 + 快捷功能 + 动态时间线）
// 主题：HarmonyOS 蓝白卡片风格
// §9.4：@StorageLink tokens 读取全部判空兜底

import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper, RADIUS, SPACING, TYPO, FONT, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';
import { router } from '@kit.ArkUI';

/** 统计数据项 */
interface StatsItem {
  value: string;
  label: string;
}

/** 快捷功能项 */
interface QuickAction {
  key: string;
  icon: Resource;
  label: string;
}

/** 时间线条目 */
interface TimelineEntry {
  time: string;
  title: string;
  content: string;
}

/** 路由参数 */
interface MemberDetailRouteParams {
  memberId?: number;
  memberName?: string;
}

@Component
export struct FamilyMemberDetailPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  @State private memberName: string = '家庭成员';
  @State private memberId: number = -1;
  @State private joinedDays: number = 365;

  private stats: StatsItem[] = [
    { value: '5', label: '今日待办' },
    { value: '80%', label: '完成率' },
    { value: '128', label: '日记数' },
    { value: '56', label: '开心事' }
  ];

  private quickActions: QuickAction[] = [
    { key: 'send_todo', icon: IconMapper.SEND, label: '发送待办' },
    { key: 'view_diary', icon: IconMapper.NAV_DIARY, label: '查看日记' },
    { key: 'happy', icon: IconMapper.MOOD_HAPPY, label: '开心事' },
    { key: 'remind', icon: IconMapper.BELL, label: '提醒' },
    { key: 'note', icon: IconMapper.COPY, label: '备注' }
  ];

  private timeline: TimelineEntry[] = [
    { time: '09:30', title: '完成待办', content: '完成了「晨间冥想」待办任务' },
    { time: '12:00', title: '写日记', content: '记录了今日的心情和感悟' },
    { time: '15:20', title: '打卡开心事', content: '今天和朋友一起喝了下午茶' },
    { time: '18:00', title: '番茄钟', content: '完成了一个 25 分钟的专注番茄钟' }
  ];

  aboutToAppear(): void {
    const params = router.getParams() as MemberDetailRouteParams;
    if (params) {
      if (params.memberName && params.memberName.length > 0) {
        this.memberName = params.memberName;
      }
      if (params.memberId !== undefined) {
        this.memberId = params.memberId;
      }
    }
  }

  private handleQuickActionTap(key: string): void {
    switch (key) {
      case 'send_todo':
        router.pushUrl({ url: 'pages/TodoPage' });
        break;
      case 'view_diary':
        router.pushUrl({ url: 'pages/CalendarPage' });
        break;
      case 'happy':
        router.pushUrl({ url: 'pages/DiaryEditPage' });
        break;
      case 'remind':
        router.pushUrl({ url: 'pages/TodoPage' });
        break;
      case 'note':
        router.pushUrl({ url: 'pages/DiaryEditPage' });
        break;
      default:
        break;
    }
  }

  build() {
    Scroll() {
      Column() {
        this.buildUserInfoCard()
        this.buildStatsGrid()
        this.buildQuickActions()
        this.buildTimeline()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
  }

  // ── 用户信息卡：大头像居中 + 昵称 + 加入天数 ──
  @Builder
  buildUserInfoCard() {
    Column() {
      // 大圆形头像（居中）
      Stack() {
        SymbolGlyph(IconMapper.NAV_PROFILE)
          .fontSize(40)
          .fontColor([this.tokens ? this.tokens.primary : '#0A59F7'])
      }
      .width(80)
      .height(80)
      .borderRadius(40)
      .backgroundColor(this.tokens ? this.tokens.accent : '#EBF5FF')

      // 昵称
      Text(this.memberName)
        .fontSize(TYPO.sectionTitle.size)
        .fontWeight(700)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .margin({ top: 12 })
        .attributeModifier(SKETCH_TITLE)

      // 加入天数
      Text('已加入' + this.joinedDays.toString() + '天')
        .fontSize(TYPO.eyebrow.size)
        .fontColor(this.tokens ? this.tokens.textTertiary : '#999999')
        .margin({ top: 4 })
        .attributeModifier(SKETCH_BODY)
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
    .alignItems(HorizontalAlign.Center)
    .borderRadius(RADIUS.card)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .shadow({
      radius: 8,
      color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.08)',
      offsetX: 0,
      offsetY: 2
    })
  }

  // ── 数据统计网格（4 列） ──
  @Builder
  buildStatsGrid() {
    Row() {
      ForEach(this.stats, (item: StatsItem) => {
        Column() {
          Text(item.value)
            .fontSize(TYPO.numCard.size)
            .fontWeight(900)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            .fontFamily(FONT.monoExtraBold)
          Text(item.label)
            .fontSize(TYPO.eyebrow.size)
            .fontColor(this.tokens ? this.tokens.textTertiary : '#999999')
            .margin({ top: 4 })
            .attributeModifier(SKETCH_BODY)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }, (item: StatsItem) => item.label)
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .borderRadius(RADIUS.card)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .shadow({
      radius: 8,
      color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.08)',
      offsetX: 0,
      offsetY: 2
    })
    .margin({ top: SPACING.cardGap })
    .alignItems(VerticalAlign.Center)
  }

  // ── 快捷功能入口（5 个方形按钮） ──
  @Builder
  buildQuickActions() {
    Row() {
      ForEach(this.quickActions, (action: QuickAction) => {
        Column() {
          Stack() {
            SymbolGlyph(action.icon)
              .fontSize(22)
              .fontColor([this.tokens ? this.tokens.primary : '#0A59F7'])
          }
          .width(48)
          .height(48)
          .borderRadius(RADIUS.cardMd)
          .backgroundColor(this.tokens ? this.tokens.accent : '#EBF5FF')

          Text(action.label)
            .fontSize(TYPO.eyebrow.size)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#666666')
            .margin({ top: 6 })
            .attributeModifier(SKETCH_BODY)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.handleQuickActionTap(action.key);
        })
        .accessibilityText(action.label)
      }, (action: QuickAction) => action.key)
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .borderRadius(RADIUS.card)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .shadow({
      radius: 8,
      color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.08)',
      offsetX: 0,
      offsetY: 2
    })
    .margin({ top: SPACING.cardGap })
    .alignItems(VerticalAlign.Center)
  }

  // ── 动态时间线 ──
  @Builder
  buildTimeline() {
    Column() {
      Text('动态')
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(700)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .margin({ bottom: 12 })
        .attributeModifier(SKETCH_TITLE)

      ForEach(this.timeline, (entry: TimelineEntry, index: number) => {
        Row() {
          // 左侧：时间 + 竖线 + 圆点
          Column() {
            Text(entry.time)
              .fontSize(TYPO.eyebrow.size)
              .fontColor(this.tokens ? this.tokens.textTertiary : '#999999')
              .fontFamily(FONT.monoBold)
              .margin({ bottom: 4 })

            Stack() {
              Circle({ width: 10, height: 10 })
                .fill(this.tokens ? this.tokens.primary : '#0A59F7')
            }
            .width(10)
            .height(10)

            if (index < this.timeline.length - 1) {
              Column()
                .width(2)
                .layoutWeight(1)
                .backgroundColor(this.tokens ? this.tokens.border : '#E0E6ED')
                .margin({ top: 2 })
            }
          }
          .width(60)
          .alignItems(HorizontalAlign.Center)

          // 右侧：事件卡片
          Column() {
            Text(entry.title)
              .fontSize(TYPO.cardTitle.size)
              .fontWeight(600)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .attributeModifier(SKETCH_BODY)
            Text(entry.content)
              .fontSize(TYPO.eyebrow.size)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#666666')
              .margin({ top: 4 })
              .attributeModifier(SKETCH_BODY)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .padding(SPACING.cardPadSm)
          .borderRadius(RADIUS.cardMd)
          .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
          .margin({ bottom: SPACING.cardGap })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (entry: TimelineEntry) => entry.time + '_' + entry.title)
    }
    .width('100%')
    .margin({ top: SPACING.sectionGap })
    .alignItems(HorizontalAlign.Start)
  }
}
