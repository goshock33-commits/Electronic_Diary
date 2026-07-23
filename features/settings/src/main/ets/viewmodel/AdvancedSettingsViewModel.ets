// <!-- agentID: DEV-018 -->
// fix: DEV-013 · T-B01 全库备份含照片：exportData/importData 委托 KnockShareService 统一引擎
//   （13 表通用 SQL dump + 照片收集/重建），废弃本 VM 自研的 SerializedTableData 列式格式，
//   避免与主备份路径分叉导致格式不互通。
// 文件: AdvancedSettingsViewModel.ets
// 任务: T029b 设置业务逻辑（高级）- 数据导出打包 + 导入恢复 + AES加密
// 关联架构: ARC-001 4.4 BackupUtils/EncryptionUtils / 非功能需求安全 / 需求 9.6 数据导出导入
// Skill 参考: frontend-design / ui-ux-pro-max
// SDK: HarmonyOS 6.1.1 (API 24)

import { KnockShareService, BackupUtils, type BackupFileInfo, EventBus } from '@ohos/shared';
import type { BackupExportResult, BackupImportResult } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';

const TAG = 'AdvancedSettingsViewModel';

/** Backup progress information */
export interface BackupProgress {
  current: number;
  total: number;
  message: string;
}

/**
 * AdvancedSettingsViewModel - Handles data export/import.
 * fix: DEV-013 · Now delegates to KnockShareService (unified 13-table SQL dump + photo collection/rebuild),
 *   replacing the prior custom per-table columnar serializer.
 * Export flow: KnockShareService.exportFullBackup → .ediary.zip (with real photos).
 * Import flow: KnockShareService.importFullBackup → restore tables + rebuild image paths.
 */
export class AdvancedSettingsViewModel {

  // ==================== Data Export ====================

  /**
   * Export all data to an encrypted backup file (with real photo files).
   * fix: DEV-013 · Delegates to KnockShareService.exportFullBackup.
   *
   * @param baseDir Application files directory (e.g., getContext().filesDir)
   * @param onProgress Optional progress callback
   * @returns Path to the exported backup file, or null on failure
   */
  async exportData(
    baseDir: string,
    onProgress?: (progress: BackupProgress) => void
  ): Promise<string | null> {
    try {
      this.emitBackupStarted();
      onProgress?.({ current: 0, total: 3, message: '开始导出数据...' });

      onProgress?.({ current: 1, total: 3, message: '读取数据库...' });
      const result: BackupExportResult | null = await KnockShareService.exportFullBackup(baseDir);

      if (result === null) {
        hilog.error(0xFF00, TAG, 'Export returned null');
        return null;
      }

      onProgress?.({ current: 2, total: 3,
        message: '已导出 ' + result.tableCount + ' 表、' + result.imageCount + ' 张图片' });
      onProgress?.({ current: 3, total: 3, message: '导出完成' });
      this.emitBackupCompleted(result.path);
      hilog.info(0xFF00, TAG, 'Data export complete: %{public}s (tables=%{public}d, images=%{public}d)',
        result.path, result.tableCount, result.imageCount);
      return result.path;
    } catch (err) {
      hilog.error(0xFF00, TAG, 'exportData failed: %{public}s', (err as Error).message);
      throw new Error(`AdvancedSettingsViewModel exportData failed: ${(err as Error).message}`);
    }
  }

  // ==================== Data Import ====================

  /**
   * Import data from a backup file (restores all 13 tables + rebuilds photo paths).
   * fix: DEV-013 · Delegates to KnockShareService.importFullBackup.
   *
   * @param baseDir Application files directory (for sandbox image rebuilding).
   * @param filePath Path to the backup file (.ediary.zip)
   * @param onProgress Optional progress callback
   * @returns true if import succeeded
   */
  async importData(
    baseDir: string,
    filePath: string,
    onProgress?: (progress: BackupProgress) => void
  ): Promise<boolean> {
    try {
      this.emitRestoreStarted();
      onProgress?.({ current: 0, total: 3, message: '开始导入数据...' });

      onProgress?.({ current: 1, total: 3, message: '解密解压数据...' });
      const result: BackupImportResult | null = await KnockShareService.importFullBackup(baseDir, filePath);

      if (result === null) {
        hilog.error(0xFF00, TAG, 'Import returned null');
        return false;
      }

      onProgress?.({ current: 2, total: 3,
        message: '已恢复 ' + result.tableCount + ' 表、' + result.imageCount + ' 张图片' });
      onProgress?.({ current: 3, total: 3, message: '导入完成' });
      this.emitRestoreCompleted();
      hilog.info(0xFF00, TAG, 'Data import complete: tables=%{public}d, images=%{public}d',
        result.tableCount, result.imageCount);
      return true;
    } catch (err) {
      hilog.error(0xFF00, TAG, 'importData failed: %{public}s', (err as Error).message);
      throw new Error(`AdvancedSettingsViewModel importData failed: ${(err as Error).message}`);
    }
  }

  /**
   * Validate a backup file before importing (version compatibility check).
   *
   * @param filePath Path to the backup file
   * @returns true if the backup is valid and compatible
   */
  async validateBackupFile(filePath: string): Promise<boolean> {
    try {
      return await BackupUtils.validateBackup(filePath);
    } catch (err) {
      hilog.error(0xFF00, TAG, 'validateBackupFile failed: %{public}s', (err as Error).message);
      return false;
    }
  }

  /**
   * List all backup files in the backup directory.
   *
   * @param baseDir Application files directory
   * @returns Array of backup file info
   */
  listBackupFiles(baseDir: string): BackupFileInfo[] {
    try {
      return BackupUtils.listBackups(baseDir);
    } catch (err) {
      hilog.error(0xFF00, TAG, 'listBackupFiles failed: %{public}s', (err as Error).message);
      return [];
    }
  }

  /**
   * Delete a backup file.
   *
   * @param filePath Path to the backup file to delete
   * @returns true if deleted successfully
   */
  deleteBackupFile(filePath: string): boolean {
    try {
      return BackupUtils.deleteBackup(filePath);
    } catch (err) {
      hilog.error(0xFF00, TAG, 'deleteBackupFile failed: %{public}s', (err as Error).message);
      return false;
    }
  }

  /**
   * Get the total number of tables included in backup.
   */
  getTableCount(): number {
    return KnockShareService.tableCount();
  }

  // ==================== Event Emitters ====================

  private emitBackupStarted(): void {
    const payload: Record<string, Object> = {};
    payload['timestamp'] = Date.now();
    EventBus.emit(EventBus.EventNames.BACKUP_STARTED, payload);
    hilog.debug(0xFF00, TAG, 'Emitted event:backup:started via EventBus');
  }

  private emitBackupCompleted(filePath: string): void {
    const payload: Record<string, Object> = {};
    payload['filePath'] = filePath;
    payload['timestamp'] = Date.now();
    EventBus.emit(EventBus.EventNames.BACKUP_COMPLETED, payload);
    hilog.debug(0xFF00, TAG, 'Emitted event:backup:completed via EventBus');
  }

  private emitRestoreStarted(): void {
    const payload: Record<string, Object> = {};
    payload['timestamp'] = Date.now();
    EventBus.emit(EventBus.EventNames.RESTORE_STARTED, payload);
    hilog.debug(0xFF00, TAG, 'Emitted event:restore:started via EventBus');
  }

  private emitRestoreCompleted(): void {
    const payload: Record<string, Object> = {};
    payload['timestamp'] = Date.now();
    EventBus.emit(EventBus.EventNames.RESTORE_COMPLETED, payload);
    hilog.debug(0xFF00, TAG, 'Emitted event:restore:completed via EventBus');
  }
}
