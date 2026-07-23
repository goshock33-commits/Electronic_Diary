// <!-- agentID: HUI-026 -->
// 组件：任务类型彩色标签（考试/作业/开会/截止/通用）
// 关联设计稿：UX-001_prototype.html
// 关联任务：F12（PLN-002 阶段6 任务提取模块UI）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText
// 深色适配：硬编码语义色（类型标签颜色固定，不随主题变化）

// HUI-029：追加手绘正文字体助手 SKETCH_BODY=清松手写体2（类型中文标签）；本文件原无 shared import，按需追加。
import { SKETCH_BODY } from '@ohos/shared';

/**
 * 任务类型彩色标签组件
 *
 * 五种任务类型各有独立语义色：
 * - 考试 (exam):   红色 #78909C
 * - 作业 (homework):橙色 #80CBC4
 * - 会议 (meeting): 蓝色 #4FC3F7
 * - 截止 (deadline):深红 #78909C
 * - 通用 (general): 灰色 #9E9E9E
 *
 * 注意：类型标签使用固定语义色，不随深浅色主题变化，
 * 确保用户在任何主题下都能快速识别任务类型。
 */
@Component
export struct TaskTypeBadge {
  @Prop taskType: string = 'general';

  /** 类型→中文标签映射 */
  private labelMap: Record<string, string> = {
    'exam': '考试',
    'homework': '作业',
    'meeting': '会议',
    'deadline': '截止',
    'general': '通用'
  };

  /** 类型→语义色映射 */
  private colorMap: Record<string, string> = {
    'exam': '#78909C',
    'homework': '#80CBC4',
    'meeting': '#4FC3F7',
    'deadline': '#78909C',
    'general': '#9E9E9E'
  };

  /** 类型→浅底色映射（用于前景文字较深的场景） */
  private bgColorMap: Record<string, string> = {
    'exam': '#FFEBEE',
    'homework': '#FFF3E0',
    'meeting': '#E3F2FD',
    'deadline': '#FFEBEE',
    'general': '#F5F5F5'
  };

  build() {
    Row() {
      Text(this.labelMap[this.taskType] ?? this.taskType)
        .fontSize(10)
        .fontWeight(600)
        .fontColor(this.bgColorMap[this.taskType] ? this.colorMap[this.taskType] : '#9E9E9E')
        .attributeModifier(SKETCH_BODY) // HUI-029：类型中文标签→清松手写体2
    }
    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
    .borderRadius(10)
    .backgroundColor(this.bgColorMap[this.taskType] ?? '#F5F5F5')
    .border({
      width: 1,
      color: this.colorMap[this.taskType] ?? '#9E9E9E'
    })
    .accessibilityText(
      '任务类型：' + (this.labelMap[this.taskType] ?? this.taskType)
    )
  }
}
