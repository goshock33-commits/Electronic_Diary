// agentID: DEV-002
// File: EventBus.ets
// Task: B01 EventBus unified string API + 21 event names + absorb channel B bare emits
// Architecture: ARC-001 4.5 / 4.6 event reliability strategy
// Skill Ref: frontend-design / ui-ux-pro-max
// SDK: HarmonyOS 6.1.1 (API 24) - emitter API first param is string

import { emitter } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'EventBus';

/**
 * Event callback type - receives flat payload (auto-unwrapped from emitter.EventData.data).
 */
export type EventCallback = (data: Record<string, Object>) => void;

/**
 * Explicit interface for the centralized event-name constants.
 * ArkTS arkts-no-untyped-obj-literals: object literals must correspond to a
 * declared interface/class (Record<string,string> literal is rejected), so all
 * 23 event-name fields are declared explicitly here.
 */
export interface EventNameMap {
  CHECKIN_CHANGED: string;
  TODO_CREATED: string;
  TODO_COMPLETED: string;
  TODO_DELETED: string;
  /** DEV-003：待办编辑（标题/分类/日程）后发射，统计页/时光轴等订阅方刷新 */
  TODO_UPDATED: string;
  DIARY_SAVED: string;
  TASK_EXTRACTED: string;
  TASK_CONVERTED: string;
  POMODORO_STATE: string;
  SECTION_CHANGED: string;
  QUOTE_CHANGED: string;
  THEME_CHANGED: string;
  SETTINGS_CHANGED: string;
  FONT_SIZE_CHANGED: string;
  REMINDER_CHANGED: string;
  SECURITY_LOCK_CHANGED: string;
  BACKUP_STARTED: string;
  BACKUP_COMPLETED: string;
  RESTORE_STARTED: string;
  RESTORE_COMPLETED: string;
  CLIPBOARD_TASK_DETECTED: string;
  GESTURE_CAPTURE_COMPLETE: string;
  SEARCH_EXECUTED: string;
  SHARE_STAGE_CHANGED: string;
}

/**
 * EventBus - Unified event bus based on Emitter API (string event names).
 *
 * Design (per ARC-001 4.5 / 4.6):
 * - Flat payload: emit() accepts a flat Record, internally wraps into emitter.EventData.data
 * - Auto-unwrap: on() callback receives flat data extracted from emitter.EventData.data
 * - Try-catch isolation: single callback exception does not affect other subscribers
 * - Lifecycle management: on/off paired per event name; off() removes all subs for that event
 *
 * Usage:
 *   EventBus.on(EventBus.EventNames.CHECKIN_CHANGED, (data: Record<string, Object>) => { ... });
 *   EventBus.emit(EventBus.EventNames.CHECKIN_CHANGED, { date: '2026-07-09', isChecked: true });
 *   EventBus.off(EventBus.EventNames.CHECKIN_CHANGED); // in aboutToDisappear
 */
export class EventBus {
  /** Centralized event name constants (23 events covering all modules) */
  static readonly EventNames: EventNameMap = {
    CHECKIN_CHANGED: 'event:checkin:changed',
    TODO_CREATED: 'event:todo:created',
    TODO_COMPLETED: 'event:todo:completed',
    TODO_DELETED: 'event:todo:deleted',
    TODO_UPDATED: 'event:todo:updated',
    DIARY_SAVED: 'event:diary:saved',
    TASK_EXTRACTED: 'event:task:extracted',
    TASK_CONVERTED: 'event:task:converted',
    POMODORO_STATE: 'event:pomodoro:state',
    SECTION_CHANGED: 'event:section:changed',
    QUOTE_CHANGED: 'event:quote:changed',
    THEME_CHANGED: 'event:theme:changed',
    SETTINGS_CHANGED: 'event:settings:changed',
    FONT_SIZE_CHANGED: 'event:fontSize:changed',
    REMINDER_CHANGED: 'event:reminder:changed',
    SECURITY_LOCK_CHANGED: 'event:securityLock:changed',
    BACKUP_STARTED: 'event:backup:started',
    BACKUP_COMPLETED: 'event:backup:completed',
    RESTORE_STARTED: 'event:restore:started',
    RESTORE_COMPLETED: 'event:restore:completed',
    CLIPBOARD_TASK_DETECTED: 'event:clipboard:task-detected',
    GESTURE_CAPTURE_COMPLETE: 'event:gesture:capture-complete',
    SEARCH_EXECUTED: 'event:search:executed',
    SHARE_STAGE_CHANGED: 'event:share:stage-changed'
  };

  /** Emitter instance - application-wide singleton (isolated from global emitter) */
  private static emitterInstance: emitter.Emitter | null = null;
  /** Subscription tracking: eventName -> Map<subId, wrappedCallback> */
  private static subscriptionMap: Map<string, Map<number, Function>> = new Map();
  /** Counter for generating unique subscription IDs */
  private static nextSubId: number = 1000;

  // ==================== Initialization ====================

  /**
   * Initialize the EventBus emitter instance.
   * Call once during app startup (StartupTasks / AbilityStage.onCreate).
   */
  static initialize(): void {
    if (!EventBus.emitterInstance) {
      EventBus.emitterInstance = new emitter.Emitter();
      hilog.info(0x0000, TAG, 'EventBus initialized');
    }
  }

  /**
   * Get the emitter instance (lazy init).
   */
  private static getEmitter(): emitter.Emitter {
    if (!EventBus.emitterInstance) {
      EventBus.emitterInstance = new emitter.Emitter();
    }
    return EventBus.emitterInstance;
  }

  // ==================== Public API ====================

  /**
   * Subscribe to an event.
   * IMPORTANT: Call off() in component's aboutToDisappear to prevent memory leaks.
   *
   * @param event The event name string to subscribe to
   * @param callback The callback invoked with flat data payload when event is emitted
   */
  static on(event: string, callback: Function): void {
    try {
      // Wrap callback for try-catch isolation + auto-unwrap emitter.EventData.data
      const wrappedCallback = (eventData: emitter.EventData): void => {
        try {
          const flatData: Record<string, Object> = eventData.data as Record<string, Object> ?? {};
          callback(flatData);
        } catch (err) {
          hilog.error(0x0000, TAG, 'EventBus.on callback error [event=%{public}s]: %{public}s',
            event, JSON.stringify(err));
        }
      };

      const emitterInstance = EventBus.getEmitter();
      emitterInstance.on(event, wrappedCallback);

      // Track subscription internally
      const subId = EventBus.nextSubId++;
      let subs = EventBus.subscriptionMap.get(event);
      if (!subs) {
        subs = new Map<number, Function>();
        EventBus.subscriptionMap.set(event, subs);
      }
      subs.set(subId, wrappedCallback);

      hilog.debug(0x0000, TAG, 'EventBus.on: event=%{public}s, subId=%{public}d', event, subId);
    } catch (err) {
      hilog.error(0x0000, TAG, 'EventBus.on failed [event=%{public}s]: %{public}s',
        event, JSON.stringify(err));
    }
  }

  /**
   * Emit an event with flat data payload.
   * Internally wraps the flat data into emitter.EventData.data.
   *
   * @param event The event name string to emit
   * @param data Flat payload object (e.g., { date: '...', isChecked: true, streakDays: 7 })
   */
  static emit(event: string, data: Record<string, Object>): void {
    try {
      const eventData: emitter.EventData = {
        data: data
      };
      EventBus.getEmitter().emit(event, eventData);
      hilog.debug(0x0000, TAG, 'EventBus.emit: event=%{public}s', event);
    } catch (err) {
      hilog.error(0x0000, TAG, 'EventBus.emit failed [event=%{public}s]: %{public}s',
        event, JSON.stringify(err));
    }
  }

  /**
   * Unsubscribe all callbacks for a given event name.
   * Call in component's aboutToDisappear lifecycle.
   *
   * @param event The event name string to unsubscribe from
   */
  static off(event: string): void {
    try {
      const subs = EventBus.subscriptionMap.get(event);
      if (subs && subs.size > 0) {
        EventBus.getEmitter().off(event);
        EventBus.subscriptionMap.delete(event);
        hilog.debug(0x0000, TAG, 'EventBus.off: event=%{public}s, removed %{public}d subscriptions',
          event, subs.size);
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'EventBus.off failed [event=%{public}s]: %{public}s',
        event, JSON.stringify(err));
    }
  }

  /**
   * Remove all subscriptions (for cleanup/testing).
   */
  static clear(): void {
    EventBus.subscriptionMap.forEach((_subs, event) => {
      try {
        EventBus.getEmitter().off(event);
      } catch (err) {
        // Ignore individual off errors during clear
      }
    });
    EventBus.subscriptionMap.clear();
    EventBus.nextSubId = 1000;
    hilog.info(0x0000, TAG, 'EventBus cleared');
  }

  /**
   * Get active subscription count across all events (for debugging).
   */
  static getSubscriptionCount(): number {
    let count = 0;
    EventBus.subscriptionMap.forEach((subs) => {
      count += subs.size;
    });
    return count;
  }
}
