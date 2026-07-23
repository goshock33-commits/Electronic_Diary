// <!-- agentID: HUI-015 -->
// 模块：手绘 Canvas 抖动工具函数
// 关联任务：T001a
// 关联设计：PLN §3 T001 — 提取 Canvas 抖动工具
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 说明：从 SketchIcon / CheckInRing / MoodBarChart / TodoProgressBar 提取公共抖动函数

/**
 * 单点抖动：在值上叠加微小正弦偏移，模拟手绘运笔不稳
 * @param v 原始坐标值
 * @param seed 抖动种子（不同种子产生不同偏移相位）
 * @returns 抖动后的坐标值
 */
export function wb(v: number, seed: number): number {
  // HUI-020 精致化（二次收敛）：抖动幅度 0.35 → 0.13，线条基本工整只留极轻微手绘温度
  // 影响面已核实：仅图标 painter 引用本工具；统计图表 CheckInRing/MoodBarChart/TodoProgressBar 各自内联抖动，不受波及
  return v + Math.sin(seed * 7.3) * 0.13;
}

/**
 * 抖动弧线：用小线段 + 半径微扰模拟手绘不完美圆弧
 * @param ctx Canvas 2D 渲染上下文
 * @param cx 圆心 x
 * @param cy 圆心 y
 * @param r 半径
 * @param startAngle 起始角度（弧度）
 * @param endAngle 终止角度（弧度）
 * @param amp 抖动振幅（精致化推荐 0.2-0.35）
 */
export function wobbleArc(
  ctx: CanvasRenderingContext2D,
  cx: number, cy: number,
  r: number, startAngle: number, endAngle: number,
  amp: number
): void {
  const steps: number = Math.max(20, Math.floor(Math.abs(endAngle - startAngle) / 0.08));
  const step: number = (endAngle - startAngle) / steps;
  let first: boolean = true;
  for (let i = 0; i <= steps; i++) {
    const a: number = startAngle + i * step;
    // HUI-020 精致化（二次收敛）：高频次级扰动系数 0.22 → 0.1，弧线基本平顺
    const wob: number = Math.sin(a * 5.3 + i * 0.37) * amp + Math.sin(a * 11.7) * amp * 0.1;
    const rr: number = r + wob;
    if (first) {
      ctx.moveTo(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr);
      first = false;
    } else {
      ctx.lineTo(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr);
    }
  }
}

/**
 * 抖动矩形：四条边线带微小偏移，模拟手绘不齐的边缘
 * @param ctx Canvas 2D 渲染上下文
 * @param x 左上角 x
 * @param y 左上角 y
 * @param w 宽度
 * @param h 高度
 * @param wobble 抖动振幅（推荐 1.0-2.0）
 */
export function wobbleRect(
  ctx: CanvasRenderingContext2D,
  x: number, y: number,
  w: number, h: number, wobble: number
): void {
  ctx.moveTo(wb(x, 1.1), wb(y, 0.3));
  ctx.lineTo(wb(x + w, 0.7), wb(y, 0.9));
  ctx.lineTo(wb(x + w, 1.3), wb(y + h, 1.1));
  ctx.lineTo(wb(x, 0.4), wb(y + h, 0.6));
  ctx.closePath();
}

/**
 * 抖动直线：两点间线段带中点偏移，模拟手绘不直
 * @param ctx Canvas 2D 渲染上下文
 * @param x1 起点 x
 * @param y1 起点 y
 * @param x2 终点 x
 * @param y2 终点 y
 * @param amp 抖动振幅（推荐 1.0-2.0）
 */
export function wobbleLine(
  ctx: CanvasRenderingContext2D,
  x1: number, y1: number,
  x2: number, y2: number,
  amp: number
): void {
  const midX: number = (x1 + x2) / 2;
  const midY: number = (y1 + y2) / 2;
  const dx: number = x2 - x1;
  const dy: number = y2 - y1;
  const len: number = Math.sqrt(dx * dx + dy * dy);
  if (len < 2) {
    ctx.moveTo(x1, y1);
    ctx.lineTo(x2, y2);
    return;
  }
  // 法线方向扰动
  const nx: number = -dy / len;
  const ny: number = dx / len;
  const wobMidX: number = midX + nx * Math.sin(x1 * 3.7 + y1 * 2.3) * amp;
  const wobMidY: number = midY + ny * Math.sin(x1 * 3.7 + y1 * 2.3) * amp;
  ctx.moveTo(wb(x1, 0.3), wb(y1, 0.7));
  ctx.lineTo(wobMidX, wobMidY);
  ctx.lineTo(wb(x2, 1.1), wb(y2, 0.5));
}

/**
 * 抖动圆角矩形：带正弦扰动的圆角矩形路径，模拟手绘涂色边缘
 * @param ctx Canvas 2D 渲染上下文
 * @param x 左上角 x
 * @param y 左上角 y
 * @param w 宽度
 * @param h 高度
 * @param r 圆角半径
 */
export function wobbleRoundRect(
  ctx: CanvasRenderingContext2D,
  x: number, y: number,
  w: number, h: number, r: number
): void {
  const wob: number = 2.5;
  ctx.moveTo(x + r + Math.sin(x * 0.5) * wob, y + Math.cos(y * 0.6) * wob);
  ctx.lineTo(x + w - r + Math.sin((x + w) * 0.4) * wob, y + Math.cos(y * 0.5) * wob);
  ctx.arcTo(x + w + Math.sin((x + w) * 3) * wob * 0.5, y, x + w, y + r + Math.cos(y * 3) * wob * 0.5, r);
  ctx.lineTo(x + w + Math.sin((x + w) * 2) * wob, y + h - r + Math.cos((y + h) * 2) * wob);
  ctx.arcTo(x + w + Math.sin((x + w) * 3) * wob * 0.5, y + h, x + w - r + Math.cos((y + h) * 3) * wob * 0.5, y + h, r);
  ctx.lineTo(x + r + Math.sin(x * 0.7) * wob, y + h + Math.cos((y + h) * 0.5) * wob);
  ctx.arcTo(x + Math.sin(x * 3) * wob * 0.5, y + h, x, y + h - r + Math.cos((y + h) * 3) * wob * 0.5, r);
  ctx.lineTo(x + Math.sin(x * 2) * wob, y + r + Math.cos(y * 2) * wob);
  ctx.arcTo(x + Math.sin(x * 3) * wob * 0.5, y, x + r + Math.cos(y * 3) * wob * 0.5, y, r);
  ctx.closePath();
}

/**
 * 根据图标尺寸缩放抖动振幅
 * 基准尺寸 22vp，基准振幅 1.0
 * @param baseAmp 基准振幅
 * @param iconSize 图标实际尺寸
 * @returns 缩放后的振幅
 */
export function scaleWobbleAmp(baseAmp: number, iconSize: number): number {
  const scale: number = iconSize / 22;
  return baseAmp * scale;
}
