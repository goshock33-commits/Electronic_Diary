// <!-- agentID: DEV-009 -->
// File: ExtraThingViewModel.ets
// Task: M05 Extra thing CRUD - add/delete/query by date
// Architecture: ARC-001 4.1 ExtraThingDao + 4.5 EventBus
// Changes: EventBus SECTION_CHANGED on add/delete (no independent AppStorage key)
// fix: DEV-009

import { ExtraThingDao } from '@ohos/shared';
import { ExtraThing } from '@ohos/shared';
import { EventBus } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'ExtraThingViewModel';

/**
 * ExtraThingViewModel - Manages extra things (多做的事) for a given date.
 */
export class ExtraThingViewModel {
  private items: ExtraThing[] = [];
  private currentDate: string = '';

  async init(date: string): Promise<void> {
    this.currentDate = date;
    try {
      this.items = await ExtraThingDao.queryByDate(date);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Init failed: %{public}s', error.message);
    }
  }

  async add(content: string): Promise<ExtraThing | null> {
    try {
      const item = new ExtraThing(this.currentDate, content);
      const rowId = await ExtraThingDao.insert(item);
      if (rowId > 0) {
        item.id = rowId;
        this.items.push(item);
        // EventBus: notify section changed (extra section) (§8.3-① Record payload: empty literal + bracket assignment)
        const payload: Record<string, Object> = {};
        payload['sectionKey'] = 'extra';
        payload['action'] = 'add';
        EventBus.emit(EventBus.EventNames.SECTION_CHANGED, payload);
        return item;
      }
      return null;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Add failed: %{public}s', error.message);
      return null;
    }
  }

  async delete(id: number): Promise<boolean> {
    try {
      await ExtraThingDao.delete(id);
      this.items = this.items.filter((e: ExtraThing) => e.id !== id);
      // EventBus: notify section changed (extra section) (§8.3-① Record payload: empty literal + bracket assignment)
      const payload: Record<string, Object> = {};
      payload['sectionKey'] = 'extra';
      payload['action'] = 'delete';
      EventBus.emit(EventBus.EventNames.SECTION_CHANGED, payload);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Delete failed: %{public}s', error.message);
      return false;
    }
  }

  getItems(): ExtraThing[] {
    return this.items;
  }

  getCount(): number {
    return this.items.length;
  }

  async refresh(): Promise<void> {
    if (this.currentDate.length > 0) {
      await this.init(this.currentDate);
    }
  }
}
