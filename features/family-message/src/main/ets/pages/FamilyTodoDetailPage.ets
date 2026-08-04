// agentID: HUI-004
// agentID: DEV-008
// File: FamilyTodoDetailPage.ets
// Task: T046 待办详情页 UI（消息条目形式）+ T047 路由参数契约
// 依赖: T045 FamilyTodoDetailViewModel
// 主题：HarmonyOS 蓝白卡片风格
// 令牌：IconMapper / SPACING / TYPO / ICON 全引用
// 路由参数契约（T047）: peerUid (必选) + messageId/todoId (可选)

import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper, SPACING, TYPO, ICON, SKETCH_BODY, RADIUS } from '@ohos/shared';
import { FamilyMessage, AccountDao } from '@ohos/shared';
import { FamilyTodoDetailViewModel } from '../viewmodel/FamilyTodoDetailViewModel';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';

const TAG = 'FamilyTodoDetailPage';

/** T047 路由参数契约 */
interface TodoDetailRouteParams {
  /** 必选：对端成员 uid */
  peerUid: string;
  /** 可选：消息 ID（定位到该消息，暂未实现） */
  messageId?: string;
  /** 可选：待办 ID（直接加载该待办） */
  todoId?: number;
  /** 可选：对端成员昵称（显示用） */
  peerNickname?: string;
}

@Component
export struct FamilyTodoDetailPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  @State private viewModel: FamilyTodoDetailViewModel = new FamilyTodoDetailViewModel();
  @State private peerNickname: string = '家人';
  @State private inputText: string = '';
  @State private currentUid: string = '';
  @State private isLoading: boolean = true;

  private scroller: Scroller = new Scroller();
  private todoId: number = -1;
  private peerUid: string = '';

  async aboutToAppear(): Promise<void> {
    // T047: 解析路由参数
    const params = router.getParams() as TodoDetailRouteParams;
    if (!params || !params.peerUid) {
      hilog.error(0x0000, TAG, 'T047: missing required param peerUid');
      this.isLoading = false;
      return;
    }

    this.peerUid = params.peerUid;
    this.todoId = params.todoId ?? -1;
    this.peerNickname = params.peerNickname ?? '家人';

    hilog.info(0x0000, TAG, 'T047: route params - peerUid=%{public}s todoId=%{public}d nickname=%{public}s',
      this.peerUid, this.todoId, this.peerNickname);

    // 获取当前登录 uid
    const uid = await AccountDao.getLoggedInUid();
    if (uid !== null) {
      this.currentUid = uid;
    }

    // 加载数据
    await this.init(this.todoId, this.peerUid, this.peerNickname);
  }

  /**
   * 初始化页面数据（内部方法，兼容旧调用）
   * @param todoId 待办 ID
   * @param peerUid 对端成员 uid
   * @param peerNickname 对端成员昵称
   */
  private async init(todoId: number, peerUid: string, peerNickname: string): Promise<void> {
    this.todoId = todoId;
    this.peerUid = peerUid;
    this.peerNickname = peerNickname;
    this.isLoading = true;

    const success = await this.viewModel.init(todoId, peerUid);
    this.isLoading = false;

    if (!success) {
      hilog.error(0x0000, TAG, 'init failed: todoId=%{public}d peerUid=%{public}s', todoId, peerUid);
    } else {
      // 初始化成功后滚动到底部
      setTimeout(() => {
        this.scrollToBottom();
      }, 100);
    }
  }

  /**
   * 滚动到底部（最新消息）
   */
  private scrollToBottom(): void {
    this.scroller.scrollEdge(Edge.Bottom);
  }

  /**
   * 发送消息
   */
  private async handleSend(): Promise<void> {
    if (this.inputText.trim().length === 0) {
      return;
    }

    const content = this.inputText.trim();
    this.inputText = '';

    const success = await this.viewModel.sendMessage(content, this.todoId.toString());
    if (success) {
      hilog.info(0x0000, TAG, 'sendMessage success');
      setTimeout(() => {
        this.scrollToBottom();
      }, 50);
    } else {
      hilog.error(0x0000, TAG, 'sendMessage failed');
    }
  }

  build() {
    Column() {
      // ── 顶栏：对端成员信息 ──
      this.buildTopBar()

      // ── 消息区：List 反向滚动 ──
      this.buildMessageList()

      // ── 底部输入区 ──
      this.buildInputBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens ? this.tokens.bg : '#F5F7FA')
  }

  // ── 顶栏：对端成员头像 + 昵称 ──
  @Builder
  buildTopBar() {
    Row() {
      // 成员头像
      Stack() {
        SymbolGlyph(IconMapper.NAV_PROFILE)
          .fontSize(20)
          .fontColor([this.tokens ? this.tokens.primary : '#0A59F7'])
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.tokens ? this.tokens.accent : '#EBF5FF')

      // 成员昵称
      Text(this.peerNickname)
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .margin({ left: 12 })
        .attributeModifier(SKETCH_BODY)
    }
    .width('100%')
    .height(56)
    .padding({ left: SPACING.pageH, right: SPACING.pageH })
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .alignItems(VerticalAlign.Center)
    .shadow({
      radius: 4,
      color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.04)',
      offsetX: 0,
      offsetY: 2
    })
  }

  // ── 消息列表 ──
  @Builder
  buildMessageList() {
    if (this.isLoading) {
      Column() {
        Text('加载中...')
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#999999')
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ scroller: this.scroller }) {
        ForEach(this.viewModel.getMessages(), (msg: FamilyMessage) => {
          ListItem() {
            this.buildMessageBubble(msg)
          }
        }, (msg: FamilyMessage) => msg.message_id)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: SPACING.pageH, right: SPACING.pageH, top: 12, bottom: 12 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }

  // ── 消息气泡 ──
  @Builder
  buildMessageBubble(msg: FamilyMessage) {
    Row() {
      if (msg.from_uid === this.currentUid) {
        Blank()
      }

      Column() {
        // 待办卡片
        this.buildTodoCard(msg)
      }
      .constraintSize({ maxWidth: '75%' })
      .padding(12)
      .borderRadius(RADIUS.cardMd)
      .backgroundColor(msg.from_uid === this.currentUid
        ? (this.tokens ? this.tokens.primary : '#0A59F7')
        : (this.tokens ? this.tokens.bgCard : '#E8E8E8'))
      .shadow({
        radius: 4,
        color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.08)',
        offsetX: 0,
        offsetY: 1
      })

      if (msg.from_uid !== this.currentUid) {
        Blank()
      }
    }
    .width('100%')
    .margin({ bottom: 8 })
    .alignItems(VerticalAlign.Top)
  }

  // ── 待办卡片内容 ──
  @Builder
  buildTodoCard(msg: FamilyMessage) {
    Column() {
      // 消息内容
      if (msg.content !== null && msg.content.length > 0) {
        Text(msg.content)
          .fontSize(TYPO.body.size)
          .fontColor(msg.from_uid === this.currentUid
            ? '#FFFFFF'
            : (this.tokens ? this.tokens.textPrimary : '#1A1A1A'))
          .attributeModifier(SKETCH_BODY)
      }

      // 待办标题（如果是待办类型消息）
      if (msg.type === 'todo') {
        Row() {
          // 待办标题
          Text(this.viewModel.getTodoTitle())
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(FontWeight.Medium)
            .fontColor(msg.from_uid === this.currentUid
              ? 'rgba(255,255,255,0.9)'
              : (this.tokens ? this.tokens.textSecondary : '#666666'))
            .layoutWeight(1)
            .attributeModifier(SKETCH_BODY)

          // 完成状态图标
          if (this.viewModel.getIsCompleted()) {
            SymbolGlyph(IconMapper.CHECKIN_DONE)
              .fontSize(16)
              .fontColor([msg.from_uid === this.currentUid ? '#FFFFFF' : (this.tokens ? this.tokens.success : '#00C853')])
              .margin({ left: 8 })
          }

          // 提醒状态图标
          if (this.viewModel.getIsReminded()) {
            SymbolGlyph(IconMapper.BELL)
              .fontSize(16)
              .fontColor([msg.from_uid === this.currentUid ? '#FFFFFF' : (this.tokens ? this.tokens.warning : '#FFA726')])
              .margin({ left: 8 })
          }
        }
        .width('100%')
        .margin({ top: msg.content !== null && msg.content.length > 0 ? 8 : 0 })
        .alignItems(VerticalAlign.Center)
      }

      // 时间戳
      Text(this.formatTime(msg.created_at))
        .fontSize(10)
        .fontColor(msg.from_uid === this.currentUid
          ? 'rgba(255,255,255,0.7)'
          : (this.tokens ? this.tokens.textTertiary : '#999999'))
        .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(msg.from_uid === this.currentUid ? HorizontalAlign.End : HorizontalAlign.Start)
  }

  // ── 底部输入区 ──
  @Builder
  buildInputBar() {
    Row() {
      // 文字输入框
      TextInput({ text: $$this.inputText, placeholder: '输入消息...' })
        .layoutWeight(1)
        .height(40)
        .fontSize(TYPO.body.size)
        .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
        .borderRadius(20)
        .padding({ left: 16, right: 16 })
        .placeholderColor(this.tokens ? this.tokens.textTertiary : '#999999')
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .onSubmit(() => {
          this.handleSend();
        })

      // 发送按钮
      Button() {
        SymbolGlyph(IconMapper.SEND)
          .fontSize(20)
          .fontColor(['#FFFFFF'])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(this.tokens ? this.tokens.primary : '#0A59F7')
      .margin({ left: 8 })
      .onClick(() => {
        this.handleSend();
      })
      .accessibilityText('发送')
    }
    .width('100%')
    .padding({ left: SPACING.pageH, right: SPACING.pageH, top: 12, bottom: 12 })
    .backgroundColor(this.tokens ? this.tokens.bg : '#F5F7FA')
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 格式化时间戳
   */
  private formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const msgDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());

    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');

    if (msgDate.getTime() === today.getTime()) {
      return hours + ':' + minutes;
    } else if (msgDate.getTime() === today.getTime() - 86400000) {
      return '昨天 ' + hours + ':' + minutes;
    } else {
      const month = (date.getMonth() + 1).toString().padStart(2, '0');
      const day = date.getDate().toString().padStart(2, '0');
      return month + '-' + day + ' ' + hours + ':' + minutes;
    }
  }
}
