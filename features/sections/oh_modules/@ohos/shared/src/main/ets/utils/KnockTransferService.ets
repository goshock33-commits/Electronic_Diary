// fix: DEV-014
// File: KnockTransferService.ets
// Task: T-B02 碰一碰「传备份/收备份」真实传输通道（业务层传输面，与 KnockShareService 载荷引擎解耦）
// 通道选型（本地 SDK .d.ts 实证，PROJECT_SPEC §10 真相源纪律）：
//   Share Kit harmonyShare（@kit.ShareKit → @hms.collaboration.harmonyShare.d.ts）
//   · 发送：harmonyShare.on('knockShare', cb)（since 5.0.0(12)）——两机 NFC 碰一碰时系统回调
//     SharableTarget，target.share(systemShare.SharedData{utd, uri}) 即经华为分享通道把文件送达对端
//   · 接收：harmonyShare.on('dataReceive', {windowId, capabilities}, cb)（since 6.0.0(20)，
//     本 SDK 6.1.1/API 24 可用）——对端碰传时回调 ReceivableTarget，receive(接收目录 URI) 落地文件
//   · 全 API 无 @permission 标注（.d.ts 实证），无需新增权限
// NFC 状态：@kit.ConnectivityKit → @ohos.nfc.controller（isNfcAvailable/isNfcOpen 无权限要求）
// 降级纪律：canIUse 守卫 SystemCapability.Collaboration.HarmonyShare / Communication.NFC.Core，
//   模拟器/无该系统能力设备诚实返回不可用（绝不假成功、不假进度）。

import { harmonyShare, systemShare } from '@kit.ShareKit';
import { nfcController } from '@kit.ConnectivityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'KnockTransferService';

const SYSCAP_HARMONY_SHARE = 'SystemCapability.Collaboration.HarmonyShare';
const SYSCAP_NFC_CORE = 'SystemCapability.Communication.NFC.Core';

/** NFC 硬件状态标签：on=已开启 / off=已关闭（可引导用户打开）/ unsupported=本机无 NFC 系统能力（模拟器常见） */
export type NfcStateLabel = 'on' | 'off' | 'unsupported';

/** 发送结果回调：success=true 表示 share() Promise 已 resolve（文件已交给华为分享通道送达对端） */
export type KnockSendResultCallback = (success: boolean, message: string) => void;

/** 接收文件回调：uris 为落地到接收目录后系统回传的文件 URI 列表 */
export type KnockReceiveFilesCallback = (uris: string[]) => void;

/** 碰一碰物理触发回调（发送/接收侧均在系统回调到达那一刻触发，可用于 UI 切「传输中」） */
export type KnockTriggeredCallback = () => void;

/** 失败回调 */
export type KnockFailCallback = (message: string) => void;

/**
 * KnockTransferService —— 碰一碰传输通道封装（纯传输面：只搬字节，不理解包内容）。
 * 载荷由 KnockShareService（DEV-013）产出/消费，本服务负责把 .ediary.zip 经华为分享通道送达/接回。
 *
 * 生命周期：armSend/armReceive 注册系统回调（武装），碰一碰物理触发后自动完成传输；
 * disarmSend/disarmReceive 取消注册（页面关闭/取消时必须调用，防泄漏重复回调）。
 */
export class KnockTransferService {
  private static sendArmed: boolean = false;
  private static recvArmed: boolean = false;
  private static knockCallback: ((target: harmonyShare.SharableTarget) => void) | null = null;
  private static recvCallback: ((target: harmonyShare.ReceivableTarget) => void) | null = null;
  private static recvRegistry: harmonyShare.RecvCapabilityRegistry | null = null;

  /** 华为分享（碰一碰）系统能力是否可用。模拟器上通常为 false。 */
  static isChannelAvailable(): boolean {
    return canIUse(SYSCAP_HARMONY_SHARE);
  }

  /**
   * 查询 NFC 硬件状态（碰一碰的物理触发依赖 NFC）。
   * .d.ts 依据：@ohos.nfc.controller isNfcAvailable()/isNfcOpen()，均无 @permission 要求。
   */
  static getNfcStateLabel(): NfcStateLabel {
    if (!canIUse(SYSCAP_NFC_CORE)) {
      return 'unsupported';
    }
    try {
      if (!nfcController.isNfcAvailable()) {
        return 'unsupported';
      }
      return nfcController.isNfcOpen() ? 'on' : 'off';
    } catch (err) {
      hilog.warn(0x0000, TAG, 'getNfcStateLabel failed: %{public}s', (err as BusinessError).message);
      return 'unsupported';
    }
  }

  /**
   * 武装发送侧：注册 knockShare 回调。碰一碰触发时把 filePath 指向的备份包经华为分享送达对端。
   * @param filePath 备份包本地绝对路径（KnockShareService.exportFullBackup 产出的 .ediary.zip）
   * @param title 分享面板展示的文件标题
   * @param onKnocked 碰一碰物理触发瞬间回调（UI 可切「传输中」）
   * @param onResult 传输结束回调（share() resolve/reject 的真实结果，非假进度）
   * @returns 是否武装成功（通道不可用/注册异常返回 false）
   */
  static armSend(filePath: string, title: string,
    onKnocked: KnockTriggeredCallback, onResult: KnockSendResultCallback): boolean {
    if (!KnockTransferService.isChannelAvailable()) {
      hilog.warn(0x0000, TAG, 'armSend: HarmonyShare syscap unavailable on this device');
      return false;
    }
    KnockTransferService.disarmSend();
    const shareUri: string = fileUri.getUriFromPath(filePath);
    const cb = (target: harmonyShare.SharableTarget): void => {
      hilog.info(0x0000, TAG, 'knockShare triggered, sharing %{public}s', title);
      onKnocked();
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.ZIP_ARCHIVE,
        uri: shareUri,
        title: title,
        description: '电子手账全量备份包（.ediary.zip）'
      };
      const data: systemShare.SharedData = new systemShare.SharedData(record);
      target.share(data).then(() => {
        hilog.info(0x0000, TAG, 'knockShare share() resolved');
        onResult(true, '备份包已经华为分享通道发出');
      }).catch((err: BusinessError) => {
        hilog.error(0x0000, TAG, 'knockShare share() failed: %{public}s', err.message);
        onResult(false, '碰一碰发送失败：' + err.message);
      });
    };
    try {
      harmonyShare.on('knockShare', cb);
      KnockTransferService.knockCallback = cb;
      KnockTransferService.sendArmed = true;
      hilog.info(0x0000, TAG, 'armSend ok: %{public}s', filePath);
      return true;
    } catch (err) {
      hilog.error(0x0000, TAG, 'armSend register failed: %{public}s', (err as BusinessError).message);
      return false;
    }
  }

  /** 解除发送武装（幂等）。 */
  static disarmSend(): void {
    if (!KnockTransferService.sendArmed) {
      return;
    }
    try {
      if (KnockTransferService.knockCallback !== null) {
        harmonyShare.off('knockShare', KnockTransferService.knockCallback);
      }
    } catch (err) {
      hilog.warn(0x0000, TAG, 'disarmSend off failed: %{public}s', (err as BusinessError).message);
    }
    KnockTransferService.knockCallback = null;
    KnockTransferService.sendArmed = false;
  }

  /**
   * 武装接收侧：注册 dataReceive 回调（需 windowId，故为异步——window.getLastWindow 实证
   * @ohos.window.d.ts getLastWindow(ctx): Promise<Window> / WindowProperties.id: number）。
   * 对端碰传 .ediary.zip 时，文件落地 receiveDirPath 后经 onFiles 回传 URI，由调用方走
   * KnockShareService.importBackupFromUri 落库。
   * @param context 上下文（取窗口 id；页面侧 getContext(this) as common.Context）
   * @param receiveDirPath 接收目录本地绝对路径（不存在会自动创建）
   * @param onKnocked 碰一碰物理触发瞬间回调
   * @param onFiles 文件落地回调（真实文件 URI）
   * @param onFail 失败回调
   * @returns 是否武装成功
   */
  static async armReceive(context: common.Context, receiveDirPath: string,
    onKnocked: KnockTriggeredCallback, onFiles: KnockReceiveFilesCallback,
    onFail: KnockFailCallback): Promise<boolean> {
    if (!KnockTransferService.isChannelAvailable()) {
      hilog.warn(0x0000, TAG, 'armReceive: HarmonyShare syscap unavailable on this device');
      return false;
    }
    KnockTransferService.disarmReceive();
    try {
      fileIo.mkdirSync(receiveDirPath, true);
    } catch (_e) {
      // 目录已存在
    }
    const receiveUri: string = fileUri.getUriFromPath(receiveDirPath);
    try {
      const win: window.Window = await window.getLastWindow(context);
      const winId: number = win.getWindowProperties().id;
      const cap: harmonyShare.RecvCapability = {
        utd: uniformTypeDescriptor.UniformDataType.ZIP_ARCHIVE,
        maxSupportedCount: 1
      };
      const registry: harmonyShare.RecvCapabilityRegistry = {
        windowId: winId,
        capabilities: [cap]
      };
      const cb = (target: harmonyShare.ReceivableTarget): void => {
        hilog.info(0x0000, TAG, 'dataReceive triggered');
        onKnocked();
        const recvCb: harmonyShare.ReceiveCallback = {
          onDataReceived: (data: systemShare.SharedData): void => {
            const records: systemShare.SharedRecord[] = data.getRecords();
            const uris: string[] = [];
            for (let i: number = 0; i < records.length; i++) {
              const u: string | undefined = records[i].uri;
              if (u !== undefined && u.length > 0) {
                uris.push(u);
              }
            }
            hilog.info(0x0000, TAG, 'dataReceive got %{public}d file(s)', uris.length);
            onFiles(uris);
          },
          onResult: (code: harmonyShare.ShareResultCode): void => {
            if (code !== harmonyShare.ShareResultCode.SHARE_SUCCESS) {
              hilog.warn(0x0000, TAG, 'dataReceive ended with code %{public}d', code);
              onFail('接收未完成（结果码 ' + code + '）');
            }
          }
        };
        target.receive(receiveUri, recvCb).catch((err: BusinessError) => {
          hilog.error(0x0000, TAG, 'receive() failed: %{public}s', err.message);
          onFail('接收启动失败：' + err.message);
        });
      };
      harmonyShare.on('dataReceive', registry, cb);
      KnockTransferService.recvCallback = cb;
      KnockTransferService.recvRegistry = registry;
      KnockTransferService.recvArmed = true;
      hilog.info(0x0000, TAG, 'armReceive ok: windowId=%{public}d dir=%{public}s', winId, receiveDirPath);
      return true;
    } catch (err) {
      hilog.error(0x0000, TAG, 'armReceive failed: %{public}s', (err as BusinessError).message);
      return false;
    }
  }

  /** 解除接收武装（幂等）。 */
  static disarmReceive(): void {
    if (!KnockTransferService.recvArmed) {
      return;
    }
    try {
      if (KnockTransferService.recvRegistry !== null && KnockTransferService.recvCallback !== null) {
        harmonyShare.off('dataReceive', KnockTransferService.recvRegistry, KnockTransferService.recvCallback);
      }
    } catch (err) {
      hilog.warn(0x0000, TAG, 'disarmReceive off failed: %{public}s', (err as BusinessError).message);
    }
    KnockTransferService.recvCallback = null;
    KnockTransferService.recvRegistry = null;
    KnockTransferService.recvArmed = false;
  }

  /** 解除全部武装（页面关闭/VM destroy 用）。 */
  static disarmAll(): void {
    KnockTransferService.disarmSend();
    KnockTransferService.disarmReceive();
  }
}
