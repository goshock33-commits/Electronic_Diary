// <!-- agentID: HUI-041 -->
// 组件：图片选择网格（手机碰平板 → 选择要传输到日记的图片，可多选）
// 关联任务：F21（PLN-002 阶段8 碰一碰分享 §10.7 弹窗A 图片选择）
// 关联设计稿：UX-001_prototype.html → page-nfc-share（image transfer selector）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 图标来源：harmonyos-symbol → 相机与照片 → picture（行750 已验证）
// 图标来源：harmonyos-symbol → 系统UI → checkmark（行76 已验证）
// 图标来源：harmonyos-symbol → 编辑/时间 → xmark（行293 已验证）
// 开发范式：ArkTS 声明式开发范式（Stage 模型）
// 运行时崩溃防范（PROJECT_SPEC §9）：无 getter-in-build（颜色改普通方法）；缩略图用纯色占位（不含 $r() 媒体）；@StorageLink 判空；@Prop 无内置属性重名
import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper } from '@ohos/shared';
import type { TransferImageItem } from '../model/NfcShareTypes';

@Component
export struct ImageTransferSelector {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  // mock 图片集合（纯色占位缩略图，字段初值无 $r()，符合 §9）
  @State private images: TransferImageItem[] = [
    { id: 1, colorHex: '#FFB4A2', selected: true },
    { id: 2, colorHex: '#A2D2FF', selected: true },
    { id: 3, colorHex: '#B5E48C', selected: false },
    { id: 4, colorHex: '#FFC8DD', selected: true },
    { id: 5, colorHex: '#CDB4DB', selected: false },
    { id: 6, colorHex: '#FFD6A5', selected: false },
    { id: 7, colorHex: '#9BF6FF', selected: false },
    { id: 8, colorHex: '#CAFFBF', selected: false },
    { id: 9, colorHex: '#FDFFB6', selected: false }
  ];
  // 确认发送：回传选中张数
  onConfirm?: (count: number) => void;
  onClose?: () => void;

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

  private getTextTertiary(): string {
    return this.tokens ? this.tokens.textTertiary : '#BBBBBB';
  }

  private getSurface(): string {
    return this.tokens ? this.tokens.surface : '#F5F5F5';
  }

  private countSelected(): number {
    let n: number = 0;
    this.images.forEach((it: TransferImageItem) => {
      if (it.selected) {
        n++;
      }
    });
    return n;
  }

  private toggle(id: number): void {
    this.images = this.images.map((it: TransferImageItem) => {
      if (it.id === id) {
        const next: TransferImageItem = { id: it.id, colorHex: it.colorHex, selected: !it.selected };
        return next;
      }
      return it;
    });
  }

  private getSendLabel(): string {
    const c: number = this.countSelected();
    return c > 0 ? ('发送 ' + c + ' 张图片') : '请选择图片';
  }

  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  build() {
    // 底部抽屉式弹窗
    Column() {
      // 遮罩（上半部，点击关闭）
      Column()
        .layoutWeight(1).width('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          if (this.onClose) {
            this.onClose();
          }
        })

      // 内容抽屉
      Column() {
        // 抓手
        Row()
          .width(40).height(4).borderRadius(2)
          .backgroundColor(this.getTextTertiary())
          .margin({ top: 8, bottom: 8 })

        // 标题栏
        Row() {
          Column() {
            Text('选择要传输的图片')
              .fontSize(18).fontWeight(700).fontColor(this.getTextPrimary())
            Text('已选 ' + this.countSelected() + ' 张')
              .fontSize(13).fontColor(this.getTextSecondary()).margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start).layoutWeight(1)

          Button() {
            SymbolGlyph(IconMapper.CLOSE)
              .fontSize(18).fontColor([this.getTextSecondary()])
          }
          .width(44).height(44).borderRadius(22)
          .backgroundColor(this.getSurface())
          .onClick(() => {
            if (this.onClose) {
              this.onClose();
            }
          })
          .accessibilityText('关闭图片选择')
        }
        .width('100%').padding({ left: 20, right: 20, bottom: 12 })
        .alignItems(VerticalAlign.Center)

        // 图片网格（3 列，可滚动多选）
        Grid() {
          ForEach(this.images, (item: TransferImageItem) => {
            GridItem() {
              this.ImageTile(item)
            }
          }, (item: TransferImageItem) => item.id.toString())
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(10).rowsGap(10)
        .width('100%').height(300)
        .padding({ left: 20, right: 20 })
        .scrollBar(BarState.Off)

        // 发送按钮
        Button(this.getSendLabel())
          .fontSize(16).fontWeight(600)
          // HUI-038：发送主按钮（漏网）→ 可用态 btnPrimaryText 白字 + btnPrimary 雾霾蓝底（原 primary 兜底青 #00C2B8）；禁用态保留 surface
          .fontColor(this.countSelected() > 0 ? (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF') : this.getTextTertiary())
          .backgroundColor(this.countSelected() > 0 ? (this.tokens ? this.tokens.btnPrimary : '#738A9C') : this.getSurface())
          .width('100%').height(52).borderRadius(26)
          .margin({ top: 12, bottom: 20 })
          .enabled(this.countSelected() > 0)
          .onClick(() => {
            if (this.onConfirm) {
              this.onConfirm(this.countSelected());
            }
          })
          .accessibilityText(this.getSendLabel())
      }
      .width('100%')
      .padding({ left: 4, right: 4 })
      .backgroundColor(this.getCardBg())
      .borderRadius({ topLeft: 28, topRight: 28 })
      .onClick(() => {})
    }
    .width('100%').height('100%')
  }

  @Builder
  ImageTile(item: TransferImageItem) {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 缩略图占位（纯色 + 隐约 picture 图标）
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%').height('100%').borderRadius(14)
          .backgroundColor(item.colorHex)
        SymbolGlyph($r('sys.symbol.picture'))
          .fontSize(26).fontColor([this.withAlpha('#FFFFFF', 'B3')])
      }
      .width('100%').aspectRatio(1)
      .borderRadius(14)
      .border({
        // HUI-038：选中态高亮描边→btnPrimary 雾霾蓝（原 primary 兜底青 #00C2B8）
        width: item.selected ? 3 : 0,
        color: this.tokens ? this.tokens.btnPrimary : '#738A9C'
      })

      // 选中角标
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 24, height: 24 })
          // HUI-038：图片选中勾选圈完成态→btnPrimary 雾霾蓝（原 primary 兜底青 #00C2B8）；未选保留半透明遮罩
          .fill(item.selected ? (this.tokens ? this.tokens.btnPrimary : '#738A9C') : this.withAlpha('#000000', '40'))
          .stroke(Color.White).strokeWidth(1.5)
        if (item.selected) {
          SymbolGlyph(IconMapper.CHECKMARK)
            // HUI-038：勾选图标→btnPrimaryText（配 btnPrimary 底）
            .fontSize(13).fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF'])
        }
      }
      .width(24).height(24).margin({ top: 8, right: 8 })
    }
    .width('100%').aspectRatio(1)
    .onClick(() => {
      this.toggle(item.id);
    })
    .accessibilityText('图片' + item.id + (item.selected ? '，已选中' : '，未选中'))
  }
}

// === @Preview mock 组件（DevEco Studio Previewer 预览） ===

@Preview
@Component
struct ImageTransferSelectorPreview {
  build() {
    Stack() {
      Column().width('100%').height('100%').backgroundColor('#F2F2F7')
      ImageTransferSelector()
    }
    .width('100%').height('100%')
  }
}
