// agentID: HUI-001
// 任务: T037 推送状态可视化
// 组件: 推送诊断区 —— Token 状态 / 通知权限 / 推送服务 / 手动刷新
// 依赖: T035 FamilyMessageManager / T036 notification_permission_denied
// 关联规范: PROJECT_SPEC §8.2 §9（防崩溃）

import { PushManager } from '@ohos/shared';
import { FamilyMessageManager, Result, MessageGroup } from '@ohos/shared';
import { IconMapper, RADIUS, SPACING, TYPO, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';
import type { ThemeColorTokens } from '@ohos/shared';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'PushStatusDiagnostic';

/**
 * 推送状态诊断组件
 *
 * 显示内容：
 * 1. Token 状态：已获取/未获取（动态读取 PushManager.getCurrentToken()）
 * 2. 通知权限：已授权/已拒绝（读取 AppStorage['notification_permission_denied']）
 * 3. 推送服务：可用/降级轮询中（X秒间隔）（读取 FamilyMessageManager.isPushServiceAvailable()）
 * 4. 最近同步时间：显示上次刷新时间戳
 * 5. 手动刷新按钮：调用 FamilyMessageManager.refreshMessages()
 *
 * 符合规范：
 * - 状态动态绑定 @State/@StorageLink，不写死
 * - 深浅色适配：使用 ThemeManager 主题色
 * - 使用 SymbolGlyph 系统图标，禁 emoji
 * - vp 单位、状态装饰器、无 any 类型
 */
@Component
export struct PushStatusDiagnostic {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  @StorageLink('notification_permission_denied') notificationDenied: boolean = false;
  @StorageLink('message_polling_interval') pollingInterval: number = 60000;

  @State tokenStatus: string = '';
  @State tokenSyncedToCloud: boolean = false; // 云端同步状态
  @State pushServiceAvailable: boolean = true;
  @State lastSyncTime: number = 0;
  @State isRefreshing: boolean = false;

  aboutToAppear(): void {
    this.updateStatus();
  }

  build() {
    Column() {
      // 卡片标题
      this.buildCardTitle('PUSH DIAGNOSTICS', '推送诊断')

      // 诊断信息卡片
      Column() {
        // Token 状态
        this.buildStatusRow(
          'Token 状态',
          this.getTokenStatusText(),
          this.tokenStatus.length > 0 && this.tokenSyncedToCloud,
          this.getTokenStatusIcon()
        )

        this.buildDivider()

        // 通知权限
        this.buildStatusRow(
          '通知权限',
          this.notificationDenied ? '已拒绝' : '已授权',
          !this.notificationDenied,
          IconMapper.BELL
        )

        this.buildDivider()

        // 推送服务状态
        this.buildStatusRow(
          '推送服务',
          this.pushServiceAvailable
            ? '可用'
            : `降级轮询中（${Math.floor(this.pollingInterval / 1000)}秒间隔）`,
          this.pushServiceAvailable,
          this.pushServiceAvailable ? IconMapper.SUCCESS : IconMapper.WARNING
        )

        this.buildDivider()

        // 最近同步时间
        Row() {
          SymbolGlyph(IconMapper.REFRESH)
            .fontSize(18)
            .fontColor([this.tokens ? this.tokens.textSecondary : '#8A9B8A'])
            .margin({ right: 12 })

          Column() {
            Text('最近同步')
              .fontSize(TYPO.cardTitle.size)
              .fontWeight(TYPO.cardTitle.weight)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .attributeModifier(SKETCH_BODY)
            Text(this.formatSyncTime())
              .fontSize(TYPO.eyebrow.size)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
              .opacity(0.7)
              .margin({ top: 2 })
              .attributeModifier(SKETCH_BODY)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 14, bottom: 14 })
        .accessibilityText('最近同步时间：' + this.formatSyncTime())

        this.buildDivider()

        // 手动刷新按钮
        Row() {
          if (this.isRefreshing) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(this.tokens ? this.tokens.btnPrimary : '#738A9C')
              .margin({ right: 12 })
          } else {
            SymbolGlyph(IconMapper.REFRESH)
              .fontSize(18)
              .fontColor([this.tokens ? this.tokens.btnPrimary : '#738A9C'])
              .margin({ right: 12 })
          }

          Text(this.isRefreshing ? '刷新中...' : '手动刷新')
            .fontSize(TYPO.cardTitle.size)
            .fontWeight(TYPO.cardTitle.weight)
            .fontColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
            .attributeModifier(SKETCH_BODY)
            .layoutWeight(1)

          if (!this.isRefreshing) {
            SymbolGlyph(IconMapper.FORWARD)
              .fontSize(14)
              .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
          }
        }
        .width('100%')
        .padding({ top: 14, bottom: 14 })
        .onClick(() => {
          if (!this.isRefreshing) {
            this.handleRefresh();
          }
        })
        .enabled(!this.isRefreshing)
        .accessibilityText(this.isRefreshing ? '刷新中' : '手动刷新消息')
      }
      .width('100%')
      .borderRadius(RADIUS.cardLg)
      .padding(SPACING.cardPadMd)
      .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
      .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)' })
      .shadow({
        radius: 12,
        color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
        offsetX: 0,
        offsetY: 4
      })
      .margin({ bottom: SPACING.cardGap })
    }
    .width('100%')
  }

  @Builder
  buildCardTitle(en: string, cn: string) {
    Column() {
      Text(en)
        .fontSize(9)
        .fontWeight(800)
        .fontColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
        .opacity(0.7)
        .letterSpacing(2)
        .attributeModifier(SKETCH_TITLE)
      Text(cn)
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(700)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .margin({ top: 2 })
        .attributeModifier(SKETCH_TITLE)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 12 })
    .accessibilityText(cn)
  }

  @Builder
  buildDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(this.tokens ? this.tokens.divider : '#EAEAE6')
  }

  @Builder
  buildStatusRow(label: string, value: string, isOk: boolean, icon: Resource) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([isOk
          ? (this.tokens ? this.tokens.btnPrimary : '#738A9C')
          : (this.tokens ? this.tokens.warning : '#FF9800')])
        .margin({ right: 12 })

      Column() {
        Text(label)
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .attributeModifier(SKETCH_BODY)
        Text(value)
          .fontSize(TYPO.eyebrow.size)
          .fontColor(isOk
            ? (this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            : (this.tokens ? this.tokens.warning : '#FF9800'))
          .opacity(0.7)
          .margin({ top: 2 })
          .attributeModifier(SKETCH_BODY)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .accessibilityText(label + '：' + value)
  }

  /**
   * 获取 Token 状态文本
   */
  private getTokenStatusText(): string {
    if (this.tokenStatus.length === 0) {
      return '未获取';
    }
    if (!this.tokenSyncedToCloud) {
      return '已获取（云端未同步）';
    }
    return '已获取并同步';
  }

  /**
   * 获取 Token 状态图标
   */
  private getTokenStatusIcon(): Resource {
    if (this.tokenStatus.length === 0) {
      return IconMapper.ERROR;
    }
    if (!this.tokenSyncedToCloud) {
      return IconMapper.WARNING;
    }
    return IconMapper.SUCCESS;
  }

  /**
   * 更新状态（读取业务数据）
   */
  private updateStatus(): void {
    try {
      // 读取 Token 状态（PushManager.getToken() 返回当前 token，空字符串表示未获取）
      this.tokenStatus = PushManager.getInstance().getToken();

      // 读取云端同步状态
      this.tokenSyncedToCloud = PushManager.getInstance().isTokenSyncedToCloud();

      // 读取推送服务状态
      this.pushServiceAvailable = FamilyMessageManager.getInstance().isPushServiceAvailable();

      hilog.info(0x0000, TAG, 'updateStatus: token=%{public}s synced=%{public}s pushAvailable=%{public}s',
        this.tokenStatus.length > 0 ? 'yes' : 'no',
        this.tokenSyncedToCloud ? 'yes' : 'no',
        this.pushServiceAvailable ? 'yes' : 'no');
    } catch (e) {
      hilog.error(0x0000, TAG, 'updateStatus failed: %{public}s', (e as Error).message);
    }
  }

  /**
   * 手动刷新消息
   */
  private async handleRefresh(): Promise<void> {
    if (this.isRefreshing) {
      return;
    }

    this.isRefreshing = true;
    hilog.info(0x0000, TAG, 'handleRefresh: start');

    try {
      const result: Result<MessageGroup[]> = await FamilyMessageManager.getInstance().refreshMessages();

      // 更新同步时间
      this.lastSyncTime = Date.now();

      if (result.success) {
        const count: number = result.data ? result.data.length : 0;
        promptAction.showToast({
          message: `已刷新（${count} 条消息）`,
          duration: 2000
        });
        hilog.info(0x0000, TAG, 'handleRefresh: success, count=%{public}d', count);
      } else {
        promptAction.showToast({
          message: result.message ?? '刷新失败，请重试',
          duration: 2000
        });
        hilog.warn(0x0000, TAG, 'handleRefresh: failed, error=%{public}s', result.message ?? 'unknown');
      }

      // 刷新后重新读取状态
      this.updateStatus();
    } catch (e) {
      promptAction.showToast({
        message: '刷新失败，请重试',
        duration: 2000
      });
      hilog.error(0x0000, TAG, 'handleRefresh exception: %{public}s', (e as Error).message);
    } finally {
      this.isRefreshing = false;
    }
  }

  /**
   * 格式化同步时间
   */
  private formatSyncTime(): string {
    if (this.lastSyncTime === 0) {
      return '尚未同步';
    }

    const now: number = Date.now();
    const diff: number = now - this.lastSyncTime;
    const seconds: number = Math.floor(diff / 1000);

    if (seconds < 60) {
      return '刚刚';
    } else if (seconds < 3600) {
      return `${Math.floor(seconds / 60)} 分钟前`;
    } else if (seconds < 86400) {
      return `${Math.floor(seconds / 3600)} 小时前`;
    } else {
      const date: Date = new Date(this.lastSyncTime);
      return `${date.getMonth() + 1}/${date.getDate()} ${date.getHours()}:${date.getMinutes().toString().padStart(2, '0')}`;
    }
  }
}
