// <!-- agentID: HUI-047 -->
// 模块：全局排版设计令牌（字号 + 字重）TYPO
// 关联需求：UX-001 §7.1 字重层级 / §7.3 字号层级 / §7.5 黑白重彩逐页
// 关联计划：PLN-003 P0-03
// 开发范式：ArkTS 声明式开发范式
// 说明：黑白重彩「加重字重 + 拉大对比 + 关键数字放大」的字号/字重集中定义。
//       各页 .fontSize()/.fontWeight() 引用 TYPO.*，禁止散写魔数字号/字重。
// 字号缩放：TYPO 从静态 const 改为 class 实例，getter 每次访问时从 AppStorage
//   读取 app_font_scale（1/1.25/1.5），乘以基准字号返回缩放后值。
//   配合 MainPage @StorageLink('app_font_scale') @Watch → themeRebuildFlip
//   子树重建，全局字号实时生效。
// 合规：PROJECT_SPEC §8.2 —— 对象字面量必须有接口类型声明（下方 interface 提供）。
//       FontWeight 为 ArkUI 全局环境枚举（enums.d.ts），无需 import；无 Light，仅 Lighter。

/**
 * 单条排版样式令牌。
 * size：字号（fp / number）；weight：字重，可用 FontWeight 枚举或数值(400/600/700/900)。
 */
export interface TypoStyle {
  /** 字号（fp） */
  readonly size: number;
  /** 字重：FontWeight 枚举或 100-900 数值，二者均可传入 .fontWeight() */
  readonly weight: FontWeight | number;
}

/**
 * 全局排版令牌类型。
 * 依 UX-001 §7.3：主标题/数字借「重彩」放大，最破单调。
 */
export interface TypoTokens {
  /** 页面大标题 H1（时光轴待办 / 打卡统计 / 系统设置） */
  readonly h1: TypoStyle;
  /** 区块 / 分组标题（时光自律轨迹 / 视觉主题美感） */
  readonly sectionTitle: TypoStyle;
  /** 卡片标题（待办任务 / 番茄钟 / 每日提醒） */
  readonly cardTitle: TypoStyle;
  /** 正文 / 内容（日记正文 / 待办文本 / 气泡内容） */
  readonly body: TypoStyle;
  /** eyebrow 英文微标 / 说明（大写宽字距，配次要色） */
  readonly eyebrow: TypoStyle;
  /** 招牌数字（封面日期 08 / 倒计时 / 统计大数） */
  readonly numHero: TypoStyle;
  /** 卡内数字（连续天数 / 累计数 / 百分比） */
  readonly numCard: TypoStyle;
}

/** 基准字号（未缩放） */
interface BaseSizes {
  h1: number;
  sectionTitle: number;
  cardTitle: number;
  body: number;
  eyebrow: number;
  numHero: number;
  numCard: number;
}

const BASE: BaseSizes = {
  h1: 30,
  sectionTitle: 20,
  cardTitle: 16,
  body: 14,
  eyebrow: 12,
  numHero: 48,
  numCard: 28
};

/**
 * 动态排版令牌：getter 每次访问时从 AppStorage 读取 app_font_scale，
 * 乘以基准字号返回缩放后值。AppStorage 为全局对象，无需 import。
 */
class ScaledTypoTokens implements TypoTokens {
  private getScale(): number {
    const scale: number | undefined = AppStorage.get<number>('app_font_scale');
    return scale !== undefined ? scale : 1;
  }

  get h1(): TypoStyle {
    const s: number = this.getScale();
    const style: TypoStyle = { size: BASE.h1 * s, weight: FontWeight.Bold };
    return style;
  }

  get sectionTitle(): TypoStyle {
    const s: number = this.getScale();
    const style: TypoStyle = { size: BASE.sectionTitle * s, weight: 600 };
    return style;
  }

  get cardTitle(): TypoStyle {
    const s: number = this.getScale();
    const style: TypoStyle = { size: BASE.cardTitle * s, weight: 600 };
    return style;
  }

  get body(): TypoStyle {
    const s: number = this.getScale();
    const style: TypoStyle = { size: BASE.body * s, weight: 400 };
    return style;
  }

  get eyebrow(): TypoStyle {
    const s: number = this.getScale();
    const style: TypoStyle = { size: BASE.eyebrow * s, weight: 400 };
    return style;
  }

  get numHero(): TypoStyle {
    const s: number = this.getScale();
    const style: TypoStyle = { size: BASE.numHero * s, weight: 900 };
    return style;
  }

  get numCard(): TypoStyle {
    const s: number = this.getScale();
    const style: TypoStyle = { size: BASE.numCard * s, weight: 900 };
    return style;
  }
}

/**
 * 全局排版令牌（动态缩放）。
 * weight 采用 §7.1：H1=700(Bold)、区块/卡标=600、正文/eyebrow=400、数字=900(Bolder/black)。
 * size 采用 §7.3：H1≈30fp、区块 20、卡标 16、正文 14、eyebrow 12、招牌数字 48、卡内数字 28。
 * 字号在访问时乘以 app_font_scale（1/1.25/1.5），实现全局字号缩放。
 */
export const TYPO: TypoTokens = new ScaledTypoTokens();
