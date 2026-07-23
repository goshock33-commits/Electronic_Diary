// <!-- agentID: DEV-007 (M17-RINGTONE 铃声试听 + 提醒铃声映射) -->
// 文件: RingtonePlayUtils.ets
// 任务: M17-RINGTONE —— 「我的」页选铃声无任何声音:补齐铃声试听播放能力 + 铃声 id → 真实音源映射。
// 技术路线: @ohos.multimedia.media AVPlayer 播放 entry/src/main/resources/rawfile/ 下的合成铃声 WAV。
//   为何不用 systemSoundManager: 本 SDK 公开 API 仅含相机快门/录像音(SystemSoundType 只有
//   PHOTO_SHUTTER/VIDEO_RECORDING_*,见 @ohos.multimedia.systemSoundManager.d.ts L36-61),
//   系统铃声/通知音的枚举与播放器均未开放给三方应用,故走 AVPlayer + rawfile 自带音源。
// API 核实来源(E:\DevEco Studio\sdk\default\openharmony\ets\api\):
//   · media.createAVPlayer(): Promise<AVPlayer>                     (@ohos.multimedia.media.d.ts L114)
//   · AVPlayer.fdSrc?: AVFileDescriptor (idle 态可设)                (L2649)
//   · AVPlayer.prepare()/play()/stop()/reset()/release(): Promise    (L2005/L2055/L2161/L2217/L2267)
//   · AVPlayer.on('stateChange', OnAVPlayerStateChangeHandle)        (L3040)
//   · AVPlayer.on('error', ErrorCallback)                            (L3739)
//   · type AVPlayerState = 'idle'|'initialized'|'prepared'|'playing'|... (L1778)
//   · interface AVFileDescriptor { fd; offset?; length? }            (L4689)
//   · resourceManager.getRawFd(path): Promise<RawFileDescriptor>     (@ohos.resourceManager.d.ts L3548)
//   · resourceManager.closeRawFd(path): Promise<void>                (L3616)
//   · RawFileDescriptor { fd; offset; length }                       (global/rawFileDescriptor.d.ts L66/89/112)
//   · WAV 为 AVPlayer 支持的音频格式("The audio formats M4A, AAC, MP3, OGG, WAV, FLAC, and AMR", L2601)
// 关联: ReminderAgentService(提醒 customRingUri 复用本类映射) / ReminderSettingsPage(前端 F11 试听接线,本类不碰 UI)。
// 编译坑对照 后端开发文档.md §十一: 无 any/unknown;无解构/spread;shared 内部相对路径 import;局部变量显式类型。

import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'RingtonePlayUtils';
const DOMAIN = 0x0000;

/**
 * M17-RINGTONE(DEV-007): 铃声元信息(id 与设置页 mock 列表对齐;file 为 entry rawfile 下真实音源文件名)。
 */
export interface RingtoneMeta {
  readonly id: string;
  readonly name: string;
  readonly file: string;
}

// M17-RINGTONE(DEV-007): 铃声 id → 真实音源映射真相源。
// id 清单与 features/settings ReminderSettingsPage.ets 的 RINGTONES mock 一致(default/nature/gentle/chime/vibrant);
// file 均已随包放置于 entry/src/main/resources/rawfile/(合成 WAV,44.1kHz 16bit mono)。
// 若日后接入系统铃声,替换此表的 file 为系统音 uri 并调整 play() 的取源分支即可,对外 API 不变。
const RINGTONE_TABLE: RingtoneMeta[] = [
  { id: 'default', name: '默认铃声', file: 'ringtone_default.wav' },
  { id: 'nature', name: '清晨鸟鸣', file: 'ringtone_nature.wav' },
  { id: 'gentle', name: '轻柔钢琴', file: 'ringtone_gentle.wav' },
  { id: 'chime', name: '风铃声', file: 'ringtone_chime.wav' },
  { id: 'vibrant', name: '活力节拍', file: 'ringtone_vibrant.wav' }
];

/**
 * RingtonePlayUtils - 铃声试听播放 + 铃声 id → 音源映射(M17-RINGTONE)。
 *
 * 全局单实例播放(静态持有 AVPlayer):再次 play 自动停掉上一次,不会叠音。
 * · play(ringtoneId, context): 试听指定铃声,进入 playing 返回 true;任何失败 hilog.error + false,不静默。
 * · stop(): 停止并释放当前试听(页面退出/切换时调用,幂等)。
 * · isPlaying(): 当前是否正在试听(前端切换按钮态可用)。
 * · listRingtones(): 内置铃声清单(id/name/file),供前端替换 mock 列表。
 * · resolveRingFile(id): id → rawfile 文件名,ReminderAgentService.customRingUri 复用同一映射,试听与真实提醒同源。
 */
export class RingtonePlayUtils {
  // 当前播放会话(同一时刻至多一个)。
  private static player: media.AVPlayer | null = null;
  // getRawFd 已打开、待 closeRawFd 归还的 rawfile 路径与其 resourceManager。
  private static openedPath: string | null = null;
  private static openedResMgr: resourceManager.ResourceManager | null = null;
  // 播放代际令牌:每次 play/stop 自增,异步回调只认最新代,防止快速连点串音/操作已释放实例。
  private static generation: number = 0;

  /**
   * 内置铃声清单(拷贝返回,防外部改动内部表)。
   */
  static listRingtones(): RingtoneMeta[] {
    return RINGTONE_TABLE.slice(0);
  }

  /**
   * 铃声 id → rawfile 音源文件名。未知 id 回退默认铃声(不抛错,试听/提醒都能兜底出声)。
   */
  static resolveRingFile(ringtoneId: string): string {
    for (let i = 0; i < RINGTONE_TABLE.length; i++) {
      if (RINGTONE_TABLE[i].id === ringtoneId) {
        return RINGTONE_TABLE[i].file;
      }
    }
    hilog.warn(DOMAIN, TAG, 'resolveRingFile: unknown ringtoneId=%{public}s, fallback to default', ringtoneId);
    return RINGTONE_TABLE[0].file;
  }

  /**
   * 当前是否正在试听播放。
   */
  static isPlaying(): boolean {
    const p: media.AVPlayer | null = RingtonePlayUtils.player;
    return p !== null && p.state === 'playing';
  }

  /**
   * 试听播放指定铃声(自动停掉上一次试听)。
   * @param ringtoneId 铃声 id(default/nature/gentle/chime/vibrant;未知 id 回退默认)。
   * @param context 任意 Context(取 resourceManager 读 rawfile;页面侧 getContext(this) 传入)。
   * @returns 进入 playing 返回 true;任何环节失败记 hilog.error 并返回 false。
   */
  static async play(ringtoneId: string, context: common.Context): Promise<boolean> {
    const myGen: number = ++RingtonePlayUtils.generation;
    // 停掉上一次(释放旧 player + 归还旧 fd),保证单实例。
    await RingtonePlayUtils.releaseCurrent();

    const file: string = RingtonePlayUtils.resolveRingFile(ringtoneId);
    const resMgr: resourceManager.ResourceManager = context.resourceManager;

    // 1) 打开 rawfile 描述符。
    let rawFd: resourceManager.RawFileDescriptor;
    try {
      rawFd = await resMgr.getRawFd(file);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'play: getRawFd(%{public}s) failed: code=%{public}d msg=%{public}s',
        file, e.code, e.message);
      return false;
    }
    if (myGen !== RingtonePlayUtils.generation) {
      // 已被更新的 play/stop 取代:归还 fd 退出。
      RingtonePlayUtils.safeCloseRawFd(resMgr, file);
      return false;
    }

    // 2) 创建 AVPlayer。
    let avPlayer: media.AVPlayer;
    try {
      avPlayer = await media.createAVPlayer();
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'play: createAVPlayer failed: code=%{public}d msg=%{public}s', e.code, e.message);
      RingtonePlayUtils.safeCloseRawFd(resMgr, file);
      return false;
    }
    if (myGen !== RingtonePlayUtils.generation) {
      try {
        await avPlayer.release();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'play: stale player release failed: %{public}s', (err as BusinessError).message);
      }
      RingtonePlayUtils.safeCloseRawFd(resMgr, file);
      return false;
    }

    RingtonePlayUtils.player = avPlayer;
    RingtonePlayUtils.openedPath = file;
    RingtonePlayUtils.openedResMgr = resMgr;

    // 3) 状态机驱动: idle --fdSrc--> initialized --prepare--> prepared --play--> playing。
    //    进入 playing 兑现 true;error/中途被取代兑现 false。播放到 completed 自动释放资源。
    return new Promise<boolean>((resolve: (v: boolean) => void) => {
      let settled: boolean = false;
      const settle = (ok: boolean): void => {
        if (!settled) {
          settled = true;
          resolve(ok);
        }
      };

      avPlayer.on('error', (err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'play: AVPlayer error: code=%{public}d msg=%{public}s', err.code, err.message);
        settle(false);
        if (myGen === RingtonePlayUtils.generation) {
          // 异步清理(error 态只能 reset/release),不阻塞回调。
          RingtonePlayUtils.releaseCurrent();
        }
      });

      avPlayer.on('stateChange', (state: media.AVPlayerState, reason: media.StateChangeReason) => {
        if (myGen !== RingtonePlayUtils.generation) {
          settle(false);
          return;
        }
        if (state === 'initialized') {
          avPlayer.prepare().catch((err: BusinessError) => {
            hilog.error(DOMAIN, TAG, 'play: prepare failed: code=%{public}d msg=%{public}s', err.code, err.message);
            settle(false);
            RingtonePlayUtils.releaseCurrent();
          });
        } else if (state === 'prepared') {
          avPlayer.play().catch((err: BusinessError) => {
            hilog.error(DOMAIN, TAG, 'play: play() failed: code=%{public}d msg=%{public}s', err.code, err.message);
            settle(false);
            RingtonePlayUtils.releaseCurrent();
          });
        } else if (state === 'playing') {
          hilog.info(DOMAIN, TAG, 'play: ringtone %{public}s (%{public}s) playing', ringtoneId, file);
          settle(true);
        } else if (state === 'completed') {
          // 试听播完自动释放(短音频一次播放,不循环)。
          RingtonePlayUtils.releaseCurrent();
        }
      });

      // 设 fdSrc 触发 idle -> initialized(必须在 on 注册之后)。
      const fdSrc: media.AVFileDescriptor = {
        fd: rawFd.fd,
        offset: rawFd.offset,
        length: rawFd.length
      };
      avPlayer.fdSrc = fdSrc;
    });
  }

  /**
   * 停止并释放当前试听(无试听时为空操作,幂等;页面退出/切换铃声前调用)。
   */
  static async stop(): Promise<void> {
    ++RingtonePlayUtils.generation; // 使在途 play 回调全部失效
    await RingtonePlayUtils.releaseCurrent();
  }

  /**
   * 释放当前 player + 归还 rawfile fd(内部复用;所有异常仅记日志,不外抛)。
   */
  private static async releaseCurrent(): Promise<void> {
    const p: media.AVPlayer | null = RingtonePlayUtils.player;
    const path: string | null = RingtonePlayUtils.openedPath;
    const mgr: resourceManager.ResourceManager | null = RingtonePlayUtils.openedResMgr;
    RingtonePlayUtils.player = null;
    RingtonePlayUtils.openedPath = null;
    RingtonePlayUtils.openedResMgr = null;
    if (p !== null) {
      try {
        await p.release(); // release 任意状态可调,一步到位释放
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'releaseCurrent: release failed: %{public}s', (err as BusinessError).message);
      }
    }
    if (mgr !== null && path !== null) {
      RingtonePlayUtils.safeCloseRawFd(mgr, path);
    }
  }

  /**
   * 归还 rawfile 描述符(fire-and-forget,失败仅记日志)。
   */
  private static safeCloseRawFd(mgr: resourceManager.ResourceManager, path: string): void {
    mgr.closeRawFd(path).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'closeRawFd(%{public}s) failed: %{public}s', path, err.message);
    });
  }
}
