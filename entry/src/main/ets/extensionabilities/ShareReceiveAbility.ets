// <!-- agentID: DEV-017 -->
// 文件: ShareReceiveAbility.ets
// 任务: T032 系统分享接收 + NFC碰一碰分享解析
// 关联架构: ARC-001 §3.1 ShareReceiveAbility / §4.2 Skill交互 / S3 多源任务提取
// Skill 参考：frontend-design

import { ShareExtensionAbility } from '@kit.AbilityKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ShareUtils } from '@ohos/shared';
import { EventBus } from '@ohos/shared';
import { common } from '@kit.AbilityKit';

const TAG = 'ShareReceiveAbility';

/**
 * Share callback interface - defined locally as SDK 6.1.1 ShareExtensionAbility
 * does not expose a nested ShareCallback type.
 */
interface ShareCallback {
  onAccept: () => void;
  onReject: (reason: string) => void;
}

/**
 * ShareReceiveAbility - 系统分享接收扩展能力
 *
 * 功能：
 * 1. 接收来自 QQ/微信等外部应用的文本分享
 * 2. 解析分享内容（文本 + 来源应用信息）
 * 3. 触发任务提取流程（跳转 TaskConfirmAbility 或弹出 ClipboardDetector 提示）
 * 4. 处理后返回结果
 * 5. 支持 NFC 碰一碰触发分享接收
 *
 * SDK 6.1.1: ShareExtensionAbility from @kit.AbilityKit
 */
export default class ShareReceiveAbility extends ShareExtensionAbility {
  onCreate(): void {
    hilog.info(0xFF00, TAG, 'ShareReceiveAbility onCreate');
  }

  /**
   * Handle incoming share request from external apps.
   * Called when user selects this app from the system share sheet.
   *
   * @param want The Want containing shared data from the source app
   * @returns ShareCallback with accept/reject handling
   */
  onShare(want: Want): ShareCallback {
    hilog.info(0xFF00, TAG, 'onShare called, bundleName=%{public}s, abilityName=%{public}s',
      want.bundleName ?? 'unknown', want.abilityName ?? 'unknown');

    // Parse the share content from the Want
    const shareContent = ShareUtils.parseShareWant(want);

    if (!shareContent || shareContent.text.length === 0) {
      hilog.warn(0xFF00, TAG, 'Share content is empty, rejecting');
      return {
        onAccept: (): void => {
          hilog.info(0xFF00, TAG, 'Empty share accepted (no-op)');
        },
        onReject: (reason: string): void => {
          hilog.info(0xFF00, TAG, 'Share rejected: %{public}s', reason);
        }
      };
    }

    hilog.info(0xFF00, TAG, 'Share received: source=%{public}s, textLen=%{public}d',
      shareContent.sourceApp, shareContent.text.length);

    // Emit share-received event for TaskExtractionViewModel to process.
    // EventBus.emit auto-wraps into emitter.EventData.data, so pass a FLAT
    // Record<string, Object> payload (aligns with EventBus flat-payload design
    // and the sibling TASK_EXTRACTED emit in TaskExtractionViewModel).
    const taskPayload: Record<string, Object> = {};
    taskPayload['source'] = `share:${shareContent.sourceApp}`;
    taskPayload['sourceApp'] = shareContent.sourceApp;
    taskPayload['sourceBundle'] = shareContent.sourceBundle;
    taskPayload['rawText'] = shareContent.text;
    taskPayload['taskId'] = -1;
    taskPayload['isNfc'] = false;
    EventBus.emit(EventBus.EventNames.TASK_EXTRACTED, taskPayload);

    return {
      onAccept: (): void => {
        hilog.info(0xFF00, TAG, 'Share accepted from %{public}s', shareContent.sourceApp);
        // Store the share data for the app to process when resumed
        AppStorage.setOrCreate('pendingShareText', shareContent.text);
        AppStorage.setOrCreate('pendingShareSource', shareContent.sourceApp);
        AppStorage.setOrCreate('pendingShareBundle', shareContent.sourceBundle);
      },
      onReject: (reason: string): void => {
        hilog.info(0xFF00, TAG, 'Share rejected: %{public}s', reason);
        AppStorage.setOrCreate('pendingShareText', '');
        AppStorage.setOrCreate('pendingShareSource', '');
      }
    };
  }

  onDestroy(): void {
    hilog.info(0xFF00, TAG, 'ShareReceiveAbility onDestroy');
  }
}
