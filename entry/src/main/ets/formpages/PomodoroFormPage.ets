// <!-- agentID: HUI-015 -->
// 文件: PomodoroFormPage.ets
// 任务: T030c 番茄钟状态桌面卡片 UI 页面
// 关联架构: ARC-001 §3.1 FormExtensionAbility
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
//
// === 图标来源章节 ===
// 所有图标引用自 HarmonyOS SymbolGlyph 系统图标库，均经 IconMapper 验证有效：
// | 图标资源                  | 用途         | 验证来源             |
// |---------------------------|--------------|----------------------|
// | sys.symbol.clock_fill     | 番茄钟图标   | IconMapper.CLOCK     |
// | sys.symbol.play_fill      | 开始计时图标 | IconMapper.PLAY      |
// | sys.symbol.pause_fill     | 暂停图标     | IconMapper.PAUSE     |
//
// === 主题色引用章节 ===
// 所有色值使用 $r('app.color.form_*') 资源引用，支持深色/浅色模式自动切换。
// 资源定义：entry/src/main/resources/base/element/color.json（浅色）
//          entry/src/main/resources/dark/element/color.json（深色）
//
// === 玻璃质感改造 ===
// 根容器 Column → Stack，叠加玻璃层：半透底 + 顶部高光 + 左上角强光 + 星光粒子(2颗)
// 不加内部分隔线（内容已经紧凑）

import { FONT, IconMapper } from '@ohos/shared';

/** 星光粒子位置（2x2 卡片用 2 颗） */
interface SparklePos {
  x: number;
  y: number;
}

const POMODORO_SPARKLES: SparklePos[] = [
  { x: 80, y: 15 },
  { x: 15, y: 70 }
];

/**
 * PomodoroFormPage - 2x2 番茄钟状态桌面卡片 UI
 * 展示计时剩余时间 + 环形进度 + 状态文字
 */
@Entry
@Component
struct PomodoroFormPage {
  @LocalStorageProp('state') pomodoroState: string = 'idle';
  @LocalStorageProp('remainingStr') remainingStr: string = '25:00';
  @LocalStorageProp('progress') progress: number = 0;
  @LocalStorageProp('preset') preset: string = 'focus';
  @LocalStorageProp('totalStr') totalStr: string = '25:00';
  @State private sparkleOpacity: number = 0.6;

  aboutToAppear(): void {
    this.startSparkleAnim();
  }

  private startSparkleAnim(): void {
    // 卡片应用不支持 setTimeout，直接启动动画
    animateTo({ duration: 2000, curve: Curve.EaseInOut, iterations: -1 }, () => {
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
      ForEach(POMODORO_SPARKLES, (pos: SparklePos) => {
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
        // 状态标签行
        Row() {
          Image(IconMapper.CLOCK)
            .width(14)
            .height(14)
            .fillColor($r('app.color.form_text_secondary'))
            .objectFit(ImageFit.Contain)

          Text(this.pomodoroState === 'focus' ? '专注中' :
            this.pomodoroState === 'break' ? '休息中' :
            this.pomodoroState === 'shortBreak' ? '短休息' :
            this.pomodoroState === 'longBreak' ? '长休息' : '待开始')
            .fontSize(12)
            .fontColor($r('app.color.form_text_secondary'))
            .margin({ left: 4 })
        }
        .margin({ bottom: 10 })

        // 环形进度 + 剩余时间
        Stack({ alignContent: Alignment.Center }) {
          Progress({
            value: this.progress,
            total: 100,
            type: ProgressType.Ring
          })
            .width(72)
            .height(72)
            .color(this.pomodoroState === 'focus'
              ? $r('app.color.form_accent_green')
              : this.pomodoroState === 'break'
              ? $r('app.color.form_accent_blue')
              : this.pomodoroState === 'shortBreak'
              ? $r('app.color.form_accent_blue')
              : this.pomodoroState === 'longBreak'
              ? $r('app.color.form_accent_blue')
              : $r('app.color.form_icon_muted'))
            .style({ strokeWidth: 4 })

          Text(this.remainingStr)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.form_text_primary'))
            .fontFamily(FONT.mono)
        }

        // 预设信息
        Text(this.preset === 'focus' ? '番茄钟 ' + this.totalStr :
          this.preset === 'shortBreak' ? '短休息 ' + this.totalStr :
          this.preset === 'longBreak' ? '长休息 ' + this.totalStr : '自定义')
          .fontSize(11)
          .fontColor($r('app.color.form_text_secondary'))
          .margin({ top: 8 })
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
      '番茄钟：' +
      (this.pomodoroState === 'focus' ? '专注中' :
        this.pomodoroState === 'break' ? '休息中' : '待开始') +
      '，剩余' + this.remainingStr
    )
  }
}
