// <!-- agentID: HUI-061 -->
// 组件：AI 识别结果面板（场景标签 + OCR 文字 + 日记建议 + 确认/编辑/重新生成/丢弃）
// 关联任务：P2-09 手势日记流程页统一薄荷青皮肤（UX-001 §6.3）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 图标来源：harmonyos-symbol → star_fill（AI 智能建议标识，项目 IconMapper 已验证 ✅，替代 absent sparkles）
// 图标来源：harmonyos-symbol → picture（场景识别标签）
// 图标来源：harmonyos-symbol → doc_text（OCR 识别文字）
// 图标来源：harmonyos-symbol → arrow_clockwise（重新生成）
// 图标来源：harmonyos-symbol → square_and_pencil（编辑）
// 图标来源：harmonyos-symbol → checkmark（确认保存，IconMapper.CHECKMARK ✅）
// 图标来源：harmonyos-symbol → trash（丢弃）
// 设计规范：卡片 RADIUS.cardMd、标签 RADIUS.input、textarea RADIUS.input
// 运行时崩溃防范（PROJECT_SPEC §9）：字段初值不含 $r()；@StorageLink 判空；标签颜色用普通方法
import type { ThemeColorTokens } from '@ohos/shared';
import { RADIUS, IconMapper } from '@ohos/shared';

@Component
export struct AISuggestionView {
  // 多个场景标签（逗号 mock 由父组件传入 string[]）
  @Prop sceneTags: string[] = [];
  @Prop @Watch('onSuggestionChanged') suggestionText: string = '';
  @Prop ocrText: string = '';
  @Prop isProcessing: boolean = false;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  // 本地可编辑副本（TextArea 双向），aboutToAppear 同步 @Prop
  @State private editableText: string = '';
  // HUI-024: 移除硬编码彩色标签色板（青/蓝/蓝灰），改由 getTagColor() 读 theme_tokens 灰阶，随黑白手绘主题并自动深浅适配
  onConfirm?: (text: string) => void;
  onEdit?: (text: string) => void;
  onDiscard?: () => void;
  onRegenerate?: () => void;

  aboutToAppear(): void {
    this.editableText = this.suggestionText;
  }

  /** 父组件重新生成建议时同步到本地可编辑副本 */
  onSuggestionChanged(): void {
    this.editableText = this.suggestionText;
  }

  private getPrimaryColor(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  // HUI-035：交互色专用 token（雾霾蓝主按钮 / 燕麦辅助 / 白按钮文字）
  private getBtnPrimary(): string {
    return this.tokens ? this.tokens.btnPrimary : '#738A9C';
  }

  private getBtnAux(): string {
    return this.tokens ? this.tokens.btnAux : '#C6BBAE';
  }

  private getBtnPrimaryText(): string {
    return this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF';
  }

  private getTextPrimary(): string {
    return this.tokens ? this.tokens.textPrimary : '#333333';
  }

  private getTextSecondary(): string {
    return this.tokens ? this.tokens.textSecondary : '#999999';
  }

  private getTextTertiary(): string {
    return this.tokens ? this.tokens.textTertiary : '#BDBDBD';
  }

  private getCardBg(): string {
    return this.tokens ? this.tokens.bgCard : '#FAFAFA';
  }

  private getBorder(): string {
    return this.tokens ? this.tokens.border : '#E0E0E0';
  }

  private getTagColor(index: number): string {
    // HUI-024: 黑白手绘主题——用主题墨黑/二级灰/三级灰轮转替代原青蓝色板（读 token 自动深浅适配，保留 index 轮转形参不改调用点）
    const ramp: string[] = [this.getPrimaryColor(), this.getTextSecondary(), this.getTextTertiary()];
    return ramp[index % ramp.length];
  }

  /** 半透明版本：ArkUI hex-alpha 为 #AARRGGBB，需前置 alpha */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        SymbolGlyph($r('sys.symbol.star_fill'))
          .fontSize(20).fontColor([this.getPrimaryColor()])
        Text('AI 日记建议')
          .fontSize(18).fontWeight(600).fontColor(this.getTextPrimary())
          .margin({ left: 8 })
      }.width('100%').margin({ bottom: 16 })

      if (this.isProcessing) {
        // 识别中态
        Column() {
          LoadingProgress().width(32).height(32).color(this.getPrimaryColor())
          Text('正在识别场景并生成建议...')
            .fontSize(14).fontColor(this.getTextSecondary()).margin({ top: 12 })
        }
        .width('100%').padding({ top: 24, bottom: 24 })
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        // 场景识别彩色标签（多标签横向流式）
        if (this.sceneTags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.sceneTags, (tag: string, index: number) => {
              Row() {
                SymbolGlyph($r('sys.symbol.picture')).fontSize(12)
                  .fontColor([this.getTagColor(index)])
                Text(tag)
                  .fontSize(12).fontColor(this.getTagColor(index)).margin({ left: 4 })
              }
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(RADIUS.input)
              .backgroundColor(this.withAlpha(this.getTagColor(index), '1A'))
              .margin({ right: 8, bottom: 8 })
              .accessibilityText('场景标签：' + tag)
            }, (tag: string, index: number) => tag + index.toString())
          }
          .width('100%').margin({ bottom: 12 })
        }

        // OCR 识别文字
        if (this.ocrText.length > 0) {
          Row() {
            SymbolGlyph($r('sys.symbol.doc_text')).fontSize(14)
              .fontColor([this.getTextTertiary()])
            Text('识别文字：' + this.ocrText)
              .fontSize(12).fontColor(this.getTextTertiary())
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ left: 6 })
              .layoutWeight(1)
          }
          .width('100%').padding(10).borderRadius(RADIUS.input)
          .backgroundColor(this.getCardBg()).margin({ bottom: 12 })
          .accessibilityText('OCR 识别文字：' + this.ocrText)
        }

        // AI 建议正文（可编辑）
        TextArea({ text: this.editableText })
          .fontSize(15).fontColor(this.getTextPrimary())
          .backgroundColor(this.getCardBg())
          .borderRadius(RADIUS.input).width('100%').height(140).padding(12)
          .border({ width: 1, color: this.getBorder() })
          .onChange((value: string) => { this.editableText = value; })
          .accessibilityText('AI 日记建议正文，可编辑')

        // 操作按钮：丢弃 / 重新生成 / 编辑 / 确认保存
        Row() {
          Button() {
            Row() {
              SymbolGlyph($r('sys.symbol.trash')).fontSize(14).fontColor([this.getTextTertiary()])
              Text('丢弃').fontSize(13).fontColor(this.getTextTertiary()).margin({ left: 4 })
            }
          }
          .backgroundColor(Color.Transparent).height(44).padding({ left: 8, right: 8 })
          .onClick(() => { if (this.onDiscard) { this.onDiscard(); } })
          .accessibilityText('丢弃建议')

          Button() {
            Row() {
              SymbolGlyph(IconMapper.REFRESH).fontSize(14).fontColor([this.getTextSecondary()])
              Text('重新生成').fontSize(13).fontColor(this.getTextSecondary()).margin({ left: 4 })
            }
          }
          .backgroundColor(this.getBtnAux()).borderRadius(22).height(44)
          .padding({ left: 12, right: 12 }).margin({ left: 8 })
          .onClick(() => { if (this.onRegenerate) { this.onRegenerate(); } })
          .accessibilityText('重新生成建议')

          Blank()

          Button() {
            Row() {
              SymbolGlyph(IconMapper.BOOKMARK).fontSize(14).fontColor([this.getPrimaryColor()])
              Text('编辑').fontSize(13).fontColor(this.getPrimaryColor()).margin({ left: 4 })
            }
          }
          .backgroundColor(this.getBtnAux()).borderRadius(22).height(44)
          .padding({ left: 14, right: 14 })
          .onClick(() => { if (this.onEdit) { this.onEdit(this.editableText); } })
          .accessibilityText('编辑建议')

          Button() {
            Row() {
              SymbolGlyph(IconMapper.CHECKMARK).fontSize(14).fontColor([this.getBtnPrimaryText()])
              Text('确认保存').fontSize(13).fontWeight(600).fontColor(this.getBtnPrimaryText()).margin({ left: 4 })
            }
          }
          .backgroundColor(this.getBtnPrimary()).borderRadius(22).height(44)
          .padding({ left: 14, right: 14 }).margin({ left: 8 })
          .onClick(() => { if (this.onConfirm) { this.onConfirm(this.editableText); } })
          .accessibilityText('确认保存日记')
        }.width('100%').margin({ top: 16 })
      }
    }
    .width('100%').borderRadius(RADIUS.cardMd).padding(20)
    .backgroundColor(this.tokens ? this.tokens.bgCard : 'rgba(255,255,255,0.92)')
    .backdropBlur(12)
    .border({ width: 1, color: this.getBorder() })
    .shadow({ radius: 24, color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.1)', offsetX: 0, offsetY: -4 })
    .accessibilityGroup(true)
  }
}

// === @Preview mock 组件（DevEco Studio Previewer 预览） ===

@Preview
@Component
struct AISuggestionViewPreview {
  build() {
    Column() {
      AISuggestionView({
        sceneTags: ['风景', '户外', '晴天'],
        suggestionText: '2026年7月8日 星期二 15:30\n拍摄了一张风景照片。\n今天...',
        ocrText: '欢迎光临',
        isProcessing: false
      })
    }.width('100%').padding(16).backgroundColor('#F2F2F7')
  }
}
