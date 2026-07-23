// <!-- agentID: HUI-015 -->
// fix: HUI-016
// 组件：手绘黑白线条图标（Canvas 替代 SymbolGlyph）— 重构版
// 关联任务：T002 / T006
// 关联设计：PLN §3 T002 — 扩展枚举 + 增强 SketchIcon + painter 分发
// 关联审判：JUDGE N1 (@StorageProp 防全量 rebuild) / JUDGE N2 (@Reusable 组件复用)
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式 (Stage 模型 · API 24)
// 崩溃防范：PROJECT_SPEC §9.4 @StorageProp 空值防御
// 说明：
//   - 图标绘制委托给 painter 模块（NavIconPainters / ActionIconPainters / MoodIconPainters / MediaIconPainters）
//   - 深色感知：@StorageProp('theme_is_dark')，由 ThemeManager 统一管理
//   - 颜色优先级：strokeColor prop > SketchThemeAdapter.getStrokeColor(isDark)
//   - 组件复用：@Reusable + aboutToReuse()，降低大量 SketchIcon 实例场景内存占用
//   - 无障碍：Canvas .accessibilityText(this.accessibilityLabel)

import { getStrokeColor } from './SketchThemeAdapter';
import {
  paintNavDiary, paintListBullet, paintFaceSmiling,
  paintGear, paintMagnifyingGlass, paintChart
} from './painters/NavIconPainters';
import {
  paintCheckmark, paintXmark, paintPlus, paintChevronLeft,
  paintChevronRight, paintChevronDown, paintChevronUp,
  paintFlame, paintCheckCircle, paintClock
} from './painters/ActionIconPainters';
import { paintSun, paintStar, paintHeart, paintCloud } from './painters/MoodIconPainters';
import { paintPlay, paintPause, paintStop, paintMic } from './painters/MediaIconPainters';

// ══════════════════════════════════════════════════
// 图标类型枚举（25 种）
// ══════════════════════════════════════════════════

export enum SketchIconType {
  // 现有（保持字符串值以兼容 StatisticsPage 旧引用）
  CHART = 'chart',
  CHECK_CIRCLE = 'check_circle',
  BOOK = 'book',
  CHECKMARK = 'checkmark',
  CLOCK = 'clock',
  // 导航类 (T003)
  NAV_DIARY = 'nav_diary',
  LIST_BULLET = 'list_bullet',
  FACE_SMILING = 'face_smiling',
  GEAR = 'gear',
  MAGNIFYING_GLASS = 'magnifying_glass',
  // 操作类 (T004)
  XMARK = 'xmark',
  PLUS = 'plus',
  CHEVRON_LEFT = 'chevron_left',
  CHEVRON_RIGHT = 'chevron_right',
  CHEVRON_DOWN = 'chevron_down',
  CHEVRON_UP = 'chevron_up',
  FLAME = 'flame',
  // 心情类 (T005a)
  SUN = 'sun',
  STAR = 'star',
  HEART = 'heart',
  CLOUD = 'cloud',
  // 媒体类 (T005b)
  PLAY = 'play',
  PAUSE = 'pause',
  STOP = 'stop',
  MIC = 'mic'
}

// ══════════════════════════════════════════════════
// Painter 函数类型
// ══════════════════════════════════════════════════

type SketchIconPainter = (ctx: CanvasRenderingContext2D, size: number, strokeColor: string) => void;

// ══════════════════════════════════════════════════
// Painter 分发映射表（零 if-else）
// ══════════════════════════════════════════════════

function buildPainterMap(): Record<string, SketchIconPainter> {
  const map: Record<string, SketchIconPainter> = {};
  // 导航类（含旧枚举迁移）
  map['chart'] = paintChart;
  map['nav_diary'] = paintNavDiary;
  map['book'] = paintNavDiary; // 旧 BOOK 映射到 NAV_DIARY painter
  map['list_bullet'] = paintListBullet;
  map['face_smiling'] = paintFaceSmiling;
  map['gear'] = paintGear;
  map['magnifying_glass'] = paintMagnifyingGlass;
  // 操作类（含旧枚举迁移）
  map['checkmark'] = paintCheckmark;
  map['check_circle'] = paintCheckCircle;
  map['clock'] = paintClock;
  map['xmark'] = paintXmark;
  map['plus'] = paintPlus;
  map['chevron_left'] = paintChevronLeft;
  map['chevron_right'] = paintChevronRight;
  map['chevron_down'] = paintChevronDown;
  map['chevron_up'] = paintChevronUp;
  map['flame'] = paintFlame;
  // 心情类
  map['sun'] = paintSun;
  map['star'] = paintStar;
  map['heart'] = paintHeart;
  map['cloud'] = paintCloud;
  // 媒体类
  map['play'] = paintPlay;
  map['pause'] = paintPause;
  map['stop'] = paintStop;
  map['mic'] = paintMic;
  return map;
}

const PAINTER_MAP: Record<string, SketchIconPainter> = buildPainterMap();

// ══════════════════════════════════════════════════
// SketchIcon 组件
// ══════════════════════════════════════════════════

@Reusable
@Component
export struct SketchIcon {
  @Prop iconType: SketchIconType = SketchIconType.CHART;
  @Prop iconSize: number = 22;
  @Prop accessibilityLabel: string = '';
  // 外部颜色覆盖（FloatingTabBar 激活态等场景）：非空时优先使用
  // fix: HUI-016 —— Canvas 换肤两件套之二：颜色相关状态变更不会自动重画 Canvas，必须 @Watch 显式重绘
  //   （统计页深色模式下已挂载的图标保持旧墨色 → 黑图标落深色卡面上不可见；与
  //   CheckInRing/MoodBarChart/TodoProgressBar 的 onThemeChange @Watch 为同一套方案）
  @Prop @Watch('onColorChange') strokeColor: string = '';
  // 深色模式感知：ThemeManager 设置 AppStorage['theme_is_dark']，单向只读
  @StorageProp('theme_is_dark') @Watch('onColorChange') isDark: boolean = false;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  /**
   * 首次创建时绘制
   */
  aboutToAppear(): void {
    // draw() 由 onReady() 触发，此处仅做初始化
  }

  /**
   * 组件复用时重绘（@Reusable 生命周期）
   * 框架更新 @Prop 值后调用，触发重绘以反映新状态
   */
  aboutToReuse(params: Record<string, Object>): void {
    // @Prop 变量已由框架自动更新，只需重绘
    this.draw();
  }

  /**
   * fix: HUI-016 —— 主题切换（theme_is_dark）或外部 strokeColor 变化时显式重绘。
   * Canvas 不随状态变量自动重画（PROJECT_SPEC 深色适配「Canvas 换肤两件套」），
   * 缺此步会导致深色模式下已挂载页面（统计页数据卡/签到勾选等）图标保持旧色不可见。
   */
  private onColorChange(): void {
    this.draw();
  }

  /**
   * 核心绘制逻辑：查表 → 找 painter → 执行绘制
   */
  private draw(): void {
    const ctx: CanvasRenderingContext2D = this.ctx;
    const size: number = this.iconSize;
    const iconTypeStr: string = this.iconType as string;

    ctx.clearRect(0, 0, size, size);

    // 颜色优先级：外部 strokeColor > 主题感知
    const color: string = this.strokeColor.length > 0 ?
      this.strokeColor : getStrokeColor(this.isDark);

    // 查 painter 映射表
    const painter: SketchIconPainter | undefined = PAINTER_MAP[iconTypeStr];
    if (painter !== undefined) {
      painter(ctx, size, color);
    }
    // 未匹配的 iconType 静默不绘制（向后兼容未来新增类型）
  }

  build() {
    Canvas(this.ctx)
      .width(this.iconSize)
      .height(this.iconSize)
      .onReady(() => {
        this.draw();
      })
      .backgroundColor(Color.Transparent)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityText(this.accessibilityLabel.length > 0 ?
        this.accessibilityLabel : '')
  }
}
