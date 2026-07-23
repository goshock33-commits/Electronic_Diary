// <!-- agentID: HUI-084 -->
// fix: F5
// 模块：前台剪贴板任务检测器（非 UI 组件 — 工具类 + 确认弹窗逻辑）
// 关联需求：F5 任务提取入口组件（剪贴板检测）
// 关联规范：PROJECT_SPEC §8 ArkTS 严格模式 / §8.3.② AppStorage 全局对象禁 import / §10 权威真相源
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式（逻辑层，不参与 build 渲染）
//
// ── 职责与链路 ──────────────────────────────────────────────────
// · 宿主（MainPage.onPageShow / 前台回归）调用 checkOnForeground()
// · ClipboardUtils.mightContainTask()（API 名已对照 shared ClipboardUtils.ets，§8.3.⑦）
//   命中 → promptAction.showDialog 确认框（项目既有 promptAction 用法，同 HomePage/TaskConfirmPage）
// · 用户确认 → new TaskExtractionViewModel().receiveFromClipboard(text)
//   —— CLIPBOARD_TASK_DETECTED / TASK_EXTRACTED 均由 ViewModel 内部按 §8.3 规范 emit，本类不重复发射
// · 同一剪贴板内容仅提示一次（静态去重，进程生命周期内有效）

import type { ThemeColorTokens } from '@ohos/shared';
import { ClipboardUtils } from '@ohos/shared';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TaskExtractionViewModel } from '../viewmodel/TaskExtractionViewModel';
import type { ExtractionResult } from '../viewmodel/TaskExtractionViewModel';

const TAG = 'ClipboardDetector';
/** 弹窗内容预览最大长度 */
const PREVIEW_MAX_LEN: number = 60;

export class ClipboardDetector {
  /** 上次已提示过的剪贴板内容（同内容去重，避免每次前台重复打扰） */
  private static lastPromptedText: string = '';
  /** 防重入：检测进行中忽略新的触发 */
  private static checking: boolean = false;

  /**
   * 前台检测入口：MainPage.onPageShow（首帧显示 + 应用回前台均触发）调用。
   * fire-and-forget：内部全链路 try-catch，不向宿主抛错。
   */
  static checkOnForeground(): void {
    ClipboardDetector.doCheck();
  }

  private static async doCheck(): Promise<void> {
    if (ClipboardDetector.checking) {
      return;
    }
    ClipboardDetector.checking = true;
    try {
      const might: boolean = await ClipboardUtils.mightContainTask();
      if (!might) {
        return;
      }
      const text: string | null = await ClipboardUtils.getText();
      if (!text || text.length === 0) {
        return;
      }
      if (text === ClipboardDetector.lastPromptedText) {
        return; // 同内容只提示一次
      }
      ClipboardDetector.lastPromptedText = text;
      ClipboardDetector.showConfirmDialog(text);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Clipboard check failed: %{public}s', JSON.stringify(err));
    } finally {
      // 任意 return/异常路径均复位，防止防重入标志卡死
      ClipboardDetector.checking = false;
    }
  }

  /** 确认弹窗：命中任务关键词后提示用户是否提取（色走 theme_tokens，判空兜底黑白） */
  private static showConfirmDialog(text: string): void {
    const tokens: ThemeColorTokens | undefined = AppStorage.get<ThemeColorTokens>('theme_tokens');
    const preview: string = text.length > PREVIEW_MAX_LEN
      ? text.substring(0, PREVIEW_MAX_LEN) + '…'
      : text;
    promptAction.showDialog({
      title: '发现疑似任务',
      message: '剪贴板内容：' + preview + '\n是否提取为任务？',
      buttons: [
        { text: '忽略', color: tokens ? tokens.textTertiary : '#8A8A8A' },
        { text: '提取任务', color: tokens ? tokens.textPrimary : '#1A1A1A' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        ClipboardDetector.extractFromClipboard(text);
      }
    }).catch((err: Error) => {
      hilog.error(0x0000, TAG, 'Show dialog failed: %{public}s', err.message);
    });
  }

  /** 用户确认后：调用后端契约 receiveFromClipboard（事件发射见文件头链路说明） */
  private static async extractFromClipboard(text: string): Promise<void> {
    try {
      const vm: TaskExtractionViewModel = new TaskExtractionViewModel();
      const result: ExtractionResult | null = await vm.receiveFromClipboard(text);
      if (result) {
        promptAction.showToast({ message: '已提取任务：' + result.title, duration: 1500 });
      } else {
        promptAction.showToast({ message: '未识别出任务内容', duration: 1500 });
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Extract from clipboard failed: %{public}s', JSON.stringify(err));
      promptAction.showToast({ message: '任务提取失败，请稍后重试', duration: 1500 });
    }
  }
}
