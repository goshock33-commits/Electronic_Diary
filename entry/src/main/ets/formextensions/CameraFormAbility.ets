// CameraFormAbility - 相机桌面卡片 FormExtensionAbility
// 点击卡片 → postCardAction message:'open_camera' → wantAgent 跳转相机
import { FormExtensionAbility, formBindingData } from '@kit.FormKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import type { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'CameraFormAbility';

export default class CameraFormAbility extends FormExtensionAbility {
  onCreate(): void {
    hilog.info(0xFF00, TAG, 'onCreate');
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(0xFF00, TAG, 'onAddForm');
    const formData: Record<string, string | number> = {};
    return formBindingData.createFormBindingData(formData);
  }

  onUpdateForm(formId: string): void {
    hilog.info(0xFF00, TAG, 'onUpdateForm: %{public}s', formId);
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(0xFF00, TAG, 'onFormEvent: %{public}s msg=%{public}s', formId, message);
    if (message === 'open_camera') {
      // FormExtensionContext 无 startAbility，改用 wantAgent 模块级 API 跳转相机
      const cameraWant: Want = {
        action: 'ohos.want.action.viewData',
        uri: 'diary://camera'
      };
      const agentInfo: wantAgent.WantAgentInfo = {
        wants: [cameraWant],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.ONE_TIME_FLAG]
      };
      wantAgent.getWantAgent(agentInfo).then((agent: WantAgent) => {
        wantAgent.trigger(agent, { code: 0 });
      }).catch((err: Error) => {
        hilog.error(0xFF00, TAG, 'wantAgent failed: %{public}s', err.message);
      });
    }
  }

  onDeleteForm(formId: string): void {
    hilog.info(0xFF00, TAG, 'onDeleteForm: %{public}s', formId);
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(0xFF00, TAG, 'onCastToNormalForm: %{public}s', formId);
  }

  onDestroy(): void {
    hilog.info(0xFF00, TAG, 'onDestroy');
  }
}
