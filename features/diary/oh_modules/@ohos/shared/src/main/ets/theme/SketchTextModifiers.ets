// <!-- agentID: HUI-025 -->
// 模块：集中手绘字体助手 SketchTextModifiers（AttributeModifier<TextAttribute> 一行套用）
// 关联需求：UX-001 §7 手绘字体分工 / HUI-021 盘点报告 §2.3「方案A」（改动最小、与 TYPO 体系一致）
// 关联计划：全局 ~365 个 Text 手绘化 —— 本文件只建基础设施，逐页套用为后续任务
// 开发范式：ArkTS 声明式开发范式
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming（均已按序调用）
//
// ── 目的 ────────────────────────────────────────────────────────────
//   避免 365 处 Text 逐行手写 `.fontFamily(FONT.sketchXxx)`。页面只需一行
//   `.attributeModifier(SKETCH_XXX)` 即可套上手绘字体（可选连字号+字重）。
//
// ── 字体分工（务必遵守，来自 UX-001 §7 + HUI-021 §2.3）─────────────────
//   · 标题类（h1 / sectionTitle / eyebrow）→ FONT.sketchTitle 猫啃什锦黑（马克笔粗标题）
//   · 正文类（cardTitle / body / 标签）    → FONT.sketchBody  清松手写体2（自然手写）
//   · 🚫 纯数字 / 英文等宽（招牌数字 numHero、卡内数字 numCard、倒计时、统计大数）
//        一律保留 FONT.mono*（JetBrains Mono）——清松/猫啃不含等宽数字字形，勿套手绘。
//        故本文件「不」提供 numHero / numCard 的手绘 modifier，此为刻意取舍。
//   · fallback 链（字体注册见 EntryAbility.registerSketchFonts）：
//        sketchTitle: MaokenAssortedSans → HarmonyOS Sans → sans-serif
//        sketchBody : QingSongHandwriting2 → HarmonyOS Sans → sans-serif
//
// ── API 依据（本地 SDK .d.ts / API 24，已 grep 自证）──────────────────
//   · AttributeModifier<T>       component/common.d.ts:19945 —— applyNormalAttribute?(instance: T): void
//   · TextAttribute              component/text.d.ts:184     —— fontFamily / fontSize / fontWeight 均在其上
//   · attributeModifier(m): T    component/common.d.ts:27952 —— Text 上 T = TextAttribute
//   AttributeModifier / TextAttribute / FontWeight 均为 ArkUI 全局环境声明，无需 import。
//
// 合规：PROJECT_SPEC §8.1 首行 HTML 注释须包在 `//` 行注释内（本行即是，安全）；
//       §8.2 无匿名对象字面量（导出的均为 class 实例）；无 any/unknown；跨模块用 '@ohos/shared'。

import { FONT } from './FontPresets';
import { TYPO } from './TypographyTokens';

// ════════════════════════════════════════════════════════════════════
// 一、基础字体族 modifier（只换字体族，不动字号/字重）
//     适用：页面已用 .fontSize(TYPO.x.size)/.fontWeight(TYPO.x.weight)，只想补字体。
// ════════════════════════════════════════════════════════════════════

/** 手绘标题字体族（猫啃什锦黑）——仅设 fontFamily=FONT.sketchTitle。 */
export class SketchTitleModifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance.fontFamily(FONT.sketchTitle);
  }
}

/** 手绘正文字体族（清松手写体2）——仅设 fontFamily=FONT.sketchBody。 */
export class SketchBodyModifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance.fontFamily(FONT.sketchBody);
  }
}

// ════════════════════════════════════════════════════════════════════
// 二、TYPO 各级组合 modifier（字号 + 字重 + 手绘字体，一行到位）
//     适用：新写/整段替换 Text，直接一行套齐三项，无需再散写 TYPO。
//     字体分工映射见文件头（标题类走 sketchTitle，正文类走 sketchBody）。
// ════════════════════════════════════════════════════════════════════

/** H1 页面大标题：sketchTitle + TYPO.h1（30fp / Bold）。 */
export class SketchH1Modifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance.fontFamily(FONT.sketchTitle).fontSize(TYPO.h1.size).fontWeight(TYPO.h1.weight);
  }
}

/** 区块 / 分组标题：sketchTitle + TYPO.sectionTitle（20fp / 600）。 */
export class SketchSectionTitleModifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance.fontFamily(FONT.sketchTitle).fontSize(TYPO.sectionTitle.size).fontWeight(TYPO.sectionTitle.weight);
  }
}

/** 卡片标题：sketchBody + TYPO.cardTitle（16fp / 600）。 */
export class SketchCardTitleModifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance.fontFamily(FONT.sketchBody).fontSize(TYPO.cardTitle.size).fontWeight(TYPO.cardTitle.weight);
  }
}

/** 正文 / 内容：sketchBody + TYPO.body（14fp / 400）。 */
export class SketchBodyTypoModifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance.fontFamily(FONT.sketchBody).fontSize(TYPO.body.size).fontWeight(TYPO.body.weight);
  }
}

/** eyebrow 英文微标 / 说明：sketchTitle + TYPO.eyebrow（12fp / 400）。 */
export class SketchEyebrowModifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance.fontFamily(FONT.sketchTitle).fontSize(TYPO.eyebrow.size).fontWeight(TYPO.eyebrow.weight);
  }
}

// ════════════════════════════════════════════════════════════════════
// 三、共享单例（无状态 → 全 App 复用同一实例，最省内存；页面直接引用即可）
//     ⚠️ 这些 modifier 无 @State，故可安全共享；勿在其中放随实例变化的状态。
// ════════════════════════════════════════════════════════════════════

/** 只套手绘标题字体族（不含字号/字重）。 */
export const SKETCH_TITLE: SketchTitleModifier = new SketchTitleModifier();
/** 只套手绘正文字体族（不含字号/字重）。 */
export const SKETCH_BODY: SketchBodyModifier = new SketchBodyModifier();

/** H1：手绘标题字体 + 30fp/Bold。 */
export const SKETCH_H1: SketchH1Modifier = new SketchH1Modifier();
/** 区块标题：手绘标题字体 + 20fp/600。 */
export const SKETCH_SECTION_TITLE: SketchSectionTitleModifier = new SketchSectionTitleModifier();
/** 卡片标题：手绘正文字体 + 16fp/600。 */
export const SKETCH_CARD_TITLE: SketchCardTitleModifier = new SketchCardTitleModifier();
/** 正文：手绘正文字体 + 14fp/400。 */
export const SKETCH_BODY_TYPO: SketchBodyTypoModifier = new SketchBodyTypoModifier();
/** eyebrow：手绘标题字体 + 12fp/400。 */
export const SKETCH_EYEBROW: SketchEyebrowModifier = new SketchEyebrowModifier();

// ════════════════════════════════════════════════════════════════════
// 四、用法示例（供后续逐页 HUI 参考）
// ════════════════════════════════════════════════════════════════════
//
// 先在页面顶部从 shared 引入所需单例：
//   import { SKETCH_H1, SKETCH_BODY_TYPO, SKETCH_TITLE, FONT, TYPO } from '@ohos/shared';
//
// 【场景 A】新写 Text，一行套齐「字号+字重+手绘字体」（最常用）：
//   Text('我的日记')
//     .attributeModifier(SKETCH_H1)          // = 30fp + Bold + 猫啃什锦黑
//     .fontColor(this.tokens ? this.tokens.textPrimary : '#000000')
//
//   Text('今天的心情很不错')
//     .attributeModifier(SKETCH_BODY_TYPO)   // = 14fp + 400 + 清松手写体2
//
// 【场景 B】页面已散写 TYPO（不想动原字号/字重），仅补手绘字体 —— 用基础族 modifier：
//   Text('设置')
//     .fontSize(TYPO.sectionTitle.size)
//     .fontWeight(TYPO.sectionTitle.weight)
//     .attributeModifier(SKETCH_TITLE)       // 只加字体族，字号/字重保持原样
//
// 【场景 C】纯数字 / 英文等宽 —— 🚫 不要套手绘，仍用 mono（本文件不提供数字 modifier）：
//   Text('08').fontFamily(FONT.monoExtraBold).fontSize(TYPO.numHero.size)   // 招牌大数：保留 mono
//   Text('28').fontFamily(FONT.monoExtraBold).fontSize(TYPO.numCard.size)   // 卡内数字：保留 mono
//
// 【字体分工速查】
//   标题/区块/eyebrow → SKETCH_H1 / SKETCH_SECTION_TITLE / SKETCH_EYEBROW（猫啃什锦黑）
//   卡片标题/正文/标签 → SKETCH_CARD_TITLE / SKETCH_BODY_TYPO（清松手写体2）
//   纯数字/等宽       → 保留 FONT.mono*（勿套手绘）
