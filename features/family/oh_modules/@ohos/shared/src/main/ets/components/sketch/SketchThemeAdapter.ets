// <!-- agentID: HUI-015 -->
// 模块：手绘图标深色模式主题适配器
// 关联任务：T001b
// 关联设计：PLN §3 T001b — 深色模式绘色适配 + 手绘边框层级常量
// 关联审判：JUDGE F1 深色模式适配、JUDGE S8 边框层级、JUDGE N1 @StorageProp 防全量 rebuild
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 说明：适配器提供纯函数，不依赖 ArkUI 组件生命周期，所有颜色基于 isDark 布尔值计算

/**
 * 手绘图标描边色
 * 浅色模式：黑色 (#000000) — 模拟铅笔/钢笔线条
 * 深色模式：白色 (#FFFFFF) — 深色背景上可见，对比度 ~16:1（远超 WCAG AA 4.5:1）
 * @param isDark 是否深色模式
 * @returns 十六进制颜色值
 */
export function getStrokeColor(isDark: boolean): string {
  return isDark ? '#FFFFFF' : '#000000';
}

/**
 * 手绘图标填充色
 * 与描边色保持一致，用于实心元素（中心点、填充块）
 * @param isDark 是否深色模式
 * @returns 十六进制颜色值
 */
export function getFillColor(isDark: boolean): string {
  return isDark ? '#FFFFFF' : '#000000';
}

/**
 * 次要/辅助色（灰色调）
 * 浅色模式：浅灰 (#CCCCCC) — 背景轨道、未激活状态
 * 深色模式：中灰 (#666666) — 深色背景上清晰可辨但弱于主色
 * @param isDark 是否深色模式
 * @returns 十六进制颜色值
 */
export function getSecondaryColor(isDark: boolean): string {
  return isDark ? '#666666' : '#CCCCCC';
}

/**
 * 三级不均匀手绘边框样式常量
 *
 * 设计意图：边框四边宽度不对称（左窄右宽、上薄下厚），模拟手绘时笔压不均的自然效果。
 * 深色感知：颜色由调用方结合 getStrokeColor() 传入。
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
  left: 2,
  right: 4,
  top: 1.5,
  bottom: 3
};

export const SKETCH_BORDER_SECONDARY: SketchBorderStyle = {
  left: 1.5,
  right: 3,
  top: 1,
  bottom: 2
};

export const SKETCH_BORDER_TERTIARY: SketchBorderStyle = {
  left: 1,
  right: 2,
  top: 0.5,
  bottom: 1.5
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
