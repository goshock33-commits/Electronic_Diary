// <!-- agentID: HUI-024 -->
// 文件: DiaryEditAbility.ets
// 任务: F09 日记全屏编辑器入口
// 关联架构: ARC-001 架构方案 §3.1 DiaryEditAbility
// 关联任务：PLN-002 F09（阶段4 日记系统）
// Skill 参考：frontend-design / ui-ux-pro-max

import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'DiaryEditAbility';

export default class DiaryEditAbility extends UIAbility {

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'DiaryEditAbility onCreate');
    // 解析 Want 参数（日期等）
    if (want.parameters) {
      const dateParam = want.parameters['date'] as string;
      if (dateParam) {
        hilog.info(0x0000, TAG, 'Received date param: %{public}s', dateParam);
      }
    }
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'DiaryEditAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, TAG, 'DiaryEditAbility onWindowStageCreate');

    // 加载日记编辑页
    windowStage.loadContent('pages/DiaryEditPage', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'Failed to load DiaryEditPage: %{public}s', JSON.stringify(err));
        // 降级：加载主页面
        windowStage.loadContent('pages/MainPage', (fallbackErr) => {
          if (fallbackErr.code) {
            hilog.error(0x0000, TAG, 'Fallback load failed: %{public}s', JSON.stringify(fallbackErr));
          }
        });
        return;
      }
      hilog.info(0x0000, TAG, 'DiaryEditPage loaded successfully');

      // 获取窗口并设置全屏沉浸式
      const mainWindow = windowStage.getMainWindowSync();
      if (mainWindow) {
        mainWindow.setWindowLayoutFullScreen(true).then(() => {
          hilog.info(0x0000, TAG, 'Fullscreen mode set');
        }).catch((err: Error) => {
          hilog.warn(0x0000, TAG, 'Fullscreen mode failed: %{public}s', err.message);
        });
      }
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, TAG, 'DiaryEditAbility onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0000, TAG, 'DiaryEditAbility onForeground');
  }

  onBackground(): void {
    hilog.info(0x0000, TAG, 'DiaryEditAbility onBackground');
  }
}
