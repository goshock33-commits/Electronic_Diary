// <!-- agentID: HUI-060 -->
// 组件：语音识别结果确认面板（P2-08：薄荷青皮肤统一 —— RADIUS.cardLg + 青染阴影 + 令牌全引用）
// 关联任务：P2-08（PLN-003 阶段P2 §6.2 语音助手页换肤）
// 关联设计稿：UX-001_redesign_report.md §6.2
// 图标来源：IconMapper.SUCCESS (checkmark_circle_fill ✅), IconMapper.ERROR (exclamationmark_triangle_fill ✅ L1468)
//     square_and_pencil (L1598 ✅), checkmark (L ✅), xmark (L ✅), bookmark (L61 ✅)
//     calendar (L ✅), clock (L ✅), map (L ✅)
// 设计令牌：RADIUS.cardLg(40vp 卡片) / RADIUS.item(16vp 内分组) / RADIUS.input(12vp 标签)
//           TYPO / SPACING / 青染 shadow (mint 低透明度 rgba(0,194,184,...))
// 运行时崩溃防范（PROJECT_SPEC §9）：无 getter-in-build；字段初值不含 $r()；@StorageLink 判空；@Prop 无内置属性重名
// 开发范式：ArkTS 声明式开发范式（Stage 模型）
import { RADIUS, SPACING, TYPO, IconMapper } from '@ohos/shared';
import type { ThemeColorTokens } from '@ohos/shared';

// 待办结构（AI 提取字段），元素类型可推断，字段均为字符串
export interface VoiceTodoFields {
  title: string;
  type: string;
  date: string;
  time: string;
  location: string;
}

@Component
export struct VoiceResultPanel {
  // 面板模式：'todo' = 语音添加待办，'diary' = 语音写日记
  @Prop mode: string = 'todo';
  // 待办模式：AI 提取的字段（默认空对象，父组件传入 mock）
  @Prop todoFields: VoiceTodoFields | null = null;
  // 日记模式：转写正文
  @Prop @Watch('onDiaryTextChanged') diaryText: string = '';
  // 低置信度标记（true=展示二次确认提示）
  @Prop lowConfidence: boolean = false;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  // 日记正文可编辑副本
  @State private editableDiary: string = '';
  onConfirmTodo?: (fields: VoiceTodoFields) => void;
  onConfirmDiary?: (text: string) => void;
  onEdit?: () => void;
  onCancel?: () => void;

  aboutToAppear(): void {
    this.editableDiary = this.diaryText;
  }

  onDiaryTextChanged(): void {
    this.editableDiary = this.diaryText;
  }

  // ==== mint 色板兜底（对齐 Preset morning-dew Light，参考 AIChatView HUI-051）====
  private getPrimary(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  private getPrimaryLight(): string {
    return this.tokens ? this.tokens.primaryLight : '#4FD8CE';
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

  private getSurface(): string {
    return this.tokens ? this.tokens.surface : '#FFFFFF';
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

  private getTitle(): string {
    return this.mode === 'diary' ? '语音写日记' : '语音添加待办';
  }

  /** 待办类型中文映射（type：exam/homework/meeting/deadline/general） */
  private getTypeLabel(type: string): string {
    const map: Record<string, string> = {
      'exam': '考试',
      'homework': '作业',
      'meeting': '会议',
      'deadline': '截止',
      'general': '普通'
    };
    return map[type] ?? '普通';
  }

  /** 半透明版本：ArkUI hex-alpha 为 #AARRGGBB，需前置 alpha */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  private handleConfirm(): void {
    if (this.mode === 'diary') {
      if (this.onConfirmDiary) {
        this.onConfirmDiary(this.editableDiary);
      }
    } else {
      if (this.onConfirmTodo && this.todoFields) {
        this.onConfirmTodo(this.todoFields);
      }
    }
  }

  build() {
    Column() {
      // 标题栏：checkmark_circle_fill 复用 IconMapper.SUCCESS (grep 验证 L ✅)
      Row() {
        SymbolGlyph(IconMapper.SUCCESS)
          .fontSize(20).fontColor([this.getPrimary()])
        Text(this.getTitle())
          .fontSize(TYPO.h1.size).fontWeight(TYPO.h1.weight).fontColor(this.getTextPrimary())
          .margin({ left: 8 })
      }
      .width('100%').margin({ bottom: 14 })

      // 低置信度二次确认提示
      if (this.lowConfidence) {
        Row() {
          // exclamationmark_triangle_fill 复用 IconMapper.ERROR (grep 验证 L1468 ✅)
          SymbolGlyph(IconMapper.ERROR)
            .fontSize(16).fontColor([this.getWarning()])
          Text('识别置信度较低，请确认内容是否准确')
            .fontSize(TYPO.body.size).fontColor(this.getWarning())
            .margin({ left: 6 }).layoutWeight(1)
        }
        .width('100%').padding(10).borderRadius(RADIUS.item)
        .backgroundColor(this.withAlpha(this.getWarning(), '1A'))
        .margin({ bottom: 12 })
        .accessibilityText('提示：识别置信度较低，请确认内容')
      }

      if (this.mode === 'diary') {
        // === 日记模式：转文字预览（可编辑）===
        TextArea({ text: this.editableDiary })
          .fontSize(TYPO.body.size).fontColor(this.getTextPrimary())
          .backgroundColor(this.getSurface())
          .borderRadius(RADIUS.item).width('100%').height(160).padding(SPACING.cardPadSm)
          .border({ width: 1, color: this.getBorder() })
          .onChange((value: string) => { this.editableDiary = value; })
          .accessibilityText('日记正文，可编辑')
      } else {
        // === 待办模式：AI 提取字段展示 ===
        Column() {
          this.FieldRow($r('sys.symbol.bookmark'), '标题', this.todoFields ? this.todoFields.title : '')
          Divider().color(this.getBorder()).margin({ top: 10, bottom: 10 })
          this.FieldRow($r('sys.symbol.bookmark'), '类型',
            this.getTypeLabel(this.todoFields ? this.todoFields.type : 'general'))
          Divider().color(this.getBorder()).margin({ top: 10, bottom: 10 })
          this.FieldRow($r('sys.symbol.calendar'), '日期', this.todoFields ? this.todoFields.date : '')
          Divider().color(this.getBorder()).margin({ top: 10, bottom: 10 })
          this.FieldRow($r('sys.symbol.clock'), '时间', this.todoFields ? this.todoFields.time : '')
          Divider().color(this.getBorder()).margin({ top: 10, bottom: 10 })
          this.FieldRow($r('sys.symbol.map'), '地点', this.todoFields ? this.todoFields.location : '')
        }
        .width('100%').padding(SPACING.cardPadSm).borderRadius(RADIUS.item)
        .backgroundColor(this.getSurface())
      }

      // 操作按钮：取消 / 编辑 / 确认
      Row() {
        // 取消：xmark 复用好 IconMapper.CLOSE (grep 验证 L ✅)
        Button() {
          Row() {
            SymbolGlyph(IconMapper.CLOSE).fontSize(14).fontColor([this.getTextTertiary()])
            Text('取消').fontSize(TYPO.body.size).fontColor(this.getTextTertiary()).margin({ left: 4 })
          }
        }
        .backgroundColor(Color.Transparent).height(44).padding({ left: 12, right: 12 })
        .onClick(() => { if (this.onCancel) { this.onCancel(); } })
        .accessibilityText('取消')

        Blank()

        // 编辑：square_and_pencil (grep 验证 L1598 ✅)
        Button() {
          Row() {
            SymbolGlyph(IconMapper.BOOKMARK).fontSize(14).fontColor([this.getPrimary()])
            Text('编辑').fontSize(TYPO.body.size).fontColor(this.getPrimary()).margin({ left: 4 })
          }
        }
        .backgroundColor(this.getBtnAux()).borderRadius(999).height(44)
        .padding({ left: SPACING.cardPadSm, right: SPACING.cardPadSm })
        .onClick(() => { if (this.onEdit) { this.onEdit(); } })
        .accessibilityText('编辑内容')

        // 确认/保存：checkmark 复用 IconMapper.CHECKMARK (grep 验证 L ✅)
        Button() {
          Row() {
            SymbolGlyph(IconMapper.CHECKMARK).fontSize(14).fontColor([this.getBtnPrimaryText()])
            Text(this.mode === 'diary' ? '保存日记' : '添加待办')
              .fontSize(TYPO.body.size).fontWeight(600).fontColor(this.getBtnPrimaryText()).margin({ left: 4 })
          }
        }
        .backgroundColor(this.getBtnPrimary()).borderRadius(999).height(44)
        .padding({ left: SPACING.cardPadSm, right: SPACING.cardPadSm }).margin({ left: 10 })
        .shadow({ radius: 8, color: this.withAlpha(this.getBtnPrimary(), '4D'), offsetX: 0, offsetY: 3 })
        .onClick(() => { this.handleConfirm(); })
        .accessibilityText(this.mode === 'diary' ? '确认保存日记' : '确认添加待办')
      }
      .width('100%').margin({ top: SPACING.cardGap })
    }
    .width('100%').borderRadius(RADIUS.cardLg).padding(SPACING.cardPadLg)
    .backgroundColor(this.getCardBg())
    .border({ width: 1, color: this.getBorder() })
    .shadow({ radius: 24, color: this.getShadow(), offsetX: 0, offsetY: 4 })
    .accessibilityGroup(true)
  }

  // ==== 待办字段行 ====
  @Builder
  FieldRow(icon: Resource, label: string, value: string) {
    Row() {
      SymbolGlyph(icon).fontSize(16).fontColor([this.getTextSecondary()])
      Text(label)
        .fontSize(TYPO.body.size).fontColor(this.getTextSecondary())
        .margin({ left: 8 }).width(52)
      Text(value.length > 0 ? value : '未识别')
        .fontSize(TYPO.body.size)
        .fontColor(value.length > 0 ? this.getTextPrimary() : this.getTextTertiary())
        .layoutWeight(1).textAlign(TextAlign.End)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%').alignItems(VerticalAlign.Center)
    .accessibilityText(label + '：' + (value.length > 0 ? value : '未识别'))
  }
}

// === @Preview mock 组件（DevEco Studio Previewer 预览） ===

@Preview
@Component
struct VoiceResultPanelPreview {
  build() {
    Column({ space: 16 }) {
      VoiceResultPanel({
        mode: 'todo',
        todoFields: {
          title: '开项目周会',
          type: 'meeting',
          date: '2026-07-09',
          time: '15:00',
          location: '3楼会议室'
        },
        lowConfidence: true
      })
      VoiceResultPanel({
        mode: 'diary',
        diaryText: '今天天气很好，去公园散步，心情格外舒畅。',
        lowConfidence: false
      })
    }
    .width('100%').padding(16).backgroundColor('#FAF8F5')
  }
}
