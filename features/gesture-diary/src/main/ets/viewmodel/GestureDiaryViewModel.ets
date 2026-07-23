// <!-- agentID: DEV-001 -->
// fix: HUI-FRONTEND
// File: GestureDiaryViewModel.ets
// Task: T037 Gesture diary business logic - shake trigger, camera launch, AI recognition, suggestion generation, user confirmation
// Architecture: ARC-001 S5 gesture photo diary / 4.4 CameraKit/ImageKit / flow C
// Skill Ref: frontend-design / ui-ux-pro-max

import { DiaryDao } from '@ohos/shared';
import { Diary } from '@ohos/shared';
import { EventBus } from '@ohos/shared';
import { CameraUtils } from '@ohos/shared';
import { ImageUtils } from '@ohos/shared';
import { SensorUtils, ShakeSensitivity } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'GestureDiaryViewModel';

export enum GestureState { IDLE = 'idle', CAPTURING = 'capturing', RECOGNIZING = 'recognizing', SUGGESTING = 'suggesting', CONFIRMED = 'confirmed' }
export interface SceneRecognition { sceneTags: string[]; ocrText: string; }
export interface DiarySuggestion { content: string; scenes: string[]; timestamp: number; }

export class GestureDiaryViewModel {
  private state: GestureState = GestureState.IDLE;
  private photoUri: string = '';
  private suggestion: DiarySuggestion | null = null;
  private isEnabled: boolean = true;

  init(enabled: boolean = true): void { this.isEnabled = enabled; this.state = GestureState.IDLE; AppStorage.setOrCreate('captureState', 'idle'); }

  /** Start shake detection */
  startShakeListener(context: Context, sensitivity: ShakeSensitivity = ShakeSensitivity.MEDIUM): void {
    if (!this.isEnabled) { return; }
    SensorUtils.startShakeListener(() => { this.onShakeDetected(context); }, sensitivity);
  }

  stopShakeListener(): void { SensorUtils.stopShakeListener(); }
  getState(): GestureState { return this.state; }
  getSuggestion(): DiarySuggestion | null { return this.suggestion; }
  getPhotoUri(): string { return this.photoUri; }

  /** Shake detected -> trigger photo capture flow */
  private async onShakeDetected(context: Context): Promise<void> {
    if (this.state === GestureState.CAPTURING || this.state === GestureState.RECOGNIZING) { return; }
    this.state = GestureState.CAPTURING;
    AppStorage.setOrCreate('captureState', 'capturing');
    try {
      await CameraUtils.capturePhoto(
        context,
        (result) => { this.onPhotoCaptured(result.imageUri); },
        (error) => { hilog.error(0x0000, TAG, 'Camera error: %{public}s', error); this.state = GestureState.IDLE; }
      );
    } catch (err) { hilog.error(0x0000, TAG, 'Shake capture error: %{public}s', (err as BusinessError).message); this.state = GestureState.IDLE; }
  }

  /** Photo captured -> AI scene recognition + OCR */
  private async onPhotoCaptured(uri: string): Promise<void> {
    this.photoUri = uri;
    this.state = GestureState.RECOGNIZING;
    AppStorage.setOrCreate('captureState', 'preview');
    try {
      const recognition = await this.performRecognition(uri);
      const suggestion = this.generateSuggestion(recognition);
      this.suggestion = suggestion;
      this.state = GestureState.SUGGESTING;
      AppStorage.setOrCreate('captureState', 'analyzing');
      const capturePayload: Record<string, Object> = {};
      capturePayload['text'] = suggestion.content;
      capturePayload['sceneLabel'] = suggestion.scenes.join(',');
      capturePayload['ocrText'] = recognition.ocrText;
      capturePayload['imagePath'] = uri;
      EventBus.emit(EventBus.EventNames.GESTURE_CAPTURE_COMPLETE, capturePayload);
    } catch (err) { hilog.error(0x0000, TAG, 'Recognition error: %{public}s', (err as BusinessError).message); this.state = GestureState.IDLE; }
  }

  /** F4: 页面直连入口——对指定照片构建 AI 建议（拍照确认/重新生成共用，替代页面 setTimeout 占位；真 OCR 需真机） */
  async buildSuggestionForPhoto(uri: string): Promise<DiarySuggestion> {
    if (uri.length > 0) { this.photoUri = uri; }
    this.state = GestureState.RECOGNIZING;
    AppStorage.setOrCreate('captureState', 'analyzing');
    const recognition = await this.performRecognition(this.photoUri);
    const suggestion = this.generateSuggestion(recognition);
    this.suggestion = suggestion;
    this.state = GestureState.SUGGESTING;
    return suggestion;
  }

  /** AI recognition: scene tags + OCR text extraction (placeholder for ImageKit integration) */
  private async performRecognition(uri: string): Promise<SceneRecognition> {
    // In production, this calls ImageKit scene detection + OCR APIs
    const info = await ImageUtils.getImageInfo(uri);
    const sceneTags = ['photo'];
    if (info) {
      if (info.width > info.height) { sceneTags.push('landscape'); } else { sceneTags.push('portrait'); }
    }
    return { sceneTags, ocrText: '' };
  }

  /** Generate diary content suggestion based on recognition + timestamp */
  private generateSuggestion(rec: SceneRecognition): DiarySuggestion {
    const now = new Date();
    const timeStr = `${now.getHours()}:${String(now.getMinutes()).padStart(2, '0')}`;
    let content = `${this.formatCurrentDate()} ${timeStr}\n`;
    if (rec.sceneTags.length > 0) {
      const tagMap: Record<string, string> = {};
      tagMap['outdoor'] = '户外';
      tagMap['indoor'] = '室内';
      tagMap['food'] = '美食';
      tagMap['portrait'] = '人物';
      tagMap['landscape'] = '风景';
      tagMap['document'] = '文档';
      tagMap['photo'] = '照片';
      const labels = rec.sceneTags.map(t => tagMap[t] ?? t).join('、');
      content += `拍摄了一张${labels}照片。\n`;
    }
    if (rec.ocrText.length > 0) { content += `识别文字：${rec.ocrText}\n`; }
    content += '今天...\n';
    return { content, scenes: rec.sceneTags, timestamp: now.getTime() };
  }

  /** User confirms -> save diary and discard temp photo (F4: finalContent 为页面编辑后的最终文本) */
  async confirmSave(baseDir: string, finalContent?: string): Promise<boolean> {
    if (!this.suggestion) { return false; }
    if (finalContent !== undefined && finalContent.length > 0) { this.suggestion.content = finalContent; }
    try {
      // Copy photo to sandbox and save diary
      const sandboxUri = await ImageUtils.copyToSandbox(this.photoUri, baseDir);
      const diary = new Diary();
      diary.date = this.getTodayDate();
      diary.content = this.suggestion.content;
      if (sandboxUri) { diary.setImageList([sandboxUri]); }
      const rowId = await DiaryDao.insert(diary);
      if (rowId > 0) {
        const diaryPayload: Record<string, Object> = {};
        diaryPayload['diaryId'] = rowId;
        diaryPayload['date'] = diary.date;
        EventBus.emit(EventBus.EventNames.DIARY_SAVED, diaryPayload);
        this.state = GestureState.CONFIRMED;
        AppStorage.setOrCreate('captureState', 'done');
        return true;
      }
      return false;
    } catch (err) { hilog.error(0x0000, TAG, 'ConfirmSave failed: %{public}s', (err as BusinessError).message); return false; }
  }

  /** User discards -> clear state */
  discard(): void { this.photoUri = ''; this.suggestion = null; this.state = GestureState.IDLE; AppStorage.setOrCreate('captureState', 'idle'); }
  setEnabled(enabled: boolean): void { this.isEnabled = enabled; }

  private getTodayDate(): string { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`; }
  private formatCurrentDate(): string {
    const d = new Date(); const weekdays = ['日','一','二','三','四','五','六'];
    return `${d.getFullYear()}年${d.getMonth()+1}月${d.getDate()}日 星期${weekdays[d.getDay()]}`;
  }
}
