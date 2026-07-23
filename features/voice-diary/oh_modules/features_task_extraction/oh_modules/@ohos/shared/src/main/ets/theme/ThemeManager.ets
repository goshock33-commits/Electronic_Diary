// <!-- agentID: HUI-001 -->
// fix: DEV-011 —— T-P01 外观设置持久化接线：PERSIST_KEY_MODE / PERSIST_KEY_FROST_LEVEL 由"声明未用"改为真持久化
//   （restorePersisted() 在 UI 实例就绪后 persistProp + 回读；setMode/setDarkMode/setFrostLevel 写入持久键）。
//   T-D02 修复（detectSystemDarkMode 用 COLOR_MODE_DARK 判定）原样保留，未动。
// agentID: DEV-010 —— T-D02 修正 detectSystemDarkMode 枚举值判反（系统枚举 DARK=0/LIGHT=1，原代码 ===1 判深色）
// 模块：主题管理器（单例）
// 关联设计稿：UX-001_prototype.html
// 关联任务：T006a
// 关联架构：4.1 主题系统 API（applyPreset / applyCustom / setDarkMode / getCurrentTheme）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 状态管理：AppStorage + PersistentStorage

import { EventBus } from '../utils/EventBus';
// DEV-010 · T-D02：引入系统色彩模式枚举（@kit.AbilityKit 导出 ConfigurationConstant，
//   本地 kits/@kit.AbilityKit.d.ts L95 实证；shared 模块已有多处 @kit.AbilityKit 导入先例）
import { ConfigurationConstant } from '@kit.AbilityKit';
import type { ThemeColorTokens, ThemeState, ThemeChangedEvent } from './ThemeConfig';
import { ThemeMode, FrostedBlurLevel } from './ThemeConfig';
// HUI-021：全局默认改为「手绘黑白」色板 getSketchMonoTokens；5 套彩色预设色板/THEME_PRESETS 已删除。
import { DEFAULT_PRESET_ID, getHighContrastTokens, getSketchMonoTokens } from './ThemePresets';

// presetId 合法范围上界（历史 5 套彩色预设的数量；预设色板已删除，仅保留 presetId 范围校验兜底）
const PRESET_ID_MAX = 5;

// AppStorage 状态键常量
const APPS_KEY_PRESET_ID = 'theme_preset_id';
const APPS_KEY_IS_DARK = 'theme_is_dark';
const APPS_KEY_MODE = 'theme_mode';
const APPS_KEY_TOKENS = 'theme_tokens';
const APPS_KEY_FROST_LEVEL = 'theme_frost_level';
// HUI-001 · T-BUG-005：高对比度（黑白重彩）开关键（与 entry SettingsPage 的 KEY_HIGH_CONTRAST 一致）
const APPS_KEY_HIGH_CONTRAST = 'app_high_contrast';

// PersistentStorage 持久化键
const PERSIST_KEY_PRESET_ID = 'persist_theme_preset_id';
const PERSIST_KEY_MODE = 'persist_theme_mode';
const PERSIST_KEY_FROST_LEVEL = 'persist_theme_frost_level';
const PERSIST_KEY_CUSTOM_THEME = 'persist_custom_theme';

/**
 * 主题管理器 — 单例模式
 * 职责：预设主题切换 / 自定义主题应用 / 深色模式切换 / 当前主题状态查询
 * 对齐架构 4.1 节主题系统 API 契约
 */
export class ThemeManager {
  private static instance: ThemeManager | null = null;

  /** 当前主题状态 */
  private currentState: ThemeState;

  /** 高对比度（黑白重彩）开关状态 —— T-BUG-005（HUI-001） */
  private highContrast: boolean = false;

  private constructor() {
    // HUI-021：全局黑白手绘主题 —— 启动即以「手绘黑白」浅色色板占位（不再用彩色预设作初值）。
    //   init() 会依据系统深浅色经 applyTokens() 复算为对应黑白色板；5 套彩色预设代码保留（已废弃）。
    this.currentState = {
      presetId: DEFAULT_PRESET_ID,
      mode: ThemeMode.FOLLOW_SYSTEM,
      isDark: false,
      tokens: getSketchMonoTokens(false),
      frostLevel: FrostedBlurLevel.MEDIUM
    };
  }

  /**
   * 获取单例实例
   */
  static getInstance(): ThemeManager {
    if (!ThemeManager.instance) {
      ThemeManager.instance = new ThemeManager();
    }
    return ThemeManager.instance;
  }

  /**
   * 初始化主题管理器
   * 从 PersistentStorage 恢复持久化的主题配置
   * 应在 AbilityStage.onCreate 或 MainAbility.onCreate 中调用
   */
  async init(): Promise<void> {
    try {
      // 从 AppStorage 恢复持久化状态
      const savedPresetId = AppStorage.get<number>(APPS_KEY_PRESET_ID);
      const savedMode = AppStorage.get<string>(APPS_KEY_MODE);
      const savedFrostLevel = AppStorage.get<number>(APPS_KEY_FROST_LEVEL);

      if (savedPresetId && savedPresetId >= 1 && savedPresetId <= PRESET_ID_MAX) {
        this.currentState.presetId = savedPresetId;
      }

      if (savedMode) {
        this.currentState.mode = savedMode as ThemeMode;
      }

      if (savedFrostLevel && savedFrostLevel >= 1 && savedFrostLevel <= 3) {
        this.currentState.frostLevel = savedFrostLevel as FrostedBlurLevel;
      }

      // T-BUG-005：恢复高对比度开关（冷启动若曾开启则沿用黑白重彩）
      const savedHighContrast = AppStorage.get<boolean>(APPS_KEY_HIGH_CONTRAST);
      if (savedHighContrast === true) {
        this.highContrast = true;
      }

      // 检测系统深色模式
      const systemDark = this.detectSystemDarkMode();
      this.currentState.isDark = (this.currentState.mode === ThemeMode.DARK) ||
        (this.currentState.mode === ThemeMode.FOLLOW_SYSTEM && systemDark);

      // 刷新色板
      this.applyTokens();

      // 同步到 AppStorage
      this.syncToAppStorage();
    } catch (err) {
      console.error('[ThemeManager] init failed:', JSON.stringify(err));
    }
  }

  /**
   * fix: DEV-011 · T-P01 —— 外观设置持久化恢复（深色模式三态 / 磨砂等级 / 高对比度）。
   * 🔴 调用时机铁律：必须在 UI 实例就绪后调用（EntryAbility.onWindowStageCreate 的 loadContent 回调内，
   *   紧跟 PersistentState.initialize 之后）。官方约束：PersistentStorage 和 UI 实例相关联，
   *   持久化操作需在 UI 实例初始化成功后（loadContent 回调被调用时）才可调用，早于该时机调用会导致持久化失败——
   *   这正是此前设置项"杀进程全回默认"的根因（persistProp 全部跑在 onCreate，静默失效）。
   * 🔴 防踩踏设计：持久键用独立 PERSIST_KEY_*（persist_theme_mode / persist_theme_frost_level），
   *   不复用 syncToAppStorage 的展示键 theme_mode / theme_frost_level——后者在 onCreate 的 init() 已被写入
   *   AppStorage，若对其 persistProp 会触发"内存值胜出覆盖磁盘值"铁律，磁盘持久值被默认值踩死。
   *   PERSIST_KEY_* 只有本方法（persistProp 恢复）与 setMode/setDarkMode/setFrostLevel（用户显式变更）两个写入方，
   *   persistProp 调用前必不存在于 AppStorage，磁盘值必胜。
   * 高对比度键 app_high_contrast 由 PersistentState.initialize persistProp（单一属主），此处仅回读应用。
   */
  restorePersisted(): void {
    try {
      PersistentStorage.persistProp(PERSIST_KEY_MODE, '');
      PersistentStorage.persistProp(PERSIST_KEY_FROST_LEVEL, 0);

      const savedMode = AppStorage.get<string>(PERSIST_KEY_MODE);
      if (savedMode) {
        // 仅接受合法枚举串（'light'/'dark'/'follow_system'）；'' 为首启哨兵值，跳过
        if (savedMode === ThemeMode.LIGHT.toString() || savedMode === ThemeMode.DARK.toString() ||
          savedMode === ThemeMode.FOLLOW_SYSTEM.toString()) {
          this.currentState.mode = savedMode as ThemeMode;
        }
      }

      const savedFrost = AppStorage.get<number>(PERSIST_KEY_FROST_LEVEL);
      if (savedFrost !== undefined && savedFrost >= 1 && savedFrost <= 3) {
        this.currentState.frostLevel = savedFrost as FrostedBlurLevel;
      }

      // 高对比度：persistProp（PersistentState.initialize 已先行接盘）恢复的磁盘值
      const savedHighContrast = AppStorage.get<boolean>(APPS_KEY_HIGH_CONTRAST);
      this.highContrast = savedHighContrast === true;

      // 依据恢复后的模式重算深浅态（FOLLOW_SYSTEM 取系统当前值；T-D02 detectSystemDarkMode 不动）
      this.currentState.isDark = (this.currentState.mode === ThemeMode.DARK) ||
        (this.currentState.mode === ThemeMode.FOLLOW_SYSTEM && this.detectSystemDarkMode());

      this.applyTokens();
      this.syncToAppStorage();
      this.emitThemeChanged();
    } catch (err) {
      console.error('[ThemeManager] restorePersisted failed:', JSON.stringify(err));
    }
  }

  /**
   * 切换深色模式（对齐架构 4.1 节 ThemeManager.setDarkMode API）
   * @param enabled 是否启用深色模式
   */
  async setDarkMode(enabled: boolean): Promise<void> {
    this.currentState.mode = enabled ? ThemeMode.DARK : ThemeMode.LIGHT;
    this.currentState.isDark = enabled;
    // fix: DEV-011 · T-P01 —— 用户显式切深/浅色落持久键（persistProp 已接盘则自动落盘）
    AppStorage.setOrCreate(PERSIST_KEY_MODE, this.currentState.mode.toString());
    this.applyTokens();
    this.syncToAppStorage();
    this.emitThemeChanged();
  }

  /**
   * 切换深色模式（一键反转当前状态，供首页深色切换图标调用）
   */
  async toggleDarkMode(): Promise<void> {
    await this.setDarkMode(!this.currentState.isDark);
  }

  /**
   * 设置主题模式（跟随系统 / 手动浅色 / 手动深色）
   * @param mode 主题模式
   */
  async setMode(mode: ThemeMode): Promise<void> {
    this.currentState.mode = mode;
    // fix: DEV-011 · T-P01 —— 深色模式三态（跟随系统/浅色/深色）落持久键，重启恢复用户选择
    AppStorage.setOrCreate(PERSIST_KEY_MODE, mode.toString());
    if (mode === ThemeMode.FOLLOW_SYSTEM) {
      this.currentState.isDark = this.detectSystemDarkMode();
    } else if (mode === ThemeMode.DARK) {
      this.currentState.isDark = true;
    } else {
      this.currentState.isDark = false;
    }
    this.applyTokens();
    this.syncToAppStorage();
    this.emitThemeChanged();
  }

  /**
   * 获取当前主题配置（对齐架构 4.1 节 ThemeManager.getCurrentTheme API）
   * @returns 当前主题状态
   */
  getCurrentTheme(): ThemeState {
    return this.currentState;
  }

  /**
   * 获取当前色板 Token
   * @returns 当前生效的色板
   */
  getTokens(): ThemeColorTokens {
    return this.currentState.tokens;
  }

  /**
   * 获取当前浅色/深色状态
   */
  isDarkMode(): boolean {
    return this.currentState.isDark;
  }

  /**
   * 获取当前预设ID
   */
  getPresetId(): number {
    return this.currentState.presetId;
  }

  /**
   * 设置毛玻璃等级
   * @param level 模糊等级 (1-3)
   */
  setFrostLevel(level: FrostedBlurLevel): void {
    this.currentState.frostLevel = level;
    // fix: DEV-011 · T-P01 —— 磨砂（沉浸强度）等级落持久键，重启恢复用户选择
    AppStorage.setOrCreate(PERSIST_KEY_FROST_LEVEL, level as number);
    this.syncToAppStorage();
  }

  /**
   * 获取毛玻璃等级
   */
  getFrostLevel(): FrostedBlurLevel {
    return this.currentState.frostLevel;
  }

  /**
   * 高对比度（黑白重彩）开关 —— T-BUG-005（HUI-001）
   * 开启：全局色板切为黑白最大对比；关闭：恢复当前预设色板。
   * 经 applyTokens + syncToAppStorage 写入 theme_tokens → 全 App 页面（@StorageLink）即时重着色。
   * @param enabled 是否开启高对比度
   */
  setHighContrast(enabled: boolean): void {
    this.highContrast = enabled;
    AppStorage.setOrCreate(APPS_KEY_HIGH_CONTRAST, enabled);
    this.applyTokens();
    this.syncToAppStorage();
    this.emitThemeChanged();
  }

  /**
   * 获取当前高对比度开关状态
   */
  isHighContrast(): boolean {
    return this.highContrast;
  }

  /**
   * 系统深色模式变更回调
   * 当用户在跟随系统模式下，系统切换深浅色时调用
   */
  onSystemDarkModeChange(isDark: boolean): void {
    if (this.currentState.mode === ThemeMode.FOLLOW_SYSTEM) {
      if (this.currentState.isDark !== isDark) {
        this.currentState.isDark = isDark;
        this.applyTokens();
        this.syncToAppStorage();
        this.emitThemeChanged();
      }
    }
  }

  // ─── 私有方法 ───

  /**
   * 应用当前色板 Token
   * HUI-021：全局黑白手绘主题 —— 默认统一走「手绘黑白」色板（深浅色各一套黑白）。
   *   · 高对比开关(T-BUG-005)仍走纯黑白高对比色板（无障碍）；二者皆黑白，保证全局黑白生效。
   *   · 5 套彩色预设(getPresetTokens/THEME_PRESETS)已废弃并删除，全局仅保留黑白色板。
   *   · 自定义主题(presetId===0)亦收敛为手绘黑白，保证「配色全局黑白」。
   */
  private applyTokens(): void {
    if (this.highContrast) {
      this.currentState.tokens = getHighContrastTokens(this.currentState.isDark);
      return;
    }
    this.currentState.tokens = getSketchMonoTokens(this.currentState.isDark);
  }

  /**
   * 同步当前状态到 AppStorage（触发 UI 自动刷新）
   */
  private syncToAppStorage(): void {
    AppStorage.setOrCreate(APPS_KEY_PRESET_ID, this.currentState.presetId);
    AppStorage.setOrCreate(APPS_KEY_IS_DARK, this.currentState.isDark);
    AppStorage.setOrCreate(APPS_KEY_MODE, this.currentState.mode);
    AppStorage.setOrCreate(APPS_KEY_TOKENS, this.currentState.tokens);
    AppStorage.setOrCreate(APPS_KEY_FROST_LEVEL, this.currentState.frostLevel);
  }

  /**
   * 发射主题变更事件（对齐架构 4.6 节 event:theme:changed）
   */
  private emitThemeChanged(): void {
    // ArkTS arkts-no-untyped-obj-literals: 空字面量 + 括号逐键赋值（唯一编译通过写法）
    const payload: Record<string, Object> = {};
    payload['presetId'] = this.currentState.presetId;
    payload['isDark'] = this.currentState.isDark;
    EventBus.emit(EventBus.EventNames.THEME_CHANGED, payload);
  }

  /**
   * 检测系统是否为深色模式
   * DEV-010 · T-D02：AppStorage['systemColorMode'] 保存 ConfigurationConstant.ColorMode 原始枚举值，
   *   由 EntryAbility 冷启动初读 + onConfigurationUpdate/onForeground 持续写入。
   *   系统枚举实证（@ohos.app.ability.ConfigurationConstant.d.ts L90/L112/L134）：
   *   COLOR_MODE_NOT_SET=-1 / COLOR_MODE_DARK=0 / COLOR_MODE_LIGHT=1。
   *   原代码 `colorMode === 1` 实为「浅色」判成深色（判反）；未写入(undefined)/NOT_SET/LIGHT 均视为浅色。
   */
  private detectSystemDarkMode(): boolean {
    try {
      const colorMode = AppStorage.get<number>('systemColorMode');
      return colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (err) {
      return false;
    }
  }
}

/**
 * 主题管理器便捷访问函数
 */
export function getThemeManager(): ThemeManager {
  return ThemeManager.getInstance();
}
