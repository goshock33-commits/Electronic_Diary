// 页面：首页左侧抽屉菜单组件
// 功能：半透明遮罩 + 左侧滑入白色面板，含打卡/统计/设置三个入口
// 开发范式：ArkTS 声明式开发范式
// 令牌驱动：RADIUS / SPACING / TYPO / IconMapper 全引用；颜色 tokens 判空兜底
// 崩溃防范（PROJECT_SPEC §9）：@StorageLink 全判空；图标走 IconMapper 静态常量

import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper, RADIUS, SPACING, TYPO, SKETCH_BODY, SKETCH_CARD_TITLE } from '@ohos/shared';
import { router, promptAction } from '@kit.ArkUI';

/** 抽屉菜单条目配置 */
interface DrawerMenuItem {
  key: string;
  icon: Resource;
  label: string;
  desc: string;
}

/** 抽屉滑入起始水平位移(vp)，须 >= 抽屉宽度以保证起始完全离屏 */
const DRAWER_SLIDE_X: number = -400;

/**
 * 左侧抽屉菜单组件
 *
 * 通过 @Prop visible 控制显隐，内部使用 if + transition 实现滑入/滑出动画。
 * 点击遮罩或菜单项后通过 onClose 回调通知父组件关闭。
 */
@Component
export struct DrawerMenu {
  @Prop visible: boolean = false;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  onClose: () => void = () => {};

  /** 菜单条目（图标走 IconMapper 静态常量，避免字段初值内联 $r()） */
  private menuItems: DrawerMenuItem[] = [
    { key: 'checkin', icon: IconMapper.CHECKIN_DONE, label: '打卡', desc: '每日签到打卡' },
    { key: 'statistics', icon: IconMapper.CHART_BAR, label: '统计', desc: '查看数据统计' },
    { key: 'settings', icon: IconMapper.SETTINGS, label: '设置', desc: '应用设置' }
  ];

  build() {
    Stack({ alignContent: Alignment.Start }) {
      if (this.visible) {
        // ── 遮罩层（半透明深色，点击关闭）──
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.4)')
          .onClick(() => {
            this.onClose();
          })
          .transition(
            TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseInOut })
          )
          .accessibilityText('点击关闭菜单')

        // ── 抽屉主体（75% 宽，从左滑入）──
        Column() {
          // 抽屉头部：Logo + 应用名
          Row() {
            Image($r('app.media.startIcon'))
              .width(48)
              .height(48)
              .borderRadius(24)

            Column() {
              Text('Mimi随记')
                .fontSize(TYPO.cardTitle.size)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                .attributeModifier(SKETCH_CARD_TITLE)
              Text('家庭日记 · 温暖记录')
                .fontSize(TYPO.eyebrow.size)
                .fontColor(this.tokens ? this.tokens.textSecondary : '#666666')
                .margin({ top: 2 })
                .attributeModifier(SKETCH_BODY)
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ top: 8, bottom: 20 })

          Divider()
            .strokeWidth(0.5)
            .color(this.tokens ? this.tokens.divider : '#EEF0F4')
            .margin({ bottom: 12 })

          // 菜单条目列表
          ForEach(this.menuItems, (item: DrawerMenuItem) => {
            Row() {
              // 圆形图标背景
              Stack() {
                SymbolGlyph(item.icon)
                  .fontSize(20)
                  .fontColor([this.tokens ? this.tokens.primary : '#0A59F7'])
              }
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor(this.tokens ? this.tokens.accent : '#EBF5FF')

              // 标签 + 描述
              Column() {
                Text(item.label)
                  .fontSize(TYPO.cardTitle.size)
                  .fontWeight(TYPO.cardTitle.weight)
                  .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                  .attributeModifier(SKETCH_CARD_TITLE)
                Text(item.desc)
                  .fontSize(TYPO.eyebrow.size)
                  .fontColor(this.tokens ? this.tokens.textTertiary : '#999999')
                  .margin({ top: 2 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .attributeModifier(SKETCH_BODY)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 12 })

              // 右箭头
              SymbolGlyph(IconMapper.FORWARD)
                .fontSize(14)
                .fontColor([this.tokens ? this.tokens.textTertiary : '#999999'])
            }
            .width('100%')
            .height(64)
            .padding({ left: 4, right: 4 })
            .borderRadius(RADIUS.cardMd)
            .onClick(() => {
              this.handleMenuTap(item.key);
            })
            .accessibilityText(item.label + '，' + item.desc)
          }, (item: DrawerMenuItem) => item.key)

          Blank()
        }
        .width('75%')
        .height('100%')
        .padding({
          left: SPACING.cardPadMd,
          right: SPACING.cardPadMd,
          top: 56,
          bottom: SPACING.cardPadMd
        })
        .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
        .shadow({
          radius: 24,
          color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.18)',
          offsetX: 4,
          offsetY: 0
        })
        .transition(
          TransitionEffect.translate({ x: DRAWER_SLIDE_X })
            .animation({ duration: 300, curve: Curve.EaseOut })
            .combine(TransitionEffect.OPACITY.animation({ duration: 200 }))
        )
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.None)
  }

  /**
   * 点击菜单项：先关闭抽屉，再导航到对应页面（未注册页面降级 toast）
   */
  private handleMenuTap(key: string): void {
    this.onClose();
    if (key === 'checkin') {
      router.pushUrl({ url: 'pages/CalendarPage' });
    } else if (key === 'statistics') {
      router.pushUrl({ url: 'pages/StatisticsPage' });
    } else if (key === 'settings') {
      router.pushUrl({ url: 'pages/SettingsPage' });
    }
  }
}
