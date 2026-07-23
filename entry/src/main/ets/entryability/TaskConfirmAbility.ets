// <!-- agentID: DEV-001 -->
// 文件: TaskConfirmAbility.ets
// 任务: T001 提取任务确认编辑入口
// 关联架构: ARC-001 架构方案 §3.1 TaskConfirmAbility
// Skill 参考：frontend-design / ui-ux-pro-max

import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'TaskConfirmAbility';

export default class TaskConfirmAbility extends UIAbility {

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'TaskConfirmAbility onCreate');
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'TaskConfirmAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, TAG, 'TaskConfirmAbility onWindowStageCreate');
    // HUI-065 · P2-11：加载任务确认弹窗页（毛玻璃遮罩 + 底部滑入 40vp 白卡 + 任务列表）
    windowStage.loadContent('pages/TaskConfirmPage', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, TAG, 'TaskConfirmAbility onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0000, TAG, 'TaskConfirmAbility onForeground');
  }

  onBackground(): void {
    hilog.info(0x0000, TAG, 'TaskConfirmAbility onBackground');
  }
}
