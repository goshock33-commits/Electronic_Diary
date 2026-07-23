// <!-- agentID: HUI-015 -->
// 文件: QuoteFormPage.ets
// 任务: T030d 每日一言桌面卡片 UI 页面
// 关联架构: ARC-001 §3.1 FormExtensionAbility
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
//
// === 图标来源章节 ===
// 所有图标引用自 HarmonyOS SymbolGlyph 系统图标库，均经 IconMapper 验证有效：
// | 图标资源                    | 用途         | 验证来源            |
// |-----------------------------|--------------|---------------------|
// | sys.symbol.ellipsis_message_1| 名言引用图标| IconMapper.QUOTE    |
// | sys.symbol.shuffle          | 刷新图标     | IconMapper.RANDOM   |
//
// === 主题色引用章节 ===
// 所有色值使用 $r('app.color.form_*') 资源引用，支持深色/浅色模式自动切换。
// 资源定义：entry/src/main/resources/base/element/color.json（浅色）
//          entry/src/main/resources/dark/element/color.json（深色）
//
// === 玻璃质感改造 ===
// 根容器 Column → Stack，叠加玻璃层：半透底 + 顶部高光 + 左上角强光 + 星光粒子(2颗)
// 分隔线放在标题行和名言正文之间

import { IconMapper } from '@ohos/shared';

/** 星光粒子位置（2x2 卡片用 2 颗） */
interface SparklePos {
  x: number;
  y: number;
}

const QUOTE_SPARKLES: SparklePos[] = [
  { x: 85, y: 20 },
  { x: 18, y: 65 }
];

/**
 * QuoteFormPage - 2x2 每日一言桌面卡片 UI
 * 展示名言正文 + 作者
 * 每日自动刷新
 */
@Entry
@Component
struct QuoteFormPage {
  @LocalStorageProp('quoteText') quoteText: string = '每一天都是新的开始';
  @LocalStorageProp('quoteAuthor') quoteAuthor: string = '—— 佚名';
  @LocalStorageProp('dateStr') dateStr: string = '';
  @State private sparkleOpacity: number = 0.6;

  aboutToAppear(): void {
    this.startSparkleAnim();
  }

  private startSparkleAnim(): void {
    // 卡片应用不支持 setTimeout，直接启动动画
    animateTo({ duration: 2200, curve: Curve.EaseInOut, iterations: -1 }, () => {
      this.sparkleOpacity = 0.15;
    });
  }

  build() {
    Stack() {
      // 层1：半透叠加层
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.form_glass_overlay'))
        .borderRadius(16)

      // 层2：顶部渐变高光
      Column()
        .width('100%')
        .height('50%')
        .linearGradient({
          angle: 180,
          colors: [['rgba(255,255,255,0.3)', 0.0], ['rgba(255,255,255,0)', 1.0]]
        })
        .borderRadius({ topLeft: 16, topRight: 16 })

      // 层3：左上角强光光斑
      Column()
        .width(50)
        .height(50)
        .borderRadius(25)
        .radialGradient({
          center: [25, 25],
          radius: 25,
          colors: [['rgba(255,255,255,0.5)', 0.0], ['rgba(255,255,255,0)', 0.7]]
        })
        .position({ x: -10, y: -10 })

      // 层4：星光粒子（2 颗）
      ForEach(QUOTE_SPARKLES, (pos: SparklePos) => {
        Column() {
          Column()
            .width(1.5)
            .height(6)
            .backgroundColor('rgba(255,255,255,' + this.sparkleOpacity + ')')
          Column()
            .width(6)
            .height(1.5)
            .backgroundColor('rgba(255,255,255,' + this.sparkleOpacity + ')')
        }
        .position({ x: pos.x, y: pos.y })
      }, (pos: SparklePos) => pos.x + '_' + pos.y)

      // 层5：原有内容
      Column() {
        // 标题行
        Row() {
          Image(IconMapper.QUOTE)
            .width(12)
            .height(12)
            .fillColor($r('app.color.form_text_secondary'))
            .objectFit(ImageFit.Contain)

          Text('每日一言')
            .fontSize(11)
            .fontColor($r('app.color.form_text_secondary'))
            .margin({ left: 4 })

          Blank()

          Text(this.dateStr)
            .fontSize(10)
            .fontColor($r('app.color.form_text_secondary'))
            .margin({ right: 6 })

          Image(IconMapper.RANDOM)
            .width(14)
            .height(14)
            .fillColor($r('app.color.form_text_secondary'))
            .objectFit(ImageFit.Contain)
            .onClick(() => {
              postCardAction(this, { 'action': 'message', 'message': 'refresh' });
            })
            .accessibilityText('换一句')
        }
        .width('100%')
        .margin({ bottom: 6 })

        // 内部分隔线
        Divider()
          .strokeWidth(1)
          .color($r('app.color.form_glass_highlight'))
          .margin({ top: 2, bottom: 8 })

        // 名言正文
        Text(this.quoteText)
          .fontSize(15)
          .lineHeight(22)
          .fontColor($r('app.color.form_text_primary'))
          .fontStyle(FontStyle.Italic)
          .width('100%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        // 作者署名
        Text(this.quoteAuthor.length > 0 ? this.quoteAuthor : '')
          .fontSize(11)
          .fontColor($r('app.color.form_text_secondary'))
          .width('100%')
          .textAlign(TextAlign.End)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })
      }
      .width('100%')
      .height('100%')
      .padding(14)
    }
    .width('100%')
    .height('100%')
    .borderRadius(16)
    .border({ width: 1.5, color: $r('app.color.form_glass_border') })
    .shadow({ radius: 30, color: 'rgba(255,255,255,0.2)', offsetX: 0, offsetY: 0 })
    .shadow({ radius: 12, color: 'rgba(0,0,0,0.1)', offsetX: 0, offsetY: 6 })
    .shadow({ radius: 4, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 2 })
    .backgroundColor(Color.Transparent)
    .accessibilityGroup(true)
    .accessibilityText(
      '每日一言：' + this.quoteText +
      (this.quoteAuthor.length > 0 ? ' ' + this.quoteAuthor : '')
    )
  }
}
