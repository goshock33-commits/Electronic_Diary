// <!-- agentID: HUI-023 -->
// 组件：分区管理面板（拖拽排序 + 开关显隐 + 标题编辑）
// 关联设计稿：UX-001_prototype.html
// 关联任务：F05（PLN-002 阶段3 五个分区UI）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText + 触控热区 >= 48x48vp
// 深色适配：ThemeColorTokens + 硬编码回退色
// Mock：配置变更本地 @State 管理

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_TITLE=猫啃什锦黑（面板标题）、SKETCH_BODY=清松手写体2（提示文案 + 分区名标签）。
import { IconMapper, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';

/**
 * 分区管理项数据
 */
export interface SectionManageItem {
  sectionKey: string;
  title: string;
  isVisible: boolean;
  icon: Resource;
}

/**
 * 默认五个分区定义
 */
const DEFAULT_SECTION_ITEMS: SectionManageItem[] = [
  { sectionKey: 'today_todo', title: '今日待办', isVisible: true, icon: IconMapper.MOOD_HAPPY },
  { sectionKey: 'tomorrow_todo', title: '明日待办', isVisible: true, icon: IconMapper.TAB_CALENDAR },  // 替代无效 sunrise_fill（本地库0命中）→ TAB_CALENDAR(calendar) 已验证
  { sectionKey: 'extra', title: '多做的事', isVisible: true, icon: IconMapper.ADD },  // 替代 sparkles — 验证来源: IconMapper.ADD 已验证
  { sectionKey: 'happy', title: '开心的事', isVisible: true, icon: IconMapper.MOOD_HEART },
  { sectionKey: 'extracted', title: '提取任务', isVisible: true, icon: IconMapper.ADD }  // 替代无效 lightbulb_fill（本地库0命中）→ ADD(plus_circle_fill) 已验证
];

@Component
export struct SectionManager {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  /** 是否可见 */
  @Prop isVisible: boolean = false;

  /** 分区管理项列表 */
  @State sections: SectionManageItem[] = [...DEFAULT_SECTION_ITEMS];
  /** 拖拽中的项索引 */
  @State private draggingIndex: number = -1;
  /** 拖拽目标索引 */
  @State private targetIndex: number = -1;
  /** 当前编辑项的 key */
  @State private editingKey: string = '';
  /** 编辑中的标题文本 */
  @State private editTitle: string = '';

  onOrderChanged?: (orderedKeys: string[]) => void;
  onVisibilityChanged?: (sectionKey: string, isVisible: boolean) => void;
  onTitleChanged?: (sectionKey: string, newTitle: string) => void;
  onClose?: () => void;

  /** HUI-040：半透明版本：ArkUI hex-alpha 为 #AARRGGBB，需前置 alpha（修复 alpha 后拼致深色拖拽行变黄 bug） */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  build() {
    if (this.isVisible) {
      Column() {
        // 毛玻璃遮罩背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.35)')
          .position({ x: 0, y: 0 })
          .onClick(() => {
            if (this.onClose) {
              this.onClose();
            }
          })
          .gesture(
            TapGesture()
              .onAction(() => {
                if (this.onClose) {
                  this.onClose();
                }
              })
          )

        // 管理面板主体
        Column() {
          // 标题栏
          Row() {
            SymbolGlyph(IconMapper.SECTION_MANAGE)
              .fontSize(20)
              .fontColor([this.tokens ? this.tokens.textPrimary : '#333333'])
              .margin({ right: 10 })
            Text('分区管理')
              .fontSize(18)
              .fontWeight(700)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#333333')
              .attributeModifier(SKETCH_TITLE) // HUI-029：面板标题→猫啃什锦黑
            Blank()
            Button() {
              SymbolGlyph(IconMapper.CLOSE)
                .fontSize(18)
                .fontColor([this.tokens ? this.tokens.textSecondary : '#999999'])
            }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              if (this.onClose) {
                this.onClose();
              }
            })
            .accessibilityText('关闭分区管理')
          }
          .width('100%')
          .height(56)
          .padding({ left: 20, right: 8 })

          Divider()
            .strokeWidth(0.5)
            .color(this.tokens ? this.tokens.divider : '#F0F0F0')
            .margin({ left: 20, right: 20 })

          // 提示文字
          Row() {
            Text('长按拖拽排序，右侧开关控制显示/隐藏')
              .fontSize(12)
              .fontColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
              .padding({ left: 20, top: 12, bottom: 4 })
              .attributeModifier(SKETCH_BODY) // HUI-029：提示文案→清松手写体2
          }
          .width('100%')

          // 分区列表（可拖拽排序）
          Column() {
            ForEach(this.sections, (section: SectionManageItem, idx: number) => {
              Column() {
                this.buildSectionRow(section, idx)
              }
              .width('100%')
              .backgroundColor(
                this.draggingIndex === idx ?
                  // HUI-040：alpha 后拼 → withAlpha 前置（#AARRGGBB），fallback 同步改前置
                  (this.tokens ? this.withAlpha(this.tokens.primary, '14') : '#1400C2B8') :
                  Color.Transparent
              )
              .borderRadius(12)
              .animation({ duration: 200, curve: Curve.EaseInOut })
            }, (section: SectionManageItem) => section.sectionKey)
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 4, bottom: 12 })
        }
        .width('90%')
        .borderRadius(20)
        .backgroundColor(this.tokens ? this.tokens.bgCard : '#FAFAFA')
        .shadow({
          radius: 24,
          color: 'rgba(0,0,0,0.18)',
          offsetY: 8
        })
        .position({ x: '5%', y: '20%' })
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .zIndex(100)
    }
  }

  @Builder
  buildSectionRow(section: SectionManageItem, idx: number) {
    Row() {
      // 拖拽手柄
      SymbolGlyph(IconMapper.DRAG_HANDLE)
        .fontSize(18)
        .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
        .gesture(
          LongPressGesture({ repeat: false, duration: 300 })
            .onAction(() => {
              this.draggingIndex = idx;
            })
        )
        .gesture(
          PanGesture({ fingers: 1, direction: PanDirection.Vertical })
            .onActionUpdate((event: GestureEvent) => {
              if (this.draggingIndex < 0) {
                return;
              }
              const moveY: number = event.offsetY;
              const rowHeight: number = 56;
              const offsetRows: number = Math.round(moveY / rowHeight);
              this.targetIndex = Math.max(0, Math.min(this.sections.length - 1,
                this.draggingIndex + offsetRows));
            })
            .onActionEnd(() => {
              if (this.draggingIndex >= 0 && this.targetIndex >= 0 &&
                this.draggingIndex !== this.targetIndex) {
                this.swapSections(this.draggingIndex, this.targetIndex);
              }
              this.draggingIndex = -1;
              this.targetIndex = -1;
            })
        )

      // 分区图标
      SymbolGlyph(section.icon)
        .fontSize(16)
        .fontColor([this.getSectionColor(section.sectionKey)])
        .margin({ left: 10 })

      // 分区标题（可编辑）
      if (this.editingKey === section.sectionKey) {
        TextInput({ text: this.editTitle, placeholder: section.title })
          .fontSize(15)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#333333')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.tokens ? this.tokens.border : '#F0F0F0')
          .borderRadius(8)
          .margin({ left: 8, right: 8 })
          .padding({ left: 8, right: 8 })
          .onChange((value: string) => {
            this.editTitle = value;
          })
          .onSubmit(() => {
            this.commitTitleEdit(section.sectionKey);
          })
      } else {
        Text(section.title)
          .fontSize(15)
          .fontWeight(500)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#333333')
          .layoutWeight(1)
          .margin({ left: 8 })
          .maxLines(1)
          .attributeModifier(SKETCH_BODY) // HUI-029：分区名标签→清松手写体2
          .gesture(
            TapGesture({ count: 2 })
              .onAction(() => {
                this.startTitleEdit(section);
              })
          )
      }

      // 编辑标题按钮
      Button() {
        SymbolGlyph(IconMapper.EDIT)  // 替代 pencil — 验证来源: IconMapper.EDIT 已验证
          .fontSize(14)
          .fontColor([this.tokens ? this.tokens.textSecondary : '#999999'])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        if (this.editingKey === section.sectionKey) {
          this.commitTitleEdit(section.sectionKey);
        } else {
          this.startTitleEdit(section);
        }
      })
      .accessibilityText('编辑' + section.title + '标题')

      // 显隐开关
      Toggle({ type: ToggleType.Switch, isOn: section.isVisible })
        .selectedColor(this.tokens ? this.tokens.switchOn : '#C6BBAE') // HUI-035：开关 ON→燕麦 switchOn
        .onChange((isOn: boolean) => {
          this.handleVisibilityChange(section.sectionKey, isOn);
        })
        .width(50)
        .height(28)
        .margin({ left: 8 })
        .accessibilityText(section.title + (section.isVisible ? '已显示' : '已隐藏') + '，点击切换')
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12 })
    .opacity(section.isVisible ? 1 : 0.55)
    .accessibilityGroup(true)
    .accessibilityText('分区：' + section.title + '，第' + (idx + 1) + '个')
  }

  /**
   * 交换两个分区的顺序
   */
  private swapSections(fromIdx: number, toIdx: number): void {
    const newSections: SectionManageItem[] = [...this.sections];
    const moved: SectionManageItem = newSections.splice(fromIdx, 1)[0];
    newSections.splice(toIdx, 0, moved);
    this.sections = newSections;

    if (this.onOrderChanged) {
      const orderedKeys: string[] = newSections.map((s: SectionManageItem) => s.sectionKey);
      this.onOrderChanged(orderedKeys);
    }
  }

  /**
   * 切换分区显示/隐藏
   */
  private handleVisibilityChange(sectionKey: string, isVisible: boolean): void {
    this.sections = this.sections.map((s: SectionManageItem) => {
      if (s.sectionKey === sectionKey) {
        return {
          sectionKey: s.sectionKey,
          title: s.title,
          isVisible: isVisible,
          icon: s.icon
        };
      }
      return s;
    });

    if (this.onVisibilityChanged) {
      this.onVisibilityChanged(sectionKey, isVisible);
    }
  }

  /**
   * 开始编辑标题
   */
  private startTitleEdit(section: SectionManageItem): void {
    this.editingKey = section.sectionKey;
    this.editTitle = section.title;
  }

  /**
   * 提交标题编辑
   */
  private commitTitleEdit(sectionKey: string): void {
    if (this.editTitle.trim().length > 0) {
      this.sections = this.sections.map((s: SectionManageItem) => {
        if (s.sectionKey === sectionKey) {
          return {
            sectionKey: s.sectionKey,
            title: this.editTitle.trim(),
            isVisible: s.isVisible,
            icon: s.icon
          };
        }
        return s;
      });

      if (this.onTitleChanged) {
        this.onTitleChanged(sectionKey, this.editTitle.trim());
      }
    }
    this.editingKey = '';
    this.editTitle = '';
  }

  /**
   * 获取分区图标颜色
   */
  private getSectionColor(sectionKey: string): string {
    const colors: Record<string, string> = {
      'today_todo': '#80CBC4',
      'tomorrow_todo': '#4FC3F7',
      'extra': '#90A4AE',
      'happy': '#90A4AE',
      'extracted': '#80CBC4'
    };
    return colors[sectionKey] || (this.tokens ? this.tokens.primary : '#00C2B8');
  }
}
