// agentID: HUI-002
// File: FamilyMessageStreamView.ets
// Task: T042 消息流列表组件 —— 类微信会话列表（LazyForEach + 长按删除）
// 依赖: T041 FamilyMessageViewModel（已完成）
// 合规: ArkTS 严格模式，PROJECT_SPEC UI 规范，用户删除偏好（长按抖动+叉号）

import { MessageGroup, IconMapper, DateUtils } from '@ohos/shared';
import type { ThemeColorTokens } from '@ohos/shared';
import { SKETCH_BODY } from '@ohos/shared';
import { FamilyMessageViewModel } from '../viewmodel/FamilyMessageViewModel';

/**
 * 消息流数据源（LazyForEach 适配器）
 */
class MessageStreamDataSource implements IDataSource {
  private dataArray: MessageGroup[] = [];
  private listeners: DataChangeListener[] = [];

  public totalCount(): number {
    return this.dataArray.length;
  }

  public getData(index: number): MessageGroup {
    return this.dataArray[index];
  }

  public registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  public unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /**
   * 更新数据源
   */
  public setData(data: MessageGroup[]): void {
    this.dataArray = data;
    this.notifyDataReload();
  }

  /**
   * 删除指定索引数据
   */
  public deleteData(index: number): void {
    if (index >= 0 && index < this.dataArray.length) {
      this.dataArray.splice(index, 1);
      this.notifyDataDelete(index);
    }
  }

  private notifyDataReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }

  private notifyDataDelete(index: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataDelete(index);
    });
  }
}

/**
 * 家庭消息流列表组件
 *
 * 职责：
 * 1. 类微信会话列表（头像+昵称+摘要+时间+红点）
 * 2. LazyForEach 分页渲染（50+ 会话无卡顿）
 * 3. 空态与加载态
 * 4. 长按删除（抖动+右上角叉号，禁左滑/禁大红块）
 *
 * 使用示例：
 * ```
 * FamilyMessageStreamView({
 *   viewModel: this.viewModel,
 *   onConversationClick: (peerUid: string) => { ... }
 * })
 * ```
 */
@Component
export struct FamilyMessageStreamView {
  @ObjectLink viewModel: FamilyMessageViewModel;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  /** 点击会话回调 */
  onConversationClick?: (peerUid: string) => void;

  /** 数据源（LazyForEach） */
  private dataSource: MessageStreamDataSource = new MessageStreamDataSource();

  /** 长按编辑模式 */
  @State editMode: boolean = false;
  /** 长按抖动动画状态 */
  @State shakeIndex: number = -1;

  aboutToAppear(): void {
    // 初始化数据源
    this.updateDataSource();
  }

  /**
   * 监听 ViewModel 数据变化，同步到数据源
   */
  private updateDataSource(): void {
    this.dataSource.setData(this.viewModel.conversationList);
  }

  build() {
    Column() {
      if (this.viewModel.isLoading && this.viewModel.conversationList.length === 0) {
        // 加载态
        this.buildLoadingState();
      } else if (this.viewModel.conversationList.length === 0) {
        // 空态
        this.buildEmptyState();
      } else {
        // 会话列表
        this.buildConversationList();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens ? this.tokens.bg : '#FFFFFF')
  }

  /**
   * 加载态
   */
  @Builder
  buildLoadingState() {
    Column() {
      SymbolGlyph(IconMapper.LOADING)
        .fontSize(48)
        .fontColor([this.tokens ? this.tokens.textTertiary : '#BDBDBD'])
        .animation({
          duration: 1000,
          curve: Curve.Linear,
          iterations: -1
        })
        .rotate({ angle: 360 })

      Text('加载中...')
        .fontSize(14)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#8A8A8A')
        .margin({ top: 16 })
        .attributeModifier(SKETCH_BODY)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 空态
   */
  @Builder
  buildEmptyState() {
    Column() {
      SymbolGlyph(IconMapper.EMPTY)
        .fontSize(48)
        .fontColor([this.tokens ? this.tokens.textTertiary : '#BDBDBD'])
        .opacity(0.4)

      Text('暂无消息')
        .fontSize(16)
        .fontWeight(500)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
        .margin({ top: 16 })
        .attributeModifier(SKETCH_BODY)

      Text('家庭成员的消息会在这里显示')
        .fontSize(14)
        .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
        .margin({ top: 8 })
        .attributeModifier(SKETCH_BODY)
    }
    .width('100%')
    .height('100%')
    .padding({ top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 会话列表
   */
  @Builder
  buildConversationList() {
    List() {
      LazyForEach(this.dataSource, (item: MessageGroup, index: number) => {
        ListItem() {
          this.buildConversationItem(item, index);
        }
        .onClick(() => {
          if (!this.editMode && this.onConversationClick) {
            this.onConversationClick(item.fromMember.uid ?? '');
          }
        })
      }, (item: MessageGroup) => item.fromMember.uid ?? item.fromMember.id.toString())
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring)
    .divider({
      strokeWidth: 0.5,
      color: this.tokens ? this.tokens.divider : '#E0E0E0',
      startMargin: 72,
      endMargin: 0
    })
    .onScrollIndex((start: number) => {
      // 滚动到底部触发加载更多
      if (start + 10 >= this.viewModel.conversationList.length && this.viewModel.hasMore) {
        this.viewModel.loadMore();
      }
    })
  }

  /**
   * 会话条目
   */
  @Builder
  buildConversationItem(item: MessageGroup, index: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Row() {
        // 左：头像
        this.buildAvatar(item);

        // 中：昵称+摘要+时间
        Column() {
          Row() {
            Text(item.getDisplayName())
              .fontSize(16)
              .fontWeight(500)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .attributeModifier(SKETCH_BODY)

            // 相对时间
            Text(this.formatRelativeTime(item.timestamp))
              .fontSize(12)
              .fontColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
              .margin({ left: 8 })
              .attributeModifier(SKETCH_BODY)
          }
          .width('100%')
          .margin({ bottom: 4 })

          // 消息摘要
          Text(this.truncatePreview(item.getPreviewText()))
            .fontSize(14)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .attributeModifier(SKETCH_BODY)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12, right: 40 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')

      // 右上：未读红点
      if (item.hasUnread() && !this.editMode) {
        this.buildUnreadBadge(item.unreadCount);
      }

      // 长按删除：右上角叉号
      if (this.editMode) {
        this.buildDeleteButton(index);
      }
    }
    .width('100%')
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          if (!this.editMode) {
            this.editMode = true;
            this.shakeIndex = index;
            // 抖动动画
            animateTo({
              duration: 100,
              curve: Curve.EaseInOut,
              iterations: 3,
              playMode: PlayMode.Alternate
            }, () => {
              this.shakeIndex = -1;
            });
          }
        })
    )
    .rotate({
      angle: this.shakeIndex === index ? 2 : 0,
      centerX: '50%',
      centerY: '50%'
    })
  }

  /**
   * 头像
   */
  @Builder
  buildAvatar(item: MessageGroup) {
    if (item.fromMember.avatar !== null && item.fromMember.avatar.length > 0) {
      Image(item.fromMember.avatar)
        .width(40)
        .height(40)
        .borderRadius(20)
        .objectFit(ImageFit.Cover)
    } else {
      // 默认头像：使用 SymbolGlyph
      Stack() {
        Circle({ width: 40, height: 40 })
          .fill(this.tokens ? this.tokens.surface : '#F5F5F5')
        SymbolGlyph(IconMapper.NAV_PROFILE)
          .fontSize(24)
          .fontColor([this.tokens ? this.tokens.textTertiary : '#BDBDBD'])
      }
      .width(40)
      .height(40)
    }
  }

  /**
   * 未读红点
   */
  @Builder
  buildUnreadBadge(count: number) {
    Text(count > 99 ? '99+' : count.toString())
      .fontSize(10)
      .fontColor('#FFFFFF')
      .fontWeight(FontWeight.Bold)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor('#FF3B30')
      .borderRadius(10)
      .position({ x: '100%', y: 12 })
      .translate({ x: -52, y: 0 })
      .constraintSize({ minWidth: 18 })
      .textAlign(TextAlign.Center)
  }

  /**
   * 删除按钮（长按抖动后显示）
   */
  @Builder
  buildDeleteButton(index: number) {
    Stack() {
      Circle({ width: 24, height: 24 })
        .fill(this.tokens ? this.tokens.textSecondary : '#8A8A8A')
      SymbolGlyph(IconMapper.CLOSE)
        .fontSize(14)
        .fontColor(['#FFFFFF'])
    }
    .width(24)
    .height(24)
    .position({ x: '100%', y: 8 })
    .translate({ x: -24, y: 0 })
    .onClick(() => {
      this.handleDeleteConversation(index);
    })
  }

  /**
   * 格式化相对时间
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
      return minutes + '分钟前';
    }
    // 今天
    if (diff < 24 * 60 * 60 * 1000) {
      const hours: number = Math.floor(diff / (60 * 60 * 1000));
      return hours + '小时前';
    }
    // 昨天
    if (diff < 48 * 60 * 60 * 1000) {
      return '昨天';
    }
    // 显示日期
    const date: Date = new Date(timestamp);
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    return month + '/' + day;
  }

  /**
   * 截断摘要文本（最多30字）
   */
  private truncatePreview(text: string): string {
    if (text.length <= 30) {
      return text;
    }
    return text.substring(0, 30) + '...';
  }

  /**
   * 处理删除会话
   */
  private handleDeleteConversation(index: number): void {
    // 从数据源删除
    this.dataSource.deleteData(index);
    // 同步 ViewModel（删除会话并重新计算未读数）
    this.viewModel.conversationList.splice(index, 1);

    // 手动重新计算未读总数
    let total: number = 0;
    for (let i = 0; i < this.viewModel.conversationList.length; i++) {
      total += this.viewModel.conversationList[i].unreadCount;
    }
    this.viewModel.unreadTotal = total;

    // 如果没有数据了，退出编辑模式
    if (this.viewModel.conversationList.length === 0) {
      this.editMode = false;
    }
  }
}
