import createTag from '../utils/helpers/html_elements';
import AnimationItem from './AnimationItem';
import displaySync from '@ohos.graphics.displaySync'
import animator from '@ohos.animator';
import fs from '@ohos.file.fs';
import bez from '../utils/bez';
import { LogUtil } from '../utils/LogUtil'
import { isExistNetworkAssets } from '../utils/DataUtil';
import { unlinkSync, unlink, rmdirSync, listFileSyncs } from '../utils/FileUtil'

const animationManagerV12 = (function () {
  var moduleOb = {};
  var registeredAnimations = [];
  var playingAnimationsNum = 0;
  var _looperStopped = true;
  var _packageName = '';
  var _playingFrameRate = 0;
  var _userPlayingFrameRate = 0;
  var _looper = null;

  // web only
  function registerAnimation(element, animationData) {
    if (!element) {
      return null;
    }

    let len = registeredAnimations.length
    for (let i = 0; i < len; i++) {
      if (registeredAnimations[i].elem !== null && registeredAnimations[i].elem === element) {
        return registeredAnimations[i].animation;
      }
    }

    var animItem = new AnimationItem();
    setupAnimation(animItem, element);
    animItem.setData(element, animationData);
    return animItem;
  }

  // web only
  function getRegisteredAnimations() {
    var animations = [];
    let len = registeredAnimations.length;
    for (let i = 0; i < len; i += 1) {
      animations.push(registeredAnimations[i].animation);
    }
    return animations;
  }

  function pickMaxFrameRate() {
    let maxFrameRate = 0;
    let len = registeredAnimations.length;
    for (let i = 0; i < len; i++) {
      let animItem = registeredAnimations[i].animation;
      if(!animItem._idle) {
        let fr = animItem.getFrameRate();
        console.info(`<${animItem.packageName}>--lottie_ohos check fr from ${animItem.name} with ${fr} fps. running fr is ${_playingFrameRate}`);
        if (fr > maxFrameRate) {
          maxFrameRate = fr;
        }
      }
    }

    if (_userPlayingFrameRate > 0 && _userPlayingFrameRate < maxFrameRate ) {
      return _userPlayingFrameRate; // user already set lower frame rate. so ignore content fr for better performance
    }

    return maxFrameRate;
  }

  function addPlayingCount() {
    playingAnimationsNum += 1;
    if (playingAnimationsNum > 0) {
      activate();
    }
  }

  function subtractPlayingCount() {
    playingAnimationsNum -= 1;
    if (playingAnimationsNum <= 0) {
      deactivate()
    }
  }

  function onAnimationItemLoaded(animItem) {
    console.info(`<${animItem.packageName}>--lottie_ohos animation created: ${animItem.name} with ${animItem.frameRate} fps`)

    _packageName = animItem.packageName;
  }

  function onAnimationItemDestroy(ev) {
    let animItem = ev.target;
    let len = registeredAnimations.length
    for (let i = len-1; i >= 0; i--) {
      if (registeredAnimations[i].animation === animItem) {
        registeredAnimations[i].animation = null;
        registeredAnimations.splice(i, 1);
        console.info(`<${animItem.packageName}>--lottie_ohos animation destroyed: ${animItem.name} with ${animItem.frameRate} fps`)
      }
    }
    
    if(registeredAnimations.length <= 0) {
      deactivate();
    }
  }

  function onAnimationItemActive(animItem) {
    console.info(`<${animItem.packageName}>--lottie_ohos animation activated: ${animItem.name} with ${animItem.getFrameRate()} fps`)

    if(animItem.getFrameRate() > _playingFrameRate) {
      //有更高帧率的动画活动，需要刷新帧率
      let fr = pickMaxFrameRate();
      requestAnimatorFrameRateIfNeeded(fr);
    }

    addPlayingCount()
  }

  function onAnimationItemIdle(animItem) {
    console.info(`<${animItem.packageName}>--lottie_ohos animation deactivated: '${animItem.name}' with ${animItem.getFrameRate()} fps`)

    subtractPlayingCount()

    if(animItem.getFrameRate() >= _playingFrameRate) {
      //最高帧率的动画暂停，需要刷新为第二高的帧率值
      let fr = pickMaxFrameRate();
      requestAnimatorFrameRateIfNeeded(fr);
    }
  }

  function setupAnimation(animItem, element) {
    animItem.addEventListener('destroy', onAnimationItemDestroy);
    animItem.addEventListener('_active', onAnimationItemActive);
    animItem.addEventListener('_idle', onAnimationItemIdle);
    animItem.addEventListener('DOMLoaded', onAnimationItemLoaded);
    registeredAnimations.push({ elem: element, animation: animItem });
  }

  function loadAnimation(params) {
    console.info(`<${params.packageName ? params.packageName : ""}>--lottie_ohos loadAnimation. ${params.name ? params.name : ""}`
      + `${params.uri ? " from " + params.uri : (params.path ? " from " + params.path : "")}`);
    var animItem = new AnimationItem();
    setupAnimation(animItem, null);
    animItem.setParams(params);
    return animItem;
  }

  function setSpeed(val, animationName) {
    console.info(`<${_packageName}>--lottie_ohos setSpeed.${val}, ${animationName ? animationName : ""}`);
    let len = registeredAnimations.length;
    for (let i = 0; i < len; i += 1) {
      if (!animationName || registeredAnimations[i].animation.name === animationName) {
        registeredAnimations[i].animation.setSpeed(val, animationName);
      }
    }
  }

  function setDirection(val, animationName) {
    console.info(`<${_packageName}>--lottie_ohos setDirection.${val}, ${animationName ? animationName : ""}`);

    let len = registeredAnimations.length;
    for (let i = 0; i < len; i += 1) {
      if (!animationName || registeredAnimations[i].animation.name === animationName) {
        registeredAnimations[i].animation.setDirection(val, animationName);
      }
    }
  }

  function play(animationName) {
    console.info(`<${_packageName}>--lottie_ohos play.${animationName ? animationName : ""}`);

    let len = registeredAnimations.length;
    for (let i = 0; i < len; i += 1) {
      if (!animationName || registeredAnimations[i].animation.name === animationName) {
        registeredAnimations[i].animation.play(animationName);
      }
    }
  }

  function resume(timeStamp, displaySynced) {
    let len = registeredAnimations.length;
    // console.debug(`<${_packageName}>--lottie_ohos resume: ${timeStamp.toFixed(0)} for total ${len} animation(s)`);

    for (let i = 0; i < len; i += 1) {
      registeredAnimations[i].animation.resume(timeStamp, displaySynced);
    }
  }

  function pause(animationName) {
    console.info(`<${_packageName}>--lottie_ohos pause.${animationName ? animationName : ""}`);

    let len = registeredAnimations.length;
    for (let i = 0; i < len; i += 1) {
      if (!animationName || registeredAnimations[i].animation.name === animationName) {
        registeredAnimations[i].animation.pause(animationName);
      }
    }
  }

  function goToAndStop(value, isFrame, animationName) {
    // console.debug(`<${_packageName}>--lottie_ohos goToAndStop.${animationName ? animationName : ""}`);

    let len = registeredAnimations.length;
    for (let i = 0; i < len; i += 1) {
      if (!animationName || registeredAnimations[i].animation.name === animationName) {
        registeredAnimations[i].animation.goToAndStop(value, isFrame, animationName);
      }
    }
  }

  function goToAndPlay(value, isFrame, animationName) {
    let len = registeredAnimations.length;
    for (let i = 0; i < len; i += 1) {
      if (!animationName || registeredAnimations[i].animation.name === animationName) {
        registeredAnimations[i].animation.goToAndPlay(value, isFrame, animationName);
      }
    }
  }

  function stop(animationName) {
    console.info(`<${_packageName}>--lottie_ohos stop.${animationName ? animationName : ""}`);

    let len = registeredAnimations.length;
    for (let i = 0; i < len; i += 1) {
      if (!animationName || registeredAnimations[i].animation.name === animationName) {
        registeredAnimations[i].animation.stop(animationName);
      }
    }
  }

  function togglePause(animationName) {
    console.info(`<${_packageName}>--lottie_ohos togglePause.${animationName ? animationName : ""}`);

    let len = registeredAnimations.length;
    for (let i = 0; i < len; i += 1) {
      if (!animationName || registeredAnimations[i].animation.name === animationName) {
        registeredAnimations[i].animation.togglePause(animationName);
      }
    }
  }

  /**
   * 设置packageName
   * @param name 应用的包名
   */
  function setPackageName(name) {
    console.info(`<${_packageName}>--lottie_ohos setPackageName.${name}`);
    _packageName = name;
  }

  /**
   * 设置所有动画的最大播放帧率
   * @param frameRate 帧率
   */
  function setFrameRate(frameRate) {
    console.info(`<${_packageName}>--lottie_ohos setFrameRate: ${frameRate}`);
    _userPlayingFrameRate = frameRate;

    let maxFr = pickMaxFrameRate();
    requestAnimatorFrameRateIfNeeded(maxFr);
  }

  function requestAnimatorFrameRateIfNeeded(frameRate) {
    let looper = getSingletonLooper();
    if(frameRate === 0) {
      console.info(`<${_packageName}>--lottie_ohos cancel fr request.`)
      deactivate();
      return
    }

    if (frameRate !== _playingFrameRate) {
      if (frameRate > 0 && frameRate <= 120) {
        _playingFrameRate = frameRate;
        let expectedFrameRate = {
          min: 0,
          max: 120,
          expected: _playingFrameRate
        }
        console.info(`<${_packageName}>--lottie_ohos request fr: ${_playingFrameRate}`)
        looper.setExpectedFrameRateRange(expectedFrameRate);
      }
    }
  }

  function destroy(animationName) {
    console.info(`<${_packageName}>--lottie_ohos destroy.${animationName ? animationName : ""}`);

    let len = registeredAnimations.length
    for (let i = (len - 1); i >= 0; i -= 1) {
      if (!animationName || registeredAnimations[i].animation.name === animationName) {
        //找到即将要被destroy的动画，销毁之。会触发回调，在回调中进行状态清理
        registeredAnimations[i].animation.destroy(animationName);
      }
    }
    if (registeredAnimations.length === 0) {
      bez.storedData = {};
    }
  }

  // html only
  function searchAnimations(animationData, standalone, renderer) {
    if(!document) {
      return;
    }
    let animElements = [].concat([].slice.call(document.getElementsByClassName('lottie')),
      [].slice.call(document.getElementsByClassName('bodymovin')));
    let lenAnims = animElements.length;
    for (let i = 0; i < lenAnims; i += 1) {
      if (renderer && !!animElements[i]) {
        animElements[i].setAttribute('data-bm-type', renderer);
      }
      registerAnimation(animElements[i], animationData);
    }
    if (standalone && lenAnims === 0) {
      if (!renderer) {
        renderer = 'svg';
      }
      var body = document.getElementsByTagName('body')[0];
      body.innerText = '';
      var div = createTag('div');
      div.style.width = '100%';
      div.style.height = '100%';
      div.setAttribute('data-bm-type', renderer);
      body.appendChild(div);
      registerAnimation(div, animationData);
    }
  }

  function setContentMode(contentMode) {
    // console.debug(`<${_packageName}>--lottie_ohos setContentMode.${contentMode}`);

    let len = registeredAnimations.length
    for (let i = 0; i < len; i += 1) {
      if (!!registeredAnimations[i].animation) {
        registeredAnimations[i].animation.setContentMode(contentMode);
      }
    }
  }

  function resize(width, height) {
    // console.debug(`<${_packageName}>--lottie_ohos resize: ${width} x ${height}`);

    let len = registeredAnimations.length
    for (let  i = 0; i < len; i += 1) {
      if (!!registeredAnimations[i].animation) {
        registeredAnimations[i].animation.resize(width, height);
      }
    }
  }

  function getSingletonLooper() {
    if (!!_looper) {
      return _looper;
    }

    _looper = (function(callback) {
      var looper = {};
      var _displaySync = null;
      var _animator = null;
      var _DURATION_ = 20000;
      var _monotonicTimeStampInMs = 0;
      var _lastAnimatorProgress = 0;

      function onframe(frameInfo) {
        _monotonicTimeStampInMs = ~~(frameInfo.timestamp / 1000_000); // ns to ms then truncation to integer
        callback(_monotonicTimeStampInMs, true);
      }

      try {
        _displaySync = displaySync.create();
        _displaySync.on("frame", onframe);

        console.info(`<${_packageName}>--lottie_ohos displaySync created.`);

        looper.first = function() {
          console.info(`<${_packageName}>--lottie_ohos displaySync first`);
        }

        looper.start = function() {
          _displaySync.start();
        }

        looper.stop = function() {
          _displaySync.stop();
        }

        looper.setExpectedFrameRateRange = function(rateRange) {
          _displaySync.setExpectedFrameRateRange(rateRange);
        }

        return looper;
      } catch (e) {
        console.info(`<${_packageName}>--lottie_ohos no displaySync. API level may be too low: ${e.message}`);
        // fallback to animator
      }

      let options = {
        duration: _DURATION_,
        easing: "linear",
        delay: 0,
        fill: "forwards",
        direction: "normal",
        iterations: -1,
        begin: 0,
        end: 1
      };
      _animator = animator.create(options);
      _animator.oncancel = () => {
        _lastAnimatorProgress = 0;
      }
      _animator.onfinish = () => {
        _lastAnimatorProgress = 0;
      }
      _animator.onframe = (progress) => {
        //在每一次帧动画回调时，忽略系统时间，仅以动画步进来计算下一次时间戳，避免时间调整引起的跳变
        _monotonicTimeStampInMs += _DURATION_ * ((progress - _lastAnimatorProgress + 1) % 1);
        _lastAnimatorProgress = progress;
        callback(_monotonicTimeStampInMs, false);
      }

      looper.first = function() {
        _lastAnimatorProgress = 0;
        _monotonicTimeStampInMs = Date.now();
        console.info(`<${_packageName}>--lottie_ohos animator first: ${_monotonicTimeStampInMs.toFixed(0)}`);
      }

      looper.start = function() {
        _animator.play();
      }

      looper.stop = function() {
        //do not call '_animator.finish' function which will further call onframe causing stack overflow.
        _animator.cancel();
      }

      looper.setExpectedFrameRateRange = function(rateRange) {
        if(_animator.setExpectedFrameRateRange) {
          _animator.setExpectedFrameRateRange(rateRange);
        } else {
          console.info(`<${_packageName}>--lottie_ohos animator no displaySync. API level may be too low.`);
        }
      }

      console.info(`<${_packageName}>--lottie_ohos animator created.`);

      return looper;
    }(resume));

    return _looper;
  }

  function activate() {
    if (playingAnimationsNum > 0 && _looperStopped) {

      console.info(`<${_packageName}>--lottie_ohos activate.`);
      getSingletonLooper().first();
      getSingletonLooper().start();

      _looperStopped = false
    }
  }

  function deactivate() {
    if(!_looperStopped) {
      _looperStopped = true;
      console.info(`<${_packageName}>--lottie_ohos deactivate.`);
      _playingFrameRate = 0;
      getSingletonLooper().stop()
    }
  }

  function freeze() {
    // console.debug(`<${_packageName}>--lottie_ohos freeze.`);

    deactivate();

    let len = registeredAnimations.length;
    for (let  i = 0; i < len; i += 1) {
      if (!!registeredAnimations[i].animation) {
        registeredAnimations[i].animation.stop();
      }
    }
  }

  function unfreeze() {
    // console.debug(`<${_packageName}>--lottie_ohos unfreeze.`);
    let len = registeredAnimations.length;
    for (let  i = 0; i < len; i += 1) {
      if (!!registeredAnimations[i].animation) {
        registeredAnimations[i].animation.start();
      }
    }
    
    activate();
  }

  function setVolume(val, animationName) {
    // console.debug(`<${_packageName}>--lottie_ohos setVolume.${val}, ${animationName ? animationName : ""}`);

    let len = registeredAnimations.length
    for (let i = 0; i < len; i += 1) {
      if (!animationName || registeredAnimations[i].animation.name === animationName) {
        registeredAnimations[i].animation.setVolume(val, animationName);
      }
    }
  }

  function mute(animationName) {
    // console.debug(`<${_packageName}>--lottie_ohos mute.${animationName ? animationName : ""}`);

    let len = registeredAnimations.length
    for (let i = 0; i < len; i += 1) {
      if (!animationName || registeredAnimations[i].animation.name === animationName) {
        registeredAnimations[i].animation.mute(animationName);
      }
    }
  }

  function unmute(animationName) {
    // console.debug(`<${_packageName}>--lottie_ohos unmute.${animationName ? animationName : ""}`);

    let len = registeredAnimations.length
    for (let i = 0; i < len; i += 1) {
      if (!animationName || registeredAnimations[i].animation.name === animationName) {
        registeredAnimations[i].animation.unmute(animationName);
      }
    }
  }


  /**
   * 清除单个文件缓存（支持同步/异步模式）
   * @param {string} path - 文件路径（支持HTTP URL格式）
   * @param {Object} container - 包含JSON数据的容器对象
   * @param {boolean} isSync - 是否使用同步模式操作
   */
  function clearSingleFileCache(path, container, isSync) {
    // 安全校验：确保上下文存在
    let context = getContext();
    if(!context) return;

    // 处理HTTP资源路径
    if (path.startsWith('http')) {
      let pathSegments = path.split('/');
      let parentDirName = pathSegments[pathSegments.length - 2]; // 父级目录名
      let originalFileName = pathSegments[pathSegments.length - 1];  // 原始文件名（含扩展名）
      let cleanFileName = originalFileName.replace(/\.(?:zip|json)$/i, ''); // 清理后文件名（去除扩展名）

      let lottieBaseDir =  `${context.filesDir}/lottie/${parentDirName}`; // 基础存储目录
      let targetDirectory = `${lottieBaseDir}/${cleanFileName}`; // 目标目录

      // 执行目录清理
      rmdir(targetDirectory,isSync);
    }

    // 处理图片资源
    if (container) {
      try {
        // 解析资源中的JSON数据
        let jsonString = container.getJsonData(path);
        let jsonObj = JSON.parse(jsonString);

        // 构建图片加载目录路径
        let loadPath = `${context.filesDir}/lottie/loadImages/`;

        // 检查是否存在网络资源
        if (isExistNetworkAssets(jsonObj?.assets)) {
          rmdir(loadPath, isSync, jsonObj);
        }
      } catch (error) {
        LogUtil.error(`JSON解析失败: ${error.message}`);
      }
    }
  }

  /**
   * 异步清除文件缓存
   * @param {string} url - 要清除缓存的文件URL或本地路径
   * @param {Object|string} container - 缓存容器对象或目录路径
   */
  function clearFileCache(url, container) {
    clearFile(url, container, false);
  }

  /**
   * 同步清除文件缓存
   * @param {string} url - 要清除缓存的文件URL或本地路径
   * @param {Object|string} container - 缓存容器对象或目录路径
   */
  function clearFileCacheSync(url, container) {
    clearFile(url, container, true);
  }

  /**
   * 清理文件缓存（支持单文件或全局清理）
   * @param {string} [url] - 可选的文件URL路径，存在时清理指定文件缓存
   * @param {Object} container - 包含JSON数据的容器对象，用于解析关联资源
   * @param {boolean} isSync - 是否使用同步模式执行清理操作
   */
  function clearFile(url, container, isSync) {
    // 安全校验：确保上下文存在
    let context = getContext();
    if (!context) {
      return;
    }

    if (url) {
      // 单文件清理模式：精确清理指定URL对应的缓存
      clearSingleFileCache(url, container, isSync);
      return;
    }
    let fileDir = `${context.filesDir}/lottie`; // 应用私有文件目录
    let cacheDir = `${context.cacheDir}/lottie`; // 系统缓存目录

    // 执行清理操作（同步/异步模式）
    rmdir(fileDir, isSync);
    rmdir(cacheDir, isSync);
  }

  /**
   * 删除指定资源文件
   * @param {string} path - 基础目录路径
   * @param {Object} assets - 资源对象，包含id和p(路径)属性
   * @param {Array} filenames - 文件名数组
   * @param {boolean} isSync - 是否同步删除标志
   */
  function rmAssetsDir(path, assets, filenames, isSync) {
    // 判断是否为HTTP资源（通过检查路径是否以http开头）
    let isHttp = assets?.p?.startsWith('http');

    if (isHttp) {
      // 构造目标文件名（assets.id + '.png'）
      const targetFilename = `${assets.id}.png`;
      const fileIndex = filenames.indexOf(targetFilename);

      // 找到匹配文件时执行删除
      if (fileIndex !== -1) {
        if (isSync) {
          unlinkSync(path + filenames[fileIndex]);
        } else {
          unlink(path + filenames[fileIndex]);
        }
      }
    }
  }

  /**
   * 根据路径删除文件或目录
   * @param {string} path - 基础目录路径
   * @param {string} filename - 文件/目录名
   * @param {boolean} isSync - 是否同步操作标志
   */
  function rmDirByPath(path, filename, isSync) {
    let dirPath = path + '/' + filename;
    // 判断是否文件夹
    try {
      let isDirectory = fs.statSync(dirPath).isDirectory();
      if (isDirectory) {
        rmdirSync(dirPath);
      } else {
        if (isSync) {
          unlinkSync(dirPath);
        } else {
          unlink(dirPath);
        }
      }
    } catch (err) {
      LogUtil.error('Method rmDirByPath execute error: ' + JSON.stringify(err));
    }
  }

  /**
   *  删除目录
   * @param path - 目标根目录路径
   * @param isSync - 是否同步操作标志
   * @param jsonObj - 资源描述对象（可选）
   */
  function rmdir(path, isSync, jsonObj) {
    let filenames = listFileSyncs(path)
    if (jsonObj) {
      for (let i = 0; i < jsonObj.assets.length; i++) {
        rmAssetsDir(path, jsonObj.assets[i], filenames, isSync);
      }
    } else {
      for (let i = 0; i < filenames.length; i++) {
        rmDirByPath(path, filenames[i], isSync);
      }
    }
  }

  function bindContext2dToCoordinator(context2d) {
  }

  function unbindContext2dFromCoordinator(context2d) {
  }

  function setAttachedCanvasHasVisibleArea(context2d, hasArea) {
  }

  moduleOb.registerAnimation = registerAnimation;
  moduleOb.loadAnimation = loadAnimation;
  moduleOb.setSpeed = setSpeed;
  moduleOb.setDirection = setDirection;
  moduleOb.play = play;
  moduleOb.pause = pause;
  moduleOb.stop = stop;
  moduleOb.togglePause = togglePause;
  moduleOb.searchAnimations = searchAnimations;
  moduleOb.resize = resize;
  moduleOb.clearFileCache = clearFileCache;
  moduleOb.clearFileCacheSync = clearFileCacheSync;
  // moduleOb.start = start;
  moduleOb.goToAndStop = goToAndStop;
  moduleOb.goToAndPlay = goToAndPlay;
  moduleOb.destroy = destroy;
  moduleOb.freeze = freeze;
  moduleOb.unfreeze = unfreeze;
  moduleOb.setVolume = setVolume;
  moduleOb.mute = mute;
  moduleOb.unmute = unmute;
  moduleOb.getRegisteredAnimations = getRegisteredAnimations;
  moduleOb.setPackageName = setPackageName;
  moduleOb.setContentMode = setContentMode;
  moduleOb.setFrameRate = setFrameRate;
  moduleOb.bindContext2dToCoordinator = bindContext2dToCoordinator;
  moduleOb.unbindContext2dFromCoordinator = unbindContext2dFromCoordinator;
  moduleOb.setAttachedCanvasHasVisibleArea = setAttachedCanvasHasVisibleArea;
  return moduleOb;
}());

export default animationManagerV12;
