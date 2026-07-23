// <!-- agentID: HUI-015 -->
// 模块：导航类手绘图标 painter（5 种）
// 关联任务：T003
// 关联设计：PLN §3 T003 — NavIconPainters
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 说明：每个函数签名统一为 (ctx, iconSize, strokeColor)，无硬编码色值

import { wb, wobbleArc, wobbleRect } from '../SketchCanvasUtils';

/**
 * 导航类图标绘制函数类型
 */
export type SketchedNavPainter = (ctx: CanvasRenderingContext2D, size: number, strokeColor: string) => void;

/**
 * NAV_DIARY — 手绘本子图标
 * 对称双页 + 中缝书脊，底边微弧模拟翻开的本子
 * HUI-020 精致化：左右完全对称、留白规整、底边用二次曲线更考究
 */
export function paintNavDiary(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  const cx: number = size / 2;
  const leftX: number = size * 0.18;
  const rightX: number = size * 0.82;
  const topY: number = size * 0.22;
  const botY: number = size * 0.78;
  const spineTopY: number = size * 0.18;
  const spineBotY: number = size * 0.84;

  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 1.6;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  // 左页：中缝顶 → 左上角 → 左下角 → 二次曲线收回中缝底
  ctx.beginPath();
  ctx.moveTo(wb(cx, 0.5), wb(spineTopY, 0.3));
  ctx.lineTo(wb(leftX, 0.8), wb(topY, 0.6));
  ctx.lineTo(wb(leftX, 0.4), wb(botY, 0.5));
  ctx.quadraticCurveTo(wb(cx - size * 0.16, 0.6), wb(botY + size * 0.02, 0.4), wb(cx, 0.7), wb(spineBotY, 0.5));
  ctx.stroke();

  // 右页（镜像）
  ctx.beginPath();
  ctx.moveTo(wb(cx, 0.5), wb(spineTopY, 0.3));
  ctx.lineTo(wb(rightX, 0.8), wb(topY, 0.6));
  ctx.lineTo(wb(rightX, 0.4), wb(botY, 0.5));
  ctx.quadraticCurveTo(wb(cx + size * 0.16, 0.6), wb(botY + size * 0.02, 0.4), wb(cx, 0.7), wb(spineBotY, 0.5));
  ctx.stroke();

  // 中缝书脊（略粗）
  ctx.lineWidth = 2.2;
  ctx.beginPath();
  ctx.moveTo(wb(cx, 0.3), wb(spineTopY, 0.3));
  ctx.lineTo(wb(cx, 0.7), wb(spineBotY, 0.5));
  ctx.stroke();
  ctx.lineWidth = 1.6;
}

/**
 * LIST_BULLET — 手绘列表图标
 * 三行等距：左侧实心子弹点 + 右侧横线
 * HUI-020 精致化：小圆点改实心（小尺寸更干净）、三行等距、线首尾对齐
 */
export function paintListBullet(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  ctx.strokeStyle = strokeColor;
  ctx.fillStyle = strokeColor;
  ctx.lineWidth = 1.7;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  const dotX: number = size * 0.20;
  const lineStartX: number = size * 0.36;
  const lineEndX: number = size * 0.82;
  const dotR: number = size * 0.045;
  const rowY: number[] = [size * 0.28, size * 0.50, size * 0.72];

  for (let row = 0; row < rowY.length; row++) {
    const y: number = rowY[row];
    // 实心子弹点
    ctx.beginPath();
    ctx.arc(wb(dotX, 0.4 + row * 0.3), wb(y, 0.3), dotR, 0, Math.PI * 2);
    ctx.fill();
    // 横线
    ctx.beginPath();
    ctx.moveTo(wb(lineStartX, 0.4 + row * 0.2), wb(y, 0.3));
    ctx.lineTo(wb(lineEndX, 0.6 + row * 0.2), wb(y, 0.6));
    ctx.stroke();
  }
}

/**
 * FACE_SMILING — 手绘笑脸图标
 * 圆脸 + 两个对称点眼 + 弧形微笑
 * HUI-020 精致化（二次收敛）：脸圆抖动 → 0.3、微笑弧 → 0.25，双眼对称、比例规整
 */
export function paintFaceSmiling(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  const cx: number = size / 2;
  const cy: number = size / 2;
  const r: number = size * 0.40;

  ctx.strokeStyle = strokeColor;
  ctx.fillStyle = strokeColor;
  ctx.lineWidth = 1.6;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  // 脸圆
  ctx.beginPath();
  wobbleArc(ctx, cx, cy, r, 0, Math.PI * 2, 0.3);
  ctx.stroke();

  // 双眼（对称实心点）
  const eyeY: number = cy - r * 0.28;
  const eyeDx: number = r * 0.36;
  const eyeR: number = size * 0.045;
  ctx.beginPath();
  ctx.arc(wb(cx - eyeDx, 0.5), wb(eyeY, 0.4), eyeR, 0, Math.PI * 2);
  ctx.fill();
  ctx.beginPath();
  ctx.arc(wb(cx + eyeDx, 0.6), wb(eyeY, 0.4), eyeR, 0, Math.PI * 2);
  ctx.fill();

  // 微笑弧
  ctx.beginPath();
  wobbleArc(ctx, cx, cy + r * 0.06, r * 0.52, Math.PI * 0.22, Math.PI * 0.78, 0.25);
  ctx.stroke();
}

/**
 * GEAR — 手绘齿轮图标
 * 梯形齿廓外圈 + 内圈轴孔
 * HUI-020 精致化（二次收敛）：由尖角星形改梯形齿（平顶/平谷）、固定抖动种子让 8 齿均匀、内圈抖动 → 0.2
 */
export function paintGear(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  const cx: number = size / 2;
  const cy: number = size / 2;
  const tipR: number = size * 0.40;
  const rootR: number = size * 0.30;
  const innerR: number = size * 0.16;
  const teeth: number = 8;
  const ta: number = (Math.PI * 2) / teeth;

  // 每个齿的 4 个采样点（占齿距比例，半径）：谷 → 齿顶左 → 齿顶右 → 谷
  const fracs: number[] = [0.0, 0.26, 0.44, 0.70];
  const radii: number[] = [rootR, tipR, tipR, rootR];

  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 1.6;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  // 梯形齿外圈
  ctx.beginPath();
  let started: boolean = false;
  for (let i = 0; i < teeth; i++) {
    for (let p = 0; p < fracs.length; p++) {
      const a: number = (i + fracs[p]) * ta - Math.PI / 2;
      const rr: number = radii[p];
      const x: number = cx + Math.cos(a) * rr;
      const y: number = cy + Math.sin(a) * rr;
      if (!started) {
        ctx.moveTo(wb(x, 0.35), wb(y, 0.55));
        started = true;
      } else {
        ctx.lineTo(wb(x, 0.4), wb(y, 0.5));
      }
    }
  }
  ctx.closePath();
  ctx.stroke();

  // 内圈轴孔
  ctx.beginPath();
  wobbleArc(ctx, cx, cy, innerR, 0, Math.PI * 2, 0.2);
  ctx.stroke();
}

/**
 * MAGNIFYING_GLASS — 手绘放大镜图标
 * 镜片圆 + 45° 手柄线
 * HUI-020 精致化（二次收敛）：镜片抖动 → 0.35、手柄严格 45° 从镜框接出、粗细协调
 */
export function paintMagnifyingGlass(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  const cx: number = size * 0.42;
  const cy: number = size * 0.42;
  const r: number = size * 0.30;
  const k: number = 0.7071; // cos45 = sin45

  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 1.8;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  // 镜片圆
  ctx.beginPath();
  wobbleArc(ctx, cx, cy, r, 0, Math.PI * 2, 0.35);
  ctx.stroke();

  // 手柄（从镜框右下 45° 延伸，略粗）
  const startX: number = cx + r * k;
  const startY: number = cy + r * k;
  const endX: number = size * 0.86;
  const endY: number = size * 0.86;
  ctx.lineWidth = 2.4;
  ctx.beginPath();
  ctx.moveTo(wb(startX, 0.4), wb(startY, 0.5));
  ctx.lineTo(wb(endX, 0.6), wb(endY, 0.4));
  ctx.stroke();
  ctx.lineWidth = 1.6;
}

/**
 * CHART — 手绘柱状图（从旧 SketchIcon 迁移）
 * 3 根等宽等距柱 + 抖动基线
 * HUI-020 精致化：柱宽/间距均匀、每柱独立 beginPath、基线两端对称留白
 */
export function paintChart(ctx: CanvasRenderingContext2D, size: number, strokeColor: string): void {
  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 1.6;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  const barW: number = size * 0.16;
  const baseY: number = size * 0.80;
  const barX: number[] = [size * 0.16, size * 0.42, size * 0.68];
  const barH: number[] = [size * 0.30, size * 0.52, size * 0.40];

  // 三根柱（等宽等距）
  for (let i = 0; i < barX.length; i++) {
    ctx.beginPath();
    wobbleRect(ctx, barX[i], baseY - barH[i], barW, barH[i], 1.0);
    ctx.stroke();
  }

  // 底部基线（抖动）
  ctx.beginPath();
  ctx.moveTo(wb(size * 0.10, 0.4), wb(baseY, 0.3));
  ctx.lineTo(wb(size * 0.90, 0.6), wb(baseY, 0.4));
  ctx.stroke();
}
