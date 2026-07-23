// <!-- agentID: HUI-026 -->
// 组件：提取任务分区（显示从各处提取的任务卡片列表，使用真实 ExtractedTaskCard 组件）
// 关联设计稿：UX-001_prototype.html
// 关联任务：F05 + F12（PLN-002 阶段3+阶段6）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText + 触控热区 >= 48x48vp
// 深色适配：ThemeColorTokens + 硬编码回退色
// Mock：3条提取任务（QQ考试 + 微信开会 + 剪贴板通用）

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_TITLE=猫啃什锦黑（分区标题）；「X条待处理」计数保留不动。
import { IconMapper, EmptyStateView, SKETCH_TITLE } from '@ohos/shared';
import { ExtractedTaskCard } from 'features_task_extraction';

/**
 * 提取任务分区数据接口
 */
export interface ExtractedTaskData {
  id: number;
  title: string;
  /** 来源: qq | wechat | voice | clipboard */
  source: string;
  /** 类型: exam | homework | meeting | deadline | general */
  category: string;
  taskDate: string;
  taskTime: string;
  location: string;
  isConverted: boolean;
}

@Component
export struct ExtractedTaskSection {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  /** mock：3条提取任务（QQ考试 + 微信开会 + 剪贴板通用） */
  @State items: ExtractedTaskData[] = [
    {
      id: 1,
      title: '下周三高等数学期末考试，地点教三楼301',
      source: 'qq',
      category: 'exam',
      taskDate: '2026-07-15',
      taskTime: '14:00',
      location: '教三楼301',
      isConverted: false
    },
    {
      id: 2,
      title: '周五下午2点项目进度讨论会',
      source: 'wechat',
      category: 'meeting',
      taskDate: '2026-07-10',
      taskTime: '14:00',
      location: '线上腾讯会议',
      isConverted: false
    },
    {
      id: 3,
      title: '记得买下周出差的火车票',
      source: 'clipboard',
      category: 'general',
      taskDate: '2026-07-12',
      taskTime: '',
      location: '',
      isConverted: false
    }
  ];

  /** 左滑删除偏移量 */
  @State private offsetMap: Record<number, number> = {};
  /** 是否展示删除按钮 */
  @State private showDeleteMap: Record<number, boolean> = {};

  onConvert?: (id: number) => void;
  onDelete?: (id: number) => void;

  build() {
    Column() {
      // ═══════════════════════════════════════════
      // 分区标题行
      // ═══════════════════════════════════════════
      Row() {
        SymbolGlyph(IconMapper.TAB_TODO)
          .fontSize(18)
          .fontColor([this.tokens ? this.tokens.primary : '#000000']) // HUI-023：死值青 #80CBC4 → 墨色 token
          .margin({ right: 10 })

        Text('提取任务')
          .fontSize(16)
          .fontWeight(600)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#333333')
          .attributeModifier(SKETCH_TITLE) // HUI-029：分区标题→猫啃什锦黑

        Text(' ' + this.items.filter((item: ExtractedTaskData) => !item.isConverted).length + '条待处理')
          .fontSize(13)
          .fontWeight(400)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')

        Blank()

        Button() {
          SymbolGlyph(IconMapper.COPY)  // grep验证: doc_fill不在全量图标库, 替换为doc_text_fill(F00BF)
            .fontSize(16)
            .fontColor([this.tokens ? this.tokens.textTertiary : '#BBBBBB'])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          // 手动检测剪贴板入口（mock阶段toast提示）
        })
        .accessibilityText('手动检测剪贴板任务')
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 4 })

      if (this.items.length > 0) {
        Divider()
          .strokeWidth(0.5)
          .color(this.tokens ? this.tokens.divider : '#F0F0F0')
          .margin({ left: 12, right: 12 })
      }

      // ═══════════════════════════════════════════
      // 任务卡片列表（使用真实 ExtractedTaskCard 组件）
      // ═══════════════════════════════════════════
      if (this.items.length > 0) {
        Column() {
          ForEach(this.items, (item: ExtractedTaskData, index: number) => {
            this.buildTaskItemWrapper(item)
          }, (item: ExtractedTaskData) => item.id.toString())
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10 })
      } else {
        // 空态
        Column() {
          EmptyStateView({
            icon: IconMapper.TAB_TODO,
            title: '暂无提取任务',
            description: '去微信、剪贴板或语音中提取任务吧',
            showAction: false
          })
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  /**
   * 左滑删除包装器 + ExtractedTaskCard
   */
  @Builder
  buildTaskItemWrapper(item: ExtractedTaskData) {
    Stack({ alignContent: Alignment.End }) {
      // 左滑露出的红色删除背景
      if (this.showDeleteMap[item.id]) {
        Row() {
          Blank()
          Button() {
            SymbolGlyph(IconMapper.DELETE)
              .fontSize(18)
              .fontColor([Color.White])
          }
          .width(72)
          .height('100%')
          .backgroundColor('#666666') // HUI-023：死值蓝灰 #78909C → 手绘深灰（配白色删除图标，浅深两色主题均可见）
          .borderRadius(12)
          .onClick(() => {
            this.handleDelete(item.id);
          })
          .accessibilityText('删除提取任务：' + item.title)
        }
        .width('100%')
        .height('100%')
      }

      // 真实 ExtractedTaskCard 组件
      ExtractedTaskCard({
        taskId: item.id,
        title: item.title,
        source: item.source,
        category: item.category,
        taskDate: item.taskDate,
        taskTime: item.taskTime,
        location: item.location,
        isConverted: item.isConverted,
        onConvert: (id: number) => {
          this.handleConvert(id);
        },
        onDismiss: (id: number) => {
          this.handleDelete(id);
        }
      })
        .offset({ x: this.offsetMap[item.id] ?? 0 })
        .gesture(
          PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
            .onActionUpdate((event: GestureEvent) => {
              if (event.offsetX < 0) {
                const newOffset: number = Math.max(event.offsetX, -72);
                this.offsetMap[item.id] = newOffset;
                this.showDeleteMap[item.id] = newOffset < -30;
              }
            })
            .onActionEnd(() => {
              if ((this.offsetMap[item.id] ?? 0) < -40) {
                this.offsetMap[item.id] = -72;
                this.showDeleteMap[item.id] = true;
              } else {
                this.offsetMap[item.id] = 0;
                this.showDeleteMap[item.id] = false;
              }
            })
        )
        .animation({ duration: 250, curve: Curve.EaseOut })
    }
    .width('100%')
  }

  /**
   * 处理删除
   */
  private handleDelete(id: number): void {
    this.offsetMap[id] = 0;
    this.showDeleteMap[id] = false;
    animateTo({ duration: 300, curve: Curve.EaseIn }, () => {
      this.items = this.items.filter((item: ExtractedTaskData) => item.id !== id);
    });
    if (this.onDelete) {
      this.onDelete(id);
    }
  }

  /**
   * 处理转为待办
   */
  private handleConvert(id: number): void {
    animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.items = this.items.map((item: ExtractedTaskData) => {
        if (item.id === id) {
          return {
            id: item.id,
            title: item.title,
            source: item.source,
            category: item.category,
            taskDate: item.taskDate,
            taskTime: item.taskTime,
            location: item.location,
            isConverted: true
          };
        }
        return item;
      });
    });
    if (this.onConvert) {
      this.onConvert(id);
    }
  }
}
