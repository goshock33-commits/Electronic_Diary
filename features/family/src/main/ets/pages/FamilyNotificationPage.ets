// <!-- agentID: DEV-011 -->
// 页面组件：家庭通知（分类筛选 + 时间线消息流）
// 归属：features_family（纯 UI 内容主体，页面壳在 entry/pages/FamilyNotificationPage.ets）
// 主题：HarmonyOS 蓝白卡片风格（primary=#0A59F7, bg=#F5F7FA, bgCard=#FFFFFF, accent=#EBF5FF）
// §1.4 三者一致：模块 name = features_family = 依赖 key = import 路径
// §9.4：@StorageLink tokens 读取全部判空兜底
// 令牌：RADIUS / SPACING / TYPO / FONT —— 全引用，禁散写魔数

import type { ThemeColorTokens } from '@ohos/shared';
import { RADIUS, SPACING, TYPO, FONT, SKETCH_BODY } from '@ohos/shared';

/** 通知分类标签 */
interface CategoryTab {
  key: string;
  label: string;
}

/** 通知消息项 */
interface NotificationItem {
  time: string;
  title: string;
  content: string;
  timestamp: string;
  category: string;
}

@Component
export struct FamilyNotificationPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** 当前选中的分类 */
  @State private activeCategory: string = 'all';

  /** 分类标签列表 */
  private categories: CategoryTab[] = [
    { key: 'all', label: '全部' },
    { key: 'todo', label: '待办' },
    { key: 'diary', label: '日记' },
    { key: 'system', label: '系统' }
  ];

  /** 通知消息列表 */
  private allNotifications: NotificationItem[] = [
    {
      time: '09:30',
      title: '新待办提醒',
      content: '妈妈给你发送了一个待办：记得买牛奶',
      timestamp: '今天 09:30',
      category: 'todo'
    },
    {
      time: '12:00',
      title: '日记更新',
      content: '爸爸发布了一篇新日记「周末郊游」',
      timestamp: '今天 12:00',
      category: 'diary'
    },
    {
      time: '15:20',
      title: '开心事分享',
      content: '妹妹分享了一件开心事：今天学会了做蛋糕',
      timestamp: '今天 15:20',
      category: 'diary'
    },
    {
      time: '18:00',
      title: '系统通知',
      content: '你的家庭组成员已更新，新增 1 位成员',
      timestamp: '今天 18:00',
      category: 'system'
    },
    {
      time: '昨天',
      title: '待办完成',
      content: '妈妈完成了待办「打扫客厅」',
      timestamp: '昨天 20:15',
      category: 'todo'
    }
  ];

  /** 根据当前分类筛选通知 */
  private getFilteredNotifications(): NotificationItem[] {
    if (this.activeCategory === 'all') {
      return this.allNotifications;
    }
    const result: NotificationItem[] = [];
    for (let i = 0; i < this.allNotifications.length; i++) {
      if (this.allNotifications[i].category === this.activeCategory) {
        result.push(this.allNotifications[i]);
      }
    }
    return result;
  }

  build() {
    Column() {
      // ── 分类筛选标签 ──
      this.buildCategoryTabs()

      // ── 通知时间线 ──
      Scroll() {
        Column() {
          this.buildNotificationTimeline()
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
  }

  // ── 分类筛选标签（全部 / 待办 / 日记 / 系统） ──
  @Builder
  buildCategoryTabs() {
    Row() {
      ForEach(this.categories, (tab: CategoryTab) => {
        Text(tab.label)
          .fontSize(TYPO.body.size)
          .fontWeight(this.activeCategory === tab.key ? 600 : 400)
          .fontColor(this.activeCategory === tab.key
            ? (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
            : (this.tokens ? this.tokens.textSecondary : '#5A5A5A'))
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(RADIUS.input)
          .backgroundColor(this.activeCategory === tab.key
            ? (this.tokens ? this.tokens.btnPrimary : '#0A59F7')
            : Color.Transparent)
          .attributeModifier(SKETCH_BODY)
          .onClick(() => {
            this.activeCategory = tab.key;
          })
          .accessibilityText(tab.label + '分类')
      }, (tab: CategoryTab) => tab.key)
    }
    .width('100%')
    .margin({ bottom: SPACING.cardGap })
  }

  // ── 通知时间线（左侧时间 + 圆点竖线，右侧消息卡片） ──
  @Builder
  buildNotificationTimeline() {
    Column() {
      ForEach(this.getFilteredNotifications(), (item: NotificationItem, index: number) => {
        Row() {
          // 左侧：时间 + 圆点 + 竖线
          Column() {
            Text(item.time)
              .fontSize(TYPO.eyebrow.size)
              .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
              .fontFamily(FONT.monoBold)
              .margin({ bottom: 4 })

            // 圆点节点
            Stack() {
              Circle({ width: 10, height: 10 })
                .fill(this.tokens ? this.tokens.primary : '#0A59F7')
            }
            .width(10)
            .height(10)

            // 竖线（非最后一项）
            if (index < this.getFilteredNotifications().length - 1) {
              Column()
                .width(2)
                .layoutWeight(1)
                .backgroundColor(this.tokens ? this.tokens.border : '#E0E6ED')
                .margin({ top: 2 })
            }
          }
          .width(60)
          .alignItems(HorizontalAlign.Center)

          // 右侧：消息卡片
          Column() {
            Text(item.title)
              .fontSize(TYPO.cardTitle.size)
              .fontWeight(600)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .attributeModifier(SKETCH_BODY)
            Text(item.content)
              .fontSize(TYPO.eyebrow.size)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
              .margin({ top: 4 })
              .attributeModifier(SKETCH_BODY)
            Text(item.timestamp)
              .fontSize(TYPO.eyebrow.size)
              .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
              .margin({ top: 6 })
              .fontFamily(FONT.mono)
              .attributeModifier(SKETCH_BODY)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .padding(SPACING.cardPadSm)
          .borderRadius(RADIUS.cardMd)
          .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
          .border({ width: 1, color: this.tokens ? this.tokens.border : '#E0E6ED' })
          .shadow({
            radius: 8,
            color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.04)',
            offsetX: 0,
            offsetY: 2
          })
          .margin({ bottom: index < this.getFilteredNotifications().length - 1 ? SPACING.cardGap : 0 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (item: NotificationItem) => item.timestamp + '_' + item.title)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
