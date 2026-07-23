// agentID: HUI-014
// 卡片：TodoCard — 今日待办清单桌面卡片 (2x4)
// 关联设计稿：HUI-014_widget_cards（frontend-design / ui-ux-pro-max / brainstorming）
// 关联任务：T030b（第5批 ExtensionAbility）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式（Stage 模型 / FormExtensionAbility）
// 无障碍：遵守 T042 规范（accessibilityText 不为空、触控热区 >= 48x48vp）
//
// === 图标来源章节 ===
// 所有图标引用自 HarmonyOS SymbolGlyph 系统图标库，均经 IconMapper 验证有效：
// | 图标资源                          | 用途             | 验证来源                  |
// |-----------------------------------|------------------|---------------------------|
// | sys.symbol.checkmark              | 待办完成勾选     | IconMapper.CHECKMARK      |
// | sys.symbol.checkmark_circle_fill  | 全部完成成功图标 | IconMapper.CHECKIN_DONE   |
// | sys.symbol.list_bullet            | 待办列表图标     | IconMapper.TAB_TODO       |
//
// === 华为文档引用章节 ===
// 核心组件参考：
//   - List / ListItem：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-list
//   - Text 组件：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-text
//   - Progress 进度条：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-progress
//   - FormExtensionAbility：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-form-formextensionability
//   - 卡片页面能力说明（ArkTS widget modules）：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-widget-modules
// 设计指南参考：
//   - Symbol 图标库：https://developer.huawei.com/consumer/cn/design/harmonyos-symbol/

// ── HUI-016 · 批次1(T008) 手绘换肤豁免（保留 SymbolGlyph，不换 SketchIcon）──────────
// 核验理由（Form Widget 运行时约束）：
//   1) 服务卡片运行于独立 FormRenderService 进程，不共享主应用 AppStorage；SketchIcon 靠
//      @StorageProp('theme_is_dark') 感知深色 → 卡片进程内恒为默认值，深色适配失效，违反
//      换肤铁律「深色必须适配」。SymbolGlyph 原生支持卡片 colorMode:"auto" 深浅自适应。
//   2) SketchIcon 为 @Reusable（面向列表滚动复用），ArkTS 卡片受限运行时无收益且增编译风险。
//   3) SketchIcon 位于 features/statistics，跨进程主题依赖须改显式 strokeColor 方可用。
//   解封条件：迁 SketchIcon 体系入 shared + 卡片内传显式 strokeColor + DevEco 真机验证 @Reusable。
import { IconMapper } from '@ohos/shared';

/** 待办项接口（从 JSON 解析） */
interface TodoItemData {
  title: string;
  completed: number; // 0=未完成, 1=已完成
}

@Entry
@Component
struct TodoCard {
  // ── FormBindingData 注入（由 TodoFormAbility 提供） ──
  @LocalStorageProp('todoListJson') todoListJson: string = '[]'; // JSON 数组字符串
  @LocalStorageProp('completedCount') completedCount: number = 0; // 已完成数量
  @LocalStorageProp('totalCount') totalCount: number = 0;          // 总待办数量
  @LocalStorageProp('dateLabel') dateLabel: string = '今日待办';  // 日期标签

  // ── 主题色 ──
  private readonly textPrimaryColor: string = '#2E3A2E';
  private readonly textSecondaryColor: string = '#8A9B8A';
  private readonly textDoneColor: string = '#BDBDBD';
  private readonly accentGreen: string = '#00C2B8';
  private readonly dividerColor: string = 'rgba(76, 175, 80, 0.10)';
  private readonly cardBgColor: string = 'rgba(255, 255, 255, 0.85)';

  /**
   * 解析 JSON 字符串为待办项数组
   */
  private parseTodos(): TodoItemData[] {
    const result: TodoItemData[] = [];
    const raw: string = this.todoListJson;
    const trimmed: string = (raw.length > 0) ? raw : '[]';
    // 手动解析简单 JSON 数组（避免依赖 JSON.parse 在 widget 中的兼容性问题）
    return this.simpleParseTodos(trimmed);
  }

  /**
   * 轻量级 JSON 数组解析
   * 格式：[{"title":"xxx","completed":0},{"title":"yyy","completed":1}]
   */
  private simpleParseTodos(json: string): TodoItemData[] {
    const items: TodoItemData[] = [];
    const inner: string = (json.charAt(0) === '[') ?
      json.substring(1, json.length - 1) : json;
    if (inner.length === 0) {
      return items;
    }
    // 按对象边界分割
    let depth: number = 0;
    let start: number = 0;
    const len: number = inner.length;
    for (let i: number = 0; i < len; i++) {
      const ch: string = inner.charAt(i);
      if (ch === '{') {
        if (depth === 0) {
          start = i;
        }
        depth++;
      } else if (ch === '}') {
        depth--;
        if (depth === 0) {
          const objStr: string = inner.substring(start, i + 1);
          const item: TodoItemData | null = this.parseOneTodo(objStr);
          if (item !== null) {
            items.push(item);
          }
        }
      }
    }
    return items;
  }

  /**
   * 解析单个 {"title":"...","completed":0} 对象
   */
  private parseOneTodo(objStr: string): TodoItemData | null {
    const titleKey: string = '"title":"';
    const completedKey: string = '"completed":';
    const titleIdx: number = objStr.indexOf(titleKey);
    const compIdx: number = objStr.indexOf(completedKey);
    if (titleIdx === -1) {
      return null;
    }
    const titleStart: number = titleIdx + titleKey.length;
    const titleEnd: number = objStr.indexOf('"', titleStart);
    const title: string = (titleEnd > titleStart) ?
      objStr.substring(titleStart, titleEnd) : '';

    let completed: number = 0;
    if (compIdx !== -1) {
      const compValStart: number = compIdx + completedKey.length;
      const compChar: string = objStr.charAt(compValStart);
      completed = (compChar === '1') ? 1 : 0;
    }

    const result: TodoItemData = { title: title, completed: completed };
    return result;
  }

  build() {
    Stack() {
      // 卡片背景
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(16)
        .backgroundColor(this.cardBgColor)
        .border({ width: 0.5, color: 'rgba(76, 175, 80, 0.12)' })
        .shadow({ radius: 12, color: 'rgba(76, 175, 80, 0.08)', offsetX: 0, offsetY: 2 })

      // 主内容区
      Column() {
        // 标题行：图标 + 日期标签 + 完成计数
        this.buildHeader()

        // 分割线
        Divider()
          .width('100%')
          .height(0.5)
          .color(this.dividerColor)
          .margin({ top: 6, bottom: 6 })

        // 待办列表
        this.buildTodoList()

        // 底部完成统计条
        this.buildFooter()
      }
      .width('100%')
      .height('100%')
      .padding({ top: 14, bottom: 10, left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .accessibilityGroup(true)
    .accessibilityText(
      '待办清单卡片：' + this.dateLabel +
      '，共' + this.totalCount + '项，已完成' + this.completedCount + '项'
    )
  }

  @Builder
  buildHeader() {
    Row() {
      SymbolGlyph(IconMapper.TAB_TODO)
        .width(18)
        .height(18)
        .fontColor([this.accentGreen])

      Text(this.dateLabel)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.textPrimaryColor)
        .margin({ left: 8 })
        .layoutWeight(1)

      // 完成计数徽章
      Text('' + this.completedCount + '/' + this.totalCount)
        .fontSize(12)
        .fontColor(this.accentGreen)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
  }

  @Builder
  buildTodoList() {
    Column() {
      // 使用函数返回值控制列表项渲染（避免 if）
      this.renderTodoItems()
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  buildFooter() {
    Row() {
      // 完成率进度条
      Progress({
        value: this.completedCount,
        total: (this.totalCount > 0) ? this.totalCount : 1,
        type: ProgressType.Linear
      })
        .width('100%')
        .height(3)
        .color(this.accentGreen)
        .style({ strokeWidth: 3 })
    }
    .width('100%')
    .margin({ top: 6 })
  }

  /**
   * 渲染待办列表项
   * 使用三元表达式替代 if，最多显示 3 条
   */
  @Builder
  renderTodoItems() {
    Column() {
      // 三元表达式控制每一项是否显示
      // 第 1 项
      this.renderTodoItem(0)
      // 第 2 项
      this.renderTodoItem(1)
      // 第 3 项
      this.renderTodoItem(2)
    }
    .width('100%')
  }

  @Builder
  renderTodoItem(index: number) {
    Column() {
      Row() {
        // 完成状态勾选图标
        SymbolGlyph((this.parseTodos().length > index && this.parseTodos()[index].completed === 1)
          ? IconMapper.CHECKIN_DONE
          : IconMapper.CHECKMARK)
          .width(18)
          .height(18)
          .fontColor([(this.parseTodos().length > index && this.parseTodos()[index].completed === 1)
            ? this.accentGreen
            : '#E0E0E0'])

        // 待办标题
        Text(this.parseTodos().length > index
          ? this.parseTodos()[index].title
          : '')
          .fontSize(14)
          .fontColor(this.parseTodos().length > index && this.parseTodos()[index].completed === 1
            ? this.textDoneColor
            : this.textPrimaryColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .decoration(this.parseTodos().length > index && this.parseTodos()[index].completed === 1
            ? { type: TextDecorationType.LineThrough, color: this.textDoneColor }
            : { type: TextDecorationType.None })
          .layoutWeight(1)
          .margin({ left: 8 })
      }
      .width('100%')
      .height(24)
    }
    .width('100%')
    .height(this.parseTodos().length > index ? 24 : 0)
  }
}
