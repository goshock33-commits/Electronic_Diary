// agentID: HUI-078
// HUI-078 改造（主 Agent 派发）：今日/明日 pills → 自由日期选择器（复用 shared ThemedDatePickerModal）；
//   新增 时间输入 + 地点输入 + 自定义标签输入 + 提醒日期时间双选择器（日期 ThemedDatePickerModal +
//   时:分 ThemedTimePickerModal）。根节点升级全屏 Stack（自绘遮罩点击关闭，等价原 autoCancel），
//   因选择器为全屏覆盖组件，嵌在 85% 宽卡片内会被裁剪（TodoBoard/SettingsPage 覆盖层同模式先例）。
//   卡片内容包 Scroll 防字段增多后超高。type 由 dueDate 推导（今天→today，否则→tomorrow）保持
//   现有 VM 通路不动；dueDate/timeText/location/customTag/remindDate/remindTime 随 AddTodoResult
//   回传，持久化待 DEV 补（不改 DAO/VM）。
// HUI-001 改造：支持「编辑模式」——editMode+preset* 预填内容、标题/按钮文案切换（编辑待办/保存）。
// 组件：新增待办弹窗（毛玻璃背景+输入框+自由日期+时间/地点/标签输入+提醒双选择器+6色日程标签选择）
// 关联设计稿：UX-001 §2.3 TodoView 复刻（Add Modal）
// 关联任务：P2-01 待办「时光轴」TodoView 复刻 / AddTodoDialog 字段扩展
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText + 触控热区 >= 48x48vp（chip 34vp 高但整行可点区域达标，同原 pills）
// 深色适配：ThemeColorTokens + 硬编码回退色
// 图标验证（本地 resource/HarmonyOS_全量图标库.md）：calendar L311 / clock L323 / bell_fill L43 ✅

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：SKETCH_TITLE=猫啃什锦黑（弹窗标题）、SKETCH_BODY=清松手写体2（字段标签）；各 Button(string) 不动。
// HUI-078：追加 ThemedDatePickerModal / ThemedTimePickerModal（自由日期 + 提醒双选择器）、DateUtils。
import {
  IconMapper, RADIUS, SPACING, SKETCH_TITLE, SKETCH_BODY,
  ThemedDatePickerModal, ThemedTimePickerModal, DateUtils
} from '@ohos/shared';

/**
 * 新增待办提交数据
 * HUI-078：扩展自由日期/时间/地点/自定义标签/提醒字段（空串=未填写）。
 * type 保留（由 dueDate 推导今/明），现有页面层 VM 通路零改动；新字段持久化待 DEV 接线。
 */
export interface AddTodoResult {
  title: string;
  type: string;
  category: string;
  /** 截止日期 YYYY-MM-DD（必有值，默认今天） */
  dueDate: string;
  /** 时间文本（如 14:30，可空） */
  timeText: string;
  /** 地点（可空） */
  location: string;
  /** 自定义标签（可空） */
  customTag: string;
  /** 提醒日期 YYYY-MM-DD（空=未设提醒） */
  remindDate: string;
  /** 提醒时间 HH:mm（空=未设） */
  remindTime: string;
}

/**
 * 分类配置
 */
interface CategoryOption {
  label: string;
  tag: string;
}

@CustomDialog
export struct AddTodoDialog {
  controller: CustomDialogController;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  // HUI-001：编辑模式（点击待办项进入）——UI 预填与文案切换，保存走 onSubmit 回调由页面层调现有 update 通路。
  /** 是否编辑模式（true=编辑既有待办，false=新增） */
  editMode: boolean = false;
  /** 编辑模式预填标题 */
  presetTitle: string = '';
  /** 编辑模式预填截止日期 YYYY-MM-DD（HUI-078：替代原 presetType 今/明） */
  presetDueDate: string = '';
  /** 编辑模式预填日程标签 */
  presetCategory: string = '日常';
  /** 编辑模式预填时间文本（HUI-078，模型暂无字段，DEV 接线后生效） */
  presetTimeText: string = '';
  /** 编辑模式预填地点（HUI-078） */
  presetLocation: string = '';
  /** 编辑模式预填自定义标签（HUI-078） */
  presetCustomTag: string = '';
  /** 编辑模式预填提醒日期（HUI-078） */
  presetRemindDate: string = '';
  /** 编辑模式预填提醒时间 HH:mm（HUI-078） */
  presetRemindTime: string = '';

  /** 输入文字 */
  @State private inputText: string = '';
  /** 选中的日程标签 */
  @State private selectedCategory: string = '日常';
  /** HUI-078：截止日期 YYYY-MM-DD（aboutToAppear 赋今天/预填，§9.3 字段初值无 $r() 安全） */
  @State private dueDate: string = '';
  /** HUI-078：时间文本（自由输入，如 14:30） */
  @State private timeText: string = '';
  /** HUI-078：地点 */
  @State private locationText: string = '';
  /** HUI-078：自定义标签 */
  @State private customTag: string = '';
  /** HUI-078：提醒日期 YYYY-MM-DD（空=未设） */
  @State private remindDate: string = '';
  /** HUI-078：提醒时 0-23（-1=未设） */
  @State private remindHour: number = -1;
  /** HUI-078：提醒分 0-59（-1=未设） */
  @State private remindMinute: number = -1;
  /** HUI-078：截止日期选择器显隐 */
  @State private showDuePicker: boolean = false;
  /** HUI-078：提醒日期选择器显隐 */
  @State private showRemindDatePicker: boolean = false;
  /** HUI-078：提醒时:分选择器显隐 */
  @State private showRemindTimePicker: boolean = false;

  aboutToAppear(): void {
    // HUI-078：截止日期默认今天；编辑模式预填既有内容
    this.dueDate = DateUtils.today();
    if (this.editMode) {
      this.inputText = this.presetTitle;
      this.selectedCategory = this.presetCategory;
      if (this.presetDueDate.length > 0) {
        this.dueDate = this.presetDueDate;
      }
      this.timeText = this.presetTimeText;
      this.locationText = this.presetLocation;
      this.customTag = this.presetCustomTag;
      this.remindDate = this.presetRemindDate;
      this.applyPresetRemindTime();
    }
  }

  /** 解析预填提醒时间 HH:mm → remindHour/remindMinute（非法忽略） */
  private applyPresetRemindTime(): void {
    const parts: string[] = this.presetRemindTime.split(':');
    if (parts.length !== 2) {
      return;
    }
    const h: number = parseInt(parts[0]);
    const m: number = parseInt(parts[1]);
    if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
      this.remindHour = h;
      this.remindMinute = m;
    }
  }

  /** 日程标签选项（6项，对齐原型） */
  private categoryOptions: CategoryOption[] = [
    { label: '日常', tag: '日常' },
    { label: '学习', tag: '学习' },
    { label: '工作', tag: '工作' },
    { label: '日记', tag: '日记' },
    { label: '微信', tag: '微信' },
    { label: '语音', tag: '语音' }
  ];

  onSubmit?: (result: AddTodoResult) => void;

  // ═══ 展示文案（普通方法，规避 §9.1 getter-in-build）═══

  /** 截止日期 chip 文案：M月D日 */
  private getDueDateText(): string {
    if (this.dueDate.length === 0) {
      return '选择日期';
    }
    return DateUtils.formatShortCN(this.dueDate);
  }

  /** 提醒日期 chip 文案 */
  private getRemindDateText(): string {
    if (this.remindDate.length === 0) {
      return '日期';
    }
    return DateUtils.formatShortCN(this.remindDate);
  }

  /** 提醒时:分 chip 文案 */
  private getRemindTimeText(): string {
    if (this.remindHour < 0 || this.remindMinute < 0) {
      return '时:分';
    }
    return this.pad2(this.remindHour) + ':' + this.pad2(this.remindMinute);
  }

  /** 提醒时:分回传串（未设=空） */
  private getRemindTimeValue(): string {
    if (this.remindHour < 0 || this.remindMinute < 0) {
      return '';
    }
    return this.pad2(this.remindHour) + ':' + this.pad2(this.remindMinute);
  }

  private pad2(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString();
  }

  /** type 推导：截止日=今天→today，否则→tomorrow（保持现有 VM add/update 通路；任意日期落库待 DEV） */
  private getDerivedType(): string {
    return DateUtils.isToday(this.dueDate) ? 'today' : 'tomorrow';
  }

  /** 是否有任一选择器覆盖层在展示（展示中遮罩不响应关闭弹窗） */
  private isPickerOpen(): boolean {
    return this.showDuePicker || this.showRemindDatePicker || this.showRemindTimePicker;
  }

  /** 提交并关闭 */
  private submit(): void {
    const title: string = this.inputText.trim();
    if (title.length > 0 && this.onSubmit) {
      const result: AddTodoResult = {
        title: title,
        type: this.getDerivedType(),
        category: this.selectedCategory,
        dueDate: this.dueDate,
        timeText: this.timeText.trim(),
        location: this.locationText.trim(),
        customTag: this.customTag.trim(),
        remindDate: this.remindDate,
        remindTime: this.getRemindTimeValue()
      };
      this.onSubmit(result);
    }
    this.controller.close();
  }

  build() {
    // HUI-078：根节点全屏 Stack——遮罩 + 卡片 + 选择器覆盖层（选择器需全屏，卡片内嵌会被裁剪）
    Stack({ alignContent: Alignment.Center }) {
      // 自绘遮罩（点击关闭，等价原 autoCancel 点外关闭；选择器展示中不响应，防误关整个弹窗）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .backdropBlur(10)
        .onClick(() => {
          if (!this.isPickerOpen()) {
            this.controller.close();
          }
        })
        .accessibilityText('弹窗遮罩，点击关闭')

      // ── 弹窗卡片（内容包 Scroll 防字段增多后超高）──
      Column() {
        Scroll() {
          Column() {
            this.buildCardContent()
          }
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('85%')
      .constraintSize({ maxWidth: 440, maxHeight: '82%' })
      .padding(SPACING.cardPadLg)
      .borderRadius(RADIUS.cardLg)
      .backgroundColor(this.tokens ? this.tokens.bgCard : 'rgba(255,255,255,0.92)')
      .backdropBlur(20)
      .shadow({
        radius: 48,
        color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.15)',
        offsetX: 0,
        offsetY: 16
      })
      .border({
        width: 1,
        color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.10)'
      })
      .accessibilityGroup(true)

      // ── HUI-078：截止日期选择器（复用 shared ThemedDatePickerModal，全屏覆盖层）──
      if (this.showDuePicker) {
        ThemedDatePickerModal({
          initialDate: this.dueDate,
          titleText: '选择截止日期',
          onConfirm: (value: Date) => {
            this.dueDate = DateUtils.formatDate(value);
            this.showDuePicker = false;
          },
          onCancel: () => {
            this.showDuePicker = false;
          }
        })
      }

      // ── HUI-078：提醒日期选择器 ──
      if (this.showRemindDatePicker) {
        ThemedDatePickerModal({
          initialDate: this.remindDate.length > 0 ? this.remindDate : this.dueDate,
          titleText: '选择提醒日期',
          onConfirm: (value: Date) => {
            this.remindDate = DateUtils.formatDate(value);
            this.showRemindDatePicker = false;
          },
          onCancel: () => {
            this.showRemindDatePicker = false;
          }
        })
      }

      // ── HUI-078：提醒时:分选择器（shared ThemedTimePickerModal，与日期弹窗同模式）──
      if (this.showRemindTimePicker) {
        ThemedTimePickerModal({
          initialHour: this.remindHour >= 0 ? this.remindHour : 8,
          initialMinute: this.remindMinute >= 0 ? this.remindMinute : 0,
          titleText: '选择提醒时间',
          onConfirm: (hour: number, minute: number) => {
            this.remindHour = hour;
            this.remindMinute = minute;
            // 只选时间未选日期时，提醒日期默认截止日
            if (this.remindDate.length === 0) {
              this.remindDate = this.dueDate;
            }
            this.showRemindTimePicker = false;
          },
          onCancel: () => {
            this.showRemindTimePicker = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // ═══ 卡片内容 @Builder ═══
  @Builder
  buildCardContent() {
    // 标题栏
    Row() {
      Text(this.editMode ? '编辑待办' : '添加待办') // HUI-001：编辑模式标题切换
        .fontSize(16)
        .fontWeight(600)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .accessibilityText(this.editMode ? '编辑待办事项' : '添加待办事项')
        .attributeModifier(SKETCH_TITLE) // HUI-029：弹窗标题→猫啃什锦黑

      Blank()

      // 关闭按钮
      Button() {
        SymbolGlyph(IconMapper.CLOSE)
          .fontSize(16)
          .fontColor([this.tokens ? this.tokens.textSecondary : '#5A5A5A'])
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.controller.close();
      })
      .accessibilityText('关闭弹窗')
    }
    .width('100%')
    .margin({ bottom: 20 })

    // 标题输入框
    TextInput({ placeholder: '具体要完成什么任务？', text: this.inputText })
      .fontSize(14)
      .fontWeight(600)
      .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
      .placeholderColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
      .backgroundColor(this.tokens ? this.tokens.bg : '#F5F5F5')
      .borderRadius(RADIUS.input)
      .height(48)
      .padding({ left: SPACING.cardPadSm, right: SPACING.cardPadSm })
      .defaultFocus(true)
      .onChange((value: string) => {
        this.inputText = value;
      })
      .accessibilityText('待办事项输入框')
      .accessibilityLevel('yes')
      .margin({ bottom: 16 })

    // ── HUI-078：截止日期（自由选择，替代原今日/明日 pills）──
    Row() {
      Text('截止日期')
        .fontSize(13)
        .fontWeight(500)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
        .accessibilityLevel('no')
        .attributeModifier(SKETCH_BODY) // HUI-029：字段标签→清松手写体2

      Blank()

      // 日期 chip（点击弹主题化日期选择器）
      Button() {
        Row() {
          SymbolGlyph(IconMapper.TAB_CALENDAR) // 图标来源：本地图标库 L311 calendar ✅
            .fontSize(13)
            .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
          Text(this.getDueDateText())
            .fontSize(12)
            .fontWeight(600)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            .margin({ left: 5 })
        }
      }
      .type(ButtonType.Capsule)
      .height(34)
      .padding({ left: 14, right: 14 })
      // HUI-041 沿用：chip 底读 surface token（浅色 #F7F7F7 / 深色 #242424）
      .backgroundColor(this.tokens ? this.tokens.surface : '#FFFFFF')
      .border({
        width: 1,
        color: this.tokens ? this.tokens.border : '#E0E0E0'
      })
      .onClick(() => {
        this.showDuePicker = true;
      })
      .accessibilityText('截止日期：' + this.getDueDateText() + '，点击选择日期')
    }
    .width('100%')
    .margin({ bottom: 12 })

    // ── HUI-078：时间 + 地点输入（同排双输入框）──
    Row() {
      // 时间输入
      TextInput({ placeholder: '时间 14:30', text: this.timeText })
        .fontSize(12)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .placeholderColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
        .backgroundColor(this.tokens ? this.tokens.bg : '#F5F5F5')
        .borderRadius(RADIUS.input)
        .height(44)
        .width(118)
        .padding({ left: 12, right: 12 })
        .onChange((value: string) => {
          this.timeText = value;
        })
        .accessibilityText('时间输入框，格式如14点30分')
        .accessibilityLevel('yes')

      // 地点输入
      TextInput({ placeholder: '地点', text: this.locationText })
        .fontSize(12)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .placeholderColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
        .backgroundColor(this.tokens ? this.tokens.bg : '#F5F5F5')
        .borderRadius(RADIUS.input)
        .height(44)
        .layoutWeight(1)
        .padding({ left: 12, right: 12 })
        .margin({ left: 8 })
        .onChange((value: string) => {
          this.locationText = value;
        })
        .accessibilityText('地点输入框')
        .accessibilityLevel('yes')
    }
    .width('100%')
    .margin({ bottom: 12 })

    // ── HUI-078：自定义标签输入 ──
    TextInput({ placeholder: '自定义标签（可选）', text: this.customTag })
      .fontSize(12)
      .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
      .placeholderColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
      .backgroundColor(this.tokens ? this.tokens.bg : '#F5F5F5')
      .borderRadius(RADIUS.input)
      .height(44)
      .padding({ left: 12, right: 12 })
      .onChange((value: string) => {
        this.customTag = value;
      })
      .accessibilityText('自定义标签输入框')
      .accessibilityLevel('yes')
      .margin({ bottom: 12 })

    // ── HUI-078：提醒日期时间双选择器（日期 chip + 时:分 chip）──
    Row() {
      Row() {
        SymbolGlyph(IconMapper.BELL) // 图标来源：本地图标库 L43 bell_fill ✅
          .fontSize(12)
          .fontColor([this.tokens ? this.tokens.textSecondary : '#5A5A5A'])
        Text('提醒')
          .fontSize(13)
          .fontWeight(500)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
          .margin({ left: 4 })
          .accessibilityLevel('no')
          .attributeModifier(SKETCH_BODY) // HUI-029：字段标签→清松手写体2
      }

      Blank()

      // 提醒日期 chip
      Button(this.getRemindDateText())
        .type(ButtonType.Capsule)
        .fontSize(12)
        .fontWeight(this.remindDate.length > 0 ? 600 : 400)
        .fontColor(this.remindDate.length > 0 ?
          (this.tokens ? this.tokens.textPrimary : '#1A1A1A') :
          (this.tokens ? this.tokens.textTertiary : '#8A8A8A'))
        .backgroundColor(this.tokens ? this.tokens.surface : '#FFFFFF')
        .border({
          width: 1,
          color: this.tokens ? this.tokens.border : '#E0E0E0'
        })
        .height(34)
        .padding({ left: 14, right: 14 })
        .onClick(() => {
          this.showRemindDatePicker = true;
        })
        .accessibilityText('提醒日期：' + this.getRemindDateText() + '，点击选择')

      // 提醒时:分 chip
      Button(this.getRemindTimeText())
        .type(ButtonType.Capsule)
        .fontSize(12)
        .fontWeight(this.remindHour >= 0 ? 600 : 400)
        .fontColor(this.remindHour >= 0 ?
          (this.tokens ? this.tokens.textPrimary : '#1A1A1A') :
          (this.tokens ? this.tokens.textTertiary : '#8A8A8A'))
        .backgroundColor(this.tokens ? this.tokens.surface : '#FFFFFF')
        .border({
          width: 1,
          color: this.tokens ? this.tokens.border : '#E0E0E0'
        })
        .height(34)
        .padding({ left: 14, right: 14 })
        .margin({ left: 8 })
        .onClick(() => {
          this.showRemindTimePicker = true;
        })
        .accessibilityText('提醒时间：' + this.getRemindTimeText() + '，点击选择')
    }
    .width('100%')
    .margin({ bottom: 16 })

    // 日程标签选择器（6色横排 pills）
    Column() {
      Text('日程标签')
        .fontSize(13)
        .fontWeight(500)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
        .margin({ bottom: 8 })
        .alignSelf(ItemAlign.Start)
        .attributeModifier(SKETCH_BODY) // HUI-029：字段标签→清松手写体2

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.categoryOptions, (cat: CategoryOption) => {
          Button(cat.label)
            .type(ButtonType.Capsule)
            .fontSize(11)
            .fontWeight(this.selectedCategory === cat.tag ? 700 : 500)
            // HUI-034：分类 pill 选中 btnPrimaryText 白字，未选中深字
            .fontColor(this.selectedCategory === cat.tag ? (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF') :
              (this.tokens ? this.tokens.textSecondary : '#5A5A5A'))
            // HUI-041：分类 pill 未选中底由死白改读 surface token（浅色 #F7F7F7 / 深色 #242424）
            .backgroundColor(this.selectedCategory === cat.tag ?
              (this.tokens ? this.tokens.btnPrimary : '#738A9C') :
              (this.tokens ? this.tokens.surface : '#FFFFFF'))
            .height(32)
            .padding({ left: 12, right: 12 })
            .borderRadius(16)
            .margin({ right: 6, bottom: 6 })
            .onClick(() => {
              this.selectedCategory = cat.tag;
            })
            .accessibilityText(cat.label + (this.selectedCategory === cat.tag ? '，已选中' : ''))
        })
      }
    }
    .width('100%')
    .margin({ bottom: 20 })

    // 操作按钮区
    Row() {
      // 取消按钮
      Button('取消')
        .fontSize(14)
        .fontWeight(500)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
        // HUI-034：取消辅助按钮套 btnAux 燕麦底
        .backgroundColor(this.tokens ? this.tokens.btnAux : '#C6BBAE')
        .layoutWeight(1)
        .height(44)
        .borderRadius(22)
        .onClick(() => {
          this.controller.close();
        })
        .accessibilityText(this.editMode ? '取消编辑' : '取消添加') // HUI-001：编辑模式文案

      // 确认按钮
      Button(this.editMode ? '保存' : '确定') // HUI-001：编辑模式按钮文案切换
        .fontSize(14)
        .fontWeight(600)
        // HUI-034：主按钮套 btnPrimaryText 白字 + btnPrimary 雾霾蓝底
        .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
        .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
        .layoutWeight(1)
        .height(44)
        .borderRadius(22)
        .margin({ left: 12 })
        .enabled(this.inputText.trim().length > 0)
        .opacity(this.inputText.trim().length > 0 ? 1.0 : 0.4)
        .onClick(() => {
          this.submit();
        })
        .accessibilityText(this.editMode ? '保存修改' : '确认添加待办') // HUI-001：编辑模式文案
    }
    .width('100%')
  }
}
