// <!-- agentID: DEV-004 -->
// 文件: DailyCount.ets
// 任务: 统计页曲线图数据层 — 按日期逐日计数通用返回结构
// 关联契约: features/statistics StatisticsViewModel.getDailySeries(DailyStatsSeries)
// Skill 参考：frontend-design / ui-ux-pro-max

/**
 * 按天聚合计数条目（GROUP BY date 查询返回行）。
 * date 统一 "YYYY-MM-DD"（与全库 date 列格式一致，DateUtils.FORMAT_DATE）。
 */
export interface DailyCount {
  date: string;
  count: number;
}
