// <!-- agentID: HUI-058 -->
// 页面：高级设置页（数据导出/导入 + 导出加密 + 字体大小 + 关于）
// 关联计划：PLN-003 P2-05（设置 SettingsView 复刻；数据导出导入入口保留在高级设置）
// 关联需求：UX-001 §2.7 / §7.5 黑白重彩；薄荷青 bento 皮肤
// 关联规范：PROJECT_SPEC §9（防崩溃）§10（图标本地库）§1.4（三者一致）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
//
// ── 令牌驱动：颜色→tokens；圆角→RADIUS；间距→SPACING；字号字重→TYPO ──
// ── 图标来源（本地库已验证）───────────────────────────────────────
//   | IconMapper.SHARE(arrowshape_turn_up_right_fill) | 导出数据 | 已验证 |
//   | sys.symbol.square_and_arrow_down                | 导入数据 | 基础系统符号(HUI-030 已用) |
//   | IconMapper.LOCK(lock_fill)                      | 导出加密 | 已验证 |
//   | IconMapper.FONT_SIZE(textformat)               | 字体大小 | 已验证 |
//   | IconMapper.INFO(info_circle_fill)              | 关于     | 已验证 |
//   | IconMapper.FORWARD(chevron_right)              | 导航箭头 | 已验证 |

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-028：引入手绘字体助手——SKETCH_TITLE=猫啃(eyebrow/H1/分组标题)，SKETCH_BODY=清松(行标题/说明/进度/分段/关于标签)；版本号数字保留不动。
import { IconMapper, RADIUS, SPACING, TYPO, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';
import { LottieAnimation } from '@ohos/shared';
import { BackupUtils, type BackupContent } from '@ohos/shared';
import { curves, promptAction, router } from '@kit.ArkUI';
import { picker, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { SettingsViewModel } from '../viewmodel/SettingsViewModel';
import type { BackupExportResult } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 字体大小选项配置 */
interface FontSizeOption {
  readonly label: string;
  readonly value: number;
  readonly scaleHint: string;
}

/** 数据操作进度状态 */
interface DataProgressState {
  isExporting: boolean;
  isImporting: boolean;
  progressMessage: string;
}

/** 确认对话框配置 */
interface ConfirmDialogConfig {
  show: boolean;
  title: string;
  message: string;
  confirmText: string;
}

/** 字体大小三档（对齐原型：标准/大/特大） */
const FONT_SIZE_OPTIONS: FontSizeOption[] = [
  { label: '标准', value: 1, scaleHint: '100%' },
  { label: '大', value: 1.25, scaleHint: '125%' },
  { label: '特大', value: 1.5, scaleHint: '150%' }
];

/** 导出数据可选项 */
interface ExportItem {
  key: string;
  label: string;
  icon: Resource;
  desc: string;
  checked: boolean;
}

/** 导出成功后文件路径 */
interface ExportResult {
  filePath: string;
  tableCount: number;
  imageCount: number;
}

@Component
export struct AdvancedSettingsPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  @State exportState: DataProgressState = {
    isExporting: false,
    isImporting: false,
    progressMessage: ''
  };
  @State confirmDialog: ConfirmDialogConfig = {
    show: false,
    title: '',
    message: '',
    confirmText: '确认'
  };
  @State isExportEncryptionOn: boolean = true;
  @State currentFontSize: number = 1;

  // ── 导出选择模态框 ──
  @State showExportSheet: boolean = false;
  @State isExporting: boolean = false;
@State exportItems: ExportItem[] = [
    { key: 'diary', label: '日记正文', icon: IconMapper.NAV_DIARY, desc: '包含所有日记内容、标题、心情', checked: true },
    { key: 'photos', label: '日记照片', icon: IconMapper.CAMERA, desc: '日记中附带的图片原文件', checked: true },
    { key: 'todo', label: '待办事项', icon: IconMapper.CHECKIN_DONE, desc: '今日、明日及全部待办清单', checked: true },
    { key: 'stats', label: '统计数据', icon: IconMapper.CHART_BAR, desc: '签到记录、番茄钟、连续天数', checked: true }
  ];
  // ── 导出成功模态框 ──
  @State showSuccessSheet: boolean = false;
  @State exportResult: ExportResult | null = null;
  // ── 成功对号动画 ──
  @State checkScale: number = 0.3;
  @State checkOpacity: number = 0;
  // ── 导入状态 ──
  @State isImporting: boolean = false;

  // 操作回调：由父组件绑定业务逻辑
  onBack?: () => void;
  onNavigateAbout?: () => void;
  onEncryptionToggle?: (enabled: boolean) => void;
  onFontSizeChange?: (level: number) => void;
  onNavigateNfcShare?: () => void;

  build() {
    Stack() {
      // ── 主内容层 ──
    Scroll() {
      Column() {
        // ═══════════ 头部：eyebrow「ADVANCED SETTINGS」+ H1「高级设置」 ═══════════
        Column() {
          Text('ADVANCED SETTINGS')
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(700)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .opacity(0.6)
            .letterSpacing(3)
            .accessibilityLevel('no')
            .attributeModifier(SKETCH_TITLE) // HUI-028：eyebrow 微标→猫啃什锦黑
          Text('高级设置')
            .fontSize(TYPO.h1.size)
            .fontWeight(TYPO.h1.weight)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            .margin({ top: 4 })
            .attributeModifier(SKETCH_TITLE) // HUI-028：页面 H1→猫啃什锦黑
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: SPACING.sectionGap })
        .accessibilityText('高级设置')

        // ═══════════ 数据管理卡 ═══════════
        this.buildCardTitle('DATA MANAGEMENT', '数据管理')

        Column() {
          // 导出数据
          Row() {
            SymbolGlyph(IconMapper.SHARE)
              .fontSize(18)
              .fontColor([this.tokens ? this.tokens.btnPrimary : '#738A9C'])
              .margin({ right: 12 })

            Column() {
              Text('导出数据')
                .fontSize(TYPO.cardTitle.size)
                .fontWeight(TYPO.cardTitle.weight)
                .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                .attributeModifier(SKETCH_BODY) // HUI-028：行标题→清松手写体2
              Text('将所有日记和数据打包导出为加密备份文件')
                .fontSize(TYPO.eyebrow.size)
                .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                .opacity(0.7)
                .margin({ top: 2 })
                .maxLines(2)
                .attributeModifier(SKETCH_BODY) // HUI-028：行说明→清松手写体2
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.exportState.isExporting) {
              LoadingProgress()
                .width(22)
                .height(22)
                .color(this.tokens ? this.tokens.btnPrimary : '#738A9C')
            } else {
              SymbolGlyph(IconMapper.FORWARD)
                .fontSize(14)
                .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
            }
          }
          .width('100%')
          .padding({ top: 14, bottom: 14 })
          .onClick(() => {
            if (!this.exportState.isExporting && !this.isExporting) {
              this.showExportSheet = true;
            }
          })
          .enabled(!this.exportState.isExporting && !this.exportState.isImporting && !this.isExporting && !this.isImporting)
          .accessibilityText('导出数据，将所有日记和数据打包导出为加密备份文件')

          this.buildDivider()

          // 导入数据
          Row() {
            SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
              .fontSize(18)
              .fontColor([this.tokens ? this.tokens.warning : '#80CBC4'])
              .margin({ right: 12 })

            Column() {
              Text('导入数据')
                .fontSize(TYPO.cardTitle.size)
                .fontWeight(TYPO.cardTitle.weight)
                .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                .attributeModifier(SKETCH_BODY) // HUI-028：行标题→清松手写体2
              Text('从备份文件恢复数据（将覆盖现有数据，请谨慎操作）')
                .fontSize(TYPO.eyebrow.size)
                .fontColor(this.tokens ? this.tokens.danger : '#78909C')
                .margin({ top: 2 })
                .maxLines(2)
                .attributeModifier(SKETCH_BODY) // HUI-028：行说明→清松手写体2
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.exportState.isImporting) {
              LoadingProgress()
                .width(22)
                .height(22)
                .color(this.tokens ? this.tokens.btnPrimary : '#738A9C')
            } else {
              SymbolGlyph(IconMapper.FORWARD)
                .fontSize(14)
                .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
            }
          }
          .width('100%')
          .padding({ top: 14, bottom: 14 })
          .onClick(() => {
            if (!this.exportState.isImporting && !this.isImporting) {
              this.pickFileAndImport();
            }
          })
          .enabled(!this.exportState.isExporting && !this.exportState.isImporting && !this.isExporting && !this.isImporting)
          .accessibilityText('导入数据，从备份文件恢复数据，将覆盖现有数据')

          this.buildDivider()

          // 导出加密 Toggle
          Row() {
            SymbolGlyph(IconMapper.LOCK)
              .fontSize(18)
              .fontColor([this.tokens ? this.tokens.textSecondary : '#8A9B8A'])
              .margin({ right: 12 })

            Column() {
              Text('导出加密')
                .fontSize(TYPO.cardTitle.size)
                .fontWeight(TYPO.cardTitle.weight)
                .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                .attributeModifier(SKETCH_BODY) // HUI-028：行标题→清松手写体2
              Text('对备份文件设置密码保护')
                .fontSize(TYPO.eyebrow.size)
                .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                .opacity(0.7)
                .margin({ top: 2 })
                .attributeModifier(SKETCH_BODY) // HUI-028：行说明→清松手写体2
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.isExportEncryptionOn })
              .selectedColor(this.tokens ? this.tokens.switchOn : '#C6BBAE') // HUI-035：开关 ON→燕麦 switchOn
              .onChange((checked: boolean) => {
                this.isExportEncryptionOn = checked;
                if (this.onEncryptionToggle) {
                  this.onEncryptionToggle(checked);
                }
              })
              .accessibilityText('导出加密开关，当前' +
                (this.isExportEncryptionOn ? '开启' : '关闭'))
          }
          .width('100%')
          .height(56)
          .accessibilityText('导出加密，对备份文件设置密码保护，当前' +
            (this.isExportEncryptionOn ? '开启' : '关闭'))
        }
        .width('100%')
        .borderRadius(RADIUS.cardLg)
        .padding(SPACING.cardPadMd)
        .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
        .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)' })
        .shadow({
          radius: 12,
          color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
          offsetX: 0,
          offsetY: 4
        })
        .margin({ bottom: SPACING.cardGap })

        // ═══════════ 进度提示（仅非模态态的提示，如导入选文件阶段）═══════════
        if (this.exportState.progressMessage.length > 0 && !this.isExporting && !this.isImporting) {
          Row() {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(this.tokens ? this.tokens.btnPrimary : '#738A9C')
              .margin({ right: 10 })

            Text(this.exportState.progressMessage)
              .fontSize(TYPO.body.size)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
              .attributeModifier(SKETCH_BODY)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .borderRadius(RADIUS.item)
          .backgroundColor(this.tokens ? this.tokens.accent : '#E6F9F8')
          .margin({ bottom: SPACING.cardGap })
          .accessibilityText(this.exportState.progressMessage)
        }

        // ═══════════ 显示卡（字体大小）═══════════
        this.buildCardTitle('DISPLAY', '显示')

        Column() {
          Row() {
            SymbolGlyph(IconMapper.FONT_SIZE)
              .fontSize(18)
              .fontColor([this.tokens ? this.tokens.textSecondary : '#8A9B8A'])
              .margin({ right: 12 })
            Text('字体大小')
              .fontSize(TYPO.cardTitle.size)
              .fontWeight(TYPO.cardTitle.weight)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .attributeModifier(SKETCH_BODY) // HUI-028：行标题→清松手写体2
          }
          .width('100%')
          .margin({ bottom: 10 })

          // 三段（青底白字激活）
          Row() {
            ForEach(FONT_SIZE_OPTIONS, (option: FontSizeOption) => {
              Text(option.label)
                .fontSize(12)
                .fontWeight(this.currentFontSize === option.value ? 700 : 400)
                .fontColor(this.currentFontSize === option.value
                  ? (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
                  : (this.tokens ? this.tokens.textSecondary : '#5A5A5A'))
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(32)
                .borderRadius(RADIUS.input)
                .backgroundColor(this.currentFontSize === option.value
                  ? (this.tokens ? this.tokens.btnPrimary : '#738A9C')
                  : (this.tokens ? this.tokens.surface : '#FFFFFF')) // HUI-041：字号分段未选中底由死白改读 surface token，修深色白底浅灰字不可见
                .attributeModifier(SKETCH_BODY) // HUI-028：字号分段标签→清松手写体2
                .onClick(() => {
                  this.currentFontSize = option.value;
                  if (this.onFontSizeChange) {
                    this.onFontSizeChange(option.value);
                  }
                })
                .accessibilityText('字体大小：' + option.label +
                  (this.currentFontSize === option.value ? '，当前选中' : ''))
            })
          }
          .width('100%')
          .padding(4)
          .borderRadius(RADIUS.item)
          .backgroundColor(this.tokens ? this.tokens.surface : '#F2F4F3')
        }
        .width('100%')
        .borderRadius(RADIUS.cardLg)
        .padding(SPACING.cardPadMd)
        .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
        .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)' })
        .shadow({
          radius: 12,
          color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
          offsetX: 0,
          offsetY: 4
        })
        .margin({ bottom: SPACING.cardGap })

        // ═══════════ 关于卡 ═══════════
        this.buildCardTitle('ABOUT', '关于')

        Column() {
          this.buildInfoRow('应用版本', '1.0.0', false)
          this.buildInfoRow('SDK 版本', 'HarmonyOS 6.1.1 (API 24)', true)
          this.buildInfoRow('数据版本', 'v1', true)
        }
        .width('100%')
        .borderRadius(RADIUS.cardLg)
        .padding(SPACING.cardPadMd)
        .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
        .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)' })
        .shadow({
          radius: 12,
          color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
          offsetX: 0,
          offsetY: 4
        })

        // 底部安全区
        Column().height(SPACING.pageBottom)
      }
      .width('100%')
      .padding({ left: SPACING.pageH, right: SPACING.pageH, top: SPACING.pageTop })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens ? this.tokens.bg : '#FAF8F5')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)

      // ── 导出选择模态框（Stack 叠层，居中）──
      if (this.showExportSheet) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.38)')
          .onClick(() => {
            this.showExportSheet = false;
          })

        Column() {
          Blank()
          this.ExportSelectionContent()
          Blank()
        }
        .width('100%')
        .height('100%')
      }

      // ── 导出/导入加载中模态框（猫咪动画悬浮居中）──
      if (this.isExporting || this.isImporting) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.38)')
          .hitTestBehavior(HitTestMode.Block)

        Column() {
          Blank()
          LottieAnimation({
            animPath: 'animations/cat-loader.json',
            animName: 'export-loading',
            loop: true,
            autoPlay: true,
            shouldPlay: true,
            accessibilityLabel: '猫咪加载动画'
          })
            .width(140)
            .height(140)

          Text(this.isExporting ? '正在导出数据…' : '正在导入数据…')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .fontWeight(500)
            .margin({ top: 12 })
            .opacity(0.9)

          Blank()
        }
        .width('100%')
        .height('100%')
      }

      // ── 导出成功模态框 ──
      if (this.showSuccessSheet) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.38)')
          .onClick(() => {
            this.showSuccessSheet = false;
          })

        Column() {
          Blank()
          this.ExportSuccessContent()
          Blank()
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Top)
  }

  // ════════════════════════════════════════════════════════════
  // 导出/导入 业务逻辑
  // ════════════════════════════════════════════════════════════

  /** 点击确认导出：关闭选择模态框 → 异步执行导出 → 成功后弹出成功模态框 */
  private async confirmExport(): Promise<void> {
    this.showExportSheet = false;
    this.isExporting = true;
    this.exportState.progressMessage = '正在导出数据…';
    try {
      const ctx: common.Context = getContext(this) as common.Context;
      const vm: SettingsViewModel = new SettingsViewModel();
      const res: BackupExportResult | null = await vm.exportBackup(ctx);
      if (res !== null) {
        // 导出成功后弹出保存选择器，让用户选择存放位置
        const saveOptions: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
        saveOptions.newFileNames = ['电子日记备份_' + new Date().toISOString().split('T')[0] + '.ediary.zip'];
        const savePicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
        let savedUris: string[] = [];
        try {
          savedUris = await savePicker.save(saveOptions);
        } catch (saveErr) {
          hilog.warn(0x0000, 'AdvancedSettings', 'save picker failed: %{public}s', (saveErr as Error).message);
        }
        if (savedUris.length === 0) {
          // 用户取消了保存选择，不显示导出成功
          this.isExporting = false;
          this.exportState.progressMessage = '';
          return;
        }
        // 用 fileIo 复制：源文件路径 → 目标 URI
        const srcFile: fileIo.File = fileIo.openSync(res.path, fileIo.OpenMode.READ_ONLY);
        const dstFile: fileIo.File = fileIo.openSync(savedUris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        await fileIo.copyFile(srcFile.fd, dstFile.fd);
        fileIo.closeSync(srcFile);
        fileIo.closeSync(dstFile);
        hilog.info(0x0000, 'AdvancedSettings', 'backup saved to: %{public}s', savedUris[0]);
        this.exportResult = {
          filePath: savedUris[0],
          tableCount: res.tableCount,
          imageCount: res.imageCount
        };
        this.showSuccessSheet = true;
        // 触发对号动画
        this.checkScale = 0.3;
        this.checkOpacity = 0;
        animateTo({ curve: curves.springMotion(0.55, 0.72) }, () => {
          this.checkScale = 1;
          this.checkOpacity = 1;
        });
      } else {
        promptAction.showToast({ message: '导出失败，请重试', duration: 2000 });
      }
    } catch (err) {
      hilog.error(0x0000, 'AdvancedSettings', 'export failed: %{public}s', (err as Error).message);
      promptAction.showToast({ message: '导出失败，请重试', duration: 2000 });
    }
    this.isExporting = false;
    this.exportState.progressMessage = '';
  }

  /** 打开文件选择器，选择 .ediary.zip 文件后解析并跳转到预览页 */
  private async pickFileAndImport(): Promise<void> {
    this.isImporting = true;
    this.exportState.progressMessage = '正在选择文件…';
    try {
      const ctx: common.Context = getContext(this) as common.Context;
      const documentSelectOptions: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.maxSelectNumber = 1;
      const documentViewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const uris: string[] = await documentViewPicker.select(documentSelectOptions);
      if (uris.length === 0) {
        this.isImporting = false;
        this.exportState.progressMessage = '';
        return;
      }
      this.exportState.progressMessage = '正在解析文件…';
      // 复制到沙箱
      const receiveDir: string = ctx.filesDir + '/received';
      try { fileIo.mkdirSync(receiveDir, true); } catch (_e) { }
      const tmpPath: string = receiveDir + '/received_' + Date.now() + '.ediary.zip';
      const srcFile: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
      const dstFile: fileIo.File = fileIo.openSync(tmpPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.copyFileSync(srcFile.fd, dstFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(dstFile);
      // 解析备份文件
      const content: BackupContent | null = await BackupUtils.importBackup(tmpPath, '');
      // 清理临时文件
      try { fileIo.unlinkSync(tmpPath); } catch (_e) { }
      if (content === null) {
        promptAction.showToast({ message: '导入失败，文件可能已损坏', duration: 2000 });
      } else {
        // 将 BackupContent 序列化到 AppStorage（extraFiles 的 Uint8Array 转为 base64）
        const tableObj: Record<string, string> = {};
        content.tableMap.forEach((value: string, key: string) => {
          tableObj[key] = value;
        });
        const extraObj: Record<string, string> = {};
        const base64Helper: util.Base64Helper = new util.Base64Helper();
        content.extraFiles.forEach((value: Uint8Array, key: string) => {
          extraObj[key] = base64Helper.encodeToStringSync(value);
        });
        const serialized: Record<string, Object> = {};
        serialized['meta'] = content.meta;
        serialized['tableMap'] = tableObj;
        serialized['extraFiles'] = extraObj;
        const contentStr: string = JSON.stringify(serialized);
        AppStorage.setOrCreate('backup_preview_content', contentStr);
        router.pushUrl({ url: 'pages/BackupPreviewPage' });
      }
    } catch (err) {
      hilog.error(0x0000, 'AdvancedSettings', 'import failed: %{public}s', (err as Error).message);
      promptAction.showToast({ message: '导入失败，请重试', duration: 2000 });
    }
    this.isImporting = false;
    this.exportState.progressMessage = '';
  }

  /** 分享：跳转到碰一碰分享页面 */
  private shareViaNfc(): void {
    this.showSuccessSheet = false;
    if (this.onNavigateNfcShare) {
      this.onNavigateNfcShare();
    }
  }

  /** 打开存放文件夹 */
  private openFolder(): void {
    this.showSuccessSheet = false;
    promptAction.showToast({ message: '文件已保存到您选择的位置', duration: 2500 });
  }

  // ════════════════════════════════════════════════════════════
  // 模态框 Builder
  // ════════════════════════════════════════════════════════════

  /** 底部滑入 — 导出数据选择（内容主体） */
  @Builder
  ExportSelectionContent() {
    Column() {
      // 顶部把手
      Row() {
        Row()
          .width(36)
          .height(5)
          .borderRadius(3)
          .backgroundColor(this.tokens ? this.tokens.divider : '#E0E0E0')
          .opacity(0.6)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 20 })

      // 标题
      Text('选择导出数据')
        .fontSize(20)
        .fontWeight(700)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .width('100%')
        .margin({ bottom: 4 })
      Text('勾选要导出的内容，未选中的不会包含在备份文件中')
        .fontSize(13)
        .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
        .width('100%')
        .margin({ bottom: 20 })

      // 可选项列表
      ForEach(this.exportItems, (item: ExportItem, index: number) => {
        Row() {
          Column() {
            Text(item.label)
              .fontSize(TYPO.cardTitle.size)
              .fontWeight(600)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            Text(item.desc)
              .fontSize(12)
              .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Checkbox, isOn: item.checked })
            .selectedColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
            .onChange((checked: boolean) => {
              const items: ExportItem[] = this.exportItems.slice();
              items[index] = { key: item.key, label: item.label, icon: item.icon, desc: item.desc, checked: checked };
              this.exportItems = items;
            })
        }
        .width('100%')
        .padding({ top: 12, bottom: 12 })
        if (index < this.exportItems.length - 1) {
          Divider()
            .strokeWidth(0.5)
            .color(this.tokens ? this.tokens.divider : '#EAEAE6')
        }
      }, (item: ExportItem) => item.key)

      // 确认按钮
      Button('确认导出')
        .width('100%')
        .height(52)
        .fontSize(16)
        .fontWeight(600)
        .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
        .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
        .borderRadius(999)
        .margin({ top: 20 })
        .shadow({ radius: 14, color: this.tokens ? this.withAlpha(this.tokens.btnPrimary, '4D') : 'rgba(115,138,156,0.30)', offsetX: 0, offsetY: 4 })
        .onClick(() => {
          this.confirmExport();
        })
    }
    .width('100%')
    .borderRadius({ topLeft: RADIUS.cardLg, topRight: RADIUS.cardLg })
    .padding({ left: 24, right: 24, top: 28, bottom: 36 })
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(204,204,204,0.4)', style: BorderStyle.Solid })
  }

  /** 居中 — 导出成功（内容主体） */
  @Builder
  ExportSuccessContent() {
    Column() {
      // 顶部操作栏
      Row() {
        // 文件夹按钮
        Button() {
          SymbolGlyph(IconMapper.EMPTY)
            .fontSize(20)
            .fontColor([this.tokens ? this.tokens.textSecondary : '#4A4A4A'])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(this.tokens ? this.tokens.surface : '#F7F7F7')
        .border({ width: 1, color: this.tokens ? this.tokens.border : '#CCCCCC' })
        .onClick(() => { this.openFolder(); })

        Blank()

        // 分享按钮
        Button() {
          SymbolGlyph(IconMapper.SHARE)
            .fontSize(20)
            .fontColor([this.tokens ? this.tokens.textSecondary : '#4A4A4A'])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(this.tokens ? this.tokens.surface : '#F7F7F7')
        .border({ width: 1, color: this.tokens ? this.tokens.border : '#CCCCCC' })
        .onClick(() => { this.shareViaNfc(); })
      }
      .width('100%')
      .margin({ bottom: 16 })

      // 对号从小放大（官方系统图标）
      Stack() {
        SymbolGlyph(IconMapper.SUCCESS)
          .fontSize(64)
          .fontColor(['#738A9C'])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .scale({ x: this.checkScale, y: this.checkScale })
          .opacity(this.checkOpacity)
      }
      .width(80)
      .height(80)
      .borderRadius(40)
      .backgroundColor(this.tokens ? this.tokens.surface : '#F7F7F7')
      .margin({ bottom: 16 })

      // 成功文案
      Text('导出成功')
        .fontSize(20)
        .fontWeight(700)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .margin({ bottom: 6 })

      Text('备份文件已保存到您选择的位置')
        .fontSize(13)
        .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
        .textAlign(TextAlign.Center)
        .lineHeight(20)

      if (this.exportResult !== null) {
        Text(this.exportResult.tableCount.toString() + ' 张表 · ' + this.exportResult.imageCount.toString() + ' 张照片')
          .fontSize(12)
          .fontColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
          .margin({ top: 8 })
          .opacity(0.8)
      }

      // 完成按钮
      Button('完成')
        .width('100%')
        .height(48)
        .fontSize(15)
        .fontWeight(600)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .backgroundColor(this.tokens ? this.tokens.btnAux : '#C6BBAE')
        .borderRadius(999)
        .margin({ top: 20 })
        .onClick(() => {
          this.showSuccessSheet = false;
        })
    }
    .width(320)
    .borderRadius(RADIUS.cardLg)
    .padding({ left: 24, right: 24, top: 28, bottom: 24 })
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(204,204,204,0.4)', style: BorderStyle.Solid })
    .shadow({ radius: 20, color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.12)', offsetX: 0, offsetY: 8 })
  }

  // ════════════════════════════════════════════════════════════
  // Builder 方法
  // ════════════════════════════════════════════════════════════

  @Builder
  buildCardTitle(en: string, cn: string) {
    Column() {
      Text(en)
        .fontSize(9)
        .fontWeight(800)
        .fontColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
        .opacity(0.7)
        .letterSpacing(2)
        .attributeModifier(SKETCH_TITLE) // HUI-028：分组 eyebrow→猫啃什锦黑
      Text(cn)
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(700)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .margin({ top: 2 })
        .attributeModifier(SKETCH_TITLE) // HUI-028：分组标题→猫啃什锦黑
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 12 })
    .accessibilityText(cn)
  }

  @Builder
  buildDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(this.tokens ? this.tokens.divider : '#EAEAE6')
  }

  @Builder
  buildInfoRow(label: string, value: string, withTopDivider: boolean) {
    Column() {
      if (withTopDivider) {
        this.buildDivider()
      }
      Row() {
        Text(label)
          .fontSize(TYPO.body.size)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .attributeModifier(SKETCH_BODY) // HUI-028：关于项标签→清松手写体2（版本号 value 保留 mono/不动）

        Blank()

        Text(value)
          .fontSize(TYPO.body.size)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
      }
      .width('100%')
      .height(48)
      .accessibilityText(label + '：' + value)
    }
    .width('100%')
  }

  /** hex + alpha → #AARRGGBB（ArkUI 阴影色专用格式） */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }
}
