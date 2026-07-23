// <!-- agentID: HUI-041 -->
// 组件：备份传输 / 接收导入确认弹窗（发送方预览备份文件；接收方覆盖警告 + 加密密码输入）
// 关联任务：F21（PLN-002 阶段8 碰一碰分享 §10.7 弹窗D/F）
// 关联设计稿：UX-001_prototype.html → page-nfc-share（backup confirm / receive import）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 图标来源：harmonyos-symbol → 办公文件 → folder_fill（行1007 已验证）
// 图标来源：harmonyos-symbol → 符号标识 → exclamationmark_triangle_fill（行1468 已验证）
// 图标来源：harmonyos-symbol → 隐私&安全 → lock_fill（行1775 已验证）
// 开发范式：ArkTS 声明式开发范式（Stage 模型）
// 运行时崩溃防范（PROJECT_SPEC §9）：无 getter-in-build（颜色改普通方法）；字段初值不含 $r()；@StorageLink 判空；@Prop 无内置属性重名
import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper } from '@ohos/shared';
import type { BackupFileMeta } from '../model/NfcShareTypes';

@Component
export struct BackupReceiveConfirmDialog {
  // 备份文件信息（默认 null，§9 不用 $r() 初值）
  @Prop file: BackupFileMeta | null = null;
  // true=接收方导入（含覆盖警告 + 密码输入）；false=发送方确认
  @Prop isReceiver: boolean = false;
  // 主操作按钮文案
  @Prop actionText: string = '确认发送';
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  // 接收方输入的解密密码（mock）
  @State private password: string = '';
  onConfirm?: (password: string) => void;
  onCancel?: () => void;

  // === 颜色兜底（普通方法，非 getter；§9）===
  private getPrimary(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  private getDanger(): string {
    return this.tokens ? this.tokens.danger : '#78909C';
  }

  private getWarning(): string {
    return this.tokens ? this.tokens.warning : '#80CBC4';
  }

  private getCardBg(): string {
    return this.tokens ? this.tokens.bgCard : '#FFFFFF';
  }

  private getTextPrimary(): string {
    return this.tokens ? this.tokens.textPrimary : '#333333';
  }

  private getTextSecondary(): string {
    return this.tokens ? this.tokens.textSecondary : '#999999';
  }

  private getSurface(): string {
    return this.tokens ? this.tokens.surface : '#F5F5F5';
  }

  private getFileName(): string {
    return this.file ? this.file.fileName : '备份文件.hth';
  }

  private getFileSize(): string {
    return this.file ? this.file.sizeLabel : '';
  }

  private getFileEntry(): string {
    return this.file ? this.file.entryLabel : '';
  }

  private getTitle(): string {
    return this.isReceiver ? '接收备份并导入' : '发送备份文件';
  }

  private canConfirm(): boolean {
    // 接收方需输入密码方可导入；发送方直接可确认
    return this.isReceiver ? this.password.length > 0 : true;
  }

  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 遮罩（点击取消）
      Column().width('100%').height('100%').backgroundColor('#66000000')
        .onClick(() => {
          if (this.onCancel) {
            this.onCancel();
          }
        })

      Column() {
        Text(this.getTitle())
          .fontSize(18).fontWeight(700).fontColor(this.getTextPrimary())
          .width('100%').textAlign(TextAlign.Start)

        // 备份文件信息卡
        Row() {
          Stack({ alignContent: Alignment.Center }) {
            Circle({ width: 48, height: 48 }).fill(this.withAlpha(this.getPrimary(), '1A'))
            SymbolGlyph($r('sys.symbol.folder_fill'))
              .fontSize(24).fontColor([this.getPrimary()])
          }
          .width(48).height(48)

          Column() {
            Text(this.getFileName())
              .fontSize(15).fontWeight(600).fontColor(this.getTextPrimary())
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.getFileSize().length > 0) {
              Text(this.getFileSize())
                .fontSize(12).fontColor(this.getTextSecondary()).margin({ top: 3 })
            }
            if (this.getFileEntry().length > 0) {
              Text(this.getFileEntry())
                .fontSize(12).fontColor(this.getTextSecondary()).margin({ top: 2 })
            }
          }
          .alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 12 })
        }
        .width('100%').padding(14)
        .backgroundColor(this.getSurface())
        .borderRadius(16).margin({ top: 16 })
        .alignItems(VerticalAlign.Center)

        // 接收方：覆盖警告 + 密码输入
        if (this.isReceiver) {
          Row() {
            SymbolGlyph(IconMapper.ERROR)
              .fontSize(18).fontColor([this.getDanger()])
            Text('导入将覆盖当前设备上的全部数据，此操作不可撤销')
              .fontSize(13).fontColor(this.getDanger())
              .layoutWeight(1).margin({ left: 10 })
          }
          .width('100%').padding(12)
          .backgroundColor(this.withAlpha(this.getDanger(), '14'))
          .borderRadius(14).margin({ top: 14 })
          .alignItems(VerticalAlign.Center)

          Row() {
            SymbolGlyph(IconMapper.LOCK)
              .fontSize(16).fontColor([this.getTextSecondary()])
            TextInput({ placeholder: '输入备份加密密码' })
              .type(InputType.Password)
              .fontSize(15)
              .backgroundColor(Color.Transparent)
              .layoutWeight(1).height(48)
              .onChange((v: string) => {
                this.password = v;
              })
              .accessibilityText('备份加密密码输入框')
          }
          .width('100%').padding({ left: 14, right: 8 })
          .backgroundColor(this.getSurface())
          .borderRadius(14).margin({ top: 12 })
          .alignItems(VerticalAlign.Center)
        }

        // 操作按钮
        Row() {
          Button('取消')
            .fontSize(15).fontWeight(500).fontColor(this.getTextSecondary())
            .backgroundColor(this.getSurface())
            .layoutWeight(1).height(50).borderRadius(25)
            .onClick(() => {
              if (this.onCancel) {
                this.onCancel();
              }
            })
            .accessibilityText('取消')

          Button(this.isReceiver ? '确认导入' : this.actionText)
            .fontSize(15).fontWeight(600)
            .fontColor(this.canConfirm() ? Color.White : this.getTextSecondary())
            .backgroundColor(this.canConfirm() ? (this.isReceiver ? this.getDanger() : this.getPrimary()) : this.getSurface())
            .layoutWeight(1).height(50).borderRadius(25).margin({ left: 12 })
            .enabled(this.canConfirm())
            .onClick(() => {
              if (this.onConfirm) {
                this.onConfirm(this.password);
              }
            })
            .accessibilityText(this.isReceiver ? '确认导入并覆盖数据' : this.actionText)
        }
        .width('100%').margin({ top: 22 })
      }
      .width('86%')
      .padding(22)
      .borderRadius(28)
      .backgroundColor(this.getCardBg())
      .shadow({ radius: 48, color: '#33000000', offsetX: 0, offsetY: 16 })
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {})
    }
    .width('100%').height('100%')
  }
}

// === @Preview mock 组件（DevEco Studio Previewer 预览） ===

@Preview
@Component
struct BackupReceiveConfirmDialogPreview {
  @State private meta: BackupFileMeta = {
    fileName: 'diary_backup_2026-07-08.hth',
    sizeLabel: '4.2 MB',
    entryLabel: '日记 128 · 待办 56 · 打卡 90'
  };

  build() {
    Stack() {
      Column().width('100%').height('100%').backgroundColor('#F2F2F7')
      BackupReceiveConfirmDialog({
        file: this.meta,
        isReceiver: true,
        actionText: '确认发送'
      })
    }
    .width('100%').height('100%')
  }
}
