// <!-- agentID: HUI-041 -->
// 组件：NFC 检测区域（三层同心圆波纹扩散动画 + 中心 NFC 图标 + 搜索状态文字 + NFC 未开启错误态）
// 关联任务：F21（PLN-002 阶段8 碰一碰分享 §10.7）
// 关联设计稿：UX-001_prototype.html → page-nfc-share（NfcDetectionView）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 图标来源：harmonyos-symbol → 连接 → nfc（行1426 已验证）
// 图标来源：harmonyos-symbol → 连接 → nfc_fill（行1430 已验证）
// 图标来源：harmonyos-symbol → 符号标识 → exclamationmark_triangle_fill（行1468 已验证）
// 开发范式：ArkTS 声明式开发范式（Stage 模型）
// 运行时崩溃防范（PROJECT_SPEC §9）：无 getter-in-build（图标/颜色改普通方法）；字段初值不含 $r()；@StorageLink 判空；@Prop 无内置属性重名；animateTo 循环在 aboutToDisappear 复位
import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper } from '@ohos/shared';

@Component
export struct NfcDetectionView {
  // 是否检测中（true=波纹脉冲动画）
  @Prop @Watch('onDetectingChanged') detecting: boolean = false;
  // NFC 是否未开启（true=展示错误引导态，不播放动画）
  @Prop nfcDisabled: boolean = false;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  // 三层脉冲：缩放 + 透明度（字段初值为纯数字，符合 §9）
  @State private ring1Scale: number = 1;
  @State private ring2Scale: number = 1;
  @State private ring3Scale: number = 1;
  @State private ring1Opacity: number = 0;
  @State private ring2Opacity: number = 0;
  @State private ring3Opacity: number = 0;
  // 中心 NFC 核心点击（(重新)开始检测）
  onCoreTap?: () => void;
  // NFC 未开启态点击"去开启"
  onEnableNfc?: () => void;

  aboutToAppear(): void {
    if (this.detecting && !this.nfcDisabled) {
      this.startRipple();
    }
  }

  aboutToDisappear(): void {
    // 复位动画目标值，终止 iterations=-1 的循环残留
    this.stopRipple();
  }

  /** 检测态切换：驱动波纹动画 */
  onDetectingChanged(): void {
    if (this.detecting && !this.nfcDisabled) {
      this.startRipple();
    } else {
      this.stopRipple();
    }
  }

  private startRipple(): void {
    // 三层错峰扩散：放大同时透明度递减（雷达脉冲），iterations=-1 无限循环
    this.ring1Opacity = 0.45;
    this.ring2Opacity = 0.45;
    this.ring3Opacity = 0.45;
    animateTo({ duration: 1800, curve: Curve.EaseOut, iterations: -1, playMode: PlayMode.Normal }, () => {
      this.ring1Scale = 2.4;
      this.ring1Opacity = 0;
    });
    animateTo({ duration: 1800, curve: Curve.EaseOut, iterations: -1, delay: 600, playMode: PlayMode.Normal }, () => {
      this.ring2Scale = 2.4;
      this.ring2Opacity = 0;
    });
    animateTo({ duration: 1800, curve: Curve.EaseOut, iterations: -1, delay: 1200, playMode: PlayMode.Normal }, () => {
      this.ring3Scale = 2.4;
      this.ring3Opacity = 0;
    });
  }

  private stopRipple(): void {
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.ring1Scale = 1;
      this.ring2Scale = 1;
      this.ring3Scale = 1;
      this.ring1Opacity = 0;
      this.ring2Opacity = 0;
      this.ring3Opacity = 0;
    });
  }

  // === 颜色兜底（普通方法，非 getter；§9）===
  private getPrimary(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  private getDanger(): string {
    return this.tokens ? this.tokens.danger : '#78909C';
  }

  private getTextPrimary(): string {
    return this.tokens ? this.tokens.textPrimary : '#333333';
  }

  private getTextSecondary(): string {
    return this.tokens ? this.tokens.textSecondary : '#999999';
  }

  private getCoreColor(): string {
    // HUI-038：NFC 核心主操作圆按钮（漏网可点控件）→ 正常态 btnPrimary 雾霾蓝（原 primary 兜底青 #00C2B8）；禁用态保留 danger
    return this.nfcDisabled ? this.getDanger() : (this.tokens ? this.tokens.btnPrimary : '#738A9C');
  }

  private getStatusTitle(): string {
    if (this.nfcDisabled) {
      return 'NFC 未开启';
    }
    return this.detecting ? '正在搜索附近设备…' : '将两台设备背靠背贴近';
  }

  private getStatusHint(): string {
    if (this.nfcDisabled) {
      return '碰一碰分享需要开启 NFC，去打开后重试';
    }
    return this.detecting ? '保持贴近，识别到设备后自动连接' : '轻触下方光圈开始搜索';
  }

  /** 半透明版本：ArkUI hex-alpha 为 #AARRGGBB，需前置 alpha */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        // 三层脉冲扩散圈（检测态显示，NFC 关闭时不显示）
        if (this.detecting && !this.nfcDisabled) {
          Circle({ width: 132, height: 132 })
            .fill(this.getPrimary())
            .opacity(this.ring1Opacity)
            .scale({ x: this.ring1Scale, y: this.ring1Scale })
          Circle({ width: 132, height: 132 })
            .fill(this.getPrimary())
            .opacity(this.ring2Opacity)
            .scale({ x: this.ring2Scale, y: this.ring2Scale })
          Circle({ width: 132, height: 132 })
            .fill(this.getPrimary())
            .opacity(this.ring3Opacity)
            .scale({ x: this.ring3Scale, y: this.ring3Scale })
        }

        // 中心 NFC 核心按钮（≥48vp 触控热区，实际 132vp）
        Button() {
          SymbolGlyph(this.nfcDisabled ? IconMapper.ERROR : $r('sys.symbol.nfc'))
            .fontSize(56)
            // HUI-038：核心按钮图标→正常态 btnPrimaryText（配 btnPrimary 底）；禁用态白（配 danger 底）
            .fontColor([this.nfcDisabled ? '#FFFFFF' : (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')])
        }
        .width(132).height(132).borderRadius(66)
        .backgroundColor(this.getCoreColor())
        .shadow({ radius: 28, color: this.withAlpha(this.getCoreColor(), '55'), offsetX: 0, offsetY: 8 })
        .onClick(() => {
          if (this.nfcDisabled) {
            if (this.onEnableNfc) {
              this.onEnableNfc();
            }
            return;
          }
          if (this.onCoreTap) {
            this.onCoreTap();
          }
        })
        .accessibilityText(this.nfcDisabled ? 'NFC 未开启，点击去开启' : (this.detecting ? '正在搜索设备，点击停止' : '点击开始碰一碰搜索'))
      }
      .width(280).height(280)

      // 状态标题
      Text(this.getStatusTitle())
        .fontSize(18).fontWeight(600)
        .fontColor(this.nfcDisabled ? this.getDanger() : this.getTextPrimary())
        .margin({ top: 4 })
        .accessibilityText(this.getStatusTitle())

      // 状态提示
      Text(this.getStatusHint())
        .fontSize(14)
        .fontColor(this.getTextSecondary())
        .textAlign(TextAlign.Center).width('80%')
        .margin({ top: 8 })
        .accessibilityText(this.getStatusHint())

      // NFC 未开启 → "去开启" 引导按钮
      if (this.nfcDisabled) {
        Button('去开启 NFC')
          .fontSize(15).fontWeight(600).fontColor(Color.White)
          .backgroundColor(this.getDanger())
          .height(48).borderRadius(24).constraintSize({ minWidth: 160 })
          .padding({ left: 24, right: 24 })
          .margin({ top: 20 })
          .onClick(() => {
            if (this.onEnableNfc) {
              this.onEnableNfc();
            }
          })
          .accessibilityText('去系统设置开启 NFC')
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

// === @Preview mock 组件（DevEco Studio Previewer 预览） ===

@Preview
@Component
struct NfcDetectionViewPreview {
  build() {
    Column({ space: 24 }) {
      NfcDetectionView({ detecting: true, nfcDisabled: false })
      NfcDetectionView({ detecting: false, nfcDisabled: true })
    }
    .width('100%').padding(16).backgroundColor('#F2F2F7')
  }
}
