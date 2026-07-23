// <!-- agentID: HUI-047 -->
// agentID: HUI-041（T-D05：新增 ICON 图标尺寸令牌 — 返回箭头/加号全局等大）
// 模块：全局布局设计令牌（圆角 RADIUS + 间距 SPACING + 图标 ICON）
// 关联需求：UX-001 §1.3 圆角系统 / §1.5 间距-栅格
// 关联计划：PLN-003 P0-01（RADIUS）/ P0-02（SPACING）
// 开发范式：ArkTS 声明式开发范式
// 说明：改一处、全 App 联动。所有卡片/条目/输入圆角读 RADIUS；
//       页面/卡内 padding、分区/卡片间距读 SPACING，禁止逐页硬编码魔数。
// 合规：PROJECT_SPEC §8.2 —— 对象字面量必须有接口类型声明（下方 interface 提供）。

/**
 * 圆角令牌类型（单位 vp / number）
 * 依 UX-001 §1.3：超大圆角 bento 是「不单调」的第二大功臣。
 */
export interface RadiusTokens {
  /** 大卡：签到/日历/弹窗/资料 ≈2.5rem */
  readonly cardLg: number;
  /** 主 bento 卡 / 标准卡 ≈2.2rem */
  readonly card: number;
  /** 中卡 ≈2rem / 标准 3xl */
  readonly cardMd: number;
  /** 卡内条目 2xl */
  readonly item: number;
  /** 小标签 / 输入 xl */
  readonly input: number;
}

/**
 * 全局圆角令牌（vp）
 * pill / 头像 / 全圆按钮请直接用「高度/2」或大数（如 999），本表不含。
 */
export const RADIUS: RadiusTokens = {
  cardLg: 40,
  card: 32,
  cardMd: 24,
  item: 16,
  input: 12
};

/**
 * 间距令牌类型（单位 vp / number）
 * 依 UX-001 §1.5：内容区左右 20、分区 24、卡内 24/20/16。
 */
export interface SpacingTokens {
  /** 内容区左右 padding（px-5） */
  readonly pageH: number;
  /** 内容区顶部 padding */
  readonly pageTop: number;
  /** 内容区底部 padding（避让悬浮 Tab 药丸） */
  readonly pageBottom: number;
  /** 分区纵向间距（space-y-6） */
  readonly sectionGap: number;
  /** 卡片间 / 卡内块间距（space-y-4） */
  readonly cardGap: number;
  /** 大卡内 padding（p-6） */
  readonly cardPadLg: number;
  /** 中卡内 padding（p-5） */
  readonly cardPadMd: number;
  /** 小卡内 padding（p-4） */
  readonly cardPadSm: number;
}

/**
 * 全局间距令牌（vp）
 */
export const SPACING: SpacingTokens = {
  pageH: 20,
  pageTop: 16,
  pageBottom: 112,
  sectionGap: 24,
  cardGap: 16,
  cardPadLg: 24,
  cardPadMd: 20,
  cardPadSm: 16
};

/**
 * 图标尺寸令牌类型（单位 vp / number）
 * HUI-041 · T-D05：返回箭头 / 加号按钮全局等大统一。
 * 返回箭头 = 系统裸箭头（sys.symbol.arrow_left）加粗，无圆形底；
 * 加号 = 空心细描边圆圈 + 粗加号（sys.symbol.plus），去实心填充。
 * 尺寸依 HarmonyOS 设计规范：常规图标 24vp 档；触控热区 ≥40vp。
 */
export interface IconSizeTokens {
  /** 返回箭头字号（裸箭头 + Bold，所有页面等大） */
  readonly navBack: number;
  /** 加号空心描边圆圈直径（标准档，所有页面等大） */
  readonly plusRing: number;
  /** 圈内加号字号（标准档，Bold） */
  readonly plus: number;
  /** 加号空心圆圈直径（大档：主操作/悬浮加号，全局统一一档） */
  readonly plusRingLg: number;
  /** 圈内加号字号（大档，Bold） */
  readonly plusLg: number;
  /** 空心圆细描边宽度 */
  readonly ringStroke: number;
  /** 图标按钮最小触控热区（去圆形底后热区不得缩水） */
  readonly touchTarget: number;
}

/**
 * 全局图标尺寸令牌（vp）— 改一处、全 App 联动
 */
export const ICON: IconSizeTokens = {
  navBack: 24,
  plusRing: 24,
  plus: 14,
  plusRingLg: 46,
  plusLg: 24,
  ringStroke: 1.5,
  touchTarget: 40
};
