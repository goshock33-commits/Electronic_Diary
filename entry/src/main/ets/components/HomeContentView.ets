// 页面：首页内容主体（家庭消息流）
// 功能：顶部导航栏 + AI 快捷入口金刚区 + 家庭消息流卡片列表 + 左侧抽屉菜单
// 开发范式：ArkTS 声明式开发范式
// 令牌驱动：RADIUS / SPACING / TYPO / IconMapper 全引用；颜色 tokens 判空兜底
// 崩溃防范（PROJECT_SPEC §9）：@StorageLink 全判空；@State 驱动刷新；无 getter-in-build
// 图标合规（PROJECT_SPEC §10）：仅用 SymbolGlyph + IconMapper；无 emoji
// 注意：底部 Tab 由 MainPage FloatingTabBar 提供，本组件不包含 Tab 栏

import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper, RADIUS, SPACING, TYPO, SKETCH_BODY_TYPO, SKETCH_BODY, SKETCH_CARD_TITLE, SKETCH_EYEBROW, SKETCH_SECTION_TITLE, FamilyMessageManager, MessageGroup } from '@ohos/shared';
import { DrawerMenu } from './DrawerMenu';
import { router, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'HomeContentView';

/** AI 快捷入口条目（金刚区） */
interface QuickEntry {
  key: string;
  icon: Resource;
  label: string;
  bgColor: string;
  iconColor: string;
}

/** 家庭消息流条目 */
interface FeedMessage {
  id: number;
  avatar: Resource;
  title: string;
  summary: string;
  time: string;
  unread: boolean;
  referenceId?: string; // 待办 ID（用于点击跳转到待办详情）
  messageType?: string; // 消息类型（'todo' | 'diary_share' | 'voice' | 'system'）
}

/**
 * 首页内容主体组件
 *
 * 包含三个主要区域：
 * 1. 顶部导航栏（Logo + 标题 + 搜索 + 菜单按钮）
 * 2. AI 快捷入口金刚区（3×2 圆形图标网格）
 * 3. 家庭消息流（卡片列表，含头像/标题/摘要/时间/未读红点）
 *
 * 左侧抽屉菜单通过 DrawerMenu 组件实现，点击菜单按钮打开。
 */
@Component
export struct HomeContentView {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  @State showDrawer: boolean = false;
  @State private feedMessages: FeedMessage[] = [];

  /** AI 快捷入口数据（图标走 IconMapper 静态常量；bgColor/iconColor 为装饰性浅色 tint） */
  private quickEntries: QuickEntry[] = [
    { key: 'photo', icon: IconMapper.CAMERA, label: '拍照记日记', bgColor: '#EBF5FF', iconColor: '#0A59F7' },
    { key: 'voice', icon: IconMapper.MIC, label: '语音记录', bgColor: '#E8F8EE', iconColor: '#52C41A' },
    { key: 'generate', icon: IconMapper.BOOKMARK, label: '日记生成', bgColor: '#FFF4E6', iconColor: '#FAAD14' },
    { key: 'remind', icon: IconMapper.BELL, label: '提醒事项', bgColor: '#F0EEFF', iconColor: '#722ED1' },
    { key: 'todo', icon: IconMapper.TAB_TODO, label: '家庭待办', bgColor: '#FFF0F0', iconColor: '#FF4D4F' },
    { key: 'ai', icon: IconMapper.AI_COMPANION, label: 'AI助手', bgColor: '#E6F7FF', iconColor: '#13C2C2' }
  ];

  // fix: DEV-026 · 接入 FamilyMessageManager 真实消息流
  async aboutToAppear(): Promise<void> {
    await this.loadMessages();
  }

  /**
   * 加载家庭消息流
   */
  private async loadMessages(): Promise<void> {
    try {
      const result = await FamilyMessageManager.getInstance().getMyMessageStream();
      if (result.success && result.data !== null) {
        const groups: MessageGroup[] = result.data;
        this.feedMessages = this.convertToFeedMessages(groups);
        hilog.info(0x0000, TAG, 'loadMessages: loaded %{public}d message groups', groups.length);
      } else {
        hilog.error(0x0000, TAG, 'loadMessages failed: %{public}s', result.message || 'unknown');
        // 失败时显示空列表（不用 mock 数据）
        this.feedMessages = [];
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'loadMessages exception: %{public}s', (e as Error).message);
      this.feedMessages = [];
    }
  }

  /**
   * 将 MessageGroup[] 转换为 FeedMessage[]
   */
  private convertToFeedMessages(groups: MessageGroup[]): FeedMessage[] {
    const defaultAvatar: Resource = $r('app.media.icon_default_avatar');
    const result: FeedMessage[] = [];

    for (let i: number = 0; i < groups.length; i++) {
      const group: MessageGroup = groups[i];
      const feedMsg: FeedMessage = {
        id: group.fromMember.id,
        avatar: defaultAvatar, // TODO: 后续支持自定义头像时，从 group.fromMember.avatar 加载
        title: group.getDisplayName(),
        summary: group.getPreviewText(),
        time: this.formatRelativeTime(group.timestamp),
        unread: group.hasUnread(),
        referenceId: group.latestMessage.reference_id !== null ? group.latestMessage.reference_id : undefined,
        messageType: group.latestMessage.type
      };
      result.push(feedMsg);
    }

    return result;
  }

  /**
   * 格式化相对时间（时间戳 → "10分钟前" / "1小时前" / "昨天" / "3天前"）
   */
  private formatRelativeTime(timestamp: number): string {
    const now: number = Date.now();
    const diff: number = now - timestamp;

    // 1分钟内
    if (diff < 60 * 1000) {
      return '刚刚';
    }

    // 1小时内
    if (diff < 60 * 60 * 1000) {
      const minutes: number = Math.floor(diff / (60 * 1000));
      return `${minutes}分钟前`;
    }

    // 24小时内
    if (diff < 24 * 60 * 60 * 1000) {
      const hours: number = Math.floor(diff / (60 * 60 * 1000));
      return `${hours}小时前`;
    }

    // 48小时内
    if (diff < 48 * 60 * 60 * 1000) {
      return '昨天';
    }

    // 7天内
    if (diff < 7 * 24 * 60 * 60 * 1000) {
      const days: number = Math.floor(diff / (24 * 60 * 60 * 1000));
      return `${days}天前`;
    }

    // 7天以上：显示月-日
    const date: Date = new Date(timestamp);
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    return `${month}月${day}日`;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ── 主内容区：顶栏 + 可滚动内容 ──
      Column() {
        this.buildTopNav()
        Scroll() {
          Column({ space: SPACING.sectionGap }) {
            this.buildQuickEntryGrid()
            this.buildMessageFeed()
          }
          .width('100%')
          .padding({
            left: SPACING.pageH,
            right: SPACING.pageH,
            top: SPACING.cardGap,
            bottom: SPACING.pageBottom
          })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')

      // ── 左侧抽屉菜单（覆盖层，通过 @Prop visible 控制显隐）──
      DrawerMenu({
        visible: this.showDrawer,
        onClose: () => {
          animateTo({ duration: 250, curve: Curve.EaseIn }, () => {
            this.showDrawer = false;
          });
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens ? this.tokens.bg : '#F5F7FA')
  }

  // ═══════════════════════════════════════════════════════════
  // 顶部导航栏：左 Logo + 标题 ｜ 右 搜索 + 菜单
  // ═══════════════════════════════════════════════════════════
  @Builder
  buildTopNav() {
    Row() {
      // 左：App Logo + 标题
      Row() {
        Image($r('app.media.startIcon'))
          .width(32)
          .height(32)
          .borderRadius(16)
        Text('Mimi随记')
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .margin({ left: 8 })
          .attributeModifier(SKETCH_CARD_TITLE)
      }
      .alignItems(VerticalAlign.Center)

      Blank()

      // 右：搜索 + 菜单
      Row() {
        Button() {
          SymbolGlyph(IconMapper.SEARCH)
            .fontSize(20)
            .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          router.pushUrl({ url: 'pages/SearchPage' });
        })
        .accessibilityText('搜索')

        Button() {
          SymbolGlyph(IconMapper.SORT)
            .fontSize(20)
            .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
            this.showDrawer = true;
          });
        })
        .accessibilityText('打开菜单')
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(56)
    .padding({ left: SPACING.pageH, right: SPACING.pageH })
    .alignItems(VerticalAlign.Center)
  }

  // ═══════════════════════════════════════════════════════════
  // AI 快捷入口金刚区（3 列 × 2 行圆形图标网格）
  // ═══════════════════════════════════════════════════════════
  @Builder
  buildQuickEntryGrid() {
    Column({ space: SPACING.cardGap }) {
      // 第一行
      Row() {
        this.buildQuickEntryItem(this.quickEntries[0])
        this.buildQuickEntryItem(this.quickEntries[1])
        this.buildQuickEntryItem(this.quickEntries[2])
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)

      // 第二行
      Row() {
        this.buildQuickEntryItem(this.quickEntries[3])
        this.buildQuickEntryItem(this.quickEntries[4])
        this.buildQuickEntryItem(this.quickEntries[5])
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
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
  }

  @Builder
  buildQuickEntryItem(entry: QuickEntry) {
    Column() {
      // 圆形图标 + 柔和彩色背景
      Stack() {
        SymbolGlyph(entry.icon)
          .fontSize(24)
          .fontColor([entry.iconColor])
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor(entry.bgColor)

      Text(entry.label)
        .fontSize(TYPO.eyebrow.size)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#666666')
        .margin({ top: 8 })
        .attributeModifier(SKETCH_BODY)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.handleQuickEntryTap(entry.key);
    })
    .accessibilityText(entry.label)
  }

  // ═══════════════════════════════════════════════════════════
  // 家庭消息流（卡片列表）
  // ═══════════════════════════════════════════════════════════
  @Builder
  buildMessageFeed() {
    Column({ space: SPACING.cardGap }) {
      // 分区标题
      Row() {
        Text('家庭消息流')
          .fontSize(TYPO.sectionTitle.size)
          .fontWeight(TYPO.sectionTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .attributeModifier(SKETCH_SECTION_TITLE)
      }
      .width('100%')

      // 消息卡片列表
      ForEach(this.feedMessages, (msg: FeedMessage) => {
        Row() {
          // 左：圆形头像
          Image(msg.avatar)
            .width(48)
            .height(48)
            .borderRadius(24)

          // 中：标题 + 摘要
          Column() {
            Text(msg.title)
              .fontSize(TYPO.cardTitle.size)
              .fontWeight(TYPO.cardTitle.weight)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .attributeModifier(SKETCH_CARD_TITLE)
            Text(msg.summary)
              .fontSize(TYPO.body.size)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#666666')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 4 })
              .attributeModifier(SKETCH_BODY_TYPO)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 12, right: 12 })

          // 右：时间 + 未读红点
          Column() {
            Text(msg.time)
              .fontSize(TYPO.eyebrow.size)
              .fontColor(this.tokens ? this.tokens.textTertiary : '#999999')
              .attributeModifier(SKETCH_EYEBROW)
            if (msg.unread) {
              Circle()
                .width(8)
                .height(8)
                .fill(this.tokens ? this.tokens.danger : '#FF4D4F')
                .margin({ top: 8 })
            }
          }
          .alignItems(HorizontalAlign.End)
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
          this.handleMessageClick(msg);
        })
        .accessibilityText(msg.title + '：' + msg.summary)
      }, (msg: FeedMessage) => msg.id.toString())
    }
    .width('100%')
  }

  /**
   * 快捷入口点击处理：跳转到对应功能页面
   */
  private handleQuickEntryTap(key: string): void {
    switch (key) {
      case 'photo':
        router.pushUrl({ url: 'pages/QuickCameraPage' });
        break;
      case 'voice':
        router.pushUrl({ url: 'pages/VoiceAssistantPage' });
        break;
      case 'generate':
        router.pushUrl({ url: 'pages/DiaryEditPage' });
        break;
      case 'remind':
        router.pushUrl({ url: 'pages/TodoPage' });
        break;
      case 'todo':
        router.pushUrl({ url: 'pages/FamilyPage' });
        break;
      case 'ai':
        AppStorage.setOrCreate('navTargetTab', 'ai');
        router.back({ url: 'pages/MainPage' });
        break;
      default:
        break;
    }
  }

  /**
   * 消息卡片点击处理：根据消息类型跳转到对应页面
   */
  private handleMessageClick(msg: FeedMessage): void {
    // AI助手消息：切换到 AI Tab
    if (msg.title === 'AI助手') {
      AppStorage.setOrCreate('navTargetTab', 'ai');
      router.back({ url: 'pages/MainPage' });
      return;
    }

    // 待办消息：跳转到 TodoPage（如果有 referenceId，通过 AppStorage 传递）
    if (msg.messageType === 'todo' && msg.referenceId !== undefined && msg.referenceId.length > 0) {
      // 通过 AppStorage 传递待办 ID，TodoPage 需要在 aboutToAppear 中读取
      AppStorage.setOrCreate('todo_detail_id', msg.referenceId);
      router.pushUrl({ url: 'pages/TodoPage' }).catch((err: Error) => {
        hilog.error(0x0000, TAG, 'pushUrl TodoPage failed: %{public}s', err.message);
      });
      return;
    }

    // 其他消息类型：跳转到家庭成员详情页
    router.pushUrl({ url: 'pages/FamilyMemberDetailPage' }).catch((err: Error) => {
      hilog.error(0x0000, TAG, 'pushUrl FamilyMemberDetailPage failed: %{public}s', err.message);
    });
  }
}
