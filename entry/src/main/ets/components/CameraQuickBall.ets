// CameraQuickBall - 快速拍照悬浮球组件
// 显示最后一张照片缩略图 + 数量角标
// 可拖动、点击跳日记编辑页、长按关闭
// 严禁使用任何 emoji 表情包
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display } from '@kit.ArkUI';

const TAG: string = 'CameraQuickBall';
const BALL_SIZE: number = 60;
const BALL_MARGIN: number = 20;

/** 路由参数接口（传照片给 DiaryEditPage，复用现有 images 字段） */
interface DiaryPhotoParams {
  images: string[];
}

@Component
export struct CameraQuickBall {
  /** 照片 URI 数组 */
  @Prop photoUris: string[] = [];
  /** 关闭回调 */
  onClose?: () => void;
  /** 悬浮球缩放（出现动画） */
  @State private ballScale: number = 0;
  /** 悬浮球透明度（出现动画） */
  @State private ballOpacity: number = 0;
  /** 位置（绝对坐标） */
  @State private posX: number = 0;
  @State private posY: number = 0;
  /** 拖动起始位置 */
  private dragStartX: number = 0;
  private dragStartY: number = 0;

  aboutToAppear(): void {
    // 计算初始位置：屏幕右下角（display 返回像素，position 使用 vp，需换算）
    try {
      const d = display.getDefaultDisplaySync();
      const density: number = d.densityPixels > 0 ? d.densityPixels : 3;
      const vpWidth: number = d.width / density;
      const vpHeight: number = d.height / density;
      this.posX = vpWidth - BALL_SIZE - BALL_MARGIN;
      this.posY = vpHeight - BALL_SIZE - 120; // 高于底部导航栏
    } catch (_e) {
      // 兜底
      this.posX = 300;
      this.posY = 600;
    }
    // 出现动画：scale 0→1 + opacity 0→1
    animateTo({
      duration: 400,
      curve: Curve.EaseOut,
      onFinish: () => {}
    }, () => {
      this.ballScale = 1;
      this.ballOpacity = 1;
    });
  }

  build() {
    Stack() {
      // 最后一张照片缩略图（圆形裁切）
      Image(this.photoUris[this.photoUris.length - 1])
        .width(56)
        .height(56)
        .borderRadius(28)
        .objectFit(ImageFit.Cover)

      // 玻璃边框环
      Circle()
        .width(58)
        .height(58)
        .fill(Color.Transparent)
        .border({ width: 2, color: 'rgba(255,255,255,0.6)' })

      // 右上角数量角标
      if (this.photoUris.length > 1) {
        Text(this.photoUris.length.toString())
          .fontSize(11)
          .fontWeight(700)
          .fontColor(Color.White)
          .width(18)
          .height(18)
          .borderRadius(9)
          .backgroundColor('#00C2B8')
          .textAlign(TextAlign.Center)
          .position({ right: -4, top: -4 })
      }
    }
    .width(BALL_SIZE)
    .height(BALL_SIZE)
    .scale({ x: this.ballScale, y: this.ballScale })
    .opacity(this.ballOpacity)
    .shadow({
      radius: 10,
      color: 'rgba(0,0,0,0.25)',
      offsetX: 0,
      offsetY: 3
    })
    .position({
      x: this.posX,
      y: this.posY
    })
    .onClick(() => {
      this.navigateToDiaryEdit();
    })
    .gesture(
      // 拖动 + 长按组合（同一手势组，避免 .gesture() 覆盖）
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ duration: 800 })
          .onAction(() => {
            this.closeBall();
          }),
        PanGesture({ distance: 8 })
          .onActionStart((event: GestureEvent) => {
            this.dragStartX = this.posX;
            this.dragStartY = this.posY;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.posX = this.dragStartX + event.offsetX;
            this.posY = this.dragStartY + event.offsetY;
          })
      )
    )
    .accessibilityText('快速拍照：' + this.photoUris.length + '张照片，点击进入日记编辑')
  }

  /** 跳转到日记编辑页（携带所有照片 URI） */
  private navigateToDiaryEdit(): void {
    try {
      // 标记悬浮球已消费（返回 MainPage 时 onPageShow 读取后清除）
      AppStorage.setOrCreate('camera_ball_consumed', true);
      const params: DiaryPhotoParams = {
        images: this.photoUris
      };
      router.pushUrl({ url: 'pages/DiaryEditPage', params: params }).catch((err: Error) => {
        hilog.error(0x0000, TAG, 'pushUrl DiaryEditPage failed: %{public}s', err.message);
      });
    } catch (err) {
      hilog.error(0x0000, TAG, 'navigateToDiaryEdit failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 关闭悬浮球（缩小 + 淡出动画） */
  private closeBall(): void {
    animateTo({
      duration: 250,
      curve: Curve.EaseIn,
      onFinish: () => {
        if (this.onClose) {
          this.onClose();
        }
      }
    }, () => {
      this.ballScale = 0;
      this.ballOpacity = 0;
    });
  }
}
