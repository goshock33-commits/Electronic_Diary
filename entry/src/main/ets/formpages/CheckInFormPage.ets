// <!-- agentID: HUI-015 -->
// 文件: CheckInFormPage.ets
// 任务: T030a 打卡进度环桌面卡片 UI 页面
// 关联架构: ARC-001 §3.1 FormExtensionAbility
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
//
// === 图标来源章节 ===
// 所有图标引用自 HarmonyOS SymbolGlyph 系统图标库，均经 IconMapper 验证有效：
// | 图标资源                          | 用途             | 验证来源                  |
// |-----------------------------------|------------------|---------------------------|
// | sys.symbol.checkmark_circle_fill  | 已打卡对勾图标   | IconMapper.CHECKIN_DONE   |
// | sys.symbol.checkmark              | 未打卡图标       | IconMapper.CHECKMARK      |
// | sys.symbol.flame_fill             | 连续打卡天数火焰 | IconMapper.STREAK_FIRE    |
//
// === 主题色引用章节 ===
// 所有色值使用 $r('app.color.form_*') 资源引用，支持深色/浅色模式自动切换。
// 资源定义：entry/src/main/resources/base/element/color.json（浅色）
//          entry/src/main/resources/dark/element/color.json（深色）
//
// === 玻璃质感改造 ===
// 根容器 Column → Stack，叠加玻璃层：半透底 + 顶部高光 + 左上角强光 + 星光粒子
// 分隔线放在日期和环形进度之间

import { IconMapper } from '@ohos/shared';

/** 星光粒子位置（2x2 卡片用 2 颗） */
interface SparklePos {
  x: number;
  y: number;
}

const CHECKIN_SPARKLES: SparklePos[] = [
  { x: 85, y: 18 },
  { x: 20, y: 72 }
];

/**
 * CheckInFormPage - 2x2 打卡进度环桌面卡片 UI
 * 展示打卡状态图标、连续天数、当月打卡率环形进度
 * 数据通过 LocalStorageProp 从 FormExtensionAbility 绑定
 */
@Entry
@Component
struct CheckInFormPage {
  @LocalStorageProp('isChecked') isChecked: number = 0;
  @LocalStorageProp('streak') streak: number = 0;
  @LocalStorageProp('monthRate') monthRate: number = 0;
  @LocalStorageProp('dateStr') dateStr: string = '';
  @LocalStorageProp('progressText') progressText: string = '0/30 0%';
  @State private sparkleOpacity: number = 0.6;

  aboutToAppear(): void {
    // 星光呼吸动画
    this.startSparkleAnim();
  }

  private startSparkleAnim(): void {
    // 卡片应用不支持 setTimeout，直接启动动画
    animateTo({ duration: 1500, curve: Curve.EaseInOut, iterations: -1 }, () => {
      this.sparkleOpacity = 0.2;
    });
  }

  build() {
    Stack() {
      // 层1：半透叠加层（模拟磨砂底）
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

      // 层4：星光粒子（2 颗，opacity 呼吸）
      ForEach(CHECKIN_SPARKLES, (pos: SparklePos) => {
        Column() {
          // 十字星：竖条
          Column()
            .width(1.5)
            .height(6)
            .backgroundColor(`rgba(255,255,255,${this.sparkleOpacity})`)
          // 十字星：横条
          Column()
            .width(6)
            .height(1.5)
            .backgroundColor(`rgba(255,255,255,${this.sparkleOpacity})`)
        }
        .position({ x: pos.x, y: pos.y })
      }, (pos: SparklePos) => `${pos.x}_${pos.y}`)

      // 层5：原有内容
      Column() {
        // 打卡状态图标 + 文字
        Row() {
          Image(this.isChecked === 1
            ? IconMapper.CHECKIN_DONE
            : IconMapper.CHECKMARK)
            .width(24)
            .height(24)
            .fillColor(this.isChecked === 1
              ? $r('app.color.form_accent_green')
              : $r('app.color.form_icon_muted'))
            .objectFit(ImageFit.Contain)

          Text(this.isChecked === 1 ? '已打卡' : '未打卡')
            .fontSize(13)
            .fontColor(this.isChecked === 1
              ? $r('app.color.form_accent_green')
              : $r('app.color.form_text_muted'))
            .margin({ left: 6 })
        }
        .width('100%')
        .margin({ bottom: 8 })

        // 连续天数 + 火焰图标
        Row() {
          Image(IconMapper.STREAK_FIRE)
            .width(16)
            .height(16)
            .fillColor(this.streak > 0
              ? $r('app.color.form_accent_orange')
              : $r('app.color.form_icon_inactive'))
            .objectFit(ImageFit.Contain)

          Text('' + this.streak + ' 天')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.form_text_primary'))
            .margin({ left: 4 })
        }
        .margin({ bottom: 6 })

        // 日期
        Text(this.dateStr)
          .fontSize(11)
          .fontColor($r('app.color.form_text_secondary'))
          .margin({ bottom: 4 })

        // 内部分隔线
        Divider()
          .strokeWidth(1)
          .color($r('app.color.form_glass_highlight'))
          .margin({ top: 4, bottom: 6 })

        // 环形进度
        Progress({
          value: this.monthRate,
          total: 100,
          type: ProgressType.Ring
        })
          .width(60)
          .height(60)
          .color(this.isChecked === 1
            ? $r('app.color.form_accent_green')
            : $r('app.color.form_accent_green_dark'))
          .style({ strokeWidth: 4 })

        // 进度文字
        Text(this.progressText)
          .fontSize(12)
          .fontColor($r('app.color.form_text_secondary'))
          .margin({ top: 4 })
      }
      .width('100%')
      .height('100%')
      .padding(12)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
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
      '打卡卡片：' +
      (this.isChecked === 1 ? '今日已打卡' : '今日未打卡') +
      '，连续' + this.streak + '天，' +
      this.progressText
    )
  }
}
