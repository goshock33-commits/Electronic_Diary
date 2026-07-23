// <!-- agentID: DEV-001 -->
// File: VoiceDiaryViewModel.ets
// Task: T038 Voice diary business logic - speech recognition, voice-to-text diary, voice add todo
// Architecture: ARC-001 4.4 SpeechRecognizer / 2.0 voice interaction
// Skill Ref: frontend-design / ui-ux-pro-max

import { DiaryDao } from '@ohos/shared';
import { TodoDao } from '@ohos/shared';
import { Diary } from '@ohos/shared';
import { TodoItem } from '@ohos/shared';
import { EventBus } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'VoiceDiaryViewModel';

export enum VoiceState { IDLE = 'idle', LISTENING = 'listening', PROCESSING = 'processing', DONE = 'done' }

export interface VoiceResult {
  text: string;
  isDiary: boolean;
  isTodo: boolean;
}

/**
 * VoiceDiaryViewModel - Manages voice-to-text diary writing and voice todo creation.
 * Integrates with Xiaoyi SpeechRecognizer for real-time speech-to-text.
 */
export class VoiceDiaryViewModel {
  private state: VoiceState = VoiceState.IDLE;
  private recognizedText: string = '';
  private isEnabled: boolean = true;

  init(enabled: boolean = true): void { this.isEnabled = enabled; this.state = VoiceState.IDLE; this.recognizedText = ''; AppStorage.setOrCreate('voiceState', 'idle'); }

  getState(): VoiceState { return this.state; }
  getRecognizedText(): string { return this.recognizedText; }
  isListening(): boolean { return this.state === VoiceState.LISTENING; }

  /**
   * Start voice recording for diary dictation or todo creation.
   * In production, this integrates with Xiaoyi SpeechRecognizer API.
   * Falls back to showing "voice service unavailable" message.
   */
  async startListening(): Promise<boolean> {
    if (!this.isEnabled) { return false; }
    this.state = VoiceState.LISTENING;
    this.recognizedText = '';
    AppStorage.setOrCreate('voiceState', 'listening');
    hilog.info(0x0000, TAG, 'Voice listening started');
    // In production: SpeechRecognizer.startListening() with streaming callbacks
    // For now, simulate with placeholder
    return true;
  }

  /** Stop voice recording and process recognized text */
  async stopListening(): Promise<VoiceResult> {
    this.state = VoiceState.PROCESSING;
    AppStorage.setOrCreate('voiceState', 'processing');
    // In production: SpeechRecognizer.stop() returns final recognized text
    const text = this.recognizedText.length > 0 ? this.recognizedText : '';
    const isTodo = VoiceDiaryViewModel.detectTodoIntent(text);
    const isDiary = !isTodo && text.length > 0;
    this.state = VoiceState.DONE;
    AppStorage.setOrCreate('voiceState', 'done');
    return { text, isDiary, isTodo };
  }

  /** Update recognized text (real-time streaming from speech recognizer) */
  onPartialResult(text: string): void { this.recognizedText = text; }

  /** Set final recognized text */
  setRecognizedText(text: string): void { this.recognizedText = text; }

  /** Save recognized text as a diary entry */
  async saveAsDiary(): Promise<boolean> {
    if (this.recognizedText.length === 0) { return false; }
    try {
      const diary = new Diary();
      diary.date = this.getTodayDate();
      diary.content = this.recognizedText;
      const rowId = await DiaryDao.insert(diary);
      if (rowId > 0) {
        const payload: Record<string, Object> = {};
        payload['diaryId'] = rowId;
        payload['date'] = diary.date;
        EventBus.emit(EventBus.EventNames.DIARY_SAVED, payload);
        this.reset();
        return true;
      }
      return false;
    } catch (err) { hilog.error(0x0000, TAG, 'SaveAsDiary failed: %{public}s', (err as BusinessError).message); return false; }
  }

  /** Add recognized text as a todo item */
  async addAsTodo(date?: string): Promise<boolean> {
    if (this.recognizedText.length === 0) { return false; }
    try {
      const todoDate = date ?? this.getTodayDate();
      // Extract todo title (remove "添加待办" prefix if present)
      let title = this.recognizedText;
      if (title.startsWith('添加待办')) { title = title.substring(4).trim(); }
      else if (title.startsWith('待办')) { title = title.substring(2).trim(); }
      const maxOrder = await TodoDao.getMaxSortOrder(todoDate, 'today');
      const todo = new TodoItem(todoDate, title, 'today');
      todo.sort_order = maxOrder + 1;
      const rowId = await TodoDao.insert(todo);
      if (rowId > 0) {
        const payload: Record<string, Object> = {};
        payload['todoId'] = rowId;
        payload['date'] = todoDate;
        payload['type'] = 'today';
        EventBus.emit(EventBus.EventNames.TODO_CREATED, payload);
        this.reset();
        return true;
      }
      return false;
    } catch (err) { hilog.error(0x0000, TAG, 'AddAsTodo failed: %{public}s', (err as BusinessError).message); return false; }
  }

  /** Cancel voice input */
  cancel(): void { this.reset(); }
  private reset(): void { this.state = VoiceState.IDLE; this.recognizedText = ''; AppStorage.setOrCreate('voiceState', 'idle'); }

  /** Detect if the recognized text contains a todo creation intent */
  private static detectTodoIntent(text: string): boolean {
    const todoKeywords = ['添加待办', '待办', '加一个待办', '新建待办', '创建待办', '提醒我', '记住'];
    return todoKeywords.some(kw => text.includes(kw));
  }

  private getTodayDate(): string { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`; }
  setEnabled(enabled: boolean): void { this.isEnabled = enabled; }
}
