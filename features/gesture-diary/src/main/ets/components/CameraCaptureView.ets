// <!-- agentID: HUI-061 -->
// 组件：相机取景框 + 拍照按钮 + 拍照后预览（重拍/使用照片）
// 关联任务：P2-09 手势日记流程页统一薄荷青皮肤（UX-001 §6.3）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 图标来源：harmonyos-symbol → xmark（关闭）
// 图标来源：harmonyos-symbol → camera_filters_fill（滤镜/前后置切换）
// 图标来源：harmonyos-symbol → arrow_clockwise（重拍）
// 图标来源：harmonyos-symbol → checkmark（使用照片，IconMapper.CHECKMARK ✅）
// 设计规范：取景框 RADIUS.cardLg（40vp）
// 运行时崩溃防范（PROJECT_SPEC §9）：@Prop 默认值不含 $r()；@StorageLink 判空
import type { ThemeColorTokens } from '@ohos/shared';
import { RADIUS, IconMapper } from '@ohos/shared';

@Component
export struct CameraCaptureView {
  @State isCapturing: boolean = false;
  // 拍照后进入预览态（true=已拍照预览，false=取景中）
  @State isPreview: boolean = false;
  // 预览照片：null=mock 无真实图，由父组件传入真实 uri 时可扩展
  @Prop previewImage: Resource | null = null;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  onCapture?: () => void;
  onRetake?: () => void;
  onUsePhoto?: () => void;
  onClose?: () => void;

  private getPrimaryColor(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  // HUI-035：交互色专用 token（雾霾蓝主按钮 / 白按钮文字）
  private getBtnPrimary(): string {
    return this.tokens ? this.tokens.btnPrimary : '#738A9C';
  }

  private getBtnPrimaryText(): string {
    return this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF';
  }

  build() {
    Column() {
      // 顶栏：关闭 + 切换
      Row() {
        Button() {
          SymbolGlyph(IconMapper.CLOSE).fontSize(20).fontColor([Color.White])
        }
        .width(44).height(44).borderRadius(22)
        .backgroundColor('rgba(0,0,0,0.3)')
        .onClick(() => { if (this.onClose) { this.onClose(); } })
        .accessibilityText('关闭相机')

        Blank()

        Button() {
          SymbolGlyph($r('sys.symbol.camera_filters_fill')).fontSize(20).fontColor([Color.White])
        }
        .width(44).height(44).borderRadius(22)
        .backgroundColor('rgba(0,0,0,0.3)')
        .enabled(!this.isPreview)
        .opacity(this.isPreview ? 0.3 : 1)
        .accessibilityText('切换镜头/滤镜')
      }.width('100%').padding(16)

      // 取景框 / 预览框
      Stack() {
        Column()
          .width('100%').aspectRatio(4 / 3).borderRadius(RADIUS.cardLg)
          .backgroundColor('#000000')
          .border({ width: 2, color: 'rgba(255,255,255,0.3)' })

        // 预览态：展示照片占位；取景态：九宫格辅助线
        if (this.isPreview) {
          if (this.previewImage) {
            Image(this.previewImage)
              .width('100%').aspectRatio(4 / 3).borderRadius(RADIUS.cardLg)
              .objectFit(ImageFit.Cover)
          } else {
            Column() {
              SymbolGlyph($r('sys.symbol.picture')).fontSize(48).fontColor(['rgba(255,255,255,0.6)'])
              Text('照片预览').fontSize(14).fontColor('rgba(255,255,255,0.6)').margin({ top: 8 })
            }
            .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
            .width('100%').aspectRatio(4 / 3)
          }
        } else {
          Column().width('100%').aspectRatio(4 / 3).borderRadius(RADIUS.cardLg)
            .border({ width: 1, color: 'rgba(255,255,255,0.15)' })
        }
      }.width('100%').padding({ left: 16, right: 16 })

      Blank()

      // 底部操作区
      if (this.isPreview) {
        // 预览态：重拍 / 使用照片
        Row() {
          Button() {
            Row() {
              SymbolGlyph(IconMapper.REFRESH).fontSize(18).fontColor([Color.White])
              Text('重拍').fontSize(15).fontColor(Color.White).margin({ left: 6 })
            }
          }
          .height(48).padding({ left: 24, right: 24 }).borderRadius(24)
          .backgroundColor('rgba(255,255,255,0.2)')
          .onClick(() => {
            this.isPreview = false;
            this.isCapturing = false;
            if (this.onRetake) { this.onRetake(); }
          })
          .accessibilityText('重新拍照')

          Button() {
            Row() {
              SymbolGlyph(IconMapper.CHECKMARK).fontSize(18).fontColor([this.getBtnPrimaryText()])
              Text('使用照片').fontSize(15).fontWeight(600).fontColor(this.getBtnPrimaryText()).margin({ left: 6 })
            }
          }
          .height(48).padding({ left: 24, right: 24 }).borderRadius(24)
          .backgroundColor(this.getBtnPrimary())
          .margin({ left: 20 })
          .onClick(() => { if (this.onUsePhoto) { this.onUsePhoto(); } })
          .accessibilityText('使用这张照片')
        }
        .justifyContent(FlexAlign.Center)
        .width('100%').margin({ bottom: 40 })
      } else {
        // 取景态：大圆形拍照按钮
        Button() {
          Stack() {
            Circle({ width: 64, height: 64 }).fill(Color.White)
          }
          .width(64).height(64)
          .border({ width: 4, color: 'rgba(255,255,255,0.5)' })
          .borderRadius(36)
        }
        .width(76).height(76).borderRadius(38)
        .backgroundColor('rgba(255,255,255,0.2)')
        .scale({ x: this.isCapturing ? 0.92 : 1, y: this.isCapturing ? 0.92 : 1 })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onClick(() => {
          this.isCapturing = true;
          this.isPreview = true;
          if (this.onCapture) { this.onCapture(); }
        })
        .accessibilityText('拍照')
        .margin({ bottom: 40 })
      }
    }
    .width('100%').height('100%')
    .backgroundColor('#000000')
  }
}

// === @Preview mock 组件（DevEco Studio Previewer 预览） ===

@Preview
@Component
struct CameraCaptureViewPreview {
  build() {
    Column() {
      Row() {
        Button() {
          SymbolGlyph(IconMapper.CLOSE).fontSize(20).fontColor([Color.White])
        }.width(44).height(44).borderRadius(22).backgroundColor('rgba(0,0,0,0.3)')
        Blank()
        Button() {
          SymbolGlyph($r('sys.symbol.camera_filters_fill')).fontSize(20).fontColor([Color.White])
        }.width(44).height(44).borderRadius(22).backgroundColor('rgba(0,0,0,0.3)')
      }.width('100%').padding(16)

      Stack() {
        Column().width('100%').aspectRatio(4 / 3).borderRadius(RADIUS.cardLg)
          .backgroundColor('#000000').border({ width: 2, color: 'rgba(255,255,255,0.3)' })
        Column().width('100%').aspectRatio(4 / 3).borderRadius(RADIUS.cardLg)
          .border({ width: 1, color: 'rgba(255,255,255,0.15)' })
      }.width('100%').padding({ left: 16, right: 16 })

      Blank()

      Button() {
        Stack() {
          Circle({ width: 64, height: 64 }).fill(Color.White)
        }.width(64).height(64).border({ width: 4, color: 'rgba(255,255,255,0.5)' }).borderRadius(36)
      }.width(76).height(76).borderRadius(38).backgroundColor('rgba(255,255,255,0.2)').margin({ bottom: 40 })
    }
    .width('100%').height('100%').backgroundColor('#000000')
  }
}
