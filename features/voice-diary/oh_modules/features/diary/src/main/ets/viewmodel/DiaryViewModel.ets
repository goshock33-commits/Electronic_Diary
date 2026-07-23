// agentID: DEV-006
// agentID: DEV-004 (M14 碰传日记 backend)
// fix: DEV-012 · T-M01 一天多篇：save 契约改造（editingId 按 id 更新 / 缺省永远 insert 新行，消除同日与跨天覆盖）；
//   新增 queryById / queryListByDate / getDiaryWithRelationsById（HUI-045 契约）。
// File: DiaryViewModel.ets
// Task: M03 Diary business logic - AppStorage + EventBus fixes + check_in linking
// Architecture: ARC-001 4.1 DiaryDao / 4.5 EventBus / S2 diary management
// Changes: AppStorage calendarMarkedDates, EventBus flat payload, getMonthMarkedDates links check_in

import { DiaryDao } from '@ohos/shared';
import { TodoDao } from '@ohos/shared';
import { HappyThingDao } from '@ohos/shared';
import { CheckInDao } from '@ohos/shared';
import { Diary } from '@ohos/shared';
import { TodoItem } from '@ohos/shared';
import { HappyThing } from '@ohos/shared';
import { EventBus } from '@ohos/shared';
import { ImageUtils } from '@ohos/shared';
// M14(DEV-004): 碰传日记（碰传图）—— 序列化/导入委托 KnockShareService 载荷引擎。
import { KnockShareService } from '@ohos/shared';
import type { DiaryBundle } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'DiaryViewModel';

/**
 * Diary with associated data for detail display.
 */
export interface DiaryWithRelations {
  diary: Diary;
  todos: TodoItem[];
  happyThings: HappyThing[];
}

/**
 * DiaryViewModel - Manages diary CRUD operations with image attachment support.
 * Maintains calendar marker data (which dates have diary entries).
 * Linked with check_in table for comprehensive calendar marking.
 */
export class DiaryViewModel {
  private currentDiary: Diary | null = null;
  private datesWithDiary: Set<string> = new Set();
  private currentYear: number = 0;
  private currentMonth: number = 0;
  // DEV-WIRE-DIARY: 记录 init 的目标日期，保存新日记时以此为准（而非默认今天），保证按选中日落库
  private targetDate: string = '';
  // FIX-DIARY: 最近一次 save 失败的真实错误信息（供页面 toast 诊断，如 UNIQUE / no such column）
  private lastSaveError: string = '';

  /**
   * Initialize for a target date. Loads the diary if it exists.
   * fix: DEV-012 · 一天多篇后 currentDiary = 该日最新一篇（DiaryDao.queryByDate 新语义）。
   */
  async init(date: string): Promise<void> {
    try {
      this.targetDate = date;
      this.currentDiary = await DiaryDao.queryByDate(date);
      hilog.info(0x0000, TAG, 'Init: date=%{public}s, hasDiary=%{public}s',
        date, String(this.currentDiary !== null));
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Init failed: %{public}s', error.message);
    }
  }

  /**
   * Load calendar marker data for a specific month.
   * Merges diary dates with check-in dates for comprehensive calendar marking.
   * @returns Array of date strings that have diary entries or check-in records.
   */
  async loadMonthDates(year: number, month: number): Promise<string[]> {
    try {
      this.currentYear = year;
      this.currentMonth = month;

      // Query both diary dates and check-in dates in parallel
      const dateResults = await Promise.all([
        DiaryDao.queryDatesWithDiary(year, month),
        this.getCheckInDatesForMonth(year, month)
      ]);
      const diaryDates: string[] = dateResults[0];
      const checkInDates: string[] = dateResults[1];

      // Merge unique dates from both sources
      const mergedDates = new Set<string>(diaryDates.concat(checkInDates));
      this.datesWithDiary = mergedDates;

      const markedDates = Array.from(mergedDates);
      // Update AppStorage for cross-component calendar access
      AppStorage.setOrCreate('calendarMarkedDates', markedDates);

      hilog.info(0x0000, TAG, 'LoadMonthDates: year=%{public}d month=%{public}d, diaryDates=%{public}d, checkInDates=%{public}d, total=%{public}d',
        year, month, diaryDates.length, checkInDates.length, markedDates.length);
      return markedDates;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'LoadMonthDates failed: %{public}s', error.message);
      return [];
    }
  }

  /**
   * Get check-in dates for a given month (for calendar marking linkage).
   * Uses CheckInDao.queryByMonth and extracts date strings.
   */
  private async getCheckInDatesForMonth(year: number, month: number): Promise<string[]> {
    try {
      const records = await CheckInDao.queryByMonth(year, month);
      const dates: string[] = [];
      for (let i = 0; i < records.length; i++) {
        dates.push(records[i].date);
      }
      return dates;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'GetCheckInDates failed: %{public}s', error.message);
      return [];
    }
  }

  /**
   * Save a diary entry.
   * fix: DEV-012 · 一天多篇保存契约：
   *   - editingId 提供且 >0 → 按 id 更新该篇（保留其 date / created_at）；id 不存在则告警后降级为新增。
   *   - editingId 缺省 → **永远 insert 新行**（不再查同日已有后覆盖 → 连根消除「同日覆盖」与「跨天覆盖前一篇」路径）。
   * 签名向后兼容：既有 UI 调用 save(content, images, title, mood) 不变（可选参数追加在末尾）。
   * 成功 emit DIARY_SAVED（payload: diaryId + date）。
   * DEV-WIRE-DIARY: linkedTodoIds 为可选关联待办 id（待办本身按 date 关联，此处仅接受入参、不改 TodoDao 语义）。
   */
  async save(content: string, imageUris: string[], title?: string, mood?: string,
    linkedTodoIds?: number[], editingId?: number): Promise<boolean> {
    this.lastSaveError = '';
    try {
      let diary: Diary | null = null;
      if (editingId !== undefined && editingId > 0) {
        diary = await DiaryDao.queryById(editingId);
        if (diary === null) {
          hilog.warn(0x0000, TAG, 'Save: editingId=%{public}d not found, fallback to insert', editingId);
        }
      }
      if (diary === null) {
        diary = new Diary();
        // 优先使用 init 传入的目标日期，未初始化时兜底今天
        diary.date = this.targetDate.length > 0 ? this.targetDate : this.getCurrentDate();
      }
      diary.content = content;
      diary.setImageList(imageUris);
      if (title !== undefined) {
        diary.title = title;
      }
      if (mood !== undefined) {
        diary.mood = mood;
      }
      diary.updated_at = Date.now();

      if (diary.id > 0) {
        await DiaryDao.update(diary);
      } else {
        const rowId = await DiaryDao.insert(diary);
        diary.id = rowId;
      }
      this.currentDiary = diary;

      // linkedTodoIds 目前仅记录日志（待办按日期关联，无 join 表需落库）
      if (linkedTodoIds && linkedTodoIds.length > 0) {
        hilog.info(0x0000, TAG, 'Diary linked todos: count=%{public}d', linkedTodoIds.length);
      }

      // Update in-memory date set and sync to AppStorage
      this.datesWithDiary.add(diary.date);
      const markedDates = Array.from(this.datesWithDiary);
      AppStorage.setOrCreate('calendarMarkedDates', markedDates);

      // Emit flat payload via new EventBus API
      const savedPayload: Record<string, Object> = {};
      savedPayload['diaryId'] = diary.id;
      savedPayload['date'] = diary.date;
      EventBus.emit(EventBus.EventNames.DIARY_SAVED, savedPayload);

      hilog.info(0x0000, TAG, 'Diary saved: date=%{public}s id=%{public}d', diary.date, diary.id);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      // FIX-DIARY: 暴露真实 DAO 错误供页面 toast 回报（诊断用）
      this.lastSaveError = error.message;
      hilog.error(0x0000, TAG, 'Save failed: %{public}s', error.message);
      return false;
    }
  }

  /** FIX-DIARY: 供页面读取最近一次保存失败的真实错误信息（诊断用） */
  getLastSaveError(): string {
    return this.lastSaveError;
  }

  /**
   * Query diary by exact date.
   * fix: DEV-012 · 一天多篇后语义为「该日最新一篇或 null」；该日全部请用 queryListByDate。
   */
  async queryByDate(date: string): Promise<Diary | null> {
    return await DiaryDao.queryByDate(date);
  }

  /**
   * fix: DEV-012 · 该日全部篇目（created_at DESC，最新在前）。HUI-045 列表页契约。
   * 异常兜底空数组。
   */
  async queryListByDate(date: string): Promise<Diary[]> {
    try {
      return await DiaryDao.queryListByDate(date);
    } catch (err) {
      hilog.error(0x0000, TAG, 'queryListByDate failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  /**
   * fix: DEV-012 · 按 id 查单篇（编辑页回填 / 详情页按篇定位契约）。异常兜底 null。
   */
  async queryById(id: number): Promise<Diary | null> {
    try {
      return await DiaryDao.queryById(id);
    } catch (err) {
      hilog.error(0x0000, TAG, 'queryById failed: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  /**
   * DEV-WIRE-DIARY: 查询全部日记（日记轮播「所有日记」入口用），按日期倒序。
   * 委托 DiaryDao.queryAll；异常兜底空数组（真实空态，非假数据）。
   */
  async getAllDiaries(): Promise<Diary[]> {
    try {
      return await DiaryDao.queryAll();
    } catch (err) {
      hilog.error(0x0000, TAG, 'getAllDiaries failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  /**
   * fix: HUI-FRONTEND-1 · 按 id 删除日记（日记轮播长按删除契约）。
   * 委托 DiaryDao.deleteById；成功后 emit DIARY_SAVED 驱动跨页刷新（与 save 同事件契约）。
   */
  async deleteDiary(id: number): Promise<boolean> {
    try {
      const ok: boolean = await DiaryDao.deleteById(id);
      if (ok) {
        const payload: Record<string, Object> = {};
        payload['diaryId'] = id;
        payload['deleted'] = true;
        EventBus.emit(EventBus.EventNames.DIARY_SAVED, payload);
      }
      return ok;
    } catch (err) {
      hilog.error(0x0000, TAG, 'deleteDiary failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * DEV-WIRE-DIARY: 查询某日某类型的真实待办（编辑页「关联待办」选择器用），委托 TodoDao.queryByDateAndType。
   * 异常兜底空数组。
   */
  async getTodosForDate(date: string, type: string): Promise<TodoItem[]> {
    try {
      return await TodoDao.queryByDateAndType(date, type);
    } catch (err) {
      hilog.error(0x0000, TAG, 'getTodosForDate failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  /**
   * Query diaries for a month.
   */
  async queryByMonth(year: number, month: number): Promise<Diary[]> {
    return await DiaryDao.queryByMonth(year, month);
  }

  /**
   * Search diary content by keyword.
   */
  async search(keyword: string): Promise<Diary[]> {
    return await DiaryDao.search(keyword);
  }

  /**
   * Get diary with associated todos and happy things for the detail page.
   * fix: DEV-012 · 一天多篇后本方法取「该日最新一篇」；按篇定位请用 getDiaryWithRelationsById。
   */
  async getDiaryWithRelations(date: string): Promise<DiaryWithRelations | null> {
    try {
      const diary = await DiaryDao.queryByDate(date);
      if (!diary) {
        return null;
      }
      const relationResults = await Promise.all([
        TodoDao.queryByDateAndType(date, 'today'),
        HappyThingDao.queryByDate(date)
      ]);
      const todos: TodoItem[] = relationResults[0];
      const happyThings: HappyThing[] = relationResults[1];
      const result: DiaryWithRelations = { diary, todos, happyThings };
      return result;
    } catch (err) {
      hilog.error(0x0000, TAG, 'GetDiaryWithRelations failed: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  /**
   * fix: DEV-012 · 按 id 取某一篇及其关联（一天多篇详情页契约，HUI-045 用）。
   * 关联 todos / happyThings 仍按该篇的 date 查（按日关联模型不变，同日各篇共享当日关联）。
   */
  async getDiaryWithRelationsById(id: number): Promise<DiaryWithRelations | null> {
    try {
      const diary = await DiaryDao.queryById(id);
      if (!diary) {
        return null;
      }
      const relationResults = await Promise.all([
        TodoDao.queryByDateAndType(diary.date, 'today'),
        HappyThingDao.queryByDate(diary.date)
      ]);
      const todos: TodoItem[] = relationResults[0];
      const happyThings: HappyThing[] = relationResults[1];
      const result: DiaryWithRelations = { diary, todos, happyThings };
      return result;
    } catch (err) {
      hilog.error(0x0000, TAG, 'getDiaryWithRelationsById failed: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  /**
   * Attach images to the current diary entry.
   */
  async attachImages(uris: string[]): Promise<void> {
    if (this.currentDiary) {
      const current = this.currentDiary.getImageList();
      this.currentDiary.setImageList(current.concat(uris));
      if (this.currentDiary.id > 0) {
        await DiaryDao.update(this.currentDiary);
      }
    }
  }

  /**
   * Remove an image from the current diary.
   */
  async removeImage(uri: string): Promise<void> {
    if (this.currentDiary) {
      const current = this.currentDiary.getImageList();
      const filtered = current.filter((u: string) => u !== uri);
      this.currentDiary.setImageList(filtered);
      if (this.currentDiary.id > 0) {
        await DiaryDao.update(this.currentDiary);
      }
      // Delete the physical file
      ImageUtils.deleteImage(uri);
    }
  }

  /** Get current diary */
  getCurrentDiary(): Diary | null {
    return this.currentDiary;
  }

  // ==================== M14 碰传日记（碰传图）====================

  /**
   * M14: 序列化某日日记为碰传载荷 JSON（含图片引用）。委托 KnockShareService 载荷引擎。
   * 该日无日记返回 null。ShareViewModel 传输阶段（scenario=image）取此载荷经软总线发对端。
   */
  async exportDiaryBundle(date: string): Promise<string | null> {
    return KnockShareService.exportDiaryBundle(date);
  }

  /**
   * M14: 导入碰传日记载荷并落库。fix: DEV-012 · 一天多篇：逐篇 insert（date+created_at 幂等去重，见 KnockShareService）。
   * 成功后 emit DIARY_SAVED（含 diaryId + date），触发首页/日历刷新（与 save() 的事件契约一致）。
   * @returns 是否成功落库。
   */
  async importDiaryBundle(json: string): Promise<boolean> {
    const id = await KnockShareService.importDiaryBundle(json);
    if (id > 0) {
      let date = '';
      try {
        const bundle = JSON.parse(json) as DiaryBundle;
        date = bundle.date;
      } catch (_e) {
        date = '';
      }
      if (date.length > 0) {
        this.datesWithDiary.add(date);
        AppStorage.setOrCreate('calendarMarkedDates', Array.from(this.datesWithDiary));
      }
      const payload: Record<string, Object> = {};
      payload['diaryId'] = id;
      payload['date'] = date;
      EventBus.emit(EventBus.EventNames.DIARY_SAVED, payload);
      hilog.info(0x0000, TAG, 'importDiaryBundle ok: date=%{public}s id=%{public}d', date, id);
      return true;
    }
    hilog.warn(0x0000, TAG, 'importDiaryBundle rejected (schema/parse)');
    return false;
  }

  /** Get current date (format YYYY-MM-DD) */
  getCurrentDate(): string {
    const now = new Date();
    const y = now.getFullYear();
    const m = String(now.getMonth() + 1).padStart(2, '0');
    const d = String(now.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }

  /** Check if a specific date has a diary entry or check-in */
  hasDiaryOnDate(date: string): boolean {
    return this.datesWithDiary.has(date);
  }

  /** Get all dates with diary entries for the loaded month */
  getDatesWithDiary(): string[] {
    return Array.from(this.datesWithDiary);
  }

  async refresh(): Promise<void> {
    // Refresh is context-dependent - caller provides the date
  }
}
