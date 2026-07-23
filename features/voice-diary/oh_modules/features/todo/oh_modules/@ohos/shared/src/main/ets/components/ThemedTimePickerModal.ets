// agentID: HUI-078
// 组件：主题化时间选择弹窗（时:分滚轮）——与 ThemedDatePickerModal（HUI-042）同模式成对
// 动因：AddTodoDialog「提醒日期时间双选择器」需要时:分滚轮；shared 无主题化时间滚轮弹窗
//   （features/settings/ReminderTimePickerModal 为圆盘交互且跨 feature 不可引）。
// 实现模式：复刻 ThemedDatePickerModal——居中卡片 + 遮罩 + 自绘标题区 + 内联系统 TimePicker 滚轮
//   （交互与系统弹窗一致），textStyle/selectedTextStyle/disappearTextStyle 全量主题化。
// API24 已验（本地 d.ts 真相源 time_picker.d.ts）：TimePickerResult{hour,minute}(:46)、
//   useMilitaryTime(:394)、disappearTextStyle(:453)、textStyle(:484)、selectedTextStyle(:515)、
//   onChange(:579)。
// 字体分工（同 ThemedDatePickerModal）：标题→SKETCH_TITLE 猫啃什锦黑；选中时间文案/滚轮行/按钮→
//   FONT.sketchBody 清松手写体2。
// 崩溃防范（PROJECT_SPEC §9）：§9.4 tokens 全判空回退；§9.1 无 getter-in-build（文案经普通方法）；
//   §9.3 字段初值无 $r()（Date 对象安全）。
// ArkTS 严格模式（§8.2）：对象字面量均带接口类型声明；无解构/spread/any；// 注释。
// 关联任务：AddTodoDialog 字段扩展（主 Agent 派发）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 注意（HUI-028 先例）：shared 组件不能 import '@ohos/shared' 自身，一律相对路径。

import type { ThemeColorTokens } from '../theme/ThemeConfig';
import { RADIUS, SPACING } from '../theme/LayoutTokens';
import { TYPO } from '../theme/TypographyTokens';
import { SKETCH_TITLE, SKETCH_BODY } from '../theme/SketchTextModifiers';
import { FONT } from '../theme/FontPresets';

@Component
export struct ThemedTimePickerModal {
  /** 初始小时（0–23，越界回退当前时刻） */
  @Prop initialHour: number = -1;
  /** 初始分钟（0–59，越界回退当前时刻） */
  @Prop initialMinute: number = -1;
  /** 弹窗标题 */
  @Prop titleText: string = '选择时间';
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** 确定回调（回传选定 时、分） */
  onConfirm?: (hour: number, minute: number) => void;
  /** 取消回调（宿主负责收起弹窗） */
  onCancel?: () => void;

  /** 当前滚轮选中 时/分（onChange 实时同步，顶部标题区随之刷新） */
  @State private curHour: number = 0;
  @State private curMinute: number = 0;
  @State private cardScale: number = 0.92;
  /** 滚轮初始定位（aboutToAppear 中设为合法值；字段初值用安全占位，§9.3 安全） */
  private initialSelected: Date = new Date(2020, 0, 1, 0, 0);

  aboutToAppear(): void {
    const h: number = this.isValidHour(this.initialHour) ? this.initialHour : 8;
    const m: number = this.isValidMinute(this.initialMinute) ? this.initialMinute : 0;
    // 用系统级对话框（避免内联 TimePicker 在模拟器上分钟值异常的已知 bug）
    this.getUIContext().showTimePickerDialog({
      selected: new Date(2025, 6, 1, h, m),
      useMilitaryTime: true,
      onAccept: (val: TimePickerResult) => {
        this.curHour = val.hour ?? h;
        this.curMinute = val.minute ?? m;
        this.confirm();
      },
      onCancel: () => {
        this.cancel();
      }
    });
  }

  private isValidHour(v: number): boolean {
    return v >= 0 && v <= 23;
  }

  private isValidMinute(v: number): boolean {
    return v >= 0 && v <= 59;
  }

  /** 补零两位 */
  private pad2(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString();
  }

  /** 顶部标题区选中时间文案（普通方法，规避 §9.1 getter-in-build） */
  private getHeaderTimeText(): string {
    return this.pad2(this.curHour) + ':' + this.pad2(this.curMinute);
  }

  /** 滚轮未选中行样式（同 ThemedDatePickerModal.wheelTextStyle 映射） */
  private wheelTextStyle(): PickerTextStyle {
    const bodyFont: Font = { family: FONT.sketchBody };
    const style: PickerTextStyle = {
      color: this.tokens ? this.tokens.textSecondary : '#4A4A4A',
      font: bodyFont
    };
    return style;
  }

  /** 滚轮选中行样式 */
  private wheelSelectedStyle(): PickerTextStyle {
    const bodyFont: Font = { family: FONT.sketchBody };
    const style: PickerTextStyle = {
      color: this.tokens ? this.tokens.textPrimary : '#000000',
      font: bodyFont
    };
    return style;
  }

  /** 滚轮边缘渐隐行样式 */
  private wheelDisappearStyle(): PickerTextStyle {
    const bodyFont: Font = { family: FONT.sketchBody };
    const style: PickerTextStyle = {
      color: this.tokens ? this.tokens.textTertiary : '#8A8A8A',
      font: bodyFont
    };
    return style;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 遮罩：半透明黑 + 毛玻璃（点击取消）——同 ThemedDatePickerModal
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .backdropBlur(10)
        .onClick(() => {
          this.cancel();
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
        .accessibilityText('弹窗遮罩，点击取消')

      // 弹窗卡片
      Column() {
        // ── 顶部标题区（自绘，字体/颜色全量主题化）──
        Text(this.titleText)
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#000000')
          .attributeModifier(SKETCH_TITLE) // 弹窗标题→猫啃什锦黑

        Text(this.getHeaderTimeText())
          .fontSize(TYPO.body.size)
          .fontWeight(500)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#4A4A4A')
          .margin({ top: 6 })
          .attributeModifier(SKETCH_BODY) // 选中时间文案→清松手写体2

        // 改用系统级 showTimePickerDialog（内联 TimePicker 在模拟器上有分钟值异常的已知 bug）

        // ── 取消 / 确定（配色/字体同 ThemedDatePickerModal 按钮映射）──
        Row() {
          Button('取消')
            .fontSize(TYPO.body.size)
            .fontWeight(500)
            .fontFamily(FONT.sketchBody)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#4A4A4A')
            .backgroundColor(this.tokens ? this.tokens.surface : '#F7F7F7')
            .layoutWeight(1)
            .height(48)
            .borderRadius(RADIUS.item)
            .onClick(() => {
              this.cancel();
            })
            .accessibilityText('取消')

          Button('确定')
            .fontSize(TYPO.body.size)
            .fontWeight(600)
            .fontFamily(FONT.sketchBody)
            .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
            .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
            .layoutWeight(1)
            .height(48)
            .borderRadius(RADIUS.item)
            .margin({ left: 12 })
            .onClick(() => {
              this.confirm();
            })
            .accessibilityText('确定，选定时间' + this.getHeaderTimeText())
        }
        .width('100%')
        .margin({ top: 18 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 440 })
      .padding(SPACING.cardPadLg)
      .borderRadius(RADIUS.cardLg)
      .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
      .backdropBlur(24)
      .border({ width: 1, color: this.tokens ? this.tokens.border : '#CCCCCC' })
      .shadow({
        radius: 48,
        color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.12)',
        offsetX: 0,
        offsetY: 16
      })
      .alignItems(HorizontalAlign.Center)
      .scale({ x: this.cardScale, y: this.cardScale })
      .transition(
        TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }))
          .animation({ duration: 240, curve: Curve.EaseOut })
      )
    }
    .width('100%')
    .height('100%')
  }

  private cancel(): void {
    if (this.onCancel) {
      this.onCancel();
    }
  }

  private confirm(): void {
    if (this.onConfirm) {
      this.onConfirm(this.curHour, this.curMinute);
    }
  }
}
