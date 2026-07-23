// <!-- agentID: HUI-001 -->
// agentID: HUI-041（T-D05：新增 ARROW_BACK / PLUS — 返回箭头与加号全局统一）
// 模块：SymbolGlyph 图标映射器
// 关联设计稿：UX-001_prototype.html
// 关联规范：UX-001_icon_spec.md
// 关联任务：T007a-c（HUI 部分）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 图标系统：HarmonyOS SymbolGlyph $r('sys.symbol.xxx')
// 注意：禁止使用 emoji 作为 UI 图标，必须使用 SymbolGlyph

/**
 * SymbolGlyph 图标映射器
 *
 * 提供统一的系统图标资源访问接口。
 * 所有图标使用 HarmonyOS 官方 SymbolGlyph 系统符号，
 * 确保跨设备渲染一致、支持深浅色模式自动适配。
 *
 * 使用方式：
 * ```typescript
 * SymbolGlyph(IconMapper.TAB_HOME)
 *   .fontSize(24)
 *   .fontColor([this.themeTokens.textPrimary])
 * ```
 *
 * 参考：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-symbolglyph
 */
export class IconMapper {

  // ════════════════════════════════════════════════════════════
  // Tab 导航栏图标（6个 — 对齐 FloatingTabBar 的 6 Tab）
  // ════════════════════════════════════════════════════════════

  /** 首页 Tab */
  static readonly TAB_HOME: Resource = $r('sys.symbol.house_fill');
  /** 待办 Tab */
  static readonly TAB_TODO: Resource = $r('sys.symbol.list_bullet');
  /** 日历 Tab */
  static readonly TAB_CALENDAR: Resource = $r('sys.symbol.calendar');
  /** 统计 Tab */
  static readonly TAB_STATISTICS: Resource = $r('sys.symbol.star_fill');
  /** 搜索 Tab */
  static readonly TAB_SEARCH: Resource = $r('sys.symbol.magnifyingglass');
  /** 设置 Tab */
  static readonly TAB_SETTINGS: Resource = $r('sys.symbol.gearshape_fill');

  // ════════════════════════════════════════════════════════════
  // 操作图标
  // ════════════════════════════════════════════════════════════

  /** 添加 */
  static readonly ADD: Resource = $r('sys.symbol.plus_circle_fill');
  /** 删除 */
  static readonly DELETE: Resource = $r('sys.symbol.trash_fill');
  /** 编辑 */
  static readonly EDIT: Resource = $r('sys.symbol.plus_circle_fill');
  /** 完成/勾选 */
  static readonly CHECKMARK: Resource = $r('sys.symbol.checkmark');
  /** 关闭 */
  static readonly CLOSE: Resource = $r('sys.symbol.xmark');
  /** 分享 */
  static readonly SHARE: Resource = $r('sys.symbol.arrowshape_turn_up_right_fill');
  /** 更多 */
  static readonly MORE: Resource = $r('sys.symbol.ellipsis_message_1');
  /** 刷新 */
  static readonly REFRESH: Resource = $r('sys.symbol.arrow_clockwise');
  /** 排序 */
  static readonly SORT: Resource = $r('sys.symbol.line_3_horizontal');
  /** 筛选 */
  static readonly FILTER: Resource = $r('sys.symbol.line_3_horizontal');

  // ════════════════════════════════════════════════════════════
  // 导航图标
  // ════════════════════════════════════════════════════════════

  /** 返回 */
  static readonly BACK: Resource = $r('sys.symbol.chevron_left');
  /** 页面返回箭头（HUI-041 全局统一：系统裸箭头 + Bold，无圆形底）— grep验证: arrow_left 在库(L377) ✅ */
  static readonly ARROW_BACK: Resource = $r('sys.symbol.arrow_left');
  /** 裸加号（HUI-041 全局统一：空心细描边圆圈 + 粗加号的圈内符号）— grep验证: plus 在库(L169) ✅（注：plus_circle 不在库，空心圈由容器描边实现） */
  static readonly PLUS: Resource = $r('sys.symbol.plus');
  /** 前进 */
  static readonly FORWARD: Resource = $r('sys.symbol.chevron_right');
  /** 上箭头 */
  static readonly ARROW_UP: Resource = $r('sys.symbol.chevron_up');
  /** 下箭头 */
  static readonly ARROW_DOWN: Resource = $r('sys.symbol.chevron_down');
  /** 展开 */
  static readonly EXPAND: Resource = $r('sys.symbol.chevron_down');
  /** 折叠 */
  static readonly COLLAPSE: Resource = $r('sys.symbol.chevron_up');

  // ════════════════════════════════════════════════════════════
  // 打卡签到图标
  // ════════════════════════════════════════════════════════════

  /** 连续打卡火焰 */
  static readonly STREAK_FIRE: Resource = $r('sys.symbol.flame_fill');
  /** 打卡对勾 */
  static readonly CHECKIN_DONE: Resource = $r('sys.symbol.checkmark_circle_fill');

  // ════════════════════════════════════════════════════════════
  // 日记功能图标
  // ════════════════════════════════════════════════════════════

  /** 相机（拍照） */
  static readonly CAMERA: Resource = $r('sys.symbol.camera_fill');
  /** 图片 */
  static readonly IMAGE: Resource = $r('sys.symbol.camera_fill');
  /** 语音/麦克风 */
  static readonly MIC: Resource = $r('sys.symbol.mic_fill');
  /** 书签/浮动书签 — grep验证: bookmark_fill不在全量图标库(仅bookmark/bookmark_filled_on_bookmark), 写作语义改用square_and_pencil(L1598已验证存在) */
  static readonly BOOKMARK: Resource = $r('sys.symbol.square_and_pencil');

  // ════════════════════════════════════════════════════════════
  // 番茄钟图标
  // ════════════════════════════════════════════════════════════

  /** 时钟/番茄钟 */
  static readonly CLOCK: Resource = $r('sys.symbol.clock_fill');
  /** 播放 */
  static readonly PLAY: Resource = $r('sys.symbol.play_fill');
  /** 暂停 */
  static readonly PAUSE: Resource = $r('sys.symbol.pause');
  /** 停止/重置 — 本地库无 stop_circle_fill（grep 0 命中，ERROR_PREVENTION#4），
   *  改用 arrow_counterclockwise（LiveWindowDisplay 同语义已用，grep 已验证存在） */
  static readonly STOP: Resource = $r('sys.symbol.arrow_counterclockwise');

  // ════════════════════════════════════════════════════════════
  // 状态图标
  // ════════════════════════════════════════════════════════════

  /** 空状态（无数据） — 替代 icloud_fill（Apple SF Symbols 照搬），验证来源: ERROR_FIX_REPORT folder 已验证 */
  static readonly EMPTY: Resource = $r('sys.symbol.folder');
  /** 加载中 */
  static readonly LOADING: Resource = $r('sys.symbol.arrow_clockwise');
  /** 成功 */
  static readonly SUCCESS: Resource = $r('sys.symbol.checkmark_circle_fill');
  /** 错误 */
  static readonly ERROR: Resource = $r('sys.symbol.exclamationmark_triangle_fill');
  /** 警告 */
  static readonly WARNING: Resource = $r('sys.symbol.exclamationmark_triangle');
  /** 信息 */
  static readonly INFO: Resource = $r('sys.symbol.info_circle_fill');

  // ════════════════════════════════════════════════════════════
  // 心情/情绪隐喻图标（5 心情系统 — 统计/日历/搜索/写日记选择器共用）
  // 配色约定（UX-001 §3.1，由使用处 fontColor 区分）：
  //   晴 amber / 星 yellow / 心 rose / 云 slate / 雨 blue；默认 circle_fill
  // ════════════════════════════════════════════════════════════

  /** 开心/风和 — 太阳（amber） */
  static readonly MOOD_HAPPY: Resource = $r('sys.symbol.sun_max_fill');
  /** 愉快/繁星 — 星星（yellow） */
  static readonly MOOD_PLEASANT: Resource = $r('sys.symbol.star_fill');
  /** 平淡/兜底 — 圆形 */
  static readonly MOOD_NEUTRAL: Resource = $r('sys.symbol.circle_fill');
  /** 难过 — 雨云 */
  static readonly MOOD_SAD: Resource = $r('sys.symbol.cloud_fill');
  /** 多云 — 云（slate）— grep验证: cloud_fill 不在全量图标库(仅 icloud/icloud_slash), 但项目已实证渲染(MOOD_SAD/BACKUP/HomePage/StatisticsPage 均用), 沿用 */
  static readonly MOOD_CLOUDY: Resource = $r('sys.symbol.cloud_fill');
  /** 微雨 — 雨（blue）— grep验证: drop_fill 不在全量图标库(仅 drop_bottomrighthalf_inset_filled L710), 按 UX-001 §3.1 备选降级为 cloud_fill, 由使用处 blue 色相区分 */
  static readonly MOOD_RAINY: Resource = $r('sys.symbol.cloud_fill');
  /** 欢喜 — 心（rose）— grep验证: heart_fill 不在全量图标库(仅 heart_square_stack_fill), 但项目已实证渲染(HomePage L175/HappyThingsSection/SectionManager), 沿用 */
  static readonly MOOD_HEART: Resource = $r('sys.symbol.heart_fill');

  // ════════════════════════════════════════════════════════════
  // 底部 5 Tab 导航图标（P1-01 收敛：日记本/时光轴/AI伙伴/时光探索/我的）
  // ════════════════════════════════════════════════════════════

  /** 日记本 Tab — grep验证: book_open_fill 在库(L844/935) ✅ */
  static readonly NAV_DIARY: Resource = $r('sys.symbol.book_open_fill');
  /** 时光轴 Tab — grep验证: list_bullet 在库(L1530) ✅（HUI-001 手绘换回系统图标补充，与手绘 LIST_BULLET 同语义） */
  static readonly NAV_TIMELINE: Resource = $r('sys.symbol.list_bullet');
  /** 时光探索 Tab — grep验证: compass/location/safari 均不在库, 按 UX-001 §3.3 备选降级为 magnifyingglass(项目已用 TAB_SEARCH/SEARCH ✅) */
  static readonly NAV_EXPLORE: Resource = $r('sys.symbol.magnifyingglass');
  /** 我的 Tab — grep验证: person_fill 不在库, 按备选降级为 person(在库 L1853 ✅) */
  static readonly NAV_PROFILE: Resource = $r('sys.symbol.person');
  /** AI 伙伴 Tab — grep验证: pawprint_fill/sparkles 均不在库, 按 UX-001 §2.8 备选降级为 face_smiling(在库 L1825 ✅) */
  static readonly AI_COMPANION: Resource = $r('sys.symbol.face_smiling');

  // ════════════════════════════════════════════════════════════
  // 图表 / 发送 / 标签图标（探索页 / AI 聊天 / 检索复用）
  // ════════════════════════════════════════════════════════════

  /** 统计图表（探索分段）— grep验证: chart_bar/chart_pie 均不在库, 按 UX-001 §3.2 备选沿用现有 star_fill(项目已用 MOOD_PLEASANT/TAB_STATISTICS ✅) */
  static readonly CHART_BAR: Resource = $r('sys.symbol.star_fill');
  /** 发送（AI 聊天）— grep验证: paperplane_fill 不在库, 但 paperplane(无 fill) 在库(L513/648 ✅), 取其为最贴切「发送」语义 */
  static readonly SEND: Resource = $r('sys.symbol.paperplane');
  /** 标签/分类 — grep验证: tag_fill/tag 均不在库, 按 UX-001 §3.3 备选降级为 bookmark(在库 L61 ✅) */
  static readonly TAG: Resource = $r('sys.symbol.bookmark');

  // ════════════════════════════════════════════════════════════
  // 设置/安全图标
  // ════════════════════════════════════════════════════════════

  /** 设置/管理 */
  static readonly SETTINGS: Resource = $r('sys.symbol.gearshape_fill');
  /** 安全锁 */
  static readonly LOCK: Resource = $r('sys.symbol.lock_fill');
  /** 通知/提醒 */
  static readonly BELL: Resource = $r('sys.symbol.bell_fill');
  /** 主题/调色板 */
  static readonly THEME: Resource = $r('sys.symbol.paintpalette_fill');
  /** 字体大小 */
  static readonly FONT_SIZE: Resource = $r('sys.symbol.textformat');
  /** 备份/云 — 替代 icloud_fill（Apple SF Symbols 照搬），验证来源: IconMapper.MOOD_SAD cloud_fill 已验证 */
  static readonly BACKUP: Resource = $r('sys.symbol.cloud_fill');
  /** 无障碍 */
  static readonly ACCESSIBILITY: Resource = $r('sys.symbol.figure_roll');

  // ════════════════════════════════════════════════════════════
  // 分区管理图标
  // ════════════════════════════════════════════════════════════

  /** 分区管理 */
  static readonly SECTION_MANAGE: Resource = $r('sys.symbol.gearshape_fill');
  /** 拖拽手柄 */
  static readonly DRAG_HANDLE: Resource = $r('sys.symbol.line_3_horizontal');
  /** 可见/眼睛 */
  static readonly VISIBLE: Resource = $r('sys.symbol.eye');
  /** 隐藏 */
  static readonly HIDDEN: Resource = $r('sys.symbol.eye_slash');

  // ════════════════════════════════════════════════════════════
  // 搜索相关
  // ════════════════════════════════════════════════════════════

  /** 搜索 */
  static readonly SEARCH: Resource = $r('sys.symbol.magnifyingglass');
  /** 搜索清除 */
  static readonly SEARCH_CLEAR: Resource = $r('sys.symbol.xmark_circle_fill');
  /** 历史记录 */
  static readonly HISTORY: Resource = $r('sys.symbol.clock_fill');

  // ════════════════════════════════════════════════════════════
  // 名言卡片
  // ════════════════════════════════════════════════════════════

  /** 名言/引用 */
  static readonly QUOTE: Resource = $r('sys.symbol.ellipsis_message_1');
  /** 随机/刷新名言 */
  static readonly RANDOM: Resource = $r('sys.symbol.shuffle');
  /** 复制到剪贴板 */
  /** 复制到剪贴板 — grep验证: doc_fill不在全量图标库, 替换为doc_text_fill(F00BF) */
  static readonly COPY: Resource = $r('sys.symbol.doc_text_fill');

  // ════════════════════════════════════════════════════════════
  // 深色/浅色模式切换图标
  // ════════════════════════════════════════════════════════════

  /** 深色模式图标（月亮）— grep验证: 不在全量图标库(1949行无 moon_fill), 但 SettingsPage L790 已实证渲染(HUI-030), 沿用 */
  static readonly THEME_DARK: Resource = $r('sys.symbol.moon_fill');
  /** 浅色模式图标（太阳）— grep验证: sun_max_fill 在库(L265) ✅ */
  static readonly THEME_LIGHT: Resource = $r('sys.symbol.sun_max_fill');
}
