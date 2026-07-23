// <!-- agentID: DEV-001 -->
// File: ClipboardUtils.ets
// Task: T007b Media utility - Clipboard read, change monitoring, text extraction
// Architecture: ARC-001 4.4 pasteboard / S3 task extraction
// Skill Ref: frontend-design / ui-ux-pro-max

import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'ClipboardUtils';

/**
 * Clipboard content result.
 */
export interface ClipboardContent {
  /** Raw clipboard text */
  text: string;
  /** Clipboard data type (text/html/uri) */
  type: string;
  /** Timestamp when the content was read */
  timestamp: number;
}

/**
 * ClipboardUtils - System clipboard interaction for task extraction.
 * Handles: reading clipboard content, monitoring changes, text extraction.
 */
export class ClipboardUtils {
  private static changeListener: ((content: ClipboardContent) => void) | null = null;
  private static systemPasteboard: pasteboard.SystemPasteboard | null = null;
  private static lastContent: string = '';

  /**
   * Get the system pasteboard instance.
   */
  private static getPasteboard(): pasteboard.SystemPasteboard {
    if (!ClipboardUtils.systemPasteboard) {
      ClipboardUtils.systemPasteboard = pasteboard.getSystemPasteboard();
    }
    return ClipboardUtils.systemPasteboard;
  }

  /**
   * Read text content from the clipboard.
   * @returns The clipboard text content or null if empty/unavailable.
   */
  static async getText(): Promise<string | null> {
    try {
      const pb = ClipboardUtils.getPasteboard();
      const data = await pb.getData();
      const text = data.getPrimaryText();
      return text && text.length > 0 ? text : null;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Failed to read clipboard: %{public}s', error.message);
      return null;
    }
  }

  /**
   * Read full clipboard content with metadata.
   */
  static async getContent(): Promise<ClipboardContent | null> {
    try {
      const text = await ClipboardUtils.getText();
      if (!text) {
        return null;
      }
      return {
        text: text,
        type: 'text/plain',
        timestamp: Date.now()
      };
    } catch (err) {
      hilog.error(0x0000, TAG, 'Failed to get clipboard content: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  /**
   * Write text to the clipboard.
   * @param text Text to copy.
   */
  static async setText(text: string): Promise<boolean> {
    try {
      const pb = ClipboardUtils.getPasteboard();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pb.setData(pasteData);
      ClipboardUtils.lastContent = text;
      hilog.info(0x0000, TAG, 'Text copied to clipboard');
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Failed to set clipboard: %{public}s', error.message);
      return false;
    }
  }

  /**
   * Start monitoring clipboard changes.
   * The callback is invoked when clipboard content changes.
   *
   * @param callback Called with new clipboard content on change.
   */
  static startMonitoring(callback: (content: ClipboardContent) => void): void {
    ClipboardUtils.changeListener = callback;
    try {
      const pb = ClipboardUtils.getPasteboard();
      pb.on('update', async () => {
        const content = await ClipboardUtils.getContent();
        if (content && content.text !== ClipboardUtils.lastContent) {
          ClipboardUtils.lastContent = content.text;
          if (ClipboardUtils.changeListener) {
            ClipboardUtils.changeListener(content);
          }
        }
      });
      hilog.info(0x0000, TAG, 'Clipboard monitoring started');
    } catch (err) {
      hilog.error(0x0000, TAG, 'Failed to start clipboard monitoring: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * Stop monitoring clipboard changes.
   */
  static stopMonitoring(): void {
    try {
      const pb = ClipboardUtils.getPasteboard();
      pb.off('update');
      ClipboardUtils.changeListener = null;
      hilog.info(0x0000, TAG, 'Clipboard monitoring stopped');
    } catch (err) {
      hilog.error(0x0000, TAG, 'Failed to stop clipboard monitoring: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * Check if clipboard has changed since last read.
   */
  static async hasChanged(): Promise<boolean> {
    const currentText = await ClipboardUtils.getText();
    return currentText !== null && currentText !== ClipboardUtils.lastContent;
  }

  /**
   * Clear the clipboard.
   */
  static async clear(): Promise<boolean> {
    try {
      const pb = ClipboardUtils.getPasteboard();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, '');
      await pb.setData(pasteData);
      ClipboardUtils.lastContent = '';
      return true;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Failed to clear clipboard: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * Check if clipboard contains text that looks like a task (heuristic detection).
   * Used by ClipboardDetector component for proactive task extraction prompts.
   */
  static async mightContainTask(): Promise<boolean> {
    const text = await ClipboardUtils.getText();
    if (!text || text.length < 5) {
      return false;
    }
    // Heuristic: text contains date-like patterns or task keywords
    const taskKeywords = ['时间', '日期', '地点', '截止', '任务', '作业', '考试',
      '会议', '完成', '明天', '今天', '下周', '周', '月', '日'];
    const hasKeyword = taskKeywords.some((kw: string) => text.includes(kw));
    const hasDatePattern = /\d{1,2}[月\/\-]\d{1,2}/.test(text) || /\d{1,2}:\d{2}/.test(text);
    return hasKeyword || hasDatePattern;
  }
}
