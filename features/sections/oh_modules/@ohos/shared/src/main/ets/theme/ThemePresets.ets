// <!-- agentID: HUI-001 -->
// 模块：主题色板定义（高对比度 + 手绘黑白）
// 关联设计稿：UX-001_prototype.html
// 关联任务：T006a / T006b
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 色彩对比度：WCAG 2.1 AA (正文 >= 4.5:1, 大文本 >= 3:1)
// 适配：浅色模式 + 深色模式双套配色
// 说明：5 套彩色预设色板（晨露/暮蓝/暖阳/樱粉/墨韵）+ THEME_PRESETS 数组
//   + getPresetTokens/getPresetName 已随黑白手绘换肤废弃并删除，仅保留下列黑白色板。

import type { ThemeColorTokens } from './ThemeConfig';

/**
 * 默认主题ID（启动时使用）
 */
export const DEFAULT_PRESET_ID: number = 1;

// ══════════════════════════════════════════════════════════════════
// 高对比度（黑白重彩）色板 —— T-BUG-005（HUI-001）
// 无障碍：去除彩色/半透明，采用纯黑白最大对比 + 实心描边分层，随开关经 theme_tokens 全局生效。
// 语义色（danger/warning）保留可辨强调，但整体高对比；对深浅色分别给「白底黑字」/「黑底白字」两套。
// ══════════════════════════════════════════════════════════════════
const HIGH_CONTRAST_LIGHT: ThemeColorTokens = {
  primary: '#000000',
  primaryLight: '#000000',
  primaryDark: '#000000',
  secondary: '#000000',
  bg: '#FFFFFF',
  bgCard: '#FFFFFF',
  bgOverlay: 'rgba(255,255,255,0.96)',
  surface: '#FFFFFF',
  textPrimary: '#000000',
  textSecondary: '#000000',
  textTertiary: '#2B2B2B',
  border: '#000000',
  divider: '#000000',
  accent: '#EAEAEA',
  danger: '#B3130B',
  success: '#000000',
  warning: '#7A5C00',
  gradientPrimary: ['#000000', '#000000'],
  gradientHero: ['#FFFFFF', '#FFFFFF'],
  shadow: 'rgba(0,0,0,0.40)',
  // 交互元素专用色（HUI-033）：高对比度无障碍场景，彩色点缀让位于对比度 → 保持纯黑（白底黑钮白字）
  btnPrimary: '#000000',
  btnPrimaryText: '#FFFFFF',
  switchOn: '#000000',
  btnAux: '#000000'
};

const HIGH_CONTRAST_DARK: ThemeColorTokens = {
  primary: '#FFFFFF',
  primaryLight: '#FFFFFF',
  primaryDark: '#FFFFFF',
  secondary: '#FFFFFF',
  bg: '#000000',
  bgCard: '#000000',
  bgOverlay: 'rgba(0,0,0,0.94)',
  surface: '#000000',
  textPrimary: '#FFFFFF',
  textSecondary: '#FFFFFF',
  textTertiary: '#D6D6D6',
  border: '#FFFFFF',
  divider: '#FFFFFF',
  accent: '#1C1C1C',
  danger: '#FF6A60',
  success: '#FFFFFF',
  warning: '#FFD400',
  gradientPrimary: ['#FFFFFF', '#FFFFFF'],
  gradientHero: ['#000000', '#000000'],
  shadow: 'rgba(0,0,0,0.92)',
  // 交互元素专用色（HUI-033）：高对比度无障碍场景，彩色点缀让位于对比度 → 保持纯白（黑底白钮黑字）
  btnPrimary: '#FFFFFF',
  btnPrimaryText: '#000000',
  switchOn: '#FFFFFF',
  btnAux: '#FFFFFF'
};

/**
 * 获取高对比度（黑白重彩）色板。
 * @param isDark 是否深色模式（决定「黑底白字」还是「白底黑字」）
 */
export function getHighContrastTokens(isDark: boolean): ThemeColorTokens {
  return isDark ? HIGH_CONTRAST_DARK : HIGH_CONTRAST_LIGHT;
}

// ══════════════════════════════════════════════════════════════════
// 手绘黑白色板（Sketch Monochrome）—— HUI-021（全局默认主题）
// ------------------------------------------------------------------
// 设计意图（frontend-design / brainstorming）：把 App 统一为「白纸黑墨 / 黑纸白墨」的
//   手绘速写本气质。与 shared/components/sketch/SketchThemeAdapter.ets 的手绘图标描边同源
//   （墨黑 #000000 / 白 #FFFFFF / 铅笔线灰 #CCCCCC / 深色线灰 #666666），保证图文一致。
// 与「高对比度(getHighContrastTokens)」的区别（这是本色板的「手绘微调」）：
//   · 边框/分割线用「铅笔线灰」(#CCCCCC / #666666) 而非纯黑/纯白硬边 —— 更像手绘线条、不刺眼；
//   · 深色底用近黑炭纸 #121212（而非纯 #000000），卡片 #1C1C1C 形成自然层级；
//   · 文字保留 3 级灰阶层级（primary/secondary/tertiary），维持信息层级又不失黑白气质。
// 语义色（danger/success/warning）统一收敛为黑/白墨色：本主题为「配色黑白」的明确设计方向，
//   语义区分交由图标 + 文案承担（配色不作唯一区分手段）。
// 深浅色双套：浅色=白底黑字（纸），深色=黑底白字（炭纸），满足深色模式黑白要求。
// ══════════════════════════════════════════════════════════════════
const SKETCH_MONO_LIGHT: ThemeColorTokens = {
  primary: '#000000',
  primaryLight: '#333333',
  primaryDark: '#000000',
  secondary: '#666666',
  bg: '#FFFFFF',
  bgCard: '#FFFFFF',
  bgOverlay: 'rgba(255,255,255,0.92)',
  surface: '#F7F7F7',
  textPrimary: '#000000',
  textSecondary: '#4A4A4A',
  textTertiary: '#8A8A8A',
  border: '#CCCCCC',
  divider: '#E0E0E0',
  accent: '#F2F2F2',
  danger: '#000000',
  success: '#000000',
  warning: '#000000',
  gradientPrimary: ['#333333', '#000000'],
  gradientHero: ['#FFFFFF', '#F2F2F2'],
  shadow: 'rgba(0,0,0,0.12)',
  // 交互元素专用色（HUI-033）：黑白手绘基调上的柔和彩色点缀，深浅色同用一套（有意，不翻黑白）
  btnPrimary: '#738A9C',
  btnPrimaryText: '#FFFFFF',
  switchOn: '#C6BBAE',
  btnAux: '#C6BBAE'
};

const SKETCH_MONO_DARK: ThemeColorTokens = {
  primary: '#FFFFFF',
  primaryLight: '#FFFFFF',
  primaryDark: '#CCCCCC',
  secondary: '#999999',
  bg: '#121212',
  bgCard: '#1C1C1C',
  bgOverlay: 'rgba(18,18,18,0.92)',
  surface: '#242424',
  textPrimary: '#FFFFFF',
  textSecondary: '#CCCCCC',
  textTertiary: '#8A8A8A',
  border: '#666666',
  divider: '#3A3A3A',
  accent: '#242424',
  danger: '#FFFFFF',
  success: '#FFFFFF',
  warning: '#FFFFFF',
  gradientPrimary: ['#FFFFFF', '#CCCCCC'],
  gradientHero: ['#121212', '#1C1C1C'],
  shadow: 'rgba(0,0,0,0.60)',
  // 交互元素专用色（HUI-033）：黑白手绘基调上的柔和彩色点缀，深浅色同用一套（有意，不翻黑白）
  btnPrimary: '#738A9C',
  btnPrimaryText: '#FFFFFF',
  switchOn: '#C6BBAE',
  btnAux: '#C6BBAE'
};

/**
 * 获取手绘黑白色板（全局默认主题）。
 * @param isDark 是否深色模式（true=黑纸白墨 / false=白纸黑墨）
 */
export function getSketchMonoTokens(isDark: boolean): ThemeColorTokens {
  return isDark ? SKETCH_MONO_DARK : SKETCH_MONO_LIGHT;
}
