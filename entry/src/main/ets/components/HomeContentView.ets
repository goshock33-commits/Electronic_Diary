// 页面：首页内容主体（家庭消息流）
// 功能：顶部导航栏 + AI 快捷入口金刚区 + 家庭消息流卡片列表 + 左侧抽屉菜单
// 开发范式：ArkTS 声明式开发范式
// 令牌驱动：RADIUS / SPACING / TYPO / IconMapper 全引用；颜色 tokens 判空兜底
// 崩溃防范（PROJECT_SPEC §9）：@StorageLink 全判空；@State 驱动刷新；无 getter-in-build
// 图标合规（PROJECT_SPEC §10）：仅用 SymbolGlyph + IconMapper；无 emoji
// 注意：底部 Tab 由 MainPage FloatingTabBar 提供，本组件不包含 Tab 栏
// DEV-007: 订阅登录成功事件，自动刷新首页数据

import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper, RADIUS, SPACING, TYPO, SKETCH_BODY_TYPO, SKETCH_BODY, SKETCH_CARD_TITLE, SKETCH_EYEBROW, SKETCH_SECTION_TITLE, MessageGroup, FamilyManager, Result, FamilyMember, EventBus } from '@ohos/shared';
import { FamilyMessageViewModel } from 'features_family_message';
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
  @State viewModel: FamilyMessageViewModel = new FamilyMessageViewModel();
  @State isRefreshing: boolean = false;
  @State private feedMessages: FeedMessage[] = [];
  @State private hasFamilyMembers: boolean = false;

  /** AI 快捷入口数据（图标走 IconMapper 静态常量；bgColor/iconColor 为装饰性浅色 tint） */
  private quickEntries: QuickEntry[] = [
    { key: 'photo', icon: IconMapper.CAMERA, label: '拍照记日记', bgColor: '#EBF5FF', iconColor: '#0A59F7' },
    { key: 'todo', icon: IconMapper.TAB_TODO, label: '待办管理', bgColor: '#FFF0F0', iconColor: '#FF4D4F' },
    { key: 'sync', icon: IconMapper.SYNC, label: '多端同步', bgColor: '#E6F7FF', iconColor: '#13C2C2' },
    { key: 'voice', icon: IconMapper.MIC, label: '语音记录', bgColor: '#E8F8EE', iconColor: '#52C41A' },
    { key: 'generate', icon: IconMapper.BOOKMARK, label: '日记生成', bgColor: '#FFF4E6', iconColor: '#FAAD14' },
    { key: 'ai', icon: IconMapper.AI_COMPANION, label: 'AI助手', bgColor: '#F0EEFF', iconColor: '#722ED1' }
  ];

  async aboutToAppear(): Promise<void> {
    hilog.info(0x0000, TAG, '🚀 HomeContentView aboutToAppear: START');

    // DEV-007: 订阅登录成功事件，自动刷新首页数据
    EventBus.on(EventBus.EventNames.ACCOUNT_LOGIN_SUCCESS, async () => {
      hilog.info(0x0000, TAG, '🔄 DEV-007: received ACCOUNT_LOGIN_SUCCESS, triggering refresh');
      await this.handleRefresh();
    });

    try {
      await this.loadMessages();
      hilog.info(0x0000, TAG, '✅ HomeContentView aboutToAppear: loadMessages completed');
      await this.checkFamilyMembers();
      hilog.info(0x0000, TAG, '✅ HomeContentView aboutToAppear: checkFamilyMembers completed');
    } catch (e) {
      hilog.error(0x0000, TAG, '❌ HomeContentView aboutToAppear failed: %{public}s', (e as Error).message);
    }
    hilog.info(0x0000, TAG, '🏁 HomeContentView aboutToAppear: END, hasFamilyMembers=%{public}s',
      this.hasFamilyMembers.toString());
  }

  aboutToDisappear(): void {
    // DEV-007: 取消订阅登录成功事件，避免内存泄漏
    EventBus.off(EventBus.EventNames.ACCOUNT_LOGIN_SUCCESS);
    hilog.info(0x0000, TAG, '🧹 DEV-007: unsubscribed from ACCOUNT_LOGIN_SUCCESS');

    this.viewModel.dispose();
  }

  /**
   * 加载家庭消息流
   */
  private async loadMessages(): Promise<void> {
    await this.viewModel.loadConversations();
    this.feedMessages = this.convertToFeedMessages(this.viewModel.conversationList);
    hilog.info(0x0000, TAG, 'loadMessages: loaded %{public}d conversations', this.viewModel.conversationList.length);
  }

  /**
   * 检查是否有家庭成员
   */
  private async checkFamilyMembers(): Promise<void> {
    hilog.info(0x0000, TAG, '🔍 checkFamilyMembers: starting...');

    try {
      const result: Result<FamilyMember[]> = await FamilyManager.getInstance().getAllMembers();
      hilog.info(0x0000, TAG, '🔍 checkFamilyMembers: success=%{public}s, data is null=%{public}s, count=%{public}d',
        result.success.toString(),
        (result.data === null).toString(),
        result.data ? result.data.length : 0);

      if (result.success && result.data !== null) {
        // 显式赋值，确保 @State 触发刷新
        const hasMembers = result.data.length > 0;
        this.hasFamilyMembers = hasMembers;

        hilog.info(0x0000, TAG, '✅ checkFamilyMembers: hasFamilyMembers=%{public}s, memberCount=%{public}d',
          this.hasFamilyMembers.toString(), result.data.length);

        if (result.data.length > 0) {
          hilog.info(0x0000, TAG, '📋 checkFamilyMembers: members=[%{public}s]',
            result.data.map((m: FamilyMember) => m.nickname).join(', '));
        }
      } else {
        this.hasFamilyMembers = false;
        hilog.warn(0x0000, TAG, '⚠️ checkFamilyMembers: failed or null data, message=%{public}s', result.message);
      }
    } catch (e) {
      this.hasFamilyMembers = false;
      hilog.error(0x0000, TAG, '❌ checkFamilyMembers exception: %{public}s', (e as Error).message);
    }

    // 强制打印最终状态
    hilog.info(0x0000, TAG, '🏁 checkFamilyMembers: FINAL hasFamilyMembers=%{public}s',
      this.hasFamilyMembers.toString());
  }

  /**
   * 下拉刷新处理
   */
  private async handleRefresh(): Promise<void> {
    this.isRefreshing = true;
    await this.viewModel.refresh();
    this.feedMessages = this.convertToFeedMessages(this.viewModel.conversationList);
    await this.checkFamilyMembers();
    this.isRefreshing = false;
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

        // 下拉刷新 + 滚动容器
        Refresh({ refreshing: $$this.isRefreshing }) {
          Scroll() {
            Column({ space: SPACING.sectionGap }) {
              this.buildQuickEntryGrid()
              this.buildMessageFeedOrGuide()
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
        .onRefreshing(async () => {
          await this.handleRefresh();
        })
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
    .onAppear(() => {
      hilog.info(0x0000, TAG, '🎨 HomeContentView build rendered: hasFamilyMembers=%{public}s, feedMessages=%{public}d',
        this.hasFamilyMembers.toString(), this.feedMessages.length);
    })
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
  // 家庭消息流或引导卡片（根据是否有家庭成员判断）
  // ═══════════════════════════════════════════════════════════
  @Builder
  buildMessageFeedOrGuide() {
    if (!this.hasFamilyMembers) {
      // 无家庭成员时显示引导卡片
      this.buildEmptyGuide();
    } else if (this.feedMessages.length === 0) {
      // 有家庭成员但无消息时显示空消息提示
      this.buildEmptyMessageHint();
    } else {
      // 有消息时显示消息流
      this.buildMessageFeed();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 无家庭引导卡片
  // ═══════════════════════════════════════════════════════════
  @Builder
  buildEmptyGuide() {
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

      // 引导卡片
      Column({ space: 16 }) {
        // 图标
        SymbolGlyph(IconMapper.NAV_PROFILE)
          .fontSize(48)
          .fontColor([this.tokens ? this.tokens.textTertiary : '#999999'])

        // 提示文本
        Text('还没有加入家庭')
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .attributeModifier(SKETCH_CARD_TITLE)

        Text('创建或加入家庭后，即可与家人分享日记、待办和语音')
          .fontSize(TYPO.body.size)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#666666')
          .textAlign(TextAlign.Center)
          .attributeModifier(SKETCH_BODY_TYPO)

        // 操作按钮
        Row({ space: 12 }) {
          Button('创建家庭')
            .fontSize(TYPO.body.size)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
            .borderRadius(RADIUS.item)
            .padding({ left: 20, right: 20, top: 10, bottom: 10 })
            .border({
              width: 1,
              color: this.tokens ? this.tokens.border : '#E0E0E0'
            })
            .onClick(() => {
              router.pushUrl({ url: 'pages/FamilyPage' }).catch((err: Error) => {
                hilog.error(0x0000, TAG, 'pushUrl FamilyPage failed: %{public}s', err.message);
              });
            })

          Button('加入家庭')
            .fontSize(TYPO.body.size)
            .fontColor('#FFFFFF')
            .backgroundColor(this.tokens ? this.tokens.primary : '#0A59F7')
            .borderRadius(RADIUS.item)
            .padding({ left: 20, right: 20, top: 10, bottom: 10 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/FamilyPage' }).catch((err: Error) => {
                hilog.error(0x0000, TAG, 'pushUrl FamilyPage failed: %{public}s', err.message);
              });
            })
        }
        .margin({ top: 8 })
      }
      .width('100%')
      .padding(SPACING.cardPadLg)
      .borderRadius(RADIUS.card)
      .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
      .shadow({
        radius: 8,
        color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.08)',
        offsetX: 0,
        offsetY: 2
      })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .onAppear(() => {
      hilog.info(0x0000, TAG, '📢 UI: showing EMPTY GUIDE (no family members)');
    })
  }

  // ═══════════════════════════════════════════════════════════
  // 有家庭成员但暂无消息提示
  // ═══════════════════════════════════════════════════════════
  @Builder
  buildEmptyMessageHint() {
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

      // 空消息提示卡片
      Column({ space: 12 }) {
        SymbolGlyph(IconMapper.NAV_PROFILE)
          .fontSize(36)
          .fontColor([this.tokens ? this.tokens.textTertiary : '#999999'])

        Text('暂无家庭消息')
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .attributeModifier(SKETCH_CARD_TITLE)

        Text('与家人互动后，消息会显示在这里')
          .fontSize(TYPO.body.size)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#666666')
          .textAlign(TextAlign.Center)
          .attributeModifier(SKETCH_BODY_TYPO)
      }
      .width('100%')
      .padding(SPACING.cardPadLg)
      .borderRadius(RADIUS.card)
      .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
      .shadow({
        radius: 8,
        color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.08)',
        offsetX: 0,
        offsetY: 2
      })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .onAppear(() => {
      hilog.info(0x0000, TAG, '📢 UI: showing EMPTY MESSAGE HINT (has members, no messages)');
    })
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
    .onAppear(() => {
      hilog.info(0x0000, TAG, '📢 UI: showing MESSAGE FEED (has %{public}d messages)', this.feedMessages.length);
    })
  }

  /**
   * 快捷入口点击处理：跳转到对应功能页面
   */
  private handleQuickEntryTap(key: string): void {
    switch (key) {
      case 'photo':
        router.pushUrl({ url: 'pages/QuickCameraPage' }).catch((err: Error) => {
          hilog.error(0x0000, TAG, 'pushUrl QuickCameraPage failed: %{public}s', err.message);
        });
        break;
      case 'todo':
        router.pushUrl({ url: 'pages/TodoPage' }).catch((err: Error) => {
          hilog.error(0x0000, TAG, 'pushUrl TodoPage failed: %{public}s', err.message);
        });
        break;
      case 'sync':
        router.pushUrl({ url: 'pages/SettingsPage', params: { openAdvanced: true } }).catch((err: Error) => {
          hilog.error(0x0000, TAG, 'pushUrl SettingsPage failed: %{public}s', err.message);
        });
        break;
      case 'voice':
        router.pushUrl({ url: 'pages/VoiceAssistantPage' }).catch((err: Error) => {
          hilog.error(0x0000, TAG, 'pushUrl VoiceAssistantPage failed: %{public}s', err.message);
        });
        break;
      case 'generate':
        router.pushUrl({ url: 'pages/DiaryEditPage' }).catch((err: Error) => {
          hilog.error(0x0000, TAG, 'pushUrl DiaryEditPage failed: %{public}s', err.message);
        });
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
