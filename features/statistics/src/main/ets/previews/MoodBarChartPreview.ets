// <!-- agentID: HUI-034 -->
// fix: HUI-016
// 预览文件：心情分布柱状图（DevEco Studio Previewer 专用，独立于组件源文件）
// 说明：@Preview struct 从 MoodBarChart.ets 移出，避免与业务组件耦合；
//       $r() 资源引用在 aboutToAppear 中赋值，避免字段声明初始值中直接使用导致的闪退。
import { MoodBarChart } from '../components/MoodBarChart';
import type { MoodDataItem } from '../components/MoodBarChart';
import { IconMapper } from '@ohos/shared';

@Preview({
  title: '心情分布柱状图 — 预览',
  width: 360,
  height: 320
})
@Component
struct MoodBarChartPreview {
  @State previewData: MoodDataItem[] = [];

  aboutToAppear(): void {
    // fix: HUI-016 · T-D03 —— MoodDataItem.color 死字段已删除（darkmode_audit A-5），预览数据同步去除
    this.previewData = [
      { label: '开心', count: 8, icon: IconMapper.MOOD_HAPPY },
      { label: '愉快', count: 5, icon: IconMapper.MOOD_PLEASANT },
      { label: '平淡', count: 3, icon: IconMapper.MOOD_NEUTRAL },
      { label: '难过', count: 2, icon: IconMapper.MOOD_SAD }
    ];
  }

  build() {
    Column() {
      MoodBarChart({ data: this.previewData })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
  }
}
