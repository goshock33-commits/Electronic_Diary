// fix: DEV-014
// <!-- agentID: DEV-M14 -->
// File: ShareViewModel.ets
// Task: T-B02 碰一碰「传备份/收备份」传输链路实装（业务层）——mock 定时器状态机替换为真实链路：
//   传备份：KnockShareService.exportFullBackup（DEV-013 载荷契约，格式勿动）→ KnockTransferService.armSend
//          （Share Kit harmonyShare 'knockShare'）→ 碰一碰物理触发 → share() 真实送达 → done
//   收备份：KnockTransferService.armReceive（harmonyShare 'dataReceive'）→ 碰一碰触发 → 文件落地 →
//          KnockShareService.importBackupFromUri（表恢复+照片重建全自动）→ done
//   降级纪律：模拟器/无华为分享系统能力设备 → 生成包 + 停在 detecting（等待对端）+ 明确降级提示
//            （AppStorage 'shareTransferNote'），绝不假进度条冒充成功。
// Architecture: ARC-001 S6 NFC share / B01 EventBus / R0-3 AppStorage
// Pattern: Follows PomodoroViewModel (M08) and GestureDiaryViewModel (M12) patterns
//
// ─── 给 HUI 的接口契约（UI 接线依据，NfcSharePage 下一棒替换自带 mock 状态机）───
// 方法：
//   init()                      初始化（同步 AppStorage 初态）
//   setContext(ctx)             注入上下文（getContext(this) as common.Context；startDetection 前必调）
//   setScenario('image'|'backup'|'receive')  切场景（idle/detecting 阶段可切）
//   startDetection()            真实链路入口：NFC 前置检查 → 生成包（传备份）→ 武装碰一碰通道 → 等碰
//   startTransfer()             UI 兼容入口：未武装时等价 startDetection；已武装时 no-op（碰一碰物理触发即自动传输）
//   cancelDetection()/cancelTransfer()  解除通道武装并回 idle
//   reset()/destroy()           复位/销毁（均解除武装）
//   getStage()/getScenario()/getProgress()/getError()/getDetectedDevice()  同步读
// AppStorage 键（@StorageLink 用）：
//   shareStage: ShareStage      idle|detecting|device|transfer|done|error（真实链路不停留 device——
//                               碰一碰即传，detecting 直接进 transfer；detectedDevice 仍会填充）
//   shareScenario: ShareScenario
//   shareProgress: number       真实里程碑进度（传：碰到=60/送达=100；收：碰到=30/落地=70/入库=100），无假定时器
//   shareError: ShareErrorType  nfcOff|incompatible|storage（error 阶段有效）
//   shareTransferNote: string   人话状态/降级提示（含包大小/行数/图数、模拟器降级说明），UI 直接展示
//   shareChannelAvailable: boolean  华为分享系统能力是否可用（false=模拟器/不支持设备）
//   shareBackupPath/shareBackupSizeBytes/shareBackupRowCount/shareBackupImageCount/shareBackupTableCount  传备份包元信息
//   shareImportRowCount/shareImportImageCount/shareImportTableCount  收备份恢复结果
// EventBus：SHARE_STAGE_CHANGED（stage/scenario/progress[/errorType]）、BACKUP_COMPLETED（done 时）

import { EventBus, KnockShareService, KnockTransferService } from '@ohos/shared';
import type { BackupExportResult, BackupImportResult, NfcStateLabel } from '@ohos/shared';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { NfcDeviceInfo } from '../model/NfcShareTypes';
import type { ShareScenario, ShareStage, ShareErrorType } from '../pages/NfcSharePage';

const TAG = 'ShareViewModel';

/**
 * ShareViewModel - Manages NFC share flow state machine (real transport since DEV-014).
 *
 * Stages: idle → detecting(武装等碰) → transfer(碰一碰触发后真实传输) → done / error
 * Scenarios: backup (传备份) / receive (收备份) / image (本轮未接通道，明确报不支持)
 */
export class ShareViewModel {
  private currentStage: ShareStage = 'idle';
  private currentScenario: ShareScenario = 'image';
  private currentError: ShareErrorType = 'nfcOff';
  private transferProgress: number = 0;
  private detectedDevice: NfcDeviceInfo | null = null;
  /** fix: DEV-014 · 上下文（取 filesDir / 窗口 id），页面侧 setContext 注入 */
  private context: common.Context | null = null;
  /** fix: DEV-014 · 通道武装标记（防重复注册；碰一碰物理触发后自动进入传输） */
  private armed: boolean = false;

  /**
   * Initialize - set idle state in AppStorage.
   */
  init(): void {
    this.syncToAppStorage();
    AppStorage.setOrCreate('shareChannelAvailable', KnockTransferService.isChannelAvailable());
    hilog.info(0x0000, TAG, 'ShareViewModel init: stage=idle, scenario=%{public}s', this.currentScenario);
  }

  /**
   * fix: DEV-014 · 注入上下文（getContext(this) as common.Context）。startDetection 前必调。
   */
  setContext(context: common.Context): void {
    this.context = context;
  }

  /**
   * Set the share scenario (image/backup/receive).
   */
  setScenario(scenario: ShareScenario): void {
    if (this.currentStage !== 'idle' && this.currentStage !== 'detecting') {
      hilog.warn(0x0000, TAG, 'Cannot switch scenario during stage=%{public}s', this.currentStage);
      return;
    }
    if (this.currentStage === 'detecting') {
      // fix: DEV-014 · detecting 中切场景需先解除已武装通道，防旧场景回调串线
      KnockTransferService.disarmAll();
      this.armed = false;
      this.transitionTo('idle');
    }
    this.currentScenario = scenario;
    AppStorage.setOrCreate('shareScenario', scenario);
    hilog.info(0x0000, TAG, 'Scenario set: %{public}s', scenario);
  }

  /**
   * fix: DEV-014 · 真实链路入口：NFC 前置检查 → （传备份）生成包 → 武装碰一碰通道 → 等待物理碰一碰。
   * 碰一碰触发后自动进入 transfer 并完成真实传输，无假定时器。
   */
  async startDetection(): Promise<void> {
    if (this.armed) {
      hilog.info(0x0000, TAG, 'startDetection: already armed, waiting for knock');
      return;
    }
    AppStorage.setOrCreate('shareChannelAvailable', KnockTransferService.isChannelAvailable());
    // NFC 真实前置检查（@ohos.nfc.controller，碰一碰物理触发依赖 NFC）
    const nfc: NfcStateLabel = KnockTransferService.getNfcStateLabel();
    if (nfc === 'off') {
      this.setNote('NFC 已关闭：请在系统设置中打开 NFC 后重试');
      this.setError('nfcOff');
      return;
    }
    this.detectedDevice = null;
    if (this.currentScenario === 'backup') {
      await this.armBackupSend(nfc);
    } else if (this.currentScenario === 'receive') {
      await this.armBackupReceive(nfc);
    } else {
      // image 场景不在 T-B02 范围：单篇日记碰传图的数据面在 DiaryViewModel/KnockShareService，
      // 通道未接线，明确报不支持（不做假流程）
      this.setNote('图片碰传通道尚未接入（本轮仅「传备份/收备份」），请切换备份场景');
      this.setError('incompatible');
    }
  }

  /**
   * Cancel detection (back to idle).
   */
  cancelDetection(): void {
    KnockTransferService.disarmAll();
    this.armed = false;
    this.transitionTo('idle');
    this.detectedDevice = null;
  }

  /**
   * fix: DEV-014 · UI 兼容入口：真实链路中「传输」由碰一碰物理触发自动开始（SharableTarget 回调内
   * 必须立即 share），无法由按钮驱动。未武装时等价 startDetection（走完整真实链路）；已武装时 no-op。
   */
  async startTransfer(): Promise<void> {
    if (!this.armed) {
      await this.startDetection();
      return;
    }
    hilog.info(0x0000, TAG, 'startTransfer: armed, transfer auto-starts on knock');
  }

  /**
   * Cancel transfer.
   */
  cancelTransfer(): void {
    KnockTransferService.disarmAll();
    this.armed = false;
    this.transferProgress = 0;
    this.transitionTo('idle');
  }

  /**
   * Set error state with a specific error type.
   * Note: transitionTo('error') emits SHARE_STAGE_CHANGED with errorType included.
   */
  setError(errorType: ShareErrorType): void {
    this.currentError = errorType;
    this.transitionTo('error');
    hilog.error(0x0000, TAG, 'Share error: %{public}s', errorType);
  }

  /**
   * Reset to idle.
   */
  reset(): void {
    KnockTransferService.disarmAll();
    this.armed = false;
    this.currentStage = 'idle';
    this.currentScenario = 'image';
    this.currentError = 'nfcOff';
    this.transferProgress = 0;
    this.detectedDevice = null;
    this.syncToAppStorage();
  }

  /** Get current stage */
  getStage(): ShareStage {
    return this.currentStage;
  }

  /** Get current scenario */
  getScenario(): ShareScenario {
    return this.currentScenario;
  }

  /** Get transfer progress */
  getProgress(): number {
    return this.transferProgress;
  }

  /** Get current error type */
  getError(): ShareErrorType {
    return this.currentError;
  }

  /** Get detected device */
  getDetectedDevice(): NfcDeviceInfo | null {
    return this.detectedDevice;
  }

  /**
   * Cleanup - disarm transport channel on destroy.
   */
  destroy(): void {
    KnockTransferService.disarmAll();
    this.armed = false;
  }

  /* ---- fix: DEV-014 · 真实链路私有实现 ---- */

  /**
   * 传备份：生成全量备份包（DEV-013 载荷契约）→ 武装 knockShare 发送通道。
   */
  private async armBackupSend(nfc: NfcStateLabel): Promise<void> {
    if (this.context === null) {
      this.setNote('内部错误：未注入上下文（页面需先调用 setContext）');
      this.setError('storage');
      return;
    }
    this.transitionTo('detecting');
    this.setNote('正在生成全量备份包…');
    const result: BackupExportResult | null = await KnockShareService.exportFullBackup(this.context.filesDir);
    if (result === null) {
      this.setNote('备份包生成失败（数据库导出异常）');
      this.setError('storage');
      return;
    }
    AppStorage.setOrCreate('shareBackupPath', result.path);
    AppStorage.setOrCreate('shareBackupSizeBytes', result.sizeBytes);
    AppStorage.setOrCreate('shareBackupRowCount', result.rowCount);
    AppStorage.setOrCreate('shareBackupImageCount', result.imageCount);
    AppStorage.setOrCreate('shareBackupTableCount', result.tableCount);
    const sizeMb: string = (result.sizeBytes / (1024 * 1024)).toFixed(2);
    const metaText: string = sizeMb + ' MB · ' + result.tableCount + ' 表 ' + result.rowCount + ' 行 · '
      + result.imageCount + ' 图';
    if (!KnockTransferService.isChannelAvailable()) {
      // 诚实降级：包已真实生成，但本机无华为分享系统能力（模拟器常见）→ 停在 detecting，不假进度
      this.setNote('备份包已生成（' + metaText + '），但本机无华为分享系统能力（模拟器/不支持设备），'
        + '无法碰一碰发送。包已留存本机备份列表，可在设置页手动导出。');
      hilog.warn(0x0000, TAG, 'armBackupSend: channel unavailable, staying in detecting (degraded)');
      return;
    }
    const fileName: string = this.fileBaseName(result.path);
    const ok: boolean = KnockTransferService.armSend(result.path, fileName,
      (): void => {
        this.onKnockTriggered(60, '碰一碰已触发，正在经华为分享发送备份包…');
      },
      (success: boolean, message: string): void => {
        this.onSendResult(success, message);
      });
    if (!ok) {
      this.setNote('碰一碰发送通道注册失败');
      this.setError('incompatible');
      return;
    }
    this.armed = true;
    const nfcHint: string = nfc === 'unsupported' ? '（注意：本机未检测到 NFC，碰一碰可能无法物理触发）' : '';
    this.setNote('备份包已生成（' + metaText + '），请将两台设备背对背碰一碰' + nfcHint);
    hilog.info(0x0000, TAG, 'armBackupSend: armed, waiting for knock, path=%{public}s', result.path);
  }

  /**
   * 收备份：武装 dataReceive 接收通道 → 碰一碰触发 → 文件落地 → importBackupFromUri 恢复。
   */
  private async armBackupReceive(nfc: NfcStateLabel): Promise<void> {
    if (this.context === null) {
      this.setNote('内部错误：未注入上下文（页面需先调用 setContext）');
      this.setError('storage');
      return;
    }
    this.transitionTo('detecting');
    if (!KnockTransferService.isChannelAvailable()) {
      // 诚实降级：停在 detecting，提示替代路径（系统分享文件打开 → EntryAbility.handleKnockWant 兜底）
      this.setNote('本机无华为分享系统能力（模拟器/不支持设备），无法碰一碰接收。'
        + '可让对端经系统分享发送备份文件，用本 App 打开即可自动恢复。');
      hilog.warn(0x0000, TAG, 'armBackupReceive: channel unavailable, staying in detecting (degraded)');
      return;
    }
    const ctx: common.Context = this.context;
    const ok: boolean = await KnockTransferService.armReceive(ctx, ctx.filesDir + '/received',
      (): void => {
        this.onKnockTriggered(30, '碰一碰已触发，正在接收备份包…');
      },
      (uris: string[]): void => {
        this.handleReceivedFiles(uris);
      },
      (message: string): void => {
        this.onReceiveFail(message);
      });
    if (!ok) {
      this.setNote('碰一碰接收通道注册失败');
      this.setError('incompatible');
      return;
    }
    this.armed = true;
    const nfcHint: string = nfc === 'unsupported' ? '（注意：本机未检测到 NFC，碰一碰可能无法物理触发）' : '';
    this.setNote('接收通道已就绪，请将两台设备背对背碰一碰' + nfcHint);
    hilog.info(0x0000, TAG, 'armBackupReceive: armed, waiting for knock');
  }

  /**
   * 碰一碰物理触发（系统回调到达）：填充对端信息 → 进入 transfer（真实链路无「确认设备」窗口，
   * SharableTarget 须在回调内立即消费，故不停留 device 阶段）。
   */
  private onKnockTriggered(progress: number, note: string): void {
    const device: NfcDeviceInfo = {
      name: '已碰到的对端设备',
      typeLabel: '华为分享',
      storageLabel: ''
    };
    this.detectedDevice = device;
    this.emitDeviceFound();
    this.transitionTo('transfer');
    this.setProgressValue(progress);
    this.setNote(note);
  }

  /** 发送结果（share() Promise 的真实 resolve/reject，非假进度） */
  private onSendResult(success: boolean, message: string): void {
    this.armed = false;
    KnockTransferService.disarmSend();
    if (success) {
      this.setProgressValue(100);
      this.setNote(message);
      this.transitionTo('done');
      this.emitTransferComplete();
    } else {
      this.setNote(message);
      this.setError('incompatible');
    }
  }

  /** 接收文件落地 → importBackupFromUri（DEV-013 签名勿动）表恢复 + 照片重建 */
  private handleReceivedFiles(uris: string[]): void {
    if (uris.length === 0) {
      this.onReceiveFail('碰一碰接收结束但未收到有效文件');
      return;
    }
    if (this.context === null) {
      this.onReceiveFail('内部错误：上下文丢失');
      return;
    }
    this.setProgressValue(70);
    this.setNote('备份包已接收，正在恢复数据…');
    const baseDir: string = this.context.filesDir;
    const uri: string = uris[0];
    KnockShareService.importBackupFromUri(baseDir, uri).then((result: BackupImportResult | null) => {
      if (result === null) {
        this.onReceiveFail('备份包解析或恢复失败（口令/格式不匹配）');
        return;
      }
      AppStorage.setOrCreate('shareImportRowCount', result.rowCount);
      AppStorage.setOrCreate('shareImportImageCount', result.imageCount);
      AppStorage.setOrCreate('shareImportTableCount', result.tableCount);
      this.armed = false;
      KnockTransferService.disarmReceive();
      this.setProgressValue(100);
      this.setNote('恢复完成：' + result.tableCount + ' 表 · ' + result.rowCount + ' 行 · '
        + result.imageCount + ' 图');
      this.transitionTo('done');
      this.emitTransferComplete();
    }).catch((err: Error) => {
      this.onReceiveFail('导入异常：' + err.message);
    });
  }

  /** 接收失败统一处理 */
  private onReceiveFail(message: string): void {
    this.armed = false;
    KnockTransferService.disarmReceive();
    this.setNote(message);
    this.setError('storage');
  }

  /* ---- Private helpers ---- */

  private transitionTo(stage: ShareStage): void {
    this.currentStage = stage;
    this.syncToAppStorage();
    this.emitStageChanged();
    hilog.info(0x0000, TAG, 'Stage transition: %{public}s', stage);
  }

  private syncToAppStorage(): void {
    AppStorage.setOrCreate('shareStage', this.currentStage);
    AppStorage.setOrCreate('shareScenario', this.currentScenario);
    AppStorage.setOrCreate('shareProgress', this.transferProgress);
    if (this.currentStage === 'error') {
      AppStorage.setOrCreate('shareError', this.currentError);
    }
  }

  /** fix: DEV-014 · 人话状态/降级提示（AppStorage 'shareTransferNote'，UI 直接展示） */
  private setNote(note: string): void {
    AppStorage.setOrCreate('shareTransferNote', note);
  }

  /** fix: DEV-014 · 真实里程碑进度（无定时器） */
  private setProgressValue(progress: number): void {
    this.transferProgress = progress;
    AppStorage.setOrCreate('shareProgress', progress);
  }

  /** fix: DEV-014 · 提取文件名 */
  private fileBaseName(path: string): string {
    const lastSlash: number = path.lastIndexOf('/');
    return lastSlash >= 0 ? path.substring(lastSlash + 1) : path;
  }

  private emitStageChanged(): void {
    const payload: Record<string, Object> = {};
    payload['stage'] = this.currentStage;
    payload['scenario'] = this.currentScenario;
    payload['progress'] = this.transferProgress;
    // Include errorType in error stage so consumers can discriminate
    if (this.currentStage === 'error') {
      payload['errorType'] = this.currentError as Object;
    }
    EventBus.emit(EventBus.EventNames.SHARE_STAGE_CHANGED, payload);
  }

  private emitDeviceFound(): void {
    const payload: Record<string, Object> = {};
    payload['stage'] = 'device';
    payload['deviceName'] = this.detectedDevice?.name ?? '';
    EventBus.emit(EventBus.EventNames.SHARE_STAGE_CHANGED, payload);
  }

  private emitTransferComplete(): void {
    const payload: Record<string, Object> = {};
    payload['stage'] = 'done';
    payload['scenario'] = this.currentScenario;
    EventBus.emit(EventBus.EventNames.BACKUP_COMPLETED, payload);
  }
}
