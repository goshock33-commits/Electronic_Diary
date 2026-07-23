// <!-- agentID: DEV-005 (M17 每日提醒 - 后台代理提醒调度) -->
// <!-- agentID: DEV-T103 (前台 TTS 到点播报) --> 新增前台播报链路(JUDGE F1 三态之·前台态):
//   app 前台可见时,到点从 todo 表(真相源)查到期待办 → TtsService.enqueue 逐条播报;
//   后台/熄屏不走本链路(走系统代理"通知+铃声"),红线由 appForeground 标志保证,回前台不补播。
//   前后台状态由 EntryAbility.onForeground/onBackground → onAppForeground/onAppBackground 接线驱动。
//   TtsService 契约(MAIN-001 拍板,T101 并行落地): getInstance().enqueue(text: string): Promise<void>。
// <!-- agentID: DEV-T104 (S2 提醒自愈闭环) --> scheduleDaily 破坏点(cancelAllReminders)之后内建
//   rescheduleAllTodoReminders 自愈(disabled/成功/失败三路径全覆盖),改"每日日记提醒"设置不再静默
//   清掉待办提醒;自愈函数加串行链防并发双发。登记条款见 workSpace/API_CONTRACT.md §十。
// <!-- agentID: DEV-013 (待办提醒增强) --> 新增 Todo 单条日历型提醒三方法:
//   scheduleTodoReminder(一次性日历提醒发布) / cancelTodoReminder(按 id 精确取消,不伤每日日记提醒)
//   / rescheduleAllTodoReminders(冷启动/进页批量恢复——scheduleDaily 的 cancelAllReminders 会连带
//   清掉 Todo 提醒,该方法从 todo 表真相源重发布并写回 reminder_id,形成自愈闭环)。
// API 核实来源: 本地 SDK @ohos.reminderAgentManager.d.ts (API 24):
//   · cancelReminder(reminderId): Promise<void>                (L81)
//   · enum ReminderType.REMINDER_TYPE_CALENDAR = 1             (L300)
//   · interface ReminderRequestCalendar { dateTime: LocalDateTime; repeatMonths?; repeatDays?; endDateTime? } (L655-695)
//   · interface LocalDateTime { year; month; day; hour; minute; second? } (L782-870, month 为 1-12)
// 文件: ReminderAgentService.ets
// 任务: M17 每日提醒 —— 把 app_settings 里的提醒开关/时间真正调度到系统(reminderAgentManager)。
//       此前只把设置落 app_settings 表,从未调用鸿蒙后台代理提醒 API 真正弹出每日通知,本类补这一层。
// 真相源: app_settings 表(features/settings SettingsViewModel 落库的 reminder_enabled / reminder_time)。
// 关联: SettingsViewModel(改设置→重调度) / EntryAbility(冷启动重调度) / DiaryReminderManager(旧调用点委托本类)。
// 编译坑对照 后端开发文档.md §十一: 无 any/unknown;无解构/spread;shared 模块内用相对路径 import;
//   boolean 以字符串 'true'/'false' 存 app_settings(与 SettingsViewModel 一致)。
// API 核实来源: sdk_dts/openharmony/ets/api/@ohos.reminderAgentManager.d.ts
//   · publishReminder(reminderReq): Promise<number>            (L57)
//   · cancelAllReminders(): Promise<void>                      (L121)
//   · enum ReminderType.REMINDER_TYPE_ALARM = 2                (L307)
//   · interface ReminderRequestAlarm { hour; minute; daysOfWeek? }  (L705-730)
//   · interface ActionButton { title; type } / ActionButtonType.ACTION_BUTTON_TYPE_CLOSE = 0 (L317-342, L269)
//   · interface WantAgent { pkgName; abilityName }             (L351-367)
//   · ReminderRequest.{notificationId,slotType,title,content,expiredContent,tapDismissed} 均为可选 (L448-646)

import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppSettingsDao } from '../database/dao/AppSettingsDao';
// DEV-013: Todo 提醒——同模块相对路径 import（§编译坑: shared 模块内禁 '@ohos/shared' 自引用）。
import { TodoDao } from '../database/dao/TodoDao';
import { TodoItem } from '../data/TodoItem';
// M17-RINGTONE(DEV-007): 铃声 id → rawfile 音源映射(与试听同源,customRingUri 直接消费同一张表)。
import { RingtonePlayUtils } from './RingtonePlayUtils';
// fix: MAIN-001·M17-FALLBACK: 系统代理提醒发布失败时的应用内直发通知降级（模拟器提醒服务缺陷兜底）。
import { NotificationUtils } from './NotificationUtils';
// DEV-T103: 前台 TTS 播报——T101 TtsService(同模块相对路径 import;契约 MAIN-001 拍板:
//   getInstance().enqueue(text: string): Promise<void>,内部 FIFO 队列自排队,busy 不炸)。
import { TtsService } from './TtsService';

const TAG = 'ReminderAgentService';
const DOMAIN = 0x0000;

// app_settings 键名(必须与 features/settings SettingsViewModel 中的常量一致;此处不能 import 该 VM,
// 否则 shared→features 反向依赖 + 循环依赖,故就地复刻键名字面量)。
const KEY_REMINDER_ENABLED = 'reminder_enabled';
const KEY_REMINDER_TIME = 'reminder_time';
// M17-RINGTONE(DEV-007): 提醒方式(notification/ring/both)与铃声 id,发布提醒时真实消费。
const KEY_REMINDER_METHOD = 'reminder_method';
const KEY_REMINDER_RINGTONE_URI = 'reminder_ringtone_uri';

// M17-RINGTONE(DEV-007): 提醒方式取值(与 SettingsViewModel.ReminderMethod 枚举字面量一致)。
const METHOD_NOTIFICATION = 'notification';
const METHOD_RING = 'ring';

// M17-RINGTONE(DEV-007): 响铃时长(秒)。API 证据: ReminderRequest.ringDuration?: number
// (@ohos.reminderAgentManager.d.ts L501, since 9;官方文档:默认 1 秒,0 = 不响铃)。
const RING_SECONDS = 10;
const RING_SECONDS_NONE = 0;

// 后台代理提醒 syscap;设备不支持时安全降级(仅记日志,不崩)。
const SYSCAP_REMINDER = 'SystemCapability.Notification.ReminderAgent';

// 固定通知 id(同 id 后发覆盖先发;配合 cancelAllReminders 保证全局仅一条日记提醒)。
const REMINDER_NOTIFICATION_ID = 2001;

// wantAgent 目标: 点击提醒拉起主 Ability。bundleName 必须与 AppScope/app.json5 的 bundleName 一致。
const TARGET_BUNDLE = 'com.example.electronic_diary';
const TARGET_ABILITY = 'EntryAbility';

// 中文文案常量。
const REMINDER_TITLE = '电子日记';
const REMINDER_CONTENT = '该记录今天的心情啦 ✍️';
const REMINDER_EXPIRED = '今天的日记提醒已过期';
const REMINDER_BTN_WRITE = '写日记';

// 默认时间(app_settings 未写入时的回退,与 SettingsViewModel.getReminderSettings 的 '20:00' 一致)。
const DEFAULT_HOUR = 20;
const DEFAULT_MINUTE = 0;

// DEV-013: Todo 待办提醒——notificationId 基址(3000+todo.id,与日记提醒 2001 隔离,各待办互不覆盖)。
const TODO_NOTIFICATION_ID_BASE = 3000;
// DEV-013: Todo 待办提醒中文文案。
const TODO_REMINDER_TITLE = '待办提醒';
const TODO_REMINDER_CONTENT = '该处理这条待办了';
const TODO_REMINDER_EXPIRED = '待办提醒已过期';
const TODO_BTN_KNOWN = '知道了';

// 每日重复: 周一(1)~周日(7) 全周。ReminderRequestAlarm 省略 daysOfWeek 只会触发一次,故显式全周。
const DAYS_ALL_WEEK: number[] = [1, 2, 3, 4, 5, 6, 7];

// DEV-T103: 前台 TTS 到点播报参数。
// · 到期回看窗口 60s:兜同一分钟多条待办 + setTimeout 触发抖动,fire 时把 [now-60s, now+1s] 判为到期。
// · 到期提前容差 1s:定时器可能略早于 remind_at 触发,±1s 内视为已到点。
// · 单次定时上限 24h:setTimeout 延时超 2^31-1ms 会溢出立即触发,远期提醒按 24h 哨兵空转接力续排。
const TTS_DUE_LOOKBACK_MS = 60 * 1000;
const TTS_DUE_EPSILON_MS = 1000;
const TTS_MAX_ARM_MS = 24 * 60 * 60 * 1000;

/**
 * ReminderAgentService - 每日提醒后台代理调度(M17)。
 *
 * 单一调度入口:全应用只维护一条"每日写日记"闹钟型提醒。
 * · scheduleDaily(hour, minute, enabled): 纯调度(先 cancelAll 再按需 publish),供 SettingsViewModel 调用。
 * · rescheduleFromSettings(): 从 app_settings 真相源读回开关/时间再 scheduleDaily,供冷启动/旧调用点复用。
 * · cancelAll(): 取消本应用全部后台代理提醒。
 */
export class ReminderAgentService {
  /**
   * 调度每日提醒(闹钟型,每日重复)。
   * enabled=false 时只取消不发布。总是先 cancelAllReminders 清旧,保证全局仅一条(幂等)。
   */
  static async scheduleDaily(hour: number, minute: number, enabled: boolean): Promise<void> {
    if (!canIUse(SYSCAP_REMINDER)) {
      hilog.warn(DOMAIN, TAG, 'ReminderAgent syscap unavailable, skip scheduling (safe degrade)');
      return;
    }
    const safeHour: number = ReminderAgentService.clampInt(hour, 0, 23, DEFAULT_HOUR);
    const safeMinute: number = ReminderAgentService.clampInt(minute, 0, 59, DEFAULT_MINUTE);
    // M17-RINGTONE(DEV-007): 从 app_settings 真相源读提醒方式/铃声 id,让「我的」页选择真实影响发布参数。
    // 放在 scheduleDaily 内部读取 → SettingsViewModel 与 EntryAbility 冷启动(rescheduleFromSettings)
    // 两条路径自然共用同一份参数,发布口径不会漂移。读取失败回退 both/default,不阻断调度。
    // HJDG-003 返工②: 两次 DB 读前置到 cancelAll 之前 —— 压缩 cancelAll→publish 的异步间隙,
    // 降低快速连改设置时同流水线交错出双闹钟的概率(M17 竞态红线);disabled 路径跳过读库。
    let method: string = 'both';
    let ringtoneId: string = 'default';
    if (enabled) {
      try {
        const methodStr: string | null = await AppSettingsDao.get(KEY_REMINDER_METHOD);
        if (methodStr !== null && methodStr.length > 0) {
          method = methodStr;
        }
        const ringtoneStr: string | null = await AppSettingsDao.get(KEY_REMINDER_RINGTONE_URI);
        if (ringtoneStr !== null && ringtoneStr.length > 0) {
          ringtoneId = ringtoneStr;
        }
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'read reminder method/ringtone failed, fallback both/default: %{public}s',
          (err as BusinessError).message);
      }
    }
    // 先清除已注册提醒(统一入口,避免与旧调度重复/竞争)。
    await ReminderAgentService.cancelAll();
    if (!enabled) {
      ReminderAgentService.clearFallbackTimer(); // 关闭提醒时同步停掉降级定时器
      hilog.info(DOMAIN, TAG, 'Reminder disabled -> cancelled only');
      // DEV-T104(S2): cancelAllReminders 连带清掉了系统侧 Todo 提醒 → 就地自愈恢复,
      // 不再依赖"下次冷启动/进待办页"才补(否则关日记提醒 = 待办提醒静默丢失)。
      await ReminderAgentService.rescheduleAllTodoReminders();
      return;
    }
    try {
      const closeBtn: reminderAgentManager.ActionButton = {
        title: REMINDER_BTN_WRITE,
        type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE
      };
      const target: reminderAgentManager.WantAgent = {
        pkgName: TARGET_BUNDLE,
        abilityName: TARGET_ABILITY
      };
      // M17-RINGTONE(DEV-007): 提醒方式 → 发布参数映射(API 证据见 @ohos.reminderAgentManager.d.ts):
      //   · ringDuration?: number   (L501, since 9;0=不响铃,官方默认 1 秒)
      //   · customRingUri?: string  (L645, since 11;rawfile 目录下铃声文件名)
      //   · slotType?: notification.SlotType (L613;SOCIAL_COMMUNICATION=1 LEVEL_HIGH 有横幅 L1095,
      //     CONTENT_INFORMATION=3 LEVEL_MIN 通知静默低打扰 L1123,见 @ohos.notificationManager.d.ts)
      // 映射:
      //   notification → 只弹通知不响铃: SOCIAL_COMMUNICATION + ringDuration 0
      //   ring         → 以响铃为主:   CONTENT_INFORMATION(通知降至最低打扰) + 响铃 + 自选铃声
      //                  (公开 API 无法完全不出通知条目,这是三方可达的最低通知形态)
      //   both(默认)   → 弹通知 + 响铃: SOCIAL_COMMUNICATION + 响铃 + 自选铃声
      const wantRing: boolean = method !== METHOD_NOTIFICATION;
      const slot: notificationManager.SlotType = method === METHOD_RING
        ? notificationManager.SlotType.CONTENT_INFORMATION
        : notificationManager.SlotType.SOCIAL_COMMUNICATION;
      const request: reminderAgentManager.ReminderRequestAlarm = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
        hour: safeHour,
        minute: safeMinute,
        daysOfWeek: DAYS_ALL_WEEK,
        actionButton: [closeBtn],
        wantAgent: target,
        title: REMINDER_TITLE,
        content: REMINDER_CONTENT,
        expiredContent: REMINDER_EXPIRED,
        notificationId: REMINDER_NOTIFICATION_ID,
        slotType: slot,
        tapDismissed: true,
        ringDuration: wantRing ? RING_SECONDS : RING_SECONDS_NONE
      };
      if (wantRing) {
        // 自定义铃声:rawfile 下文件名(与试听 RingtonePlayUtils 同一映射表,试听所闻即提醒所响)。
        request.customRingUri = RingtonePlayUtils.resolveRingFile(ringtoneId);
      }
      const reminderId: number = await ReminderAgentService.publishWithRetry(request);
      // 系统代理发布成功 → 停掉可能存在的降级定时器（避免双重提醒）
      ReminderAgentService.clearFallbackTimer();
      hilog.info(DOMAIN, TAG,
        'Daily reminder published: id=%{public}d, time=%{public}d:%{public}d, method=%{public}s, ring=%{public}s',
        reminderId, safeHour, safeMinute, method, wantRing ? RingtonePlayUtils.resolveRingFile(ringtoneId) : 'none');
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'publishReminder failed: code=%{public}d, msg=%{public}s', e.code, e.message);
      // fix: MAIN-001·M17-FALLBACK —— 系统代理拒绝发布（模拟器提醒服务缺陷实测：wipe 后首条即报 1700002）
      // 时降级为应用内定时直发通知：App 存活即到点弹通知；系统代理正常的设备走不到这里，不会双重提醒。
      ReminderAgentService.armFallbackTimer(safeHour, safeMinute);
    }
    // DEV-T104(S2 自愈闭环): 本方法开头的 cancelAllReminders(及 publishWithRetry 重试内的再次 cancelAll)
    // 会连带清掉系统侧全部 Todo 提醒。此处在破坏点之后统一自愈——从 todo 表真相源重发布未过期待办提醒,
    // 成功/失败路径都执行(失败只影响日记提醒,不该陪葬待办提醒)。必须放在 publishWithRetry 之后,
    // 否则重试路径的 cancelAll 会把刚恢复的待办提醒再次清掉。
    await ReminderAgentService.rescheduleAllTodoReminders();
  }

  // ==================== 应用内降级提醒（M17-FALLBACK · MAIN-001）====================

  /** 降级定时器 id（-1 = 未启用）。仅系统代理发布失败时启用；App 进程存亡决定其存亡。 */
  private static fallbackTimerId: number = -1;

  /** 清除降级定时器（系统代理发布成功 / 提醒被关闭时调用，幂等）。 */
  private static clearFallbackTimer(): void {
    if (ReminderAgentService.fallbackTimerId !== -1) {
      clearTimeout(ReminderAgentService.fallbackTimerId);
      ReminderAgentService.fallbackTimerId = -1;
      hilog.info(DOMAIN, TAG, 'Fallback in-app reminder cleared');
    }
  }

  /**
   * 启用应用内降级提醒：定时到下一个 HH:mm 直发通知（notificationManager，不经代理服务）。
   * 触发后自动续订次日同一时刻。仅在系统代理发布失败时被调用。
   */
  private static armFallbackTimer(hour: number, minute: number): void {
    ReminderAgentService.clearFallbackTimer();
    const now: Date = new Date();
    const target: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour, minute, 0);
    let delayMs: number = target.getTime() - now.getTime();
    if (delayMs <= 0) {
      delayMs += 24 * 60 * 60 * 1000; // 已过当日时刻 → 顺延明天
    }
    ReminderAgentService.fallbackTimerId = setTimeout(() => {
      ReminderAgentService.fallbackTimerId = -1;
      NotificationUtils.sendDailyReminder(REMINDER_TITLE, REMINDER_CONTENT).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'Fallback notification failed: %{public}s', err.message);
      });
      hilog.info(DOMAIN, TAG, 'Fallback in-app reminder fired (%{public}d:%{public}d)', hour, minute);
      // 续订次日
      ReminderAgentService.armFallbackTimer(hour, minute);
    }, delayMs);
    hilog.info(DOMAIN, TAG,
      'Fallback in-app reminder armed for %{public}d:%{public}d (fires in %{public}d s, app-alive only)',
      hour, minute, Math.round(delayMs / 1000));
  }

  /**
   * fix: HUI-FRONTEND-2 · 1700002（提醒数超限）自愈重试。
   * 实测（模拟器 hilog）：cancelAllReminders 已 resolve 但系统侧清理有滞后，紧跟的 publish 仍读到旧计数
   * 报 1700002。此处捕获该码后等待 500ms → 再 cancelAll → 再 publish，最多重试 2 次；其余错误码直接抛。
   */
  private static async publishWithRetry(request: reminderAgentManager.ReminderRequestAlarm): Promise<number> {
    let lastErr: BusinessError | null = null;
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        return await reminderAgentManager.publishReminder(request);
      } catch (err) {
        const e = err as BusinessError;
        if (e.code !== 1700002) {
          throw new Error(`publishReminder failed: ${e.code} ${e.message}`);
        }
        lastErr = e;
        hilog.warn(DOMAIN, TAG, '1700002 quota race, retry %{public}d/2 after cancelAll+delay', attempt + 1);
        await ReminderAgentService.cancelAll();
        await ReminderAgentService.sleep(500);
      }
    }
    throw new Error(`publishReminder failed after retries: ${lastErr !== null ? lastErr.message : 'unknown'}`);
  }

  /** 简单延时（重试间隙用） */
  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  /**
   * 从 app_settings(真相源)读回开关/时间并重新调度。
   * 供 EntryAbility 冷启动(重启后提醒仍在) & DiaryReminderManager 兼容层复用。
   * 非致命:任一步失败仅记日志,不抛。
   */
  static async rescheduleFromSettings(): Promise<void> {
    if (!canIUse(SYSCAP_REMINDER)) {
      hilog.warn(DOMAIN, TAG, 'ReminderAgent syscap unavailable, skip reschedule (safe degrade)');
      return;
    }
    try {
      const enabledStr: string | null = await AppSettingsDao.get(KEY_REMINDER_ENABLED);
      const timeStr: string | null = await AppSettingsDao.get(KEY_REMINDER_TIME);
      const enabled: boolean = enabledStr === 'true';
      const time: string = (timeStr !== null && timeStr.length > 0) ? timeStr : '20:00';
      const parts: string[] = time.split(':');
      const hour: number = parts.length > 0 ? parseInt(parts[0], 10) : DEFAULT_HOUR;
      const minute: number = parts.length > 1 ? parseInt(parts[1], 10) : DEFAULT_MINUTE;
      const safeHour: number = isNaN(hour) ? DEFAULT_HOUR : hour;
      const safeMinute: number = isNaN(minute) ? DEFAULT_MINUTE : minute;
      await ReminderAgentService.scheduleDaily(safeHour, safeMinute, enabled);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'rescheduleFromSettings failed: %{public}s', e.message);
    }
  }

  /**
   * 取消本应用全部后台代理提醒(单条日记提醒场景足够)。
   */
  static async cancelAll(): Promise<void> {
    if (!canIUse(SYSCAP_REMINDER)) {
      return;
    }
    try {
      await reminderAgentManager.cancelAllReminders();
      hilog.info(DOMAIN, TAG, 'All reminders cancelled');
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'cancelAllReminders failed: %{public}s', e.message);
    }
  }

  // ==================== Todo 待办提醒（DEV-013 · 日历型一次性提醒）====================

  /**
   * DEV-013：调度单条待办提醒（REMINDER_TYPE_CALENDAR 一次性，不重复）。
   * · 幂等：发布前先按 todo.reminder_id 精确清旧（cancelTodoReminder 吞"id 不存在"类错误）。
   * · remind_at 为空/已过期 → 只清旧不发布，返回 -1。
   * · 发布失败不抛：记日志 + NotificationUtils 无法定时兜底（一次性场景），返回 -1，
   *   调用方据返回值决定是否写回 reminder_id（不污染 DB 引用）。
   * · notificationId = TODO_NOTIFICATION_ID_BASE + todo.id：与日记提醒 2001 隔离，
   *   各待办互不覆盖。
   * ⚠️ 已知交互：scheduleDaily/publishWithRetry 内的 cancelAllReminders 会连带清掉系统侧
   *   Todo 提醒（DB 里 remind_at/reminder_id 仍在）——DEV-T104 起 scheduleDaily 尾部已内建
   *   rescheduleAllTodoReminders 就地自愈；冷启动/进待办页仍各有一次兜底恢复。
   *   自愈登记条款（任何新增 ReminderAgent 调用必须登记自愈）见 workSpace/API_CONTRACT.md §十。
   * @returns 系统 reminderId（>=0 成功；-1 未发布/失败）
   */
  static async scheduleTodoReminder(todo: TodoItem): Promise<number> {
    // DEV-T103: 前台 TTS——用内存 remind_at 抢先收紧前台播报定时器(不等调用方把 remind_at 写回 DB,
    // 避免"调度先于写库"读到旧值;到点播不播仍以 todo 表为准,改时/取消/完成在 fire 时自然过滤)。
    // 与系统代理 syscap 无关(纯应用内 setTimeout+TTS),故置于 syscap 检查之前,syscap 缺失设备照常前台播报。
    if (todo.remind_at !== null && todo.remind_at > Date.now()) {
      ReminderAgentService.armTtsAt(todo.remind_at);
    }
    if (!canIUse(SYSCAP_REMINDER)) {
      hilog.warn(DOMAIN, TAG, 'ReminderAgent syscap unavailable, skip todo reminder (safe degrade)');
      return -1;
    }
    // 先清旧提醒（改时间/重复调度幂等）
    await ReminderAgentService.cancelTodoReminder(todo.reminder_id);
    ReminderAgentService.clearTodoFallback(todo.id);
    if (todo.remind_at === null || todo.remind_at <= Date.now()) {
      hilog.info(DOMAIN, TAG, 'Todo reminder skipped (no remind_at or expired): id=%{public}d', todo.id);
      return -1;
    }
    const t: Date = new Date(todo.remind_at);
    try {
      const closeBtn: reminderAgentManager.ActionButton = {
        title: TODO_BTN_KNOWN,
        type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE
      };
      const target: reminderAgentManager.WantAgent = {
        pkgName: TARGET_BUNDLE,
        abilityName: TARGET_ABILITY
      };
      // LocalDateTime.month 为 1-12（.d.ts L800），JS getMonth() 0-11 需 +1
      const when: reminderAgentManager.LocalDateTime = {
        year: t.getFullYear(),
        month: t.getMonth() + 1,
        day: t.getDate(),
        hour: t.getHours(),
        minute: t.getMinutes(),
        second: t.getSeconds()
      };
      const request: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: when,
        actionButton: [closeBtn],
        wantAgent: target,
        title: todo.title.length > 0 ? todo.title : TODO_REMINDER_TITLE,
        content: ReminderAgentService.buildTodoContent(todo),
        expiredContent: TODO_REMINDER_EXPIRED,
        notificationId: TODO_NOTIFICATION_ID_BASE + todo.id,
        slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        tapDismissed: true
      };
      const reminderId: number = await reminderAgentManager.publishReminder(request);
      hilog.info(DOMAIN, TAG,
        'Todo reminder published: todoId=%{public}d, reminderId=%{public}d, at=%{public}d-%{public}d-%{public}d %{public}d:%{public}d',
        todo.id, reminderId, when.year, when.month, when.day, when.hour, when.minute);
      return reminderId;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'publish todo reminder failed: todoId=%{public}d, code=%{public}d, msg=%{public}s',
        todo.id, e.code, e.message);
      // M17-FALLBACK：系统代理提醒不可用（模拟器配额满 1700002 等）→ 降级为应用内 setTimeout + 直发通知
      ReminderAgentService.armTodoFallback(todo);
      return -1;
    }
  }

  // ==================== Todo 降级提醒（M17-FALLBACK 扩展 · DEV-013）====================
  /** Todo 降级定时器 Map（key=todo.id, value=timerId）。App 存活即到点直发通知，进程死亡失效。 */
  private static todoFallbackTimers: Map<number, number> = new Map();

  /** 清除指定待办的降级定时器（幂等）。 */
  static clearTodoFallback(todoId: number): void {
    const timerId: number | undefined = ReminderAgentService.todoFallbackTimers.get(todoId);
    if (timerId !== undefined) {
      clearTimeout(timerId);
      ReminderAgentService.todoFallbackTimers.delete(todoId);
    }
  }

  /** 系统提醒发布失败时降级：setTimeout 到期直发应用内通知（不依赖系统代理服务） */
  private static armTodoFallback(todo: TodoItem): void {
    ReminderAgentService.clearTodoFallback(todo.id);
    if (todo.remind_at === null) { return; }
    const delayMs: number = todo.remind_at - Date.now();
    if (delayMs <= 0) { return; }
    const timerId: number = setTimeout(() => {
      ReminderAgentService.todoFallbackTimers.delete(todo.id);
      NotificationUtils.sendTodoReminder(todo.id, todo.title).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'Todo fallback notification failed: id=%{public}d, msg=%{public}s',
          todo.id, err.message);
      });
      hilog.info(DOMAIN, TAG, 'Todo fallback notification fired: id=%{public}d', todo.id);
    }, delayMs);
    ReminderAgentService.todoFallbackTimers.set(todo.id, timerId);
    hilog.info(DOMAIN, TAG,
      'Todo fallback timer armed: id=%{public}d fires in %{public}ds (app-alive only)',
      todo.id, Math.round(delayMs / 1000));
  }

  /**
   * DEV-013：按系统 reminderId 精确取消单条待办提醒（不动每日日记提醒与其他待办提醒）。
   * null/负值直接跳过；"id 不存在"（已触发/已被 cancelAll 清掉）视为幂等成功，只记 warn 不抛。
   */
  static async cancelTodoReminder(reminderId: number | null): Promise<void> {
    if (!canIUse(SYSCAP_REMINDER)) {
      return;
    }
    if (reminderId === null || reminderId < 0) {
      return;
    }
    try {
      await reminderAgentManager.cancelReminder(reminderId);
      hilog.info(DOMAIN, TAG, 'Todo reminder cancelled: reminderId=%{public}d', reminderId);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'cancel todo reminder ignored (already fired/cleared): id=%{public}d, msg=%{public}s',
        reminderId, e.message);
    }
  }

  /**
   * DEV-013：批量恢复全部未过期待办提醒（自愈闭环）。
   * 场景：冷启动 / scheduleDaily 的 cancelAllReminders 连带清除 / 系统重启后代理提醒丢失。
   * 从 todo 表真相源查 completed=0 且 remind_at>now 的行，逐条重发布并把新 reminder_id 写回 DB。
   * 非致命：任一条失败仅记日志继续下一条，不抛。
   * DEV-T104(S2)：并发防重——scheduleDaily 尾部自愈与 TodoViewModel.init / EntryAbility 冷启动可能
   * 同时触发本方法；两次并发执行会各自 query→publish，同一待办被双发两条系统提醒（DB 只记后写回的
   * reminder_id，先发的成为无主提醒无法精确取消）。故用静态 Promise 串行链把所有调用排队执行。
   */
  private static todoRestoreChain: Promise<void> = Promise.resolve();

  static rescheduleAllTodoReminders(): Promise<void> {
    const run: Promise<void> = ReminderAgentService.todoRestoreChain
      .then((): Promise<void> => ReminderAgentService.doRescheduleAllTodoReminders());
    // doRescheduleAllTodoReminders 全 try/catch 不 reject；仍兜底 catch 防链条卡死。
    ReminderAgentService.todoRestoreChain = run.catch((): void => {});
    return run;
  }

  /** 自愈实际执行体（仅经 rescheduleAllTodoReminders 串行链进入，勿直接调用）。 */
  private static async doRescheduleAllTodoReminders(): Promise<void> {
    if (!canIUse(SYSCAP_REMINDER)) {
      return;
    }
    try {
      const pending: TodoItem[] = await TodoDao.queryPendingReminders(Date.now());
      let restored: number = 0;
      for (let i = 0; i < pending.length; i++) {
        const todo: TodoItem = pending[i];
        const newId: number = await ReminderAgentService.scheduleTodoReminder(todo);
        if (newId >= 0) {
          await TodoDao.updateReminderRef(todo.id, todo.remind_at, newId);
          restored++;
        }
      }
      hilog.info(DOMAIN, TAG, 'Todo reminders restored: %{public}d/%{public}d', restored, pending.length);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'rescheduleAllTodoReminders failed: %{public}s', e.message);
    }
  }

  // ==================== 前台 TTS 到点播报（DEV-T103 · JUDGE F1 三态之·前台态）====================
  // app 前台可见时,到点从 todo 表(真相源)查到期待办 → TtsService.enqueue 逐条播报。
  // 红线:只前台——appForeground 由 EntryAbility 生命周期接线驱动,后台清定时器,fire 路径再双重校验;
  // 后台/熄屏到点走系统代理"通知+铃声"链路,回前台不补播(迟到播报只骚扰不提醒)。
  // 与 M17-FALLBACK 降级通知相互独立:通知是可见提醒,TTS 是前台开口,不构成双重提醒。
  // 已知边界:前后台以 EntryAbility 为准——DiaryEditAbility 等子 Ability 独占前台的短暂窗口内不播报
  // (主场景老人模式/首页均驻留 EntryAbility;不引入未核验的 applicationStateChange API)。

  /** app 是否前台可见(EntryAbility 生命周期驱动;默认 false,未接线则本链路整体静默,不误播)。 */
  private static appForeground: boolean = false;
  /** 前台 TTS 定时器 id(-1 = 未启用)。全局仅一个:总是定到"最近一条未来提醒"。 */
  private static ttsTimerId: number = -1;
  /** 当前定时器目标时刻(ms;-1 = 未启用)。armTtsAt 据此"只收紧不放松"。 */
  private static ttsNextFireAt: number = -1;

  /** EntryAbility.onForeground 接线入口:标记前台并从 todo 表重排播报定时器。 */
  static onAppForeground(): void {
    ReminderAgentService.appForeground = true;
    hilog.info(DOMAIN, TAG, 'App foreground -> refresh TTS schedule');
    ReminderAgentService.refreshTtsSchedule();
  }

  /** EntryAbility.onBackground 接线入口:标记后台并清定时器(红线:后台不走 TTS)。 */
  static onAppBackground(): void {
    ReminderAgentService.appForeground = false;
    ReminderAgentService.clearTtsTimer();
    hilog.info(DOMAIN, TAG, 'App background -> TTS timer cleared');
  }

  /** 清除前台 TTS 定时器(幂等)。 */
  private static clearTtsTimer(): void {
    if (ReminderAgentService.ttsTimerId !== -1) {
      clearTimeout(ReminderAgentService.ttsTimerId);
      ReminderAgentService.ttsTimerId = -1;
      ReminderAgentService.ttsNextFireAt = -1;
    }
  }

  /**
   * 从 todo 表(真相源)重排前台 TTS 定时器:取最近一条未来提醒,交 armTtsAt 定时。
   * 竞态口径(M17 红线的收敛式解法):不清旧、不作废在途查询,一切经 armTtsAt"只收紧不放松"收敛——
   * 并发查库/新增调度最终只留最早一只定时器;陈旧的更早定时器到点空转一次(fire 查 DB 无到期项)
   * 后自愈重排,不误播、不丢播、无双定时器。后台由 armTtsAt/fire 双重前台校验拦截。
   */
  private static refreshTtsSchedule(): void {
    if (!ReminderAgentService.appForeground) {
      return;
    }
    TodoDao.queryPendingReminders(Date.now()).then((pending: TodoItem[]): void => {
      if (pending.length === 0) {
        return;
      }
      const first: TodoItem = pending[0]; // queryPendingReminders 按 remind_at ASC,首条即最近
      if (first.remind_at !== null) {
        ReminderAgentService.armTtsAt(first.remind_at);
      }
    }).catch((err: Error): void => {
      hilog.warn(DOMAIN, TAG, 'refreshTtsSchedule query failed (non-fatal): %{public}s', err.message);
    });
  }

  /**
   * 定时到指定时刻播报(只收紧:已有同刻/更早定时器则不动)。
   * scheduleTodoReminder 以内存 remind_at 直接调用——不等 DB 写回,避免"调度先于写库"竞态;
   * 到点播不播仍以 todo 表为准(改时/取消/完成在 fire 时自然过滤,定时器最多空转一次后自愈重排)。
   */
  private static armTtsAt(remindAt: number): void {
    if (!ReminderAgentService.appForeground) {
      return;
    }
    if (ReminderAgentService.ttsTimerId !== -1 && ReminderAgentService.ttsNextFireAt <= remindAt) {
      return; // 已有同刻/更早的定时器,无需收紧
    }
    ReminderAgentService.clearTtsTimer();
    let delayMs: number = remindAt - Date.now();
    if (delayMs < 0) {
      delayMs = 0;
    }
    if (delayMs > TTS_MAX_ARM_MS) {
      delayMs = TTS_MAX_ARM_MS; // 远期提醒:24h 哨兵空转接力,防 setTimeout 溢出立即触发
    }
    ReminderAgentService.ttsNextFireAt = remindAt;
    ReminderAgentService.ttsTimerId = setTimeout((): void => {
      ReminderAgentService.ttsTimerId = -1;
      ReminderAgentService.ttsNextFireAt = -1;
      ReminderAgentService.onTtsTimerFired();
    }, delayMs);
    hilog.info(DOMAIN, TAG, 'Foreground TTS timer armed: fires in %{public}ds (foreground-alive only)',
      Math.round(delayMs / 1000));
  }

  /** 播报串行链:并发 fire 排队执行,防两批并发查库把同一到期待办播两遍(思路同 todoRestoreChain)。 */
  private static ttsSpeakChain: Promise<void> = Promise.resolve();
  /** 已播水位(ms):本批播到的时刻上界,后续批次只查水位之后的提醒,同一批次不重播。 */
  private static ttsSpokenUntil: number = 0;

  /** 到点入口:串行播报到期待办,无论成败都从 todo 表重排下一条(链路不断)。 */
  private static onTtsTimerFired(): void {
    const run: Promise<void> = ReminderAgentService.ttsSpeakChain
      .then((): Promise<void> => ReminderAgentService.speakDueTodos());
    ReminderAgentService.ttsSpeakChain = run.catch((): void => {});
    run.then((): void => {
      ReminderAgentService.refreshTtsSchedule();
    }).catch((err: Error): void => {
      hilog.warn(DOMAIN, TAG, 'Foreground TTS fire failed (non-fatal): %{public}s', err.message);
      ReminderAgentService.refreshTtsSchedule();
    });
  }

  /**
   * 查 todo 表并播报当前到期待办:completed=0 且 remind_at ∈ (max(now-60s, 已播水位), now+1s]。
   * 回看 60s 兜同一分钟多条/定时抖动;逐条 enqueue(TtsService 内部 FIFO,顺序播完,busy 自排队)。
   * enqueue 失败仅记日志——系统通知/铃声链路不受影响,TTS 只是前台增强,不致命(失败项不重试,水位照推)。
   */
  private static async speakDueTodos(): Promise<void> {
    if (!ReminderAgentService.appForeground) {
      return; // 红线:到点时已转后台 → 不播,交给系统通知链路
    }
    const now: number = Date.now();
    const floorMs: number = Math.max(now - TTS_DUE_LOOKBACK_MS, ReminderAgentService.ttsSpokenUntil);
    const pending: TodoItem[] = await TodoDao.queryPendingReminders(floorMs);
    let spoken: number = 0;
    for (let i = 0; i < pending.length; i++) {
      const todo: TodoItem = pending[i];
      if (todo.remind_at === null || todo.remind_at > now + TTS_DUE_EPSILON_MS) {
        continue; // 未到期(查询结果含未来项,过滤只留到期批次)
      }
      if (!ReminderAgentService.appForeground) {
        return; // 入队途中转后台 → 立即停止(水位不推,该批次由系统通知链路接手)
      }
      try {
        await TtsService.getInstance().enqueue(ReminderAgentService.buildTtsText(todo));
        spoken++;
        hilog.info(DOMAIN, TAG, 'Foreground TTS enqueued: todoId=%{public}d', todo.id);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'TTS enqueue failed (non-fatal): todoId=%{public}d, msg=%{public}s',
          todo.id, (err as BusinessError).message);
      }
    }
    // 水位推进:本批已覆盖 (floor, now+1s],串行链保证推进期间无并发读
    const until: number = now + TTS_DUE_EPSILON_MS;
    if (until > ReminderAgentService.ttsSpokenUntil) {
      ReminderAgentService.ttsSpokenUntil = until;
    }
    hilog.info(DOMAIN, TAG, 'Foreground TTS due batch done: %{public}d spoken', spoken);
  }

  /** DEV-T103:拼播报文本——"待办提醒:{标题}(,地点:{地点})";标题空回退通用文案,适合口播不含 emoji 结构。 */
  private static buildTtsText(todo: TodoItem): string {
    const title: string = todo.title.length > 0 ? todo.title : TODO_REMINDER_CONTENT;
    if (todo.location !== null && todo.location.length > 0) {
      return `${TODO_REMINDER_TITLE}：${title}，地点：${todo.location}`;
    }
    return `${TODO_REMINDER_TITLE}：${title}`;
  }

  /** DEV-013：拼待办提醒正文——"HH:mm · 地点 · 该处理待办了"，无时间/地点则逐段省略。 */
  private static buildTodoContent(todo: TodoItem): string {
    const parts: string[] = [];
    if (todo.due_time !== null && todo.due_time.length > 0) {
      parts.push(todo.due_time);
    }
    if (todo.location !== null && todo.location.length > 0) {
      parts.push(todo.location);
    }
    parts.push(TODO_REMINDER_CONTENT);
    return parts.join(' · ');
  }

  /** 整数范围钳制(NaN/越界回退默认值)。 */
  private static clampInt(v: number, min: number, max: number, fallback: number): number {
    if (isNaN(v)) {
      return fallback;
    }
    const r: number = Math.floor(v);
    if (r < min) {
      return min;
    }
    if (r > max) {
      return max;
    }
    return r;
  }
}
