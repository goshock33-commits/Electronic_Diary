// agentID: HUI-054
// 组件：待办列表（今日备忘/明日日程分组+空态复用+条目间间距+快捷新增）
// 关联设计稿：UX-001 §2.3 TodoView 复刻
// 关联任务：P2-01 待办「时光轴」TodoView 复刻
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText + 触控热区 >= 48x48vp
// 深色适配：ThemeColorTokens + 硬编码回退色

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_TITLE=猫啃什锦黑（分组标题）；数量药丸走 FONT.monoBold 保留不动。
import { IconMapper, EmptyStateView, RADIUS, SPACING, TYPO, FONT, SKETCH_TITLE, ICON } from '@ohos/shared';
import { TodoItem, type TodoItemData } from './TodoItem';

@Component
export struct TodoList {
  /** 分组类型：today | tomorrow */
  @Prop groupType: string = 'today';
  /** 分组标题 */
  @Prop groupTitle: string = '';
  /** 待办项数据列表 */
  @Prop items: TodoItemData[] = [];
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  onToggle?: (id: number) => void;
  onDelete?: (id: number) => void;
  onAdd?: () => void;
  /** HUI-001：点击项编辑回调（透传 TodoItem.onEdit，由页面层弹编辑弹窗） */
  onEdit?: (id: number) => void;
  // HUI-001（四轮）：activeDeleteId/onDeleteModeChange 透传链已拆——删除态改走 AppStorage
  //   （TodoItem @StorageLink('todo_active_delete_id') 直连），真机证实 ForEach 内 @Prop 链退出方向不同步。

  build() {
    Column() {
      // 分组标题栏
      Row() {
        Text(this.groupTitle)
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .accessibilityText(this.groupTitle)
          .attributeModifier(SKETCH_TITLE) // HUI-029：分组标题→猫啃什锦黑

        // 数量药丸
        Text(this.items.length.toString() + '项')
          .fontSize(10)
          .fontFamily(FONT.monoBold)
          .fontWeight(900)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
          .backgroundColor(this.tokens ? this.tokens.divider : '#F0F0F0')
          .borderRadius(10)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .margin({ left: 8 })

        Blank()

        // 非空分组保留快捷新增入口；空分组继续使用下方 EmptyStateView 按钮，避免重复。
        if (this.items.length > 0) {
          Button() {
            Stack() {
              SymbolGlyph(IconMapper.PLUS)
                .fontSize(ICON.plus)
                .fontWeight(FontWeight.Bold)
                .fontColor([this.tokens ? this.tokens.btnPrimary : '#738A9C'])
            }
            .width(ICON.plusRing)
            .height(ICON.plusRing)
            .borderRadius(ICON.plusRing / 2)
            .border({
              width: ICON.ringStroke,
              color: this.tokens ? this.tokens.btnPrimary : '#738A9C'
            })
          }
          .width(48)
          .height(48)
          .borderRadius(24)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            if (this.onAdd) {
              this.onAdd();
            }
          })
          .accessibilityText(this.groupType === 'today' ? '添加今日待办' : '添加明日待办')
        }
      }
      .width('100%')
      .padding({ left: SPACING.cardPadMd, right: SPACING.cardPadSm, bottom: 4 })

      // 列表项（每项之间间距）
      if (this.items.length > 0) {
        Column() {
          ForEach(this.items, (item: TodoItemData, index: number) => {
            TodoItem({
              todoId: item.id,
              title: item.title,
              completed: item.completed,
              sourceLabel: item.sourceLabel,
              // HUI-078：元信息透传（截止日=既有 date 字段；时间/地点/自定义标签为可选字段，未填传空）
              dueDate: item.dueDateFmt !== undefined ? item.dueDateFmt : item.date,
              timeText: item.time !== undefined ? item.time : '',
              location: item.location !== undefined ? item.location : '',
              customTag: item.customTag !== undefined ? item.customTag : '',
              // HUI-079：执行人昵称透传（可选字段，未填传空=不显示徽标）
              assigneeName: item.assigneeName !== undefined ? item.assigneeName : '',
              onToggle: (todoId: number) => {
                if (this.onToggle) {
                  this.onToggle(todoId);
                }
              },
              onDelete: (todoId: number) => {
                if (this.onDelete) {
                  this.onDelete(todoId);
                }
              },
              onEdit: (todoId: number) => {
                if (this.onEdit) {
                  this.onEdit(todoId);
                }
              }
            })
              .margin({ top: index === 0 ? 0 : 8 })
          }, (item: TodoItemData) => {
            // HUI-001 修「勾选后对号/划线不刷新」：ForEach key 原只含 id——completed 变化 key 不变 →
            //   itemGenerator 不重执行 → 嵌套 TodoItem 的 @Prop completed 收不到更新（停抖 bug 同款
            //   ForEach 内 @Prop 链不同步，真机实证）。key 掺入 completed/title：变化即该条销毁重建，
            //   强制以新值重绘（编辑改标题同获刷新）。
            return item.id.toString() + '_' + (item.completed ? '1' : '0') + '_' + item.title;
          })
        }
        .width('100%')
        .padding({ left: SPACING.cardPadSm, right: SPACING.cardPadSm, bottom: SPACING.cardPadSm })
      } else {
        // 空态复用 EmptyStateView，小猫探头 Lottie 动画
        EmptyStateView({
          icon: IconMapper.TAB_TODO,
          animPath: 'animations/小猫探头.json',
          title: this.getEmptyTitle(),
          description: this.getEmptyDescription(),
          showAction: true,
          actionText: '添加待办',
          onAction: () => {
            if (this.onAdd) {
              this.onAdd();
            }
          }
        })
          .padding({ top: 8, bottom: 8 })
      }
    }
    .width('100%')
    .borderRadius(RADIUS.card)
    // HUI-001（三轮）：左滑已拆，clip 保留（无害）——抖动 ±1.6° 顶点位移约 4vp，条目在分组卡
    //   padding 内不会被裁；clip 兼防其他内容溢出描边圆角（API24 common.d.ts:26622）。
    .clip(true)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FAFAFA')
    .border({
      width: 1,
      color: this.tokens ? this.tokens.border : '#E0E0E0'
    })
    .accessibilityGroup(true)
  }

  /**
   * 获取空态标题
   */
  private getEmptyTitle(): string {
    if (this.groupType === 'today') {
      return '暂无今日备忘';
    }
    return '暂无明日日程';
  }

  /**
   * 获取空态描述
   */
  private getEmptyDescription(): string {
    if (this.groupType === 'today') {
      return '点击下方按钮添加今日待办'; // HUI-001：原"点击右侧加号"指向已删除的头部加号，改指空态按钮
    }
    return '提前规划明天要做的事情';
  }
}
