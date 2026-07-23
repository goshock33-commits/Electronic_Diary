// <!-- agentID: HUI-041 -->
// 模块：碰一碰分享共享类型定义
// 页面/组件：NFC 碰一碰分享（NfcSharePage 及子组件复用）
// 关联任务：F21（PLN-002 阶段8 碰一碰分享 §10.7）
// 关联设计稿：UX-001_prototype.html → page-nfc-share
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式（Stage 模型）
// 说明：接口用于 @Prop 传参，默认值均为空数组/基本类型，不含 $r()（PROJECT_SPEC §9）

/** 发现的邻近设备信息（mock 数据） */
export interface NfcDeviceInfo {
  /** 设备名称，如 "华为 MatePad Pro" */
  name: string;
  /** 设备类型描述，如 "平板" / "手机" */
  typeLabel: string;
  /** 剩余可用存储描述，如 "128 GB 可用" */
  storageLabel: string;
}

/** 待传输图片项（mock：以纯色占位块表示缩略图，避免 $r() 资源在字段初值中） */
export interface TransferImageItem {
  /** 图片序号（唯一） */
  id: number;
  /** 占位缩略图颜色（#RRGGBB） */
  colorHex: string;
  /** 是否被选中 */
  selected: boolean;
}

/** 备份文件信息（mock 数据） */
export interface BackupFileMeta {
  /** 文件名，如 "diary_backup_2026-07-08.hth" */
  fileName: string;
  /** 文件大小描述，如 "4.2 MB" */
  sizeLabel: string;
  /** 包含条目数描述，如 "日记 128 · 待办 56 · 打卡 90" */
  entryLabel: string;
}
