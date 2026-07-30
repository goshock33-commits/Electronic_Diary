// <!-- agentID: HUI-043 -->
// @Entry 小艺语音助手页（路由入口，委托 features/voice-diary VoiceAssistantPage）
// §1.4 三者一致：模块 name = features_voice_diary = 依赖 key = import 路径
import { VoiceAssistantPage } from 'features_voice_diary';
import { reportPawTouch, PawOverlayLayer } from '@ohos/shared';

@Entry
@Component
struct VoiceAssistantPageEntry {
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      VoiceAssistantPage()
      // HUI-001: 猫爪视觉层（同树最上层子节点，整层 None 不参与命中，不挡交互）
      // PawOverlayLayer()
    }
    .width('100%')
    .height('100%')
    // HUI-001: 猫爪特效触摸捕获（页面树内监听 Down，不消费；视觉层在本页根 Stack 顶层）
    .onTouch((event: TouchEvent) => reportPawTouch(event))
  }
}
