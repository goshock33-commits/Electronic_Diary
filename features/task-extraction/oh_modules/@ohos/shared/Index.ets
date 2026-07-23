// <!-- agentID: DEV-002 -->
// fix: HUI-FRONTEND
// fix: DEV-012（T-M01 一天多篇：补导出 DiaryEntryPayload 载荷 v2 条目类型）
// agentID: HUI-041（T-D05：导出 ICON 图标尺寸令牌）
// 文件: shared/Index.ets
// 任务: T001 shared HAR 模块入口
// 关联架构: ARC-001 架构方案 §3.2 shared 模块

// ========== 数据模型 ==========
export { Diary } from './src/main/ets/data/Diary';
export { CheckIn } from './src/main/ets/data/CheckIn';
export { TodoItem } from './src/main/ets/data/TodoItem';
export { HappyThing } from './src/main/ets/data/HappyThing';
export { ExtraThing } from './src/main/ets/data/ExtraThing';
export { ExtractedTask } from './src/main/ets/data/ExtractedTask';
export { Quote } from './src/main/ets/data/Quote';
export { PomodoroSession } from './src/main/ets/data/PomodoroSession';
export { AppSettings } from './src/main/ets/data/AppSettings';
export { Account } from './src/main/ets/data/Account';
// agentID: DEV-004 — 统计曲线图逐日计数结构（DiaryDao/TodoDao 范围聚合返回类型）
export { type DailyCount } from './src/main/ets/data/DailyCount';
// DEV-FAMILY — 家庭成员实体（family_member 表，FamilyMemberDao 返回类型）
export { FamilyMember } from './src/main/ets/data/FamilyMember';

// ========== 数据库层 ==========
export { DatabaseHelper } from './src/main/ets/database/DatabaseHelper';
export { DatabaseExecutor } from './src/main/ets/database/DatabaseExecutor';

// ========== DAO ==========
export { DiaryDao } from './src/main/ets/database/dao/DiaryDao';
export { CheckInDao } from './src/main/ets/database/dao/CheckInDao';
export { TodoDao } from './src/main/ets/database/dao/TodoDao';
export { HappyThingDao } from './src/main/ets/database/dao/HappyThingDao';
export { ExtraThingDao } from './src/main/ets/database/dao/ExtraThingDao';
export { ExtractedTaskDao } from './src/main/ets/database/dao/ExtractedTaskDao';
export { QuoteDao } from './src/main/ets/database/dao/QuoteDao';
export { PomodoroDao } from './src/main/ets/database/dao/PomodoroDao';
export { AppSettingsDao } from './src/main/ets/database/dao/AppSettingsDao';
export { SectionConfigDao, type SectionConfig } from './src/main/ets/database/dao/SectionConfigDao';
// DEV-FAMILY — 家庭成员 DAO（insert/update/delete/queryAll/findByNickname）
export { FamilyMemberDao } from './src/main/ets/database/dao/FamilyMemberDao';
// DEV+HUI — 登录态 Account DAO（getLoggedInAccount/saveLoginAccount/logout/isLoggedIn/getLoggedInUid）
export { AccountDao } from './src/main/ets/database/dao/AccountDao';

// ========== 状态管理 ==========
export { AppState } from './src/main/ets/state/AppState';
export { PersistentState } from './src/main/ets/state/PersistentState';

// ========== 工具类 ==========
export { EncryptionUtils } from './src/main/ets/utils/EncryptionUtils';
// fix: DEV-013 · T-B01 备份含照片：BackupContent（表 JSON + 图片字节）随引擎升级导出
export { BackupUtils, type BackupFileInfo, type BackupContent, type BackupMeta } from './src/main/ets/utils/BackupUtils';
export { NotificationUtils } from './src/main/ets/utils/NotificationUtils';
export { ImageUtils } from './src/main/ets/utils/ImageUtils';
export { CameraUtils } from './src/main/ets/utils/CameraUtils';
export { ClipboardUtils } from './src/main/ets/utils/ClipboardUtils';
export { SensorUtils, ShakeSensitivity } from './src/main/ets/utils/SensorUtils';
export { ShareUtils } from './src/main/ets/utils/ShareUtils';
// fix: HUI-FRONTEND-1 — 恢复 origin/main 的 M14 碰传载荷引擎（DiaryViewModel 依赖）
export { KnockShareService, type BackupExportResult, type BackupImportResult, type DiaryBundle, type DiaryEntryPayload } from './src/main/ets/utils/KnockShareService';
// fix: DEV-014 · T-B02 碰一碰真实传输通道（Share Kit harmonyShare 发送/接收 + NFC 状态）
export { KnockTransferService, type NfcStateLabel, type KnockSendResultCallback, type KnockReceiveFilesCallback, type KnockTriggeredCallback, type KnockFailCallback } from './src/main/ets/utils/KnockTransferService';
export { EventBus, type EventCallback } from './src/main/ets/utils/EventBus';
export { DiaryReminderManager, type DiaryReminderConfig } from './src/main/ets/utils/DiaryReminderManager';
// fix: HUI-FRONTEND — F11：铃声试听工具（AVPlayer + rawfile 5 段 WAV，与真实提醒同映射）
export { RingtonePlayUtils, type RingtoneMeta } from './src/main/ets/utils/RingtonePlayUtils';
// fix: HUI-FRONTEND-2 — M17 提醒调度服务（恢复自 origin/main：reminderAgentManager 真实调度 + 通知权限）
export { ReminderAgentService } from './src/main/ets/utils/ReminderAgentService';
// 鸿蒙DEV — TTS 语音播报单例服务（@kit.CoreSpeechKit textToSpeech：init/enqueue/interrupt/stopAll/shutdown）
export { TtsService } from './src/main/ets/utils/TtsService';
// DEV-D2 — ASR↔TTS 互斥焦点状态机（speaking 不启 ASR / listening 强停 TTS，EventBus 同步）
export { VoiceFocusManager, VoiceFocusState } from './src/main/ets/utils/VoiceFocusManager';
// DEV-FAMILY — 家庭成员业务层单例（包装 FamilyMemberDao，Result<T> 统一返回，不外抛异常）
export { FamilyManager, Result, type CreateFamilyResult, type JoinFamilyResult } from './src/main/ets/utils/FamilyManager';
// DEV+HUI — 登录态管理单例（AGC Auth 云函数认证 + AccountDao 落库，Result<T> 统一返回）
export { AccountManager } from './src/main/ets/utils/AccountManager';

// 日记封面解析（DEV-001）：上传图优先，否则按稳定 id 取 19 张内置封面（rawfile/covers/）
export { resolveDiaryCover, BUILTIN_COVER_COUNT } from './src/main/ets/utils/DiaryCoverResolver';

// ========== AppStartup ==========
export { StartupConfig } from './src/main/ets/startup/StartupConfig';
export { StartupTasks } from './src/main/ets/startup/StartupTasks';

// ========== 无障碍 ==========
// AccessibilityConfig 已删除（HUI-031 死代码清理：全项目零引用、导出早已注释）。

// ========== 主题系统（HUI-001） ==========
export { ThemeManager, getThemeManager } from './src/main/ets/theme/ThemeManager';
export { ThemeMode, FrostedBlurLevel, type ThemeState, type ThemeChangedEvent, type CustomThemeConfig, type ThemeColorTokens, type FrostedBlurPack, type ThemePreset, type TabItemConfig } from './src/main/ets/theme/ThemeConfig';

export { DEFAULT_PRESET_ID, getHighContrastTokens } from './src/main/ets/theme/ThemePresets';

export { FrostedGlassUtils } from './src/main/ets/theme/FrostedGlassUtils';

// 系统选择弹窗主题换肤（HUI-042 · T-D07）：DatePicker/TextPicker 等系统弹窗读 theme_tokens 统一换肤
export { PickerDialogTheme } from './src/main/ets/theme/PickerDialogTheme';

// ========== 设计令牌（HUI-047 · P0）：圆角/间距/排版 ==========
export { RADIUS, SPACING, ICON, type RadiusTokens, type SpacingTokens, type IconSizeTokens } from './src/main/ets/theme/LayoutTokens';

export { TYPO, type TypoStyle, type TypoTokens } from './src/main/ets/theme/TypographyTokens';

// ========== 字体族预设（HUI-049 · P0-07）：JetBrains Mono 等宽字体族名 ==========
export { FONT, type FontFamilyPresets } from './src/main/ets/theme/FontPresets';

// ========== 集中手绘字体助手（HUI-025）：AttributeModifier<TextAttribute> 一行套手绘字体 ==========
export {
  SketchTitleModifier, SketchBodyModifier,
  SketchH1Modifier, SketchSectionTitleModifier, SketchCardTitleModifier,
  SketchBodyTypoModifier, SketchEyebrowModifier,
  SKETCH_TITLE, SKETCH_BODY,
  SKETCH_H1, SKETCH_SECTION_TITLE, SKETCH_CARD_TITLE, SKETCH_BODY_TYPO, SKETCH_EYEBROW
} from './src/main/ets/theme/SketchTextModifiers';

// ========== 工具类（HUI-001） ==========
export { IconMapper } from './src/main/ets/utils/IconMapper';
export { DateUtils } from './src/main/ets/utils/DateUtils';

// ========== 通用 UI 组件（HUI-001 · T009） ==========
export { FloatingTabBar, type FloatingTabBarConfig } from './src/main/ets/components/FloatingTabBar';

export { FrostedNavigationBar, type NavAction } from './src/main/ets/components/FrostedNavigationBar';

export { FrostedDialog, type FrostedDialogConfig } from './src/main/ets/components/FrostedDialog';

export { ElasticButton, ElasticButtonStyle } from './src/main/ets/components/ElasticButton';

export { LoadingView, LoadingStyle } from './src/main/ets/components/LoadingView';

export { EmptyStateView } from './src/main/ets/components/EmptyStateView';

// 主题化日期选择弹窗（HUI-042 · T-D07 三轮）：系统 DatePickerDialog 顶部标题区不可换肤 → 自绘替代
export { ThemedDatePickerModal } from './src/main/ets/components/ThemedDatePickerModal';

// 主题化时间选择弹窗（HUI-078）：时:分滚轮，与 ThemedDatePickerModal 成对（AddTodoDialog 提醒双选择器用）
export { ThemedTimePickerModal } from './src/main/ets/components/ThemedTimePickerModal';

// ========== Lottie 动画组件（HUI-017 · T-LT02） ==========
export { LottieAnimation } from './src/main/ets/components/LottieAnimation';

// ========== 全局猫爪点击特效（HUI-001 · 纯页面树内：捕获 reportPawTouch + 视觉 PawOverlayLayer 同树子层） ==========
export {
  PawOverlayLayer, reportPawTouch
} from './src/main/ets/components/PawClickEffect';

// ========== 手绘图标系统（HUI-016 · 批次1 T007：从 features/statistics 迁入 shared，解耦供 FloatingTabBar 等 shared 级组件复用） ==========
export { SketchIcon, SketchIconType } from './src/main/ets/components/sketch/SketchIcon';
export {
  getStrokeColor, getFillColor, getSecondaryColor, getBorderStyle,
  SKETCH_BORDER_PRIMARY, SKETCH_BORDER_SECONDARY, SKETCH_BORDER_TERTIARY,
  type SketchBorderStyle
} from './src/main/ets/components/sketch/SketchThemeAdapter';
export {
  wb, wobbleArc, wobbleRect, wobbleLine, wobbleRoundRect, scaleWobbleAmp
} from './src/main/ets/components/sketch/SketchCanvasUtils';

// ========== AI 网络层全局契约（DEV-004 · T101：DeepSeek OpenAI 兼容协议，落地后冻结） ==========
export {
  DS_MAX_TOOL_ROUNDS,
  DSErrorKind,
  type DSRole,
  type DSMessage,
  type DSToolCall,
  type DSFunctionCall,
  type DSTool,
  type DSFunctionDef,
  type DSJsonSchema,
  type DSSchemaProp,
  type DSStreamChunk,
  type DSStreamChoice,
  type DSDelta,
  type DSStreamToolCall,
  type DSStreamFunctionCall,
  type DSChatRequest,
  type DSChatResponse,
  type DSChoice,
  type DSUsage,
  type DSChatResult,
  type ToolExecResult,
  type SessionCallbacks
} from './src/main/ets/network/DeepSeekTypes';

// ========== AI 网络层实现（DEV-004 · T103：HttpClient.postJson + DeepSeekClient 非流式；postStream 留 T301） ==========
export { HttpClient, type HttpTextResponse } from './src/main/ets/network/HttpClient';
// 【F1】MODEL_ID/BASE_URL/PATH_* 集中常量：全工程唯一定义点在 DeepSeekClient.ets 顶部
// HUI-001：DSChatOptions —— chat 可选生成参数（ghost text 内联补全 max_tokens/temperature）
export { DeepSeekClient, MODEL_ID, BASE_URL, PATH_CHAT, PATH_MODELS, type DSChatOptions } from './src/main/ets/network/DeepSeekClient';

// ========== 云数据库服务（AGC Cloud DB SDK 封装） ==========
export { CloudDbService, CloudAccount, CloudFamily, CloudFamilyMember, VoiceReminder } from './src/main/ets/cloud/CloudDbService';
// T307 跨设备语音提醒发送端 + push token 上报维护（DEV-VOICE-REMIND）
export { VoiceReminderSender, VoiceReminderStatus, type VoiceReminderSendOptions } from './src/main/ets/cloud/VoiceReminderSender';
