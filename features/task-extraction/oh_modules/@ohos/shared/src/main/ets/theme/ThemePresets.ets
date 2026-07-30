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
// 蓝白卡片色板（Blue-White Card）—— 全局默认主题
// ------------------------------------------------------------------
// 设计意图：HarmonyOS 蓝白卡片风格，主色 #0A59F7 (HarmonyOS 蓝)，
//   白色卡片 + 浅灰背景 (#F5F7FA)，恢复真实语义色（红/绿/橙）。
//   标准 HarmonyOS Sans 字体 + SymbolGlyph 系统图标 + 均匀边框 + 柔和阴影。
// ══════════════════════════════════════════════════════════════════
const SKETCH_MONO_LIGHT: ThemeColorTokens = {
  primary: '#0A59F7',
  primaryLight: '#3B82F6',
  primaryDark: '#003DB8',
  secondary: '#666666',
  bg: '#F5F7FA',
  bgCard: '#FFFFFF',
  bgOverlay: 'rgba(255,255,255,0.92)',
  surface: '#F0F4F8',
  textPrimary: '#1A1A1A',
  textSecondary: '#666666',
  textTertiary: '#999999',
  border: '#E0E6ED',
  divider: '#EEF0F4',
  accent: '#EBF5FF',
  danger: '#FF4D4F',
  success: '#52C41A',
  warning: '#FAAD14',
  gradientPrimary: ['#0A59F7', '#003DB8'],
  gradientHero: ['#FFFFFF', '#F0F4F8'],
  shadow: 'rgba(0,0,0,0.08)',
  btnPrimary: '#0A59F7',
  btnPrimaryText: '#FFFFFF',
  switchOn: '#0A59F7',
  btnAux: '#E0E6ED'
};

const SKETCH_MONO_DARK: ThemeColorTokens = {
  primary: '#4A90E2',
  primaryLight: '#5BA0F5',
  primaryDark: '#2A6FCC',
  secondary: '#999999',
  bg: '#121212',
  bgCard: '#1E1E1E',
  bgOverlay: 'rgba(18,18,18,0.92)',
  surface: '#242424',
  textPrimary: '#FFFFFF',
  textSecondary: '#CCCCCC',
  textTertiary: '#8A8A8A',
  border: '#3A3A3A',
  divider: '#2A2A2A',
  accent: '#1A2B4D',
  danger: '#FF6A60',
  success: '#73D13D',
  warning: '#FFD43B',
  gradientPrimary: ['#0A59F7', '#003DB8'],
  gradientHero: ['#1E1E1E', '#121212'],
  shadow: 'rgba(0,0,0,0.40)',
  btnPrimary: '#0A59F7',
  btnPrimaryText: '#FFFFFF',
  switchOn: '#0A59F7',
  btnAux: '#3A3A3A'
};

/**
 * 获取蓝白卡片色板（全局默认主题）。
 * @param isDark 是否深色模式
 */
export function getSketchMonoTokens(isDark: boolean): ThemeColorTokens {
  return isDark ? SKETCH_MONO_DARK : SKETCH_MONO_LIGHT;
}
