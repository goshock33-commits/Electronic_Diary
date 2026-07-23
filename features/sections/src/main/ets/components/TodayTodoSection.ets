// <!-- agentID: HUI-023 -->
// agentID: HUI-041（T-D05：新增加号按钮统一 — 空心描边圆圈+粗加号）
// 组件：今日待办分区（内嵌 TodoList + 内联新增入口 + 左滑删除）
// 关联设计稿：UX-001_prototype.html
// 关联任务：F05（PLN-002 阶段3 五个分区UI）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText + 触控热区 >= 48x48vp
// 深色适配：ThemeColorTokens + 硬编码回退色
// Mock：硬编码 3 条今日待办

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_TITLE=猫啃什锦黑（分区标题）、SKETCH_BODY=清松手写体2（待办标题 + 来源标签）；「X项」计数保留不动，Button('添加') 不动。
import { IconMapper, ICON, EmptyStateView, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';

/**
 * 待办项数据（对齐 TodoItemData 接口）
 */
export interface TodayTodoData {
  id: number;
  title: string;
  completed: boolean;
  sourceLabel: string;
  date: string;
}

/**
 * 生成自增 ID
 */
let todayTodoNextId: number = 200;

function generateTodayTodoId(): number {
  todayTodoNextId += 1;
  return todayTodoNextId;
}

@Component
export struct TodayTodoSection {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  /** Mock：今日待办数据 */
  @State items: TodayTodoData[] = [
    { id: 1, title: '完成鸿蒙应用开发作业', completed: false, sourceLabel: '日记', date: '2026-07-08' },
    { id: 2, title: '复习 TypeScript 泛型章节', completed: true, sourceLabel: '', date: '2026-07-08' },
    { id: 3, title: '参加下午3点项目组会议', completed: false, sourceLabel: '微信', date: '2026-07-08' }
  ];

  /** 新增输入框可见性 */
  @State private showAddInput: boolean = false;
  /** 新增输入值 */
  @State private addText: string = '';
  /** 各 item 左滑偏移 */
  @State private offsetMap: Record<number, number> = {};
  /** 各 item 删除按钮可见 */
  @State private showDeleteMap: Record<number, boolean> = {};

  onToggle?: (id: number) => void;
  onDelete?: (id: number) => void;
  onAdd?: (title: string) => void;

  build() {
    Column() {
      // 分区标题行
      Row() {
        SymbolGlyph(IconMapper.MOOD_HAPPY)
          .fontSize(18)
          .fontColor([this.tokens ? this.tokens.primary : '#000000']) // HUI-023：死值青 #00C2B8 → 墨色 token
          .margin({ right: 10 })
        Text('今日待办')
          .fontSize(16)
          .fontWeight(600)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#333333')
          .attributeModifier(SKETCH_TITLE) // HUI-029：分区标题→猫啃什锦黑
        Text(' ' + this.getUncompletedCount() + '项')
          .fontSize(13)
          .fontWeight(400)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
        Blank()
        // 内联新增入口（HUI-041：空心描边圆圈 + 粗加号）
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
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showAddInput = true;
        })
        .accessibilityText('添加今日待办')
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 4 })

      // 分割线
      if (this.items.length > 0 || this.showAddInput) {
        Divider()
          .strokeWidth(0.5)
          .color(this.tokens ? this.tokens.divider : '#F0F0F0')
          .margin({ left: 12, right: 12 })
      }

      // 新增输入框
      if (this.showAddInput) {
        Row() {
          TextInput({ text: this.addText, placeholder: '输入今日待办内容...' })
            .fontSize(14)
            .layoutWeight(1)
            .height(42)
            .backgroundColor(Color.Transparent)
            .placeholderColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
            .onChange((value: string) => {
              this.addText = value;
            })
            .onSubmit(() => {
              this.commitAddTodo();
            })

          Button('添加')
            .fontSize(13)
            .fontWeight(500)
            .fontColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
            .backgroundColor(Color.Transparent)
            .height(36)
            .onClick(() => {
              this.commitAddTodo();
            })
            .accessibilityText('确认添加今日待办')

          Button() {
            SymbolGlyph(IconMapper.CLOSE)
              .fontSize(14)
              .fontColor([this.tokens ? this.tokens.textTertiary : '#BBBBBB'])
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showAddInput = false;
            this.addText = '';
          })
          .accessibilityText('取消添加')
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 8 })
      }

      // 列表项
      if (this.items.length > 0) {
        Column() {
          ForEach(this.items, (item: TodayTodoData, index: number) => {
            this.buildTodoItem(item)
          }, (item: TodayTodoData) => item.id.toString())
        }
        .width('100%')
      } else {
        Column() {
          EmptyStateView({
            icon: IconMapper.MOOD_HAPPY,
            title: '暂无今日待办',
            description: '点击上方加号添加今日待办事项',
            showAction: true,
            actionText: '添加待办',
            onAction: () => {
              this.showAddInput = true;
            }
          })
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  buildTodoItem(item: TodayTodoData) {
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
          .backgroundColor('#666666') // HUI-023：死值灰 #9E9E9E → 手绘深灰（配白色删除图标，浅深两色主题均可见）
          .borderRadius(0)
          .onClick(() => {
            this.handleDelete(item.id);
          })
          .accessibilityText('删除待办：' + item.title)
        }
        .width('100%')
        .height('100%')
      }

      // 待办内容主体
      Row() {
        // 勾选圆圈
        Column() {
          if (item.completed) {
            SymbolGlyph(IconMapper.CHECKMARK)
              .fontSize(12)
              .fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF'])
          }
        }
        .width(24)
        .height(24)
        .borderRadius(12)
        .backgroundColor(item.completed ?
          (this.tokens ? this.tokens.btnPrimary : '#738A9C') :
          (this.tokens ? this.tokens.surface : '#FFFFFF')) // HUI-041：勾选圈未完成底由死白改读 surface token（深色 #242424），深色下不再刺眼白点
        .border({
          width: item.completed ? 0 : 2,
          color: this.tokens ? this.tokens.border : '#E0E0E0'
        })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.handleToggle(item.id);
        })
        .animation({ duration: 200, curve: Curve.EaseInOut })
        .accessibilityText(item.completed ?
          '已完成：' + item.title :
          '未完成：' + item.title + '，点击标记完成')
        .accessibilityLevel('yes')

        // 标题
        Text(item.title)
          .fontSize(15)
          .fontColor(item.completed ?
            (this.tokens ? this.tokens.textTertiary : '#BDBDBD') :
            (this.tokens ? this.tokens.textPrimary : '#333333'))
          .decoration(item.completed ? {
            type: TextDecorationType.LineThrough,
            color: this.tokens ? this.tokens.textTertiary : '#BDBDBD'
          } : undefined)
          .layoutWeight(1)
          .margin({ left: 12 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .accessibilityLevel('no')
          .attributeModifier(SKETCH_BODY) // HUI-029：待办标题→清松手写体2

        // 来源标记
        if (item.sourceLabel.length > 0) {
          Row() {
            Text(item.sourceLabel)
              .fontSize(10)
              .fontWeight(500)
              .fontColor(Color.White)
              .attributeModifier(SKETCH_BODY) // HUI-029：来源标签→清松手写体2
          }
          .backgroundColor(this.getSourceColor(item.sourceLabel))
          .borderRadius(10)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .accessibilityText('来源：' + item.sourceLabel)
        }
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.tokens ? this.tokens.bgCard : '#FAFAFA')
      .offset({ x: this.offsetMap[item.id] ?? 0 })
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
          .onActionUpdate((event: GestureEvent) => {
            if (event.offsetX < 0) {
              const newOffset = Math.max(event.offsetX, -72);
              this.offsetMap[item.id] = newOffset;
              this.showDeleteMap[item.id] = newOffset < -30;
            }
          })
          .onActionEnd((event: GestureEvent) => {
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
      .accessibilityGroup(true)
    }
    .width('100%')
    .height(52)
    .border({
      width: { bottom: 0.5 },
      color: this.tokens ? this.tokens.divider : '#F0F0F0'
    })
  }

  private getUncompletedCount(): string {
    const count: number = this.items.filter((item: TodayTodoData) => !item.completed).length;
    return count.toString();
  }

  private handleToggle(id: number): void {
    animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      const newItems: TodayTodoData[] = this.items.map((item: TodayTodoData) => {
        if (item.id === id) {
          return {
            id: item.id,
            title: item.title,
            completed: !item.completed,
            sourceLabel: item.sourceLabel,
            date: item.date
          };
        }
        return item;
      });
      this.items = newItems;
    });
    if (this.onToggle) {
      this.onToggle(id);
    }
  }

  private handleDelete(id: number): void {
    this.offsetMap[id] = 0;
    this.showDeleteMap[id] = false;
    animateTo({ duration: 300, curve: Curve.EaseIn }, () => {
      this.items = this.items.filter((item: TodayTodoData) => item.id !== id);
    });
    if (this.onDelete) {
      this.onDelete(id);
    }
  }

  private commitAddTodo(): void {
    if (this.addText.trim().length === 0) {
      return;
    }
    const newItem: TodayTodoData = {
      id: generateTodayTodoId(),
      title: this.addText.trim(),
      completed: false,
      sourceLabel: '',
      date: '2026-07-08'
    };
    animateTo({ duration: 350, curve: Curve.EaseOut }, () => {
      this.items = [newItem, ...this.items];
    });
    this.addText = '';
    this.showAddInput = false;
    if (this.onAdd) {
      this.onAdd(newItem.title);
    }
  }

  private getSourceColor(label: string): string {
    // HUI-023：来源标签底色原为彩色死值（青/青/蓝/灰），黑白主题统一收敛为手绘深灰（白字来源标签在浅深两色主题均可读，来源差异由标签文案承担）
    const lower: string = label.toLowerCase();
    if (lower === 'wechat' || lower === '微信') {
      return '#666666';
    }
    if (lower === 'voice' || lower === '语音') {
      return '#666666';
    }
    if (lower === 'diary' || lower === '日记') {
      return '#666666';
    }
    return '#666666';
  }
}
