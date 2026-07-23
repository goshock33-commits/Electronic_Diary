// <!-- agentID: HUI-041 -->
// 组件：传输进度弹窗（通用：传图 / 备份复用；进度环 + 百分比 + AES-256 加密标注 + 完成态）
// 关联任务：F21（PLN-002 阶段8 碰一碰分享 §10.7 弹窗B/C/E/G）
// 关联设计稿：UX-001_prototype.html → page-nfc-share（transfer progress / complete）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 图标来源：harmonyos-symbol → 系统UI → checkmark_circle_fill（行83 已验证）
// 图标来源：harmonyos-symbol → 隐私&安全 → lock_fill（行1775 已验证）
// API 来源：本地 SDK progress.d.ts（API 24）→ ProgressType.Ring + .style({ strokeWidth }) + .value()（已验证）
// 开发范式：ArkTS 声明式开发范式（Stage 模型）
// 运行时崩溃防范（PROJECT_SPEC §9）：无 getter-in-build（颜色改普通方法）；字段初值不含 $r()；@StorageLink 判空；@Prop 无内置属性重名（用 progressValue/transferMode 等）
import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper } from '@ohos/shared';

@Component
export struct TransferProgressDialog {
  // 进度 0-100（避免与内置 value 冲突用 progressValue）
  @Prop progressValue: number = 0;
  // 传输标题（如"正在传输图片" / "正在传输备份"）
  @Prop titleText: string = '正在传输';
  // 目标设备名
  @Prop deviceName: string = '';
  // 是否显示 AES-256 加密标注
  @Prop encrypted: boolean = false;
  // 是否已完成
  @Prop completed: boolean = false;
  // 完成文案（如"已传输 3 张图片到 华为 MatePad"）
  @Prop completeText: string = '传输完成';
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  onDone?: () => void;
  onCancel?: () => void;

  // === 颜色兜底（普通方法，非 getter；§9）===
  private getPrimary(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  private getSuccess(): string {
    return this.tokens ? this.tokens.success : '#00C2B8';
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

  private getRingTrack(): string {
    return this.tokens ? this.tokens.divider : '#EAEAEA';
  }

  private getPercentText(): string {
    return Math.round(this.progressValue) + '%';
  }

  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 遮罩（传输中不允许点遮罩关闭，避免误操作）
      Column().width('100%').height('100%').backgroundColor('#66000000')

      Column() {
        if (this.completed) {
          this.CompleteContent()
        } else {
          this.ProgressContent()
        }
      }
      .width('84%')
      .padding(28)
      .borderRadius(28)
      .backgroundColor(this.getCardBg())
      .shadow({ radius: 48, color: '#33000000', offsetX: 0, offsetY: 16 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%').height('100%')
  }

  // ==== 传输中 ====
  @Builder
  ProgressContent() {
    Text(this.titleText)
      .fontSize(18).fontWeight(700).fontColor(this.getTextPrimary())

    if (this.deviceName.length > 0) {
      Text('目标设备：' + this.deviceName)
        .fontSize(13).fontColor(this.getTextSecondary()).margin({ top: 6 })
    }

    // 进度环 + 居中百分比
    Stack({ alignContent: Alignment.Center }) {
      Progress({ value: this.progressValue, total: 100, type: ProgressType.Ring })
        .width(160).height(160)
        .color(this.getPrimary())
        .backgroundColor(this.getRingTrack())
        .style({ strokeWidth: 12 })

      Column() {
        Text(this.getPercentText())
          .fontSize(34).fontWeight(700).fontColor(this.getTextPrimary())
        Text('传输中')
          .fontSize(13).fontColor(this.getTextSecondary()).margin({ top: 2 })
      }
    }
    .width(160).height(160).margin({ top: 20 })
    .accessibilityText('传输进度 ' + this.getPercentText())

    // AES-256 加密标注（备份场景）
    if (this.encrypted) {
      Row() {
        SymbolGlyph(IconMapper.LOCK)
          .fontSize(14).fontColor([this.getPrimary()])
        Text('AES-256 端到端加密传输')
          .fontSize(13).fontColor(this.getPrimary()).margin({ left: 6 })
      }
      .backgroundColor(this.withAlpha(this.getPrimary(), '14'))
      .borderRadius(14).padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .margin({ top: 20 })
      .alignItems(VerticalAlign.Center)
    }

    // 取消
    Button('取消传输')
      .fontSize(15).fontWeight(500).fontColor(this.getTextSecondary())
      .backgroundColor(this.getSurface())
      .width('100%').height(48).borderRadius(24)
      .margin({ top: 24 })
      .onClick(() => {
        if (this.onCancel) {
          this.onCancel();
        }
      })
      .accessibilityText('取消传输')
  }

  // ==== 完成 ====
  @Builder
  CompleteContent() {
    SymbolGlyph(IconMapper.SUCCESS)
      .fontSize(72).fontColor([this.getSuccess()])
      .margin({ top: 4 })

    Text('传输完成')
      .fontSize(20).fontWeight(700).fontColor(this.getTextPrimary())
      .margin({ top: 16 })

    Text(this.completeText)
      .fontSize(14).fontColor(this.getTextSecondary())
      .textAlign(TextAlign.Center).width('90%')
      .margin({ top: 8 })

    Button('完成')
      .fontSize(16).fontWeight(600)
      // HUI-038：完成主按钮（漏网）→ btnPrimaryText 白字 + btnPrimary 雾霾蓝底（原 primary 兜底青 #00C2B8）
      .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
      .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
      .width('100%').height(50).borderRadius(25)
      .margin({ top: 28 })
      .onClick(() => {
        if (this.onDone) {
          this.onDone();
        }
      })
      .accessibilityText('完成并关闭')
  }
}

// === @Preview mock 组件（DevEco Studio Previewer 预览） ===

@Preview
@Component
struct TransferProgressDialogPreview {
  build() {
    Column({ space: 16 }) {
      Stack() {
        Column().width('100%').height('50%').backgroundColor('#F2F2F7')
        TransferProgressDialog({
          progressValue: 64, titleText: '正在传输备份',
          deviceName: '荣耀 Magic', encrypted: true, completed: false
        })
      }.width('100%').height('50%')

      Stack() {
        Column().width('100%').height('50%').backgroundColor('#F2F2F7')
        TransferProgressDialog({
          progressValue: 100, completed: true,
          completeText: '已传输 3 张图片到 华为 MatePad Pro'
        })
      }.width('100%').height('50%')
    }
    .width('100%').height('100%')
  }
}
