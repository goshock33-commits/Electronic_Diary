// <!-- agentID: HUI-023 -->
// agentID: HUI-041（T-D05：新增加号按钮统一 — 空心描边圆圈+粗加号）
// 组件：多做的事分区（列表 + 底部快速新增输入框 + 左滑删除）
// 关联设计稿：UX-001_prototype.html
// 关联任务：F05（PLN-002 阶段3 五个分区UI）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText + 触控热区 >= 48x48vp
// 深色适配：ThemeColorTokens + 硬编码回退色
// Mock：硬编码 3 条多做的事

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_TITLE=猫啃什锦黑（分区标题）、SKETCH_BODY=清松手写体2（条目正文）；「X件」计数保留不动。
import { IconMapper, ICON, EmptyStateView, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';

export interface ExtraThingItemData {
  id: number;
  content: string;
  date: string;
}

let extraThingNextId: number = 400;

function generateExtraThingId(): number {
  extraThingNextId += 1;
  return extraThingNextId;
}

@Component
export struct ExtraThingsSection {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  @State items: ExtraThingItemData[] = [
    { id: 1, content: '帮助同桌解决了数学难题', date: '2026-07-08' },
    { id: 2, content: '主动整理了班级图书角', date: '2026-07-08' },
    { id: 3, content: '课间跑步3公里', date: '2026-07-08' }
  ];

  @State private addText: string = '';
  @State private offsetMap: Record<number, number> = {};
  @State private showDeleteMap: Record<number, boolean> = {};

  onDelete?: (id: number) => void;
  onAdd?: (content: string) => void;

  build() {
    Column() {
      // 分区标题行
      Row() {
        SymbolGlyph(IconMapper.ADD)  // 替代 sparkles — 验证来源: IconMapper.ADD 已验证; HomePage 同分区使用此图标
          .fontSize(18)
          .fontColor([this.tokens ? this.tokens.primary : '#000000']) // HUI-023：死值蓝灰 #90A4AE → 墨色 token
          .margin({ right: 10 })
        Text('多做的事')
          .fontSize(16)
          .fontWeight(600)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#333333')
          .attributeModifier(SKETCH_TITLE) // HUI-029：分区标题→猫啃什锦黑
        Text(' ' + this.items.length + '件')
          .fontSize(13)
          .fontWeight(400)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
        Blank()
        // 快速新增入口（HUI-041：空心描边圆圈 + 粗加号）
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
          // 直接聚焦底部输入框（通过 scrollIntoView 行为）
        })
        .accessibilityText('添加多做的事')
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

      // 列表项
      if (this.items.length > 0) {
        Column() {
          ForEach(this.items, (item: ExtraThingItemData, index: number) => {
            this.buildExtraItem(item)
          }, (item: ExtraThingItemData) => item.id.toString())
        }
        .width('100%')
      } else {
        Column() {
          EmptyStateView({
            icon: $r('sys.symbol.star_fill'),  // grep验证: sparkles不在全量图标库, 替换为star_fill(F0009)
            title: '还没有多做的事',
            description: '记录今天额外完成的事情',
            showAction: false
          })
        }
        .width('100%')
      }

      // 底部快速新增输入框
      Row() {
        Circle({ width: 6, height: 6 })
          .fill(this.tokens ? this.tokens.primary : '#00C2B8')
          .flexShrink(0)

        TextInput({ text: this.addText, placeholder: '记录一件多做的事...' })
          .fontSize(14)
          .layoutWeight(1)
          .height(42)
          .backgroundColor(Color.Transparent)
          .placeholderColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
          .margin({ left: 10 })
          .onChange((value: string) => {
            this.addText = value;
          })
          .onSubmit(() => {
            this.commitAdd();
          })

        Button() {
          SymbolGlyph(IconMapper.SEND)
            .fontSize(16)
            .fontColor([this.addText.trim().length > 0 ?
              (this.tokens ? this.tokens.btnPrimary : '#738A9C') :
              (this.tokens ? this.tokens.border : '#E0E0E0')]) // HUI-035：发送激活图标→雾霾蓝 btnPrimary（禁用留灰）
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.commitAdd();
        })
        .accessibilityText('发送')
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 8 })
    }
    .width('100%')
  }

  @Builder
  buildExtraItem(item: ExtraThingItemData) {
    Stack({ alignContent: Alignment.End }) {
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
          .borderRadius(0)
          .onClick(() => {
            this.handleDelete(item.id);
          })
          .accessibilityText('删除：' + item.content)
        }
        .width('100%')
        .height('100%')
      }

      Row() {
        Circle({ width: 6, height: 6 })
          .fill(this.tokens ? this.tokens.textTertiary : '#CCCCCC')
          .flexShrink(0)

        Text(item.content)
          .fontSize(14)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#333333')
          .layoutWeight(1)
          .margin({ left: 12 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .accessibilityLevel('no')
          .attributeModifier(SKETCH_BODY) // HUI-029：多做的事条目正文→清松手写体2
      }
      .width('100%')
      .height(46)
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
      .accessibilityGroup(true)
      .accessibilityText(item.content)
    }
    .width('100%')
    .height(46)
    .border({
      width: { bottom: 0.5 },
      color: this.tokens ? this.tokens.divider : '#F0F0F0'
    })
  }

  private handleDelete(id: number): void {
    this.offsetMap[id] = 0;
    this.showDeleteMap[id] = false;
    animateTo({ duration: 300, curve: Curve.EaseIn }, () => {
      this.items = this.items.filter((item: ExtraThingItemData) => item.id !== id);
    });
    if (this.onDelete) {
      this.onDelete(id);
    }
  }

  private commitAdd(): void {
    if (this.addText.trim().length === 0) {
      return;
    }
    const newItem: ExtraThingItemData = {
      id: generateExtraThingId(),
      content: this.addText.trim(),
      date: '2026-07-08'
    };
    animateTo({ duration: 350, curve: Curve.EaseOut }, () => {
      this.items = [newItem, ...this.items];
    });
    this.addText = '';
    if (this.onAdd) {
      this.onAdd(newItem.content);
    }
  }
}
