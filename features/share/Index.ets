// <!-- agentID: HUI-064 -->（承接 HUI-063 / 原 HUI-041）
// 模块入口：碰一碰分享（features_share）
// 关联计划：PLN-003 P2-07b（各 stage @Builder 内容实现：检测脉冲 / 设备卡 / 进度环 / 完成 / 错误三态）
// §1.4 三者一致：模块 name = features_share = 依赖 key = import 路径
//
// 导出：模态框内容主体 NfcSharePage（P2-07b：stage 状态机 + 各 stage 完整内容 + 三模式切换器 + 关闭）
//       + stage/scenario/errorType 类型 + 共享数据类型
//       + 5 个原独立弹窗 UI 组件（骨架期 mock 参考，内容已迁入 NfcSharePage 各 stage @Builder）
// agentID: DEV-M14 — added ShareViewModel export
export type { NfcDeviceInfo, TransferImageItem, BackupFileMeta } from './src/main/ets/model/NfcShareTypes';
export { NfcSharePage } from './src/main/ets/pages/NfcSharePage';
export type { ShareScenario, ShareStage, ShareErrorType } from './src/main/ets/pages/NfcSharePage';
export { NfcDetectionView } from './src/main/ets/components/NfcDetectionView';
export { DeviceFoundDialog } from './src/main/ets/components/DeviceFoundDialog';
export { ImageTransferSelector } from './src/main/ets/components/ImageTransferSelector';
export { TransferProgressDialog } from './src/main/ets/components/TransferProgressDialog';
export { BackupReceiveConfirmDialog } from './src/main/ets/components/BackupReceiveConfirmDialog';
// agentID: DEV-M14
export { ShareViewModel } from './src/main/ets/viewmodel/ShareViewModel';
