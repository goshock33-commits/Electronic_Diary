import {
  extendPrototype,
} from '../utils/functionExtensions';

import audioControllerFactory from '../utils/audio/AudioController';
import {
  getSubframeEnabled,
  BMEnterFrameEvent,
  BMCompleteEvent,
  BMCompleteLoopEvent,
  BMSegmentStartEvent,
  BMDestroyEvent,
  BMRenderFrameErrorEvent,
  BMConfigErrorEvent,
  createElementID,
  getExpressionsPlugin,
} from '../utils/common';
import ImagePreloader from '../utils/imagePreloader';
import BaseEvent from '../utils/BaseEvent';
import dataManager from '../utils/DataManager';
import markerParser from '../utils/markers/markerParser';
import ProjectInterface from '../utils/expressions/ProjectInterface';
import { getRenderer, getRegisteredRenderer } from '../renderers/renderersManager';
import downloadManager from '../utils/DownloadManager';
import {
  readJson,
  handleAssets,
  createFilesDir,
  handleZipAssets,
  isCacheExist,
  isHaveImg,
  createImageFilesDir,
  isJsonFile,
  isCompressdFile,
  isExistNetworkAssets
} from '../utils/DataUtil';
import {LogUtil} from '../utils/LogUtil'
import deviceInfo from '@ohos.deviceInfo';

const AnimationItem = function () {
  this._cbs = [];
  this.name = '';
  this.path = '';
  this.source = null;
  this.isLoaded = false;
  this.absoluteFrameToPlay = -1;  //absolute frame number based by 0, regardless of whether playing segments
  this._absoluteFramePlayed = -1;
  this.firstFrame = 0;            //the number of the started frame which is in playing segments
  this.endFrame = 0;
  this.offsetFrame = 0;           //the minimum number of segment frames. Note that it's not certainly firstFrame
  this.totalFrames = 0;
  this.frameRate = 0;
  this.frameMult = 0;
  this._speed = 1;
  this._direction = 1;
  this.playCount = 0;
  this.animationData = {};
  this.assets = [];
  this.isPaused = true;
  this.autoplay = false;
  this.loop = true;
  this.renderer = null;
  this.animationID = createElementID();
  this.assetsPath = '';
  this.timeCompleted = 0;
  this.segmentPos = 0;
  this.isSubframeEnabled = getSubframeEnabled();
  this.segments = [];
  this._idle = true;
  this.projectInterface = ProjectInterface();
  this.imagePreloader = new ImagePreloader();
  this.audioController = audioControllerFactory();
  this.markers = [];
  this.configAnimation = this.configAnimation.bind(this);
  this.onSetupError = this.onSetupError.bind(this);
  this.onSegmentComplete = this.onSegmentComplete.bind(this);
  this.drawnFrameEvent = new BMEnterFrameEvent('drawnFrame', 0, 0, 0);
  this.context = null;
  this.packageName = '';
  this.contentMode = '';
  this.userPlayingFrameRate = 0;    // the max playing frame rate of this animation
  this.lastTimestamp = 0;
  this._loopCompleteTime = 20;
  this._firstTime = 0;
  this.isFirstLoaded = false;
  this.isNetLoad = false;
  this.isAutoSkip = true;
  this._hasArea = true;
  this._isCanvasStatusDeterminate = false;
  this.autoFontSize = true;
  this._isLoaded = true;

  /*
   * for backward compatiblity
   * relative frame based by offsetFrame.
   */
  Object.defineProperty(this, 'currentRawFrame', {
    get() {
      return this.absoluteFrameToPlay;
    },
    set(value) {
      let nextFrame = this.getNextFrameToPlay(value);
      this.absoluteFrameToPlay = this.relativeFrameToAbsolute(nextFrame);
    }
  });

  /*
   * for backward compatiblity
   * relative frame based by offsetFrame. Integerized when subFrame is false.
   */
  Object.defineProperty(this, 'currentFrame', {
    get() {
      let frameToPlay = this.isSubframeEnabled ?  this.absoluteFrameToPlay: Math.floor(this.absoluteFrameToPlay);
      // for backward compatiblity
      return this.absoluteFrameToRelative(frameToPlay);
    },
    set(value) {
      let frameToPlay = this.getNextFrameToPlay(value);
      let absoluteFrame = this.relativeFrameToAbsolute(frameToPlay);
      this.absoluteFrameToPlay = this.isSubframeEnabled ? absoluteFrame : Math.floor(absoluteFrame);
    }
  });

  /*
 * for backward compatiblity
 * 播放速率, 值为>=1的正整数.
 */
  Object.defineProperty(this, 'playSpeed', {
    get() {
      return this._speed;
    },
    set(value) {
      this.setSpeed(value);
    }
  });

  /*
 * for backward compatiblity
 * 播放速率, 值为>=1的正整数.
 */
  Object.defineProperty(this, 'playDirection', {
    get() {
      return this._direction;
    },
    set(value) {
      this.setDirection(value);
    }
  });

};

extendPrototype([BaseEvent], AnimationItem);

AnimationItem.prototype._getLogTag = function() {
  let abilityName = this.getUiContext()?.getHostContext()?.abilityInfo?.name;
  return `<(${abilityName} ${this.animationID})> ${this.packageName} ${this.name} animation`;
};

AnimationItem.prototype.loadCacheData = function (uri, resultDir) {
  let existResult = isCacheExist(uri, resultDir.route); // 沙箱中是否有下载的资源
  if (existResult?.isExist) {
    let cacheData = readJson(uri, resultDir.route, this.triggerEvent.bind(this));
    // 优先读取缓存
    if (isJsonFile(uri)) {
      if (cacheData?.assets?.length && isExistNetworkAssets(cacheData?.assets)) {
        let newJsonData = handleAssets(cacheData);
        this.setupAnimation(newJsonData); // 加载有图片资源的json资源
      } else {
        this.setupAnimation(cacheData); // 加载无图片资源的json资源
      };
    } else if (isCompressdFile(uri)) {
      // 修改u路径
      let newCacheData = handleZipAssets(cacheData, resultDir.route);

      if (newCacheData?.assets?.length && isExistNetworkAssets(newCacheData?.assets)) {
        let newJsonData = handleAssets(newCacheData);
        this.setupAnimation(newJsonData); // 加载有图片资源的json资源
      } else {
        this.setupAnimation(newCacheData); // 加载无图片资源的json资源
      };
    };
    this.isNetLoad = false;
  } else {
    // 若缓存无资源，加载网络资源
    downloadManager.loadNetworkAnimation(uri, (jsonData, isNetLoad) => {
      this.isNetLoad = isNetLoad;
      this.setupAnimation(jsonData);
    }, this.triggerEvent.bind(this), resultDir, false);
  };
};

AnimationItem.prototype.loadAnimationData = function (jsonData, isNetwork) {
  try {
    if (jsonData?.assets?.length && isExistNetworkAssets(jsonData?.assets)) {
      this.loadImage(jsonData, isNetwork);
    } else {
      // 无网络图片
      this.setupAnimation(jsonData);
    }
  } catch (error) {
    this._isLoaded = false;
    LogUtil.error(`${this._getLogTag()} error.message: ${JSON.stringify(error.message)}, error.stack: ${JSON.stringify(error.stack)}`);
  }
};

AnimationItem.prototype.loadImage = function (jsonData, isNetwork) {
  if (isNetwork) {
    downloadManager.loadNetworkImage(jsonData).then((results) => {
      let newJsonData = handleAssets(jsonData);
      this.setupAnimation(newJsonData);
    })
      .catch((err) => {
        // 处理网络异常加载缓存
        let imgRouterFilesDir = createImageFilesDir();
        let isImg = isHaveImg(imgRouterFilesDir); // 沙箱中是否有下载的图片资源
        if (isImg) {
          let cacheImagesData = handleAssets(jsonData);
          this.setupAnimation(cacheImagesData);
        } else {
          // 缓存无资源，返回加载异常
          setTimeout(() => {
            this.triggerEvent('error', err);
          }, 0);
        }
        ;
      });
  } else {
    // false 优先加载缓存资源
    let imgRouterFilesDir = createImageFilesDir();
    let isImg = isHaveImg(imgRouterFilesDir); // 沙箱中是否有下载的图片资源
    if (isImg) {
      let filesJsonData = handleAssets(jsonData);
      this.setupAnimation(filesJsonData);
    } else {
      downloadManager.loadNetworkImage(jsonData).then((results) => {
        let newJsonData = handleAssets(jsonData);
        this.setupAnimation(newJsonData);
      })
        .catch((err) => {
          // 下载失败,返回加载异常
          setTimeout(() => {
            this.triggerEvent('error', err);
          }, 0);
        });
    }
    ;
  }
};

AnimationItem.prototype.getUiContext = function () {
  return this.wrapper?.canvas?.uiContext_;
};

AnimationItem.prototype.setParams = function (params) {
  if (params.wrapper || params.container) {
    this.wrapper = params.wrapper || params.container;
  }
  var animType = 'svg';
  if (params.animType) {
    animType = params.animType;
  } else if (params.renderer) {
    animType = params.renderer;
  }
  this.autoFontSize = 'autoFontSize' in params ? params.autoFontSize : true;
  this.name = params.name ? params.name : '';
  const RendererClass = getRenderer(animType);
  this.renderer = new RendererClass(this, params.rendererSettings);
  this.context = getContext();
  let resContext = 'context' in params ? params.context : getContext();
  let imagePath = 'imagePath' in params ? params.imagePath : '';
  let imageAssetDelegate = 'imageAssetDelegate' in params ? params.imageAssetDelegate : null;
  this.imagePreloader.setCacheType(animType, this.renderer.globalData.defs, resContext, imagePath);
  this.imagePreloader.setImageAssetDelegate(imageAssetDelegate)
  this.renderer.setProjectInterface(this.projectInterface);
  this.animType = animType;
  if (params.loop === ''
    || params.loop === null
    || params.loop === undefined
    || params.loop === true) {
    this.loop = true;
  } else if (params.loop === false) {
    this.loop = false;
  } else {
    this.loop = parseInt(params.loop, 10);
  }
  this.contentMode = 'contentMode' in params ? params.contentMode : '';
  this.packageName = 'packageName' in params ? params.packageName : '';
  if (params.frameRate) {
    this.setFrameRate(params.frameRate);
  }
  this.autoplay = 'autoplay' in params ? params.autoplay : true;
  this.isAutoSkip = 'autoSkip' in params ? params.autoSkip : true;
  this.autoloadSegments =
    Object.prototype.hasOwnProperty.call(params, 'autoloadSegments') ? params.autoloadSegments : true;
  this.assetsPath = params.assetsPath;
  this.initialSegment = params.initialSegment;
  if (params.audioFactory) {
    this.audioController.setAudioFactory(params.audioFactory);
  }

  if (params.animationData) {
    this.source = 'data';
    this.loadAnimationData(params.animationData, params.isNetwork);
  } else if (params.path) {
    this.source = params.path;
    if (params.path.lastIndexOf('\\') !== -1) {
      this.path = params.path.substr(0, params.path.lastIndexOf('\\') + 1);
    } else {
      this.path = params.path.substr(0, params.path.lastIndexOf('/') + 1);
    }
    this.fileName = params.path.substr(params.path.lastIndexOf('/') + 1);
    this.fileName = this.fileName.substr(0, this.fileName.lastIndexOf('.json'));
    try {
      dataManager.loadAnimation(
        this.wrapper,
        params.path,
        params.isNetwork,
        this.configAnimation,
        this.onSetupError
      );
    } catch (err) {
      this.triggerEvent('error', err);
    }
  } else if (params.uri) {
    this.source = params.uri;
    this.loadNetworkResource(params.uri, params.isNetwork)
  }
};

AnimationItem.prototype.onCanvasHasVisibleArea = function(canvasUniqueId, hasArea) {
  LogUtil.info(`${this._getLogTag()} canvas(${canvasUniqueId}) has ${hasArea ? 'visible' : 'no'} area.`);
  this._isCanvasStatusDeterminate = true;
  this._visibleAreaChanged(canvasUniqueId, hasArea);
};

AnimationItem.prototype.loadNetworkResource = function (uri, isNetwork) {
  let resultDir = createFilesDir(uri);
  if (isNetwork) {
    // true 优先加载网络资源
    downloadManager.loadNetworkAnimation(uri, (jsonData, isNetLoad) => {
      this.isNetLoad = isNetLoad;
      this.setupAnimation(jsonData);
    }, this.triggerEvent.bind(this), resultDir, true);
  } else {
    // false 优先加载缓存资源
    this.loadCacheData(uri, resultDir);
  }
};

AnimationItem.prototype.onSetupError = function () {
  setTimeout(() => {
    this.trigger('data_failed');
  }, 0);
};

AnimationItem.prototype.setupAnimation = function (data) {
  dataManager.completeAnimation(
    data,
    this.configAnimation
  );
};

// web only
AnimationItem.prototype.setData = function (wrapper, animationData) {
  if (animationData) {
    if (typeof animationData !== 'object') {
      animationData = JSON.parse(animationData);
    }
  }
  var params = {
    wrapper: wrapper,
    animationData: animationData,
  };
  var wrapperAttributes = wrapper.attributes;

  params.path = wrapperAttributes.getNamedItem('data-animation-path') // eslint-disable-line no-nested-ternary
    ? wrapperAttributes.getNamedItem('data-animation-path').value
    : wrapperAttributes.getNamedItem('data-bm-path') // eslint-disable-line no-nested-ternary
      ? wrapperAttributes.getNamedItem('data-bm-path').value
      : wrapperAttributes.getNamedItem('bm-path')
        ? wrapperAttributes.getNamedItem('bm-path').value
        : '';
  params.animType = wrapperAttributes.getNamedItem('data-anim-type') // eslint-disable-line no-nested-ternary
    ? wrapperAttributes.getNamedItem('data-anim-type').value
    : wrapperAttributes.getNamedItem('data-bm-type') // eslint-disable-line no-nested-ternary
      ? wrapperAttributes.getNamedItem('data-bm-type').value
      : wrapperAttributes.getNamedItem('bm-type') // eslint-disable-line no-nested-ternary
        ? wrapperAttributes.getNamedItem('bm-type').value
        : wrapperAttributes.getNamedItem('data-bm-renderer') // eslint-disable-line no-nested-ternary
          ? wrapperAttributes.getNamedItem('data-bm-renderer').value
          : wrapperAttributes.getNamedItem('bm-renderer')
            ? wrapperAttributes.getNamedItem('bm-renderer').value
            : getRegisteredRenderer() || 'canvas';

  var loop = wrapperAttributes.getNamedItem('data-anim-loop') // eslint-disable-line no-nested-ternary
    ? wrapperAttributes.getNamedItem('data-anim-loop').value
    : wrapperAttributes.getNamedItem('data-bm-loop') // eslint-disable-line no-nested-ternary
      ? wrapperAttributes.getNamedItem('data-bm-loop').value
      : wrapperAttributes.getNamedItem('bm-loop')
        ? wrapperAttributes.getNamedItem('bm-loop').value
        : '';
  if (loop === 'false') {
    params.loop = false;
  } else if (loop === 'true') {
    params.loop = true;
  } else if (loop !== '') {
    params.loop = parseInt(loop, 10);
  }
  var autoplay = wrapperAttributes.getNamedItem('data-anim-autoplay') // eslint-disable-line no-nested-ternary
    ? wrapperAttributes.getNamedItem('data-anim-autoplay').value
    : wrapperAttributes.getNamedItem('data-bm-autoplay') // eslint-disable-line no-nested-ternary
      ? wrapperAttributes.getNamedItem('data-bm-autoplay').value
      : wrapperAttributes.getNamedItem('bm-autoplay')
        ? wrapperAttributes.getNamedItem('bm-autoplay').value
        : true;
  params.autoplay = autoplay !== 'false';

  params.name = wrapperAttributes.getNamedItem('data-name') // eslint-disable-line no-nested-ternary
    ? wrapperAttributes.getNamedItem('data-name').value
    : wrapperAttributes.getNamedItem('data-bm-name') // eslint-disable-line no-nested-ternary
      ? wrapperAttributes.getNamedItem('data-bm-name').value
      : wrapperAttributes.getNamedItem('bm-name')
        ? wrapperAttributes.getNamedItem('bm-name').value
        : '';
  var prerender = wrapperAttributes.getNamedItem('data-anim-prerender') // eslint-disable-line no-nested-ternary
    ? wrapperAttributes.getNamedItem('data-anim-prerender').value
    : wrapperAttributes.getNamedItem('data-bm-prerender') // eslint-disable-line no-nested-ternary
      ? wrapperAttributes.getNamedItem('data-bm-prerender').value
      : wrapperAttributes.getNamedItem('bm-prerender')
        ? wrapperAttributes.getNamedItem('bm-prerender').value
        : '';

  if (prerender === 'false') {
    params.prerender = false;
  }
  if (!params.path) {
    this.trigger('destroy');
  } else {
    this.setParams(params);
  }
};

AnimationItem.prototype.includeLayers = function (data) {
  if (data.op > this.animationData.op) {
    this.animationData.op = data.op;
    this.totalFrames = Math.floor(data.op - this.animationData.ip);
  }
  var layers = this.animationData.layers;
  var i;
  var len = layers.length;
  var newLayers = data.layers;
  var j;
  var jLen = newLayers.length;
  for (j = 0; j < jLen; j += 1) {
    i = 0;
    while (i < len) {
      if (layers[i].id === newLayers[j].id) {
        layers[i] = newLayers[j];
        break;
      }
      i += 1;
    }
  }
  if (!!this.renderer) {
    if (data.chars || data.fonts) {
      this.renderer.globalData.fontManager.addChars(data.chars);
      this.renderer.globalData.fontManager.addFonts(data.fonts, this.renderer.globalData.defs);
    }
  }
  if (data.assets) {
    len = data.assets.length;
    for (i = 0; i < len; i += 1) {
      this.animationData.assets.push(data.assets[i]);
    }
  }
  this.animationData.__complete = false;
  dataManager.completeAnimation(
    this.animationData,
    this.onSegmentComplete
  );
};

AnimationItem.prototype.onSegmentComplete = function (data) {
  this.animationData = data;
  var expressionsPlugin = getExpressionsPlugin();
  if (expressionsPlugin) {
    expressionsPlugin.initExpressions(this);
  }
  this.loadNextSegment();
};

AnimationItem.prototype.loadNextSegment = function () {
  var segments = this.animationData.segments;
  if (!segments || segments.length === 0 || !this.autoloadSegments) {
    this.trigger('data_ready');
    this.timeCompleted = this.totalFrames;
    return;
  }
  var segment = segments.shift();
  this.timeCompleted = segment.time * this.frameRate;
  var segmentPath = this.path + this.fileName + '_' + this.segmentPos + '.json';
  this.segmentPos += 1;
  dataManager.loadData(segmentPath, this.includeLayers.bind(this), function () {
    this.trigger('data_failed');
  }.bind(this));
};

AnimationItem.prototype.loadSegments = function () {
  var segments = this.animationData.segments;
  if (!segments) {
    this.timeCompleted = this.totalFrames;
  }
  this.loadNextSegment();
};

AnimationItem.prototype.imagesLoaded = function () {
  this.trigger('loaded_images');
  this.checkLoaded();
};

AnimationItem.prototype.preloadImages = function () {
  this.imagePreloader.setAssetsPath(this.assetsPath);
  this.imagePreloader.setPath(this.path);
  this.imagePreloader.loadAssets(this.animationData.assets, this.imagesLoaded.bind(this));
};

AnimationItem.prototype.configAnimation = function (animData, isNetLoad) {
  if (isNetLoad != undefined) {
    this.isNetLoad = isNetLoad
  }
  if (!this.renderer) {
    return;
  }
  try {
    this.animationData = animData;
    this.renderer.configAnimation(animData);
    if (!animData.assets) {
      animData.assets = [];
    }

    this.assets = this.animationData.assets;
    if(!this.animationData.fr || this.animationData.fr <= 0) {
      this.frameRate = 10;
      LogUtil.warn(`${this._getLogTag()} with 0 fr. use ${this.frameRate} instead.`);
    } else {
      this.frameRate = this.animationData.fr;
    }
    this.frameMult = this.frameRate / 1000;
    this.renderer.searchExtraCompositions(animData.assets);
    this.markers = markerParser(animData.markers || []);

    this.trigger('config_ready', this);
    this.preloadImages();
    this.loadSegments();
    this.updateFrameModifier();
    this.waitForFontsLoaded();
    if (this.isPaused) {
      this.audioController.pause();
    }

    if (this.initialSegment) {
      this.setSegment(this.initialSegment[0], this.initialSegment[1]);
    } else {
      this.setSegment(this.animationData.ip, this.animationData.op);
    }
    this._isLoaded = false;

  } catch (error) {
    LogUtil.warn(`${this._getLogTag()} exception in configAnimation: ${error.message} , ${error.stack}`);
    this.triggerConfigError(error);
  }
};

AnimationItem.prototype.waitForFontsLoaded = function () {
  if (!this.renderer) {
    return;
  }
  if (this.renderer?.globalData?.fontManager?.isLoaded) {
    this.checkLoaded();
  } else {
    setTimeout(this.waitForFontsLoaded.bind(this), 20);
  }
};

AnimationItem.prototype.checkLoaded = function () {
  if (!this.renderer) {
    return;
  }
  if (!this.isLoaded
    && this.renderer?.globalData?.fontManager?.isLoaded
    && (this.imagePreloader.loadedImages() || this.renderer.rendererType !== 'canvas')
    && (this.imagePreloader.loadedFootages())
  ) {
    this.isLoaded = true;
    var expressionsPlugin = getExpressionsPlugin();
    if (expressionsPlugin) {
      expressionsPlugin.initExpressions(this);
    }
    this.renderer.initItems();
    setTimeout(function() {
      this.trigger('DOMLoaded', this);
    }.bind(this), 0);

    LogUtil.info(`${this._getLogTag()} created from ${this.source ? this.source : 'data'}`);

    if (this.autoplay) {
      this.isFirstLoaded = true;
      if (!this._isCanvasStatusDeterminate) {
        LogUtil.warn(`${this._getLogTag()} playing with indeterminate canvas(${this.wrapper?.canvas?.getUniqueId()}) status.`);
      }
      this.play();
    } else {
      this.gotoCurrentFrame();
    }
  }
};

AnimationItem.prototype.setContentMode = function (contentMode) {
  //防止this.renderer为null，导致读取updateContentMode属性失败
  if (!!this.renderer && contentMode) {
    LogUtil.info(`${this._getLogTag()} setContentMode: ${contentMode}`);
    this.renderer.updateContentMode(contentMode);
  }
};

/*
 * 注意：这里虽然叫setFrameRate, 但本质是为了设置"播放帧率", 而不是动画源帧率. 动画源帧率是固定值.
 */
AnimationItem.prototype.setFrameRate = function (playingFrameRate) {
  LogUtil.info(`${this._getLogTag()} setFrameRate: ${playingFrameRate}`);

  this.userPlayingFrameRate = playingFrameRate;
};

/*
 * 注意：这里虽然叫getFrameRate, 但本质是为了获取"播放帧率", 而不是动画源帧率. 在获取动画源帧率时不可调用此接口.
 * 此处保持与setFrameRate命名风格一致是为了保持对称. 由于setFrameRate接口已经开出去了, 不能再更改.
 */
AnimationItem.prototype.getFrameRate = function () {
  if (this.userPlayingFrameRate > 0 && this.userPlayingFrameRate <= 120) {
    return this.userPlayingFrameRate;
  } else {
    return this.frameRate;
  }
}

AnimationItem.prototype.resize = function (width, height) {
  // Adding this validation for backwards compatibility in case an event object was being passed down
  let _width = typeof width === 'number' ? width : undefined;
  let _height = typeof height === 'number' ? height : undefined;

  //防止this.renderer为null，导致读取updateContainerSize属性失败
  if (!!this.renderer && !!this.renderer.updateContainerSize) {
    this.renderer.updateContainerSize(_width, _height);
  }
};

AnimationItem.prototype.setSubframe = function (flag) {
  LogUtil.info(`${this._getLogTag()} setSubframe: ${flag}`);

  this.isSubframeEnabled = !!flag;
};

AnimationItem.prototype.gotoCurrentFrame = function (skipOverdraw) {
  if (!this.totalFrames || this.totalFrames <= 0) {
    LogUtil.error(`${this._getLogTag()} Invalid animation data, canvas uniqueId is: ${this.wrapper?.canvas?.getUniqueId()}`);
    return;
  }

  if (this.timeCompleted !== this.totalFrames && this.absoluteFrameToPlay > this.timeCompleted) {
    this.absoluteFrameToPlay = this.timeCompleted;
  }

  if (!skipOverdraw || this._absoluteFramePlayed !== this.absoluteFrameToPlay) {
    if (this.renderCurrentFrame()) {
      this._absoluteFramePlayed = this.absoluteFrameToPlay;
      return true;
    }
  }

  return false;
};

AnimationItem.prototype.changeColor = function (color, endColor, layer, index) {
  if (!this.renderer) {
    return;
  }
  LogUtil.info(`${this._getLogTag()} changeColor: ${color}-${endColor}, ${layer} layer, ${index} element`);

  try {
    this.renderer.changeColor(color, endColor, layer, index);
    this.renderer.renderFrame(this.absoluteFrameToPlay, true);
    this.gotoCurrentFrame(false);
  } catch (error) {
    LogUtil.warn(`${this._getLogTag()} exception in changeColor: ${error.message}`);
    // TODO: decide how to handle catch case
  }
}

AnimationItem.prototype.renderCurrentFrame = function () {
  if (this.isLoaded === false || !this.renderer) {
    return false;
  }

  let frameToPlay = this.isSubframeEnabled ?  this.absoluteFrameToPlay: Math.floor(this.absoluteFrameToPlay);
  try {
    this.trigger('enterFrame');
    this.renderer.renderFrame(frameToPlay);
    this.trigger('drawnFrame');
  } catch (error) {
    LogUtil.warn(`${this._getLogTag()} exception in renderCurrentFrame: ${error.message} , ${error.stack}`);
    this.triggerRenderFrameError(error);
    return false;
  }

  return true;
};

AnimationItem.prototype._updateIdleStatus = function () {
  if (this.isPaused || (!this._hasArea && this.isAutoSkip)) {
    if (!this._idle) {
      this._idle = true;
      this.trigger('_idle', this);
    }
  } else {
    if (this._idle) {
      this._idle = false;
      this.trigger('_active', this);
    }
  }
};

AnimationItem.prototype._visibleAreaChanged = function (canvasUniqueId, isVisible) {
  let hasArea = this._hasArea;
  this._hasArea = isVisible;
  if (hasArea !== this._hasArea) {
    LogUtil.info(`${this._getLogTag()} canvas(${canvasUniqueId}) is ${isVisible ? 'moved in' : 'moved out'}`);
    this._updateIdleStatus();
  }
};

AnimationItem.prototype.play = function (name) {
  if (name && this.name !== name) {
    return;
  }
  LogUtil.info(`${this._getLogTag()} play:  ${this.isPaused ? 'paused' : 'playing'}`);

  if (this.isPaused === true) {
    this.isPaused = false;
    this.lastTimestamp = 0;   //此处赋值不可省掉，它决定了时间是否暂停
    this.trigger('_play');
    LogUtil.info(`${this._getLogTag()} is playing`);
    this.audioController.resume();
    this._updateIdleStatus();
  }
};

AnimationItem.prototype.pause = function (name) {
  if (name && this.name !== name) {
    return;
  }
  LogUtil.info(`${this._getLogTag()} pause:  ${this.isPaused ? 'paused' : 'playing'}`);

  if (this.isPaused === false) {
    this.isPaused = true;
    this.trigger('_pause');
    LogUtil.info(`${this._getLogTag()} is paused`);
    this._updateIdleStatus();
    this.audioController.pause();
  }
};

AnimationItem.prototype.togglePause = function (name) {
  if (name && this.name !== name) {
    return;
  }
  LogUtil.info(`${this._getLogTag()} togglePause:  ${this.isPaused ? 'paused' : 'playing'}`);
  if (this.isPaused === true) {
    this.play();
  } else {
    this.pause();
  }
};

AnimationItem.prototype.getNextFrameToPlay = function (frames) {
  if(frames < 0) {
    frames = -frames;
  }

  let nextFrame = frames;
  if((this._direction > 0 && this.firstFrame > this.endFrame)      // 逆序segment且正向播放
    || (this._direction < 0 && this.firstFrame < this.endFrame)) { // 正序segment且逆向播放
    //改为用大值(初始值)作为起点
    nextFrame = this.totalFrames - 1 - frames;
  }

  return nextFrame;
};

AnimationItem.prototype._complete = function (name, explicitly) {
  if (name && this.name !== name && this.playCount === 0) {
    return;
  }

  this.pause();
  LogUtil.info(`${this._getLogTag()} completed${explicitly ? ' explicitly' :
    ''}.  playing ${this.playCount} times`);
  // 如果是人工干预停止, 则不触发事件回调，保持与旧版本逻辑相同
  if (!explicitly) {
    this.trigger('complete');
  }
  this.playCount = 0;
};

AnimationItem.prototype.stop = function (name) {
  if (name && this.name !== name) {
    return;
  }

  LogUtil.info(`${this._getLogTag()} stop: ${this.isPaused ? 'paused' : 'playing'}`);
  let nextFrame = this.getNextFrameToPlay(0);
  this.gotoRelativeFrame(nextFrame);
  this._complete(name, true);
};

AnimationItem.prototype.getMarkerData = function (markerName) {
  var marker;
  for (var i = 0; i < this.markers.length; i += 1) {
    marker = this.markers[i];
    if (marker.payload && marker.payload.name === markerName) {
      return marker;
    }
  }
  return null;
};

AnimationItem.prototype.goToAndStop = function (framesOrMarker, isFrame, name) {
  if (name && this.name !== name) {
    return;
  }
  LogUtil.info(`${this._getLogTag()} goToAndStop: ${framesOrMarker} ${isFrame ? 'frame' : 'ms(or marker)'} ${name ? name : ''}`);

  if (Number.isNaN(framesOrMarker)) {
    LogUtil.info(`${this._getLogTag()} goToAndStop: frame is NaN`);
    return;
  }

  if (isFrame) {
    let nextFrame = this.getNextFrameToPlay(framesOrMarker);
    this.goToFrame(nextFrame);
  } else {
    let numValue = Number(framesOrMarker);
    if (isNaN(numValue)) {
      let marker = this.getMarkerData(framesOrMarker);
      if (marker) {
        this.playCount = 0;
        if (!marker.duration) {
          let nextFrame = this.adjustSegment([marker.time, this.animationData.op]);
          this.goToFrame(nextFrame);
        } else {
          let nextFrame = this.adjustSegment([marker.time, marker.time + marker.duration]);
          this.goToFrame(nextFrame);
        }
      }
    } else {
      let nextFrame = this.getNextFrameToPlay(framesOrMarker * this.frameModifier);
      this.goToFrame(nextFrame);
    }
  }

  this.pause();
};

AnimationItem.prototype.goToAndPlay = function (framesOrMarker, isFrame, name) {
  if (name && this.name !== name) {
    return;
  }
  LogUtil.info(`${this._getLogTag()} goToAndPlay: ${framesOrMarker} ${isFrame ? 'frame' :
    'ms(or marker)'} ${name ? name : ''}`);

  if (Number.isNaN(framesOrMarker)) {
    this.goToAndStop(this.firstFrame, isFrame, name);
  } else {
    this.goToAndStop(framesOrMarker, isFrame, name);
  }

  this.play();
};

AnimationItem.prototype.resume = function (timeStamp, displaySynced) {
  if (this.isPaused === true || this.isLoaded === false) {
    this.lastTimestamp = timeStamp;
    return;
  } else if (!this._hasArea && this.isAutoSkip) { //canvas完全隐藏且用户不要求强行绘制时，跳过执行绘制。
    return;
  }

  if(displaySynced && this.isFirstLoaded) {
    /*
     * 刚刚加载完动画后,displaySync首帧的timestamp还是加载动画之前的vsync所携带的时间戳，在动画解析时间过长的场景下该timestamp会过早从而引起跳帧。
     * 比如解析30fps动画，假设需要210ms，则时间戳会提前210ms左右，导致绘制逻辑计算后会跳过7帧。
     * 通过简单跳过并直接绘制首帧来workaround。最终表现为首帧会多显示2个左右的周期。
     * TODO: 如果能够将负载卸载到其它线程，降低主线程负载，则可将此逻辑优化掉，否则需要保留，以便保证从首帧开始播放
     */
    LogUtil.info(`${this._getLogTag()} first play.`);
    this.isFirstLoaded = false;
    this.lastTimestamp = 0;
    this.advanceTime(0); // 播放当前帧
    return;
  }

  if (this.lastTimestamp === 0) {
    LogUtil.info(`${this._getLogTag()} start for drawing.`);
    this.advanceTime(0); // 播放当前帧
  } else {
    let elapsedTime = timeStamp - this.lastTimestamp; // displaySync.onframe回调处理会保证timeStamp单调性，不受设备时间调整的影响

    this.advanceTime(elapsedTime);
  }
  this.lastTimestamp = timeStamp;
}

AnimationItem.prototype.advanceTime = function (elapsedTime) {
  let nextFrame = this.absoluteFrameToRelative(this.absoluteFrameToPlay) + elapsedTime * this.frameModifier;
  if (nextFrame >= this.totalFrames || nextFrame < 0) {
    let frames = nextFrame;
    if(nextFrame < 0) {
      frames = -nextFrame + this.totalFrames;
    }

    if (!this.totalFrames || this.totalFrames <= 0) {
      LogUtil.error(`${this._getLogTag()} Invalid animation data: totalFrames is 0 or negative, canvas uniqueId is: ${this.wrapper?.canvas?.getUniqueId()}`);
      return;
    }

    let loop = true;
    while (frames >= this.totalFrames && loop && this.totalFrames) {
      frames -= this.totalFrames;
      loop = this.checkLoop();
    }

    if(!loop) {
      frames = this.totalFrames - 1;
    }
    nextFrame = this.getNextFrameToPlay(frames);
  }

  this.gotoRelativeFrame(nextFrame);
};

/*
 * 在前后台切换场景下，会出现时间戳跳变的情况。
 * 此时需要计算出正确的下一帧，并更新playCount次数
 */
AnimationItem.prototype.checkLoop = function () {
  if ( this.checkSegments() !== -1 ) {
    return true;
  }

  this.playCount += 1;

  // total playing 1 times when this.loop = 0, 2 times when loop = 1, 3 times when loop = 2, and so on.
  if (this.loop === true || this.playCount <= this.loop) {
    this.trigger('loopComplete');
    let currentTimestamp = Date.now();
    if ((currentTimestamp - this._firstTime) > this._loopCompleteTime) {
      this._firstTime = currentTimestamp;
      LogUtil.info(`${this._getLogTag()} loopComplete name: ${this.name} from ${this.source}, canvas uniqueId is: ${this.wrapper?.canvas?.getUniqueId()}`);
    }
    return true;
  } else {
    //达到预期参数, 正常播放完成. 停留在最后一个segment上。TODO 可考虑从第1个segment重新开始。这需要不从segments序列中清除segment，并把segmentPos变量利用起来，
    setTimeout(() => {
      this._complete();
    }, 0);
  }

  return false;
};

AnimationItem.prototype.adjustSegment = function (arr) {
  let nextFrame = -1;
  if(arr[0] === arr[1]) {
    // 区间为左闭右开，因此相同左右值意味着没有可用帧，直接返回无效帧
    return nextFrame;
  }

  if (arr[1] < arr[0]) {
    this.totalFrames = arr[0] - arr[1];
    this.offsetFrame = arr[1] + 1;    // 从大到小播放时，小值作为目的帧需要被排除, 而大值需被包含，整体偏移1帧保证"左闭右开"区间
  } else {
    this.totalFrames = arr[1] - arr[0];
    this.offsetFrame = arr[0];
  }

  this.timeCompleted = this.totalFrames;
  this.firstFrame = arr[0];
  this.endFrame = arr[1];
  this.updateFrameModifier();

  nextFrame = this.getNextFrameToPlay(0);

  this.trigger('segmentStart');
  return nextFrame;
};

AnimationItem.prototype.setSegment = function (init, end) {
  LogUtil.info(`${this._getLogTag()} setSegment: ${init} ~ ${end}`);
  if (!this._isLoaded && (!this.totalFrames || this.totalFrames <= 0)) {
    LogUtil.error(`${this._getLogTag()} Invalid animation data, canvas uniqueId is: ${this.wrapper?.canvas?.getUniqueId()}`);
    return;
  }
  let nextFrame = this.adjustSegment([init, end]);
  this.gotoRelativeFrame(nextFrame);
};

AnimationItem.prototype.playSegments = function (arr, forceFlag) {
  LogUtil.info(`${this._getLogTag()} playSegments: ${arr}, ${forceFlag ? 'immediate' : 'deferred'}`);

  if (!this.totalFrames || this.totalFrames <= 0) {
    LogUtil.error(`${this._getLogTag()} Invalid animation data, canvas uniqueId is: ${this.wrapper?.canvas?.getUniqueId()}`);
    return;
  }
  if (forceFlag) {
    this.segments.length = 0;
  }
  let segmentAvailable = false;
  if (typeof arr[0] === 'object') { // [ [x,x], [x,x], ...]
    for (let i = 0; i < arr.length; i += 1) {
      if (arr[i].length >= 2) {
        this.segments.push(arr[i]);
        segmentAvailable = true;
      }
    }
  } else { // [x,x]
    if (arr.length >= 2) {
      this.segments.push(arr);
      segmentAvailable = true;
    }
  }

  if(!segmentAvailable) {
    return;
  }

  if (forceFlag) {
    this.playCount = 0; //replay
    let nextFrame = this.checkSegments();
    this.gotoRelativeFrame(nextFrame);
  }

  if (this.isPaused) {
    this.play();
  }
};

AnimationItem.prototype.resetSegments = function (forceFlag) {
  LogUtil.info(`${this._getLogTag()} resetSegments: ${forceFlag ? 'immediate' : 'deferred'}`);
  if (!this.totalFrames || this.totalFrames <= 0) {
    LogUtil.error(`${this._getLogTag()} Invalid animation data, canvas uniqueId is: ${this.wrapper?.canvas?.getUniqueId()}`);
    return;
  }

  this.segments.length = 0;
  this.segments.push([this.animationData.ip, this.animationData.op]);
  if (forceFlag) {
    this.playCount = 0;   //replay
    let nextFrame = this.checkSegments();
    this.gotoRelativeFrame(nextFrame);
  }
};

AnimationItem.prototype.checkSegments = function () {
  let nextFrame = -1;
  while (this.segments.length) {
    nextFrame = this.adjustSegment(this.segments.shift())
    if(nextFrame !== -1) {
      break;
    }
    // 跳过空片段
  }
  return nextFrame;
};

AnimationItem.prototype.destroy = function (name) {
  if (name && this.name !== name) {
    return;
  }
  LogUtil.info(`${this._getLogTag()} destroy${name ? name :
    ''}, canvas uniqueId: ${this.wrapper?.canvas?.getUniqueId()}`);
  LogUtil.version();
  this.stop() // stop the animation because it is dying
  if (this.renderer) {
    this.renderer.destroy();
    this.renderer = null;
  }
  if (this.imagePreloader) {
    this.imagePreloader.destroy();
    this.imagePreloader = null;
  }
  this.trigger('destroy');
  this._cbs = null;
  this.onEnterFrame = null;
  this.onLoopComplete = null;
  this.onComplete = null;
  this.onSegmentStart = null;
  this.onDestroy = null;
  this.projectInterface = null;
  this.animationData = {};
  this.assets = [];
  this.segments = [];
};

AnimationItem.prototype.relativeFrameToAbsolute = function (relativeFrame) {
  return relativeFrame + this.offsetFrame;
};

AnimationItem.prototype.absoluteFrameToRelative = function (absoluteFrame) {
  return absoluteFrame - this.offsetFrame;
};

AnimationItem.prototype.gotoRelativeFrame = function (nextValue) {
  let nextFrame;
  if (this.totalFrames === nextValue) {
    nextFrame = nextValue;
  } else {
    nextFrame = nextValue % this.totalFrames;
  }

  if (nextFrame < 0) {
    nextFrame += this.totalFrames;
  }

  this.absoluteFrameToPlay = this.relativeFrameToAbsolute(nextFrame);
  this.gotoCurrentFrame(true);
};

AnimationItem.prototype.goToFrame = function (nextValue) {
  let nextFrame = nextValue;
  if (nextFrame < 0) {
    nextFrame += this.totalFrames;
  }

  this.absoluteFrameToPlay = this.relativeFrameToAbsolute(nextFrame);
  this.gotoCurrentFrame(true);
};

AnimationItem.prototype.setSpeed = function (val) {
  LogUtil.info(`${this._getLogTag()} setSpeed: ${val}`);
  if (val === 0) {
    this.pause(); // 参考 index.d.ts setSpeed的对外声明：speed>0正向播放, speed<0反向播放, speed=0暂停播放, speed=1.0/-1.0正常速度播放
    return;
  }

  if (val > 0) {
    this.setDirection(1);
  } else {
    this.setDirection(-1);
  }

  let speed = Math.abs(val); // 参考 index.d.ts playSpeed的对外声明：播放速率
  if (this._speed !== speed) {
    this._speed = speed;
    this.updateFrameModifier();
  }
};

AnimationItem.prototype.setDirection = function (val) {
  let direction = val < 0 ? -1 : 1;
  if(this._direction !== direction) {
    LogUtil.info(`${this._getLogTag()} setDirection: ${val}`);

    this._direction = direction;
    this.updateFrameModifier();
  }
};

AnimationItem.prototype.toggleDirection = function () {
  LogUtil.info(`${this._getLogTag()} toggleDirection. current is ${this._direction}`);
  this._direction = -this._direction;
  this.updateFrameModifier();
};

AnimationItem.prototype.setLoop = function (isLooping) {
  this.loop = isLooping;
};

AnimationItem.prototype.setVolume = function (val, name) {
  if (name && this.name !== name) {
    return;
  }
  this.audioController.setVolume(val);
};

AnimationItem.prototype.getVolume = function () {
  return this.audioController.getVolume();
};

AnimationItem.prototype.mute = function (name) {
  if (name && this.name !== name) {
    return;
  }
  LogUtil.info(`${this._getLogTag()} mute: ${name ? name : ''}`);

  this.audioController.mute();
};

AnimationItem.prototype.unmute = function (name) {
  if (name && this.name !== name) {
    return;
  }
  LogUtil.info(`${this._getLogTag()} unmute: ${name ? name : ''}`);

  this.audioController.unmute();
};

AnimationItem.prototype.updateFrameModifier = function () {
  let direction = 1;
  if (this.firstFrame > this.endFrame) {
    direction = this._direction > 0 ? -1 : 1; //由大到小播放时，正向需要用负值，反向需要正值
  } else {
    direction = this._direction > 0 ? 1 : -1;
  }

  let modifier = this._speed * direction;
  this.frameModifier = this.frameMult * modifier;
  this.audioController.setRate(modifier);
};

AnimationItem.prototype.getPath = function () {
  return this.path;
};

AnimationItem.prototype.getAssetsPath = function (assetData) {
  var path = '';
  if (assetData.e) {
    path = assetData.p;
  } else if (this.assetsPath) {
    var imagePath = assetData.p;
    if (imagePath.indexOf('images/') !== -1) {
      imagePath = imagePath.split('/')[1];
    }
    path = this.assetsPath + imagePath;
  } else {
    path = this.path;
    path += assetData.u ? assetData.u : '';
    path += assetData.p;
  }
  return path;
};

AnimationItem.prototype.getAssetData = function (id) {
  var i = 0;
  var len = this.assets ? this.assets.length : 0;
  while (i < len) {
    if (id === this.assets[i].id) {
      return this.assets[i];
    }
    i += 1;
  }
  return null;
};

AnimationItem.prototype.hide = function () {
  LogUtil.info(`${this._getLogTag()} hide.`);
  if (!this.renderer) {
    return;
  }
  this.renderer.hide();
};

AnimationItem.prototype.show = function () {
  LogUtil.info(`${this._getLogTag()} show.`);
  if (!this.renderer) {
    return;
  }
  this.renderer.show();
};

AnimationItem.prototype.getDuration = function (isFrame) {
  let duration = isFrame ? this.totalFrames : this.totalFrames / this.frameMult;
  LogUtil.info(`${this._getLogTag()} getDuration: total ${duration} ${isFrame ? 'frames' : 's'}`);
  return duration;
};

AnimationItem.prototype.updateDocumentData = function (path, documentData, index) {
  if (!this.renderer) {
    return;
  }
  try {
    var element = this.renderer.getElementByPath(path);
    element.updateDocumentData(documentData, index);
  } catch (error) {
    LogUtil.warn(`${this._getLogTag()} exception in updateDocumentData: ${error.message}`);
    // TODO: decide how to handle catch case
  }
};

AnimationItem.prototype.trigger = function (name, args) {
  if (this._cbs && this._cbs[name]) {
    switch (name) {
      case 'enterFrame':
        this.triggerEvent(name, new BMEnterFrameEvent(name, this.currentFrame, this.totalFrames, this.frameModifier));
        break;
      case 'drawnFrame':
        this.drawnFrameEvent.currentTime = this.currentFrame;
        this.drawnFrameEvent.totalTime = this.totalFrames;
        this.drawnFrameEvent.direction = this.frameModifier;
        this.triggerEvent(name, this.drawnFrameEvent);
        break;
      case 'loopComplete':
        this.triggerEvent(name, new BMCompleteLoopEvent(name, this.loop, this.playCount, this.frameMult));
        break;
      case 'complete':
        this.triggerEvent(name, new BMCompleteEvent(name, this.frameMult));
        break;
      case 'segmentStart':
        this.triggerEvent(name, new BMSegmentStartEvent(name, this.offsetFrame, this.totalFrames));
        break;
      case 'destroy':
        this.triggerEvent(name, new BMDestroyEvent(name, this));
        break;
      default:
        this.triggerEvent(name, args);
    }
  }
  if (name === 'enterFrame' && this.onEnterFrame) {
    this.onEnterFrame.call(this, new BMEnterFrameEvent(name, this.currentFrame, this.totalFrames, this.frameMult));
  }
  if (name === 'loopComplete' && this.onLoopComplete) {
    this.onLoopComplete.call(this, new BMCompleteLoopEvent(name, this.loop, this.playCount, this.frameMult));
  }
  if (name === 'complete' && this.onComplete) {
    this.onComplete.call(this, new BMCompleteEvent(name, this.frameMult));
  }
  if (name === 'segmentStart' && this.onSegmentStart) {
    this.onSegmentStart.call(this, new BMSegmentStartEvent(name, this.offsetFrame, this.totalFrames));
  }
  if (name === 'destroy' && this.onDestroy) {
    this.onDestroy.call(this, new BMDestroyEvent(name, this));
  }
};

AnimationItem.prototype.triggerRenderFrameError = function (nativeError) {
  setTimeout(() => {
    this._isLoaded = false;
    var error = new BMRenderFrameErrorEvent(nativeError, this.currentFrame);
    this.triggerEvent('error', error);

    if (this.onError) {
      this.onError.call(this, error);
    }
    LogUtil.error(`${this._getLogTag()} triggerRenderFrameError: ${JSON.stringify(error)}`);
  }, 0);
};

AnimationItem.prototype.triggerConfigError = function (nativeError) {
  setTimeout(() => {
    this._isLoaded = false;
    var error = new BMConfigErrorEvent(nativeError, this.currentFrame);
    this.triggerEvent('error', error);

    if (this.onError) {
      this.onError.call(this, error);
    }
    LogUtil.error(`${this._getLogTag()} triggerConfigError: ${JSON.stringify(error)}`);
  }, 0);
};

export default AnimationItem;
