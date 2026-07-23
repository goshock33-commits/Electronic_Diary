// <!-- agentID: DEV-011 -->
// 文件: SecurityLockAbility.ets
// 任务: T001 安全锁PIN码验证入口 + M15 连线 SettingsViewModel
// 关联架构: ARC-001 架构方案 3.1 SecurityLockAbility
// Skill 参考：frontend-design / ui-ux-pro-max

import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'SecurityLockAbility';

export default class SecurityLockAbility extends UIAbility {

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'SecurityLockAbility onCreate');
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'SecurityLockAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, TAG, 'SecurityLockAbility onWindowStageCreate');
    // Load SecurityLockPage (fixed: was incorrectly loading MainPage)
    windowStage.loadContent('pages/SecurityLockPage', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'Failed to load SecurityLockPage: %{public}s', JSON.stringify(err));
      } else {
        hilog.info(0x0000, TAG, 'SecurityLockPage loaded successfully');
      }
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, TAG, 'SecurityLockAbility onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0000, TAG, 'SecurityLockAbility onForeground');
  }

  onBackground(): void {
    hilog.info(0x0000, TAG, 'SecurityLockAbility onBackground');
  }
}
