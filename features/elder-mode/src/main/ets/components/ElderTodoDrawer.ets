// <!-- agentID: HUI -->
// 组件：ElderTodoDrawer 长辈模式待办抽屉（左侧滑出 + 大字号待办列表 + 整行点击完成）
// 关联模块：features/elder-mode（HAR）
// 交互：遮罩点击/右上角关闭按钮（56vp）关闭；待办整行（>=72vp 热区）点击切换完成态；
//       完成态=近黑实心大勾选圈 + 删除线灰字（黑白中性，无青色/无大红——用户偏好）
// 适老化：标题 28vp / 条目 24vp / 辅助 18vp 大字号；触控热区 >= 56vp（整行 72vp、关闭钮 56vp）
// 显隐范式：@Prop isVisible + onClose 回调（对齐 SectionManager 先例）；TransitionEffect 左滑入场
// 运行时崩溃防范（PROJECT_SPEC §9）：普通方法非 getter；字段初值不含 $r()；
//       @StorageLink 判空；对象字面量均有声明类型（§8.2）
// 开发范式：ArkTS 声明式开发范式（Stage 模型）

import { IconMapper } from '@ohos/shared';
import type { ThemeColorTokens } from '@ohos/shared';

/** 关闭按钮边长(vp)——适老化触控热区 >= 56vp */
const CLOSE_BTN_SIZE: number = 56;
/** 待办条目最小行高(vp)——整行热区（> 56vp 基线再加码） */
const ITEM_MIN_HEIGHT: number = 72;
/** 勾选圈边长(vp) */
const CHECK_SIZE: number = 40;
/** 抽屉入场/退场动画时长(ms) */
const DRAWER_ANIM_DURATION: number = 240;
/** 兜底主文字色（高对比近黑，与 ElderHomeView 一致） */
const FALLBACK_TEXT_PRIMARY: string = '#1A1A1A';
/** 兜底次要文字色 */
const FALLBACK_TEXT_SECONDARY: string = '#5C5C5C';
/** 兜底弱文字色（完成态删除线灰字） */
const FALLBACK_TEXT_TERTIARY: string = '#8A8A8A';
/** 兜底抽屉底色 */
const FALLBACK_BG_CARD: string = '#FFFFFF';
/** 兜底条目底色（暖白，与 ElderHomeView 渐变同族） */
const FALLBACK_SURFACE: string = '#F7F1E7';
/** 兜底边框色（暖灰） */
const FALLBACK_BORDER: string = '#C9B8A0';
/** 遮罩色（半透明近黑 #AARRGGBB，alpha 前置——HUI-040 先例） */
const SCRIM_COLOR: string = '#66000000';

/**
 * 长辈模式待办条目数据（宿主由 TodoItem 模型映射填充）
 */
export interface ElderTodoData {
  id: number;
  title: string;
  completed: boolean;
  /** 可选时间文本（如 "14:30"，空/缺省不显示） */
  timeText?: string;
}

/**
 * ElderTodoDrawer —— 长辈模式左侧待办抽屉。
 *
 * 典型用法（宿主壳接线）：
 *   ElderTodoDrawer({
 *     isVisible: this.drawerVisible,
 *     items: this.elderTodos,
 *     onToggle: (id: number) => { this.todoVM.toggleComplete(id); },
 *     onClose: () => { this.drawerVisible = false; }
 *   })
 */
@Component
export struct ElderTodoDrawer {
  /** 是否可见（宿主驱动；false 时整树不渲染，不挡触摸） */
  @Prop isVisible: boolean = false;
  /** 待办列表数据 */
  @Prop items: ElderTodoData[] = [];
  /** 主题令牌（未注入时走暖色兜底，§9 判空使用） */
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** 整行点击切换完成回调（DB/事件由宿主 TodoViewModel 承接） */
  onToggle?: (id: number) => void;
  /** 关闭回调（遮罩点击/关闭按钮） */
  onClose?: () => void;

  // ==== 取色（普通方法非 getter，§9.1；均为 string，判空兜底）====
  private getTextPrimary(): string {
    return this.tokens !== null ? this.tokens.textPrimary : FALLBACK_TEXT_PRIMARY;
  }

  private getTextSecondary(): string {
    return this.tokens !== null ? this.tokens.textSecondary : FALLBACK_TEXT_SECONDARY;
  }

  private getTextTertiary(): string {
    return this.tokens !== null ? this.tokens.textTertiary : FALLBACK_TEXT_TERTIARY;
  }

  private getDrawerBg(): string {
    return this.tokens !== null ? this.tokens.bgCard : FALLBACK_BG_CARD;
  }

  private getItemBg(): string {
    return this.tokens !== null ? this.tokens.surface : FALLBACK_SURFACE;
  }

  private getBorder(): string {
    return this.tokens !== null ? this.tokens.border : FALLBACK_BORDER;
  }

  /** 完成态勾选圈底色（近黑高对比；深色主题下 textPrimary 近白同样成立） */
  private getCheckDoneBg(): string {
    return this.tokens !== null ? this.tokens.textPrimary : FALLBACK_TEXT_PRIMARY;
  }

  /** 完成态勾颜色（与勾选圈底反色） */
  private getCheckMarkColor(): string {
    return this.tokens !== null ? this.tokens.bgCard : FALLBACK_BG_CARD;
  }

  /** 未完成数量（普通方法非 getter，§9.1） */
  private getRemainCount(): number {
    return this.items.filter((t: ElderTodoData): boolean => !t.completed).length;
  }

  build() {
    if (this.isVisible) {
      Stack({ alignContent: Alignment.Start }) {
        // ===== 遮罩（点击关闭，渐显）=====
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(SCRIM_COLOR)
          .transition(TransitionEffect.opacity(0)
            .animation({ duration: DRAWER_ANIM_DURATION, curve: Curve.EaseOut }))
          .onClick(() => {
            if (this.onClose !== undefined) {
              this.onClose();
            }
          })
          .accessibilityText('关闭待办列表')

        // ===== 左侧抽屉面板（左滑入场）=====
        Column() {
          // 头部：标题 + 未完成数 + 关闭按钮（56vp）
          Row() {
            Column() {
              Text('今日待办')
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.getTextPrimary())
              Text(this.getRemainCount() > 0 ?
                '还有 ' + this.getRemainCount() + ' 件没做完' :
                '都做完啦')
                .fontSize(18)
                .fontColor(this.getTextSecondary())
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .accessibilityGroup(true)

            Column() {
              SymbolGlyph(IconMapper.CLOSE)
                .fontSize(26)
                .fontColor([this.getTextPrimary()])
            }
            .width(CLOSE_BTN_SIZE)
            .height(CLOSE_BTN_SIZE)
            .borderRadius(16)
            .backgroundColor(this.getItemBg())
            .border({ width: 1.5, color: this.getBorder() })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              if (this.onClose !== undefined) {
                this.onClose();
              }
            })
            .accessibilityText('关闭待办列表')
          }
          .width('100%')
          .padding({ left: 20, right: 16, top: 20, bottom: 16 })

          // 列表 / 空态
          if (this.items.length > 0) {
            List({ space: 12 }) {
              ForEach(this.items, (item: ElderTodoData) => {
                ListItem() {
                  this.buildTodoRow(item)
                }
              }, (item: ElderTodoData): string => item.id.toString() + '_' + (item.completed ? '1' : '0'))
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .padding({ left: 16, right: 16 })

            // 底部操作提示（大字辅助文案）
            Text('点一下事情，就能划掉它')
              .fontSize(18)
              .fontColor(this.getTextSecondary())
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding({ top: 12, bottom: 24 })
          } else {
            Column() {
              SymbolGlyph(IconMapper.EMPTY)
                .fontSize(48)
                .fontColor([this.getTextSecondary()])
              Text('今天没有要做的事')
                .fontSize(22)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.getTextSecondary())
                .margin({ top: 16 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
        }
        .width('82%')
        .constraintSize({ maxWidth: 400 })
        .height('100%')
        .backgroundColor(this.getDrawerBg())
        .transition(TransitionEffect.translate({ x: '-100%' })
          .animation({ duration: DRAWER_ANIM_DURATION, curve: Curve.EaseOut }))
      }
      .width('100%')
      .height('100%')
    }
  }

  // ═══ 待办条目行 @Builder（整行 >=72vp 热区点击完成；大勾选圈 + 24vp 大字标题）═══
  @Builder
  buildTodoRow(item: ElderTodoData) {
    Row() {
      // 大勾选圈（40x40 视觉，行热区整体 >=72vp）
      Column() {
        if (item.completed) {
          SymbolGlyph(IconMapper.CHECKMARK)
            .fontSize(22)
            .fontColor([this.getCheckMarkColor()])
        }
      }
      .width(CHECK_SIZE)
      .height(CHECK_SIZE)
      .borderRadius(CHECK_SIZE / 2)
      .backgroundColor(item.completed ? this.getCheckDoneBg() : Color.Transparent)
      .border({
        width: item.completed ? 0 : 3,
        color: this.getBorder()
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      // 标题 + 可选时间（完成态：删除线 + 灰字）
      Column() {
        Text(item.title)
          .fontSize(24)
          .fontWeight(item.completed ? FontWeight.Normal : FontWeight.Medium)
          .fontColor(item.completed ? this.getTextTertiary() : this.getTextPrimary())
          .decoration(item.completed ? {
            type: TextDecorationType.LineThrough,
            color: this.getTextTertiary()
          } : { type: TextDecorationType.None })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.timeText !== undefined && item.timeText.length > 0) {
          Text(item.timeText)
            .fontSize(18)
            .fontColor(this.getTextSecondary())
            .margin({ top: 4 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 16 })
    }
    .width('100%')
    .constraintSize({ minHeight: ITEM_MIN_HEIGHT })
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .borderRadius(20)
    .backgroundColor(this.getItemBg())
    .border({ width: 1, color: this.getBorder() })
    .onClick(() => {
      if (this.onToggle !== undefined) {
        this.onToggle(item.id);
      }
    })
    .accessibilityGroup(true)
    .accessibilityText(item.completed ?
      '已完成：' + item.title + '，点击恢复为未完成' :
      '未完成：' + item.title + '，点击标记完成')
  }
}
