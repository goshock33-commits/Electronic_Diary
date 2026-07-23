// <!-- agentID: HUI-001 -->
// fix: HUI-FRONTEND
export { CheckInRing } from './src/main/ets/components/CheckInRing';
export { MoodBarChart, type MoodDataItem } from './src/main/ets/components/MoodBarChart';
export { TodoProgressBar } from './src/main/ets/components/TodoProgressBar';
// agentID: HUI-001 — 统计页四线趋势曲线图（顶部四卡替换，"笔画出来"入场动画）
export { TrendLineChart, type TrendChartData } from './src/main/ets/components/TrendLineChart';
// agentID: HUI-016 — 批次1 T007：SketchIcon 体系（SketchIcon/SketchThemeAdapter/SketchCanvasUtils/painters）
//   已迁至 shared（shared/src/main/ets/components/sketch/），此处不再导出。
//   引用方改从 '@ohos/shared' 引入（避免 shared→features/statistics 循环依赖）。
// agentID: DEV-003
// agentID: DEV-004 — 曲线图契约：DailyStatsSeries 随 StatisticsViewModel 同路径导出（StatisticsPage 既有 import 路径）
export { StatisticsViewModel, type DailyStatsSeries } from './src/main/ets/viewmodel/StatisticsViewModel';
// fix: HUI-FRONTEND — F6：统计页周/月切换需按周期拉数，导出 StatsPeriod（loadPeriod 入参枚举）与 MonthStats（返回类型）
export { StatsPeriod, type MonthStats } from './src/main/ets/viewmodel/StatisticsViewModel';
