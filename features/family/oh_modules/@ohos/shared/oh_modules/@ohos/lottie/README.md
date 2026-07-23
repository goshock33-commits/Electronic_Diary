# lottie

> **We recommend using [lottie-turbo](https://gitcode.com/CPF-ApplicationTPC/lottie_turbo): Its declarative invocation is more concise, supporting parallel loading, in-memory caching, and sub-thread rendering. This leads to a performance improvement of over 30%, ensuring a smoother UI experience in scenarios with multiple or complex animations.**

## Recommended Versions

| Version | Release Date | Status | Notes |
|---------|--------------|--------|-------|
| v2.0.31 | 2026-05-21 | ✅ Recommended (latest stable) | Recommended for new projects and general upgrades |
| v2.0.30 | 2026-04-15 | Stable (older) | Safe to stay on if not upgrading |

## v2.0.31 Compatible Upgrade — Stability Improvements <sub>2026-05-21</sub>

We recommend upgrading to v2.0.31, which enhances robustness in edge cases and avoids exceptions in null/empty scenarios.

> **Note:** Upgrading to v2.0.31 from v2.0.30 onwards is a compatible upgrade; no code changes are required.

This upgrade focuses on stability improvements of the library.

### 🔧 Stability Improvements
- Enhance code robustness to prevent exceptions when reading properties from null `canvasShadow` objects and null `dynamicProperties` arrays, avoiding crashes in null-pointer scenarios [#353](https://gitcode.com/CPF-ApplicationTPC/lottieArkTS/pull/353)
- Enhance code robustness to handle reading properties from empty `this.elements[i]` and image resources from empty `assetData`, covering more edge cases [#348](https://gitcode.com/CPF-ApplicationTPC/lottieArkTS/pull/348)

### 🔄 Compatibility Notes
- No Breaking Changes; API interfaces remain unchanged
- Only internal implementation optimizations; no changes required to existing code

> 📄 **For the full change history and issue fix details, see:** [CHANGELOG.md](./CHANGELOG.md)

## Introduction

Lottie is an animation library for OpenHarmony that parses Adobe After Effects animations, exported as JSON files with Bodymovin, and renders them natively on mobile devices.

This library is based on the industry-standard Lottie animation engine, providing comprehensive animation playback control capabilities and supporting various animation effects and rendering features, delivering smooth, high-quality animation experiences for OpenHarmony applications.

**Core Features:**

- **Animation Parsing and Rendering**: Fully supports JSON format animation files exported from Adobe After Effects via Bodymovin plugin, with high-performance local rendering on OpenHarmony devices
- **Multiple Loading Methods**: Supports loading animation resources from local files, memory data, and network URLs to meet different scenario requirements
- **Playback Control**: Provides complete animation playback control capabilities including play, pause, stop, seek, speed control, and direction control
- **Advanced Features**: Supports animation segment playback, color modification, fill mode settings, frame rate control, and other advanced features
- **Performance Optimization**: Supports automatic drawing skip when animations are invisible to reduce power consumption
- **Resource Management**: Supports external image resource loading, cache management, memory optimization, and other resource management features

**Use Cases:**

- App startup animations and transition animations
- Interactive animation feedback (such as button clicks, list loading, etc.)
- Complex visual effects and animation displays
- Animation scenes in games, education, and entertainment applications
- Business applications requiring high-quality animation experiences

## Effects demonstration

![showlottie](./screenshot/showlottie_EN.gif)

## Constraints

This project has been verified in the following version:
- DevEco Studio: NEXT Developer Beta3 (5.0.3.524), SDK: API 12 (5.0.0.25), ROM: 5.0.0.25
- DevEco Studio: NEXT Developer Beta1 (5.0.3.122), SDK: API 12 (5.0.0.18), ROM: 5.0.0.18

## How to Install

```bash
ohpm install @ohos/lottie
```

For details about the OpenHarmony ohpm environment configuration, see [OpenHarmony HAR](https://gitcode.com/openharmony-tpc/docs/blob/master/OpenHarmony_har_usage.en.md).

## Access Requirements

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

## Example

### Example

```typescript
import lottie, { AnimationItem } from '@ohos/lottie';

@Entry
@Component
struct Index {
  // Build a rendering context.
  private renderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasRenderingContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings);
  private animateItem: AnimationItem | null = null;
  private animateName: string = "animation"; // name

  // Destroy animation.
  aboutToDisappear(): void {
    console.info('aboutToDisappear');
    lottie.destroy();
  }

  build() {
    Row() {
      // Configure a canvas.
      Canvas(this.canvasRenderingContext)
        .width(200)
        .height(200)
        .backgroundColor(Color.Gray)
        .onReady(() => {
          // Load animation.
          if (this.animateItem != null) {
            // Load animations during canvas onReady, ensure that animation size is correct.
            this.animateItem?.resize();
          } else {
            // Anti-aliasing settings.
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
      renderer: 'canvas', // canvas renderer
      loop: true,
      autoplay: false,
      name: this.animateName,
      contentMode: 'Contain',
      path: 'common/animation.json',
    })
    // Animations are loaded asynchronously, any operations on animateItem should be performed within callback function for when animation has finished loading.
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

### Important Notes

- 1. It is recommended to load of animation in the onReady method of canvas, and call lottie.destroy(name) method before loading of animation to ensure that animation will not be loaded repeatedly.
- 2. It is recommended to put the operation of animation animateItem in the 'DOMLoaded' callback listener of addEventListener, and ensure that animation-related operations are performed after complete construction and parsing are completed, so as to avoid potential loading order problems. Because if it is the same code block, animation is loaded asynchronously.
- 3. It is recommended to add animation anti-aliasing, such as sample code code 67 to 68 line, to reduce the jagged phenomenon of animation edge, make animation screen smoother and more delicate, and achieve best animation effect.
- 4. For the destruction of animation, it is recommended to use lottie.destroy(name) method, which is more performance-friendly than directly using animateItem.destroy().
- 5. It is recommended to destroy all animations on the page when the page is destroyed or uninstalled to ensure that page resources are properly managed and released.
- 6. If obfuscation mode compilation fails, it is recommended to add configuration in the obfuscation-rules.txt file under the corresponding module: -keep ./oh_modules/@ohos/lottie.
- 7. It is recommended that the aspect ratio of canvas be consistent with that of animation. For example, if the aspect ratio of animation is 1000 * 2000 (i.e., a ratio of 1:2), then the width and height of canvas can be set to 200 * 400, also maintaining a ratio of 1:2. It is recommended that the width and height of canvas should not be larger than the original width and height of animation.
- 8. Note: When loading external resource images, if the specified path is used: imagePage:'lottie/images/', the path of the external resource image refers to the path under the rawfile directory or the file directory in the sandbox.
- 9. The external image resources referenced in Lottie's JSON file need to be stored in the rawfile directory. For example, if "u":"images/" in the json file, a folder named images is created in the rawfile directory to store the images.
- 10. Path description and considerations for Lottie to read sandbox animation resources
  1. Animation resource path (path parameter)  
     When specifying the animation resource path through the path parameter (for example: path: "lottie/robotYoga.json"), Lottie's resource lookup order is as follows:  Priority is given to reading the sandbox file directory: First, the lottie/robotYoga.json file is searched in the sandbox's file directory.
     Degrade to read the rawfile directory: If the corresponding resource is not found in the sandbox file directory, continue to search for a file with the same path in the resources/rawfile directory.
     Priority summary: file directory > rawfile directory.

  2. Image resource path (imagePath parameter)
     When specifying the path of animated image resources through the imagePath parameter (for example: imagePath: 'common/images/'), Lottie's resource lookup order is as follows:
     Priority is given to reading the sandbox file directory: First, it will search for image files in the common/images/ directory under the sandbox's file directory.
     Degrade to read rawfile directory: If the corresponding image resource is not found in the sandbox file directory, continue to search for the image file with the same path in the resources/rawfile directory.
     Priority summary: file directory > rawfile directory.
- 11. If you encounter a blank delay during the initial loading of an animation, you can add the parameter `autoSkip: false` during the animation loading to resolve the issue. This problem is usually caused by a delay in the Canvas visibility callback.

## How to Use

### To start off, get required data prepared.

Lottie animations are created in Adobe After Effects and exported with Bodymovin as JSON files.

When creating an animation in Adobe After Effects, you need to set the animation width (**w**), animation height (**h**), bodymovin version (**v**), frame rate (**fr**), start frame (**ip**),
end frame (**op**), static resource information (**assets**), and layer information (**layers**).

For demo test purposes, you can use the [JSON file in the example project](https://gitcode.com/CPF-ApplicationTPC/lottieArkTS/tree/master/entry/src/main/ets/common/lottie).

### 1. Import component to the corresponding class.

   ```typescript
   import lottie from '@ohos/lottie';
   ```

### 2. Build a rendering context.

   ```typescript
     private mainRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
     private mainCanvasRenderingContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.mainRenderingSettings);
   ```

### 3. Place the JSON file required by the animation in the directory at the same level as the **pages** directory and reference the file. (In this example, the JSON file used is **entry/src/main/ets/common/lottie/data.json**).

   Note: The JSON file path cannot be a relative path, such as one that starts with a single dot (.) or double dot (..), followed by a slash (/). Using a relative path will result in a failure to fetch the animation source.

   This is because a relative path referenced in the **index** page is based on the **index.ets** file, whereas the path passed to the **loadAnimation** API is based on the **pages** folder.

   Therefore, if the JSON file is stored in the **pages** folder, the path should be **pages/common/data.json**.

   ```typescript
     private path:string = 'common/lottie/data.json';
     Or
     private jsonData:string = {"v":"4.6.6","fr":24,"ip":0,"op":72,"w":1000,"h":1000,"nm":"Comp 2","ddd":0,"assets":[],...};
   ```

### 4. Configure a canvas.

   ```typescript
          Canvas(this.mainCanvasRenderingContext)
           .width('50%')
           .height(360 + 'px')
           .backgroundColor(Color.Gray)
           .onReady(()=>{
           // Anti-aliasing settings.
               this.mainCanvasRenderingContext.imageSmoothingEnabled = true;
               this.mainCanvasRenderingContext.imageSmoothingQuality = 'medium';
           })
   ```

   Note: It is recommended that the aspect ratio set for the canvas be the same as that of the JSON animation resource. For example, if the aspect ratio of the JSON animation resource is 1:2, the aspect ratio set for the canvas should also be 1:2.

   The anti-aliasing settings in this example: **mainCanvasRenderingContext.imageSmoothingEnabled = true** and **mainCanvasRenderingContext.imageSmoothingQuality = 'medium'**.

   A canvas is cleared before an animation is drawn on it.

### 5. Load animation.

   Pay attention to the time when you want your animation to load. If you want the animation to load upon a button click, simply place the animation loading logic in the click event. If you want the animation to load automatically once the page where it is located is displayed, you must place the animation loading logic within or after the **onReady()** lifecycle callback.

   For a canvas to load one animation multiple times or load different animations, manually destroy the previously loaded animation (by calling **lottie.destroy('name')**) each time before the canvas loads again.

     ```typescript
         lottie.destroy('2016'); // Destroy the previously loaded animation before loading a new one.
         this.animationItem = lottie.loadAnimation({
                 container: this.mainCanvasRenderingContext,  // Rendering context.
                 renderer: 'canvas',                          // Rendering mode.
                 loop: true,                                  // Whether to loop playback. The default value is true.
                 autoplay: true,                              // Whether to enable automatic playback. The default value is true.
                 name: '2016',                                // Animation name.
                 contentMode: 'Contain',                      // Fill mode.
                 frameRate: 30,                               // Set the frame rate to 30.
                 imagePath: 'lottie/images/',                 // Load and read images in the specified path.
                 path: this.path,                             // JSON file path.
                 initialSegment: [10,50]                      // Initial segment of the animation.
               })
          Or
         lottie.loadAnimation({
                 container: this.mainCanvasRenderingContext,  // Rendering context.
                 renderer: 'canvas',                          // Rendering mode.
                 loop: true,                                  // Whether to loop playback. The default value is true.
                 autoplay: true,                              // Whether to enable automatic playback. The default value is true.
                 contentMode: 'Contain',                      // Fill mode.
                 frameRate: 30,                               // Set the frame rate to 30.
                 animationData: this.jsonData,                // JSON object data.
                 initialSegment: [10,50]                      // Initial segment of the animation.
               })
          Or
         lottie.loadAnimation({
                 uri: 'https://assets7.lottiefiles.com/packages/lf20_sF7uci.json', // Internet resources specified by URI.
                 container: this.canvasRenderingContext,                            // Rendering context.
                 renderer: 'canvas',                                                // Canvas rendering mode.
                 loop: true,                                                        // Whether to loop playback. The default value is true.
                 autoplay: true,                                                    // Whether to enable automatic playback. The default value is true.
                 name: this.animateName,                                            // Animation name.
               })
     ```

   To load an animation, use either **path** or **animationData**.

   - **path**: Only relative paths under **entry/src/main/ets** are allowed. Cross-package file search is not supported.
   - **animationData**: Set this parameter based on **ResourceManager**.
   - **uri**: Internet animations can be loaded through URIs. In this case, you must request the permissions **ohos.permission.INTERNET** and **ohos.permission.GET_NETWORK_INFO**.
   - Loading external resource images: By default, the application reads images in the sandbox path. If the specified images are not found in the sandbox, the application searches for them in **rawfile**.

### 6. Load an animation with an HSP.

**Use Cases:**
- When the application uses HSP (Harmony Shared Package) modular architecture, animation resource files are usually packaged in the HSP module
- When the main application needs to load animation resources within the HSP module, HSP-specific loading methods are required
- Suitable for large applications where animation resources are centrally managed and shared across multiple modules

**Implementation Principle:**
- In HSP scenarios, lottie loads JSON resource files through **animationData**
- Animation JSON resource files must be placed in the **rawfile** directory for reading and loading
- Use createModuleContext to create HSP module context and read resources through ResourceManager

**Loading Method:**

   ```typescript
       lottie.loadAnimation({
               container: this.mainCanvasRenderingContext,  // Rendering context.
               renderer: 'canvas',                          // Rendering mode.
               loop: true,                                  // Whether to loop playback. The default value is true.
               autoplay: true,                              // Whether to enable automatic playback. The default value is true.
               animationData: this.jsonData,                // JSON object data.
               contentMode: 'Contain',                      // Fill mode.
               initialSegment: [10,50]                      // Initial segment of the animation.
             })
   ```

   To load an animation, use **animationData**.

   **animationData**: Set this parameter based on **ResourceManager**.

   ```typescript
       let resStr = new util.TextDecoder('utf-8',{ignoreBOM: true});
       let context = getContext(this).createModuleContext('library') as common.UIAbilityContext;
       context.resourceManager.getRawFile('grunt.json',(err: Error,data: Uint8Array) =>{
         if(data === null || data === undefined || data.buffer=== undefined){
           return;
         }
         let lottieStr = resStr.decode(new Uint8Array(data.buffer));
         this.jsonData = JSON.parse(lottieStr);
       })
   ```
#### 6.1 Resource Loading Instructions in HSP Modules
When using Lottie in an HSP (Harmony Shared Package) module and needing to load external image resources, the context parameter must be passed to ensure Lottie can accurately read resource files (e.g., image resources in the rawfile directory) within the module.
Code Example:
```typescript
import { common } from '@kit.AbilityKit';

// Obtain the independent context of the HSP module
let contexts = getContext(this).createModuleContext('sharedLibrary') as common.UIAbilityContext;

// Pass the context parameter when loading the animation
lottie.loadAnimation({
  container: this.animContainer,
  renderer: 'canvas',
  animationData: this.jsonData,
  context: contexts,   // Critical: Pass the HSP module context
  imagePath: 'images/'  // Specify the image resource path
});
```
Notes：
- Replace 'sharedLibrary' in createModuleContext with the actual HSP module name.
- If the correct context is not passed, Lottie will be unable to access local resources within the HSP module, causing image loading failures.

### 7. Control animation playback.

- Play animation.

  ```typescript
  lottie.play(); // Play all animations.
  Or
  animationItem.play(); // Play a given animation.
  ```

- Stop animation.

  ```typescript
  lottie.stop(); // Stop all animations.
  Or
  animationItem.stop(); // Stop a given animation.
  ```

- Pause animation.

  ```typescript
  lottie.pause(); // Pause all animations.
  Or
  animationItem.pause(); // Pause a given animation.
  ```

- Switch animation playback state between running and paused.

  ```typescript
  lottie.togglePause(); // Switch playback state between running and paused for all animations.
  Or
  animationItem.togglePause(); // Switch playback state between running and paused for a given animation.
  ```

- Set playback speed.
   > Note: If speed is greater than **0**, animation plays forwards. If speed is less than **0**, animation plays backwards. If speed is **0**, animation is paused. If speed is **1.0** or **-1.0**, animation plays at the normal speed.
   > Note: Playback speed has no numerical range limitation and can be any floating point number. The larger the absolute value, the faster the playback speed.
 
   ```typescript
   lottie.setSpeed(1); // Set playback speed for all animations.
   Or
   animationItem.setSpeed(1); // Set the playback speed for a given animation.
   ```

- Set playback direction.
  > Note: The value **1** indicates forward, and **-1** indicates backward.

  ```typescript
  lottie.setDirection(1); // Set playback direction for all animations.
  Or
  animationItem.setDirection(1); // Set the playback direction for a given animation.
  ```

- Destroy animation.
  > Note: An animation needs to be destroyed when the page where it is located disappears or exits. The **destroy()** API can be used together with the **aboutToDisappear()** and **onPageHide()** callbacks of the page or the **onDisAppear()** callback of the canvas component.

  ```typescript
  lottie.destroy(); // Destroy all animations.
  Or
  lottie.destroy('name'); // Destroy a given animation.
  ```

- Clear Cache.
  ```typescript
  lottie.clearFileCache(); //Clear animation cache files downloaded to the sandbox through the network.
  Or
  lottie.clearFileCache('path'); //Clear animation cache file corresponding to the specified network address.
  Or
  lottie.clearFileCache('path',container); //Clear cache of network resources referenced by the specified local animation file.
  ```

- Stop animation at a frame or a point of time.
  > Note: The second parameter specifies whether to control by frame or time (in milliseconds). The value **true** means to control by frame, and **false** (default) means to control by time.

  ```typescript
  animationItem.goToAndStop(250,true);
  Or
  animationItem.goToAndStop(5000,false);
  ```

- Start animation from a frame or a point of time.
  > Note: The second parameter specifies whether to control by frame or time (in milliseconds). The value **true** means to control by frame, and **false** (default) means to control by time.
  ```typescript
  animationItem.goToAndPlay(250,true);
  Or
  animationItem.goToAndPlay(12000,false);
  ```

- Set an animation segment to limit the frame range for animation playback.

  ```typescript
  animationItem.setSegment(5,15);
  ```

- Play animation segments.
  > Note: The second parameter specifies whether setting takes effect immediately. The value **true** indicates that setting takes effect immediately, and **false** indicates that the setting takes effect upon the next playback.

  ```typescript
  animationItem.playSegments([5,15],[20,30],true);
  ```

- Reset animation segments so that animation plays from the start frame.
  > Note: The parameter specifies whether setting takes effect immediately. The value **true** indicates that setting takes effect immediately, and **false** indicates that the setting takes effect upon the next playback.

  ```typescript
  animationItem.resetSegments(5,15);
  ```

- Obtain animation duration or number of frames.
  > Note: The value **true** means to obtain the number of frames, and **false** means to obtain the duration (in ms).

  ```typescript
  animationItem.getDuration();
  ```

- Add an event listener.
  > Note: For an event listener to be removed correctly, its callback function must be the same as that of the event listener already added and must be predefined.

  ```typescript
  AnimationEventName = 'drawnFrame' | 'enterFrame' | 'loopComplete' | 'complete' | 'segmentStart' | 'destroy' | 'config_ready' | 'data_ready' | 'DOMLoaded' | 'error' | 'data_failed' | 'loaded_images';

  animationItem.addEventListener("enterFrame",function(){
      // TODO something
  })
  ```

- Change animation color.

  > Note: The first parameter indicates the RGB/RGBA color value. The second parameter indicates the animation layer and is optional. The third parameter indicates the index of the element corresponding to the animation layer and is optional.

  ```typescript
  animationItem.changeColor([255,150,203,0.8]);  // Change the color of the entire animation.
  Or
  animationItem.changeColor([255,150,203,0.8],2); // Change the color of the second layer of the animation.
  Or
  animationItem.changeColor([255,150,203,0.8],2,2); // Change the color of the second element at the second layer of the animation.
  ```

- Remove an event listener.

  ```typescript
  animationItem.removeEventListener("enterFrame",function(){
      // TODO something
  })
  ```

- Resize animation layout.

  ```typescript
  animationItem.resize();
  ```

- Set animation fill mode.

  > Note: There are five fill modes: **Fill**, **Cover**, **Top**, **Bottom**, and **Contain**. The default mode is **Contain**.

  ```typescript
  animationItem.setContentMode('Cover');
  ```

- Set the frame rate range of the animation.

  > Note: The frame rate ranges from 1 to 120. A larger frame rate causes higher power consumption.

  ```typescript
  animationItem.setFrameRate(30);
  ```

- Clear cache file.
  > Note: container is with canvas component binding context CanvasRenderingContext2D, json file path for local resources.
  ```typescript
  lottie.clearFileCache() //Clear all animation cache files.
  Or
  lottie.clearFileCache('path') //Clear the specified animation cache file.
  Or
  lottie.clearFileCache('path',container) //Clears the network resource cache file in the specified local animation.
  ```

### 8. Destroy animation.

   Generally, animation is destroyed in the **onDisAppear()** API of the canvas component or in the **aboutToDisappear()** method during page destruction.

   With lottie, you can destroy an animation in two modes:

    - **lottie.destroy**: destroys all animations; **lottie.destroy(name)** destroys animation with the specified name. You are advised to use this mode to destroy animations.
    - **animationItem.destroy**: destroys a given animation. Improper use may cause memory leakage. To destroy a given animation, you are advised to use **lottie.destroy(name)**.

**Consequences of Improper Destruction:**

1. **Memory Leakage**:
   - If animations are created but not actively destroyed, animationItem objects will continue to exist, causing memory leakage
   - Memory leakage leads to continuous growth of application memory usage, potentially causing the application to be killed by the system
   - In scenarios with frequent page switching, undestroyed animations will accumulate significant memory usage

2. **Unreleased Resources**:
   - Animation-related Canvas resources, image resources, timers, etc. will not be properly released
   - Leads to system resource shortage, affecting normal operation of other functions
   - May cause high GPU memory usage, affecting rendering performance

3. **Animation Instance Conflicts**:
   - When there are multiple animations on one page and animation instances are assigned to the same variable, using animationItem.destroy() will only destroy the last one
   - Other animation instances still exist and continue to occupy resources, potentially causing abnormal animation playback

4. **Event Listener Leakage**:
   - Internal event listeners of animations will not be cleaned up and continue to listen for events
   - May cause performance degradation and unexpected behavior

**Recommended Practices:**
```typescript
// Destroy all animations when page is destroyed
aboutToDisappear(): void {
  lottie.destroy(); // Destroy all animations
}

// Or destroy by name
aboutToDisappear(): void {
  lottie.destroy('animationName'); // Destroy specified animation
}
```
   > Note 1: When there are multiple animations on one page and the animation instance is assigned to the same variable **animationItem**, only the last animation is destroyed when **animationItem.destroy** is called. In the following code example, animations whose names are **cat** and **2016** are assigned to **this.animationItem**. Calling **animationItem.destroy()** destroys only the animation whose name is **2016**, but not the one whose name is **cat**.

     ```typescript
         this.animationItem = lottie.loadAnimation({
               container: this.mainCanvasRenderingContext,  // Rendering context.
               renderer: 'canvas',                          // Rendering mode.
               loop: true,                                  // Whether to loop playback. The default value is true.
               autoplay: true,                              // Whether to enable automatic playback. The default value is true.
               name: 'cat',                                // Animation name.
               contentMode: 'Contain',                      // Fill mode.
               path: this.path,                             // JSON file path.
               initialSegment: [10,50]                      // Initial segment of the animation.
             })

         this.animationItem = lottie.loadAnimation({
               container: this.mainCanvasRenderingContext,  // Rendering context.
               renderer: 'canvas',                          // Rendering mode.
               loop: true,                                  // Whether to loop playback. The default value is true.
               autoplay: true,                              // Whether to enable automatic playback. The default value is true.
               name: '2016',                                // Animation name.
               contentMode: 'Contain',                      // Fill mode.
               path: this.path,                             // JSON file path.
               initialSegment: [10,50]                      // Initial segment of the animation.
             })

     ```

   > Note 2: If you call the following APIs in the same code block as **lottie.loadAnimation** before animation loading is complete, the settings may not take effect: **stop**, **togglePause**, **pause**, **goToAndStop**, **goToAndPlay**, **setSegment**, **getDuration**, **changeColor**, and **setContentMode**. <b>Call these APIs after the animation is loaded. You can use **animationItem.addEventListener('DOMLoaded')** to listen for the animation loading completion.</b>

   ```typescript
   // The animation is not completely loaded. The settings of changeColor and setContentMode are invalid.
   Button('Load 2016')
       .onClick(() => {
         if (this.animationItem2 == null) {
           this.animationItem2 = lottie.loadAnimation({
             container: this.canvasRenderingContext,
             renderer: 'canvas', // Canvas rendering mode.
             name: '2016',
             path: 'common/lottie/data.json',
           })
           this.animationItem2.changeColor([255,150,203,0.8]);
           this.animationItem2.setContentMode('Top');
         }
       })

   ```

   ```typescript
   // After animationItem.addEventListener('DOMLoaded') is invoked, the settings of changeColor and setContentMode are valid.
   Button('Load 2016')
     .onClick(() => {
       if (this.animationItem2 == null) {
         this.animationItem2 = lottie.loadAnimation({
           container: this.canvasRenderingContext,
           renderer: 'canvas', // Canvas rendering mode.
           loop: true,
           autoplay: false,
           name: '2016',
           contentMode: 'Contain',
           path: 'common/lottie/data.json',
         })

         this.animationItem2.addEventListener('DOMLoaded', (args: Object): void => {
           this.animationItem2.changeColor([255,150,203,0.8]);
           // this.animationItem2?.setContentMode('Top');
           // ...
         }); // The event is triggered after the animation is loaded but before it is played.
       }
     })

   ```

### 9. Determine whether animation resource is a network load example
```typescript
 this.isNet = 'Whether to load network' + this.animateItem.isNetLoad;
```
### 10. Log switch function
```typescript
 LogUtil.mLogLevel = LogUtil.ON; //open log
 LogUtil.mLogLevel = LogUtil.OFF; //close log
```

### 11. Skip drawing when animation is invisible

Lottie supports skipping drawing when animation slides to the invisible area to reduce redundant drawing (This feature is only supported in API 13 and above versions). The current processing logic assumes that lottie is bound to a specific canvas node, but in some complex interaction scenarios, it fails to track changes in the binding relationship, making it inapplicable when there are complex changes in UI logic, including:

- Preloading scenario, when canvas node has no binding relationship with lottie. This includes explicit preloading by developer and implicit preloading by system caused by cache mechanism of lazyforeach.
- Node reuse scenario, when node may form a binding relationship with different animations.
- Node destruction and reconstruction scenario, when old node has changed and the association relationship of the new node is reestablished. The above situations cannot be handled currently. As a result, lottie cannot accurately perceive the state of the canvas node, redundant drawing occurs, and even obvious experience problems such as inactivity when it should be active.

Therefore, the coordinator object with CanvasRenderingContext2D as the core is introduced to track the dynamic relationship between lottie animation, CanvasRenderingContext2D, and Canvas. Only when the CanvasRenderingContext2D associated with lottie corresponds to a visible canvas, drawing will be actually performed, otherwise drawing will be skipped to avoid redundant load. When the coordinator cannot confirm the accurate canvas node status, compatibility processing is introduced: when user does not explicitly call bindContext2dToCoordinator interface, drawing is performed by default, otherwise no further callback notifications such as drawing are performed. In order to avoid inconsideration of compatibility processing, setAttachedCanvasHasVisibleArea interface is introduced to support developers to force correction of the canvas node status associated with context2d to support escape.

**Use Cases:**
- **Long list scrolling scenarios**: List contains multiple animations, when user scrolls, most animations are invisible, need to skip drawing to save performance
- **Page switching scenarios**: Page contains multiple animations, when user switches to other pages, animations in original page are invisible, should stop drawing
- **Tab switching scenarios**: Multiple Tab pages each contain animations, when switching Tab, invisible animations should skip drawing
- **Complex animation scenarios**: Single page contains multiple complex animations, when some animations are obscured by other elements, should skip drawing of invisible animations

**Impact of Enabling:**
- **Performance improvement**: Skip drawing of invisible animations, reduce CPU/GPU usage, improve overall performance by 30%+
- **Power consumption reduction**: Reduce unnecessary rendering operations, lower device power consumption, extend battery life
- **Memory optimization**: Avoid invisible animations occupying too many rendering resources
- **UI smoothness improvement**: Reduce main thread rendering pressure, UI interactions become smoother

**Consequences of Not Enabling:**
- **Performance waste**: Invisible animations still continue to draw, wasting CPU/GPU resources
- **Increased power consumption**: Device continues to perform unnecessary rendering operations, increasing power consumption
- **UI lag**: Large number of invisible animations drawing occupies main thread, causing UI interaction lag
- **Memory usage**: Invisible occupation animations still occupy rendering resources, higher memory usage

**How to Enable:**

**Method 1: Through autoSkip parameter (recommended, simple)**
```typescript
lottie.loadAnimation({
  container: this.canvasRenderingContext,
  renderer: 'canvas',
  loop: true,
  autoplay: true,
  autoSkip: true,  // Enable invisible skip drawing feature
  path: 'common/lottie/data.json'
})
```

**Method 2: Through Coordinator (recommended, more precise control)**
Suitable for complex scenarios where precise control of animation drawing timing is needed.

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
    lottie.destroy("robotYoga");
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

**Notes:**
- autoSkip parameter default value is true, recommended to keep enabled
- Coordinator method is suitable for API 13 and above versions
- In complex interaction scenarios (such as LazyForEach, node reuse), Coordinator method is recommended
- When page is destroyed, must call unbindContext2dFromCoordinator to unbind

### 12. Preventing Animation Memory Leaks

- Avoid using @state decorator for animation objects: When using @state to decorate an animationItem object, it may prevent animation from being properly destroyed, leading to memory leak issues.


- Destroy animations in a timely manner: When an animation is no longer in use or when the page is about to be destroyed, the animation must be actively destroyed. If animations are only created but not actively destroyed, animationItem objects will continue to exist, thereby causing memory leaks. It is recommended to use lottie.destroy(name) method to destroy animations.


- It is prohibited to manually clear the "destroy" listener event: manually executing `removeEventListener('destroy')` will clear the animation's internal self-destruction callback, causing `lottie.destroy(name)` to fail to fully execute the subsequent resource release process, thereby leading to a memory leak.


## Available APIs

### AnimationItem

| API                               | Type                                 | Description                                                                                   |
|-----------------------------------|--------------------------------------|-----------------------------------------------------------------------------------------------|
| play()                            | name?                                | Plays animation.                                                                          |
| stop()                            | name?                                | Stops animation.                                                                          |
| pause()                           | name?                                | Pauses animation.                                                                         |
| togglePause()                     | name?                                | Switches animation playback state between running and paused.                             |
| destroy()                         | name?                                | Destroys animation.                                                                       |
| goToAndStop()                     | value, isFrame?, name?               | Seeks to a certain frame or point of time and then stops animation.                       |
| goToAndPlay()                     | value, isFrame?, name?               | Seeks to a certain frame or point of time and then starts animation.                      |
| setSegment()                      | init,end                             | Sets an animation segment.                                                                    |
| playSegments()                    | arr, forceFlag                       | Plays animation segments.                                                                     |
| resetSegments()                   | forceFlag                            | Resets animation.                                                                         |
| setSpeed()                        | speed                                | Sets playback speed.                                                                      |
| resize()                          | width?, height?                      | Refresh animation layout.                                                                     |
| setDirection()                    | direction                            | Sets playback direction.                                                                  |
| getDuration()                     | isFrames?                            | Obtains animation duration.                                                               |
| addEventListener()                | eventName,callback                   | Adds an event listener.                                                                       |
| removeEventListener()             | name,callback?                       | Removes an event listener.                                                                    |
| changeColor()                     | color, layer?, index?                | Changes animation color.                                                                  |
| setContentMode()                  | contentMode                          | Sets fill mode.                                                                           |
| setFrameRate()                    | frameRate                            | Sets animation frame rate.                                                                |

### AnimationItem Properties

| Property          | Type               | Description                                                                 |
|-------------------|--------------------|-----------------------------------------------------------------------------|
| name              | string             | Animation name                                                              |
| isLoaded          | boolean            | Whether the animation has been loaded                                       |
| currentFrame      | number             | Current frame position (considering playback direction)                     |
| currentRawFrame   | number             | Current frame position                                                      |
| firstFrame        | number             | First frame of the animation                                                |
| totalFrames       | number             | Total number of animation frames                                            |
| frameRate         | number             | Animation frame rate (fps)                                                  |
| frameMult         | number             | Frame multiplier                                                            |
| playSpeed         | number             | Current playback speed                                                      |
| playDirection     | number             | Playback direction, 1 for forward, -1 for reverse                           |
| playCount         | number             | Number of times played                                                      |
| isPaused          | boolean            | Whether the animation is paused                                             |
| autoplay          | boolean            | Whether to autoplay                                                         |
| loop              | boolean \| number  | Whether to loop playback, true for infinite loop, number for playback count |
| renderer          | any                | Renderer type                                                               |
| animationID       | string             | Unique animation identifier                                                 |
| timeCompleted     | number             | Animation completion time                                                   |
| segmentPos        | number             | Current segment position                                                    |
| isSubframeEnabled | boolean            | Whether subframe rendering is enabled                                       |
| segments          | AnimationSegment \| AnimationSegment[] | Array of current playing segments                                           |

### LottiePlayer

| API                               | Type                                         | Description                                                                                   |
|-----------------------------------|----------------------------------------------|-----------------------------------------------------------------------------------------------|
| play()                            | name?, onlyCurrentAbility?                   | Plays animation.                                                                           |
| stop()                            | name?, onlyCurrentAbility?                   | Stops animation.                                                                           |
| pause()                           | name?, onlyCurrentAbility?                   | Pauses animation.                                                                          |
| togglePause()                     | name?, onlyCurrentAbility?                   | Switches animation playback state between running and paused.                              |
| destroy()                         | name?, onlyCurrentAbility?                   | Destroys animation.                                                                        |
| goToAndStop()                     | value, isFrame?, name?, onlyCurrentAbility?  | Seeks to a certain frame or point of time and then stops animation.                        |
| goToAndPlay()                     | value, isFrame?, name?, onlyCurrentAbility?  | Seeks to a certain frame or point of time and then starts animation.                       |
| setSpeed()                        | speed, name?, onlyCurrentAbility?            | Sets playback speed.                                                                       |
| resize()                          | width?, height?, onlyCurrentAbility?         | Refresh animation layout.                                                                     |
| setDirection()                    | direction, name?, onlyCurrentAbility?        | Sets playback direction.                                                                   |
| setContentMode()                  | contentMode, name?, onlyCurrentAbility?      | Sets fill mode.                                                                            |
| loadAnimation()                   | loadAnimation                                | Load Animation.                                                                               |
| setFrameRate()                    | frameRate                                    | Sets animation frame rate.                                                                 |
| clearFileCache()                  | url?, container?                             | Clear animation cache files downloaded to sandbox through network.                 |
| bindContext2dToCoordinator()      | CanvasRenderingContext2D                     | Track dynamic relationship between lottie animation, CanvasRenderingContext2D, and Canvas. |
| unbindContext2dFromCoordinator()  | CanvasRenderingContext2D                     | Remove tracking relationship.                                                                 |
| setAttachedCanvasHasVisibleArea() | CanvasRenderingContext2D, boolean            | Supports forced correction of the canvas node status associated with context2d.               |

#### loadAnimation Parameter Configuration

| Field Name | Type | Required | Default Value | Description | OpenHarmony supports 
|--------|------|------|--------|------|------|
| container | CanvasRenderingContext2D | Yes | - | The CanvasRenderingContext2D bound to the canvas component, providing basic rendering and drawing capabilities | Yes |
| path | string | No | - | Animation data file path within the app, supports relative paths under entry/src/main/ets, cross-package paths are not supported. Choose one of path or animationData | Yes |
| animationData | any | No | - | Animation data in json format. Choose one of path or animationData | Yes |
| renderer | string | No | canvas | Rendering type, currently supports canvas mode | Yes |
| loop | boolean | No | true | Whether to loop playback after the animation ends. If the value is true, the animation loops indefinitely. If the value is number and >= 1, it sets the number of times to repeat playback | Yes |
| autoplay | boolean | No | true | Automatic playback setting | Yes |
| initialSegment | AnimationSegment | No | - | Initial frame range for playing animation resources | Yes |
| name | string | No | - | Animation name. After the animation is successfully loaded, you can apply this name on Lottie related APIs to control the animation | Yes |
| context | common.UIAbilityContext | No | - | Application context Context. In HSP scenarios, the correct context must be passed. In non-HSP scenarios, context can be omitted | Yes |
| packageName | string | No | - | Application package name, used to distinguish different modules calling the animator when printing logs. packageName can be omitted | Yes |
| contentMode | string | No | Contain | Animation fill mode, default value is Contain, supports: Fill, Top, Cover, Bottom, Contain | Yes |
| frameRate | number | No | - | Set the animator's refresh frame rate, range from 1 to 120 | Yes |
| uri | string | No | - | Read animation data from a network path, supports json and zip format | Yes |
| isNetwork | boolean | No | - | If true, prioritize reading network resources; if false, prioritize reading local cached resources | Yes |
| imagePath | string | No | - | Read image resources from the specified path | Yes |
| autoSkip | boolean | No | true | Whether to skip drawing when the animation is invisible. If set to true, drawing is skipped. If set to false, drawing is performed unconditionally | Yes |
| imageAssetDelegate | Function | No | - | Call this interface when loading images to obtain the PixelMap object for drawing | Yes |
| autoFontSize | boolean | No | true | Whether the animation scales with the system font setting. If set to false, it does not scale with the system font. If set to true, it scales with the system font | Yes |

## About obfuscation

- Code obfuscation, please see [Code Obfuscation](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/arkts-utils/source-obfuscation.md).
- If you want lottie library not to be obfuscated during code obfuscation, you need to add corresponding exclusion rules in the obfuscation rule configuration file obfuscation-rules.txt.
```text
-keep
./oh_modules/@ohos/lottie
```

## New Features

1. The animation color can be changed in canvas rendering mode.
- The color value can be in RGB format.
- The color value can be in RGBA format.
- The color can be set for the start keyframe.

2. Certain masks and mattes features are supported for canvas rendering.
- For masks, the supported modes are: mode = a, mode = s, mode = f.
- For mattes, the supported modes are: tt = 1, tt = 2.

3. The Gaussian blur effect is added for animations in canvas rendering mode.

4. External resource images can be loaded in canvas rendering mode.
- External resource images in the sandbox (which is searched before the **rawfile** folder) can be loaded.
- External resource images in the **rawfile** folder can be loaded.

5. The fill mode can be set, with the following options available:
- Fill (may be stretched, not cropped)
- Top (aligned with the top edge, not cropped)
- Bottom (aligned with the bottom edge, not cropped)
- Cover (may be cropped)
- Contain (aligned with the center vertically, may be cropped)

6. The frame rate can be set for animations.

7. Internet animations and animations specified by URIs can be loaded.
- Animations in the path specified by URIs can be rendered.
- Internet animation can be rendered.
- Note: If the animation file contains Internet resources, you must request the permissions **ohos.permission.INTERNET** and **ohos.permission.GET_NETWORK_INFO**.

8. When the animation is completely invisible, the current animation will automatically pause and stop sending drawing instructions to optimize performance and reduce power consumption.

## Legacy issues

* HTML rendering mode
* Filter effect in SVG rendering
* Some masks and mattes features
* Luminance mask (that is, tt = 3)
* Animation visibility control in components
* Animation registration
* Animation search
* Animation data update
* Certain effects
* Animations containing expressions
* Modify the content of the animated text
  Due to system API limitations, Lottie does not support playing animations on the following devices or components:
* Card component (Form): The card runs in a separate process, lacking the rendering environment required by Lottie.
* Smart wearable devices: Including smartwatches and other wearable devices, they are unable to support Lottie animation playback due to limitations in system resources and graphics capabilities.


## Directory Structure

```
/lottie        # Root directory of project
├── entry      # Sample code
├── library    # Lottie library folder
│    └─ src/main/js    # Core code, including JSON parsing, animation drawing, and animation manipulation
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
│       └─ index.d.ts    # API declaration
├── README.md     # Readme
├── README_zh.md  # Readme
```

## How to Contribute

If you find any problem when using lottie, submit an [issue](https://gitcode.com/CPF-ApplicationTPC/lottieArkTS/issues) or a [PR](https://gitcode.com/CPF-ApplicationTPC/lottieArkTS/pulls).

## License

This project is licensed under [MIT License](https://gitcode.com/CPF-ApplicationTPC/lottieArkTS/blob/master/LICENSE).