// <!-- agentID: HUI-001 -->
// 模块：主题配置类型定义
// 关联设计稿：UX-001_prototype.html
// 关联任务：T006a / T006b
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式

/**
 * 色板 Token — 单个主题的完整颜色定义
 * 每个主题包含浅色和深色两套完整配色
 * 参照 HarmonyOS Design System 色彩规范
 */
export interface ThemeColorTokens {
  /** 主色 */
  readonly primary: string;
  /** 主色（亮） */
  readonly primaryLight: string;
  /** 主色（暗） */
  readonly primaryDark: string;
  /** 辅色 */
  readonly secondary: string;
  /** 背景色（页面底层） */
  readonly bg: string;
  /** 卡片背景色 */
  readonly bgCard: string;
  /** 覆盖层背景色 */
  readonly bgOverlay: string;
  /** 表面色（输入框/按钮底） */
  readonly surface: string;
  /** 主要文字色 */
  readonly textPrimary: string;
  /** 次要文字色 */
  readonly textSecondary: string;
  /** 禁用/弱文字色 */
  readonly textTertiary: string;
  /** 边框色 */
  readonly border: string;
  /** 分割线色 */
  readonly divider: string;
  /** 强调背景色 */
  readonly accent: string;
  /** 危险/错误色 */
  readonly danger: string;
  /** 成功色 */
  readonly success: string;
  /** 警告色 */
  readonly warning: string;
  /** 主渐变 */
  readonly gradientPrimary: [string, string];
  /** Hero 区域渐变 */
  readonly gradientHero: [string, string];
  /** 阴影色 */
  readonly shadow: string;
  // ── 交互元素专用色 token（HUI-033）──────────────────────────────
  // 用途：给黑白手绘基调的交互元素加柔和彩色点缀，独立于 primary（primary 复用于正文/图标/图表，不可染色）。
  // 未选中/辅助描边态直接用白色 #FFFFFF，不设 token。
  /** 主按钮 / 调节按钮 / 任务勾选完成态 背景（雾霾蓝） */
  readonly btnPrimary: string;
  /** 主按钮文字色（白，与 btnPrimary 底形成大文本对比） */
  readonly btnPrimaryText: string;
  /** 开关打开态色（燕麦） */
  readonly switchOn: string;
  /** 辅助 / 次要按钮色（燕麦） */
  readonly btnAux: string;
}

/**
 * 主题模式
 */
export enum ThemeMode {
  /** 浅色模式 */
  LIGHT = 'light',
  /** 深色模式 */
  DARK = 'dark',
  /** 跟随系统 */
  FOLLOW_SYSTEM = 'follow_system'
}

/**
 * 毛玻璃模糊等级
 */
export enum FrostedBlurLevel {
  /** 轻模糊 — 背景隐约可见 */
  LIGHT = 1,
  /** 均衡模糊 — 背景半透 */
  MEDIUM = 2,
  /** 强模糊 — 背景高度雾化 */
  HEAVY = 3
}

/**
 * 毛玻璃参数包
 */
export interface FrostedBlurPack {
  /** 背景模糊半径(vp) */
  blurRadius: number;
  /** 背景不透明度 (0-1) */
  backgroundOpacity: number;
  /** 饱和度 */
  saturation: number;
  /** 亮度 */
  brightness: number;
}

/**
 * 主题预设配置
 */
export interface ThemePreset {
  /** 预设ID (1-5) */
  readonly id: number;
  /** 预设名称 */
  readonly name: string;
  /** 浅色模式色板 */
  readonly lightTokens: ThemeColorTokens;
  /** 深色模式色板 */
  readonly darkTokens: ThemeColorTokens;
}

/**
 * 自定义主题配置
 */
export interface CustomThemeConfig {
  /** 自定义浅色色板 */
  lightTokens: ThemeColorTokens;
  /** 自定义深色色板 */
  darkTokens: ThemeColorTokens;
  /** 主题名称 */
  name: string;
}

/**
 * 当前运行时主题状态
 */
export interface ThemeState {
  /** 当前预设ID (1-5 为预设，0 为自定义) */
  presetId: number;
  /** 当前主题模式 */
  mode: ThemeMode;
  /** 是否深色模式激活 */
  isDark: boolean;
  /** 当前生效的色板 Token */
  tokens: ThemeColorTokens;
  /** 当前毛玻璃等级 (1-3) */
  frostLevel: FrostedBlurLevel;
}

/**
 * 主题变更事件载荷
 */
export interface ThemeChangedEvent {
  /** 新预设ID */
  presetId: number;
  /** 是否深色模式 */
  isDark: boolean;
}

/**
 * Tab 配置项（供 FloatingTabBar 使用）
 */
export interface TabItemConfig {
  key: string;
  icon: Resource;
  label: string;
}
