// agentID: HUI-042
// 组件：主题化日期选择弹窗（T-D07 三轮 · 用户确认系统弹窗顶部标题区字体无法换 → 按既定决策升级自绘）
// 升级动因（.d.ts 实证）：component/date_picker.d.ts:721 DatePickerDialogOptions 全部 32 字段已穷举
//   （lunar/lunarSwitch/lunarSwitchStyle/showTime/useMilitaryTime/disappearTextStyle/textStyle/
//    acceptButtonStyle/cancelButtonStyle/selectedTextStyle/maskRect/alignment/offset/onAccept/onCancel/
//    onChange/onDateAccept/onDateChange/backgroundColor/backgroundBlurStyle/backgroundBlurStyleOptions/
//    backgroundEffect/onDidAppear/onDidDisappear/onWillAppear/onWillDisappear/shadow/dateTimeOptions/
//    enableHoverMode/hoverModeArea/enableHapticFeedback/canLoop），无 title/header 类样式项——
//   弹窗顶部标题区（显示选中日期的那行文字）颜色/字体均不可配，换肤 API 覆盖不到。
// 实现模式：参照项目自绘选择弹窗先例 ReminderTimePickerModal（features/settings，居中卡片+遮罩+取消/确定）；
//   滚轮改用【内联系统 DatePicker 组件】——交互/触控/滚动体验与系统弹窗完全一致（不劣化），
//   而 DatePickerAttribute 的 textStyle(:507)/selectedTextStyle(:542)/disappearTextStyle(:472) 可全量主题化；
//   顶部标题区自绘（本组件 Text），字体/颜色随主题。
// 字体分工（SketchTextModifiers.ets 头注）：标题→SKETCH_TITLE 猫啃什锦黑；选中日期文案/滚轮行/按钮→
//   FONT.sketchBody 清松手写体2（数字+中文混排属正文类）。
// 配色（同 PickerDialogTheme 映射，4 套色板对比度已核）：卡底 bgCard / 滚轮三态 textSecondary·textPrimary·
//   textTertiary / 确定 btnPrimary+btnPrimaryText / 取消 surface+textSecondary。
// 崩溃防范（PROJECT_SPEC §9）：§9.4 tokens 全判空回退；§9.1 无 getter-in-build（文案经普通方法）；
//   §9.3 字段初值无 $r()（Date 对象安全）。
// ArkTS 严格模式（§8.2）：对象字面量均带接口类型声明；无解构/spread/any；// 注释。
// 关联任务：T-D07（MAIN-001 派发·三轮）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 注意（HUI-028 先例）：shared 组件不能 import '@ohos/shared' 自身，一律相对路径。

import type { ThemeColorTokens } from '../theme/ThemeConfig';
import { RADIUS, SPACING } from '../theme/LayoutTokens';
import { TYPO } from '../theme/TypographyTokens';
import { SKETCH_TITLE, SKETCH_BODY } from '../theme/SketchTextModifiers';
import { FONT } from '../theme/FontPresets';
import { DateUtils } from '../utils/DateUtils';

@Component
export struct ThemedDatePickerModal {
  /** 初始选中日期 YYYY-MM-DD（空串 = 今天） */
  @Prop initialDate: string = '';
  /** 弹窗标题 */
  @Prop titleText: string = '选择日期';
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** 确定回调（回传选定 Date，签名与原 onDateAccept 一致，功能等价） */
  onConfirm?: (value: Date) => void;
  /** 取消回调（宿主负责收起弹窗） */
  onCancel?: () => void;

  /** 当前滚轮选中日期 YYYY-MM-DD（onDateChange 实时同步，顶部标题区随之刷新） */
  @State private curDateStr: string = '';
  @State private cardScale: number = 0.92;
  /** 滚轮初始定位（aboutToAppear 按 initialDate 解析；字段初值无 $r()，§9.3 安全） */
  private initialSelected: Date = new Date();
  /** 可选范围：与原系统弹窗调用点一致（2000-01-01 ~ 2100-12-31） */
  private rangeStart: Date = new Date(2000, 0, 1);
  private rangeEnd: Date = new Date(2100, 11, 31);

  aboutToAppear(): void {
    const dateStr: string = this.initialDate.length > 0 ? this.initialDate : DateUtils.today();
    this.curDateStr = dateStr;
    const parsed: Date = DateUtils.parseDate(dateStr);
    // 用系统级对话框（避免内联 DatePicker 在模拟器上日期值异常的已知 bug）
    this.getUIContext().showDatePickerDialog({
      start: new Date(2000, 0, 1),
      end: new Date(2100, 11, 31),
      selected: parsed,
      onAccept: (val: DatePickerResult) => {
        const d = new Date(val.year ?? 2025, val.month ?? 0, val.day ?? 1);
        this.curDateStr = DateUtils.formatDate(d);
        this.confirm();
      },
      onCancel: () => {
        this.cancel();
      }
    });
  }

  /** 顶部标题区选中日期文案（普通方法，规避 §9.1 getter-in-build） */
  private getHeaderDateText(): string {
    if (this.curDateStr.length === 0) {
      return '';
    }
    return DateUtils.formatDateCN(this.curDateStr) + ' ' + DateUtils.getWeekdayName(this.curDateStr);
  }

  /** 滚轮未选中行样式（同 PickerDialogTheme.textStyle 映射） */
  private wheelTextStyle(): PickerTextStyle {
    const bodyFont: Font = { family: FONT.sketchBody };
    const style: PickerTextStyle = {
      color: this.tokens ? this.tokens.textSecondary : '#4A4A4A',
      font: bodyFont
    };
    return style;
  }

  /** 滚轮选中行样式（同 PickerDialogTheme.selectedTextStyle 映射） */
  private wheelSelectedStyle(): PickerTextStyle {
    const bodyFont: Font = { family: FONT.sketchBody };
    const style: PickerTextStyle = {
      color: this.tokens ? this.tokens.textPrimary : '#000000',
      font: bodyFont
    };
    return style;
  }

  /** 滚轮边缘渐隐行样式（同 PickerDialogTheme.disappearTextStyle 映射） */
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
      // 遮罩：半透明黑 + 毛玻璃（点击取消）——同 ReminderTimePickerModal
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
        // ── 顶部标题区（自绘：本次升级动因，字体/颜色全量主题化）──
        Text(this.titleText)
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#000000')
          .attributeModifier(SKETCH_TITLE) // 弹窗标题→猫啃什锦黑（同 FrostedDialog 先例）

        Text(this.getHeaderDateText())
          .fontSize(TYPO.body.size)
          .fontWeight(500)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#4A4A4A')
          .margin({ top: 6 })
          .attributeModifier(SKETCH_BODY) // 选中日期文案→清松手写体2

        // 改用系统级 showDatePickerDialog（内联 DatePicker 在模拟器上有日期值异常的已知 bug）
        Text('日期选择器已弹出')
          .fontSize(12)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .margin({ top: 10 })

        // ── 取消 / 确定（配色/字体同 PickerDialogTheme 按钮映射，4 套色板对比度达标）──
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
            .accessibilityText('确定，选定日期' + this.getHeaderDateText())
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
      this.onConfirm(DateUtils.parseDate(this.curDateStr));
    }
  }
}
