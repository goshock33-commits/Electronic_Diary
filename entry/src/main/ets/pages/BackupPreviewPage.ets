// 页面：备份导入预览（选择性恢复 + 合并/覆盖模式）
// 从设置页 pickFileAndImport 解析成功后 router.pushUrl 跳入，BackupContent 通过 AppStorage 传递。
// 用户逐表勾选 + 选择合并/覆盖 → 确认后调 KnockShareService.restoreFromContent 执行恢复。
// 开发范式：ArkTS 声明式开发范式
// 崩溃防范：§9 @StorageLink tokens 判空回退；无字段初值 $r()；无 getter-in-build。

import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper, RADIUS, SPACING, TYPO, KnockShareService, type BackupContent, type BackupMeta, type BackupImportResult } from '@ohos/shared';
import { router, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

const TAG: string = 'BackupPreviewPage';

interface SerializedBackup {
  meta: BackupMeta;
  tableMap: Record<string, string>;
  extraFiles: Record<string, string>;
}

interface TableDisplayInfo {
  tableName: string;
  displayName: string;
  rowCount: number;
  checked: boolean;
}

const TABLE_DISPLAY_NAMES: Record<string, string> = {
  'diary': '日记本',
  'diary_entry': '日记条目',
  'check_in': '打卡记录',
  'todo': '待办事项',
  'happy_thing': '开心事',
  'extra_thing': '多做的事',
  'extracted_task': '提取任务',
  'quote': '名言',
  'pomodoro_session': '番茄钟',
  'section_config': '分区配置',
  'app_settings': '应用设置',
  'custom_emoji': '自定义表情',
  'chat_message': '聊天记录'
};

@Entry
@Component
struct BackupPreviewPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  @State tableList: TableDisplayInfo[] = [];
  @State importMode: string = 'merge';
  @State isRestoring: boolean = false;
  @State allChecked: boolean = true;

  aboutToAppear(): void {
    this.loadBackupContent();
  }

  private loadBackupContent(): void {
    const contentStr: string | undefined = AppStorage.get<string>('backup_preview_content');
    if (contentStr === undefined || contentStr.length === 0) {
      hilog.error(0x0000, TAG, 'No backup content in AppStorage');
      router.back();
      return;
    }
    try {
      const parsed: SerializedBackup = JSON.parse(contentStr) as SerializedBackup;
      const tableMap: Record<string, string> = parsed.tableMap;
      const tables: string[] = Object.keys(tableMap);
      tables.sort();
      const list: TableDisplayInfo[] = [];
      for (let i: number = 0; i < tables.length; i++) {
        const tName: string = tables[i];
        const json: string = tableMap[tName];
        let rowCount: number = 0;
        try {
          const rows: Object[] = JSON.parse(json) as Object[];
          rowCount = rows !== null ? rows.length : 0;
        } catch (_e) {
          rowCount = 0;
        }
        const display: string = TABLE_DISPLAY_NAMES[tName] !== undefined ? TABLE_DISPLAY_NAMES[tName] : tName;
        list.push({ tableName: tName, displayName: display, rowCount: rowCount, checked: true });
      }
      this.tableList = list;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Failed to parse backup content: %{public}s', (err as Error).message);
      router.back();
    }
  }

  private toggleAll(checked: boolean): void {
    const updated: TableDisplayInfo[] = [];
    for (let i: number = 0; i < this.tableList.length; i++) {
      const item: TableDisplayInfo = this.tableList[i];
      updated.push({ tableName: item.tableName, displayName: item.displayName, rowCount: item.rowCount, checked: checked });
    }
    this.tableList = updated;
    this.allChecked = checked;
  }

  private toggleItem(index: number, checked: boolean): void {
    const updated: TableDisplayInfo[] = [];
    for (let i: number = 0; i < this.tableList.length; i++) {
      const item: TableDisplayInfo = this.tableList[i];
      if (i === index) {
        updated.push({ tableName: item.tableName, displayName: item.displayName, rowCount: item.rowCount, checked: checked });
      } else {
        updated.push(item);
      }
    }
    this.tableList = updated;
    let allOn: boolean = true;
    for (let i: number = 0; i < updated.length; i++) {
      if (!updated[i].checked) {
        allOn = false;
        break;
      }
    }
    this.allChecked = allOn;
  }

  private getSelectedTables(): string[] {
    const result: string[] = [];
    for (let i: number = 0; i < this.tableList.length; i++) {
      if (this.tableList[i].checked) {
        result.push(this.tableList[i].tableName);
      }
    }
    return result;
  }

  private getSelectedRowCount(): number {
    let total: number = 0;
    for (let i: number = 0; i < this.tableList.length; i++) {
      if (this.tableList[i].checked) {
        total += this.tableList[i].rowCount;
      }
    }
    return total;
  }

  private async confirmRestore(): Promise<void> {
    const selected: string[] = this.getSelectedTables();
    if (selected.length === 0) {
      promptAction.showToast({ message: '请至少选择一项数据', duration: 2000 });
      return;
    }
    this.isRestoring = true;
    try {
      const contentStr: string | undefined = AppStorage.get<string>('backup_preview_content');
      if (contentStr === undefined) {
        promptAction.showToast({ message: '导入失败，请重试', duration: 2000 });
        this.isRestoring = false;
        return;
      }
      // 反序列化：tableMap 直接用，extraFiles 从 base64 还原为 Uint8Array
      const parsed: SerializedBackup = JSON.parse(contentStr) as SerializedBackup;
      const tableMap: Map<string, string> = new Map<string, string>();
      const rawTableMap: Record<string, string> = parsed.tableMap;
      const tableKeys: string[] = Object.keys(rawTableMap);
      for (let i: number = 0; i < tableKeys.length; i++) {
        tableMap.set(tableKeys[i], rawTableMap[tableKeys[i]]);
      }
      const extraFiles: Map<string, Uint8Array> = new Map<string, Uint8Array>();
      const rawExtra: Record<string, string> = parsed.extraFiles;
      if (rawExtra !== undefined && rawExtra !== null) {
        const extraKeys: string[] = Object.keys(rawExtra);
        const base64Helper: util.Base64Helper = new util.Base64Helper();
        for (let i: number = 0; i < extraKeys.length; i++) {
          const bytes: Uint8Array = base64Helper.decodeSync(rawExtra[extraKeys[i]]);
          extraFiles.set(extraKeys[i], bytes);
        }
      }
      const content: BackupContent = {
        meta: parsed.meta,
        tableMap: tableMap,
        extraFiles: extraFiles
      };
      const ctx: Context = getContext(this) as Context;
      const result: BackupImportResult | null = await KnockShareService.restoreFromContent(
        ctx.filesDir, content, selected, this.importMode);
      if (result !== null) {
        promptAction.showToast({
          message: '导入成功：' + result.tableCount + ' 表、' + result.rowCount + ' 条记录',
          duration: 2000
        });
        AppStorage.setOrCreate('backup_preview_content', '');
        router.back();
      } else {
        promptAction.showToast({ message: '导入失败，请重试', duration: 2000 });
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'confirmRestore failed: %{public}s', (err as Error).message);
      promptAction.showToast({ message: '导入失败，请重试', duration: 2000 });
    }
    this.isRestoring = false;
  }

  @Builder
  TableRow(item: TableDisplayInfo, index: number) {
    Row() {
      Toggle({ type: ToggleType.Checkbox, isOn: item.checked })
        .selectedColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
        .onChange((checked: boolean) => {
          this.toggleItem(index, checked);
        })
        .width(22)
        .height(22)

      Column() {
        Text(item.displayName)
          .fontSize(TYPO.body.size)
          .fontWeight(600)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        Text(item.tableName + ' · ' + item.rowCount + ' 条记录')
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#888888')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: SPACING.cardGap })
    }
    .width('100%')
    .padding({ left: SPACING.cardPadMd, right: SPACING.cardPadMd, top: 14, bottom: 14 })
  }

  build() {
    Column() {
      // Header
      Row() {
        Button() {
          SymbolGlyph(IconMapper.ARROW_BACK)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          router.back();
        })
        .accessibilityText('返回')

        Text('导入预览')
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(700)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .margin({ left: 4 })

        Blank()
      }
      .width('100%')
      .height(48)
      .padding({ left: SPACING.pageH, right: SPACING.pageH })

      // Content
      Scroll() {
        Column() {
          // 全选行
          Row() {
            Toggle({ type: ToggleType.Checkbox, isOn: this.allChecked })
              .selectedColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
              .onChange((checked: boolean) => {
                this.toggleAll(checked);
              })
              .width(22)
              .height(22)

            Text('全选')
              .fontSize(TYPO.body.size)
              .fontWeight(700)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .margin({ left: SPACING.cardGap })

            Blank()

            Text(this.tableList.length + ' 张表')
              .fontSize(TYPO.eyebrow.size)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
          }
          .width('100%')
          .padding({ left: SPACING.cardPadMd, right: SPACING.cardPadMd, top: 12, bottom: 12 })

          // 表列表卡片
          Column() {
            ForEach(this.tableList, (item: TableDisplayInfo, index: number) => {
              this.TableRow(item, index)
              if (index < this.tableList.length - 1) {
                Divider()
                  .strokeWidth(0.5)
                  .color(this.tokens ? this.tokens.divider : '#F0F0F0')
              }
            })
          }
          .width('100%')
          .borderRadius(RADIUS.card)
          .backgroundColor(this.tokens ? this.tokens.surface : '#FFFFFF')
          .border({ width: 1, color: this.tokens ? this.tokens.border : '#E0E0E0' })
          .margin({ left: SPACING.pageH, right: SPACING.pageH, bottom: SPACING.sectionGap })

          // 导入模式选择
          Column() {
            Text('导入模式')
              .fontSize(TYPO.eyebrow.size)
              .fontWeight(700)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
              .width('100%')
              .margin({ bottom: SPACING.cardGap })

            Row() {
              Button('合并')
                .fontSize(TYPO.body.size)
                .fontWeight(TYPO.body.weight)
                .fontColor(this.importMode === 'merge' ?
                  (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF') :
                  (this.tokens ? this.tokens.textSecondary : '#5A5A5A'))
                .backgroundColor(this.importMode === 'merge' ?
                  (this.tokens ? this.tokens.btnPrimary : '#738A9C') :
                  (this.tokens ? this.tokens.surface : '#FFFFFF'))
                .borderRadius(20)
                .height(38)
                .layoutWeight(1)
                .border({ width: 1, color: this.tokens ? this.tokens.border : '#E0E0E0' })
                .onClick(() => {
                  this.importMode = 'merge';
                })

              Button('覆盖')
                .fontSize(TYPO.body.size)
                .fontWeight(TYPO.body.weight)
                .fontColor(this.importMode === 'overwrite' ?
                  (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF') :
                  (this.tokens ? this.tokens.textSecondary : '#5A5A5A'))
                .backgroundColor(this.importMode === 'overwrite' ?
                  (this.tokens ? this.tokens.btnPrimary : '#738A9C') :
                  (this.tokens ? this.tokens.surface : '#FFFFFF'))
                .borderRadius(20)
                .height(38)
                .layoutWeight(1)
                .margin({ left: 10 })
                .border({ width: 1, color: this.tokens ? this.tokens.border : '#E0E0E0' })
                .onClick(() => {
                  this.importMode = 'overwrite';
                })
            }
            .width('100%')

            Text(this.importMode === 'merge' ?
              '合并：保留现有数据，备份中的记录覆盖同 ID 的记录' :
              '覆盖：清空选中表的所有数据后导入备份内容')
              .fontSize(TYPO.eyebrow.size)
              .fontColor(this.tokens ? this.tokens.textTertiary : '#888888')
              .margin({ top: 10 })
          }
          .width('100%')
          .borderRadius(RADIUS.card)
          .backgroundColor(this.tokens ? this.tokens.surface : '#FFFFFF')
          .border({ width: 1, color: this.tokens ? this.tokens.border : '#E0E0E0' })
          .padding(SPACING.cardPadMd)
          .margin({ left: SPACING.pageH, right: SPACING.pageH, bottom: SPACING.sectionGap })

          Column().height(SPACING.pageBottom)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // 底部确认栏
      Row() {
        Column() {
          Text(this.getSelectedTables().length + ' 项已选')
            .fontSize(TYPO.eyebrow.size)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
          Text(this.getSelectedRowCount() + ' 条记录')
            .fontSize(TYPO.eyebrow.size)
            .fontColor(this.tokens ? this.tokens.textTertiary : '#888888')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)

        Button(this.isRestoring ? '导入中…' : '确认导入')
          .fontSize(TYPO.body.size)
          .fontWeight(700)
          .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
          .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
          .borderRadius(22)
          .height(44)
          .padding({ left: 32, right: 32 })
          .margin({ left: SPACING.cardGap })
          .enabled(!this.isRestoring)
          .onClick(() => {
            this.confirmRestore();
          })
      }
      .width('100%')
      .padding({ left: SPACING.pageH, right: SPACING.pageH, top: 12, bottom: 12 })
      .backgroundColor(this.tokens ? this.tokens.bg : '#FAF8F5')
      .border({ width: 1, color: this.tokens ? this.tokens.divider : '#F0F0F0' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens ? this.tokens.bg : '#FAF8F5')
  }

  pageTransition() {
    PageTransitionEnter({ duration: 320, curve: Curve.Friction })
      .slide(SlideEffect.Right)
    PageTransitionExit({ duration: 260, curve: Curve.Friction })
      .slide(SlideEffect.Right)
  }
}
