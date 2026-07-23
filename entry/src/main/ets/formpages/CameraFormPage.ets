// 桌面卡片：相机卡片（2x2 圆形 + 玻璃质感）
// 展示相机图片，叠加半透玻璃层 + 发光边框 + 高光
// 点击跳转相机页面
@Entry
@Component
struct CameraFormPage {
  build() {
    Stack() {
      // 底层：相机图片（圆形裁切）
      Image($rawfile('cards/camera.jpg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .borderRadius(999)

      // 玻璃叠加层：半透白底
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.form_glass_overlay'))
        .borderRadius(999)

      // 顶部高光（仅上半圆）
      Column()
        .width('100%')
        .height('50%')
        .linearGradient({
          angle: 180,
          colors: [['rgba(255,255,255,0.25)', 0.0], ['rgba(255,255,255,0)', 1.0]]
        })
        .borderRadius({ topLeft: 999, topRight: 999 })

      // 左上角强光光斑
      Column()
        .width(40)
        .height(40)
        .borderRadius(20)
        .radialGradient({
          center: [20, 20],
          radius: 20,
          colors: [['rgba(255,255,255,0.4)', 0.0], ['rgba(255,255,255,0)', 0.7]]
        })
        .position({ x: 8, y: 8 })

      // 星光粒子（2 颗）
      Column() {
        Column()
          .width(1.5)
          .height(5)
          .backgroundColor('rgba(255,255,255,0.5)')
        Column()
          .width(5)
          .height(1.5)
          .backgroundColor('rgba(255,255,255,0.5)')
      }
      .position({ x: 75, y: 20 })

      Column() {
        Column()
          .width(1.5)
          .height(5)
          .backgroundColor('rgba(255,255,255,0.35)')
        Column()
          .width(5)
          .height(1.5)
          .backgroundColor('rgba(255,255,255,0.35)')
      }
      .position({ x: 20, y: 75 })
    }
    .width('100%')
    .height('100%')
    .borderRadius(999)
    .border({ width: 1.5, color: $r('app.color.form_glass_border') })
    .shadow({ radius: 24, color: 'rgba(255,255,255,0.2)', offsetX: 0, offsetY: 0 })
    .shadow({ radius: 10, color: 'rgba(0,0,0,0.1)', offsetX: 0, offsetY: 5 })
    .shadow({ radius: 4, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 2 })
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      postCardAction(this, {
        'action': 'message',
        'message': 'open_camera'
      });
    })
    .accessibilityText('打开相机')
  }
}
