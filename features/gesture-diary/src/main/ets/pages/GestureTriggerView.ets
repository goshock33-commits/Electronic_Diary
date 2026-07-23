// <!-- agentID: HUI-061 -->
// 页面：手势日记触发视图（摇一摇/长按书签/右拉触发动画+光晕效果）
// 关联任务：P2-09 手势日记流程页统一薄荷青皮肤（UX-001 §6.3）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 图标来源：harmonyos-symbol → dot_radiowaves_left_and_right（信号波纹，表示摇一摇震动反馈）
// 图标来源：harmonyos-symbol → hand_point_up_tap_fill_1（手势操作类，表示触摸/长按手势）
// 令牌引用：TYPO / RADIUS / IconMapper 来自 @ohos/shared
import type { ThemeColorTokens } from '@ohos/shared';
import { curves } from '@kit.ArkUI';

@Component
export struct GestureTriggerView {
  @State showOverlay: boolean = false;
  @State triggerType: 'shake' | 'swipe' | 'longpress' = 'shake';
  @State gestureEnabled: boolean = true;
  // 父组件可控：挂载时若传入 'shake'/'swipe'/'longpress' 则自动展示对应动画（空串=不自动展示）
  @Prop autoShowType: string = '';
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  onTriggerCapture?: () => void;
  onDismiss?: () => void;

  aboutToAppear(): void {
    if (this.autoShowType === 'shake' || this.autoShowType === 'swipe' || this.autoShowType === 'longpress') {
      this.triggerType = this.autoShowType;
      this.showOverlay = true;
    }
  }

  // === 计算方法已移出 build()：改为普通方法，build 中显式调用() ===
  // ArkTS 声明式范式下 build 中调用 getter 访问 @State 存在首帧 this 绑定/时序风险
  // （triggerIcon 返回 Resource 风险最高，同 StatisticsPage 已实证会崩），改普通方法更稳。

  /** 触发图标：摇一摇用 dot_radiowaves_left_and_right，其他手势用 hand_point_up_tap_fill_1 */
  private getTriggerIcon(): Resource {
    return this.triggerType === 'shake'
      ? $r('sys.symbol.dot_radiowaves_left_and_right')
      : $r('sys.symbol.hand_point_up_tap_fill_1');
  }

  /** 触发提示文案 */
  private getTriggerText(): string {
    const map: Record<string, string> = {
      'shake': '检测到摇一摇',
      'swipe': '检测到右拉手势',
      'longpress': '书签已长按'
    };
    return map[this.triggerType] ?? '准备拍照';
  }

  /** 触发副标题 */
  private getTriggerSubtitle(): string {
    const map: Record<string, string> = {
      'shake': '摇动手机快速拍照写日记',
      'swipe': '从屏幕右边缘向左滑动触发',
      'longpress': '长按书签快速记录'
    };
    return map[this.triggerType] ?? '';
  }

  /** 主题色 fallback */
  private getPrimaryColor(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  // HUI-035：交互色专用 token（雾霾蓝主按钮 / 白按钮文字）
  private getBtnPrimary(): string {
    return this.tokens ? this.tokens.btnPrimary : '#738A9C';
  }

  private getBtnPrimaryText(): string {
    return this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF';
  }

  // === build() 仅含 UI 声明语法 ===

  build() {
    if (this.showOverlay && this.gestureEnabled) {
      Column() {
        Stack() {
          // 光晕背景
          Column()
            .width('100%').height('100%')
            .backgroundColor('rgba(0,0,0,0.6)')
            .backdropBlur(12)
          // 触发动画区
          Column() {
            SymbolGlyph(this.getTriggerIcon())
              .fontSize(64)
              .fontColor([Color.White])
              .scale({ x: 1.05, y: 1.05 })
              .animation({
                duration: 600,
                curve: curves.springMotion(0.35, 0.86, 0.1)
              })
              .accessibilityText(this.getTriggerText())

            Text(this.getTriggerText())
              .fontSize(24).fontWeight(600).fontColor(Color.White)
              .margin({ top: 24 }).textAlign(TextAlign.Center)
              .accessibilityText(this.getTriggerText())

            Text(this.getTriggerSubtitle())
              .fontSize(16).fontColor('rgba(255,255,255,0.7)')
              .margin({ top: 12 }).textAlign(TextAlign.Center)
              .accessibilityText(this.getTriggerSubtitle())

            Row() {
              Button('拍照').fontSize(15).fontWeight(500).fontColor(this.getBtnPrimaryText())
                .backgroundColor(this.getBtnPrimary())
                .borderRadius(24).height(48).padding({ left: 32, right: 32 })
                .onClick(() => {
                  this.showOverlay = false;
                  if (this.onTriggerCapture) { this.onTriggerCapture(); }
                }).accessibilityText('立即拍照').margin({ top: 32 })
              Button('取消').fontSize(15).fontColor('rgba(255,255,255,0.7)')
                .backgroundColor(Color.Transparent).height(48).margin({ left: 16, top: 32 })
                .onClick(() => {
                  this.showOverlay = false;
                  if (this.onDismiss) { this.onDismiss(); }
                }).accessibilityText('取消手势触发')
            }
          }
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        }.width('100%').height('100%')
      }
      .width('100%').height('100%')
    }
  }

  /** 外部调用：显示触发动画 */
  showTrigger(type: 'shake' | 'swipe' | 'longpress'): void {
    this.triggerType = type;
    this.showOverlay = true;
  }

  /** 外部调用：关闭 */
  dismiss(): void {
    this.showOverlay = false;
  }
}

// === @Preview mock 组件（用于 DevEco Studio Previewer 预览） ===

@Preview
@Component
struct GestureTriggerViewPreview {
  build() {
    Column() {
      Stack() {
        // 光晕背景 (mock)
        Column()
          .width('100%').height('100%')
          .backgroundColor('rgba(0,0,0,0.6)')
          .backdropBlur(12)
        // 触发动画区 (mock: triggerType='shake')
        Column() {
          SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right'))
            .fontSize(64)
            .fontColor([Color.White])

          Text('检测到摇一摇')
            .fontSize(24).fontWeight(600).fontColor(Color.White)
            .margin({ top: 24 }).textAlign(TextAlign.Center)

          Text('摇动手机快速拍照写日记')
            .fontSize(16).fontColor('rgba(255,255,255,0.7)')
            .margin({ top: 12 }).textAlign(TextAlign.Center)

          Row() {
            Button('拍照').fontSize(15).fontWeight(500).fontColor(Color.White)
              .backgroundColor('#738A9C') // HUI-035: @Preview mock 无 tokens 字段，套雾霾蓝 btnPrimary 字面量（对齐真实组件）
              .borderRadius(24).height(48).padding({ left: 32, right: 32 })
              .margin({ top: 32 })
            Button('取消').fontSize(15).fontColor('rgba(255,255,255,0.7)')
              .backgroundColor(Color.Transparent).height(48).margin({ left: 16, top: 32 })
          }
        }
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      }.width('100%').height('100%')
    }
    .width('100%').height('100%')
  }
}
