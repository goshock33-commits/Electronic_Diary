// <!-- agentID: HUI-060 -->
// 组件：语音监听环（P2-08：薄荷青统一皮肤 —— mint 色板 + TYPO/RADIUS/SPACING 令牌引用）
// 关联任务：P2-08（PLN-003 阶段P2 §6.2 语音助手页换肤）
// 关联设计稿：UX-001_redesign_report.md §6.2
// 图标来源：IconMapper.MIC (mic_fill ✅ L1352)；mic_slash_fill (L1360 ✅)
// 动效：三层同心圆扩散脉冲（§1.6 ping/pulse 范式），原有逻辑完整保留
// 运行时崩溃防范（PROJECT_SPEC §9）：无 getter-in-build；字段初值不含 $r()；@StorageLink 判空；@Prop 无内置属性重名
// 开发范式：ArkTS 声明式开发范式（Stage 模型）
import { RADIUS, SPACING, TYPO, IconMapper } from '@ohos/shared';
import type { ThemeColorTokens } from '@ohos/shared';

@Component
export struct VoiceListenRing {
  // 是否监听中（true=脉冲动画，false=静止）
  @Prop @Watch('onListeningChanged') isListening: boolean = false;
  // 麦克风权限是否被拒绝（true=展示禁用态）
  @Prop permissionDenied: boolean = false;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  // 三层脉冲：缩放 + 透明度递减（字段初值为纯数字，符合 §9）
  @State private ring1Scale: number = 1;
  @State private ring2Scale: number = 1;
  @State private ring3Scale: number = 1;
  @State private ring1Opacity: number = 0;
  @State private ring2Opacity: number = 0;
  @State private ring3Opacity: number = 0;
  onToggle?: (listening: boolean) => void;

  aboutToAppear(): void {
    if (this.isListening) {
      this.startPulse();
    }
  }

  /** 监听态切换：驱动脉冲动画 */
  onListeningChanged(): void {
    if (this.isListening) {
      this.startPulse();
    } else {
      this.stopPulse();
    }
  }

  /** 三层错峰扩散：缩放放大同时透明度递减（radar 脉冲），iterations=-1 无限循环，§1.6 ping/pulse */
  private startPulse(): void {
    this.ring1Opacity = 0.5;
    this.ring2Opacity = 0.5;
    this.ring3Opacity = 0.5;
    animateTo({ duration: 1600, curve: Curve.EaseOut, iterations: -1, playMode: PlayMode.Normal }, () => {
      this.ring1Scale = 2.2;
      this.ring1Opacity = 0;
    });
    animateTo({ duration: 1600, curve: Curve.EaseOut, iterations: -1, delay: 530, playMode: PlayMode.Normal }, () => {
      this.ring2Scale = 2.2;
      this.ring2Opacity = 0;
    });
    animateTo({ duration: 1600, curve: Curve.EaseOut, iterations: -1, delay: 1060, playMode: PlayMode.Normal }, () => {
      this.ring3Scale = 2.2;
      this.ring3Opacity = 0;
    });
  }

  private stopPulse(): void {
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.ring1Scale = 1;
      this.ring2Scale = 1;
      this.ring3Scale = 1;
      this.ring1Opacity = 0;
      this.ring2Opacity = 0;
      this.ring3Opacity = 0;
    });
  }

  // === 图标改普通方法（§9：Resource 返回值不放 getter-in-build）===
  // mic_fill / mic_slash_fill 均 grep 验证在本地全量图标库（L1352/L1360）
  private getMicIcon(): Resource {
    return this.permissionDenied ? $r('sys.symbol.mic_slash_fill') : IconMapper.MIC;
  }

  // ==== mint 色板兜底（对齐 Preset morning-dew Light）====
  private getPrimary(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  private getPrimaryLight(): string {
    return this.tokens ? this.tokens.primaryLight : '#4FD8CE';
  }

  // HUI-035：交互色专用 token（雾霾蓝主按钮 / 白按钮图标）
  private getBtnPrimary(): string {
    return this.tokens ? this.tokens.btnPrimary : '#738A9C';
  }

  private getBtnPrimaryText(): string {
    return this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF';
  }

  private getDanger(): string {
    return this.tokens ? this.tokens.danger : '#78909C';
  }

  private getBg(): string {
    return this.tokens ? this.tokens.bg : '#FAF8F5';
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

  private getShadow(): string {
    return this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)';
  }

  private getCoreColor(): string {
    return this.permissionDenied ? this.getDanger() : this.getBtnPrimary();
  }

  private getStatusText(): string {
    if (this.permissionDenied) {
      return '麦克风权限未开启';
    }
    return this.isListening ? '正在聆听，请说话…' : '点击开始语音输入';
  }

  /** 半透明版本：ArkUI hex-alpha 为 #AARRGGBB，需前置 alpha */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        // 三层脉冲扩散圈（监听态显示，§1.6 签到 ping/pulse 同款范式）
        if (this.isListening && !this.permissionDenied) {
          Circle({ width: 120, height: 120 })
            .fill(this.getBtnPrimary())
            .opacity(this.ring1Opacity)
            .scale({ x: this.ring1Scale, y: this.ring1Scale })
          Circle({ width: 120, height: 120 })
            .fill(this.getBtnPrimary())
            .opacity(this.ring2Opacity)
            .scale({ x: this.ring2Scale, y: this.ring2Scale })
          Circle({ width: 120, height: 120 })
            .fill(this.getBtnPrimary())
            .opacity(this.ring3Opacity)
            .scale({ x: this.ring3Scale, y: this.ring3Scale })
        }

        // 中心麦克风按钮（mic_fill / mic_slash_fill）
        Button() {
          SymbolGlyph(this.getMicIcon())
            .fontSize(48)
            .fontColor([this.getBtnPrimaryText()])
        }
        .width(120).height(120).borderRadius(60)
        .backgroundColor(this.getCoreColor())
        .shadow({ radius: 24, color: this.withAlpha(this.getCoreColor(), '55'), offsetX: 0, offsetY: 6 })
        .onClick(() => {
          if (this.permissionDenied) {
            return;
          }
          if (this.onToggle) {
            this.onToggle(!this.isListening);
          }
        })
        .accessibilityText(this.isListening ? '停止语音输入' : '开始语音输入')
      }
      .width(300).height(300)

      Text(this.getStatusText())
        .fontSize(TYPO.body.size)
        .fontWeight(TYPO.body.weight)
        .fontColor(this.permissionDenied ? this.getDanger() : this.getTextSecondary())
        .margin({ top: 8 })
        .accessibilityText(this.getStatusText())
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

// === @Preview mock 组件（DevEco Studio Previewer 预览） ===

@Preview
@Component
struct VoiceListenRingPreview {
  build() {
    Column({ space: 16 }) {
      VoiceListenRing({ isListening: true, permissionDenied: false })
      VoiceListenRing({ isListening: false, permissionDenied: false })
      VoiceListenRing({ isListening: false, permissionDenied: true })
    }
    .width('100%').padding(16).backgroundColor('#FAF8F5')
  }
}
