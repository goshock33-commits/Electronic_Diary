// <!-- agentID: HUI-058 -->
// fix: HUI-FRONTEND
// agentID: HUI-041（T-D05：返回箭头统一 — 裸 arrow_left 加粗 ICON.navBack，去圆形填充底）
// 页面：提醒方式设置页（弹通知/响铃/弹通知+响铃 + 自定义铃声选择）
// 关联计划：PLN-003 P2-05（设置 SettingsView 复刻；薄荷青 bento 皮肤）
// 关联需求：UX-001 §2.7 / §7.5 黑白重彩
// 关联规范：PROJECT_SPEC §9（防崩溃）§10（图标本地库）§1.4（三者一致）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
//
// ── 令牌驱动：颜色→tokens；圆角→RADIUS；间距→SPACING；字号字重→TYPO ──
// ── 图标来源（本地库已验证）───────────────────────────────────────
//   | IconMapper.BACK(chevron_left)      | 返回     | 已验证 |
//   | IconMapper.BELL(bell_fill)         | 提醒方式 | 已验证 |
//   | sys.symbol.speaker_wave_3_fill     | 响铃     | 基础系统符号(HUI-030 已用) |
//   | IconMapper.CHECKMARK(checkmark)    | 选中标记 | 已验证 |
//
// ── §9.3 防崩：REMINDER_METHODS 的 icon 为模块级常量数组（非 struct 字段初始值），
//    资源上下文在模块加载后就绪，沿用 HUI-030 既有可运行模式，不闪退。

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-028：引入手绘字体助手——SKETCH_TITLE=猫啃(eyebrow/H1/分组标题)，SKETCH_BODY=清松(方式标题/说明/铃声名)。
import { IconMapper, RADIUS, SPACING, TYPO, ICON, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';
// fix: HUI-FRONTEND — F11：铃声试听工具 + 真实铃声列表（替换硬编码 mock）
import { RingtonePlayUtils, RingtoneMeta } from '@ohos/shared';
import { common } from '@kit.AbilityKit';
// fix: HUI-FRONTEND — F13：提醒方式/铃声选择落 DB（重启不丢失）
import { SettingsViewModel, ReminderMethod, ReminderSettings } from '../viewmodel/SettingsViewModel';

/** 提醒方式选项 */
interface ReminderMethodOption {
  readonly value: string;
  readonly label: string;
  readonly desc: string;
  readonly icon: Resource;
}

const REMINDER_METHODS: ReminderMethodOption[] = [
  {
    value: 'notification',
    label: '弹通知',
    desc: '仅弹出通知栏提醒，无声音',
    icon: IconMapper.BELL
  },
  {
    value: 'ring',
    label: '响铃',
    desc: '仅播放铃声提醒，不弹出通知',
    icon: $r('sys.symbol.speaker_wave_3_fill')
  },
  {
    value: 'both',
    label: '弹通知 + 响铃',
    desc: '同时弹出通知并播放铃声',
    icon: IconMapper.BELL
  }
];

// fix: HUI-FRONTEND — F11：原「模拟铃声选项（mock数据）」硬编码列表已删，
//   改用 RingtonePlayUtils.listRingtones()（id 与原 mock 5 个 id 完全对齐，音源在 rawfile/ringtones/）。

@Component
export struct ReminderSettingsPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  @State currentMethod: string = 'both';
  @State currentRingtoneId: string = 'default';
  @State isCustomRingtoneOn: boolean = false;
  // fix: HUI-FRONTEND — F11：真实铃声列表（静态元数据，无 $r()，§9.3 安全）
  private ringtones: RingtoneMeta[] = RingtonePlayUtils.listRingtones();
  // fix: HUI-FRONTEND — F13：设置业务 VM（setReminderMethod/setReminderRingtone 落 app_settings 表）
  private settingsVM: SettingsViewModel = new SettingsViewModel();
  // 操作回调
  onBack?: () => void;
  onMethodChange?: (method: string) => void;
  onRingtoneChange?: (ringtoneId: string) => void;

  // fix: HUI-FRONTEND — F13：进页回读持久化值（AppStorage 同步首帧 + DB 异步权威覆盖），默认统一 'both'
  aboutToAppear(): void {
    const m = AppStorage.get<string>('app_reminder_method');
    if (m !== undefined && m.length > 0) {
      this.currentMethod = m;
    }
    this.settingsVM.getReminderSettings().then((s: ReminderSettings) => {
      this.currentMethod = s.method;
      if (s.ringtoneUri.length > 0) {
        this.currentRingtoneId = s.ringtoneUri;
      }
    }).catch(() => {
    });
  }

  // fix: HUI-FRONTEND — F11：页面退出必停试听（幂等）
  aboutToDisappear(): void {
    RingtonePlayUtils.stop();
  }

  build() {
    Column() {
      // ═══════════ 顶部返回 + eyebrow + H1 ═══════════
      Row() {
        Button() {
          SymbolGlyph(IconMapper.ARROW_BACK)
            .fontSize(ICON.navBack)
            .fontWeight(FontWeight.Bold) // HUI-041：系统裸箭头加粗
            .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent) // HUI-041：去圆形填充底，保留 40vp 透明热区
        .onClick(() => {
          if (this.onBack) {
            this.onBack();
          }
        })
        .accessibilityText('返回设置')

        Column() {
          Text('REMINDER METHOD')
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(700)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .opacity(0.6)
            .letterSpacing(3)
            .accessibilityLevel('no')
            .attributeModifier(SKETCH_TITLE) // HUI-028：eyebrow 微标→猫啃什锦黑
          Text('提醒方式')
            .fontSize(22)
            .fontWeight(700)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            .margin({ top: 2 })
            .attributeModifier(SKETCH_TITLE) // HUI-028：页面 H1→猫啃什锦黑
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
      }
      .width('100%')
      .padding({ left: SPACING.pageH, right: SPACING.pageH, top: SPACING.pageTop, bottom: 8 })
      .accessibilityText('提醒方式设置')

      Scroll() {
        Column() {
          // ═══════════ 通知方式卡 ═══════════
          this.buildCardTitle('NOTIFY MODE', '通知方式')

          Column() {
            ForEach(REMINDER_METHODS, (method: ReminderMethodOption, index: number) => {
              Column() {
                if (index > 0) {
                  this.buildDivider()
                }
                Row() {
                  SymbolGlyph(method.icon)
                    .fontSize(20)
                    .fontColor([this.currentMethod === method.value
                      ? (this.tokens ? this.tokens.btnPrimary : '#738A9C')
                      : (this.tokens ? this.tokens.textSecondary : '#8A9B8A')]) // HUI-035：选中方式图标→雾霾蓝 btnPrimary
                    .margin({ right: 12 })

                  Column() {
                    Text(method.label)
                      .fontSize(TYPO.cardTitle.size)
                      .fontWeight(TYPO.cardTitle.weight)
                      .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                      .attributeModifier(SKETCH_BODY) // HUI-028：方式标题→清松手写体2
                    Text(method.desc)
                      .fontSize(TYPO.eyebrow.size)
                      .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                      .opacity(0.7)
                      .margin({ top: 2 })
                      .attributeModifier(SKETCH_BODY) // HUI-028：方式说明→清松手写体2
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  if (this.currentMethod === method.value) {
                    SymbolGlyph(IconMapper.CHECKMARK)
                      .fontSize(18)
                      .fontColor([this.tokens ? this.tokens.btnPrimary : '#738A9C'])
                  }
                }
                .width('100%')
                .padding({ top: 14, bottom: 14 })
                .onClick(() => {
                  this.currentMethod = method.value;
                  // fix: HUI-FRONTEND — F13：补调 VM 落 DB（原先只写 AppStorage+prefs，
                  //   loadProfile 用 DB 默认值反杀显示，重启看似重置）
                  this.settingsVM.setReminderMethod(method.value as ReminderMethod).catch(() => {
                  });
                  if (this.onMethodChange) {
                    this.onMethodChange(method.value);
                  }
                })
                .accessibilityText(method.label + '，' + method.desc +
                  (this.currentMethod === method.value ? '，当前选中' : ''))
              }
              .width('100%')
            })
          }
          .width('100%')
          .borderRadius(RADIUS.cardLg)
          .padding({ left: SPACING.cardPadMd, right: SPACING.cardPadMd })
          .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
          .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)' })
          .shadow({
            radius: 12,
            color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
            offsetX: 0,
            offsetY: 4
          })
          .margin({ bottom: SPACING.cardGap })

          // ═══════════ 铃声选择卡 ═══════════
          this.buildCardTitle('RINGTONE', '铃声选择')

          Column() {
            ForEach(this.ringtones, (ringtone: RingtoneMeta, index: number) => {
              Column() {
                if (index > 0) {
                  this.buildDivider()
                }
                Row() {
                  SymbolGlyph(IconMapper.BELL)
                    .fontSize(18)
                    .fontColor([this.currentRingtoneId === ringtone.id
                      ? (this.tokens ? this.tokens.btnPrimary : '#738A9C')
                      : (this.tokens ? this.tokens.textSecondary : '#8A9B8A')])
                    .margin({ right: 12 })

                  Text(ringtone.name)
                    .fontSize(TYPO.cardTitle.size)
                    .fontWeight(TYPO.cardTitle.weight)
                    .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                    .attributeModifier(SKETCH_BODY) // HUI-028：铃声名称→清松手写体2

                  Blank()

                  if (this.currentRingtoneId === ringtone.id) {
                    SymbolGlyph(IconMapper.CHECKMARK)
                      .fontSize(18)
                      .fontColor([this.tokens ? this.tokens.btnPrimary : '#738A9C'])
                  }
                }
                .width('100%')
                .height(52)
                .onClick(() => {
                  this.currentRingtoneId = ringtone.id;
                  // fix: HUI-FRONTEND — F11：选中即试听（页面退出/再点其它铃声自动停）
                  RingtonePlayUtils.play(ringtone.id, getContext(this) as common.Context);
                  // fix: HUI-FRONTEND — F13：铃声选择同步落 DB（重启不丢失）
                  this.settingsVM.setReminderRingtone(ringtone.id).catch(() => {
                  });
                  if (this.onRingtoneChange) {
                    this.onRingtoneChange(ringtone.id);
                  }
                })
                .accessibilityText('铃声：' + ringtone.name +
                  (this.currentRingtoneId === ringtone.id ? '，当前选中' : ''))
              }
              .width('100%')
            })
          }
          .width('100%')
          .borderRadius(RADIUS.cardLg)
          .padding({ left: SPACING.cardPadMd, right: SPACING.cardPadMd })
          .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
          .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)' })
          .shadow({
            radius: 12,
            color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
            offsetX: 0,
            offsetY: 4
          })

          // 底部安全区
          Column().height(SPACING.pageBottom)
        }
        .width('100%')
        .padding({ left: SPACING.pageH, right: SPACING.pageH, top: 8 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens ? this.tokens.bg : '#FAF8F5')
  }

  @Builder
  buildCardTitle(en: string, cn: string) {
    Column() {
      Text(en)
        .fontSize(9)
        .fontWeight(800)
        .fontColor(this.tokens ? this.tokens.primary : '#00C2B8')
        .opacity(0.7)
        .letterSpacing(2)
        .attributeModifier(SKETCH_TITLE) // HUI-028：分组 eyebrow→猫啃什锦黑
      Text(cn)
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(700)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .margin({ top: 2 })
        .attributeModifier(SKETCH_TITLE) // HUI-028：分组标题→猫啃什锦黑
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 12 })
    .accessibilityText(cn)
  }

  @Builder
  buildDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(this.tokens ? this.tokens.divider : '#EAEAE6')
  }
}
