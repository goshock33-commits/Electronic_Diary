// <!-- agentID: HUI-015 -->
// 模块：媒体类手绘图标 painter（4 种）
// 关联任务：T005b
// 关联设计：PLN §3 T005c — MediaIconPainters（注：PLN 用 T005c，任务书用 T005b）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 说明：每个函数签名统一为 (ctx, iconSize, strokeColor)，无硬编码色值

import { wb, wobbleLine, wobbleRect } from '../SketchCanvasUtils';

/**
 * 媒体类图标绘制函数类型
 */
export type SketchedMediaPainter = (ctx: CanvasRenderingContext2D, size: number, strokeColor: string) => void;

/**
 * PLAY — 手绘播放三角
 * 指向右侧的抖动三角形
 */
export function paintPlay(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 1.5;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  const cx: number = size / 2;
  const cy: number = size / 2;
  const offset: number = size * 0.06; // 视觉居中偏移（三角形重心偏左）
  const halfH: number = size * 0.32;

  // 指向右侧的三角形
  ctx.beginPath();
  ctx.moveTo(wb(cx - halfH * 0.5 + offset, 0.3), wb(cy - halfH, 0.5));
  ctx.lineTo(wb(cx + halfH * 0.8 + offset, 0.7), wb(cy, 0.4));
  ctx.lineTo(wb(cx - halfH * 0.5 + offset, 0.4), wb(cy + halfH, 0.6));
  ctx.closePath();
  ctx.stroke();

  // 填充
  ctx.fillStyle = strokeColor;
  ctx.globalAlpha = 0.2;
  ctx.fill();
  ctx.globalAlpha = 1.0;
}

/**
 * PAUSE — 手绘暂停双竖线
 * 两条平行竖线
 * HUI-020 抖动二次收敛：wobbleLine amp 1.0/1.2 → 0.35/0.4
 */
export function paintPause(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 2.5;
  ctx.lineCap = 'round';

  const cx: number = size / 2;
  const cy: number = size / 2;
  const gap: number = size * 0.15;
  const barH: number = size * 0.5;
  const barTop: number = cy - barH / 2;
  const barBot: number = cy + barH / 2;

  // 左竖线
  ctx.beginPath();
  wobbleLine(ctx, cx - gap, barTop, cx - gap, barBot, 0.35);
  ctx.stroke();

  // 右竖线
  ctx.beginPath();
  wobbleLine(ctx, cx + gap, barTop, cx + gap, barBot, 0.4);
  ctx.stroke();
  ctx.lineWidth = 1.5;
}

/**
 * STOP — 手绘停止方块
 * 抖动矩形方块
 */
export function paintStop(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 1.5;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  const cx: number = size / 2;
  const cy: number = size / 2;
  const halfSide: number = size * 0.28;

  ctx.beginPath();
  wobbleRect(ctx, cx - halfSide, cy - halfSide, halfSide * 2, halfSide * 2, 1.5);
  ctx.stroke();

  // 填充
  ctx.fillStyle = strokeColor;
  ctx.globalAlpha = 0.2;
  ctx.fill();
  ctx.globalAlpha = 1.0;
}

/**
 * MIC — 手绘麦克风图标
 * 话筒轮廓（椭圆头 + 竖柄 + 底部横线）
 * HUI-020 抖动二次收敛：竖柄/底座 wobbleLine amp 1.2/1.0 → 0.4/0.35
 */
export function paintMic(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 1.5;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  const cx: number = size / 2;
  const headCY: number = size * 0.32;
  const headRX: number = size * 0.18;
  const headRY: number = size * 0.22;

  // 话筒头部椭圆
  ctx.beginPath();
  // 用抖动弧线近似椭圆：分成左右两个半弧，上下为平顶点
  const topY: number = headCY - headRY;
  const botY: number = headCY + headRY;
  ctx.moveTo(wb(cx, 0.3), wb(topY, 0.5));
  // 右半弧
  ctx.bezierCurveTo(
    wb(cx + headRX * 1.2, 0.4), wb(topY, 0.3),
    wb(cx + headRX * 1.2, 0.6), wb(botY, 0.5),
    wb(cx, 0.5), wb(botY, 0.4)
  );
  // 左半弧
  ctx.bezierCurveTo(
    wb(cx - headRX * 1.2, 0.7), wb(botY, 0.3),
    wb(cx - headRX * 1.2, 0.4), wb(topY, 0.6),
    wb(cx, 0.3), wb(topY, 0.5)
  );
  ctx.stroke();

  // 竖柄（从底部向下延伸）
  const handleTop: number = botY + 2;
  const handleBot: number = size * 0.82;
  ctx.lineWidth = 2;
  ctx.beginPath();
  wobbleLine(ctx, cx, handleTop, cx, handleBot, 0.4);
  ctx.stroke();

  // 底部横线（底座）
  ctx.lineWidth = 2;
  ctx.beginPath();
  wobbleLine(ctx, cx - size * 0.15, handleBot, cx + size * 0.15, handleBot, 0.35);
  ctx.stroke();
  ctx.lineWidth = 1.5;
}
