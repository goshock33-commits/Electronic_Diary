# lottie

> **推荐使用 [lottie-turbo](https://gitcode.com/CPF-ApplicationTPC/lottie_turbo)：声明式调用更加简洁，支持并行加载、内存缓存、子线程渲染，性能优化 30%+，多动画/复杂动画场景下 UI 界面更流畅。**

## 版本推荐

| 版本 | 发布日期 | 状态 | 说明 |
|------|----------|------|------|
| v2.0.31 | 2026-05-21 | ✅ 推荐最新稳定版 | 推荐用于新项目与常规升级 |
| v2.0.30 | 2026-04-15 | 稳定（旧版） | 暂不升级可继续使用 |

## v2.0.31 兼容升级 —— 稳定性提升 <sub>2026-05-21</sub>

推荐升级到 v2.0.31，增强边界场景健壮性，避免空值场景下的异常。

> **声明：** 从 v2.0.30 起升级至 v2.0.31 均为兼容性升级，开发者无需修改现有代码。

本次升级聚焦该库稳定性提升。

### 🔧 稳定性提升
- 增强代码健壮性，防止从空 `canvasShadow` 对象及空 `dynamicProperties` 数组读取属性时抛出异常，避免空指针场景下的崩溃 [#353](https://gitcode.com/CPF-ApplicationTPC/lottieArkTS/pull/353)
- 增强代码健壮性，处理从空 `this.elements[i]` 读取属性及从空 `assetData` 读取图片资源导致的异常，覆盖更多边界场景 [#348](https://gitcode.com/CPF-ApplicationTPC/lottieArkTS/pull/348)

### 🔄 兼容性说明
- 无 Breaking Changes，API 接口保持不变
- 仅内部实现优化，现有代码无需修改

> 📄 **完整变更历史与 Issue 修复细节，请参阅：** [CHANGELOG.md](./CHANGELOG.md)

## 简介

lottie 是适用于 OpenHarmony 的动画库，支持解析 Adobe After Effects 软件通过 Bodymovin 插件导出的 JSON 格式动画，并在移动设备上进行本地渲染。

本库基于业界成熟的 Lottie 动画引擎实现，提供了完整的动画播放控制能力，支持多种动画效果和渲染特性，为 OpenHarmony 应用带来流畅、高质量的动画体验。

**核心功能：**

- **动画解析与渲染**：完整支持 Adobe After Effects 通过 Bodymovin 插件导出的 JSON 格式动画文件，在 OpenHarmony 设备上进行高性能本地渲染
- **多种加载方式**：支持从本地文件、json数据、网络 URL 加载动画资源，满足不同场景需求
- **播放控制**：提供播放、暂停、停止、跳转、速度控制、方向控制等完整的动画播放控制能力
- **高级特性**：支持动画片段播放、颜色修改、填充模式设置、帧率控制等高级功能
- **性能优化**：支持动画不可见时自动跳过绘制，减少功耗
- **资源管理**：支持外部图片资源加载、缓存管理、内存优化等资源管理功能

**适用场景：**

- 应用启动动画和过渡动画
- 交互式动画反馈（如按钮点击、列表加载等）
- 复杂的视觉特效和动画展示
- 游戏、教育、娱乐类应用中的动画场景
- 需要高质量动画体验的商业应用

## 效果展示

![showlottie](./screenshot/showlottie.gif)

## 下载安装

```bash
ohpm install @ohos/lottie
```

OpenHarmony ohpm 环境配置等更多内容，请参考[如何安装 OpenHarmony ohpm 包](https://gitcode.com/openharmony-tpc/docs/blob/master/OpenHarmony_har_usage.md)。

## 约束与限制

### 兼容性

在下述版本验证通过：
- DevEco Studio: NEXT Developer Beta3(5.0.3.524), SDK: API12(5.0.0.25), ROM: 5.0.0.25;
- DevEco Studio: NEXT Developer Beta1(5.0.3.122), SDK: API12(5.0.0.18), ROM: 5.0.0.18;

### 权限要求

```json5
  "requestPermissions": [
    {
      "name": "ohos.permission.INTERNET",
      "usedScene": {
        "abilities": [
          "EntryAbility"
        ],
        "when": "always"
      }
    },
    {
      "name": "ohos.permission.GET_NETWORK_INFO",
      "usedScene": {
        "abilities": [
          "EntryAbility"
        ],
        "when": "always"
      }
    }
  ]
```

## 使用示例

### 完整示例

```typescript
import lottie, { AnimationItem } from '@ohos/lottie';

@Entry
@Component
struct Index {
  // 构建渲染上下文
  private renderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasRenderingContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings);
  private animateItem: AnimationItem | null = null;
  private animateName: string = 'animation';

  // 页面销毁时释放动画资源
  aboutToDisappear(): void {
    console.info('aboutToDisappear');
    lottie.destroy();
  }

  build() {
    Row() {
      // 关联画布
      Canvas(this.canvasRenderingContext)
        .width(200)
        .height(200)
        .backgroundColor(Color.Gray)
        .onReady(() => {
          // 加载动画
          if (this.animateItem != null) {
            // 可在此生命回调周期中加载动画，可以保证动画尺寸正确
            this.animateItem?.resize();
          } else {
            // 抗锯齿的设置
            this.canvasRenderingContext.imageSmoothingEnabled = true;
            this.canvasRenderingContext.imageSmoothingQuality = 'medium';
            this.loadAnimation();
          }
        })
    }
  }

  loadAnimation() {
    this.animateItem = lottie.loadAnimation({
      container: this.canvasRenderingContext,
      renderer: 'canvas', // canvas 渲染模式
      loop: true,
      autoplay: false,
      name: this.animateName,
      contentMode: 'Contain',
      path: 'common/animation.json',
    })
    // 因为动画是异步加载，所以对 animateItem 的操作需要放在动画加载完成回调里操作
    this.animateItem.addEventListener('DOMLoaded', (args: Object): void => {
      this.animateItem.changeColor([225, 25, 100, 1]);
      this.animateItem.play();
    });
  }

  destroy() {
    this.animateItem.removeEventListener('DOMLoaded');
    lottie.destroy(this.animateName);
    this.animateItem = null;
  }
}
```

### 注意事项

- 1.建议在 canvas 的 onReady 方法中加载动画，并在加载该动画之前先调用 lottie.destroy(name) 方法，以确保动画不会重复加载。
- 2.建议对动画animateItem的操作放在addEventListener的'DOMLoaded'回调监听中，确保在完全构建并解析完成后，再执行与动画相关的操作，从而避免潜在的加载顺序问题。因为如果是同一个代码块，动画的加载是异步加载的。
- 3.建议添加动画抗锯齿，如示例代码67到68行，以减少动画边缘的锯齿状现象，使动画画面更加平滑细腻，实现更佳的动画效果。
- 4.动画的销毁，推荐使用lottie.destroy(name)方法，相较于直接使用animateItem.destroy()，性能更友好。
- 5.建议在页面销毁或卸载时，将页面上所有的动画进行销毁，确保页面资源得到妥善管理和释放。
- 6.混淆模式编译报错，建议在对应的模块下的obfuscation-rules.txt文件添加配置：-keep ./oh_modules/@ohos/lottie。
- 7.建议canvas的宽高比例与动画的宽高比例保持一致。例如动画的宽高比是1000 * 2000（即1:2的比例），那么可以将canvas的宽高设置为 200 * 400，同样保持1:2的比例。建议canvas的宽高不要大于动画的原始宽高。
- 8.注意：加载外部资源图片时，若采用指定路径的方式：imagePath:'lottie/images/'，外部资源图片的路径是指rawfile目录下的或者沙箱里file目录下的路径。
- 9.Lottie的JSON文件中引用的外部图片资源，需要存放在rawfile目录下。例如json文件中 "u":"images/"，则在rawfile目录下创建一个名为images的文件夹，存放图片。
- 10.Lottie 读取沙箱动画资源的路径说明与注意事项
  1. 动画资源路径（path 参数）
     当通过 path 参数指定动画资源路径时（例如：path: "lottie/robotYoga.json"），Lottie 的资源查找顺序如下：
     优先读取沙箱 file 目录：首先在沙箱的 file 目录下查找 lottie/robotYoga.json 文件。
     降级读取 rawfile 目录：若沙箱 file 目录中未找到对应资源，则继续在 resources/rawfile 目录下查找相同路径的文件。
     优先级总结：file 目录 > rawfile 目录。

  2. 图片资源路径（imagePath 参数）
     当通过 imagePath 参数指定动画图片资源路径时（例如：imagePath: 'common/images/'），Lottie 的资源查找顺序如下：
     优先读取沙箱 file 目录：首先在沙箱的 file 目录下查找 common/images/ 目录中的图片文件。
     降级读取 rawfile 目录：若沙箱 file 目录中未找到对应图片资源，则继续在 resources/rawfile 目录下查找相同路径的图片文件。
     优先级总结：file 目录 > rawfile 目录。
- 11.若遇到动画首次加载出现空白延迟，可在动画加载时添加 autoSkip: false 参数解决。该问题通常由Canvas可见回调延迟引起。

## 使用说明

### 前提：数据准备

lottie 动画文件是由设计人员使用 Adobe After Effects 软件通过 bodymovin 插件导出 json 格式的文件。

AE 软件创建动画时需要设置动画的宽(w)、高(h)、bodymovin 插件的版本号(v)、帧率(fr)、开始帧(ip)、
结束帧(op)、静态资源信息(assets)、图层信息(layers)等重要信息。

如果仅是用于 demo 测试，可以使用[工程示例中的 json 文件](https://gitcode.com/CPF-ApplicationTPC/lottieArkTS/tree/master/entry/src/main/ets/common/lottie)。

### 1. 在相应的类中引入组件

```typescript
import lottie from '@ohos/lottie';
```

### 2. 构建渲染上下文

```typescript
private mainRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
private mainCanvasRenderingContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.mainRenderingSettings);
```

### 3. 将动画需要的 json 文件放到 pages 同级别目录下，然后引用。(json 路径为 entry/src/main/ets/common/lottie/data.json)

注意：json 文件路径不能使用 ./ 或者 ../ 等相对路径，相对路径获取不到动画源数据，会导致动画加载不出来。

传递给 loadAnimation 方法的路径是相对于 pages 文件夹为基准的，而 index 页面内引入的相对路径的动画是以 index.ets 文件为基准的，两者基准不一致。

所以如果 json 文件放置在 pages 文件夹下，路径应为 'pages/common/data.json' 样式。

```typescript
private path: string = "common/lottie/data.json";
或
private jsonData: string = {"v":"4.6.6","fr":24,"ip":0,"op":72,"w":1000,"h":1000,"nm":"Comp 2","ddd":0,"assets":[],...};
```

### 4. 关联画布

```typescript
Canvas(this.mainCanvasRenderingContext)
  .width('50%')
  .height(360 + 'px')
  .backgroundColor(Color.Gray)
  .onReady(() => {
    // 抗锯齿的设置
    this.mainCanvasRenderingContext.imageSmoothingEnabled = true;
    this.mainCanvasRenderingContext.imageSmoothingQuality = 'medium';
  })
```

注意：canvas 设置的宽高比例建议和动画 json 资源里面的宽高比例一致，如：json 动画资源里的宽高比例是 1:2 ，则 canvas 设置的宽高也是 1:2。
- 想要的抗锯齿效果：mainCanvasRenderingContext.imageSmoothingEnabled = true 与 mainCanvasRenderingContext.imageSmoothingQuality = 'medium'。

- 动画绘制前会对 canvas 画布进行清空处理，画布清空后再绘制动画。

### 5. 加载动画

- 加载动画的时机需要注意，点击按钮加载动画可按照正常逻辑放在点击事件内，如果想要实现进入页面自动播放动画，需要结合 Canvas 组件的 onReady() 生命回调周期实现，加载动画时机需放置在 onReady() 生命周期回调内或及之后。
- 同一 Canvas 组件加载多次/不同动画资源，需要手动销毁动画(lottie.destroy('name'))，之后才可再次加载其他动画资源。

```typescript
lottie.destroy('2016'); // 加载动画前先销毁之前加载的动画
this.animationItem = lottie.loadAnimation({
  container: this.mainCanvasRenderingContext,  // 渲染上下文
  renderer: 'canvas',                          // 渲染方式
  loop: true,                                  // 是否循环播放,默认 true
  autoplay: true,                              // 是否自动播放，默认 true
  name: '2016',                                // 动画名称
  contentMode: 'Contain',                      // 填充的模式
  frameRate: 30,                               // 设置 animator 的刷帧率为 30
  imagePath: 'lottie/images/',                 // 加载读取指定路径下的图片资源
  path: this.path,                             // json 路径
  initialSegment: [10,50]                      // 播放的动画片段
})
或
lottie.loadAnimation({
  container: this.mainCanvasRenderingContext,  // 渲染上下文
  renderer: 'canvas',                          // 渲染方式
  loop: true,                                  // 是否循环播放,默认 true
  autoplay: true,                              // 是否自动播放，默认 true
  contentMode: 'Contain',                      // 填充的模式
  frameRate: 30,                               // 设置 animator 的刷帧率为 30
  animationData: this.jsonData,                // json 对象数据
  initialSegment: [10,50]                      // 播放的动画片段
})
或
lottie.loadAnimation({
  uri: "https://assets7.lottiefiles.com/packages/lf20_sF7uci.json",  // uri 网络资源
  container: this.canvasRenderingContext,                            // 渲染上下文
  renderer: 'canvas',                                                // canvas 渲染模式
  loop: true,                                                        // 是否循环播放,默认 true
  autoplay: true,                                                    // 是否自动播放，默认 true
  name: this.animateName,                                            // 动画名
})
```

- 加载动画时，path 参数和 animationData 参数，二者选其一。
- path 参数：只支持加载 entry/src/main/ets 文件夹下的相对路径，不支持跨包查找文件。
- animationData 参数：可结合 ResourceManager 进行读取资源文件内容进行设置。
- uri 参数：支持加载网络资源和通过 URI 路径方式加载动画，该方式需申请 ohos.permission.INTERNET，ohos.permission.GET_NETWORK_INFO 两个权限。
- 加载外部资源图片：应用默认读取沙箱路径下的图片，如果沙箱下没有对应的资源图片，则会继续读取 rawfile 下的对应资源图片。

### 6. HSP 场景

**使用场景：**
- 当应用采用 HSP（Harmony Shared Package）模块化架构时，动画资源文件通常打包在 HSP 模块中
- 主应用需要加载 HSP 模块内的动画资源时，需要使用 HSP 专用的加载方式
- 适用于大型应用中动画资源集中管理、多模块共享动画资源的场景

**实现原理：**
- HSP 场景下，lottie 加载动画 json 资源文件需通过 animationData 方式加载
- 需要把动画 json 资源文件放在 rawfile 目录下进行读取加载
- 使用 createModuleContext 创建 HSP 模块上下文，通过 ResourceManager 读取资源

**加载方式：**

```typescript
lottie.loadAnimation({
  container: this.mainCanvasRenderingContext,  // 渲染上下文
  renderer: 'canvas',                          // 渲染方式
  loop: true,                                  // 是否循环播放,默认 true
  autoplay: true,                              // 是否自动播放，默认 true
  animationData: this.jsonData,                // json 对象数据
  contentMode: 'Contain',                      // 填充的模式
  initialSegment: [10,50]                      // 播放的动画片段
})
```

- 加载动画时，animationData 参数。
- animationData 参数：可结合 ResourceManager 进行读取资源文件内容进行设置。

```typescript
try {
  application.createModuleContext(getContext(this), 'sharedLibrary').then((data: Context) => {
    this.moduleContext = data;
    this.moduleContext?.resourceManager.getRawFileContent('animation.json',(err: Error,data: Uint8Array) =>{
      if(data === null || data === undefined || data.buffer=== undefined){
        return;
      }
      let resStr = util.TextDecoder.create('utf-8',{ignoreBOM: true});
      let lottieStr = resStr.decodeToString(new Uint8Array(data.buffer));
      this.mLottieData = JSON.parse(lottieStr);
    })
  }).catch((error: BusinessError) => {
  })
} catch (error) {
}
```
#### 6.1 HSP 模块中的资源加载说明
在 HSP（Harmony Shared Package）模块中使用 Lottie 并需要加载外部资源图片时， 必须传入  context  上下文参数 ，以确保 Lottie 能够准确读取该模块下的资源文件（如  rawfile  目录下的图片资源）。
代码示例：
```typescript
import { common } from '@kit.AbilityKit';

// 获取 HSP 模块的独立上下文
let contexts = getContext(this).createModuleContext('sharedLibrary') as common.UIAbilityContext;

// 在加载动画时传入 context 参数
lottie.loadAnimation({
  container: this.animContainer,
  renderer: 'canvas',
  animationData: this.jsonData,
  context: contexts,   // 关键：传入 HSP 模块上下文
  imagePath: 'images/'  // 指定图片资源路径
});
```
注意事项：
- createModuleContext  中的  'sharedLibrary'  需替换为实际的 HSP 模块名称。
- 若不传入正确的  context ，Lottie 将无法读取 HSP 模块内的本地资源，导致图片加载失败。


### 7. 控制动画

- 播放动画

  ```typescript
  lottie.play(); // 所有动画播放
  或
  animationItem.play(); // 当前指定 animationItem 动画播放
  ```

- 停止动画

  ```typescript
  lottie.stop(); // 所有动画停止
  或
  animationItem.stop(); // 当前指定 animationItem 动画停止
  ```

- 暂停动画

  ```typescript
  lottie.pause(); // 所有动画暂停
  或
  animationItem.pause(); // 当前指定 animationItem 动画暂停
  ```

- 切换暂停/播放

  ```typescript
  lottie.togglePause(); // 所有动画切换暂停/播放
  或
  animationItem.togglePause(); // 当前指定 animationItem 动画切换暂停/播放
  ```

- 设置播放速度

  > 注意：speed>0 正向播放, speed<0 反向播放, speed=0 暂停播放, speed=1.0/-1.0 正常速度播放。
  > 播放速度无数值范围限制，可为任意浮点数，数值越大播放速度越快。

  ```typescript
  lottie.setSpeed(1); // 所有动画设置播放速度
  或
  animationItem.setSpeed(1); // 当前指定 animationItem 动画设置播放速度
  ```

- 设置动画播放方向

  > 注意：direction 1 为正向，-1 为反向。

  ```typescript
  lottie.setDirection(1); // 所有动画设置播放方向
  或
  animationItem.setDirection(1); // 当前指定 animationItem 动画设置播放方向
  ```

- 销毁动画

  > 注意：页面不显示或退出页面时，需要销毁动画； 可配合页面生命周期 aboutToDisappear() 及 onPageHide()，或者 Canvas 组件的 onDisAppear() 使用。

  ```typescript
  lottie.destroy(); // 销毁所有动画
  或
  lottie.destroy('name'); // 销毁指定 name 动画
  ```

- 控制动画停止在某一帧或某一时刻

  > 注意：根据第二个参数判断按帧还是按毫秒控制，true 按帧控制，false 按时间控制，缺省默认为 false。

  ```typescript
  animationItem.goToAndStop(250, true);
  或
  animationItem.goToAndStop(5000, false);
  ```

- 控制动画从某一帧或某一时刻开始播放

  > 注意：根据第二参数判断按帧还是按毫秒控制，true 按帧控制，false 按时间控制，缺省默认为 false。

  ```typescript
  animationItem.goToAndPlay(250, true);
  或
  animationItem.goToAndPlay(12000, false);
  ```

- 限定动画资源播放时的整体帧范围，即设置动画片段

  ```typescript
  animationItem.setSegment(5, 15);
  ```

- 播放动画片段

  > 注意：第二参数值为 true 立刻生效， 值为 false 循环下次播放的时候生效。

  ```typescript
  animationItem.playSegments([5, 15], [20, 30], true);
  ```

- 重置动画播放片段，使动画从起始帧开始播放完整动画

  > 注意：参数值为 true 立刻生效，值为 false 循环下次播放的时候生效。

  ```typescript
  animationItem.resetSegments(5, 15);
  ```

- 获取动画时长/帧数

  > 注意：参数值为 true 时获取帧数，值为 false 时获取时间(单位 ms)。

  ```typescript
  animationItem.getDuration();
  ```

- 添加侦听事件

  > 注意：添加和移除的事件监听，回调函数需是同一个，需预先定义，否则将不能正确移除。

  ```typescript
  AnimationEventName = 'drawnFrame' | 'enterFrame' | 'loopComplete' | 'complete' | 'segmentStart' | 'destroy' | 'config_ready' | 'data_ready' | 'DOMLoaded' | 'error' | 'data_failed' | 'loaded_images';

  animationItem.addEventListener("enterFrame", function(){
      // TODO something
  })
  ```

- 更改动画渲染颜色

  > 注意：第一个参数颜色是 RGB/RGBA 值，第二个参数是动画的层次 可不填，第三个参数是对应动画层次的元素的下标值 可不填。

  ```typescript
  animationItem.changeColor([255, 150, 203, 0.8]);  // 修改整个动画的颜色
  或
  animationItem.changeColor([255, 150, 203, 0.8], 2); // 修改该动画第二层的颜色
  或
  animationItem.changeColor([255, 150, 203, 0.8], 2, 2); // 修改该动画第二层第二个元素的颜色
  ```

- 移除侦听事件

  ```typescript
  animationItem.removeEventListener("enterFrame", function(){
      // TODO something
  })
  ```

- 刷新动画布局

  ```typescript
  animationItem.resize();
  ```

- 动画填充模式

  > 注意：动画填充模式共有 5 种：Fill、Cover、Top、Bottom、Contain，其中默认的填充模式是：Contain。

  ```typescript
  animationItem.setContentMode('Cover');

  ```

- 设置动画的刷帧率

  > 注意：设置动画 animator 的刷帧率，范围是 1~120 帧率越大，功耗越严重。

  ```typescript
  animationItem.setFrameRate(30);

  ```

- 清除缓存文件

  > 注意：container 是与 canvas 组件绑定的上下文 CanvasRenderingContext2D，用于本地资源路径 json 文件。

  ```typescript
  lottie.clearFileCache(); // 清除所有通过网络下载到沙箱的动画缓存文件
  或
  lottie.clearFileCache('https://p3-dcd.byteimg.com/obj/motor-mis-img/5ec2c8af22bc17aedafe147a1d38f21d.json'); // 清除指定网络地址对应的动画缓存文件
  或
  lottie.clearFileCache('common/lottie/data_url.json', container); // 清理指定本地动画文件引用的网络资源缓存
  ```

### 8. 动画销毁

- lottie 销毁的时机：动画的销毁一般在 canvas 组件生命周期的 onDisAppear() 方法进行，或者在页面销毁时的 aboutToDisappear() 方法里执行。
- lottie 销毁动画支持以下两种方式：
  1. lottie.destroy：销毁所有动画播放，lottie.destroy(name) 销毁指定 name 的动画， 建议使用该方式销毁动画。
  2. animationItem.destroy：销毁当前指定 animationItem 的动画播放，该销毁方式使用不当可能会引起内存泄漏问题，建议使用 lottie.destroy(name) 销毁方式。
  - 执行this.animationItem.destroy()，只会销毁name为2016的动画，name为cat的动画不会被销毁。建议动画销毁时，使用lottie.destroy方式进行销毁。

**销毁不当的后果：**

1. **内存泄漏**：
   - 若仅创建动画而不主动销毁，animationItem 对象会持续存在，引发内存泄漏
   - 内存泄漏会导致应用占用内存持续增长，最终可能被系统杀死
   - 在页面频繁切换的场景下，未销毁的动画会累积大量内存占用

2. **资源未释放**：
   - 动画相关的 Canvas 资源、图片资源、定时器等不会被正确释放
   - 导致系统资源紧张，影响其他功能正常运行
   - 可能导致 GPU 内存占用过高，影响渲染性能

3. **事件监听器泄漏**：
   - 动画内部的事件监听器不会被清理，持续监听事件
   - 可能导致性能下降和意外行为

**推荐做法：**
```typescript
// 页面销毁时统一销毁所有动画
aboutToDisappear(): void {
  lottie.destroy(); // 销毁所有动画
}

// 或指定名称销毁
aboutToDisappear(): void {
  lottie.destroy('animationName'); // 销毁指定动画
}
```

  > 说明一：当同一个页面中存在多个动画，且动画实例赋值给同一个变量 animationItem 时，使用 animationItem.destroy 销毁动画时，只会销毁最后一个。如下代码示例，将 name 为 cat 和 2016 的动画同时赋值给 this.animationItem，执行 animationItem.destroy() 销毁动画时，仅销毁最后加载的 name 为 2016 动画。name 为 cat 的动画不会被销毁。

  ```typescript
  this.animationItem = lottie.loadAnimation({
    container: this.mainCanvasRenderingContext,  // 渲染上下文
    renderer: 'canvas',                          // 渲染方式
    loop: true,                                  // 是否循环播放,默认 true
    autoplay: true,                              // 是否自动播放，默认 true
    name: 'cat',                                // 动画名称
    contentMode: 'Contain',                      // 填充的模式
    path: this.path,                             // json 路径
    initialSegment: [10,50]                      // 播放的动画片段
  })

  this.animationItem = lottie.loadAnimation({
    container: this.mainCanvasRenderingContext,  // 渲染上下文
    renderer: 'canvas',                          // 渲染方式
    loop: true,                                  // 是否循环播放,默认 true
    autoplay: true,                              // 是否自动播放，默认 true
    name: '2016',                                // 动画名称
    contentMode: 'Contain',                      // 填充的模式
    path: this.path,                             // json 路径
    initialSegment: [10,50]                      // 播放的动画片段
  })

  ```

  > 说明二：当 lottie 未加载完成前（ lottie.loadAnimation 方法和下述方法在同一代码块中同时使用），调用下述方法可能导致设置无效：stop、togglePause、pause、goToAndStop、goToAndPlay、setSegment、getDuration、changeColor、setContentMode。<b>应将上述方法在动画加载完成之后再执行，通过 animationItem.addEventListener('DOMLoaded') 监听动画加载完成，示例如下：</b>

  ```typescript
  // 动画未加载完成，changeColor 和 setContentMode 设置无效
  Button('加载2016')
    .onClick(() => {
      if (this.animationItem2 == null) {
        this.animationItem2 = lottie.loadAnimation({
          container: this.canvasRenderingContext,
          renderer: 'canvas', // canvas 渲染模式
          name: '2016',
          path: 'common/lottie/data.json',
        })
        this.animationItem2.changeColor([255, 150, 203, 0.8]);
        this.animationItem2.setContentMode('Top');
      }
    })
  ```

  ```typescript
  // animationItem.addEventListener('DOMLoaded') 监听后执行方法，changeColor 和 setContentMode 设置有效
  Button('加载2016')
    .onClick(() => {
      if (this.animationItem2 == null) {
        this.animationItem2 = lottie.loadAnimation({
          container: this.canvasRenderingContext,
          renderer: 'canvas', // canvas 渲染模式
          loop: true,
          autoplay: false,
          name: '2016',
          contentMode: 'Contain',
          path: 'common/lottie/data.json',
        })

        this.animationItem2.addEventListener('DOMLoaded', (args: Object): void => {
          this.animationItem2?.changeColor([255, 150, 203, 0.8]);
          // this.animationItem2?.setContentMode('Top');
          // ...
        }); // 动画加载完成，播放之前触发
      }
    })
  ```

### 9. 判断动画资源是否为网络加载使用示例

```typescript
this.isNet = '是否为网络加载' + this.animateItem.isNetLoad;
```

### 10. 日志开关功能

```typescript
LogUtil.mLogLevel = LogUtil.ON; // 打开日志信息
LogUtil.mLogLevel = LogUtil.OFF; // 关闭日志信息
```

### 11. 动画不可见时跳过绘制

lottie 支持动画滑动到不可见区域时，跳过绘制，减少冗余绘制(需要在 API 13 及以上的版本才支持该功能)。当前处理逻辑假定了 lottie 跟一个具体的 canvas 节点已经绑定，但是在一些复杂交互场景下，未能追踪绑定关系变化，使得 UI 逻辑存在复杂变化时出现不适用，包括：

- 预加载场景，此时 canvas 节点跟 lottie 尚无绑定关系。这又包括开发者显式预加载以及 lazyforeach 的 cache 机制引起的系统隐式预加载。
- 节点复用场景，此时节点可能会跟不同的动画形成绑定关系。
- 节点销毁后又重建的场景，此时旧节点已发生变化，新节点的关联关系被重新建立。

以上几种情况，当前都无法处理。导致 lottie 无法准确感知 canvas 节点状态，出现冗余绘制，甚至应该活动时不活动等明显的体验问题。 因此引入以 CanvasRenderingContext2D 为核心的协调员 coordinator 对象，用来跟踪 lottie 动画、 CanvasRenderingContext2D、 Canvas 三者之间的动态关联关系。只有当 lottie 所关联 CanvasRenderingContext2D 对应了一个可见的 canvas 时，才会真正执行绘制，否则都会跳过绘制，避免冗余负载。当 coordinator 无法确认准确的 canvas 节点状态时，引入兼容性处理：当用户未显式调用 bindContext2dToCoordinator 接口时，默认进行绘制，否则不进行绘制等进一步的回调通知。为了避免兼容性处理考虑不周，引入 setAttachedCanvasHasVisibleArea 接口，支持开发者强制修正 context2d 所关联的 canvas 节点状态，以便支持逃生。

**使用场景：**
- **长列表滚动场景**：列表中包含多个动画，用户滚动时大部分动画不可见，需要跳过绘制以节省性能
- **页面切换场景**：页面中有多个动画，用户切换到其他页面时，原页面动画不可见，应停止绘制
- **Tab 切换场景**：多个 Tab 页面各自包含动画，切换 Tab 时不可见动画应跳过绘制
- **复杂动画场景**：单个页面包含多个复杂动画，部分动画被其他元素遮挡时，应跳过不可见动画的绘制

**启用影响：**
- **性能提升**：跳过不可见动画的绘制，减少 CPU/GPU 占用，提升整体性能 30%+
- **功耗降低**：减少不必要的渲染操作，降低设备功耗，延长续航时间
- **内存优化**：避免不可见动画占用过多渲染资源
- **UI 流畅度提升**：减少主线程渲染压力，UI 交互更加流畅

**不启用的后果：**
- **性能浪费**：不可见动画仍然持续绘制，浪费 CPU/GPU 资源
- **功耗增加**：设备持续进行不必要的渲染操作，增加功耗
- **UI 卡顿**：大量不可见动画绘制占用主线程，导致 UI 交互卡顿
- **内存占用**：不可见动画仍占用渲染资源，内存占用较高

**如何开启：**

**方式一：通过 autoSkip 参数（推荐，简单）**
```typescript
lottie.loadAnimation({
  container: this.canvasRenderingContext,
  renderer: 'canvas',
  loop: true,
  autoplay: true,
  autoSkip: true,  // 启用不可见跳过绘制功能
  path: 'common/lottie/data.json'
})
```

**方式二：通过 Coordinator（推荐，更精确控制）**
适用于复杂场景，需要精确控制动画绘制时机。

```typescript
import lottie from '@ohos/lottie';

@Entry
@Component
struct InvisibleAreaAutoPlay {
  private renderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvas2D: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings);

  aboutToAppear(): void {
    lottie.bindContext2dToCoordinator(this.canvas2D);
  }

  aboutToDisappear(): void {
    lottie.unbindContext2dFromCoordinator(this.canvas2D);
    lottie.destroy('robotYoga');
  }

  build() {
    Stack() {
      Canvas(this.canvas2D)
        .width(300)
        .height(300)
        .backgroundColor(Color.Gray)
        .onReady(() => {
          lottie.loadAnimation({
            container: this.canvas2D,
            renderer: 'canvas',
            loop: true,
            autoplay: true,
            contentMode: 'Contain',
            name: 'robotYoga',
            path: 'common/lottie/robotYoga.json'
          })
        })
    }.height('40%')
      .width('100%')
      .backgroundColor(Color.Gray)
  }
}
```

**注意事项：**
- autoSkip 参数默认值为 true，建议保持开启
- Coordinator 方式适用于 API 13 及以上版本
- 在复杂交互场景下（如 LazyForEach、节点复用），推荐使用 Coordinator 方式
- 页面销毁时必须调用 unbindContext2dFromCoordinator 解除绑定

### 12. 防止动画内存泄漏

- 避免使用 @state 修饰动画对象：当使用 @state 来修饰 animationItem 对象时，可能会导致动画无法被正常销毁，从而引发内存泄漏问题。
- 及时销毁动画：当动画不再使用或页面即将销毁时，必须主动销毁动画。若仅创建动画而不主动销毁，animationItem 对象会持续存在，进而引发内存泄漏。建议采用 lottie.destroy(name) 方法来销毁动画。
- 禁止手动清除 destroy 监听事件：手动执行 removeEventListener('destroy') 会清除动画内部自身的销毁回调，导致 lottie.destroy(name) 无法完整执行后续的资源释放流程，从而引发内存泄漏。

## 接口说明

### AnimationItem

| 使用方法                              | 类型                    | 相关描述    |
|-----------------------------------|-----------------------|---------|
| play()                            | name?           | 播放      |
| stop()                            | name?                 | 停止      |
| pause()                           | name?                 | 暂停      |
| togglePause()                     | name?                 | 切换暂停    |
| destroy()                         | name?                 | 销毁动画    |
| goToAndStop()                     | value, isFrame?, name? | 跳到某一时刻并停止 |
| goToAndPlay()                     | value, isFrame?, name? | 跳到某一时刻并播放 |
| setSegment()                      | init,end              | 设置动画片段  |
| playSegments()                    | arr, forceFlag        | 播放指定片段  |
| resetSegments()                   | forceFlag             | 重置动画    |
| setSpeed()                        | speed                 | 设置播放速度  |
| resize()                          | width?, height?       | 刷新动画布局  |
| setDirection()                    | direction             | 设置播放方向  |
| getDuration()                     | isFrames?             | 获取动画时长  |
| addEventListener()                | eventName,callback    | 添加监听状态  |
| removeEventListener()             | name,callback?        | 移除监听状态  |
| changeColor()                     | color, layer?, index? | 更改动画颜色  |
| setContentMode()                  | contentMode           | 设置填充模式  |
| setFrameRate()                    | frameRate             | 设置动画刷帧率 |

### AnimationItem 属性

| 属性名               | 类型                                     | 描述                           |
|-------------------|----------------------------------------|------------------------------|
| name              | string                                 | 动画名称                         |
| isLoaded          | boolean                                | 动画是否已加载完成                    |
| currentFrame      | number                                 | 当前播放帧数，精度为浮点数                |
| currentRawFrame   | number                                 | 相对帧位置                        |
| firstFrame        | number                                 | 动画第一帧                        |
| totalFrames       | number                                 | 动画总帧数                        |
| frameRate         | number                                 | 动画帧率（fps）                    |
| frameMult         | number                                 | 帧倍数                          |
| playSpeed         | number                                 | 当前播放速度                       |
| playDirection     | number                                 | 播放方向，1为正向，-1为反向              |
| playCount         | number                                 | 已播放次数                        |
| isPaused          | boolean                                | 动画是否处于暂停状态                   |
| autoplay          | boolean                                | 是否自动播放                       |
| loop              | boolean \| number                      | 是否循环播放，true为无限循环，number为播放次数 |
| renderer          | any                                    | 渲染器类型                        |
| animationID       | string                                 | 动画唯一标识符                      |
| timeCompleted     | number                                 | 动画完成时间                       |
| segmentPos        | number                                 | 当前片段位置                       |
| isSubframeEnabled | boolean                                | 是否启用子帧渲染                     |
| segments          | AnimationSegment \| AnimationSegment[] | 当前播放的片段数组                    |

### LottiePlayer

| 使用方法                              | 类型                                          | 相关描述                                                       |
|-----------------------------------|---------------------------------------------|------------------------------------------------------------|
| play()                            | name?, onlyCurrentAbility?                  | 播放                                                         |
| stop()                            | name?, onlyCurrentAbility?                  | 停止                                                         |
| pause()                           | name?, onlyCurrentAbility?                  | 暂停                                                         |
| togglePause()                     | name?, onlyCurrentAbility?                  | 切换暂停                                                       |
| destroy()                         | name?, onlyCurrentAbility?                  | 销毁动画                                                       |
| goToAndStop()                     | value, isFrame?, name?, onlyCurrentAbility? | 跳到某一时刻并停止                                                  |
| goToAndPlay()                     | value, isFrame?, name?, onlyCurrentAbility? | 跳到某一时刻并播放                                                  |
| setSpeed()                        | speed, name?, onlyCurrentAbility?           | 设置播放速度                                                     |
| resize()                          | width?, height?, onlyCurrentAbility?        | 刷新动画布局                                                     |
| setDirection()                    | direction, name?, onlyCurrentAbility?       | 设置播放方向                                                     |
| setContentMode()                  | contentMode, name?, onlyCurrentAbility?     | 设置填充模式                                                     |
| loadAnimation()                   | params                                      | 加载动画                                                       |
| setFrameRate()                    | frameRate                                   | 设置动画刷帧率                                                    |
| clearFileCache()                  | url?, container?                            | 清除通过网络下载到沙箱的动画缓存文件                                         |
| bindContext2dToCoordinator()      | CanvasRenderingContext2D                    | 跟踪 lottie动画, CanvasRenderingContext2D, Canvas 三者之间的动态关联关系  |
| unbindContext2dFromCoordinator()  | CanvasRenderingContext2D                    | 解除追踪关系                                                     |
| setAttachedCanvasHasVisibleArea() | CanvasRenderingContext2D, boolean           | 支持强制修正 context2d 所关联的 canvas 节点状态                              |

#### loadAnimation 参数配置

| 字段名 | 类型 | 必填 | 默认值 | 描述 | OpenHarmony平台支持 |
|--------|------|------|--------|------|------|
| container | CanvasRenderingContext2D | 是 | - | 与 canvas 组件绑定的上下文 CanvasRenderingContext2D，提供最基础的绘制渲染能力 | 是 |
| path | string | 否 | - | 应用内的动画数据文件路径，仅支持 entry/src/main/ets 路径下的相对路径，不支持跨包路径设置，与 animationData 二选一 | 是 |
| animationData | any | 否 | - | json 格式的动画数据，与 path 二选一 | 是 |
| renderer | string | 否 | canvas | 渲染类型，目前支持 canvas 方式 | 是 |
| loop | boolean | 否 | true | 动画播放结束后是否循环播放，值为 true 时无限循环播放；值为 number 且 >=1 时为设置重复播放的次数 | 是 |
| autoplay | boolean | 否 | true | 自动播放设置 | 是 |
| initialSegment | AnimationSegment | 否 | - | 初始化动画资源播放时的整体帧范围 | 是 |
| name | string | 否 | - | 动画名称，动画成功加载后，可在 Lottie 相关接口上，应用该名称进行动画控制 | 是 |
| context | common.UIAbilityContext | 否 | - | 应用上下文 Context，在 HSP 场景下需要传正确的 context，非 HSP 场景不影响，context 可以不传 | 是 |
| packageName | string | 否 | - | 应用包名，用于打印日志区分不同模块调用启动 animator，packageName 可以不传 | 是 |
| contentMode | string | 否 | Contain | 动画填充模式，默认值Contain，支持：Fill、Top、Cover、Bottom、Contain | 是 |
| frameRate | number | 否 | - | 设置 animator 的刷帧率，范围 1~120 | 是 |
| uri | string | 否 | - | 读取来自网络路径的动画数据，支持 json 和 zip 格式 | 是 |
| isNetwork | boolean | 否 | - | true 优先读取网络资源，false 优先读取本地缓存资源 | 是 |
| imagePath | string | 否 | - |读取指定路径下的图片资源 | 是 |
| autoSkip | boolean | 否 | true | 当动画不可见时，是否跳过绘制：设为 true 则跳过绘制，设为 false 则不跳过绘制(即无条件绘制) | 是 |
| imageAssetDelegate | Function | 否 | - | 在加载图片时，调用此接口获取获取绘制的 PixelMap 对象 | 是 |
| autoFontSize | boolean | 否 | true | 动画是否随系统设字体放大，设为 false 则不随系统字体放大，设为 true 则随系统字体放大 | 是 |

## 9. 关于混淆

- 代码混淆，请查看[代码混淆简介](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/arkts-utils/source-obfuscation.md)。
- 如果希望 lottie 库在代码混淆过程中不会被混淆，需要在混淆规则配置文件 obfuscation-rules.txt 中添加相应的排除规则。

```text
-keep
./oh_modules/@ohos/lottie
```

## 新增特性

1. 支持 canvas 渲染模式下动画的颜色修改。
- 支持设置 RGB 格式颜色。
- 支持设置 RGBA 格式颜色。
- 支持设置起始关键帧颜色。

2. 支持 canvas 渲染模式下动画的 masks/mattes 部分特性。
- masks 模式支持 mode = a, mode = s, mode = f 模式。
- mattes 模式支持 tt = 1, tt = 2 模式。

3. 支持 canvas 渲染模式下动画的高斯模糊效果。

4. 支持 canvas 渲染模式下加载外部资源图片。
- 支持加载沙箱路径的外部资源图片(优先查找的路径)。
- 支持加载 rawfile 目录下的外部资源图片。

5. 支持设置填充模式。
- Fill 填充拉伸(可能被拉伸、不会被裁剪)。
- Top 等比填充-顶对齐(不会被裁剪、长边对齐)。
- Bottom 等比填充-底对齐(不会被裁剪、长边对齐)。
- Cover 等比缩放填充(可能被裁剪、短边对齐)。
- Contain 等比填充-纵向中对齐(不会被裁剪、长边对齐)。

6. 支持设置动画 animator 的刷帧率。

7. 支持加载网络资源和通过 URI 路径方式加载动画。
- 支持通过 URI 方式指定资源路径渲染动画。
- 支持根据在线资源渲染动画。
- 说明：如果 lottie 文件含有网络资源，需申请 ohos.permission.INTERNET，ohos.permission.GET_NETWORK_INFO 两个权限。

8. 支持当动画处于隐藏状态或完全不可见时，当前动画将自动暂停其向 canvas 底层发送绘制指令，以此优化性能并减少功耗。

## 遗留问题

* 不支持 HTML 渲染方式
* 不支持 SVG 渲染中 filter 效果
* 不支持动画中 masks,mattes 部分特性
* 不支持亮度遮罩模式，即：tt=3
* 不支持组件控制动画显示、隐藏
* 不支持注册动画
* 不支持查找动画
* 不支持更新动画数据
* 不支持部分效果
* 不支持含有表达式的动画
* 不支持动态修改动画文本内容
受系统 API 限制，Lottie 不支持在以下设备或组件上播放动画：
* 卡片组件（Form）：卡片运行在独立进程中，缺少 Lottie 所需的渲染环境。
* 智能穿戴设备：包括智能手表等穿戴设备，受系统资源及图形能力限制，无法支持 Lottie 动画播放。

## 目录结构

```
/lottie        # 项目根目录
├── entry      # 示例代码文件夹
├── library    # lottie 库文件夹
│    └─ src/main/js   # 核心代码，包含 json 解析，动画绘制，操作动画
│          └─ 3rd_party
│          └─ animation
│          └─ effects
│          └─ elements
│          └─ modules
│          └─ renderers
│          └─ utils
│          └─ EffectsManager.js
│          └─ main.js
│          └─ mask.js
│       └─ index.d.ts
├── README.md     # 安装使用方法
├── README_zh.md  # 安装使用方法
```

## 贡献代码

使用过程中发现任何问题都可以提交 [Issue](https://gitcode.com/CPF-ApplicationTPC/lottieArkTS/issues)，当然，也非常欢迎提交 [PR](https://gitcode.com/CPF-ApplicationTPC/lottieArkTS/pulls) 。

## 开源协议

本项目遵循 [MIT License](https://gitcode.com/CPF-ApplicationTPC/lottieArkTS/blob/master/LICENSE)。