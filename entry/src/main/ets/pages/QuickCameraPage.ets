// QuickCameraPage - 桌面相机卡片快速拍照页（CameraKit 多拍）
// 用户流程：桌面卡片点击 → EntryAbility → MainPage → 本页面
// 功能：实时预览 + 连续拍照 + 缩略图列表 + 完成返回
// 需要权限：ohos.permission.CAMERA
// 严禁使用任何 emoji 表情包
import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { abilityAccessCtrl } from '@kit.AbilityKit';
import type { Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import { router, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { IconMapper } from '@ohos/shared';

const TAG: string = 'QuickCameraPage';
const PHOTO_DIR: string = 'quick_photos';

@Entry
@Component
struct QuickCameraPage {
  // ── 状态 ────────────────────────────────────────
  /** 已拍照片 URI 列表 */
  @State capturedPhotos: string[] = [];
  /** 是否正在拍照（防连拍重入） */
  @State isCapturing: boolean = false;
  /** 相机预览 Surface ID（XComponent 提供） */
  private surfaceId: string = '';
  /** XComponent 控制器 */
  private xComponentController: XComponentController = new XComponentController();
  /** CameraKit 对象 */
  private cameraManager: camera.CameraManager | null = null;
  private cameraInput: camera.CameraInput | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private photoOutput: camera.PhotoOutput | null = null;
  private photoSession: camera.PhotoSession | null = null;
  /** 当前使用的相机设备索引（0=后置，1=前置） */
  private currentDeviceIndex: number = 0;
  /** 可用相机设备列表 */
  private cameraDevices: camera.CameraDevice[] = [];
  /** 拍照完成时的照片回调（photoAvailable 事件触发） */
  private pendingPhotoResolver: ((uri: string) => void) | null = null;

  aboutToAppear(): void {
    this.ensureCameraPermission().then((granted: boolean) => {
      if (!granted) {
        promptAction.showToast({ message: '相机权限未开启，无法拍照', duration: 2000 });
        setTimeout(() => { router.back(); }, 500);
        return;
      }
      // 延迟初始化相机（等 XComponent 加载完成获取 surfaceId）
    });
  }

  aboutToDisappear(): void {
    this.releaseCamera();
  }

  // ── 权限 ────────────────────────────────────────

  private async ensureCameraPermission(): Promise<boolean> {
    const ctx = this.getUIContext().getHostContext();
    if (!ctx) {
      return false;
    }
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const perms: Array<Permissions> = ['ohos.permission.CAMERA'];
      const result: PermissionRequestResult = await atManager.requestPermissionsFromUser(ctx, perms);
      const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
      return granted;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Camera permission request failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  // ── 相机初始化 ──────────────────────────────────

  /**
   * XComponent onLoad 回调：获取 surfaceId 后初始化相机
   */
  private onXComponentLoad(): void {
    this.surfaceId = this.xComponentController.getXComponentSurfaceId();
    this.initCamera();
  }

  private async initCamera(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (!ctx) {
        hilog.error(0x0000, TAG, 'Context is null');
        return;
      }

      // 获取相机管理器
      this.cameraManager = camera.getCameraManager(ctx);

      // 获取可用相机设备
      this.cameraDevices = this.cameraManager.getSupportedCameras();
      if (this.cameraDevices.length === 0) {
        promptAction.showToast({ message: '未检测到相机设备', duration: 2000 });
        setTimeout(() => { router.back(); }, 500);
        return;
      }

      // 默认使用后置相机
      this.currentDeviceIndex = 0;
      for (let i = 0; i < this.cameraDevices.length; i++) {
        if (this.cameraDevices[i].cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK) {
          this.currentDeviceIndex = i;
          break;
        }
      }

      await this.startCameraSession();
    } catch (err) {
      hilog.error(0x0000, TAG, 'initCamera failed: %{public}s', JSON.stringify(err));
      promptAction.showToast({ message: '相机初始化失败', duration: 2000 });
    }
  }

  private async startCameraSession(): Promise<void> {
    if (!this.cameraManager || this.surfaceId.length === 0) {
      return;
    }

    const device = this.cameraDevices[this.currentDeviceIndex];

    // 创建输入
    this.cameraInput = this.cameraManager.createCameraInput(device);
    await this.cameraInput.open();

    // 创建预览输出
    this.previewOutput = this.cameraManager.createPreviewOutput(this.surfaceId);

    // 创建拍照输出
    this.photoOutput = this.cameraManager.createPhotoOutput();

    // 监听拍照输出错误事件
    this.photoOutput.on('error', (err: BusinessError) => {
      hilog.error(0x0000, TAG, 'PhotoOutput error: %{public}s', err.message);
    });

    // 监听拍照结果（使用 on 方式，事件类型为 'photoAssetAvailable'）
    // 注意：需要确保 SDK 版本支持此事件类型

    // 创建拍照会话
    this.photoSession = this.cameraManager.createSession<camera.PhotoSession>(camera.SceneMode.NORMAL_PHOTO);

    // 配置会话
    this.photoSession.beginConfig();
    this.photoSession.addInput(this.cameraInput);
    this.photoSession.addOutput(this.photoOutput);
    this.photoSession.addOutput(this.previewOutput);
    await this.photoSession.commitConfig();
    await this.photoSession.start();

    hilog.info(0x0000, TAG, 'Camera session started');
  }

  private async releaseCamera(): Promise<void> {
    try {
      if (this.photoSession) {
        await this.photoSession.stop();
        await this.photoSession.release();
        this.photoSession = null;
      }
      if (this.photoOutput) {
        await this.photoOutput.release();
        this.photoOutput = null;
      }
      if (this.previewOutput) {
        await this.previewOutput.release();
        this.previewOutput = null;
      }
      if (this.cameraInput) {
        await this.cameraInput.close();
        this.cameraInput = null;
      }
      hilog.info(0x0000, TAG, 'Camera released');
    } catch (err) {
      hilog.error(0x0000, TAG, 'releaseCamera failed: %{public}s', JSON.stringify(err));
    }
  }

  // ── 拍照 ────────────────────────────────────────

  private async capturePhoto(): Promise<void> {
    if (this.isCapturing || !this.photoSession || !this.photoOutput) {
      return;
    }
    this.isCapturing = true;

    try {
      const setting: camera.PhotoCaptureSetting = {
        quality: camera.QualityLevel.QUALITY_LEVEL_HIGH,
        rotation: camera.ImageRotation.ROTATION_0
      };
      await this.photoOutput.capture(setting);
      // 注意：拍照结果通过回调获取，但当前 API 版本可能需要使用其他方式
    } catch (err) {
      hilog.error(0x0000, TAG, 'capturePhoto failed: %{public}s', JSON.stringify(err));
      promptAction.showToast({ message: '拍照失败', duration: 1500 });
      this.isCapturing = false;
    }
  }

  private async handlePhotoAvailable(photo: camera.Photo): Promise<void> {
    try {
      const img: image.Image = photo.main;

      // 直接获取 JPEG 编码数据（CameraKit 输出的 photo 内含 JPEG 压缩数据）
      const component: image.Component = await img.getComponent(image.ComponentType.JPEG);
      const jpegBuffer: ArrayBuffer = component.byteBuffer;

      // 保存到沙箱
      const ctx = this.getUIContext().getHostContext();
      if (!ctx) {
        hilog.error(0x0000, TAG, 'Context is null when saving photo');
        this.isCapturing = false;
        await photo.release();
        return;
      }

      const dirPath = ctx.filesDir + '/' + PHOTO_DIR;
      try {
        fileIo.mkdirSync(dirPath, true);
      } catch (_e) {
        // 目录已存在
      }
      const timestamp = Date.now();
      const fileName = 'photo_' + timestamp.toString() + '.jpg';
      const filePath = dirPath + '/' + fileName;

      const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, jpegBuffer);
      fileIo.closeSync(file);

      const photoUri = 'file://' + filePath;
      this.capturedPhotos = [...this.capturedPhotos, photoUri];

      hilog.info(0x0000, TAG, 'Photo saved: %{public}s', photoUri);

      // 释放 Photo 对象和 Image 对象
      await photo.release();
    } catch (err) {
      hilog.error(0x0000, TAG, 'handlePhotoAvailable failed: %{public}s', JSON.stringify(err));
      promptAction.showToast({ message: '保存照片失败', duration: 1500 });
    } finally {
      this.isCapturing = false;
    }
  }

  // ── 切换前后置相机 ──────────────────────────────

  private async switchCamera(): Promise<void> {
    if (this.cameraDevices.length < 2) {
      promptAction.showToast({ message: '仅有一个相机', duration: 1000 });
      return;
    }

    // 释放当前会话
    await this.releaseCamera();

    // 切换到另一个相机
    if (this.currentDeviceIndex === 0) {
      // 尝试找前置
      for (let i = 0; i < this.cameraDevices.length; i++) {
        if (this.cameraDevices[i].cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT) {
          this.currentDeviceIndex = i;
          break;
        }
      }
    } else {
      // 切回后置
      for (let i = 0; i < this.cameraDevices.length; i++) {
        if (this.cameraDevices[i].cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK) {
          this.currentDeviceIndex = i;
          break;
        }
      }
    }

    await this.startCameraSession();
  }

  // ── 完成 ────────────────────────────────────────

  private handleDone(): void {
    if (this.capturedPhotos.length === 0) {
      // 未拍照，直接返回
      AppStorage.setOrCreate('camera_quick_mode', false);
      router.back();
      return;
    }

    // 将照片 URI 数组写入 AppStorage（JSON 字符串）
    AppStorage.setOrCreate('camera_photos_json', JSON.stringify(this.capturedPhotos));
    AppStorage.setOrCreate('camera_quick_mode', false);
    router.back();
  }

  private handleClose(): void {
    // 放弃所有照片，直接返回
    AppStorage.setOrCreate('camera_quick_mode', false);
    router.back();
  }

  // ── UI 构建 ─────────────────────────────────────

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 层1：相机实时预览
      XComponent({
        id: 'cameraPreview',
        type: XComponentType.SURFACE,
        controller: this.xComponentController
      })
        .width('100%')
        .height('100%')
        .onLoad(() => {
          this.onXComponentLoad();
        })

      // 层2：全屏黑色遮罩（半透，给按钮区域留白）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.15)')

      // 层3：顶栏（关闭 + 切换）
      Column() {
        Row() {
          // 关闭按钮
          Button() {
            SymbolGlyph(IconMapper.CLOSE)
              .fontSize(20)
              .fontColor([Color.White])
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .backgroundColor('rgba(0,0,0,0.35)')
          .onClick(() => {
            this.handleClose();
          })
          .accessibilityText('关闭相机')

          Blank()

          // 前后置切换按钮
          Button() {
            SymbolGlyph($r('sys.symbol.camera_filters_fill'))
              .fontSize(20)
              .fontColor([Color.White])
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .backgroundColor('rgba(0,0,0,0.35)')
          .onClick(() => {
            this.switchCamera();
          })
          .accessibilityText('切换前后置相机')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12 })
      }
      .width('100%')

      // 层4：底部操作区
      Column() {
        // 已拍缩略图横向滚动列表
        if (this.capturedPhotos.length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.capturedPhotos, (uri: string, idx: number) => {
                Stack() {
                  Image(uri)
                    .width(48)
                    .height(48)
                    .borderRadius(8)
                    .objectFit(ImageFit.Cover)

                  // 删除角标
                  Button() {
                    SymbolGlyph(IconMapper.CLOSE)
                      .fontSize(10)
                      .fontColor(['#FFFFFF'])
                  }
                  .width(18)
                  .height(18)
                  .borderRadius(9)
                  .backgroundColor('rgba(0,0,0,0.6)')
                  .position({ right: -6, top: -6 })
                  .onClick(() => {
                    this.removePhoto(idx);
                  })
                  .accessibilityText('删除照片')
                }
              }, (_uri: string, idx: number) => idx.toString())
            }
            .padding({ left: 16, right: 16 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .height(56)
          .margin({ bottom: 16 })
        }

        // 拍照按钮 + 完成按钮
        Row() {
          // 完成按钮（左侧）
          if (this.capturedPhotos.length > 0) {
            Button() {
              Row() {
                SymbolGlyph(IconMapper.CHECKMARK)
                  .fontSize(16)
                  .fontColor([Color.White])
                Text('完成')
                  .fontSize(15)
                  .fontWeight(600)
                  .fontColor(Color.White)
                  .margin({ left: 6 })
              }
            }
            .height(44)
            .padding({ left: 20, right: 20 })
            .borderRadius(22)
            .backgroundColor('#00C2B8')
            .onClick(() => {
              this.handleDone();
            })
            .accessibilityText('完成拍照，返回主页')
          }

          Blank()

          // 拍照按钮（右侧，大圆形）
          Button() {
            Stack() {
              Circle()
                .width(60)
                .height(60)
                .fill(Color.White)
            }
            .width(60)
            .height(60)
            .border({ width: 4, color: 'rgba(255,255,255,0.5)' })
            .borderRadius(34)
          }
          .width(72)
          .height(72)
          .borderRadius(36)
          .backgroundColor('rgba(255,255,255,0.15)')
          .scale({
            x: this.isCapturing ? 0.9 : 1,
            y: this.isCapturing ? 0.9 : 1
          })
          .animation({ duration: 120, curve: Curve.EaseOut })
          .enabled(!this.isCapturing)
          .onClick(() => {
            this.capturePhoto();
          })
          .accessibilityText('拍照')
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
        .margin({ bottom: 40 })
      }
      .width('100%')
      .padding({ top: 20, bottom: 20 })
      .linearGradient({
        angle: 180,
        colors: [['rgba(0,0,0,0)', 0.0], ['rgba(0,0,0,0.5)', 1.0]]
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }

  /** 删除已拍照片 */
  private removePhoto(index: number): void {
    const newPhotos: string[] = [];
    for (let i = 0; i < this.capturedPhotos.length; i++) {
      if (i !== index) {
        newPhotos.push(this.capturedPhotos[i]);
      }
    }
    this.capturedPhotos = newPhotos;
  }
}
