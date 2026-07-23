// <!-- agentID: DEV-009 -->
// File: SectionViewModel.ets
// Task: M06 Section management - sort, visibility toggle, custom titles
// Architecture: ARC-001 4.1 SectionConfigDao + 4.5 EventBus
// Changes: Replaced raw SQL with SectionConfigDao + AppStorage sectionConfigs writes
// fix: DEV-009

import { EventBus } from '@ohos/shared';
import { SectionConfigDao, type SectionConfig } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'SectionViewModel';

/**
 * Default section configurations (used on first run when DB is empty).
 * Mirrors SectionConfig interface from SectionConfigDao.
 */
const DEFAULT_SECTIONS: SectionConfig[] = [
  { id: 0, sectionKey: 'today_todo', title: '今日待办', isVisible: 1, sortOrder: 1 },
  { id: 0, sectionKey: 'tomorrow_todo', title: '明日待办', isVisible: 1, sortOrder: 2 },
  { id: 0, sectionKey: 'extra', title: '多做的事', isVisible: 1, sortOrder: 3 },
  { id: 0, sectionKey: 'happy', title: '开心的事', isVisible: 1, sortOrder: 4 },
  { id: 0, sectionKey: 'extracted', title: '提取任务', isVisible: 1, sortOrder: 5 }
];

/**
 * SectionViewModel - Manages the 5 customizable section configurations.
 * Handles: sorting, visibility toggle, custom title editing, persistence.
 *
 * M06 refactor: Replaced inline raw SQL (querySqlSync/insertSync/updateSync) with
 * SectionConfigDao (async RelationalStore Promise APIs). Fixed double beginTransaction bug.
 */
export class SectionViewModel {
  private sections: SectionConfig[] = [];

  /**
   * Initialize section configs. Loads from database or creates defaults.
   */
  async init(): Promise<void> {
    try {
      this.sections = await SectionConfigDao.loadAll();
      if (this.sections.length === 0) {
        // First run: insert default configs
        this.sections = [...DEFAULT_SECTIONS];
        await SectionConfigDao.saveAll(this.sections);
        // Re-load to get generated IDs
        this.sections = await SectionConfigDao.loadAll();
      }
      this.sections.sort((a, b) => a.sortOrder - b.sortOrder);
      // AppStorage: publish initial section configs
      AppStorage.setOrCreate('sectionConfigs', this.sections);
      hilog.info(0x0000, TAG, 'Sections initialized: %{public}d sections', this.sections.length);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, 'Init failed: %{public}s', error.message);
      this.sections = [...DEFAULT_SECTIONS];
      // AppStorage: publish fallback configs so UI is not empty on DB init failure
      AppStorage.setOrCreate('sectionConfigs', this.sections);
    }
  }

  /**
   * Get all section configs sorted by sortOrder (visible only).
   */
  getSections(): SectionConfig[] {
    return this.sections.filter((s: SectionConfig) => s.isVisible === 1);
  }

  /**
   * Get all section configs including hidden ones.
   */
  getAllSections(): SectionConfig[] {
    return [...this.sections];
  }

  /**
   * Toggle visibility of a section.
   */
  async toggleVisibility(sectionKey: string): Promise<void> {
    const section = this.sections.find((s: SectionConfig) => s.sectionKey === sectionKey);
    if (section) {
      section.isVisible = section.isVisible === 1 ? 0 : 1;
      await SectionConfigDao.saveAll(this.sections);
      // AppStorage: publish updated configs
      AppStorage.setOrCreate('sectionConfigs', this.sections);
      // EventBus: notify section visibility changed (§8.3-① Record payload: empty literal + bracket assignment)
      const payload: Record<string, Object> = {};
      payload['sectionKey'] = sectionKey;
      payload['isVisible'] = section.isVisible;
      EventBus.emit(EventBus.EventNames.SECTION_CHANGED, payload);
    }
  }

  /**
   * Update sort order for reordering sections.
   */
  async updateSortOrder(orderedKeys: string[]): Promise<void> {
    orderedKeys.forEach((key: string, index: number) => {
      const section = this.sections.find((s: SectionConfig) => s.sectionKey === key);
      if (section) {
        section.sortOrder = index + 1;
      }
    });
    this.sections.sort((a, b) => a.sortOrder - b.sortOrder);
    await SectionConfigDao.saveAll(this.sections);
    // AppStorage: publish updated configs
    AppStorage.setOrCreate('sectionConfigs', this.sections);
    // EventBus: notify reorder (§8.3-① Record payload: empty literal + bracket assignment)
    const payload: Record<string, Object> = {};
    payload['action'] = 'reorder';
    EventBus.emit(EventBus.EventNames.SECTION_CHANGED, payload);
  }

  /**
   * Update a section's custom title.
   */
  async updateTitle(sectionKey: string, newTitle: string): Promise<boolean> {
    const section = this.sections.find((s: SectionConfig) => s.sectionKey === sectionKey);
    if (section && newTitle.trim().length > 0) {
      section.title = newTitle.trim();
      await SectionConfigDao.saveAll(this.sections);
      // AppStorage: publish updated configs
      AppStorage.setOrCreate('sectionConfigs', this.sections);
      // EventBus: notify title changed (§8.3-① Record payload: empty literal + bracket assignment)
      const payload: Record<string, Object> = {};
      payload['sectionKey'] = sectionKey;
      payload['title'] = newTitle;
      EventBus.emit(EventBus.EventNames.SECTION_CHANGED, payload);
      return true;
    }
    return false;
  }

  /**
   * Get a section config by key.
   */
  getSectionByKey(key: string): SectionConfig | undefined {
    return this.sections.find((s: SectionConfig) => s.sectionKey === key);
  }
}
