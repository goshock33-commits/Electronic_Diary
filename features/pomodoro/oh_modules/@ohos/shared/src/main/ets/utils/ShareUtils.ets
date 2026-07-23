// <!-- agentID: DEV-001 -->
// File: ShareUtils.ets
// Task: T007c Data utility - System share receiving, text parsing, source app info
// Architecture: ARC-001 4.2 Skill interaction / S3 task extraction
// Skill Ref: frontend-design / ui-ux-pro-max

import { hilog } from '@kit.PerformanceAnalysisKit';
import { wantConstant } from '@kit.AbilityKit';
import { Want } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';

const TAG = 'ShareUtils';

/**
 * Parsed share content from external apps (QQ, WeChat, etc.).
 */
export interface ShareContent {
  /** The extracted text content */
  text: string;
  /** Source application name (if available) */
  sourceApp: string;
  /** Source application bundle name (if available) */
  sourceBundle: string;
  /** MIME type of the shared content */
  mimeType: string;
  /** Raw Want parameters for extended access */
  extras: Record<string, Object>;
}

/**
 * ShareUtils - System share receiving and parsing utilities.
 * Handles: receiving shared content from external apps, text extraction,
 * source app identification, Intent parameters parsing.
 */
export class ShareUtils {
  /**
   * Parse share content from a Want received by ShareReceiveAbility.
   *
   * @param want The Want object from the share event.
   * @returns Parsed ShareContent or null if no valid content found.
   */
  static parseShareWant(want: Want): ShareContent | null {
    try {
      const parameters = want.parameters ?? {};
      const extras: Record<string, Object> = {};

      // Extract known share keys
      let text = '';
      let sourceApp = '未知应用';
      let sourceBundle = '';
      let mimeType = 'text/plain';

      // Try to get shared text from various possible keys
      if (parameters['ohos.extra.param.key.share.text'] as string) {
        text = parameters['ohos.extra.param.key.share.text'] as string;
      } else if (parameters[wantConstant.Params.ABILITY_BACK_TO_OTHER_MISSION_STACK] as string) {
        text = parameters[wantConstant.Params.ABILITY_BACK_TO_OTHER_MISSION_STACK] as string;
      } else if (parameters['shareText'] as string) {
        text = parameters['shareText'] as string;
      } else if (parameters['text'] as string) {
        text = parameters['text'] as string;
      }

      // Try to get source app info
      if (parameters['ohos.extra.param.key.share.source'] as string) {
        sourceApp = parameters['ohos.extra.param.key.share.source'] as string;
      }
      if (parameters['callerBundleName'] as string) {
        sourceBundle = parameters['callerBundleName'] as string;
        // Derive friendly name from bundle
        if (sourceBundle.includes('com.tencent.mm')) {
          sourceApp = '微信';
        } else if (sourceBundle.includes('com.tencent.mobileqq')) {
          sourceApp = 'QQ';
        }
      }

      // Build extras map for extended access
      const paramKeys = Object.keys(parameters);
      for (const key of paramKeys) {
        const value = parameters[key];
        if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
          extras[key] = value;
        }
      }

      if (text.length === 0) {
        hilog.warn(0x0000, TAG, 'No share text found in Want');
        return null;
      }

      const content: ShareContent = {
        text: text,
        sourceApp: sourceApp,
        sourceBundle: sourceBundle,
        mimeType: mimeType,
        extras: extras
      };

      hilog.info(0x0000, TAG, 'Share parsed: source=%{public}s, textLen=%{public}d',
        sourceApp, text.length);
      return content;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Failed to parse share Want: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  /**
   * Extract a task-relevant description from shared text.
   * Cleans up and truncates the text for AI extraction processing.
   *
   * @param text Raw shared text.
   * @param maxLength Maximum allowed length for AI processing.
   * @returns Cleaned text suitable for task extraction.
   */
  static extractTaskText(text: string, maxLength: number = 500): string {
    if (!text) {
      return '';
    }
    // Remove excessive whitespace
    let cleaned = text.replace(/\s+/g, ' ').trim();
    // Truncate to max length
    if (cleaned.length > maxLength) {
      cleaned = cleaned.substring(0, maxLength) + '...';
    }
    return cleaned;
  }

  /**
   * Check if the shared text potentially contains task information.
   * Quick pre-check before invoking AI extraction.
   */
  static mightContainTaskInfo(text: string): boolean {
    if (!text || text.length < 5) {
      return false;
    }
    const taskIndicators = [
      '时间', '日期', '地点', '地点在', '截止', '任务', '作业',
      '考试', '会议', '完成', '明天', '今天', '下周', '周', '月', '日',
      '要', '必须', '需要', '请', '通知', '安排', '记得', '别忘了',
      'exam', 'deadline', 'meeting', 'homework'
    ];
    return taskIndicators.some((kw: string) => text.includes(kw));
  }

  /**
   * Create a share Want for use within the app (for internal navigation).
   *
   * @param bundleName Target app bundle name.
   * @param abilityName Target ability name.
   * @param text Text to share.
   * @returns Want object for startAbility.
   */
  static createShareWant(bundleName: string, abilityName: string, text: string): Want {
    return {
      bundleName: bundleName,
      abilityName: abilityName,
      parameters: {
        'shareText': text,
        'ohos.extra.param.key.share.text': text
      }
    };
  }

  /**
   * Check if the app was launched via share (cold start from external share).
   *
   * @param want Launch Want from onCreate.
   * @returns The shared text or null if not launched via share.
   */
  static isShareLaunch(want: Want): string | null {
    try {
      const parameters = want.parameters ?? {};
      const shareText = parameters['ohos.extra.param.key.share.text'] as string ??
        parameters['shareText'] as string;
      return shareText && shareText.length > 0 ? shareText : null;
    } catch (_err) {
      return null;
    }
  }
}
