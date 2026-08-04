// <!-- agentID: HUI-015 -->
// 模块：手绘图标深色模式主题适配器
// 关联任务：T001b
// 关联设计：PLN §3 T001b — 深色模式绘色适配 + 手绘边框层级常量
// 关联审判：JUDGE F1 深色模式适配、JUDGE S8 边框层级、JUDGE N1 @StorageProp 防全量 rebuild
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 说明：适配器提供纯函数，不依赖 ArkUI 组件生命周期，所有颜色基于 isDark 布尔值计算

/**
 * 图标描边色
 * 浅色模式：深色 #1A1A1A
 * 深色模式：白色 #FFFFFF
 * @param isDark 是否深色模式
 * @returns 十六进制颜色值
 */
export function getStrokeColor(isDark: boolean): string {
  return isDark ? '#FFFFFF' : '#1A1A1A';
}

/**
 * 图标填充色
 * 与描边色保持一致，用于实心元素（中心点、填充块）
 * @param isDark 是否深色模式
 * @returns 十六进制颜色值
 */
export function getFillColor(isDark: boolean): string {
  return isDark ? '#FFFFFF' : '#1A1A1A';
}

/**
 * 次要/辅助色（灰色调）
 * 浅色模式：浅灰 (#E0E6ED)
 * 深色模式：中灰 (#3A3A3A)
 * @param isDark 是否深色模式
 * @returns 十六进制颜色值
 */
export function getSecondaryColor(isDark: boolean): string {
  return isDark ? '#3A3A3A' : '#E0E6ED';
}

/**
 * 三级均匀边框样式常量
 *
 * 设计意图：统一均匀边框宽度，干净利落的卡片风格。
 *
 * PRIMARY   — 一级功能卡片（统计数据卡、日记轮播、打卡区域）
 * SECONDARY — 二级区域（搜索面板、心情列表、待办项）
 * TERTIARY  — 三级分隔/辅助（设置项、低频入口）
 */
export interface SketchBorderStyle {
  left: number;
  right: number;
  top: number;
  bottom: number;
}

export const SKETCH_BORDER_PRIMARY: SketchBorderStyle = {
  left: 1.5,
  right: 1.5,
  top: 1.5,
  bottom: 1.5
};

export const SKETCH_BORDER_SECONDARY: SketchBorderStyle = {
  left: 1,
  right: 1,
  top: 1,
  bottom: 1
};

export const SKETCH_BORDER_TERTIARY: SketchBorderStyle = {
  left: 0.5,
  right: 0.5,
  top: 0.5,
  bottom: 0.5
};

/** getBorderStyle 返回值类型 */
export interface SketchBorderResult {
  width: SketchBorderStyle;
  color: string;
}

/**
 * 获取指定层级的手绘边框样式对象
 * 可直接用于 .border({ width: ..., color: ... })
 * @param isDark 是否深色模式
 * @param level 边框层级：'primary' | 'secondary' | 'tertiary'
 */
export function getBorderStyle(isDark: boolean, level: string): SketchBorderResult {
  let width: SketchBorderStyle = SKETCH_BORDER_PRIMARY;
  if (level === 'secondary') {
    width = SKETCH_BORDER_SECONDARY;
  } else if (level === 'tertiary') {
    width = SKETCH_BORDER_TERTIARY;
  }
  const result: SketchBorderResult = {
    width: width,
    color: getStrokeColor(isDark)
  };
  return result;
}
