// <!-- agentID: DEV-009 -->
// File: HappyThingViewModel.ets
// Task: M04 Happy thing CRUD - add/delete/query by date
// Architecture: ARC-001 4.1 HappyThingDao + 4.5 EventBus
// Changes: AppStorage happyThings + EventBus SECTION_CHANGED on add/delete
// fix: DEV-009

import { HappyThingDao } from '@ohos/shared';
import { HappyThing } from '@ohos/shared';
import { EventBus } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'HappyThingViewModel';

/**
 * HappyThingViewModel - Manages happy things (开心的事) for a given date.
 */
export class HappyThingViewModel {
  private items: HappyThing[] = [];
  private currentDate: string = '';

  async init(date: string): Promise<void> {
    this.currentDate = date;
    try {
      this.items = await HappyThingDao.queryByDate(date);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Init failed: %{public}s', error.message);
    }
  }

  async add(content: string, emojiId: string, image?: string): Promise<HappyThing | null> {
    try {
      const item = new HappyThing(this.currentDate, content, emojiId);
      if (image) {
        item.image = image;
      }
      const rowId = await HappyThingDao.insert(item);
      if (rowId > 0) {
        item.id = rowId;
        this.items.push(item);
        // AppStorage: write happyThings list
        AppStorage.setOrCreate('happyThings', this.items);
        // EventBus: notify section changed (§8.3-① Record payload: empty literal + bracket assignment)
        const payload: Record<string, Object> = {};
        payload['sectionKey'] = 'happy';
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
      await HappyThingDao.delete(id);
      this.items = this.items.filter((h: HappyThing) => h.id !== id);
      // AppStorage: write updated happyThings list
      AppStorage.setOrCreate('happyThings', this.items);
      // EventBus: notify section changed (§8.3-① Record payload: empty literal + bracket assignment)
      const payload: Record<string, Object> = {};
      payload['sectionKey'] = 'happy';
      payload['action'] = 'delete';
      EventBus.emit(EventBus.EventNames.SECTION_CHANGED, payload);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Delete failed: %{public}s', error.message);
      return false;
    }
  }

  getItems(): HappyThing[] {
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
