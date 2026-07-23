// <!-- agentID: HUI-041 -->
// 组件：设备发现弹窗（碰一碰识别到邻近设备后的确认发送卡片）
// 关联任务：F21（PLN-002 阶段8 碰一碰分享 §10.7 弹窗A/D）
// 关联设计稿：UX-001_prototype.html → page-nfc-share（device-found dialog）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 图标来源：harmonyos-symbol → 连接 → nfc_fill（行1430 已验证）
// 开发范式：ArkTS 声明式开发范式（Stage 模型）
// 运行时崩溃防范（PROJECT_SPEC §9）：无 getter-in-build（颜色改普通方法）；字段初值不含 $r()；@StorageLink 判空；@Prop 无内置属性重名；由父组件 if 控制显隐
import type { ThemeColorTokens } from '@ohos/shared';
import type { NfcDeviceInfo } from '../model/NfcShareTypes';

@Component
export struct DeviceFoundDialog {
  // 设备信息（默认 null，真实值由父组件传入；§9 不用 $r() 初值）
  @Prop device: NfcDeviceInfo | null = null;
  // 弹窗标题
  @Prop titleText: string = '发现设备';
  // 主操作按钮文案
  @Prop actionText: string = '发送';
  // 副说明（如"准备传输 3 张图片"）
  @Prop subtitleText: string = '';
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  onConfirm?: () => void;
  onCancel?: () => void;

  // === 颜色兜底（普通方法，非 getter；§9）===
  private getPrimary(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
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

  private getDeviceName(): string {
    return this.device ? this.device.name : '邻近设备';
  }

  private getDeviceMeta(): string {
    if (!this.device) {
      return '';
    }
    return this.device.typeLabel + ' · ' + this.device.storageLabel;
  }

  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  build() {
    // 全屏遮罩层（点击遮罩取消）
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%').height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          if (this.onCancel) {
            this.onCancel();
          }
        })

      // 弹窗卡片
      Column() {
        // 设备头像（NFC 图标圆）
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 72, height: 72 }).fill(this.withAlpha(this.getPrimary(), '1A'))
          SymbolGlyph($r('sys.symbol.nfc_fill'))
            .fontSize(38).fontColor([this.getPrimary()])
        }
        .width(72).height(72).margin({ top: 4 })

        Text(this.titleText)
          .fontSize(14).fontColor(this.getTextSecondary())
          .margin({ top: 14 })

        Text(this.getDeviceName())
          .fontSize(20).fontWeight(700).fontColor(this.getTextPrimary())
          .margin({ top: 4 })
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.getDeviceMeta().length > 0) {
          Text(this.getDeviceMeta())
            .fontSize(13).fontColor(this.getTextSecondary())
            .margin({ top: 6 })
        }

        if (this.subtitleText.length > 0) {
          Text(this.subtitleText)
            .fontSize(14).fontColor(this.getPrimary())
            .backgroundColor(this.withAlpha(this.getPrimary(), '14'))
            .borderRadius(14).padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .margin({ top: 16 })
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
            .accessibilityText('取消发送')

          Button(this.actionText)
            // HUI-038：确认发送主按钮（漏网）→ btnPrimaryText 白字 + btnPrimary 雾霾蓝底（原 primary 兜底青 #00C2B8）
            .fontSize(15).fontWeight(600)
            .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
            .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
            .layoutWeight(1).height(50).borderRadius(25).margin({ left: 12 })
            .shadow({ radius: 12, color: this.withAlpha(this.getPrimary(), '4D'), offsetX: 0, offsetY: 4 })
            .onClick(() => {
              if (this.onConfirm) {
                this.onConfirm();
              }
            })
            .accessibilityText(this.actionText + '到' + this.getDeviceName())
        }
        .width('100%').margin({ top: 24 })
      }
      .width('84%')
      .padding(24)
      .borderRadius(28)
      .backgroundColor(this.getCardBg())
      .shadow({ radius: 48, color: '#33000000', offsetX: 0, offsetY: 16 })
      .alignItems(HorizontalAlign.Center)
      // 吞掉卡片点击，避免冒泡触发遮罩取消
      .onClick(() => {})
    }
    .width('100%').height('100%')
  }
}

// === @Preview mock 组件（DevEco Studio Previewer 预览） ===

@Preview
@Component
struct DeviceFoundDialogPreview {
  @State private device: NfcDeviceInfo = {
    name: '华为 MatePad Pro',
    typeLabel: '平板',
    storageLabel: '128 GB 可用'
  };

  build() {
    Stack() {
      Column().width('100%').height('100%').backgroundColor('#F2F2F7')
      DeviceFoundDialog({
        device: this.device,
        titleText: '发现设备',
        actionText: '发送图片',
        subtitleText: '准备传输 3 张图片'
      })
    }
    .width('100%').height('100%')
  }
}
