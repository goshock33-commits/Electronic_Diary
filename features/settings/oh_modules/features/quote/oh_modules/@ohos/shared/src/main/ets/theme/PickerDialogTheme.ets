// agentID: HUI-042
// 模块：系统选择弹窗主题化换肤工具（T-D07）
// 说明：DatePickerDialog / TextPickerDialog 等系统选择弹窗默认为系统材质样式，
//       与 App 黑白手绘主题（theme_tokens）不符。本工具集中提供「token → 弹窗样式项」
//       的换肤映射，各调用点一行一项读取，改一处、全 App 联动（DRY，同 FrostedGlassUtils 组织方式）。
// 保留系统滚轮交互，仅换肤（用户已确认决策：官方样式 API，不自绘）。
// ⚠️ 适用范围（T-D07 三轮收口）：仅适用于【无顶部标题区】的系统选择弹窗（当前：番茄钟
//   showTextPickerDialog——text_picker.d.ts 无 title/header 字段，弹窗不渲染标题区，换肤即达标）。
//   DatePickerDialog 因顶部标题区（选中日期行）无任何可配样式项（date_picker.d.ts:721 全字段
//   穷举验证），已升级自绘 components/ThemedDatePickerModal 替代，原 2 处日期弹窗调用点
//   （TodoBoard / features_search SearchPage）不再走本工具。
// 关联任务：T-D07（MAIN-001 派发）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
//
// API 依据（本地 SDK API 24 .d.ts，PROJECT_SPEC §10 唯一真相源）：
//   component/date_picker.d.ts:721  DatePickerDialogOptions
//     :851 disappearTextStyle / :870 textStyle / :886 acceptButtonStyle
//     :902 cancelButtonStyle / :921 selectedTextStyle / :1127 backgroundColor
//     :1147 backgroundBlurStyle（@default BlurStyle.COMPONENT_ULTRA_THICK →
//       置 NONE 纯色背景才能生效，不被系统模糊材质覆盖）
//   component/text_picker.d.ts:1193 TextPickerDialogOptions（同名样式项 :1260/:1278/:1294/:1310/:1328/:1546/:1566）
//   component/common.d.ts:9932 PickerTextStyle { color?, font?: Font }
//   component/common.d.ts:9980 PickerDialogButtonStyle
//     { fontColor?(:10030), fontWeight?(:10040), fontFamily?: Resource|string(:10060), backgroundColor?, borderRadius?, ... }
//   component/units.d.ts:1954 Font { size?, weight?, family?: string|Resource, style? }（family 可单设，字号沿用系统默认层级）
//   BlurStyle 为全局类型，无需导入（PROJECT_SPEC §7）
//
// 字体（HUI-042 二轮修复：用户反馈「字体没换」）：
//   滚轮三态行 + 确定/取消按钮统一补 FONT.sketchBody（清松手写体2 = App 正文/标签全局字体，
//   分工依据 SketchTextModifiers.ets 头注：正文类→sketchBody；字号不设，保留系统滚轮
//   「渐隐/常规/选中」三级字号层级）。字体经 EntryAbility.registerSketchFonts() 以
//   UIContext.getFont().registerFont() 注册于主窗口 UI 实例；date_picker/text_picker.d.ts
//   的 DialogOptions 均无 showInSubWindow 项（已 grep 自证）→ 弹窗渲染于调用方同一 UI 实例，
//   注册字体可生效；字体缺字形字符由系统自动回退渲染，不崩不空。
//
// 色彩映射（深浅色双达标，WCAG 对比度按 4 套色板逐一核算）：
//   背景        bgCard        （浅=白纸 #FFFFFF / 深=炭纸 #1C1C1C）
//   未选中行    textSecondary （浅 #4A4A4A on #FFFFFF ≈ 8.9:1 / 深 #CCCCCC on #1C1C1C ≈ 9.7:1）
//   选中行      textPrimary   （黑墨/白墨，≥ 15:1）
//   边缘渐隐行  textTertiary  （有意渐隐，系统语义）
//   确定按钮    btnPrimary 底 + btnPrimaryText 字（HUI-035 全局主按钮既有配对，大字号语义）
//   取消按钮    surface 底 + textSecondary 字
//     （不用 btnAux 底：高对比度浅色板 btnAux=#000000 与 textSecondary=#000000 同色不可读；
//       surface/textSecondary 在手绘浅、手绘深、高对比浅、高对比深 4 套色板下对比度全部 ≥ 4.5:1）
//
// 崩溃防范（PROJECT_SPEC §9.4）：tokens 判空回退 SKETCH_MONO_LIGHT 同值
// ArkTS 严格模式（§8.2）：对象字面量均带接口类型声明（PickerTextStyle / PickerDialogButtonStyle）

import type { ThemeColorTokens } from './ThemeConfig';
import { RADIUS } from './LayoutTokens';
import { FONT } from './FontPresets';

/**
 * 系统选择弹窗（DatePickerDialog / TextPickerDialog / TimePickerDialog）主题换肤工具。
 * 用法（调用点逐项读取，tokens 为页面 @StorageLink('theme_tokens')，可空）：
 * ```typescript
 * this.getUIContext().showDatePickerDialog({
 *   // ...业务项...
 *   backgroundColor: PickerDialogTheme.bg(this.tokens),
 *   backgroundBlurStyle: PickerDialogTheme.blur(),
 *   textStyle: PickerDialogTheme.textStyle(this.tokens),
 *   selectedTextStyle: PickerDialogTheme.selectedTextStyle(this.tokens),
 *   disappearTextStyle: PickerDialogTheme.disappearTextStyle(this.tokens),
 *   acceptButtonStyle: PickerDialogTheme.acceptButtonStyle(this.tokens),
 *   cancelButtonStyle: PickerDialogTheme.cancelButtonStyle(this.tokens)
 * });
 * ```
 */
export class PickerDialogTheme {

  /** 弹窗背板色：主题卡片底（浅=白纸 / 深=炭纸） */
  static bg(tokens: ThemeColorTokens | null): ResourceColor {
    return tokens ? tokens.bgCard : '#FFFFFF';
  }

  /**
   * 弹窗背景模糊材质：置 NONE。
   * date_picker.d.ts:1147 默认 COMPONENT_ULTRA_THICK（系统模糊材质），
   * 不关掉会盖住 bg() 的纯色主题底，导致换肤不生效。
   */
  static blur(): BlurStyle {
    return BlurStyle.NONE;
  }

  /** 滚轮未选中行文字样式（App 正文手写体；字号不设，保留系统层级） */
  static textStyle(tokens: ThemeColorTokens | null): PickerTextStyle {
    const bodyFont: Font = { family: FONT.sketchBody };
    const style: PickerTextStyle = {
      color: tokens ? tokens.textSecondary : '#4A4A4A',
      font: bodyFont
    };
    return style;
  }

  /** 滚轮选中行文字样式（黑墨/白墨最高层级 + App 正文手写体；字号/字重沿用系统选中态默认） */
  static selectedTextStyle(tokens: ThemeColorTokens | null): PickerTextStyle {
    const bodyFont: Font = { family: FONT.sketchBody };
    const style: PickerTextStyle = {
      color: tokens ? tokens.textPrimary : '#000000',
      font: bodyFont
    };
    return style;
  }

  /** 滚轮边缘渐隐行文字样式（最弱层级 + App 正文手写体，保留系统渐隐语义） */
  static disappearTextStyle(tokens: ThemeColorTokens | null): PickerTextStyle {
    const bodyFont: Font = { family: FONT.sketchBody };
    const style: PickerTextStyle = {
      color: tokens ? tokens.textTertiary : '#8A8A8A',
      font: bodyFont
    };
    return style;
  }

  /** 确定按钮：全局主按钮配对（btnPrimary 底 + btnPrimaryText 字，同 HUI-035）+ App 正文手写体 */
  static acceptButtonStyle(tokens: ThemeColorTokens | null): PickerDialogButtonStyle {
    const style: PickerDialogButtonStyle = {
      fontColor: tokens ? tokens.btnPrimaryText : '#FFFFFF',
      fontWeight: 600,
      fontFamily: FONT.sketchBody,
      backgroundColor: tokens ? tokens.btnPrimary : '#738A9C',
      borderRadius: RADIUS.item
    };
    return style;
  }

  /** 取消按钮：次级按钮（surface 底 + textSecondary 字，4 套色板对比度全达标）+ App 正文手写体 */
  static cancelButtonStyle(tokens: ThemeColorTokens | null): PickerDialogButtonStyle {
    const style: PickerDialogButtonStyle = {
      fontColor: tokens ? tokens.textSecondary : '#4A4A4A',
      fontWeight: 500,
      fontFamily: FONT.sketchBody,
      backgroundColor: tokens ? tokens.surface : '#F7F7F7',
      borderRadius: RADIUS.item
    };
    return style;
  }
}
