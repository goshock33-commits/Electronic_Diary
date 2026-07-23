// <!-- agentID: HUI-034 -->
// 预览文件：待办完成率进度条（DevEco Studio Previewer 专用，独立于组件源文件）
// 说明：@Preview struct 从 TodoProgressBar.ets 移出，避免与业务组件耦合。
import type { ThemeColorTokens } from '@ohos/shared';
import { TodoProgressBar } from '../components/TodoProgressBar';

@Preview({ title: '正常进度', width: 360, height: 200 })
@Preview({ title: '零进度', width: 360, height: 200 })
@Preview({ title: '全部完成', width: 360, height: 200 })
@Component
struct TodoProgressBarPreview {
  aboutToAppear(): void {
    // 为预览提供 Mock 主题色板
    AppStorage.setOrCreate<ThemeColorTokens>('theme_tokens', {
      textSecondary: '#666666',
      textTertiary: '#999999',
      primary: '#00C2B8',
      bgCard: '#FAFAFA',
      border: '#E0E0E0',
    } as ThemeColorTokens);
  }

  build() {
    Column({ space: 12 }) {
      // 预览 1: 正常进度 (5/8)
      TodoProgressBar({ completed: 5, total: 8 })

      // 预览 2: 零进度 (0/5)
      TodoProgressBar({ completed: 0, total: 5 })

      // 预览 3: 全部完成 (10/10)
      TodoProgressBar({ completed: 10, total: 10 })
    }
    .width('100%').padding(16)
    .backgroundColor('#F5F5F5')
  }
}
