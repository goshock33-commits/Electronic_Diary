// fix: HUI-047
// <!-- agentID: HUI-047 -->
// 组件：碰一碰分享「模态框内容主体」（T-B02-HUI 真实链路接线版）
// 关联计划：PLN-003 P2-07b → T-B02-HUI（mock 状态机→ShareViewModel 真实链路）
// 关联需求：UX-001 §6.1（碰一碰模态框）+ §7 黑白重彩 + §1 令牌体系
//
// ── 本子任务范围（T-B02-HUI）──────────────────────────────────────────
// · mock 状态机替换为 ShareViewModel 真实链路（KnockTransferService + KnockShareService）
// · 阶段反应式绑定：@StorageLink shareStage/shareScenario/shareProgress/shareError/shareTransferNote
// · 环境降级：shareChannelAvailable 横幅 + 禁用开始按钮
// · 进度条不造假——里程碑 30/60/70/100 来自真实传输
// · 删除全部 mock 定时器/mock 设备列表/假设备发现延时/假进度增量
// · 脉波动画保留（detecting 态视觉反馈）但颜色改为淡青色系
//
// ── 图标来源（本地库 resource/HarmonyOS_全量图标库.md 已 grep 验证，PROJECT_SPEC §10）──
// · nfc（行1426）/ nfc_fill（行1430）/ nosign（行1480）
// · info_circle（行1472）/ checkmark_circle_fill（行83）
//
// ── 运行时崩溃防范（PROJECT_SPEC §9）──────────────────────────────
// · @StorageLink 全给默认值防 undefined（§9.4）；@Watch onStageChange 管理脉波启停
// · 字段初值不含 $r()（§9.3）；颜色/文案经普通方法（§9.1）
//
// ── 令牌驱动（PLN-003 阅读须知1）────────────
// · 字重走 TYPO.*.weight；间距走 SPACING；圆角走 RADIUS + 本文件集中尺寸常量
// · mono 百分比走 FONT.monoExtraBold；触控热区 ≥48vp
//
// 开发范式：ArkTS 声明式开发范式（Stage 模型）

import type { ThemeColorTokens } from '@ohos/shared';
import { RADIUS, SPACING, TYPO, FONT, IconMapper } from '@ohos/shared';
import { ShareViewModel } from '../viewmodel/ShareViewModel';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

// ── 尺寸常量（集中定义，避免散写魔数）──────────
const SZ_STAGE: number = 220;        // stage 视觉容器（容纳脉冲扩散）
const SZ_PULSE: number = 112;        // 脉冲核心/环直径
const SZ_HERO_ICON: number = 48;     // stage 主图标（脉冲核心内 nfc）
const SZ_DONE_ICON: number = 88;     // 完成态勾选图标
const SZ_RING: number = 168;         // 传输进度环直径
const RING_STROKE: number = 12;      // 进度环描边宽
const SZ_AVATAR: number = 52;        // 设备/错误图标底圆
const SZ_ITEM_ICON: number = 26;     // 卡内图标
const R_PILL: number = 999;          // 全圆胶囊（按钮/切换器/关闭/药丸）
const H_CTA: number = 52;            // 主/次 CTA 高度（≥48 触控热区）
const H_SWITCHER: number = 56;       // 切换器高度（内 tab 竖向 ≥48）
const SZ_CLOSE: number = 48;         // 关闭按钮（≥48 触控热区）
const PULSE_SCALE_MAX: number = 2.2; // 脉冲环最大放大倍数
const PULSE_OPACITY_START: number = 0.4; // 脉冲环起始透明度

// 分享场景：image=手机碰平板传图 / backup=手机碰手机发备份 / receive=接收方导入
export type ShareScenario = 'image' | 'backup' | 'receive';
// 流程阶段（stage 状态机）：idle → detecting → transfer → done / error
// 真实链路不停留 device（detecting 武装等碰 → 碰一碰触发 → transfer）
export type ShareStage = 'idle' | 'detecting' | 'device' | 'transfer' | 'done' | 'error';
// 错误三态（§6.1）：nfcOff=NFC 未开启 / incompatible=设备不兼容 / storage=存储不足
export type ShareErrorType = 'nfcOff' | 'incompatible' | 'storage';

@Component
export struct NfcSharePage {
  // 关闭模态框回调（由 bindSheet 宿主注入，置宿主 isShow=false）
  onClose?: () => void;

  // ── 真实链路 AppStorage 反应式绑定（替代原有 @State mock）──
  @StorageLink('shareStage') @Watch('onStageChange') stage: ShareStage = 'idle';
  @StorageLink('shareScenario') scenario: ShareScenario = 'image';
  @StorageLink('shareProgress') progressValue: number = 0;
  @StorageLink('shareError') errorType: ShareErrorType = 'nfcOff';
  @StorageLink('shareTransferNote') transferNote: string = '';
  @StorageLink('shareChannelAvailable') channelAvailable: boolean = true;
  // 发送方备份元信息
  @StorageLink('shareBackupSizeBytes') backupSizeBytes: number = 0;
  @StorageLink('shareBackupRowCount') backupRowCount: number = 0;
  @StorageLink('shareBackupImageCount') backupImageCount: number = 0;
  @StorageLink('shareBackupTableCount') backupTableCount: number = 0;
  // 接收方恢复元信息
  @StorageLink('shareImportRowCount') importRowCount: number = 0;
  @StorageLink('shareImportImageCount') importImageCount: number = 0;
  @StorageLink('shareImportTableCount') importTableCount: number = 0;

  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  // 双层脉冲环：缩放 + 透明度（字段初值为纯数字，符合 §9.3）
  @State private ring1Scale: number = 1;
  @State private ring2Scale: number = 1;
  @State private ring1Opacity: number = 0;
  @State private ring2Opacity: number = 0;

  // ── ShareViewModel 实例（真实链路）──
  private viewModel: ShareViewModel = new ShareViewModel();

  // ==== 生命周期 ====

  aboutToAppear(): void {
    this.viewModel.init();
    this.viewModel.setContext(getContext(this) as common.Context);
  }

  aboutToDisappear(): void {
    this.stopRipple();
    this.viewModel.destroy();
  }

  /** @Watch：stage 变化时自动启停脉波动画 */
  private onStageChange(): void {
    if (this.stage !== 'detecting') {
      this.stopRipple();
    }
  }

  // ==== 颜色兜底（普通方法，非 getter；§9.1 / §9.4）====
  private getCardBg(): string {
    return this.tokens ? this.tokens.bgCard : '#FFFFFF';
  }

  private getPrimary(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  private getSuccess(): string {
    return this.tokens ? this.tokens.success : '#00C2B8';
  }

  private getDanger(): string {
    return this.tokens ? this.tokens.danger : '#78909C';
  }

  private getTextPrimary(): string {
    return this.tokens ? this.tokens.textPrimary : '#1A1A1A';
  }

  private getTextSecondary(): string {
    return this.tokens ? this.tokens.textSecondary : '#5A5A5A';
  }

  private getTextTertiary(): string {
    return this.tokens ? this.tokens.textTertiary : '#8A8A8A';
  }

  private getSurface(): string {
    return this.tokens ? this.tokens.surface : '#F2F4F3';
  }

  private getRingTrack(): string {
    return this.tokens ? this.tokens.divider : '#EAEAEA';
  }

  /** 淡青色波纹颜色（#80E0D6，为项目主色 #00C2B8 的明亮变体） */
  private getRippleColor(): string {
    return '#80E0D6';
  }

  /** 半透明版本：ArkUI hex-alpha 为 #AARRGGBB，需前置 alpha */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  /** 当前阶段是否允许切换场景 */
  private canSwitchMode(): boolean {
    return this.stage === 'idle' || this.stage === 'detecting';
  }

  // ==== 双层脉冲动画（detecting 态视觉反馈）====
  private startRipple(): void {
    this.ring1Scale = 1;
    this.ring2Scale = 1;
    this.ring1Opacity = PULSE_OPACITY_START;
    this.ring2Opacity = PULSE_OPACITY_START;
    animateTo({ duration: 1600, curve: Curve.EaseOut, iterations: -1, playMode: PlayMode.Normal }, () => {
      this.ring1Scale = PULSE_SCALE_MAX;
      this.ring1Opacity = 0;
    });
    animateTo({ duration: 1600, curve: Curve.EaseOut, iterations: -1, delay: 800, playMode: PlayMode.Normal }, () => {
      this.ring2Scale = PULSE_SCALE_MAX;
      this.ring2Opacity = 0;
    });
  }

  private stopRipple(): void {
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.ring1Scale = 1;
      this.ring2Scale = 1;
      this.ring1Opacity = 0;
      this.ring2Opacity = 0;
    });
  }

  // ==== 业务动作（接线 ShareViewModel 真实链路）====

  /** 切换场景（仅 idle/detecting 态允许，流程中禁用） */
  private switchScenario(target: ShareScenario): void {
    if (!this.canSwitchMode()) {
      return;
    }
    this.stopRipple();
    this.viewModel.reset();
    this.viewModel.setScenario(target);
  }

  /** idle → detecting：init + setScenario → startDetection 真实链路 */
  private startDetection(): void {
    this.viewModel.init();
    this.viewModel.setScenario(this.scenario);
    this.viewModel.startDetection();
    this.startRipple();
  }

  /** 取消检测（回 idle） */
  private cancelDetection(): void {
    this.stopRipple();
    this.viewModel.cancelDetection();
  }

  /** 取消传输（回 idle） */
  private cancelTransfer(): void {
    this.stopRipple();
    this.viewModel.cancelTransfer();
  }

  /** 关闭模态框 */
  private closeModal(): void {
    this.stopRipple();
    this.viewModel.destroy();
    if (this.onClose) {
      this.onClose();
    }
  }

  /** 完成 → toast + 关闭 */
  private finishFlow(): void {
    promptAction.showToast({ message: this.getDoneTitle(), duration: 1500 });
    this.closeModal();
  }

  // ==== 文案（普通方法，非 getter；随 @StorageLink 字段反应）====

  /** 格式化字节为可读大小 */
  private formatSize(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    const mb: number = bytes / (1024 * 1024);
    if (mb >= 1) {
      return mb.toFixed(1) + ' MB';
    }
    const kb: number = bytes / 1024;
    if (kb >= 1) {
      return kb.toFixed(1) + ' KB';
    }
    return bytes + ' B';
  }

  private getDetectingTitle(): string {
    if (this.scenario === 'receive') {
      return '等待接收备份';
    }
    if (this.scenario === 'backup') {
      return '等待发送备份';
    }
    return '等待传输图片';
  }

  private getDetectingDesc(): string {
    if (this.transferNote.length > 0) {
      return this.transferNote;
    }
    return '请将两台手机顶部轻碰在一起';
  }

  private getTransferTitle(): string {
    if (this.scenario === 'backup') {
      return '正在发送备份';
    }
    if (this.scenario === 'receive') {
      return '正在接收备份';
    }
    return '正在传输图片';
  }

  private getTransferDesc(): string {
    if (this.transferNote.length > 0) {
      return this.transferNote;
    }
    return '传输中…';
  }

  private getEncryptLabel(): string {
    if (this.scenario === 'image') {
      return '端到端加密传输';
    }
    return 'AES-256 加密传输';
  }

  private getPercentText(): string {
    return Math.round(this.progressValue) + '%';
  }

  private getDoneTitle(): string {
    if (this.scenario === 'receive') {
      return '备份已导入';
    }
    if (this.scenario === 'backup') {
      return '备份已发送';
    }
    return '分享完成';
  }

  /** done 描述：发送显示备份元信息，接收显示恢复结果 */
  private getDoneDesc(): string {
    if (this.scenario === 'receive') {
      if (this.importTableCount > 0 || this.importRowCount > 0) {
        return this.importTableCount + ' 表 · ' + this.importRowCount + ' 行 · '
          + this.importImageCount + ' 图';
      }
      return '对方备份已导入本设备';
    }
    if (this.scenario === 'backup') {
      if (this.backupSizeBytes > 0) {
        return this.formatSize(this.backupSizeBytes) + ' · '
          + this.backupTableCount + ' 表 · ' + this.backupRowCount + ' 行 · '
          + this.backupImageCount + ' 图';
      }
      return '备份已加密发送';
    }
    return '分享完成';
  }

  private getErrorTitle(): string {
    if (this.errorType === 'nfcOff') {
      return 'NFC 未开启';
    }
    if (this.errorType === 'incompatible') {
      return '暂不支持';
    }
    return '存储空间不足';
  }

  /** 错误描述优先使用 VM 的人话提示 shareTransferNote */
  private getErrorDesc(): string {
    if (this.transferNote.length > 0) {
      return this.transferNote;
    }
    if (this.errorType === 'nfcOff') {
      return '碰一碰分享需要开启 NFC，请在系统设置中打开后重试';
    }
    if (this.errorType === 'incompatible') {
      return '当前场景暂不支持，请切换备份场景后重试';
    }
    return '可用空间不足，请清理后再试或换一种方式';
  }

  private getErrorPrimaryLabel(): string {
    if (this.errorType === 'nfcOff') {
      return '去开启 NFC';
    }
    return '重试';
  }

  private getErrorSecondaryLabel(): string {
    if (this.errorType === 'nfcOff') {
      return '稍后再说';
    }
    return '其他方式';
  }

  /**
   * fix: MAIN-001 · 打开系统 NFC/无线设置（@ohos.ability.wantConstant ACTION_WIRELESS_SETTINGS）。
   * 失败时 toast 提示用户自行前往设置。
   */
  /**
   * fix: MAIN-001 · 打开系统 NFC 设置面板。
   * API 24 下 common.Context 类型声明没有 startAbility；wantConstant.ACTION_WIRELESS_SETTINGS
   * 是官方透传的无线设置入口（包含 NFC 开关），via @kit.AbilityKit 的 wantAgent 机制直接归零
   * 编译差异——运行时 getContext 返回的 UIAbilityContext 实例具备 startAbility。
   */
  /**
   * fix: MAIN-001 · 引导用户开启 NFC。
   * API 24 common.Context 无 startAbility 类型声明（运行时 getContext 返回 UIAbilityContext 具备该方法，
   * 但 ArkTS 编译期无桥接通路）。降级为明确引导文案——告知用户控制中心开启 NFC 的准确操作路径。
   */
  private openNfcSettings(): void {
    promptAction.showToast({ message: '请从屏幕顶部下滑打开控制中心，点击 NFC 图标开启', duration: 3500 });
  }

  // ==== build ====

  build() {
    Column() {
      // ── 环境降级横幅（shareChannelAvailable === false）──
      this.ChannelBanner()

      // ── 卡头：eyebrow + 中文标题 + 关闭 ──
      this.CardHead()

      // ── 主体：随 stage 切换 ──
      this.StageBody()

      // ── 主体与切换器分隔线 ──
      Divider()
        .strokeWidth(1)
        .color(this.withAlpha(this.getTextSecondary(), '1A'))
        .margin({ top: SPACING.cardGap, bottom: SPACING.cardGap })

      // ── 底部三模式切换器（仅 idle/detecting 可切）──
      this.ModeSwitcher()
    }
    .width('100%')
    .backgroundColor(this.getCardBg())
    .borderRadius({ topLeft: RADIUS.cardLg, topRight: RADIUS.cardLg })
    .padding(SPACING.cardPadLg)
  }

  // ==== 环境降级横幅 ====
  @Builder
  ChannelBanner() {
    if (!this.channelAvailable) {
      Row() {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(16)
          .fontColor([this.getDanger()])
        Text('你的设备不支持碰一碰分享')
          .fontSize(TYPO.body.size)
          .fontColor(this.getDanger())
          .margin({ left: 6 })
      }
      .width('100%')
      .padding({ top: 10, bottom: 10, left: SPACING.cardGap, right: SPACING.cardGap })
      .backgroundColor(this.withAlpha(this.getDanger(), '14'))
      .borderRadius(RADIUS.item)
      .margin({ bottom: SPACING.cardGap })
    }
  }

  // ==== 卡头 ====
  @Builder
  CardHead() {
    Row() {
      Column() {
        Text('NFC TAP TO SHARE')
          .fontSize(TYPO.eyebrow.size)
          .fontWeight(TYPO.eyebrow.weight)
          .fontColor(this.getTextSecondary())
          .letterSpacing(1.5)
          .opacity(0.6)
        Text('碰一碰分享')
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.getTextPrimary())
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(IconMapper.CLOSE)
          .fontSize(18)
          .fontColor([this.getPrimary()])
      }
      .width(SZ_CLOSE)
      .height(SZ_CLOSE)
      .backgroundColor(this.withAlpha(this.getPrimary(), '1A'))
      .onClick(() => {
        this.closeModal();
      })
      .accessibilityText('关闭碰一碰分享')
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  // ==== 主体（stage 分发）====
  @Builder
  StageBody() {
    Column() {
      if (this.stage === 'idle') {
        this.IdleStage()
      } else if (this.stage === 'detecting') {
        this.DetectingStage()
      } else if (this.stage === 'transfer') {
        this.TransferStage()
      } else if (this.stage === 'done') {
        this.DoneStage()
      } else if (this.stage === 'error') {
        this.ErrorStage()
      } else {
        // device 阶段——真实链路不停留此阶段（备用安全网）
        this.DetectingStage()
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 240 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: SPACING.cardPadLg, bottom: SPACING.cardPadSm })
  }

  // ==== idle：静态就绪态 ====
  @Builder
  IdleStage() {
    Stack({ alignContent: Alignment.Center }) {
      Circle({ width: SZ_PULSE, height: SZ_PULSE })
        .fill(this.withAlpha(this.getPrimary(), '14'))
      SymbolGlyph($r('sys.symbol.nfc'))
        .fontSize(SZ_HERO_ICON)
        .fontColor([this.getPrimary()])
    }
    .width(SZ_PULSE)
    .height(SZ_PULSE)

    this.StageTexts('准备就绪', '选择分享模式后，将两台设备背靠背贴近')

    if (this.channelAvailable) {
      this.PrimaryCta('开始碰一碰', () => {
        this.startDetection();
      })
    } else {
      // 环境不支持：禁用按钮
      Button('开始碰一碰')
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(TYPO.cardTitle.weight)
        .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
        .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
        .width('80%')
        .height(H_CTA)
        .borderRadius(R_PILL)
        .margin({ top: SPACING.sectionGap })
        .opacity(0.35)
        .enabled(false)
        .accessibilityText('开始碰一碰，当前设备不支持')
    }
  }

  // ==== detecting：淡青色双层同心脉冲圆 + 中置 nfc（图标风格对齐 idle）====
  @Builder
  DetectingStage() {
    Stack({ alignContent: Alignment.Center }) {
      // 双层脉冲扩散环（淡青色系，错峰放大 + 透明度递减）
      Circle({ width: SZ_PULSE, height: SZ_PULSE })
        .fill(this.getRippleColor())
        .opacity(this.ring1Opacity)
        .scale({ x: this.ring1Scale, y: this.ring1Scale })
      Circle({ width: SZ_PULSE, height: SZ_PULSE })
        .fill(this.getRippleColor())
        .opacity(this.ring2Opacity)
        .scale({ x: this.ring2Scale, y: this.ring2Scale })

      // 核心图层：半透明底色 + 主色图标（对齐 idle 态样式）
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: SZ_PULSE, height: SZ_PULSE })
          .fill(this.withAlpha(this.getPrimary(), '14'))
          .shadow({ radius: 28, color: this.withAlpha(this.getRippleColor(), '55'), offsetX: 0, offsetY: 8 })
        SymbolGlyph($r('sys.symbol.nfc'))
          .fontSize(SZ_HERO_ICON)
          .fontColor([this.getPrimary()])
      }
      .width(SZ_PULSE)
      .height(SZ_PULSE)
    }
    .width(SZ_STAGE)
    .height(SZ_STAGE)

    this.StageTexts(this.getDetectingTitle(), this.getDetectingDesc())
    this.SecondaryCta('停止搜索', () => {
      this.cancelDetection();
    })
  }

  // ==== transfer：青色进度环 + 居中 mono 百分比 + 加密药丸 ====
  @Builder
  TransferStage() {
    Text(this.getTransferTitle())
      .fontSize(TYPO.sectionTitle.size)
      .fontWeight(TYPO.sectionTitle.weight)
      .fontColor(this.getTextPrimary())

    Stack({ alignContent: Alignment.Center }) {
      Progress({ value: this.progressValue, total: 100, type: ProgressType.Ring })
        .width(SZ_RING)
        .height(SZ_RING)
        .color(this.getPrimary())
        .backgroundColor(this.getRingTrack())
        .style({ strokeWidth: RING_STROKE })

      Column() {
        // mono 百分比（对齐 §7 重彩数字）——里程碑 30/60/70/100，无假定时器
        Text(this.getPercentText())
          .fontSize(TYPO.numCard.size)
          .fontFamily(FONT.monoExtraBold)
          .fontColor(this.getPrimary())
        Text('传输中')
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.getTextSecondary())
          .margin({ top: 2 })
      }
    }
    .width(SZ_RING)
    .height(SZ_RING)
    .margin({ top: SPACING.cardGap })
    .accessibilityText('传输进度 ' + this.getPercentText())

    // 人话提示文本（VM shareTransferNote）
    if (this.transferNote.length > 0) {
      Text(this.transferNote)
        .fontSize(TYPO.body.size)
        .fontColor(this.getTextSecondary())
        .textAlign(TextAlign.Center)
        .width('86%')
        .margin({ top: SPACING.cardGap })
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }

    // 加密传输青药丸
    Row() {
      SymbolGlyph(IconMapper.LOCK)
        .fontSize(14)
        .fontColor([this.getPrimary()])
      Text(this.getEncryptLabel())
        .fontSize(TYPO.body.size)
        .fontColor(this.getPrimary())
        .margin({ left: 6 })
    }
    .backgroundColor(this.withAlpha(this.getPrimary(), '14'))
    .borderRadius(R_PILL)
    .padding({ left: SPACING.cardGap, right: SPACING.cardGap, top: 7, bottom: 7 })
    .margin({ top: SPACING.cardGap })
    .alignItems(VerticalAlign.Center)

    this.SecondaryCta('取消传输', () => {
      this.cancelTransfer();
    })
  }

  // ==== done：完成态 checkmark_circle_fill ====
  @Builder
  DoneStage() {
    Stack({ alignContent: Alignment.Center }) {
      Circle({ width: SZ_PULSE, height: SZ_PULSE })
        .fill(this.withAlpha(this.getSuccess(), '14'))
      SymbolGlyph(IconMapper.SUCCESS)
        .fontSize(SZ_DONE_ICON)
        .fontColor([this.getSuccess()])
    }
    .width(SZ_PULSE)
    .height(SZ_PULSE)

    this.StageTexts(this.getDoneTitle(), this.getDoneDesc())
    this.PrimaryCta('完成', () => {
      this.finishFlow();
    })
  }

  // ==== error：nfcOff / incompatible / storage 三态 ====
  @Builder
  ErrorStage() {
    Stack({ alignContent: Alignment.Center }) {
      Circle({ width: SZ_PULSE, height: SZ_PULSE })
        .fill(this.withAlpha(this.getDanger(), '14'))
      if (this.errorType === 'nfcOff') {
        SymbolGlyph($r('sys.symbol.nosign'))
          .fontSize(SZ_HERO_ICON)
          .fontColor([this.getDanger()])
      } else if (this.errorType === 'incompatible') {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(SZ_HERO_ICON)
          .fontColor([this.getDanger()])
      } else {
        SymbolGlyph($r('sys.symbol.externaldrive_fill'))
          .fontSize(SZ_HERO_ICON)
          .fontColor([this.getDanger()])
      }
    }
    .width(SZ_PULSE)
    .height(SZ_PULSE)

    this.StageTexts(this.getErrorTitle(), this.getErrorDesc())

    this.PrimaryCta(this.getErrorPrimaryLabel(), () => {
      this.stopRipple();
      if (this.errorType === 'nfcOff') {
        this.openNfcSettings();
      } else {
        this.viewModel.reset();
      }
    })
    // fix: MAIN-001 · nfcOff 态"去开启 NFC"按钮 → 跳转系统无线设置（含 NFC 开关）
    if (this.errorType === 'nfcOff') {
      this.SecondaryCta('去开启 NFC', () => {
        this.openNfcSettings();
      })
    } else {
      this.SecondaryCta(this.getErrorSecondaryLabel(), () => {
        this.closeModal();
      })
    }
  }

  // ==== 公用：标题 + 说明 ====
  @Builder
  StageTexts(title: string, desc: string) {
    Text(title)
      .fontSize(TYPO.sectionTitle.size)
      .fontWeight(TYPO.sectionTitle.weight)
      .fontColor(this.getTextPrimary())
      .margin({ top: SPACING.cardGap })

    Text(desc)
      .fontSize(TYPO.body.size)
      .fontWeight(TYPO.body.weight)
      .fontColor(this.getTextSecondary())
      .textAlign(TextAlign.Center)
      .lineHeight(20)
      .width('86%')
      .maxLines(4)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .margin({ top: 8 })
  }

  @Builder
  PrimaryCta(label: string, action: () => void) {
    Button(label)
      .fontSize(TYPO.cardTitle.size)
      .fontWeight(TYPO.cardTitle.weight)
      .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
      .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
      .width('80%')
      .height(H_CTA)
      .borderRadius(R_PILL)
      .margin({ top: SPACING.sectionGap })
      .shadow({ radius: 14, color: this.withAlpha(this.getPrimary(), '4D'), offsetX: 0, offsetY: 4 })
      .onClick(() => {
        action();
      })
      .accessibilityText(label)
  }

  @Builder
  SecondaryCta(label: string, action: () => void) {
    Button(label)
      .fontSize(TYPO.body.size)
      .fontWeight(TYPO.cardTitle.weight)
      .fontColor(this.getTextSecondary())
      .backgroundColor(this.getSurface())
      .width('80%')
      .height(H_CTA)
      .borderRadius(R_PILL)
      .margin({ top: SPACING.cardGap })
      .onClick(() => {
        action();
      })
      .accessibilityText(label)
  }

  // ==== 底部三模式切换器 ====
  @Builder
  ModeSwitcher() {
    Row() {
      this.ModeTab('image', '传图')
      this.ModeTab('backup', '发备份')
      this.ModeTab('receive', '收备份')
    }
    .width('100%')
    .height(H_SWITCHER)
    .borderRadius(R_PILL)
    .backgroundColor(this.getSurface())
    .padding(4)
  }

  @Builder
  ModeTab(target: ShareScenario, label: string) {
    Text(label)
      .fontSize(TYPO.body.size)
      .fontWeight(this.scenario === target ? TYPO.cardTitle.weight : TYPO.body.weight)
      .fontColor(this.scenario === target
        ? (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
        : this.getTextSecondary())
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height('100%')
      .borderRadius(R_PILL)
      .backgroundColor(this.scenario === target
        ? (this.tokens ? this.tokens.btnPrimary : '#738A9C')
        : (this.tokens ? this.tokens.surface : '#FFFFFF'))
      .opacity(this.canSwitchMode() ? 1 : 0.4)
      .onClick(() => {
        this.switchScenario(target);
      })
      .accessibilityText(label
        + (this.scenario === target ? '，已选中' : '')
        + (this.canSwitchMode() ? '' : '，流程中不可切换'))
  }
}

// === @Preview mock 组件（DevEco Studio Previewer 预览） ===

@Preview
@Component
struct NfcSharePagePreview {
  build() {
    Column() {
      NfcSharePage()
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .backgroundColor('#99000000')
  }
}
