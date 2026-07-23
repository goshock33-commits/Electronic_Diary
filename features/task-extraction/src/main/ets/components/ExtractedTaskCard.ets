// <!-- agentID: HUI-026 -->
// 组件：提取任务卡片（来源标签图标 + 类型彩色标签 + 标题 + 时间地点 + 转为待办按钮）
// 关联设计稿：UX-001_prototype.html
// 关联任务：F12（PLN-002 阶段6 任务提取模块UI）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText + 触控热区 >= 48x48vp
// 深色适配：ThemeColorTokens + 硬编码回退色

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_BODY=清松手写体2（任务标题 + 地点 + 状态标签）；日期时间行保留不动，Button('转为待办') 不动。
import { IconMapper, RADIUS, SKETCH_BODY } from '@ohos/shared';
import { TaskSourceIndicator } from './TaskSourceIndicator';
import { TaskTypeBadge } from './TaskTypeBadge';

@Component
export struct ExtractedTaskCard {
  @Prop taskId: number = 0;
  @Prop title: string = '';
  @Prop source: string = 'clipboard';
  @Prop category: string = 'general';
  @Prop taskDate: string = '';
  @Prop taskTime: string = '';
  @Prop location: string = '';
  @Prop isConverted: boolean = false;
  // HUI-065 · P2-11：勾选模式（任务确认弹窗复用）——
  //   selectable=true 时头部前置圆勾选、隐藏单卡「忽略/转为待办」按钮、整卡点按切换选中；
  //   默认 false 保持既有 features_sections 列表用法不变（向后兼容）。
  @Prop selectable: boolean = false;
  @Prop selected: boolean = true;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  onConvert?: (taskId: number) => void;
  onDismiss?: (taskId: number) => void;
  onToggleSelect?: (taskId: number) => void;

  /**
   * 格式化日期+时间显示文本
   */
  private getDateTimeText(): string {
    let result: string = this.taskDate;
    if (this.taskTime.length > 0) {
      result += ' ' + this.taskTime;
    }
    return result;
  }

  build() {
    Column() {
      // ═══════════════════════════════════════════
      // 顶部：来源标签 + 类型标签
      // ═══════════════════════════════════════════
      Row() {
        // HUI-065 · P2-11：勾选模式下头部前置圆勾选（选中=青实心+白勾，未选=描边空心）
        if (this.selectable) {
          Stack({ alignContent: Alignment.Center }) {
            Circle({ width: 22, height: 22 })
              .fill(this.selected ? (this.tokens ? this.tokens.btnPrimary : '#738A9C') : (this.tokens ? this.tokens.surface : '#FFFFFF')) // HUI-041：勾选圈未选中底由死白改读 surface token，深色跟随主题（描边 border 仍在）
              .stroke(this.selected
                ? (this.tokens ? this.tokens.btnPrimary : '#738A9C')
                : (this.tokens ? this.tokens.border : '#D0D0D0'))
              .strokeWidth(2)
            if (this.selected) {
              SymbolGlyph(IconMapper.CHECKMARK)
                .fontSize(12)
                .fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF'])
            }
          }
          .width(22)
          .height(22)
          .margin({ right: 10 })
        }

        TaskSourceIndicator({ source: this.source })

        Blank()

        TaskTypeBadge({ taskType: this.category })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12 })

      // ═══════════════════════════════════════════
      // 中部：任务标题
      // ═══════════════════════════════════════════
      Text(this.title)
        .fontSize(15)
        .fontWeight(500)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#333333')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: 14, right: 14, top: 10 })
        .attributeModifier(SKETCH_BODY) // HUI-029：任务标题→清松手写体2

      // ═══════════════════════════════════════════
      // 时间 + 地点信息行
      // ═══════════════════════════════════════════
      if (this.taskDate.length > 0 || this.location.length > 0) {
        Row() {
          if (this.taskDate.length > 0) {
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(12)
              .fontColor([this.tokens ? this.tokens.textTertiary : '#BDBDBD'])

            Text(this.getDateTimeText())
              .fontSize(12)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#999999')
              .margin({ left: 4 })
          }

          if (this.location.length > 0) {
            if (this.taskDate.length > 0) {
              Text('  |  ')
                .fontSize(12)
                .fontColor(this.tokens ? this.tokens.border : '#E0E0E0')
            }

            SymbolGlyph($r('sys.symbol.position'))  // grep验证: location_fill不在全量图标库, 替换为position(F01CA)
              .fontSize(12)
              .fontColor([this.tokens ? this.tokens.textTertiary : '#BDBDBD'])

            Text(this.location)
              .fontSize(12)
              .fontColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
              .margin({ left: 4 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .attributeModifier(SKETCH_BODY) // HUI-029：地点（中文标签）→清松手写体2
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 8 })
      }

      // ═══════════════════════════════════════════
      // 底部分隔线（勾选模式下隐藏单卡操作，故一并隐藏分隔线）
      // ═══════════════════════════════════════════
      if (!this.selectable && !this.isConverted) {
        Divider()
          .strokeWidth(0.5)
          .color(this.tokens ? this.tokens.divider : '#F0F0F0')
          .margin({ left: 14, right: 14, top: 10 })
      }

      // ═══════════════════════════════════════════
      // 底部：操作按钮区（勾选模式改用弹窗底部「全部添加/取消」，此处隐藏）
      // ═══════════════════════════════════════════
      if (!this.selectable && !this.isConverted) {
        Row() {
          // 忽略/关闭按钮
          Button() {
            SymbolGlyph(IconMapper.CLOSE)
              .fontSize(14)
              .fontColor([this.tokens ? this.tokens.textTertiary : '#BBBBBB'])
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            if (this.onDismiss) {
              this.onDismiss(this.taskId);
            }
          })
          .accessibilityText('忽略任务：' + this.title)

          Blank()

          // 转为待办按钮
          Button('转为待办')
            .fontSize(13)
            .fontWeight(600)
            .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
            .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C') // HUI-035：转为待办主按钮→雾霾蓝 btnPrimary
            .borderRadius(20)
            .height(40)
            .padding({ left: 20, right: 20 })
            .onClick(() => {
              if (this.onConvert) {
                this.onConvert(this.taskId);
              }
            })
            .accessibilityText('将"' + this.title + '"转为待办事项')
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 6, bottom: 10 })
      } else if (!this.selectable) {
        // ═══════════════════════════════════════════
        // 已转换态：绿色确认标识
        // ═══════════════════════════════════════════
        Row() {
          SymbolGlyph(IconMapper.CHECKMARK)
            .fontSize(14)
            .fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF'])

          Text('已添加为待办')
            .fontSize(13)
            .fontWeight(500)
            .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
            .margin({ left: 6 })
            .attributeModifier(SKETCH_BODY) // HUI-029：已转换状态标签→清松手写体2
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 10, bottom: 12 })
        .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
        .borderRadius({
          bottomLeft: 12,
          bottomRight: 12,
          topLeft: 0,
          topRight: 0
        })
        .accessibilityText('任务"' + this.title + '"已添加为待办')
      }

      // HUI-065 · P2-11：勾选模式无底部按钮，补底部留白避免内容贴边
      if (this.selectable) {
        Row().width('100%').height(12)
      }
    }
    .width('100%')
    .borderRadius(RADIUS.item)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FAFAFA')
    .border({
      width: 1,
      color: this.selectable
        ? (this.selected
          ? (this.tokens ? this.tokens.btnPrimary : '#738A9C')
          : (this.tokens ? this.tokens.border : '#E0E0E0'))
        : (this.isConverted
          ? (this.tokens ? this.tokens.btnPrimary : '#738A9C')
          : (this.tokens ? this.tokens.border : '#E0E0E0'))
    })
    .margin({ bottom: 10 })
    .onClick(() => {
      if (this.selectable && this.onToggleSelect) {
        this.onToggleSelect(this.taskId);
      }
    })
    .accessibilityGroup(true)
    .accessibilityText(
      '提取任务：' + this.title +
      '，来源：' + this.source +
      '，类型：' + this.category +
      (this.selectable
        ? (this.selected ? '，已选中' : '，未选中')
        : (this.isConverted ? '，已添加为待办' : '，未转换'))
    )
  }
}
