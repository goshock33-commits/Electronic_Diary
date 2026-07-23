// <!-- agentID: DEV-001 -->
// fix: DEV+HUI —— 四期 Auth 改密码方案：@hw-agconnect/auth SDK 全链路已删（auth.init /
//   rawfile 读 agconnect-services.json / oh-package 依赖）。注册登录改走 Cloud DB Account 表
//   （AccountManager.register/login，CloudDbService 内部 zone 按需打开），本文件无需任何 Auth 初始化。
// fix: DEV-014 · T-B02 收备份兜底链路：handleKnockWant（冷/热启动解析 .ediary.zip 文件 URI → 自动导入）
// fix: HUI-FRONTEND
// fix: HUI-T105 —— 长辈模式「点通知拉起 + TTS 复述」接收侧：onCreate/onNewWant 解析 want.parameters
//   （elder_tts_text 直取 / todoId 回查 todo 表拼文案）→ AppStorage(elder_tts_text + elder_tts_seq 自增)
//   → ElderHomeView @Watch 消费 TtsService.enqueue 复述；persist_elder_mode=1 时通知路由一律收敛到
//   pages/ElderModePage（栈顶已是则跳过，不重复压栈）。发布侧 wantAgent.parameters 由提醒调度方接线。
// fix: DEV-011 —— T-P01 设置项持久化端到端修复：PersistentState.initialize（全部 persistProp）移入
//   onWindowStageCreate 的 loadContent 回调。根因：PersistentStorage 和 UI 实例相关联，persistProp
//   早于 loadContent 回调（此前跑在 onCreate 的 StartupTasks P0）会静默持久化失败 → 除落 DB 的
//   提醒设置外，全部设置杀进程即回默认。回调内随后调 ThemeManager.restorePersisted() 恢复
//   深色模式三态/磨砂/高对比并重算色板。T-D02 systemColorMode 链路原样保留。
// agentID: DEV-010 —— T-D02 跟随系统深色链路修通（systemColorMode 冷启动初读 + onConfigurationUpdate 运行时监听）
// File: EntryAbility.ets
// Task: T040 AppStartup integration - HiTrace startup profiling
// Architecture: ARC-001 3.6 AppStartup
// Skill Ref: frontend-design / ui-ux-pro-max

import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { StartupTasks, ShareUtils, FONT, getThemeManager, ReminderAgentService, NotificationUtils, PersistentState, TodoDao, TodoItem, VoiceReminderSender, KnockShareService, EventBus } from '@ohos/shared';
import type { BackupImportResult } from '@ohos/shared';
import { LiveViewManager } from '../utils/LiveViewManager';
import { DiaryReminderManager } from '@ohos/shared';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

// HUI-T105: 长辈模式「点通知拉起 + TTS 复述」——want.parameters 约定键（PLN-001_family_plan T105 /
//   JUDGE_review_family_arch F1：onNewWant 携带 todoId → 路由 ElderHome → 立即播报全文）。
//   发布侧（Todo 代理提醒 wantAgent.parameters / 家人 Push want.parameters）二选一携带：
//   · elder_tts_text: string —— 直接播报全文（优先；Push 场景可带称呼文案）
//   · todoId: number|string —— 待办 id，从 todo 表回查拼文案（已完成/已删除的待办查不到即不复述）
const WANT_KEY_ELDER_TTS_TEXT = 'elder_tts_text';
const WANT_KEY_ELDER_TODO_ID = 'todoId';
// HUI-T105: 复述载荷 AppStorage 键——文本 + 自增序号（ElderHomeView @StorageLink('elder_tts_seq')
//   @Watch 消费；消费标记 elder_tts_consumed_seq 由消费侧维护，防组件重建重播）。
const STORAGE_KEY_ELDER_TTS_TEXT = 'elder_tts_text';
const STORAGE_KEY_ELDER_TTS_SEQ = 'elder_tts_seq';
// HUI-T105: 长辈模式页路由 URL（与 MainPage onPageShow 的 persist_elder_mode 重定向同一目标）。
const ELDER_PAGE_URL = 'pages/ElderModePage';
// HUI-T105: todoId 回查窗口——通知点击可能晚于到点较久，回看 24h 内未完成的提醒待办。
const ELDER_TODO_LOOKBACK_MS = 24 * 60 * 60 * 1000;
// DEV-VOICE-REMIND · T308 配套：家人语音提醒 Push 点击 want.parameters 约定键——
//   voice_push 云函数 clickAction data 携带 voice_reminder_id（已读回写）+ elder_tts_text（复用
//   HUI-T105 播报链路，老人模式直接开口）。本键仅做 status=read 回写，播报由 elder_tts_text 走既有路径。
const WANT_KEY_VOICE_REMINDER_ID = 'voice_reminder_id';

export default class EntryAbility extends UIAbility {
  // F7: 提醒通知点击路由——DiaryReminderManager wantAgent.parameters 带 router_target，
  //   冷启动 onCreate / 热启动 onNewWant 解析暂存，窗口就绪后 pushUrl 跳「写日记页」
  private pendingRouteTarget: string = '';
  private mainWindowStage: window.WindowStage | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');

    // fix: DEV+HUI —— 四期密码方案：原三期 AGC Auth SDK 初始化块（rawfile 读 agconnect-services.json
    //   → auth.init）已整体删除。注册/登录走 Cloud DB（AccountManager 内部 ensureZoneOpened 按需开 zone），
    //   无需任何 Auth SDK 前置初始化。

    // DEV-010 · T-D02：跟随系统深色链路 —— 冷启动初读系统深浅色。
    //   全项目此前无任何位置写入 AppStorage['systemColorMode']，ThemeManager.detectSystemDarkMode()
    //   永远读到 undefined → 「跟随系统」恒判浅色。此处必须在 getThemeManager().init() 之前写入，
    //   保证 init() 内 detectSystemDarkMode() 读到的即是当前系统深浅色（冷启动首帧即正确色板）。
    //   取值源：UIAbilityContext.config.colorMode（application/UIAbilityContext.d.ts L150，
    //   Configuration.colorMode: ConfigurationConstant.ColorMode，DARK=0 / LIGHT=1 / NOT_SET=-1）。
    this.syncSystemColorMode(this.context.config.colorMode);

    // HUI-021：全局黑白手绘主题 —— 冷启动即初始化 ThemeManager。
    //   init() 体内无 await（虽声明 async），在 onWindowStageCreate/loadContent 之前同步把
    //   「手绘黑白」色板写入 AppStorage['theme_tokens']，使首帧前全 App @StorageLink 页面即为黑白。
    //   （此前无任何位置调用 init()，theme_tokens 冷启动为空，各页只能用自身硬编码 fallback。）
    getThemeManager().init().catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'HUI-021: theme init failed: %{public}s', err.message);
    });

    // AppStartup: Execute startup tasks
    // P0 sync tasks (database init) complete before first frame
    // P1 async tasks (theme restore, notification channels) run in background
    // P2 idle tasks (quote preload, stats cache) deferred after first frame
    StartupTasks.executeAll(this.context).then(() => {
      hilog.info(DOMAIN, TAG, 'AppStartup: all tasks completed');
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'AppStartup: tasks failed: %{public}s', err.message);
    });

    // T035: Initialize LiveView and DiaryReminder systems
    LiveViewManager.initialize(this.context);
    DiaryReminderManager.initialize(this.context);
    // fix: HUI-FRONTEND-2 · M17 冷启动重调度每日提醒（恢复队友 DEV-005 方案）。
    //   真相源 = app_settings（SettingsViewModel 落库的开关/时间/方式/铃声），等 StartupTasks P0
    //   InitDatabase 完成后经 ReminderAgentService 重发后台代理提醒，保证 App 重启后系统提醒仍在。
    //   替换旧的 DiaryReminderManager Timer 恢复（只响一次+独立 prefs 时间漂移），避免双重调度。
    StartupTasks.executeAll(this.context).then(() => {
      return ReminderAgentService.rescheduleFromSettings();
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'M17: reschedule daily reminder failed: %{public}s', err.message);
    });
    // fix: HUI-FRONTEND-2 · M17 首次冷启动申请通知权限——未授权时 publishReminder 抛 1700001 静默失败，
    //   提醒开了也不响。requestPermission 内部已捕获拒绝（返回 false），此处仅记录。
    NotificationUtils.requestPermission(this.context).then((granted: boolean) => {
      if (!granted) {
        hilog.warn(DOMAIN, TAG, 'M17: notification permission denied — daily reminder will be silent');
      }
    });

    // T032: Handle share launch (cold start from external share)
    const shareText = ShareUtils.isShareLaunch(want);
    if (shareText) {
      hilog.info(DOMAIN, TAG, 'App launched via share, textLen=%{public}d', shareText.length);
      AppStorage.setOrCreate('pendingShareText', shareText);
      AppStorage.setOrCreate('pendingShareSource', want.bundleName ?? 'unknown');
    }

    // F7: 冷启动解析提醒通知携带的路由目标（窗口尚未就绪，先暂存，onWindowStageCreate 后消费）
    this.parseRouteTarget(want);
    // HUI-T105: 冷启动解析长辈模式复述载荷（写 AppStorage，ElderHomeView aboutToAppear 消费；
    //   长辈模式路由由 MainPage onPageShow 重定向 + flushPendingRoute 收敛兜底，此处不判模式——
    //   persist_elder_mode 此刻尚未经 loadContent 回调恢复，读不可靠）
    this.parseElderTtsWant(want);
    // DEV-VOICE-REMIND · T308 配套：家人语音提醒通知点击（冷启动）——已读回写
    this.parseVoiceReminderWant(want);
    // fix: DEV-014 · T-B02 收备份兜底链路（冷启动）：系统分享/文件打开携带 .ediary.zip → 自动导入
    this.handleKnockWant(want);
    // 桌面相机卡片快速拍照（冷启动）：diary://camera → AppStorage 通知 MainPage 跳 QuickCameraPage
    this.parseCameraQuickMode(want);

    // DEV-VOICE-REMIND · T307：云同步初始化（挂 StartupTasks 之后——token/成员上报要查本地库）：
    //   开 Cloud DB zone + 订阅 tokenUpdate + 登录态恢复后上报 push token（写 Account/FamilyMember 云表）。
    //   全链路内部降级（未登录/未配 AGC/断网仅日志），不影响本机功能。
    StartupTasks.executeAll(this.context).then(() => {
      return VoiceReminderSender.getInstance().initialize(this);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'T307: cloud sync init failed: %{public}s', err.message);
    });
  }

  // F7: 热启动（应用存活时点提醒通知）——解析路由目标并立即跳转
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onNewWant');
    this.parseRouteTarget(want);
    // HUI-T105: 解析长辈模式复述载荷（elder_tts_text 直取 / todoId 回查，经 AppStorage 送达 ElderHomeView）
    const hasElderPayload: boolean = this.parseElderTtsWant(want);
    // DEV-VOICE-REMIND · T308 配套：家人语音提醒通知点击（热启动）——已读回写
    this.parseVoiceReminderWant(want);
    // fix: DEV-014 · T-B02 收备份兜底链路（热启动）：系统分享/文件打开携带 .ediary.zip → 自动导入
    this.handleKnockWant(want);
    // 桌面相机卡片快速拍照（热启动）
    this.parseCameraQuickMode(want);
    // HUI-T105: 长辈模式下点通知须回长辈模式页——载荷命中且无其它路由目标时补路由目标
    //   （热启动时 persist_elder_mode 已由 loadContent 回调恢复，读取可靠；普通模式不受影响）
    if (hasElderPayload && this.pendingRouteTarget.length === 0
      && AppStorage.get<number>(PersistentState.KEY_ELDER_MODE) === 1) {
      this.pendingRouteTarget = ELDER_PAGE_URL;
    }
    this.flushPendingRoute();
  }

  // DEV-VOICE-REMIND · T308 配套：want.parameters 携带 voice_reminder_id（家人提醒 Push 点击）时，
  //   回写云表 status=read（发送端可见流转）。fire-and-forget：云端失败仅日志，不阻塞启动/路由。
  //   播报文本不在此处理——云函数 clickAction data 同时携带 elder_tts_text，由 parseElderTtsWant 既有链路消费。
  private parseVoiceReminderWant(want: Want): void {
    try {
      const params = want.parameters;
      if (params === undefined) {
        return;
      }
      const rawId = params[WANT_KEY_VOICE_REMINDER_ID];
      if (typeof rawId !== 'string' || rawId.length === 0) {
        return;
      }
      hilog.info(DOMAIN, TAG, 'T308: voice reminder clicked, id=%{public}s', rawId);
      StartupTasks.executeAll(this.context).then(() => {
        return VoiceReminderSender.getInstance().markAsRead(rawId);
      }).then(() => {
        hilog.info(DOMAIN, TAG, 'T308: voice reminder marked read: %{public}s', rawId);
      }).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'T308: markAsRead failed: %{public}s', err.message);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'T308: parseVoiceReminderWant failed: %{public}s', JSON.stringify(err));
    }
  }

  // fix: DEV-014 · T-B02 收备份兜底链路：解析 want 携带的备份文件 URI 并自动导入。
  //   来源：① 华为分享/系统分享把 .ediary.zip 发到本机后用本 App 打开（ohos.want.action.viewData，
  //   文件 URI 在 want.uri）；② 应用内约定键 shareFileUri；③ 系统分享流键 ability.params.stream。
  //   命中 .ediary.zip 即经 KnockShareService.importBackupFromUri（DEV-013 签名勿动）表恢复 + 照片重建，
  //   结果写 AppStorage(shareImport*) 并 emit BACKUP_COMPLETED（§8.3① Record 括号逐键赋值）。
  private handleKnockWant(want: Want): void {
    try {
      let uri: string = '';
      if (typeof want.uri === 'string' && want.uri.length > 0) {
        uri = want.uri;
      }
      const params = want.parameters;
      if (uri.length === 0 && params !== undefined) {
        const conv = params['shareFileUri'];
        if (typeof conv === 'string' && conv.length > 0) {
          uri = conv;
        }
        if (uri.length === 0) {
          const stream = params['ability.params.stream'];
          if (typeof stream === 'string' && stream.length > 0) {
            uri = stream;
          } else if (Array.isArray(stream) && stream.length > 0 && typeof stream[0] === 'string') {
            uri = stream[0] as string;
          }
        }
      }
      if (uri.length === 0 || uri.indexOf('.ediary.zip') < 0) {
        return;
      }
      hilog.info(DOMAIN, TAG, 'DEV-014: knock/share backup uri detected, importing');
      const importUri: string = uri;
      // 等 StartupTasks P0（数据库初始化）完成后再导入（executeAll 幂等合流，同 onCreate 既有模式）
      StartupTasks.executeAll(this.context).then(() => {
        return KnockShareService.importBackupFromUri(this.context.filesDir, importUri);
      }).then((result: BackupImportResult | null) => {
        if (result === null) {
          hilog.error(DOMAIN, TAG, 'DEV-014: backup import failed (parse/restore)');
          AppStorage.setOrCreate('shareTransferNote', '收到的备份包解析或恢复失败');
          return;
        }
        AppStorage.setOrCreate('shareImportRowCount', result.rowCount);
        AppStorage.setOrCreate('shareImportImageCount', result.imageCount);
        AppStorage.setOrCreate('shareImportTableCount', result.tableCount);
        AppStorage.setOrCreate('shareTransferNote', '备份恢复完成：' + result.tableCount + ' 表 · '
          + result.rowCount + ' 行 · ' + result.imageCount + ' 图');
        const payload: Record<string, Object> = {};
        payload['stage'] = 'done';
        payload['scenario'] = 'receive';
        payload['rowCount'] = result.rowCount;
        payload['imageCount'] = result.imageCount;
        EventBus.emit(EventBus.EventNames.BACKUP_COMPLETED, payload);
        hilog.info(DOMAIN, TAG, 'DEV-014: backup imported ok, rows=%{public}d images=%{public}d',
          result.rowCount, result.imageCount);
      }).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'DEV-014: handleKnockWant import error: %{public}s', err.message);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'DEV-014: handleKnockWant failed: %{public}s', JSON.stringify(err));
    }
  }

  // 桌面相机卡片快速拍照：检测 want.uri === 'diary://camera' → 设 AppStorage 通知 MainPage
  // MainPage aboutToAppear/onPageShow 监听 camera_quick_mode → router.pushUrl QuickCameraPage
  private parseCameraQuickMode(want: Want): void {
    try {
      if (typeof want.uri === 'string' && want.uri === 'diary://camera') {
        hilog.info(DOMAIN, TAG, 'Quick camera mode detected from want.uri');
        AppStorage.setOrCreate('camera_quick_mode', true);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'parseCameraQuickMode failed: %{public}s', JSON.stringify(err));
    }
  }

  // F7: 从 want.parameters 提取 router_target（DiaryReminderManager 提醒 wantAgent 约定键）
  private parseRouteTarget(want: Want): void {
    try {
      const params = want.parameters;
      if (params !== undefined) {
        const target = params['router_target'];
        if (typeof target === 'string' && target.length > 0) {
          this.pendingRouteTarget = target;
        }
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'F7: parseRouteTarget failed: %{public}s', JSON.stringify(err));
    }
  }

  // F7: 窗口就绪后消费暂存路由（冷启动 loadContent 完成 / 热启动 onNewWant 直接调）
  private flushPendingRoute(): void {
    if (this.pendingRouteTarget.length === 0 || this.mainWindowStage === null) {
      return;
    }
    let target: string = this.pendingRouteTarget;
    this.pendingRouteTarget = '';
    // HUI-T105: 长辈模式路由收敛——persist_elder_mode=1 时任何通知路由目标一律改投长辈模式页
    //   （防冷启动 F7 router_target=DiaryEditPage 压在长辈页上破坏适老锁定；本方法两个调用点
    //   均晚于 loadContent 回调内 PersistentState.initialize，此处读持久键可靠）。
    const elderOn: number | undefined = AppStorage.get<number>(PersistentState.KEY_ELDER_MODE);
    if (elderOn === 1) {
      target = ELDER_PAGE_URL;
    }
    try {
      const uiRouter = this.mainWindowStage.getMainWindowSync().getUIContext().getRouter();
      // HUI-T105: 栈顶已是目标页则不重复压栈（长辈页常驻栈顶时热启动点通知的常态路径）
      const state = uiRouter.getState();
      if (state.path + state.name === target) {
        hilog.info(DOMAIN, TAG, 'HUI-T105: already on %{public}s, skip push', target);
        return;
      }
      uiRouter.pushUrl({ url: target });
      hilog.info(DOMAIN, TAG, 'F7: routed to %{public}s from reminder click', target);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'F7: flushPendingRoute failed: %{public}s', JSON.stringify(err));
    }
  }

  // HUI-T105: 解析 want 中的长辈模式复述载荷。返回是否命中（同步判定；todoId 路径异步回查后再发布）。
  //   载荷经 AppStorage（elder_tts_text + elder_tts_seq 自增）送达 ElderHomeView（@Watch/aboutToAppear
  //   消费）。普通模式下载荷照常写入，但无 ElderHomeView 挂载即无人消费，零副作用。
  private parseElderTtsWant(want: Want): boolean {
    try {
      const params = want.parameters;
      if (params === undefined) {
        return false;
      }
      const direct = params[WANT_KEY_ELDER_TTS_TEXT];
      if (typeof direct === 'string' && direct.length > 0) {
        this.publishElderTts(direct);
        return true;
      }
      const rawId = params[WANT_KEY_ELDER_TODO_ID];
      let todoId: number = -1;
      if (typeof rawId === 'number' && !isNaN(rawId)) {
        todoId = Math.floor(rawId);
      } else if (typeof rawId === 'string' && rawId.length > 0) {
        const parsed: number = parseInt(rawId, 10);
        if (!isNaN(parsed)) {
          todoId = parsed;
        }
      }
      if (todoId < 0) {
        return false;
      }
      this.resolveTodoTts(todoId);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'HUI-T105: parseElderTtsWant failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  // HUI-T105: todoId → todo 表回查拼播报文案（口径对齐 ReminderAgentService.buildTtsText：
  //   「待办提醒：{标题}（，地点：{地点}）」）。冷启动挂在 StartupTasks（P0 InitDatabase）之后查库
  //   （executeAll 幂等合流，onCreate 已有两处复用同一模式）；查不到（已完成/已删除）即不复述。
  private resolveTodoTts(todoId: number): void {
    StartupTasks.executeAll(this.context).then(() => {
      const floorMs: number = Date.now() - ELDER_TODO_LOOKBACK_MS;
      return TodoDao.queryPendingReminders(floorMs);
    }).then((items: TodoItem[]) => {
      for (let i = 0; i < items.length; i++) {
        const todo: TodoItem = items[i];
        if (todo.id !== todoId) {
          continue;
        }
        const title: string = todo.title.length > 0 ? todo.title : '该处理这条待办了';
        let text: string = `待办提醒：${title}`;
        if (todo.location !== null && todo.location.length > 0) {
          text = `${text}，地点：${todo.location}`;
        }
        this.publishElderTts(text);
        return;
      }
      hilog.warn(DOMAIN, TAG, 'HUI-T105: todoId=%{public}d not found/completed, skip respeak', todoId);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'HUI-T105: resolveTodoTts failed: %{public}s', err.message);
    });
  }

  // HUI-T105: 发布复述载荷——文本先写、序号后自增写（消费侧以序号为触发信号，读文本时必已就位）。
  private publishElderTts(text: string): void {
    const prevSeq: number | undefined = AppStorage.get<number>(STORAGE_KEY_ELDER_TTS_SEQ);
    const seq: number = (prevSeq !== undefined ? prevSeq : 0) + 1;
    AppStorage.setOrCreate(STORAGE_KEY_ELDER_TTS_TEXT, text);
    AppStorage.setOrCreate(STORAGE_KEY_ELDER_TTS_SEQ, seq);
    hilog.info(DOMAIN, TAG, 'HUI-T105: elder tts payload published seq=%{public}d len=%{public}d',
      seq, text.length);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  // DEV-010 · T-D02：运行中系统深浅色切换监听（无需重启 App 即时生效）。
  //   API 依据：UIAbility extends Ability（@ohos.app.ability.UIAbility.d.ts L276），
  //   Ability.onConfigurationUpdate(newConfig: Configuration)（@ohos.app.ability.Ability.d.ts L54）。
  //   前置条件：onCreate 已 setColorMode(COLOR_MODE_NOT_SET)（跟随系统），系统切深浅色时本回调被触发。
  //   链路：newConfig.colorMode → AppStorage['systemColorMode'] → ThemeManager.onSystemDarkModeChange()
  //   → applyTokens + syncToAppStorage('theme_tokens') → 全 App @StorageLink/@Watch 页面即时重渲染。
  onConfigurationUpdate(newConfig: Configuration): void {
    this.syncSystemColorMode(newConfig.colorMode);
  }

  // DEV-010 · T-D02：系统深浅色统一同步入口（冷启动 onCreate / 运行中 onConfigurationUpdate / 回前台 onForeground 复用）。
  //   · 写入 AppStorage['systemColorMode']：保存 ConfigurationConstant.ColorMode 原始枚举值
  //     （COLOR_MODE_DARK=0 / COLOR_MODE_LIGHT=1 / COLOR_MODE_NOT_SET=-1，本地 .d.ts L90/L112/L134 实证）。
  //   · 同值跳过：onConfigurationUpdate 也会因语言/字号等其它配置变更触发，避免无效刷新。
  //   · §8.3②：AppStorage 为全局对象，禁止 import。
  private syncSystemColorMode(colorMode: ConfigurationConstant.ColorMode | undefined): void {
    try {
      if (colorMode === undefined) {
        return;
      }
      const prev = AppStorage.get<number>('systemColorMode');
      if (prev === colorMode) {
        return;
      }
      AppStorage.setOrCreate('systemColorMode', colorMode);
      const isDark: boolean = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      hilog.info(DOMAIN, TAG, 'DEV-010: systemColorMode=%{public}d, isDark=%{public}d', colorMode, isDark ? 1 : 0);
      // 通知主题系统：仅 FOLLOW_SYSTEM 模式且深浅态实际变化时才刷新色板（ThemeManager 内已做双重防抖）
      getThemeManager().onSystemDarkModeChange(isDark);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'DEV-010: syncSystemColorMode failed: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');
    // F7: 记录窗口舞台供提醒路由消费
    this.mainWindowStage = windowStage;

    // fix: DEV-011 · T-P01：loadContent 改回调形态——persistProp 的唯一合法时机是本回调
    //   （官方约束：PersistentStorage 和 UI 实例相关联，持久化操作需在 UI 实例初始化成功后
    //   （即 loadContent 传入的回调被调用时）才可以被调用，早于该时机调用会导致持久化失败）。
    //   顺序铁律：① PersistentState.initialize（persistProp 恢复磁盘值→AppStorage）
    //           ② ThemeManager.restorePersisted（persist_theme_* 接线 + 依据恢复值重算色板广播）
    //   二者均同步执行，先于页面对这些键的任何写入（防"内存值胜出覆盖磁盘值"）。
    windowStage.loadContent('pages/MainPage', (err: BusinessError) => {
      if (err && err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
      try {
        PersistentState.initialize(this.context);
        getThemeManager().restorePersisted();
        // fix: DEV+HUI —— 四期密码方案：登录注册走 Cloud DB（AccountManager），无 Auth SDK，此处无需任何注入
        hilog.info(DOMAIN, TAG, 'DEV-011: PersistentStorage initialized in loadContent callback');
      } catch (persistErr) {
        hilog.error(DOMAIN, TAG, 'DEV-011: persist init failed: %{public}s', JSON.stringify(persistErr));
      }
      // P0-07: UIContext 就绪后注册 JetBrains Mono 等宽字体（仅数字/英文）
      this.registerMonoFonts(windowStage);
      // HUI-006: 注册手绘风格字体（猫啃什锦黑 + 清松手写体2）
      this.registerSketchFonts(windowStage);
      // HUI-001: 猫爪特效已改纯页面树内方案（各页根容器捕获+同树视觉层），窗口级挂载已拆除
      // F7: 冷启动来自提醒点击时，主页加载完成后补跳「写日记页」
      this.flushPendingRoute();
    });
  }

  // P0-07 方案A：注册 JetBrains Mono 4 字重自定义字体。
  // · API 24 中全局 font.registerFont 已 @deprecated(since 18)，改用
  //   UIContext.getFont().registerFont()（@ohos.font.d.ts / @ohos.arkui.UIContext.d.ts 已 grep 自证）。
  // · FontOptions 仅 { familyName, familySrc } 无 weight 字段，故每个字重注册独立 familyName。
  // · 族名与 shared 的 FONT 常量一一对应，避免魔法字符串。
  // · §9 崩溃防范：整体 try/catch，注册失败仅告警不闪退，UI 回退系统字体。
  private registerMonoFonts(windowStage: window.WindowStage): void {
    try {
      const uiFont = windowStage.getMainWindowSync().getUIContext().getFont();
      uiFont.registerFont({ familyName: FONT.mono, familySrc: $rawfile('fonts/JetBrainsMono-Regular.ttf') });
      uiFont.registerFont({ familyName: FONT.monoMedium, familySrc: $rawfile('fonts/JetBrainsMono-Medium.ttf') });
      uiFont.registerFont({ familyName: FONT.monoBold, familySrc: $rawfile('fonts/JetBrainsMono-Bold.ttf') });
      uiFont.registerFont({ familyName: FONT.monoExtraBold, familySrc: $rawfile('fonts/JetBrainsMono-ExtraBold.ttf') });
      hilog.info(DOMAIN, TAG, 'P0-07: JetBrains Mono registered (Regular/Medium/Bold/ExtraBold).');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'P0-07: registerFont failed: %{public}s', JSON.stringify(err));
    }
  }

  // HUI-006: 注册手绘风格字体（猫啃什锦黑 + 清松手写体2）。
  // · 设计依据：UX-001_sketch_design.md v2 §2.2
  // · 审判修正：JUDGE-001 N1 — 使用 UIContext.getFont().registerFont() 替代已弃用的全局 font.registerFont()
  // · 注册失败静默降级到 fallback 链（MaokenAssortedSans → HarmonyOS Sans → sans-serif）
  // · familyName 须与 shared/FontPresets.ets 的 FONT.sketchTitle / FONT.sketchBody 完全一致
  private registerSketchFonts(windowStage: window.WindowStage): void {
    try {
      const uiFont = windowStage.getMainWindowSync().getUIContext().getFont();
      uiFont.registerFont({
        familyName: FONT.sketchTitle,
        familySrc: $rawfile('fonts/MaokenAssortedSans-TC.otf')
      });
      uiFont.registerFont({
        familyName: FONT.sketchBody,
        familySrc: $rawfile('fonts/QingSongHandwriting2.ttf')
      });
      hilog.info(DOMAIN, TAG, 'HUI-006: Sketch fonts registered (MaokenAssortedSans + QingSongHandwriting2).');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'HUI-006: Sketch font registration failed: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
    // DEV-010 · T-D02：回前台兜底同步——若系统深浅色在后台期间变化且 onConfigurationUpdate 未及送达，
    //   回前台时以 context.config.colorMode 当前值补一次同步（同值跳过，无副作用）。
    this.syncSystemColorMode(this.context.config.colorMode);
    // DEV-T103：前台 TTS 到点播报——标记 app 前台并从 todo 表重排播报定时器。
    // 只前台红线：后台播报由 onAppBackground 清定时器 + fire 路径双重校验共同保证不发生。
    ReminderAgentService.onAppForeground();
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
    // DEV-T103：转后台立即停前台 TTS 定时链路（到点提醒交还系统代理"通知+铃声"）。
    ReminderAgentService.onAppBackground();
  }
}