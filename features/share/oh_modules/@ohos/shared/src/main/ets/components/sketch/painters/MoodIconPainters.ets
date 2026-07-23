// <!-- agentID: HUI-015 -->
// 模块：心情类手绘图标 painter（4 种）
// 关联任务：T005a
// 关联设计：PLN §3 T005a — MoodIconPainters
// 参考风格：MoodBarChart.drawSketchMoodIcon
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 说明：每个函数签名统一为 (ctx, iconSize, strokeColor)，无硬编码色值

import { wb, wobbleArc, wobbleLine } from '../SketchCanvasUtils';

/**
 * 心情类图标绘制函数类型
 */
export type SketchedMoodPainter = (ctx: CanvasRenderingContext2D, size: number, strokeColor: string) => void;

/**
 * SUN — 手绘太阳图标
 * 中心小圆 + 放射状短线（光芒）
 * HUI-020 抖动二次收敛：中心圆 wobbleArc 0.8 → 0.3、光芒 wobbleLine 1.0 → 0.35
 */
export function paintSun(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  const cx: number = size / 2;
  const cy: number = size / 2;
  const innerR: number = size * 0.18;

  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 1.5;
  ctx.lineCap = 'round';

  // 中心圆
  ctx.beginPath();
  wobbleArc(ctx, cx, cy, innerR, 0, Math.PI * 2, 0.3);
  ctx.stroke();

  // 放射光芒（8 条短线）
  const rayCount: number = 8;
  for (let i = 0; i < rayCount; i++) {
    const a: number = (i / rayCount) * Math.PI * 2;
    const innerX: number = cx + Math.cos(a) * innerR * 1.3;
    const innerY: number = cy + Math.sin(a) * innerR * 1.3;
    const outerX: number = cx + Math.cos(a) * size * 0.42;
    const outerY: number = cy + Math.sin(a) * size * 0.42;
    ctx.beginPath();
    wobbleLine(ctx, innerX, innerY, outerX, outerY, 0.35);
    ctx.stroke();
  }
}

/**
 * STAR — 手绘星星图标
 * 四角星形（十字交叉 + 对角线交叉）
 * HUI-020 抖动二次收敛：各交叉线 wobbleLine amp 1.0/1.2 → 0.35/0.4
 */
export function paintStar(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  const cx: number = size / 2;
  const cy: number = size / 2;
  const r: number = size * 0.38;

  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 1.5;
  ctx.lineCap = 'round';

  // 十字线
  ctx.beginPath();
  wobbleLine(ctx, cx, cy - r, cx, cy + r, 0.35);
  ctx.stroke();
  ctx.beginPath();
  wobbleLine(ctx, cx - r, cy, cx + r, cy, 0.4);
  ctx.stroke();

  // 对角交叉线
  ctx.beginPath();
  wobbleLine(ctx, cx - r * 0.7, cy - r * 0.7, cx + r * 0.7, cy + r * 0.7, 0.35);
  ctx.stroke();
  ctx.beginPath();
  wobbleLine(ctx, cx + r * 0.7, cy - r * 0.7, cx - r * 0.7, cy + r * 0.7, 0.4);
  ctx.stroke();
}

/**
 * HEART — 手绘心形图标
 * 经典双弧 + 底部尖角心形
 */
export function paintHeart(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  const cx: number = size / 2;
  const cy: number = size / 2;
  const r: number = size * 0.32;

  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 1.5;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  // 心形：两段圆弧汇合到下方尖角
  ctx.beginPath();
  ctx.moveTo(wb(cx, 0.3), wb(cy + r * 0.6, 0.5)); // 底部尖角
  // 左弧
  ctx.arc(wb(cx - r * 0.5, 0.4), wb(cy - r * 0.15, 0.5), r * 0.5, Math.PI * 0.15, Math.PI * 1.05, false);
  // 顶弧左
  ctx.arc(wb(cx - r * 0.08, 0.4), wb(cy - r * 0.5, 0.5), r * 0.48, Math.PI * 0.7, Math.PI * 0.05, true);
  // 顶弧右
  ctx.arc(wb(cx + r * 0.08, 0.5), wb(cy - r * 0.5, 0.4), r * 0.48, Math.PI * 0.95, Math.PI * 0.3, true);
  // 右弧
  ctx.arc(wb(cx + r * 0.5, 0.6), wb(cy - r * 0.15, 0.4), r * 0.5, Math.PI * 1.85, Math.PI * 0.15, false);
  ctx.closePath();
  ctx.stroke();

  // 填充（半透明）
  ctx.fillStyle = strokeColor;
  ctx.globalAlpha = 0.15;
  ctx.fill();
  ctx.globalAlpha = 1.0;
}

/**
 * CLOUD — 手绘云朵图标
 * 多个重叠的圆 + 底部平线构成云形
 * HUI-020 抖动二次收敛：三圆 wobbleArc amp 1.2/1.0/0.8 → 0.35/0.3/0.3
 */
export function paintCloud(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  const cx: number = size / 2;
  const cy: number = size / 2;

  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 1.5;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  // 云朵由多个重叠圆构成
  const c1x: number = cx - size * 0.18;
  const c1y: number = cy + size * 0.05;
  const c1r: number = size * 0.16;
  const c2x: number = cx + size * 0.05;
  const c2y: number = cy - size * 0.08;
  const c2r: number = size * 0.2;
  const c3x: number = cx + size * 0.2;
  const c3y: number = cy + size * 0.08;
  const c3r: number = size * 0.14;

  // 三圆
  ctx.beginPath();
  wobbleArc(ctx, c1x, c1y, c1r, 0, Math.PI * 2, 0.35);
  ctx.stroke();
  ctx.beginPath();
  wobbleArc(ctx, c2x, c2y, c2r, 0, Math.PI * 2, 0.3);
  ctx.stroke();
  ctx.beginPath();
  wobbleArc(ctx, c3x, c3y, c3r, 0, Math.PI * 2, 0.3);
  ctx.stroke();

  // 底部连线（连接三个圆的下部弧线，抹去圆的下半部边界）
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(wb(c1x - c1r * 0.6, 0.3), wb(cy + size * 0.25, 0.5));
  ctx.lineTo(wb(c3x + c3r * 0.5, 0.7), wb(cy + size * 0.22, 0.4));
  ctx.stroke();
  ctx.lineWidth = 1.5;
}
