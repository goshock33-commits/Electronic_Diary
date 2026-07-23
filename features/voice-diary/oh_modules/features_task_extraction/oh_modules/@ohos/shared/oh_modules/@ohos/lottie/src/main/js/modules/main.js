import { setLocationHref, setWebWorker } from '../main';
import animationManager from '../animation/AnimationManager';
import animationManagerV12 from '../animation/AnimationManagerV12';
import {
  setDefaultCurveSegments,
  getDefaultCurveSegments,
  roundValues,
  setIdPrefix,
  setSubframeEnabled,
  setExpressionsPlugin,
} from '../utils/common';
import PropertyFactory from '../utils/PropertyFactory';
import ShapePropertyFactory from '../utils/shapes/ShapeProperty';
import Matrix from '../3rd_party/transformation-matrix';
import deviceInfo from '@ohos.deviceInfo';

const SDK_VERSION_THRESHOLD = 14;
const lottie = {};
var standalone = '__[STANDALONE]__';
var animationData = '__[ANIMATIONDATA]__';
var renderer = '';
let isHighVersion = deviceInfo.sdkApiVersion > SDK_VERSION_THRESHOLD;
const manager = isHighVersion ? animationManager : animationManagerV12;

function setLocation(href) {
  setLocationHref(href);
}

function searchAnimations() {
  if (standalone === true) {
    manager.searchAnimations(animationData, standalone, renderer);
  } else {
    manager.searchAnimations();
  }
}

function setSubframeRendering(flag) {
  setSubframeEnabled(flag);
}

function setPrefix(prefix) {
  setIdPrefix(prefix);
}

function loadAnimation(params) {
  if (standalone === true) {
    params.animationData = JSON.parse(animationData);
  }
  return manager.loadAnimation(params);
}

function setQuality(value) {
  if (typeof value === 'string') {
    switch (value) {
      case 'high':
        setDefaultCurveSegments(200);
        break;
      default:
      case 'medium':
        setDefaultCurveSegments(50);
        break;
      case 'low':
        setDefaultCurveSegments(10);
        break;
    }
  } else if (!isNaN(value) && value > 1) {
    setDefaultCurveSegments(value);
  }
  if (getDefaultCurveSegments() >= 50) {
    roundValues(false);
  } else {
    roundValues(true);
  }
}

function inBrowser() {
  return false;
}

function installPlugin(type, plugin) {
  if (type === 'expressions') {
    setExpressionsPlugin(plugin);
  }
}

function getFactory(name) {
  switch (name) {
    case 'propertyFactory':
      return PropertyFactory;
    case 'shapePropertyFactory':
      return ShapePropertyFactory;
    case 'matrix':
      return Matrix;
    default:
      return null;
  }
}


lottie.play = manager.play;
lottie.pause = manager.pause;
lottie.setLocationHref = setLocation;
lottie.togglePause = manager.togglePause;
lottie.setSpeed = manager.setSpeed;
lottie.setDirection = manager.setDirection;
lottie.stop = manager.stop;
lottie.searchAnimations = searchAnimations;
lottie.registerAnimation = manager.registerAnimation;
lottie.loadAnimation = loadAnimation;
lottie.setSubframeRendering = setSubframeRendering;
lottie.resize = manager.resize;
lottie.setContentMode = manager.setContentMode;
lottie.clearFileCache = manager.clearFileCache;
lottie.clearFileCacheSync = manager.clearFileCacheSync;
// lottie.start = start;
lottie.goToAndStop = manager.goToAndStop;
lottie.goToAndPlay = manager.goToAndPlay;
lottie.destroy = animationManager.destroy;
lottie.setFrameRate = manager.setFrameRate;
lottie.setQuality = setQuality;
lottie.inBrowser = inBrowser;
lottie.installPlugin = installPlugin;
lottie.freeze = manager.freeze;
lottie.unfreeze = manager.unfreeze;
lottie.setVolume = manager.setVolume;
lottie.mute = manager.mute;
lottie.unmute = manager.unmute;
lottie.getRegisteredAnimations = manager.getRegisteredAnimations;
lottie.bindContext2dToCoordinator = manager.bindContext2dToCoordinator;
lottie.unbindContext2dFromCoordinator = manager.unbindContext2dFromCoordinator;
lottie.setAttachedCanvasHasVisibleArea = manager.setAttachedCanvasHasVisibleArea;
lottie.useWebWorker = setWebWorker;
lottie.setIDPrefix = setPrefix;
lottie.__getFactory = getFactory;
lottie.version = '[[BM_VERSION]]';


function getQueryVariable(variable) {
  var vars = queryString.split('&');
  for (var i = 0; i < vars.length; i += 1) {
    var pair = vars[i].split('=');
    if (decodeURIComponent(pair[0]) == variable) { // eslint-disable-line eqeqeq
      return decodeURIComponent(pair[1]);
    }
  }
  return null;
}
var queryString = '';
if (standalone) {
  renderer = getQueryVariable('renderer');
}

export default lottie;
