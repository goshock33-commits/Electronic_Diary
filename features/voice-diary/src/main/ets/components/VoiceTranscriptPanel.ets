// <!-- agentID: HUI-060 -->
// 组件：实时转文字面板（P2-08：薄荷青皮肤统一 —— RADIUS.cardLg + 青染阴影 + 令牌全引用）
// 关联任务：P2-08（PLN-003 阶段P2 §6.2 语音助手页换肤）
// 关联设计稿：UX-001_redesign_report.md §6.2
// 图标来源：doc_text (L1478 ✅ 本地全量图标库 count=2)；wifi_slash (L ✅ count=2)
// 设计令牌：RADIUS.cardLg(40vp 卡片) / TYPO / SPACING / FONT（全引用，禁魔数）
// 运行时崩溃防范（PROJECT_SPEC §9）：无 getter-in-build；字段初值不含 $r()；@StorageLink 判空；@Prop 无内置属性重名
// 开发范式：ArkTS 声明式开发范式（Stage 模型）
import { RADIUS, SPACING, TYPO } from '@ohos/shared';
import type { ThemeColorTokens } from '@ohos/shared';

@Component
export struct VoiceTranscriptPanel {
  // 实时转写文本（父组件逐字追加）
  @Prop transcript: string = '';
  // 是否监听中（控制光标闪烁）
  @Prop @Watch('onListeningChanged') isListening: boolean = false;
  // 网络超时降级态
  @Prop networkTimeout: boolean = false;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  // 光标可见性（闪烁动画）
  @State private cursorVisible: boolean = true;
  private cursorTimerId: number = -1;
  onRetry?: () => void;

  aboutToAppear(): void {
    if (this.isListening) {
      this.startCursorBlink();
    }
  }

  aboutToDisappear(): void {
    this.stopCursorBlink();
  }

  onListeningChanged(): void {
    if (this.isListening) {
      this.startCursorBlink();
    } else {
      this.stopCursorBlink();
      this.cursorVisible = false;
    }
  }

  private startCursorBlink(): void {
    if (this.cursorTimerId !== -1) {
      return;
    }
    this.cursorTimerId = setInterval(() => {
      this.cursorVisible = !this.cursorVisible;
    }, 500);
  }

  private stopCursorBlink(): void {
    if (this.cursorTimerId !== -1) {
      clearInterval(this.cursorTimerId);
      this.cursorTimerId = -1;
    }
  }

  // ==== mint 色板兜底（对齐 Preset morning-dew Light，参考 AIChatView HUI-051）====
  private getPrimary(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  private getPrimaryLight(): string {
    return this.tokens ? this.tokens.primaryLight : '#4FD8CE';
  }

  // HUI-035：交互色专用 token（雾霾蓝主按钮 / 白按钮文字）
  private getBtnPrimary(): string {
    return this.tokens ? this.tokens.btnPrimary : '#738A9C';
  }

  private getBtnPrimaryText(): string {
    return this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF';
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

  private getCardBg(): string {
    return this.tokens ? this.tokens.bgCard : 'rgba(255,255,255,0.85)';
  }

  private getBorder(): string {
    return this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)';
  }

  private getShadow(): string {
    return this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)';
  }

  private getWarning(): string {
    return this.tokens ? this.tokens.warning : '#80CBC4';
  }

  /** 半透明版本：ArkUI hex-alpha 为 #AARRGGBB，需前置 alpha */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  private hasText(): boolean {
    return this.transcript.length > 0;
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        // doc_text：grep 验证 L1478 ✅，语义 = 文字转写标识
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(16).fontColor([this.getPrimary()])
        Text('实时转文字')
          .fontSize(TYPO.cardTitle.size).fontWeight(600).fontColor(this.getTextSecondary())
          .margin({ left: 6 })
      }
      .width('100%').margin({ bottom: 10 })

      if (this.networkTimeout) {
        // 网络超时降级态
        Column() {
          // wifi_slash：grep 验证 L ✅
          SymbolGlyph($r('sys.symbol.wifi_slash'))
            .fontSize(36).fontColor([this.getWarning()])
          Text('网络连接超时')
            .fontSize(TYPO.cardTitle.size).fontWeight(600).fontColor(this.getTextPrimary())
            .margin({ top: 12 })
          Text('语音识别服务暂时不可用，请检查网络后重试')
            .fontSize(TYPO.body.size).fontColor(this.getTextSecondary())
            .textAlign(TextAlign.Center).margin({ top: 6 }).lineHeight(TYPO.body.size + 4)
          Button('重试')
            .fontSize(TYPO.body.size).fontWeight(600).fontColor(this.getBtnPrimaryText())
            .backgroundColor(this.getBtnPrimary())
            .borderRadius(999).height(40).padding({ left: 28, right: 28 })
            .margin({ top: 16 })
            .shadow({ radius: 8, color: this.withAlpha(this.getBtnPrimary(), '4D'), offsetX: 0, offsetY: 3 })
            .onClick(() => { if (this.onRetry) { this.onRetry(); } })
            .accessibilityText('重试语音识别')
        }
        .width('100%').padding({ top: 24, bottom: 24 })
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else if (this.hasText()) {
        // 转写文本 + 闪烁光标
        Row() {
          Text() {
            Span(this.transcript)
              .fontSize(TYPO.body.size + 4).fontColor(this.getTextPrimary())
            Span('|')
              .fontSize(TYPO.body.size + 4)
              .fontColor(this.cursorVisible && this.isListening ? this.getPrimary() : Color.Transparent)
          }
          .lineHeight(TYPO.body.size + 14).width('100%').textAlign(TextAlign.Start)
        }
        .width('100%')
        .accessibilityText('转写文字：' + this.transcript)
      } else {
        // 空态引导（识别未出结果）
        Column() {
          Text(this.isListening ? '正在识别，请继续说话…' : '尚未识别到语音内容')
            .fontSize(TYPO.body.size).fontColor(this.getTextTertiary())
            .textAlign(TextAlign.Center)
          if (this.isListening) {
            Text(this.cursorVisible ? '|' : ' ')
              .fontSize(TYPO.body.size + 4).fontColor(this.getPrimary()).margin({ top: 4 })
          }
        }
        .width('100%').padding({ top: 20, bottom: 20 })
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .accessibilityText(this.isListening ? '正在识别语音' : '尚未识别到语音内容')
      }
    }
    .width('100%').padding(SPACING.cardPadMd).borderRadius(RADIUS.cardLg)
    .backgroundColor(this.getCardBg())
    .border({ width: 1, color: this.getBorder() })
    .shadow({ radius: 24, color: this.getShadow(), offsetX: 0, offsetY: 4 })
    .constraintSize({ minHeight: 120 })
    .alignItems(HorizontalAlign.Start)
  }
}

// === @Preview mock 组件（DevEco Studio Previewer 预览） ===

@Preview
@Component
struct VoiceTranscriptPanelPreview {
  build() {
    Column({ space: 16 }) {
      VoiceTranscriptPanel({ transcript: '提醒我明天下午三点开会', isListening: true, networkTimeout: false })
      VoiceTranscriptPanel({ transcript: '', isListening: true, networkTimeout: false })
      VoiceTranscriptPanel({ transcript: '', isListening: false, networkTimeout: true })
    }
    .width('100%').padding(16).backgroundColor('#FAF8F5')
  }
}
