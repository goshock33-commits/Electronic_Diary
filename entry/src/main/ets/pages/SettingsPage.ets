// <!-- agentID: HUI-058 -->（原 HUI-030）
// fix: DEV-013 · T-B01 备份含照片：接线高级设置页 onExportData/onImportData 回调（委托 SettingsViewModel → KnockShareService 统一引擎）
// agentID: HUI-041（T-D05：返回箭头统一 — 裸 arrow_left 加粗 ICON.navBack，去圆形填充底）
// 页面：设置 Tab 页「壳」（组合基础设置 + 高级设置/提醒设置子页入口）
// 关联计划：PLN-003 P2-05（设置 SettingsView 复刻 + 删除主题切换 UI）
// 关联需求：UX-001 §2.7 SettingsView / 决策：主题切换删除（仅留深浅色）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：遵守 T042 规范
//
// 说明：此页面作为 MainPage 的 Tab 内容页「壳」，仅负责子页路由与业务回调绑定，
// 组合 features/settings 模块中的 SettingsPage（基础设置内容主体）、
// AdvancedSettingsPage（高级设置）、ReminderSettingsPage（提醒方式）组件。
//
// P2-05 视觉复刻主战场在 features 内容副本：eyebrow「APP SYSTEM SETTINGS」+ H1「系统设置」
// 置于 features/settings 的 SettingsPage 内容顶部（与 StatisticsPage/TodoPage 一致，随内容滚动），
// 本壳不再重复渲染标题；子页 AdvancedSettingsPage / ReminderSettingsPage 亦自带 eyebrow+H1。
// 主题切换 UI 已删（HUI-045 起，本任务确认保留删除态）：本壳无 ThemeStyle / CustomTheme 路由入口。
//
// === 图标来源章节 ===
// | 图标资源                 | 用途       | 验证来源                    |
// |--------------------------|------------|-----------------------------|
// | sys.symbol.chevron_left  | 返回按钮   | IconMapper.BACK（已验证）   |

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-043：碰一碰分享 / 小艺语音助手入口需要路由跳转
import { router } from '@kit.ArkUI';
// HUI-033 · TST Bug1 修复：引入 ThemeManager + 主题枚举 + AppState 键，用于回落基础设置的业务写入
import { IconMapper, ICON, getThemeManager, ThemeMode, FrostedBlurLevel, AppState, DiaryReminderManager } from '@ohos/shared';
// fix: DEV-013 · 导入/导出回调：高级设置页 onExportData/onImportData 委托 SettingsViewModel
// HUI-030: 从 settings 特性模块导入 UI 组件
import { SettingsPage as FeatureSettingsPage } from 'features/settings';
import { AdvancedSettingsPage } from 'features/settings';
import { ReminderSettingsPage } from 'features/settings';
// fix: HUI-FRONTEND-2 · M17：提醒开关走 SettingsViewModel（内部落库+ReminderAgentService.scheduleDaily 真实调度）
import { SettingsViewModel, ReminderMethod } from 'features/settings';
import { hilog } from '@kit.PerformanceAnalysisKit';

// HUI-063 · P2-07a：碰一碰分享由 @Entry 独立页改为 bindSheet 模态框
// §1.4 三者一致：模块 name = features_share = 依赖 key = import 路径
import { NfcSharePage } from 'features_share';

// HUI-033 · TST Bug1：基础设置中尚未纳入 AppState 的附加状态键（AppStorage 驱动 UI 刷新）
// 注：高对比度（app_high_contrast）改由 ThemeManager.setHighContrast 内部读写（T-BUG-005），此处不再单独持有键。
const KEY_FONT_SCALE = 'app_font_scale';
const KEY_SHAKE_SENSITIVITY_VALUE = 'app_shake_sensitivity_value';
const KEY_FLOATING_ENTRY = 'app_floating_entry';
const KEY_SECURITY_LOCK = 'app_security_lock';
const KEY_REMINDER_ENABLED = 'app_reminder_enabled';
const KEY_REMINDER_METHOD = 'app_reminder_method';

/** 子页面枚举 */
enum SettingsSubPage {
  MAIN = 'main',
  ADVANCED = 'advanced',
  REMINDER = 'reminder'
}

@Component
export struct SettingsPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  @State private currentPage: SettingsSubPage = SettingsSubPage.MAIN;
  // HUI-063 · P2-07a：碰一碰分享模态框显隐（bindSheet 两向绑定 $$）
  @State private nfcSheetShown: boolean = false;

  build() {
    if (this.currentPage === SettingsSubPage.ADVANCED) {
      // 高级设置子页面（AdvancedSettingsPage 自带 eyebrow+H1，故此处仅置返回按钮，避免重复标题）
      Column() {
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
            this.currentPage = SettingsSubPage.MAIN;
          })
          .accessibilityText('返回基础设置')

          Blank()
        }
        .width('100%')
        .height(48)
        .padding({ left: 20, right: 20, top: 12 })

        AdvancedSettingsPage({
          onBack: () => {
            this.currentPage = SettingsSubPage.MAIN;
          },
          onNavigateNfcShare: () => {
            this.nfcSheetShown = true;
          }
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.tokens ? this.tokens.bg : '#FAF8F5')
    } else if (this.currentPage === SettingsSubPage.REMINDER) {
      // 提醒方式子页面 — 回调桥接到 DiaryReminderManager
      ReminderSettingsPage({
        onBack: () => {
          this.currentPage = SettingsSubPage.MAIN;
        },
        onMethodChange: (method: string) => {
          AppStorage.setOrCreate(KEY_REMINDER_METHOD, method);
          DiaryReminderManager.setNotifyMethod(method);
        },
        onRingtoneChange: (ringtoneId: string) => {
          DiaryReminderManager.setRingtone(ringtoneId);
        }
      })
    } else {
      // 基础设置主页
      FeatureSettingsPage({
        // ── 导航类回调 ──
        onNavigateAdvanced: () => {
          this.currentPage = SettingsSubPage.ADVANCED;
        },
        onNavigateReminderSettings: () => {
          this.currentPage = SettingsSubPage.REMINDER;
        },
        // ── 碰一碰分享 / 小艺语音助手入口（HUI-043 路由跳转）──
        // HUI-063 · P2-07a：碰一碰分享改 bindSheet 模态框（不再 pushUrl 独立页）
        onNavigateNfcShare: () => {
          this.nfcSheetShown = true;
        },
        onNavigateVoiceAssistant: () => {
          router.pushUrl({ url: 'pages/VoiceAssistantPage' }).catch(() => {
          });
        },
        // ── 安全锁入口（HUI-065 · P2-11：router 跳转独立解锁页）──
        onNavigateSecurityLock: () => {
          router.pushUrl({ url: 'pages/SecurityLockPage' }).catch(() => {
          });
        },
        // ── 账号登录入口（HUI-058：router 跳转 pages/LoginPage；仅在未登录态可点击）──
        onNavigateLogin: () => {
          router.pushUrl({ url: 'pages/LoginPage' }).catch(() => {
          });
        },
        // ── 家庭成员入口（HUI-069：router 跳转 features_family 独立页）──
        onNavigateFamily: () => {
          router.pushUrl({ url: 'pages/FamilyPage' }).catch(() => {
          });
        },
        // ── 外观类回调（通过 ThemeManager + AppStorage 落地）──
        onFontSizeChange: (level: number) => {
          this.handleFontSizeChange(level);
        },
        onDarkModeChange: (modeIdx: number) => {
          this.handleDarkModeChange(modeIdx);
        },
        onFrostLevelChange: (level: number) => {
          this.handleFrostLevelChange(level);
        },
        onHighContrastToggle: (enabled: boolean) => {
          this.handleHighContrastToggle(enabled);
        },
        // ── 手势与辅助类回调 ──
        onGestureToggle: (enabled: boolean) => {
          AppStorage.setOrCreate(AppState.KEY_GESTURE_DIARY_ENABLED, enabled ? 1 : 0);
        },
        onShakeSensitivityChange: (level: string) => {
          this.handleShakeSensitivityChange(level);
        },
        onFloatingEntryToggle: (enabled: boolean) => {
          AppStorage.setOrCreate(KEY_FLOATING_ENTRY, enabled);
        },
        // ── 安全类回调 ──
        onSecurityLockToggle: (enabled: boolean) => {
          AppStorage.setOrCreate(KEY_SECURITY_LOCK, enabled);
        },
        // ── 提醒类回调 ──
        onReminderToggle: (enabled: boolean) => {
          AppStorage.setOrCreate(KEY_REMINDER_ENABLED, enabled);
          // fix: HUI-FRONTEND-2 · M17：走 SettingsViewModel（落库 + ReminderAgentService.scheduleDaily
          //   真实系统调度，含通知权限申请）；DiaryReminderManager 已退出调度职责（防双重调度竞态）
          new SettingsViewModel().setReminderEnabled(enabled).catch((err: Error) => {
            hilog.error(0x0000, 'SettingsPage', 'setReminderEnabled failed: %{public}s', err.message);
          });
        },
        onReminderMethodChange: (method: string) => {
          AppStorage.setOrCreate(KEY_REMINDER_METHOD, method);
          // fix: HUI-FRONTEND-2 · 方式变更同样走 VM 落库+重调度（notification/ring/both 三档真实消费）
          new SettingsViewModel().setReminderMethod(method as ReminderMethod).catch((err: Error) => {
            hilog.error(0x0000, 'SettingsPage', 'setReminderMethod failed: %{public}s', err.message);
          });
        }
      })
        // HUI-063 · P2-07a：bindSheet 模态框外壳
        //   遮罩 rgba(0,0,0,0.6)（§6.1）+ 底部滑入（preferType=BOTTOM）由 SheetOptions 提供；
        //   40vp 白卡由 NfcSharePage 根 Column 自绘（RADIUS.cardLg 顶角），故 sheet 背景设透明避免双层卡；
        //   自绘关闭 xmark，故 showClose=false；不需拖拽条 dragBar=false。
        .bindSheet($$this.nfcSheetShown, this.NfcSheetBuilder(), {
          preferType: SheetType.BOTTOM,
          height: SheetSize.FIT_CONTENT,
          dragBar: false,
          showClose: false,
          backgroundColor: Color.Transparent,
          maskColor: 'rgba(0,0,0,0.6)'
        })
    }
  }

  // HUI-063 · P2-07a：碰一碰分享模态框内容主体（features_share NfcSharePage）
  @Builder
  NfcSheetBuilder() {
    NfcSharePage({
      onClose: () => {
        this.nfcSheetShown = false;
      }
    })
  }

  // ════════════════════════════════════════════════════════════
  // HUI-033 · TST Bug1 修复：基础设置回调业务实现
  // 统一通过 ThemeManager（主题系统单例）+ AppStorage（响应式刷新）落地
  // ════════════════════════════════════════════════════════════

  /**
   * 字体大小切换
   * FeatureSettingsPage 传入的 level 为缩放系数（1 / 1.25 / 1.5）
   * 同时写入档位索引（0/1/2）与缩放系数，供全局 UI 读取
   */
  private handleFontSizeChange(level: number): void {
    let levelIdx: number = 0;
    if (level >= 1.5) {
      levelIdx = 2;
    } else if (level >= 1.25) {
      levelIdx = 1;
    }
    AppStorage.setOrCreate(AppState.KEY_FONT_SIZE_LEVEL, levelIdx);
    AppStorage.setOrCreate(KEY_FONT_SCALE, level);
  }

  /**
   * 深色模式切换（0=跟随系统, 1=浅色, 2=深色）
   * 通过 ThemeManager.setMode 统一切换主题模式并刷新色板
   */
  private handleDarkModeChange(modeIdx: number): void {
    let mode: ThemeMode = ThemeMode.FOLLOW_SYSTEM;
    if (modeIdx === 1) {
      mode = ThemeMode.LIGHT;
    } else if (modeIdx === 2) {
      mode = ThemeMode.DARK;
    }
    getThemeManager().setMode(mode);
    // 同步 AppState 深色标记（0/1），供非主题模块读取
    AppStorage.setOrCreate(AppState.KEY_DARK_MODE, modeIdx === 2 ? 1 : 0);
  }

  /**
   * 沉浸光感（毛玻璃）等级切换（1=弱, 2=均衡, 3=强）
   */
  private handleFrostLevelChange(level: number): void {
    let frost: FrostedBlurLevel = FrostedBlurLevel.MEDIUM;
    if (level === 1) {
      frost = FrostedBlurLevel.LIGHT;
    } else if (level === 3) {
      frost = FrostedBlurLevel.HEAVY;
    }
    getThemeManager().setFrostLevel(frost);
  }

  /**
   * 高对比度（黑白重彩）模式切换 —— T-BUG-005 修复（HUI-001）
   * 交由 ThemeManager.setHighContrast 切换黑白高对比色板，经 theme_tokens 全局广播即时生效；
   * setHighContrast 内部已写入 'app_high_contrast'，此处无需再单独写入。
   */
  private handleHighContrastToggle(enabled: boolean): void {
    getThemeManager().setHighContrast(enabled);
  }

  /**
   * 摇动灵敏度切换（low/medium/high -> 0/1/2）
   */
  private handleShakeSensitivityChange(level: string): void {
    let idx: number = 1;
    if (level === 'low') {
      idx = 0;
    } else if (level === 'high') {
      idx = 2;
    }
    AppStorage.setOrCreate(AppState.KEY_SHAKE_SENSITIVITY, idx);
    AppStorage.setOrCreate(KEY_SHAKE_SENSITIVITY_VALUE, level);
  }
}
