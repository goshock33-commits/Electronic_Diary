// agentID: HUI-014
// 卡片：QuoteCard — 每日一言桌面卡片 (2x2)
// 关联设计稿：HUI-014_widget_cards（frontend-design / ui-ux-pro-max / brainstorming）
// 关联任务：T030d（第5批 ExtensionAbility）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式（Stage 模型 / FormExtensionAbility）
// 无障碍：遵守 T042 规范（accessibilityText 不为空、触控热区 >= 48x48vp）
//
// === 图标来源章节 ===
// 所有图标引用自 HarmonyOS SymbolGlyph 系统图标库，均经 IconMapper 验证有效：
// | 图标资源                    | 用途         | 验证来源            |
// |-----------------------------|--------------|---------------------|
// | sys.symbol.shuffle          | 随机刷新名言 | IconMapper.RANDOM   |
// | sys.symbol.ellipsis_message_1| 名言引用图标| IconMapper.QUOTE    |
//
// === 华为文档引用章节 ===
// 核心组件参考：
//   - Text 组件：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-text
//   - Button 组件：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-button
//   - Stack/Column/Row 容器：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-stack
//   - FormExtensionAbility：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-form-formextensionability
//   - 卡片页面能力说明（ArkTS widget modules）：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-widget-modules
// 设计指南参考：
//   - Symbol 图标库：https://developer.huawei.com/consumer/cn/design/harmonyos-symbol/

// ── HUI-016 · 批次1(T009) 手绘换肤豁免（保留 SymbolGlyph，不换 SketchIcon）──────────
// 核验理由（Form Widget 运行时约束）：
//   1) 服务卡片运行于独立 FormRenderService 进程，不共享主应用 AppStorage；SketchIcon 靠
//      @StorageProp('theme_is_dark') 感知深色 → 卡片进程内恒为默认值，深色适配失效，违反
//      换肤铁律「深色必须适配」。SymbolGlyph 原生支持卡片 colorMode:"auto" 深浅自适应。
//   2) SketchIcon 为 @Reusable（面向列表滚动复用），ArkTS 卡片受限运行时无收益且增编译风险。
//   3) SketchIcon 位于 features/statistics，跨进程主题依赖须改显式 strokeColor 方可用。
//   解封条件：迁 SketchIcon 体系入 shared + 卡片内传显式 strokeColor + DevEco 真机验证 @Reusable。
import { IconMapper } from '@ohos/shared';

@Entry
@Component
struct QuoteCard {
  // ── FormBindingData 注入（由 QuoteFormAbility 提供） ──
  @LocalStorageProp('quoteText') quoteText: string = '每一天都是新的开始。';  // 名言正文
  @LocalStorageProp('quoteAuthor') quoteAuthor: string = '';                    // 作者署名
  @LocalStorageProp('hasAuthor') hasAuthor: number = 0;                        // 0=无作者, 1=有作者

  // ── 主题色 ──
  private readonly textPrimaryColor: string = '#2E3A2E';
  private readonly textSecondaryColor: string = '#8A9B8A';
  private readonly accentGreen: string = '#00C2B8';
  private readonly cardBgColor: string = 'rgba(255, 255, 255, 0.85)';
  private readonly quoteMarkColor: string = 'rgba(76, 175, 80, 0.15)';

  build() {
    Stack() {
      // 卡片背景（毛玻璃效果）
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(16)
        .backgroundColor(this.cardBgColor)
        .border({ width: 0.5, color: 'rgba(76, 175, 80, 0.12)' })
        .shadow({ radius: 12, color: 'rgba(76, 175, 80, 0.08)', offsetX: 0, offsetY: 2 })

      // 主内容区
      Column() {
        // 标题行：引用图标 + 标签 + 刷新按钮
        Row() {
          SymbolGlyph(IconMapper.QUOTE)
            .width(12)
            .height(12)
            .fontColor([this.textSecondaryColor])

          Text('每日一言')
            .fontSize(11)
            .fontColor(this.textSecondaryColor)
            .margin({ left: 4 })
            .layoutWeight(1)

          // 刷新按钮
          Button() {
            SymbolGlyph(IconMapper.RANDOM)
              .width(12)
              .height(12)
              .fontColor([this.textSecondaryColor])
          }
          .width(26)
          .height(26)
          .borderRadius(13)
          .backgroundColor(Color.Transparent)
          .accessibilityText('随机刷新名言')
        }
        .width('100%')
        .margin({ bottom: 8 })

        // 名言引文区（引号装饰 + 正文）
        Stack({ alignContent: Alignment.TopStart }) {
          // 装饰左引号（大字淡色）
          Text('"')
            .fontSize(42)
            .fontColor(this.quoteMarkColor)
            .fontWeight(FontWeight.Bold)
            .position({ left: -2, top: -8 })
            .accessibilityLevel('no')

          // 名言正文
          Text(this.quoteText)
            .fontSize(15)
            .lineHeight(22)
            .fontColor(this.textPrimaryColor)
            .fontStyle(FontStyle.Italic)
            .width('100%')
            .padding({ left: 18, right: 4, top: 2 })
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .layoutWeight(1)

        // 作者署名（三元控制显示）
        Text(this.hasAuthor === 1 ? '—— ' + this.quoteAuthor : '')
          .fontSize(11)
          .fontColor(this.textSecondaryColor)
          .width('100%')
          .textAlign(TextAlign.End)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4, right: 2 })
      }
      .width('100%')
      .height('100%')
      .padding({ top: 12, bottom: 12, left: 14, right: 14 })
    }
    .width('100%')
    .height('100%')
    .accessibilityGroup(true)
    .accessibilityText(
      '每日一言卡片：' + this.quoteText +
      (this.hasAuthor === 1 ? ' —— ' + this.quoteAuthor : '')
    )
  }
}
