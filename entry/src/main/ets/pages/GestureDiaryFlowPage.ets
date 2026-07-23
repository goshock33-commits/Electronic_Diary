// <!-- agentID: HUI-038 -->
// @Entry 手势日记流程页（路由入口，委托 features/gesture-diary GestureDiaryFlowPage）
// 关联任务：F16（PLN-002 阶段7 手势日记）
import { GestureDiaryFlowPage } from 'features_gesture_diary';
import { reportPawTouch, PawOverlayLayer } from '@ohos/shared';

@Entry
@Component
struct GestureDiaryFlowPageEntry {
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      GestureDiaryFlowPage()
      // HUI-001: 猫爪视觉层（同树最上层子节点，整层 None 不参与命中，不挡交互）
      PawOverlayLayer()
    }
    .width('100%')
    .height('100%')
    // HUI-001: 猫爪特效触摸捕获（页面树内监听 Down，不消费；视觉层在本页根 Stack 顶层）
    .onTouch((event: TouchEvent) => reportPawTouch(event))
  }
}
