// <!-- agentID: HUI-049 -->
// 模块：全局字体族预设 FONT（字体族名常量集中定义）
// 关联需求：UX-001 招牌数字 / 倒计时 / 统计大数 采用等宽 JetBrains Mono
// 关联计划：PLN-003 P0-07（方案A：应用启动时 font.registerFont 注册自定义字体）
// 开发范式：ArkTS 声明式开发范式
// 合规：PROJECT_SPEC §8.2（对象字面量必须有接口类型声明，下方 interface 提供）
//       §1.4（模块名三者一致：本文件由 shared 模块 '@ohos/shared' 导出）
//
// ── 字体分工（重要）────────────────────────────────────────────────
// · 中文：一律走系统鸿蒙字体 HarmonyOS Sans（FONT.sans / FONT.serif），
//         JetBrains Mono 为纯英文数字字体，不含中文字形，切勿用于中文文本。
// · JetBrains Mono：仅用于「数字 / 英文等宽」场景 —— 招牌日期、倒计时、统计数字。
//         使用方式：Text('08').fontFamily(FONT.monoBold) 之类。
//
// ── 4 字重映射（JetBrains Mono 无 900，设计要 900 时降级用 800 ExtraBold）──
//   设计字重(§7.1)   →  实际字体族(familyName)            →  字重(ttf)
//   400 Regular      →  FONT.mono          'JetBrains Mono'            400
//   500 Medium       →  FONT.monoMedium    'JetBrains Mono Medium'    500
//   600/700 Bold     →  FONT.monoBold      'JetBrains Mono Bold'      700
//   800/900 Black     →  FONT.monoExtraBold 'JetBrains Mono ExtraBold' 800
//
// ── 为何一个字重对应一个 familyName ────────────────────────────────
//   API 24 本地声明 @ohos.font.d.ts 的 FontOptions 只有 { familyName, familySrc }，
//   没有 weight 字段（已 grep 自证）。故 registerFont 无法把多个字重合并到同一
//   familyName 下由 .fontWeight() 区分，必须为每个字重注册一个独立 familyName。
//   实际渲染时对 mono 文本应「选族名」而非「靠 .fontWeight() 加粗」。
//   注册逻辑见 entry/.../entryability/EntryAbility.ets 的 registerMonoFonts()。

/**
 * 字体族名预设类型。
 * mono/monoMedium/monoBold/monoExtraBold 为已注册的 JetBrains Mono 4 字重族名；
 * sans/serif 直接使用系统鸿蒙字体（无需注册）。
 * sketchTitle/sketchBody 为手绘风格字体（需在 EntryAbility 中注册）。
 */
export interface FontFamilyPresets {
  /** 等宽 400 Regular —— 数字/英文常规 */
  readonly mono: string;
  /** 等宽 500 Medium —— 数字/英文中等 */
  readonly monoMedium: string;
  /** 等宽 700 Bold —— 数字/英文加粗（含设计 600） */
  readonly monoBold: string;
  /** 等宽 800 ExtraBold —— 招牌大数/统计数字（设计 900 降级至此） */
  readonly monoExtraBold: string;
  /** 无衬线：系统鸿蒙字体（中文正文/标题默认） */
  readonly sans: string;
  /** 衬线位：项目统一复用系统鸿蒙字体（无独立衬线体） */
  readonly serif: string;
  /** 手绘标题体：猫啃什锦黑（马克笔风格，用于H1/大数字/sectionTitle/eyebrow）
   *  Fallback 链：MaokenAssortedSans → HarmonyOS Sans → sans-serif
   *  familyName 须与 EntryAbility.registerSketchFonts() 中一致。 */
  readonly sketchTitle: string;
  /** 手绘正文字：清松手写体2（自然手写风格，用于body/标签/辅助文字）
   *  Fallback 链：QingSongHandwriting2 → HarmonyOS Sans → sans-serif
   *  familyName 须与 EntryAbility.registerSketchFonts() 中一致。 */
  readonly sketchBody: string;
}

/**
 * 全局字体族预设。
 * mono* 族名须与 EntryAbility.registerMonoFonts() 中 registerFont 的 familyName 完全一致。
 * sketchTitle/sketchBody 族名须与 EntryAbility.registerSketchFonts() 中 registerFont 的 familyName 完全一致。
 */
export const FONT: FontFamilyPresets = {
  mono: 'JetBrains Mono',
  monoMedium: 'JetBrains Mono Medium',
  monoBold: 'JetBrains Mono Bold',
  monoExtraBold: 'JetBrains Mono ExtraBold',
  sans: 'HarmonyOS Sans',
  serif: 'HarmonyOS Sans',
  sketchTitle: 'MaokenAssortedSans',
  sketchBody: 'QingSongHandwriting2'
};
