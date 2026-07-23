// <!-- agentID: HUI-065 -->
// 组件：任务确认弹窗「模态框内容主体」（P2-11）
// 关联需求：UX-001 §6.7 任务确认弹窗（复用 §6.1 同款模态骨架）+ §7 黑白重彩 + §1 令牌体系
// 关联计划：PLN-003 P2-11
//
// ── 本组件范围 ──────────────────────────────────────────────────
// · 复用 P2-07a（NfcSharePage）同款模态骨架：40vp 白卡（顶角圆）+ 卡头 eyebrow/关闭；
//   毛玻璃遮罩 + 底部滑入由宿主（entry TaskConfirmPage / bindSheet）提供。
// · 任务列表：ExtractedTaskCard（selectable 勾选模式：圆勾选 + 分类彩标 TaskTypeBadge）。
// · 底部两按钮：全部添加 / 取消。
//
// ── 图标来源（本地库 resource/HarmonyOS_全量图标库.md 已 grep 验证，PROJECT_SPEC §10）──
// · xmark（行293）关闭 —— IconMapper.CLOSE 已在用 ✅
// · checkmark_circle_fill（行83）主按钮 ✅
// · 圆勾选、分类彩标由 ExtractedTaskCard 内部绘制
//
// ── 令牌驱动（PLN-003 阅读须知1）──────────────────────────────────
// · 圆角走 RADIUS；间距走 SPACING；字号/字重走 TYPO；颜色走 tokens（判空兜底）；触控热区 ≥48vp
// · §1.4 三者一致：模块 name = features_task_extraction = 依赖 key = import 路径
//
// ── 崩溃防范（PROJECT_SPEC §9）────────────────────────────────────
// · §9.1 无 getter-in-build（颜色经普通方法）；§9.3 字段初值无 $r()；§9.4 tokens 全判空
// · 无定时器（滑入动画在宿主页）
//
// 开发范式：ArkTS 声明式开发范式

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_TITLE=猫啃什锦黑（eyebrow 微标 + 模态标题）、SKETCH_BODY=清松手写体2（空态正文 + 按钮内文字）；Button('取消') 不动。
import { RADIUS, SPACING, TYPO, IconMapper, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';
import { ExtractedTaskCard } from './ExtractedTaskCard';

// 尺寸常量（集中定义，避免散写魔数）
const R_PILL: number = 999;        // 全圆胶囊（按钮/关闭）
const H_CTA: number = 52;          // 按钮高度（≥48 触控热区）
const SZ_CLOSE: number = 48;       // 关闭按钮（≥48 触控热区）
const MAX_LIST_H: number = 360;    // 任务列表最大高度（超出滚动）

/** 确认弹窗任务展示项（纯基础类型，无 $r() → 符合 §9.3） */
export interface ConfirmTaskItem {
  id: number;
  title: string;
  source: string;
  category: string;
  taskDate: string;
  taskTime: string;
  location: string;
}

@Component
export struct TaskConfirmView {
  @Prop tasks: ConfirmTaskItem[] = [];
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  // 选中的任务 id（默认全选；重新赋值新数组以触发 @State 刷新）
  @State private selectedIds: number[] = [];

  // 回调（由宿主注入）
  onConfirm?: (ids: number[]) => void;
  onCancel?: () => void;
  onClose?: () => void;

  aboutToAppear(): void {
    // 默认全选
    const ids: number[] = [];
    this.tasks.forEach((t: ConfirmTaskItem) => {
      ids.push(t.id);
    });
    this.selectedIds = ids;
  }

  // ==== 颜色兜底（普通方法，非 getter；§9.1 / §9.4）====
  private getCardBg(): string {
    return this.tokens ? this.tokens.bgCard : '#FFFFFF';
  }

  private getPrimary(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  // HUI-035：交互色专用 token（雾霾蓝主按钮 / 燕麦辅助 / 白按钮文字）
  private getBtnPrimary(): string {
    return this.tokens ? this.tokens.btnPrimary : '#738A9C';
  }

  private getBtnAux(): string {
    return this.tokens ? this.tokens.btnAux : '#C6BBAE';
  }

  private getBtnPrimaryText(): string {
    return this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF';
  }

  private getTextPrimary(): string {
    return this.tokens ? this.tokens.textPrimary : '#1A1A1A';
  }

  private getTextSecondary(): string {
    return this.tokens ? this.tokens.textSecondary : '#5A5A5A';
  }

  private getTextTertiary(): string {
    return this.tokens ? this.tokens.textTertiary : '#8A8A8A';
  }

  private getSurface(): string {
    return this.tokens ? this.tokens.surface : '#F2F4F3';
  }

  private getDivider(): string {
    return this.tokens ? this.tokens.divider : '#EAEAEA';
  }

  /** 半透明版本：ArkUI hex-alpha 为 #AARRGGBB，需前置 alpha */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  private isSelected(id: number): boolean {
    return this.selectedIds.includes(id);
  }

  private toggle(id: number): void {
    if (this.selectedIds.includes(id)) {
      this.selectedIds = this.selectedIds.filter((x: number) => x !== id);
    } else {
      this.selectedIds = this.selectedIds.concat(id);
    }
  }

  private confirm(): void {
    if (this.onConfirm) {
      this.onConfirm(this.selectedIds);
    }
    if (this.onClose) {
      this.onClose();
    }
  }

  private cancel(): void {
    if (this.onCancel) {
      this.onCancel();
    }
    if (this.onClose) {
      this.onClose();
    }
  }

  build() {
    Column() {
      // ── 卡头：eyebrow + 标题 + 关闭 ──
      Row() {
        Column() {
          Text('TASK CONFIRM')
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(TYPO.eyebrow.weight)
            .fontColor(this.getTextSecondary())
            .letterSpacing(1.5)
            .opacity(0.6)
            .attributeModifier(SKETCH_TITLE) // HUI-029：eyebrow 微标→猫啃什锦黑
          Text('确认提取的待办')
            .fontSize(TYPO.cardTitle.size)
            .fontWeight(TYPO.cardTitle.weight)
            .fontColor(this.getTextPrimary())
            .margin({ top: 4 })
            .attributeModifier(SKETCH_TITLE) // HUI-029：模态标题→猫啃什锦黑
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(IconMapper.CLOSE)
            .fontSize(18)
            .fontColor([this.getPrimary()])
        }
        .width(SZ_CLOSE)
        .height(SZ_CLOSE)
        .backgroundColor(this.withAlpha(this.getBtnAux(), '1A'))
        .onClick(() => {
          this.cancel();
        })
        .accessibilityText('关闭任务确认')
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // ── 任务列表 / 空态 ──
      if (this.tasks.length > 0) {
        Scroll() {
          Column() {
            ForEach(this.tasks, (item: ConfirmTaskItem) => {
              ExtractedTaskCard({
                taskId: item.id,
                title: item.title,
                source: item.source,
                category: item.category,
                taskDate: item.taskDate,
                taskTime: item.taskTime,
                location: item.location,
                selectable: true,
                selected: this.isSelected(item.id),
                onToggleSelect: (id: number) => {
                  this.toggle(id);
                }
              })
            }, (item: ConfirmTaskItem) => item.id.toString())
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: MAX_LIST_H })
        .scrollBar(BarState.Off)
        .margin({ top: SPACING.cardGap })
      } else {
        Column() {
          Text('暂无可确认的待办')
            .fontSize(TYPO.body.size)
            .fontColor(this.getTextTertiary())
            .attributeModifier(SKETCH_BODY) // HUI-029：空态正文→清松手写体2
        }
        .width('100%')
        .height(120)
        .justifyContent(FlexAlign.Center)
      }

      // ── 分隔线 ──
      Divider()
        .strokeWidth(1)
        .color(this.getDivider())
        .margin({ top: SPACING.cardGap, bottom: SPACING.cardGap })

      // ── 底部两按钮：取消 / 全部添加 ──
      Row() {
        Button('取消')
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.getTextSecondary())
          .backgroundColor(this.getBtnAux())
          .layoutWeight(1)
          .height(H_CTA)
          .borderRadius(R_PILL)
          .onClick(() => {
            this.cancel();
          })
          .accessibilityText('取消，不添加任何待办')

        Button() {
          Row() {
            SymbolGlyph(IconMapper.SUCCESS)
              .fontSize(18)
              .fontColor([this.getBtnPrimaryText()])
            Text('全部添加')
              .fontSize(TYPO.cardTitle.size)
              .fontWeight(TYPO.cardTitle.weight)
              .fontColor(this.getBtnPrimaryText())
              .margin({ left: 6 })
              .attributeModifier(SKETCH_BODY) // HUI-029：按钮内文字标签→清松手写体2
          }
          .alignItems(VerticalAlign.Center)
        }
        .backgroundColor(this.getBtnPrimary())
        .layoutWeight(1)
        .height(H_CTA)
        .borderRadius(R_PILL)
        .margin({ left: SPACING.cardGap })
        .shadow({ radius: 14, color: this.withAlpha(this.getBtnPrimary(), '4D'), offsetX: 0, offsetY: 4 })
        .onClick(() => {
          this.confirm();
        })
        .accessibilityText('全部添加，共 ' + this.selectedIds.length + ' 项选中')
      }
      .width('100%')
    }
    .width('100%')
    .backgroundColor(this.getCardBg())
    .borderRadius({ topLeft: RADIUS.cardLg, topRight: RADIUS.cardLg })
    .padding(SPACING.cardPadLg)
  }
}

// === @Preview mock（DevEco Studio Previewer 预览）===

@Preview
@Component
struct TaskConfirmViewPreview {
  private mockTasks: ConfirmTaskItem[] = [
    { id: 1, title: '周五前提交 UI 重构验收报告', source: 'clipboard', category: 'deadline', taskDate: '07/11', taskTime: '18:00', location: '' },
    { id: 2, title: '下午三点产品评审会议', source: 'wechat', category: 'meeting', taskDate: '07/09', taskTime: '15:00', location: '会议室 A' },
    { id: 3, title: '复习期末考试第 3 章', source: 'voice', category: 'exam', taskDate: '07/12', taskTime: '', location: '' }
  ];

  build() {
    Column() {
      TaskConfirmView({ tasks: this.mockTasks })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .backgroundColor('#99000000')
  }
}
