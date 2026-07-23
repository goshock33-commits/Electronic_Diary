// <!-- agentID: HUI-026 -->
// fix: F5-v2
// 任务提取模块导出（F12）
export { ExtractedTaskCard } from './src/main/ets/components/ExtractedTaskCard';
export { TaskSourceIndicator } from './src/main/ets/components/TaskSourceIndicator';
export { TaskTypeBadge } from './src/main/ets/components/TaskTypeBadge';
// HUI-065 · P2-11：任务确认弹窗内容主体 + 展示项类型
export { TaskConfirmView, type ConfirmTaskItem } from './src/main/ets/components/TaskConfirmView';
// agentID: DEV-003
export { TaskExtractionViewModel } from './src/main/ets/viewmodel/TaskExtractionViewModel';
// fix: F5-v2 — 提取结果类型补导出（AIChatView 显式标注用）
export { type ExtractionResult } from './src/main/ets/viewmodel/TaskExtractionViewModel';
// extract_task AI 升级 — 类别枚举补导出（AIIntentHandler 构造 ExtractionResult 用）
export { TaskCategory } from './src/main/ets/viewmodel/TaskExtractionViewModel';
// fix: F5-v2 — FloatingEntry 已按用户审查移除；保留前台剪贴板检测器 ClipboardDetector
export { ClipboardDetector } from './src/main/ets/components/ClipboardDetector';
