// <!-- agentID: HUI-058 -->
// <!-- agentID: HUI-049 -->
// fix: DEV-011 —— T-P01：applyNickname 补落 DB（settingsVM.saveNickname → app_settings 表，
//   冷启动由 StartupTasks.warmupSettingsFromDb 回灌 'app_user_nickname'；原先只写会话级 AppStorage 重启即丢）
// fix: HUI-FRONTEND
// HUI-001 · T104：新增「AI 伙伴」卡片（DeepSeek API Key 录入/掩码回显 + 连接测试三分支 Toast；T102 加密持久化真接线，T103 testConnection 契约 stub 待联调）
// fix: F10（HUI-083：安全锁开关 ON → PinSetupModal 设 PIN → SettingsViewModel.setPin；OFF → removePin；取消/失败回拨）
// 页面：我的「设置」SettingsView 复刻（薄荷青 bento 风格）
// 关联计划：PLN-003 P2-05（设置 SettingsView 复刻 + 删除主题切换 UI）
// 关联需求：UX-001 §2.7 SettingsView / §7.5 黑白重彩 / 决策：主题切换删除（仅留深浅色）
// 关联规范：PROJECT_SPEC §9（防崩溃）§10（图标本地库权威）§1.4（模块名三者一致）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
//
// ── 复刻要点（UX-001 §2.7）─────────────────────────────────────────
//   1. eyebrow「APP SYSTEM SETTINGS」（省图标）+ H1「系统设置」
//   2. 资料卡：青圆头像(64vp person 图标) + 昵称 + 3 列统计(日记/连续/番茄，mono 数字)
//   3. 交互体验卡：每日提醒(开关+时间+方式) / 小艺语音 / 沉浸强度三段 / 摇一摇+敏感度
//   4. 外观卡：深色模式三段 + 高对比(黑白重彩)开关；**无 5 主题选择器 / 无自定义主题入口**
//   5. 系统卡：安全锁入口 / 碰一碰分享入口 / 字体大小 / 高级设置(数据导出导入在此)
//
// ── 删除主题切换 UI（决策确认，HUI-045 已做，本页确认保留删除状态）──────
//   · 本页不含「视觉主题卡」的 5 色主题圆点选择器；
//   · 不含自定义主题编辑入口（ThemeStylePage / CustomThemeEditor 已删除，HUI-031 死代码清理）；
//   · ThemeManager.applyPreset / applyCustom 及 5 套彩色预设已随黑白换肤删除（HUI-031）；
//   · 仅保留深色/浅色(深色模式三段) + 高对比(黑白重彩)开关。
//
// ── 令牌驱动（禁硬编码，PLN-003 阅读须知 1）───────────────────────────
//   颜色 → tokens；圆角 → RADIUS；间距 → SPACING；字号字重 → TYPO；mono → FONT。
//
// ── 图标来源（PROJECT_SPEC §10：本地图标库 grep 验证）───────────────
//   | 图标                              | 用途       | 来源                                   |
//   |-----------------------------------|-----------|----------------------------------------|
//   | IconMapper.NAV_PROFILE(person)    | 头像       | IconMapper 已验证(person 在库 L1853)   |
//   | sys.symbol.square_and_pencil      | 编辑昵称   | IconMapper.BOOKMARK 已验证(L1598)      |
//   | IconMapper.NAV_DIARY(book_open_fill)| 日记数   | IconMapper 已验证(L844/935)            |
//   | IconMapper.STREAK_FIRE(flame_fill)| 连续天数   | IconMapper 已验证                      |
//   | IconMapper.CLOCK(clock_fill)      | 番茄数     | IconMapper 已验证                      |
//   | IconMapper.BELL(bell_fill)        | 每日提醒   | IconMapper 已验证                      |
//   | sys.symbol.speaker_wave_3_fill    | 提醒方式   | 基础系统符号(HUI-030 已用)             |
//   | IconMapper.MIC(mic_fill)          | 语音助手   | IconMapper 已验证                      |
//   | IconMapper.VISIBLE(eye)           | 沉浸强度   | IconMapper 已验证                      |
//   | IconMapper.ACCESSIBILITY(figure_roll)| 摇一摇  | IconMapper 已验证                      |
//   | sys.symbol.gearshape_fill         | 摇动灵敏度 | IconMapper.SETTINGS 已验证             |
//   | sys.symbol.rectangle_on_rectangle | 悬浮入口   | 基础系统符号(HUI-030 已用)             |
//   | sys.symbol.moon_fill              | 深色模式   | 基础系统符号(HUI-030 已用)             |
//   | sys.symbol.circle_righthalf_inset_filled | 高对比 | HJDG-001 纠正(HUI-030 已用)         |
//   | IconMapper.FONT_SIZE(textformat)  | 字体大小   | IconMapper 已验证                      |
//   | IconMapper.LOCK(lock_fill)        | 安全锁     | IconMapper 已验证                      |
//   | sys.symbol.dot_radiowaves_left_and_right | 碰一碰 | HJDG-001 纠正(HUI-030 已用)         |
//   | IconMapper.SETTINGS(gearshape_fill)| 高级设置  | IconMapper 已验证                      |
//   | IconMapper.FORWARD(chevron_right) | 导航箭头   | IconMapper 已验证                      |

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-026：引入手绘字体助手（全局黑白手绘换肤）——SKETCH_TITLE=猫啃(H1/eyebrow/分组标题)，SKETCH_BODY=清松(卡片标题/正文/标签/按钮)；mono 统计数字与 HH:mm 时间保留不动。
import { IconMapper, RADIUS, SPACING, TYPO, FONT, getThemeManager, ThemeMode, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';
import { AppState } from '@ohos/shared';
// HUI-001 · T104：AI 伙伴卡片——DeepSeek API Key 加密持久化 + 连接测试
import { PersistentState, DSErrorKind, DeepSeekClient, MODEL_ID } from '@ohos/shared';
import { curves, router, promptAction } from '@kit.ArkUI';
// HUI-049：账号登录状态 — AccountManager 用于登出（@StorageProp 响应式驱动登录态回显）
import { AccountManager } from '@ohos/shared';
// HUI-001 · T-BUG-004 / T-FEAT-002：昵称编辑弹窗 + 每日提醒时间选择器
import { NicknameEditModal } from '../components/NicknameEditModal';
import { ReminderTimePickerModal } from '../components/ReminderTimePickerModal';
// fix: F10：安全锁 PIN 设置弹窗 + 设置业务 VM（setPin/removePin/hasPinSet 持久化）
import { PinSetupModal } from '../components/PinSetupModal';
import { SettingsViewModel } from '../viewmodel/SettingsViewModel';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { DSChatResult } from '@ohos/shared';
import { ApiKeyEditModal } from '../components/ApiKeyEditModal';

/** 三段选择器 / Toggle 切换弹性动效曲线（springMotion: response=0.55, dampingFraction=0.72，自然回弹不生硬） */
const SETTINGS_SPRING: ICurve = curves.springMotion(0.55, 0.72);

/** 深色模式选项（modeValue: 0=跟随系统, 1=浅色, 2=深色） */
interface DarkModeOption {
  readonly label: string;
  readonly modeValue: number;
}

/** 沉浸光感等级选项（level: 1=弱, 2=均衡, 3=强） */
interface FrostLevelOption {
  readonly label: string;
  readonly level: number;
  readonly desc: string;
}

/** 摇动灵敏度选项 */
interface ShakeSensitivityOption {
  readonly label: string;
  readonly value: string;
}

/** 字体大小选项 */
interface FontSizeOption {
  readonly label: string;
  readonly value: number;
}

/** 提醒方式选项 */
interface ReminderMethodOption {
  readonly label: string;
  readonly value: string;
}

/** 资料卡统计项 */
interface ProfileStat {
  readonly label: string;
  readonly value: number;
  readonly color: string;
}

const DARK_MODE_OPTIONS: DarkModeOption[] = [
  { label: '跟随系统', modeValue: 0 },
  { label: '浅色', modeValue: 1 },
  { label: '深色', modeValue: 2 }
];

const FROST_LEVEL_OPTIONS: FrostLevelOption[] = [
  { label: '强', level: 3, desc: '背景高度雾化' },
  { label: '均衡', level: 2, desc: '背景半透' },
  { label: '弱', level: 1, desc: '背景隐约可见' }
];

const SHAKE_SENSITIVITY_OPTIONS: ShakeSensitivityOption[] = [
  { label: '低', value: 'low' },
  { label: '中', value: 'medium' },
  { label: '高', value: 'high' }
];

const FONT_SIZE_OPTIONS: FontSizeOption[] = [
  { label: '标准', value: 1 },
  { label: '大', value: 1.25 },
  { label: '特大', value: 1.5 }
];

const REMINDER_METHOD_OPTIONS: ReminderMethodOption[] = [
  { label: '弹通知', value: 'notification' },
  { label: '响铃', value: 'ring' },
  { label: '弹通知+响铃', value: 'both' }
];

/** 提醒时间状态 */
interface ReminderTimeState {
  isEnabled: boolean;
  hour: number;
  minute: number;
}

@Component
export struct SettingsPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  @StorageLink('theme_is_dark') isDark: boolean = false;

  // ── 资料区 ──
  @State nickname: string = '时光旅人';

  // ── 提醒 ──
  @State reminderState: ReminderTimeState = { isEnabled: false, hour: 20, minute: 0 };
  @State currentReminderMethod: string = 'both';
  // ── 外观 ──
  @State currentDarkModeIdx: number = 0;
  @State isHighContrastOn: boolean = false;
  @State currentFontSize: number = 1;
  // ── 交互体验 ──
  @State currentFrostLevel: number = 2; // 均衡
  @State isGestureDiaryOn: boolean = true;
  @State currentShakeSensitivity: string = 'medium';
  @State isFloatingEntryOn: boolean = true;
  // ── 安全 ──
  @State isSecurityLockOn: boolean = false;
  // ── 账号登录（HUI-058；HUI-LOGIN：独立设置行已删，登录入口统一在资料卡）──
  @StorageProp('account_logged_in') isAccountLoggedIn: boolean = false;

  // ── 弹窗显隐（HUI-001）──
  /** 昵称编辑弹窗（T-BUG-004） */
  @State private showNicknameModal: boolean = false;
  /** 每日提醒时间选择器（T-FEAT-002） */
  @State private showTimePicker: boolean = false;
  /** 安全锁 PIN 设置弹窗（fix: F10） */
  @State private showPinSetupModal: boolean = false;

  // ── AI 伙伴（HUI-001 · T104）──
  /** API Key 录入弹窗显隐 */
  @State private showApiKeyModal: boolean = false;
  /** API Key 掩码回显（未配置 / ****尾4位）；直读 @State 规避「按值 @Builder 参数快照不刷新」坑 */
  @State private apiKeyMask: string = '未配置';
  /** 连接测试 loading（行尾「测试中…」+ 防重入） */
  @State private isTestingConnection: boolean = false;
  /** AI 写作建议开关（HUI-001 ghost text：编辑页内联补全总闸；持久化 persist_ai_writing_suggestion，默认开） */
  @State private isAiSuggestionOn: boolean = true;
  /** 长辈模式开关（DEV：persist_elder_mode，默认关；开启后下次进入首页整页替换为长辈模式页） */
  @State private isElderModeOn: boolean = false;

  /** 设置业务 VM（fix: F10：安全锁 PIN 落库 setPin/removePin/hasPinSet） */
  private settingsVM: SettingsViewModel = new SettingsViewModel();

  // 操作回调：由父组件（entry SettingsPage 壳）绑定业务逻辑
  onNavigateAdvanced?: () => void;
  onNavigateSecurityLock?: () => void;
  onNavigateGestureSettings?: () => void;
  onNavigateReminderSettings?: () => void;
  onNavigateVoiceAssistant?: () => void;
  onNavigateNfcShare?: () => void;
  /** 家庭成员入口（HUI-069：entry 壳绑定 router 跳转 pages/FamilyPage 独立页） */
  onNavigateFamily?: () => void;
  /** 账号登录入口（HUI-058：entry 壳绑定 router 跳转 pages/LoginPage；已登则显示手机号脱敏不跳转） */
  onNavigateLogin?: () => void;
  onReminderToggle?: (enabled: boolean) => void;
  onReminderTimePick?: () => void;
  onFontSizeChange?: (level: number) => void;
  onDarkModeChange?: (modeIdx: number) => void;
  onFrostLevelChange?: (level: number) => void;
  onHighContrastToggle?: (enabled: boolean) => void;
  onGestureToggle?: (enabled: boolean) => void;
  onShakeSensitivityChange?: (level: string) => void;
  onFloatingEntryToggle?: (enabled: boolean) => void;
  onSecurityLockToggle?: (enabled: boolean) => void;
  onReminderMethodChange?: (method: string) => void;

  /**
   * HUI-068: 读取持久化状态回显到设置页控件（解决"跟随系统"等初始态错位）
   * 必须在 aboutToAppear 中调用 ThemeManager.getInstance() 获取运行时态
   */
  // fix: DEV-013 — 去掉 aboutToAppear 的 async：ArkTS 框架同步调用生命周期钩子，
  // 不等待返回的 Promise，导致 await 后的 DB 查询 @State 赋值落在框架变更检测周期外，
  // 首帧始终显示初始 mock 值（42/7）。改为同步 + fire-and-forget loadProfile，
  // @State 赋值在 Promise.then 微任务中触发能正常被框架捕获重绘。
  aboutToAppear(): void {
    // 深色模式：从 ThemeManager 当前主题态回显
    const tm = getThemeManager();
    const theme = tm.getCurrentTheme();
    switch (theme.mode) {
      case ThemeMode.FOLLOW_SYSTEM:
        this.currentDarkModeIdx = 0;
        break;
      case ThemeMode.LIGHT:
        this.currentDarkModeIdx = 1;
        break;
      case ThemeMode.DARK:
        this.currentDarkModeIdx = 2;
        break;
    }
    // 沉浸光感：从 ThemeManager 回显
    this.currentFrostLevel = theme.frostLevel as number;
    // 黑白重彩：从 AppStorage 回显（key 与 entry 壳保持一致）
    const hc = AppStorage.get<boolean>('app_high_contrast');
    if (hc !== undefined) {
      this.isHighContrastOn = hc;
    }
    // 字体大小：从 AppStorage 回显
    const fs = AppStorage.get<number>('app_font_scale');
    if (fs !== undefined) {
      this.currentFontSize = fs;
    }
    // 摇一摇灵敏度：从 AppStorage 回显
    const ss = AppStorage.get<string>('app_shake_sensitivity_value');
    if (ss !== undefined) {
      this.currentShakeSensitivity = ss;
    }
    // 昵称：从 AppStorage 回显（会话级占位存储；跨重启持久化待 DEV 接入 PersistentState）
    const nk = AppStorage.get<string>('app_user_nickname');
    if (nk !== undefined && nk.length > 0) {
      this.nickname = nk;
    }
    // 提醒时间：从 AppStorage 回显（会话级占位；跨重启持久化 persist_reminder_time 待 DEV 接入）
    const rh = AppStorage.get<number>('app_reminder_hour');
    const rm = AppStorage.get<number>('app_reminder_minute');
    if (rh !== undefined || rm !== undefined) {
      this.reminderState = {
        isEnabled: this.reminderState.isEnabled,
        hour: rh !== undefined ? rh : this.reminderState.hour,
        minute: rm !== undefined ? rm : this.reminderState.minute
      };
    }
    // fix: HUI-FRONTEND — F12：补同步读 app_reminder_enabled 初始化提醒开关首帧
    //   （persistProp + 启动 DB 暖入已保证键值就绪；原先只靠异步链路 → 首帧恒「关」肉眼闪烁）
    const re = AppStorage.get<boolean>('app_reminder_enabled');
    if (re !== undefined) {
      this.reminderState = {
        isEnabled: re,
        hour: this.reminderState.hour,
        minute: this.reminderState.minute
      };
    }
    // fix: HUI-FRONTEND — F13：提醒方式回显（否则永远显示初始 'both'，与持久化值脱节）
    const rmethod = AppStorage.get<string>('app_reminder_method');
    if (rmethod !== undefined && rmethod.length > 0) {
      this.currentReminderMethod = rmethod;
    }
    // fix: HUI-FRONTEND — F14：摇一摇/悬浮窗开关回显（persistProp 已持久，页面此前不读 → 重启显示错位）
    const gd = AppStorage.get<number>(AppState.KEY_GESTURE_DIARY_ENABLED);
    if (gd !== undefined) {
      this.isGestureDiaryOn = gd === 1;
    }
    const fe = AppStorage.get<boolean>('app_floating_entry');
    if (fe !== undefined) {
      this.isFloatingEntryOn = fe;
    }
    // 安全锁：从 DB 回显（fix: F10——hasPinSet 为持久化真相，开关随已设 PIN 状态显示）
    this.settingsVM.hasPinSet().then((has: boolean) => {
      this.isSecurityLockOn = has;
    });
    // HUI-001 · T104：API Key 掩码回显（T102 加密通路解密后取尾 4 位；杀进程重开仍在）
    this.refreshApiKeyMask();
    // HUI-001 · ghost text：AI 写作建议开关回显（persistProp 已接盘，读不到按默认开）
    const aiSuggestion = AppStorage.get<number>(PersistentState.KEY_AI_WRITING_SUGGESTION);
    this.isAiSuggestionOn = aiSuggestion === undefined ? true : aiSuggestion === 1;
    // DEV：长辈模式开关回显（persistProp 已接盘，读不到按默认关）
    const elderMode = AppStorage.get<number>(PersistentState.KEY_ELDER_MODE);
    this.isElderModeOn = elderMode === 1;
  }



  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
      Column() {
        // ═══════════ 头部：eyebrow「APP SYSTEM SETTINGS」+ H1「系统设置」 ═══════════
        Column() {
          Text('APP SYSTEM SETTINGS')
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(700)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .opacity(0.6)
            .letterSpacing(3)
            .accessibilityLevel('no')
            .attributeModifier(SKETCH_TITLE) // HUI-026：eyebrow 微标→猫啃什锦黑

          Text('系统设置')
            .fontSize(TYPO.h1.size)
            .fontWeight(TYPO.h1.weight)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            .margin({ top: 4 })
            .attributeModifier(SKETCH_TITLE) // HUI-026：页面 H1→猫啃什锦黑
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: SPACING.sectionGap })
        .accessibilityText('系统设置')

        // ═══════════ 资料卡 ═══════════
        this.buildProfileCard()

        // ═══════════ 交互体验卡 ═══════════
        this.buildInteractionCard()

        // ═══════════ 外观卡（深色/浅色 + 黑白重彩，无主题选择器）═══════════
        this.buildAppearanceCard()

        // ═══════════ AI 伙伴卡（HUI-001 · T104：Key 录入/掩码 + 连接测试）═══════════
        this.buildAiCompanionCard()

        // ═══════════ 系统卡（安全锁 / 碰一碰 / 高级设置）═══════════
        this.buildSystemCard()

        // HUI-049：退出登录按钮（页面底部，仅登录态可见，触控热区 ≥ 48vp）
        //   令牌驱动：bgCard 底 + border 边框 + textSecondary 字色 + shadow 景深（与页面其他卡片风格一致）
        if (this.isAccountLoggedIn) {
          Button('退出登录')
            .width('100%')
            .height(48)
            .fontSize(TYPO.cardTitle.size)
            .fontWeight(TYPO.cardTitle.weight)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
            .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)' })
            .borderRadius(RADIUS.cardLg)
            .shadow({
              radius: 12,
              color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
              offsetX: 0,
              offsetY: 4
            })
            .margin({ top: SPACING.cardGap })
            .onClick(() => { this.handleLogout(); })
        }

        // 底部安全区（避让悬浮 Tab）
        Column().height(SPACING.pageBottom)
      }
      .width('100%')
      .padding({ left: SPACING.pageH, right: SPACING.pageH, top: SPACING.pageTop })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens ? this.tokens.bg : '#FAF8F5')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)

      // 昵称编辑弹窗（T-BUG-004）
      if (this.showNicknameModal) {
        NicknameEditModal({
          initialName: this.nickname,
          onConfirm: (name: string) => {
            this.applyNickname(name);
          },
          onCancel: () => {
            this.showNicknameModal = false;
          }
        })
      }

      // 每日提醒时间选择器（T-FEAT-002）
      if (this.showTimePicker) {
        ReminderTimePickerModal({
          initialHour: this.reminderState.hour,
          initialMinute: this.reminderState.minute,
          onConfirm: (h: number, m: number) => {
            this.applyReminderTime(h, m);
          },
          onCancel: () => {
            this.showTimePicker = false;
          }
        })
      }

      // 安全锁 PIN 设置弹窗（fix: F10）：两段式 4 位数字输入，确认后 setPin 落库，取消/失败回拨 OFF
      if (this.showPinSetupModal) {
        PinSetupModal({
          onConfirm: (pin: string) => {
            this.applyPinSetup(pin);
          },
          onCancel: () => {
            this.cancelPinSetup();
          }
        })
      }

      // API Key 录入弹窗（HUI-001 · T104）：复用昵称弹窗 UI 模式；持久化走 T102 PersistentState.saveApiKey（M6：先例不持久化的坑不复用）
      if (this.showApiKeyModal) {
        ApiKeyEditModal({
          onConfirm: (key: string) => {
            this.applyApiKey(key);
          },
          onCancel: () => {
            this.showApiKeyModal = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // ════════════════════════════════════════════════════════════
  // 资料卡：青圆头像 + 昵称
  // ════════════════════════════════════════════════════════════
  @Builder
  buildProfileCard() {
    Column() {
      // 头像 + 昵称
      Row() {
        // 80vp 圆形默认头像
        Image($r('app.media.icon_default_avatar'))
          .width(80)
          .height(80)
          .borderRadius(40)
          .objectFit(ImageFit.Cover)
          .margin({ right: 16 })

        Column() {
          Row() {
            Text(this.isAccountLoggedIn ? this.nickname : '未登录')
              .fontSize(20)
              .fontWeight(700)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .attributeModifier(SKETCH_BODY)
            if (!this.isAccountLoggedIn) {
              SymbolGlyph(IconMapper.FORWARD)
                .fontSize(14)
                .fontColor([this.tokens ? this.tokens.textSecondary : '#8A9B8A'])
                .margin({ left: 8 })
            }
          }

          Text(this.isAccountLoggedIn ? '点击可编辑昵称' : '点击登录账号')
            .fontSize(TYPO.eyebrow.size)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .opacity(0.7)
            .margin({ top: 4 })
            .attributeModifier(SKETCH_BODY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .onClick(() => {
        if (!this.isAccountLoggedIn) {
          if (this.onNavigateLogin) { this.onNavigateLogin(); }
          return;
        }
        this.showNicknameModal = true;
      })
      .accessibilityText('用户资料：' + this.nickname + '，点击编辑昵称')


    }
    .width('100%')
    .borderRadius(RADIUS.cardLg)
    .padding(SPACING.cardPadMd)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)' })
    .shadow({
      radius: 12,
      color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
      offsetX: 0,
      offsetY: 4
    })
    .margin({ bottom: SPACING.cardGap })
  }

  // ════════════════════════════════════════════════════════════
  // 交互体验卡
  // ════════════════════════════════════════════════════════════
  @Builder
  buildInteractionCard() {
    Column() {
      this.buildCardTitle('EXPERIENCE', '交互体验')

      // 每日提醒（开关）
      this.buildToggleRow(
        IconMapper.BELL,
        '每日提醒',
        '每日定时提醒写日记',
        this.reminderState.isEnabled,
        (checked: boolean) => { this.setReminderEnabled(checked); }
      )

      // 提醒时间（开启时显示）
      if (this.reminderState.isEnabled) {
        this.buildDivider()
        // 提醒时间行 —— 专用响应式行（T-FEAT-002 回归修复：直读 formatReminderTime()，避免按值 @Builder value 不刷新）
        this.buildReminderTimeRow()
      }

      // 提醒方式（开启时显示）
      if (this.reminderState.isEnabled) {
        this.buildDivider()
        this.buildNavRowWithIcon(
          $r('sys.symbol.speaker_wave_3_fill'),
          '提醒方式',
          this.getCurrentReminderMethodLabel(),
          () => {
            if (this.onNavigateReminderSettings) {
              this.onNavigateReminderSettings();
            }
          }
        )
      }

      this.buildDivider()

      // 小艺语音助手入口
      this.buildNavRowWithIcon(
        IconMapper.MIC,
        '小艺语音助手',
        '语音添加待办 / 口述写日记',
        () => {
          if (this.onNavigateVoiceAssistant) {
            this.onNavigateVoiceAssistant();
          }
        }
      )

      this.buildDivider()

      // 沉浸强度（三段：强/均衡/弱，青底白字激活）
      this.buildFrostSegment()

      this.buildDivider()

      // 摇一摇拍照（开关）
      this.buildToggleRow(
        IconMapper.ACCESSIBILITY,
        '摇一摇拍照',
        '摇一摇打开相机拍照写日记',
        this.isGestureDiaryOn,
        (checked: boolean) => { this.setGestureEnabled(checked); }
      )

      // 摇动灵敏度（手势开启时显示，三段）
      if (this.isGestureDiaryOn) {
        this.buildDivider()
        this.buildShakeSegment()
      }

      this.buildDivider()

      // 悬浮窗快捷入口（鸿蒙增强，保留）
      this.buildToggleRow(
        $r('sys.symbol.rectangle_on_rectangle'),
        '悬浮窗快捷入口',
        '首页悬浮任务输入按钮',
        this.isFloatingEntryOn,
        (checked: boolean) => { this.setFloatingEntry(checked); }
      )
    }
    .width('100%')
    .borderRadius(RADIUS.cardLg)
    .padding(SPACING.cardPadMd)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)' })
    .shadow({
      radius: 12,
      color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
      offsetX: 0,
      offsetY: 4
    })
    .margin({ bottom: SPACING.cardGap })
  }

  // ════════════════════════════════════════════════════════════
  // 外观卡（深色/浅色三段 + 高对比开关）—— 无 5 主题选择器 / 无自定义主题
  // ════════════════════════════════════════════════════════════
  @Builder
  buildAppearanceCard() {
    Column() {
      this.buildCardTitle('APPEARANCE', '外观显示')

      // 深色模式（三段：跟随系统/浅色/深色，青底白字激活）
      this.buildDarkModeSegment()

      this.buildDivider()

      // 高对比度（黑白重彩总开关）—— 专用响应式行（T-BUG-005 回归修复：Toggle 直绑 @State，避免按值 @Builder 快照回弹）
      this.buildHighContrastRow()

      this.buildDivider()

      // 字体大小（三段）
      this.buildFontSegment()

      this.buildDivider()

      // 长辈模式开关（DEV：persist_elder_mode 直写 AppStorage，沿用 AI 写作建议开关先例；
      //   生效时机：MainPage onPageShow 读键 replaceUrl 整页替换（冷启动/回前台），非即时跳转。
      //   图标复用 IconMapper.NAV_PROFILE(person)，本文件已验证在库（资料卡头像同源））
      this.buildToggleRow(
        IconMapper.NAV_PROFILE,
        '长辈模式',
        '首页切换为大字语音模式，下次进入生效',
        this.isElderModeOn,
        (checked: boolean) => {
          this.isElderModeOn = checked;
          AppStorage.setOrCreate(PersistentState.KEY_ELDER_MODE, checked ? 1 : 0);
        }
      )
    }
    .width('100%')
    .borderRadius(RADIUS.cardLg)
    .padding(SPACING.cardPadMd)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)' })
    .shadow({
      radius: 12,
      color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
      offsetX: 0,
      offsetY: 4
    })
    .margin({ bottom: SPACING.cardGap })
  }

  // ════════════════════════════════════════════════════════════
  // 系统卡（安全锁 / 碰一碰分享 / 高级设置）
  // ════════════════════════════════════════════════════════════
  @Builder
  buildSystemCard() {
    Column() {
      this.buildCardTitle('SYSTEM', '安全与数据')

      // HUI-LOGIN：原「账号登录」独立导航行已删 —— 登录入口统一走资料卡（buildProfileCard 未登录态点击）

      // 安全锁（开关 + 导航）
      Row() {
        SymbolGlyph(IconMapper.LOCK)
          .fontSize(18)
          .fontColor([this.tokens ? this.tokens.textSecondary : '#8A9B8A'])
          .margin({ right: 12 })

        Column() {
          Text('安全锁')
            .fontSize(TYPO.cardTitle.size)
            .fontWeight(TYPO.cardTitle.weight)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            .attributeModifier(SKETCH_BODY) // HUI-026：行标题→清松手写体2
          Text('4 位 PIN 码保护')
            .fontSize(TYPO.eyebrow.size)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .opacity(0.7)
            .margin({ top: 2 })
            .attributeModifier(SKETCH_BODY) // HUI-026：行说明→清松手写体2
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.isSecurityLockOn })
          .selectedColor(this.tokens ? this.tokens.switchOn : '#C6BBAE') // HUI-034：系统开关 ON 态套 switchOn 燕麦
          .onChange((checked: boolean) => { this.setSecurityLock(checked); })
          .accessibilityText('安全锁开关，当前' + (this.isSecurityLockOn ? '开启' : '关闭'))
          .margin({ right: 6 })

        SymbolGlyph(IconMapper.FORWARD)
          .fontSize(14)
          .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
      }
      .width('100%')
      .height(56)
      .onClick(() => {
        if (this.onNavigateSecurityLock) {
          this.onNavigateSecurityLock();
        }
      })
      .accessibilityText('安全锁设置，4 位 PIN 码保护')

      this.buildDivider()

      // 碰一碰分享入口
      this.buildNavRowWithIcon(
        $r('sys.symbol.dot_radiowaves_left_and_right'),
        '碰一碰分享',
        'NFC 碰触传输图片、备份文件',
        () => {
          if (this.onNavigateNfcShare) {
            this.onNavigateNfcShare();
          }
        }
      )

      this.buildDivider()

      // 家庭成员入口（HUI-069：features_family 独立页，成员列表 + 昵称管理）
      this.buildNavRowWithIcon(
        IconMapper.NAV_PROFILE,
        '家庭成员',
        '成员列表、昵称管理',
        () => {
          if (this.onNavigateFamily) {
            this.onNavigateFamily();
          }
        }
      )

      this.buildDivider()

      // 高级设置入口（数据导出/导入、导出加密在此页内）
      this.buildNavRowWithIcon(
        IconMapper.SETTINGS,
        '高级设置',
        '数据导出 / 导入、导出加密',
        () => {
          if (this.onNavigateAdvanced) {
            this.onNavigateAdvanced();
          }
        }
      )
    }
    .width('100%')
    .borderRadius(RADIUS.cardLg)
    .padding(SPACING.cardPadMd)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)' })
    .shadow({
      radius: 12,
      color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
      offsetX: 0,
      offsetY: 4
    })
  }

  // ════════════════════════════════════════════════════════════
  // 通用 Builder：卡标题 / 分隔线 / 导航行 / 开关行
  // ════════════════════════════════════════════════════════════

  @Builder
  buildCardTitle(en: string, cn: string) {
    Column() {
      Text(en)
        .fontSize(9)
        .fontWeight(800)
        .fontColor(this.tokens ? this.tokens.primary : '#00C2B8')
        .opacity(0.7)
        .letterSpacing(2)
        .attributeModifier(SKETCH_TITLE) // HUI-026：分组 eyebrow→猫啃什锦黑
      Text(cn)
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(700)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .margin({ top: 2 })
        .attributeModifier(SKETCH_TITLE) // HUI-026：分组标题→猫啃什锦黑
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

  @Builder
  buildNavRow(label: string, value: string, onClick: () => void) {
    Row() {
      Text(label)
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(TYPO.cardTitle.weight)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .attributeModifier(SKETCH_BODY) // HUI-026：行标题→清松手写体2（value 可能为 HH:mm 时间，保留不动）

      Blank()

      Text(value)
        .fontSize(TYPO.body.size)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
        .maxLines(1)
        .margin({ right: 4 })

      SymbolGlyph(IconMapper.FORWARD)
        .fontSize(14)
        .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
    }
    .width('100%')
    .height(52)
    .onClick(onClick)
    .accessibilityText(label + '，当前：' + value)
  }

  @Builder
  buildNavRowWithIcon(icon: Resource, label: string, value: string, onClick: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([this.tokens ? this.tokens.textSecondary : '#8A9B8A'])
        .margin({ right: 12 })

      Text(label)
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(TYPO.cardTitle.weight)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .attributeModifier(SKETCH_BODY) // HUI-026：行标题→清松手写体2

      Blank()

      Text(value)
        .fontSize(TYPO.eyebrow.size)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
        .opacity(0.7)
        .maxLines(1)
        .margin({ right: 4 })
        .constraintSize({ maxWidth: 150 })
        .attributeModifier(SKETCH_BODY) // HUI-026：行说明→清松手写体2

      SymbolGlyph(IconMapper.FORWARD)
        .fontSize(14)
        .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
    }
    .width('100%')
    .height(56)
    .onClick(onClick)
    .accessibilityText(label + '，' + value)
  }

  /** HUI-058：账号登录导航行 —— HUI-LOGIN：已删除（登录入口统一在资料卡），本注释占位防止误加回 */

  @Builder
  buildToggleRow(
    icon: Resource,
    label: string,
    hint: string,
    isOn: boolean,
    onToggle: (checked: boolean) => void
  ) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([this.tokens ? this.tokens.textSecondary : '#8A9B8A'])
        .margin({ right: 12 })

      Column() {
        Text(label)
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .attributeModifier(SKETCH_BODY) // HUI-026：开关行标题→清松手写体2
        Text(hint)
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
          .opacity(0.7)
          .margin({ top: 2 })
          .attributeModifier(SKETCH_BODY) // HUI-026：开关行说明→清松手写体2
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(this.tokens ? this.tokens.switchOn : '#C6BBAE') // HUI-034：系统开关 ON 态套 switchOn 燕麦（buildToggleRow 覆盖 每日提醒/摇一摇/悬浮窗 三处）
        .onChange(onToggle)
        .accessibilityText(label + '开关，当前' + (isOn ? '开启' : '关闭'))
    }
    .width('100%')
    .height(56)
    .accessibilityText(label + '：' + hint)
  }

  // ════════════════════════════════════════════════════════════
  // AI 伙伴卡（HUI-001 · T104）：DeepSeek API Key 录入/掩码 + 连接测试
  //   风格复现 buildCardTitle + buildNavRowWithIcon + buildDivider；
  //   两行 value 均为运行时变化值（掩码/测试中…），按本文件既有教训
  //   （T-BUG-005/T-FEAT-002：按值 @Builder 参数快照不刷新）做专用响应式行直读 @State。
  //   图标（本地库 grep 验证，PROJECT_SPEC §10）：
  //     | sys.symbol.key_horizontal | API Key 行 | HarmonyOS_全量图标库.md L1759 |
  //     | sys.symbol.bolt           | 连接测试行 | HarmonyOS_全量图标库.md L1444 |
  //   无青色（T104 红字 L3 + 用户偏好）：新元素 fallback 一律中性灰。
  // ════════════════════════════════════════════════════════════

  @Builder
  buildAiCompanionCard() {
    Column() {
      this.buildCardTitle('AI COMPANION', 'AI 伙伴')

      // API Key 录入行（掩码回显）
      this.buildApiKeyRow()

      this.buildDivider()

      // 连接测试行（loading：行尾「测试中…」）
      this.buildTestConnectionRow()

      this.buildDivider()

      // AI 写作建议开关（HUI-001 ghost text：日记编辑页内联补全总闸，默认开）
      // 图标来源：本地 HarmonyOS_全量图标库.md L726 → lightbulb（已 grep 验证）
      this.buildToggleRow(
        $r('sys.symbol.lightbulb'),
        'AI 写作建议',
        '写日记时浅灰续写建议，回车采纳',
        this.isAiSuggestionOn,
        (checked: boolean) => {
          this.isAiSuggestionOn = checked;
          AppStorage.setOrCreate(PersistentState.KEY_AI_WRITING_SUGGESTION, checked ? 1 : 0);
        }
      )
    }
    .width('100%')
    .borderRadius(RADIUS.cardLg)
    .padding(SPACING.cardPadMd)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,0,0,0.08)' })
    .shadow({
      radius: 12,
      color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.06)',
      offsetX: 0,
      offsetY: 4
    })
    .margin({ bottom: SPACING.cardGap })
  }

  /** API Key 行（T104）：value 直读 this.apiKeyMask —— 已配置显 ****尾4位，未配置显「未配置」 */
  @Builder
  buildApiKeyRow() {
    Row() {
      SymbolGlyph($r('sys.symbol.key_horizontal'))
        .fontSize(18)
        .fontColor([this.tokens ? this.tokens.textSecondary : '#5A5A5A'])
        .margin({ right: 12 })

      Text('DeepSeek API Key')
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(TYPO.cardTitle.weight)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .attributeModifier(SKETCH_BODY) // HUI-026：行标题→清松手写体2（掩码 value 类代码值，保留不动）

      Blank()

      Text(this.apiKeyMask)
        .fontSize(TYPO.eyebrow.size)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
        .opacity(0.7)
        .maxLines(1)
        .margin({ right: 4 })
        .constraintSize({ maxWidth: 150 })

      SymbolGlyph(IconMapper.FORWARD)
        .fontSize(14)
        .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
    }
    .width('100%')
    .height(56)
    .onClick(() => {
      this.showApiKeyModal = true;
    })
    .accessibilityText('DeepSeek API Key，当前：' + this.apiKeyMask + '，点击编辑')
  }

  /** 连接测试行（T104）：value 直读 this.isTestingConnection —— loading 显「测试中…」，结果走 Toast 三分支 */
  @Builder
  buildTestConnectionRow() {
    Row() {
      SymbolGlyph($r('sys.symbol.bolt'))
        .fontSize(18)
        .fontColor([this.tokens ? this.tokens.textSecondary : '#5A5A5A'])
        .margin({ right: 12 })

      Text('连接测试')
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(TYPO.cardTitle.weight)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .attributeModifier(SKETCH_BODY) // HUI-026：行标题→清松手写体2

      Blank()

      Text(this.isTestingConnection ? '测试中…' : '')
        .fontSize(TYPO.eyebrow.size)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
        .opacity(0.7)
        .maxLines(1)
        .margin({ right: 4 })
        .attributeModifier(SKETCH_BODY)

      SymbolGlyph(IconMapper.FORWARD)
        .fontSize(14)
        .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
    }
    .width('100%')
    .height(56)
    .onClick(() => {
      this.onTestConnectionTap();
    })
    .accessibilityText('连接测试' + (this.isTestingConnection ? '，测试中' : '，点击测试 DeepSeek 连接'))
  }

  // ════════════════════════════════════════════════════════════
  // 专用响应式行（HUI-001）：直读 @State/方法，规避「按值 @Builder 参数快照不刷新」
  //   坑：@Builder 的值传递参数在状态变化/重渲时复用旧快照，导致 Toggle 回弹、value 不更新。
  //   解：无参 @Builder 内直接读 this.xxx —— 随组件重渲实时取最新值。
  // ════════════════════════════════════════════════════════════

  /** 黑白重彩开关行（T-BUG-005 回归修复：Toggle.isOn 直绑 this.isHighContrastOn） */
  @Builder
  buildHighContrastRow() {
    Row() {
      SymbolGlyph($r('sys.symbol.circle_righthalf_inset_filled'))
        .fontSize(18)
        .fontColor([this.tokens ? this.tokens.textSecondary : '#8A9B8A'])
        .margin({ right: 12 })

      Column() {
        Text('黑白重彩')
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .attributeModifier(SKETCH_BODY) // HUI-026：开关行标题→清松手写体2
        Text('增强文字与背景对比，信息层级更分明')
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
          .opacity(0.7)
          .margin({ top: 2 })
          .attributeModifier(SKETCH_BODY) // HUI-026：开关行说明→清松手写体2
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.isHighContrastOn })
        .selectedColor(this.tokens ? this.tokens.switchOn : '#C6BBAE') // HUI-034：系统开关 ON 态套 switchOn 燕麦
        .onChange((checked: boolean) => {
          this.setHighContrast(checked);
        })
        .accessibilityText('黑白重彩开关，当前' + (this.isHighContrastOn ? '开启' : '关闭'))
    }
    .width('100%')
    .height(56)
    .accessibilityText('黑白重彩：增强文字与背景对比，信息层级更分明')
  }

  /** 提醒时间行（T-FEAT-002 回归修复：value 直读 this.formatReminderTime()，随 reminderState 换引用实时刷新） */
  @Builder
  buildReminderTimeRow() {
    Row() {
      Text('提醒时间')
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(TYPO.cardTitle.weight)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .attributeModifier(SKETCH_BODY) // HUI-026：行标题→清松手写体2（HH:mm 时间值保留 mono/不套手绘）

      Blank()

      Text(this.formatReminderTime())
        .fontSize(TYPO.body.size)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
        .maxLines(1)
        .margin({ right: 4 })

      SymbolGlyph(IconMapper.FORWARD)
        .fontSize(14)
        .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
    }
    .width('100%')
    .height(52)
    .onClick(() => {
      this.showTimePicker = true;
    })
    .accessibilityText('提醒时间，当前：' + this.formatReminderTime())
  }

  // ════════════════════════════════════════════════════════════
  // 三段控件（青底白字激活）—— 标题行 + 全宽分段轨道
  // 单个分段药丸抽为独立 @Component「SegPill」（见文件末），以获得属性级响应式与弹性动画。
  // ════════════════════════════════════════════════════════════

  /** 三段标题行（左图标 + 标签） */
  @Builder
  buildSegHeader(icon: Resource, label: string) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([this.tokens ? this.tokens.textSecondary : '#8A9B8A'])
        .margin({ right: 12 })
      Text(label)
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(TYPO.cardTitle.weight)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .attributeModifier(SKETCH_BODY) // HUI-026：三段控件标题→清松手写体2
    }
    .width('100%')
    .margin({ bottom: 10 })
  }

  /** 沉浸强度（强/均衡/弱） */
  @Builder
  buildFrostSegment() {
    Column() {
      this.buildSegHeader(IconMapper.VISIBLE, '沉浸强度')
      Row() {
        ForEach(FROST_LEVEL_OPTIONS, (opt: FrostLevelOption) => {
          SegPill({
            label: opt.label,
            isActive: this.currentFrostLevel === opt.level,
            activeBg: this.tokens ? this.tokens.btnPrimary : '#738A9C', // HUI-036：分段选中底改交互色 btnPrimary 雾霾蓝（原 primary 兜底青）
            inactiveText: this.tokens ? this.tokens.textSecondary : '#5A5A5A',
            onTap: () => { this.setFrostLevel(opt.level); }
          })
        }, (opt: FrostLevelOption) => 'frost_' + opt.level)
      }
      .width('100%')
      .padding(4)
      .borderRadius(RADIUS.item)
      .backgroundColor(this.tokens ? this.tokens.surface : '#F2F4F3')
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .accessibilityText('沉浸强度，强均衡弱三档')
  }

  /** 深色模式（跟随系统/浅色/深色） */
  @Builder
  buildDarkModeSegment() {
    Column() {
      this.buildSegHeader($r('sys.symbol.moon_fill'), '深色模式')
      Row() {
        ForEach(DARK_MODE_OPTIONS, (opt: DarkModeOption) => {
          SegPill({
            label: opt.label,
            isActive: this.currentDarkModeIdx === opt.modeValue,
            activeBg: this.tokens ? this.tokens.btnPrimary : '#738A9C', // HUI-036：分段选中底改交互色 btnPrimary 雾霾蓝（原 primary 兜底青）
            inactiveText: this.tokens ? this.tokens.textSecondary : '#5A5A5A',
            onTap: () => { this.setDarkMode(opt.modeValue); }
          })
        }, (opt: DarkModeOption) => 'dark_' + opt.modeValue)
      }
      .width('100%')
      .padding(4)
      .borderRadius(RADIUS.item)
      .backgroundColor(this.tokens ? this.tokens.surface : '#F2F4F3')
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .accessibilityText('深色模式，跟随系统浅色深色三档')
  }

  /** 摇动灵敏度（低/中/高） */
  @Builder
  buildShakeSegment() {
    Column() {
      this.buildSegHeader(IconMapper.SETTINGS, '摇动灵敏度')
      Row() {
        ForEach(SHAKE_SENSITIVITY_OPTIONS, (opt: ShakeSensitivityOption) => {
          SegPill({
            label: opt.label,
            isActive: this.currentShakeSensitivity === opt.value,
            activeBg: this.tokens ? this.tokens.btnPrimary : '#738A9C', // HUI-036：分段选中底改交互色 btnPrimary 雾霾蓝（原 primary 兜底青）
            inactiveText: this.tokens ? this.tokens.textSecondary : '#5A5A5A',
            onTap: () => { this.setShakeSensitivity(opt.value); }
          })
        }, (opt: ShakeSensitivityOption) => 'shake_' + opt.value)
      }
      .width('100%')
      .padding(4)
      .borderRadius(RADIUS.item)
      .backgroundColor(this.tokens ? this.tokens.surface : '#F2F4F3')
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .accessibilityText('摇动灵敏度，低中高三档')
  }

  /** 字体大小（标准/大/特大） */
  @Builder
  buildFontSegment() {
    Column() {
      this.buildSegHeader(IconMapper.FONT_SIZE, '字体大小')
      Row() {
        ForEach(FONT_SIZE_OPTIONS, (opt: FontSizeOption) => {
          SegPill({
            label: opt.label,
            isActive: this.currentFontSize === opt.value,
            activeBg: this.tokens ? this.tokens.btnPrimary : '#738A9C', // HUI-036：分段选中底改交互色 btnPrimary 雾霾蓝（原 primary 兜底青）
            inactiveText: this.tokens ? this.tokens.textSecondary : '#5A5A5A',
            onTap: () => { this.setFontSize(opt.value); }
          })
        }, (opt: FontSizeOption) => 'font_' + opt.value)
      }
      .width('100%')
      .padding(4)
      .borderRadius(RADIUS.item)
      .backgroundColor(this.tokens ? this.tokens.surface : '#F2F4F3')
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .accessibilityText('字体大小，标准大特大三档')
  }

  // ════════════════════════════════════════════════════════════
  // 状态 setter（含回调守卫，避免 build 内内联条件）
  // ════════════════════════════════════════════════════════════

  /** 应用昵称（T-BUG-004 / fix: DEV-011·T-P01）：更新回显 + AppStorage 即时同步 + VM 落 app_settings 表（跨重启持久化） */
  private applyNickname(name: string): void {
    this.nickname = name;
    AppStorage.setOrCreate('app_user_nickname', name);
    // fix: DEV-011 —— 原注释自证"跨重启持久化待 DEV 接入"：补调 saveNickname 落库，
    //   冷启动 StartupTasks.warmupSettingsFromDb 读 DB 回灌 AppStorage → aboutToAppear 回显。
    this.settingsVM.saveNickname(name).catch((err: Error) => {
      hilog.error(0x0000, 'SettingsPage', 'saveNickname failed: %{public}s', err.message);
    });
    this.showNicknameModal = false;
  }

  /** 应用提醒时间（T-FEAT-002 / fix: MAIN-001·M17）：更新回显 + 落库 + 触发系统提醒重调度 */
  private applyReminderTime(hour: number, minute: number): void {
    this.reminderState = { isEnabled: this.reminderState.isEnabled, hour: hour, minute: minute };
    AppStorage.setOrCreate('app_reminder_hour', hour);
    AppStorage.setOrCreate('app_reminder_minute', minute);
    // fix: MAIN-001·M17 —— 原先只写 AppStorage（注释自证"跨重启持久化待 DEV 接入"），重启回默认 20:00。
    // 补调 VM 落 app_settings 表；VM 内部 rescheduleSystemReminder 会按新时间立即重发布系统提醒。
    const hh: string = String(hour).padStart(2, '0');
    const mm: string = String(minute).padStart(2, '0');
    this.settingsVM.setReminderTime(hh + ':' + mm).catch((err: Error) => {
      hilog.error(0x0000, 'SettingsPage', 'setReminderTime failed: %{public}s', err.message);
    });
    this.showTimePicker = false;
  }

  private setReminderEnabled(checked: boolean): void {
    // 弹性动效包裹状态变更：开关切换 + 提醒时间/方式行的展开收起自然回弹
    animateTo({ curve: SETTINGS_SPRING }, () => {
      this.reminderState = {
        isEnabled: checked,
        hour: this.reminderState.hour,
        minute: this.reminderState.minute
      };
    });
    if (this.onReminderToggle) {
      this.onReminderToggle(checked);
    }
  }

  private setFrostLevel(level: number): void {
    animateTo({ curve: SETTINGS_SPRING }, () => {
      this.currentFrostLevel = level;
    });
    if (this.onFrostLevelChange) {
      this.onFrostLevelChange(level);
    }
  }

  private setDarkMode(modeIdx: number): void {
    animateTo({ curve: SETTINGS_SPRING }, () => {
      this.currentDarkModeIdx = modeIdx;
    });
    if (this.onDarkModeChange) {
      this.onDarkModeChange(modeIdx);
    }
  }

  private setHighContrast(checked: boolean): void {
    animateTo({ curve: SETTINGS_SPRING }, () => {
      this.isHighContrastOn = checked;
    });
    if (this.onHighContrastToggle) {
      this.onHighContrastToggle(checked);
    }
  }

  private setGestureEnabled(checked: boolean): void {
    // 弹性动效包裹：开关 + 摇动灵敏度三段行的展开收起
    animateTo({ curve: SETTINGS_SPRING }, () => {
      this.isGestureDiaryOn = checked;
    });
    // fix: HUI-FRONTEND — F14①：补调 VM 落 app_settings 表（备份/碰传/跨设备恢复包含此设置）
    this.settingsVM.setGestureDiaryEnabled(checked).catch(() => {
    });
    if (this.onGestureToggle) {
      this.onGestureToggle(checked);
    }
  }

  private setShakeSensitivity(value: string): void {
    animateTo({ curve: SETTINGS_SPRING }, () => {
      this.currentShakeSensitivity = value;
    });
    if (this.onShakeSensitivityChange) {
      this.onShakeSensitivityChange(value);
    }
  }

  private setFloatingEntry(checked: boolean): void {
    animateTo({ curve: SETTINGS_SPRING }, () => {
      this.isFloatingEntryOn = checked;
    });
    // fix: HUI-FRONTEND — F14③：补调 VM 落 app_settings 表（备份/碰传/跨设备恢复包含此设置）
    this.settingsVM.setFloatingEntryEnabled(checked).catch(() => {
    });
    if (this.onFloatingEntryToggle) {
      this.onFloatingEntryToggle(checked);
    }
  }

  /**
   * 安全锁开关（fix: F10）
   * ON：先乐观置开（开关跟手），弹 PIN 设置弹窗；setPin 成功才通知父组件，取消/失败回拨 OFF
   * OFF：调 SettingsViewModel.removePin() 删除 PIN 并通知父组件
   */
  private setSecurityLock(checked: boolean): void {
    // 幂等守卫：programmatic 回拨/回显引发的 onChange 重入直接忽略（仅响应真实状态翻转）
    if (checked === this.isSecurityLockOn) {
      return;
    }
    if (checked) {
      animateTo({ curve: SETTINGS_SPRING }, () => {
        this.isSecurityLockOn = true;
      });
      this.showPinSetupModal = true;
      return;
    }
    animateTo({ curve: SETTINGS_SPRING }, () => {
      this.isSecurityLockOn = false;
    });
    this.disableSecurityLock();
  }

  /** 关闭安全锁（fix: F10）：removePin 删除 PIN；失败则开关回拨 ON 保持状态一致 */
  private async disableSecurityLock(): Promise<void> {
    try {
      await this.settingsVM.removePin();
      promptAction.showToast({ message: '安全锁已关闭', duration: 1500 });
      if (this.onSecurityLockToggle) {
        this.onSecurityLockToggle(false);
      }
    } catch (_err) {
      animateTo({ curve: SETTINGS_SPRING }, () => {
        this.isSecurityLockOn = true;
      });
      promptAction.showToast({ message: '关闭失败，请重试', duration: 1500 });
    }
  }

  /** PIN 设置确认（fix: F10）：setPin 落库成功 → 关弹窗+通知父组件；失败 → 回拨 OFF */
  private async applyPinSetup(pin: string): Promise<void> {
    try {
      const ok: boolean = await this.settingsVM.setPin(pin);
      if (ok) {
        this.showPinSetupModal = false;
        promptAction.showToast({ message: '安全锁已开启', duration: 1500 });
        if (this.onSecurityLockToggle) {
          this.onSecurityLockToggle(true);
        }
        return;
      }
      this.revertSecurityLockOff('设置失败，请重试');
    } catch (_err) {
      this.revertSecurityLockOff('设置失败，请重试');
    }
  }

  /** PIN 设置取消（fix: F10）：关弹窗，开关回拨 OFF */
  private cancelPinSetup(): void {
    this.revertSecurityLockOff('');
  }

  /** 回拨 OFF（fix: F10）：关弹窗 + 弹性回拨开关 +（可选）Toast */
  private revertSecurityLockOff(msg: string): void {
    this.showPinSetupModal = false;
    animateTo({ curve: SETTINGS_SPRING }, () => {
      this.isSecurityLockOn = false;
    });
    if (msg.length > 0) {
      promptAction.showToast({ message: msg, duration: 1500 });
    }
  }

  private setFontSize(value: number): void {
    animateTo({ curve: SETTINGS_SPRING }, () => {
      this.currentFontSize = value;
    });
    if (this.onFontSizeChange) {
      this.onFontSizeChange(value);
    }
  }

  // ════════════════════════════════════════════════════════════
  // AI 伙伴（HUI-001 · T104）：Key 持久化 + 掩码 + 连接测试
  // ════════════════════════════════════════════════════════════

  /** 掩码回显（T104）：经 T102 解密通路取明文 → ****尾4位；未配置/失败显「未配置」 */
  private async refreshApiKeyMask(): Promise<void> {
    try {
      const key: string = await PersistentState.getApiKey();
      this.apiKeyMask = this.maskApiKey(key);
    } catch (_err) {
      // 解密失败保持「未配置」，不打断页面渲染
    }
  }

  /** 明文 Key → 掩码：空=未配置；<4位=****；其余=****尾4位 */
  private maskApiKey(key: string): string {
    if (key.length === 0) {
      return '未配置';
    }
    if (key.length < 4) {
      return '****';
    }
    return '****' + key.substring(key.length - 4);
  }

  /** 保存 API Key（T104）：走 T102 加密持久化 PersistentState.saveApiKey（M6：不复用昵称弹窗先例的会话级存储） */
  private async applyApiKey(key: string): Promise<void> {
    this.showApiKeyModal = false;
    try {
      const ok: boolean = await PersistentState.saveApiKey(key);
      if (ok) {
        this.apiKeyMask = this.maskApiKey(key);
        promptAction.showToast({ message: 'API Key 已保存', duration: 1500 });
        return;
      }
      promptAction.showToast({ message: '保存失败，请重试', duration: 1500 });
    } catch (_err) {
      promptAction.showToast({ message: '保存失败，请重试', duration: 1500 });
    }
  }

  /** 连接测试入口（T104）：防重入 + loading + 结果 Toast 分支 */
  private async onTestConnectionTap(): Promise<void> {
    if (this.isTestingConnection) {
      return;
    }
    this.isTestingConnection = true;
    let result: DSChatResult;
    try {
      result = await this.runTestConnection();
    } catch (_err) {
      const failed: DSChatResult = {
        ok: false,
        errorKind: DSErrorKind.NETWORK,
        errorText: '网络不可用，请检查网络'
      };
      result = failed;
    }
    this.isTestingConnection = false;
    this.showTestResultToast(result);
  }

  /**
   * 连接测试通路（T104 · T103 联调完成）：DeepSeekClient.testConnection()
   * GET /models（免费轻量，200=Key 有效 / 401=无效，禁 chat 代替【M2】）
   */
  private runTestConnection(): Promise<DSChatResult> {
    return DeepSeekClient.testConnection();
  }

  /**
   * 测试结果 Toast 分支（T104 · 按 DSErrorKind 封闭枚举）：
   *   成功 → 连接成功 (deepseek-v4-flash)；401 → Key 无效；402 → 余额不足；network → 网络不可用；其他 → errorText。
   * TODO(T103 联调)：若 DeepSeekClient 导出 MODEL_ID 常量，成功文案改拼常量，维持「模型 ID 唯一定义点」【F1】。
   */
  private showTestResultToast(result: DSChatResult): void {
    if (result.ok) {
      promptAction.showToast({ message: '连接成功 (deepseek-v4-flash)', duration: 2000 });
      return;
    }
    let msg: string = result.errorText ?? '连接失败，请重试';
    if (result.errorKind === DSErrorKind.HTTP_401) {
      msg = 'Key 无效，请检查后重填';
    } else if (result.errorKind === DSErrorKind.HTTP_402) {
      msg = '余额不足，请到 DeepSeek 控制台充值';
    } else if (result.errorKind === DSErrorKind.NETWORK) {
      msg = '网络不可用，请检查网络';
    }
    promptAction.showToast({ message: msg, duration: 2000 });
  }

  // ════════════════════════════════════════════════════════════
  // 辅助方法
  // ════════════════════════════════════════════════════════════

  private formatReminderTime(): string {
    const h: string = String(this.reminderState.hour).padStart(2, '0');
    const m: string = String(this.reminderState.minute).padStart(2, '0');
    return h + ':' + m;
  }

  private getCurrentReminderMethodLabel(): string {
    const found: ReminderMethodOption | undefined = REMINDER_METHOD_OPTIONS.find(
      (m: ReminderMethodOption) => m.value === this.currentReminderMethod
    );
    return found ? found.label : '弹通知+响铃';
  }

  /** HUI-049：退出登录（确认后调 AccountManager.logout()，无需手动刷新 UI——@StorageProp 自动响应） */
  private handleLogout(): void {
    AlertDialog.show({
      title: '退出登录',
      message: '确定要退出当前账号吗？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '退出',
        action: () => {
          AccountManager.getInstance().logout();
        }
      }
    });
  }
}

// ════════════════════════════════════════════════════════════
// 分段药丸（HUI-079 修复 Bug2：设置页三段选择器弹性动画无效）
// ────────────────────────────────────────────────────────────
// 症结：原 buildSegPill 为局部 @Builder，isActive 以「值参」传入 → ArkUI 不追踪其响应性，
//   高亮不会随 @State 变化刷新。旧代码为强制刷新，把选中态编进 ForEach 的 key
//   （'frost_' + level + '_' + (active?'1':'0')），选中态一变 key 就变 → 组件被销毁重建。
//   而 animateTo / springMotion 只能过渡「已存在节点的属性变化」，对「重建」无能为力，
//   故 HUI-078 加的 springMotion 完全不生效 → 用户「没弹性效果」。
// 修复：药丸抽为独立 @Component，选中态用 @Prop 传入（属性级响应式，稳定 key 下也能就地刷新），
//   并对 backgroundColor / fontColor / scale 施加 .animation(SETTINGS_SPRING) 属性动画：
//   选中态切换时青底与文字色 spring 过渡，非选中态 scale 0.92 → 选中 1.0 带轻微回弹，弹性可见。
@Component
struct SegPill {
  // HUI-041：注入主题 tokens，供未选中态底色跟随主题（原先只有 activeBg 一个死值链路）
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  @Prop label: string;
  @Prop isActive: boolean;
  @Prop activeBg: string;
  @Prop inactiveText: string;
  onTap?: () => void;

  build() {
    Text(this.label)
      .fontSize(12)
      .fontWeight(this.isActive ? 700 : 400)
      .fontColor(this.isActive ? Color.White : this.inactiveText)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(32)
      .borderRadius(RADIUS.input)
      // HUI-041：分段未选中态底由死白 #FFFFFF 改读 surface token（浅色 #F7F7F7 / 深色 #242424），修深色白底浅灰字不可见；选中态仍走 activeBg=btnPrimary
      .backgroundColor(this.isActive ? this.activeBg : (this.tokens ? this.tokens.surface : '#FFFFFF'))
      .attributeModifier(SKETCH_BODY) // HUI-026：分段药丸标签→清松手写体2
      // 选中态微放大回弹，非选中态略缩以强化层级；spring 过渡使弹性可见
      .scale(this.isActive ? { x: 1, y: 1 } : { x: 0.92, y: 0.92 })
      .animation({ curve: SETTINGS_SPRING })
      .onClick(() => {
        if (this.onTap) {
          this.onTap();
        }
      })
      .accessibilityText(this.label + (this.isActive ? '，当前选中' : ''))
  }
}
