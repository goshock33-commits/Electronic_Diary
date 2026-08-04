// <!-- agentID: HUI-015 -->
// 模块：操作类手绘图标 painter（7 种）
// 关联任务：T004
// 关联设计：PLN §3 T004 — ActionIconPainters
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 说明：每个函数签名统一为 (ctx, iconSize, strokeColor)，无硬编码色值

import { wb, wobbleArc, wobbleLine } from '../SketchCanvasUtils';

/**
 * 操作类图标绘制函数类型
 */
export type SketchedActionPainter = (ctx: CanvasRenderingContext2D, size: number, strokeColor: string) => void;

/**
 * CHECKMARK — 手写对勾
 * 粗线 + arcTo 转角圆弧过渡（从原 draw() 迁移）
 * HUI-020 精致化：线宽 3 → 2.8、拐点比例更匀称、抖动随共享 wb 收敛
 */
export function paintCheckmark(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 2.8;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  const sx: number = wb(size * 0.24, 0.4);
  const sy: number = wb(size * 0.52, 0.5);
  const bx: number = wb(size * 0.43, 0.4);
  const by: number = wb(size * 0.70, 0.5);
  const ex: number = wb(size * 0.80, 0.5);
  const ey: number = wb(size * 0.26, 0.4);

  ctx.beginPath();
  ctx.moveTo(sx, sy);
  ctx.lineTo(bx, by);
  ctx.arcTo(bx + size * 0.06, by, ex, ey, size * 0.16);
  ctx.lineTo(ex, ey);
  ctx.stroke();
  ctx.lineWidth = 1.5;
}

/**
 * XMARK — 手绘叉号
 * 两条交叉的抖动斜线
 * HUI-020 抖动二次收敛：wobbleLine amp 1.5/1.8 → 0.5/0.55
 */
export function paintXmark(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 2;
  ctx.lineCap = 'round';

  const margin: number = size * 0.25;

  // 左上到右下
  ctx.beginPath();
  wobbleLine(ctx, margin, margin, size - margin, size - margin, 0.5);
  ctx.stroke();

  // 右上到左下
  ctx.beginPath();
  wobbleLine(ctx, size - margin, margin, margin, size - margin, 0.55);
  ctx.stroke();
  ctx.lineWidth = 1.5;
}

/**
 * PLUS — 手绘加号
 * 一横一竖两条抖动线
 * HUI-020 抖动二次收敛：wobbleLine amp 1.2/1.5 → 0.4/0.5
 */
export function paintPlus(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 2;
  ctx.lineCap = 'round';

  const cx: number = size / 2;
  const cy: number = size / 2;
  const halfLen: number = size * 0.3;

  // 横线
  ctx.beginPath();
  wobbleLine(ctx, cx - halfLen, cy, cx + halfLen, cy, 0.4);
  ctx.stroke();

  // 竖线
  ctx.beginPath();
  wobbleLine(ctx, cx, cy - halfLen, cx, cy + halfLen, 0.5);
  ctx.stroke();
  ctx.lineWidth = 1.5;
}

/**
 * CHEVRON_LEFT — 手绘左箭头
 * 人字形折线（两段抖动线段组成 < 形）
 */
export function paintChevronLeft(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 2;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  const cx: number = size / 2;
  const cy: number = size / 2;

  ctx.beginPath();
  ctx.moveTo(wb(cx + size * 0.2, 0.4), wb(cy - size * 0.3, 0.6));
  ctx.lineTo(wb(cx - size * 0.2, 0.5), wb(cy, 0.4));
  ctx.lineTo(wb(cx + size * 0.2, 0.3), wb(cy + size * 0.3, 0.7));
  ctx.stroke();
  ctx.lineWidth = 1.5;
}

/**
 * CHEVRON_RIGHT — 手绘右箭头
 */
export function paintChevronRight(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 2;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  const cx: number = size / 2;
  const cy: number = size / 2;

  ctx.beginPath();
  ctx.moveTo(wb(cx - size * 0.2, 0.5), wb(cy - size * 0.3, 0.3));
  ctx.lineTo(wb(cx + size * 0.2, 0.4), wb(cy, 0.5));
  ctx.lineTo(wb(cx - size * 0.2, 0.6), wb(cy + size * 0.3, 0.4));
  ctx.stroke();
  ctx.lineWidth = 1.5;
}

/**
 * CHEVRON_DOWN — 手绘下箭头
 */
export function paintChevronDown(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 2;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  const cx: number = size / 2;
  const cy: number = size / 2;

  ctx.beginPath();
  ctx.moveTo(wb(cx - size * 0.3, 0.5), wb(cy - size * 0.2, 0.3));
  ctx.lineTo(wb(cx, 0.4), wb(cy + size * 0.2, 0.5));
  ctx.lineTo(wb(cx + size * 0.3, 0.6), wb(cy - size * 0.2, 0.4));
  ctx.stroke();
  ctx.lineWidth = 1.5;
}

/**
 * CHEVRON_UP — 手绘上箭头
 */
export function paintChevronUp(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 2;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  const cx: number = size / 2;
  const cy: number = size / 2;

  ctx.beginPath();
  ctx.moveTo(wb(cx - size * 0.3, 0.3), wb(cy + size * 0.2, 0.5));
  ctx.lineTo(wb(cx, 0.5), wb(cy - size * 0.2, 0.4));
  ctx.lineTo(wb(cx + size * 0.3, 0.6), wb(cy + size * 0.2, 0.3));
  ctx.stroke();
  ctx.lineWidth = 1.5;
}

/**
 * FLAME — 手绘火焰图标
 * 不规则的火焰形状（用抖动弧线画出）
 */
export function paintFlame(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 1.5;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  const cx: number = size / 2;
  const baseY: number = size * 0.85;
  const tipY: number = size * 0.12;
  const halfW: number = size * 0.25;

  // 火焰轮廓（左右两条不对称弧线 + 底部）
  ctx.beginPath();
  // 从底部左端出发
  ctx.moveTo(wb(cx - halfW, 0.3), wb(baseY, 0.5));
  // 左侧弧线向上到尖端
  ctx.quadraticCurveTo(
    wb(cx - halfW * 1.3, 0.8), wb(baseY - size * 0.35, 0.4),
    wb(cx, 0.5), wb(tipY, 0.3)
  );
  // 右侧弧线向下回到底部右端
  ctx.quadraticCurveTo(
    wb(cx + halfW * 1.3, 0.7), wb(baseY - size * 0.35, 0.5),
    wb(cx + halfW, 0.4), wb(baseY, 0.6)
  );
  ctx.closePath();
  ctx.stroke();

  // 填充（手绘填充——半透明 + 排线）
  ctx.fillStyle = strokeColor;
  ctx.globalAlpha = 0.2;
  ctx.beginPath();
  ctx.moveTo(cx - halfW * 0.6, baseY - 2);
  ctx.quadraticCurveTo(cx - halfW * 0.3, baseY - size * 0.3, cx, tipY + size * 0.12);
  ctx.quadraticCurveTo(cx + halfW * 0.3, baseY - size * 0.3, cx + halfW * 0.6, baseY - 2);
  ctx.closePath();
  ctx.fill();
  ctx.globalAlpha = 1.0;
}

/**
 * CHECK_CIRCLE — 手绘圈 + 手写勾（从旧 SketchIcon 迁移）
 * HUI-020 精致化（二次收敛）：圆圈抖动 → 0.3、勾居中三段比例匀称
 */
export function paintCheckCircle(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  const cx: number = size / 2;
  const cy: number = size / 2;

  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 1.7;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  // 手绘圈
  ctx.beginPath();
  wobbleArc(ctx, cx, cy, size * 0.42, 0, Math.PI * 2, 0.3);
  ctx.stroke();

  // 手写勾（居中）
  ctx.lineWidth = 2.2;
  ctx.beginPath();
  ctx.moveTo(wb(cx - size * 0.20, 0.4), wb(cy + size * 0.02, 0.5));
  ctx.lineTo(wb(cx - size * 0.04, 0.5), wb(cy + size * 0.18, 0.6));
  ctx.lineTo(wb(cx + size * 0.24, 0.5), wb(cy - size * 0.18, 0.4));
  ctx.stroke();
  ctx.lineWidth = 1.5;
}

/**
 * CLOCK — 手绘闹钟（从旧 SketchIcon 迁移）
 * 表盘 + 对称双耳（45°）+ 10:10 时分针 + 中心点
 * HUI-020 精致化（二次收敛）：表盘抖动 → 0.25、双耳沿 45° 与表盘相切对称、指针取 10:10 经典姿态
 */
export function paintClock(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  const cx: number = size / 2;
  const cy: number = size / 2;
  const r: number = size * 0.38;
  const k: number = 0.7071; // 45° 相切分量

  ctx.strokeStyle = strokeColor;
  ctx.fillStyle = strokeColor;
  ctx.lineWidth = 1.7;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  // 圆形表盘
  ctx.beginPath();
  wobbleArc(ctx, cx, cy, r, 0, Math.PI * 2, 0.25);
  ctx.stroke();

  // 左耳（表盘左上 45° 相切点向外）
  ctx.beginPath();
  ctx.moveTo(wb(cx - r * k, 0.4), wb(cy - r * k, 0.5));
  ctx.lineTo(wb(cx - size * 0.34, 0.5), wb(cy - size * 0.34, 0.4));
  ctx.stroke();

  // 右耳（对称）
  ctx.beginPath();
  ctx.moveTo(wb(cx + r * k, 0.4), wb(cy - r * k, 0.5));
  ctx.lineTo(wb(cx + size * 0.34, 0.5), wb(cy - size * 0.34, 0.4));
  ctx.stroke();

  // 时针（短，指向 10 点方向）
  ctx.lineWidth = 2.4;
  ctx.beginPath();
  ctx.moveTo(cx, cy);
  ctx.lineTo(wb(cx - size * 0.12, 0.5), wb(cy - size * 0.15, 0.5));
  ctx.stroke();

  // 分针（长，指向 2 点方向）
  ctx.lineWidth = 1.7;
  ctx.beginPath();
  ctx.moveTo(cx, cy);
  ctx.lineTo(wb(cx + size * 0.15, 0.5), wb(cy - size * 0.22, 0.5));
  ctx.stroke();

  // 中心点
  ctx.beginPath();
  ctx.arc(cx, cy, size * 0.035, 0, Math.PI * 2);
  ctx.fill();
}
