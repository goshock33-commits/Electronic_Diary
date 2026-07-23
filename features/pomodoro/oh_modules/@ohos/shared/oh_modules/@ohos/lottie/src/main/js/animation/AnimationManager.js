import createTag from '../utils/helpers/html_elements';
import AnimationItem from './AnimationItem';
import displaySync from '@ohos.graphics.displaySync'
import animator from '@ohos.animator';
import fs from '@ohos.file.fs';
import bez from '../utils/bez';
import { LogUtil } from '../utils/LogUtil'
import deviceInfo from '@ohos.deviceInfo';
import { isExistNetworkAssets } from '../utils/DataUtil';
import { unlinkSync, unlink, rmdirSync, listFileSyncs } from '../utils/FileUtil'

let _nextIdInCoordinator = 0;
const Coordinator = function() {
    this._context2dShadows = new WeakMap();
    this._context2dCallbacks = new WeakMap();
    this._canvasShadows = new WeakMap();
};

Coordinator.prototype._getLogTag = function() {
    return '<Coordinator>';
};

Coordinator.prototype._getOrCreateCanvasShadow = function(canvas) {
    if (!canvas) {
        return {};
    }
    let canvasShadow = this._canvasShadows.get(canvas);
    if (canvasShadow) {
        return canvasShadow;
    }
    canvasShadow = {
        canvas, // G.OBJ.03 推荐在对象字面量中使用方法简写和属性简写
        status: {
            hasArea: undefined,
        },
        context2dShadow: undefined,
    };
    this._canvasShadows.set(canvas, canvasShadow);

    // 以下2个接口未支持链式调用, 此处注册有可能会覆盖此前其它处理逻辑所注册的处理逻辑. 当然其它处理逻辑也可能影响coordinator的行为.
    // 应避免不同的处理逻辑同时针对同一个canvas节点进行注册. 此处输出日志便于维测.
    LogUtil.warn(`${this._getLogTag()} coordinator register canvas(${canvas.getUniqueId()}) callbacks.`);
    canvas.commonEvent.setOnVisibleAreaApproximateChange(
        { ratios: [0], expectedUpdateInterval: 500 },
        this._onVisibleAreaApproximateChange.bind(this, canvas));

    return canvasShadow;
};

Coordinator.prototype._isNodeAndAncestorVisible = function (node) {
    if (!node) {
        return false;
    }

    let isVisible = node.isVisible();
    let parent = node.getParent();
    while (parent && isVisible) {
        isVisible = parent.isVisible();
        parent = parent.getParent();
    }
    return isVisible;
};

Coordinator.prototype._notifyAnimationCanvasHasArea = function (animation, hasArea, context2dShadow) {
    /*
     * 影子数据的构建是依赖各种回调被依次调用，才能逐步完成. 在被构建出来之前, 存在 canvas 状态未知的情形
     */
    if (!animation) {
        return;
    }

    let canvas = context2dShadow?.canvasShadow?.canvas;
    let canvasUniqueId = canvas?.getUniqueId();
    let _hasArea = hasArea;
    if (_hasArea !== true && _hasArea !== false) {
        // canvas节点可见性状态未知, 此时canvas可能早已创建过, 也可能刚刚开始创建, 通过获取一次当前状态进行辅助判断
        let isAttached = canvas?.isAttached();
        let isVisible = this._isNodeAndAncestorVisible(canvas);
        LogUtil.warn(`${this._getLogTag()} canvas(${canvasUniqueId}) is ${isAttached ? 'attached to' :
            'detached from'} UItree and ${isVisible ? 'visible' : 'invisible'}`);
        if (!isAttached || !isVisible) {
            _hasArea = false;
        } else if (context2dShadow.option.preferredNoArea) {
            LogUtil.info(`${this._getLogTag()} regard canvas(${canvasUniqueId}) as no visible area.`);
            _hasArea = false;
        }
    }

    if (_hasArea === true || _hasArea === false) {
        animation.onCanvasHasVisibleArea(canvasUniqueId, _hasArea);
    } else {
        // 即便canvas是在树上且visible, 也不意味着节点是具备可见面积的, 为保持前向兼容, 此时不对animation做主动通知
        LogUtil.warn(`${this._getLogTag()} do NOT notify animation(${animation.animationID}) for indeterminate canvas(${canvasUniqueId}) status.`);
    }
};

Coordinator.prototype._onVisibleAreaApproximateChange = function(canvas, isVisible) {
    let uniqueId = canvas?.getUniqueId();
    LogUtil.info(`${this._getLogTag()} canvas(${uniqueId}) visible area changed to ${isVisible}.`);
    if (!canvas) {
        return;
    }
    let canvasShadow = this._canvasShadows.get(canvas);
    if (canvasShadow) {
        canvasShadow.status.hasArea = isVisible;

        this._notifyAnimationCanvasHasArea(canvasShadow.context2dShadow?.animation, isVisible,
            canvasShadow.context2dShadow);
    }
};

Coordinator.prototype._onContext2dAttachedToCanvas = function (context2d) {
    if (!context2d) {
        return;
    }
    let { canvas } = context2d;
    let canvasUniqueId = canvas?.getUniqueId();
    let context2dShadow = this._context2dShadows.get(context2d);
    LogUtil.info(`${this._getLogTag()} context2d(${context2dShadow?._id}) attached to canvas(${canvasUniqueId})`);
    if (!canvas) {
        return;
    }
    let canvasShadow = this._getOrCreateCanvasShadow(canvas);
    canvasShadow.context2dShadow = context2dShadow;

    if (context2dShadow && context2dShadow.canvasShadow !== canvasShadow) {
        context2dShadow.canvasShadow = canvasShadow;
    } else {
        LogUtil.warn(`${this._getLogTag()} context2d(${context2dShadow?._id}) already attached to the same canvas(${canvasUniqueId}).`);
    }

    this._onVisibleAreaApproximateChange(canvasShadow.canvas, canvasShadow.status.hasArea);
};

Coordinator.prototype._onContext2dDetachedFromCanvas = function (context2d) {
    if (!context2d) {
        return;
    }
    let context2dShadow = this._context2dShadows.get(context2d);
    let canvas = context2dShadow?.canvasShadow?.canvas;
    let canvasUniqueId = canvas?.getUniqueId();
    LogUtil.info(`${this._getLogTag()} context2d(${context2dShadow?._id}) detached from canvas(${canvasUniqueId})`);

    this._notifyAnimationCanvasHasArea(context2dShadow?.animation, false, context2dShadow);

    if (canvas) {
        let canvasShadow = this._getOrCreateCanvasShadow(canvas);
        if (canvasShadow) {
            canvasShadow.context2dShadow = null;
        }
    }

    if (context2dShadow) {
        context2dShadow.canvasShadow = null; // null:确定解绑, undefined:不确定是否绑定
    }
};

Coordinator.prototype._getOrCreateContext2dCallback = function (context2d) {
    if (!context2d) {
        return {};
    }
    let callbacks = this._context2dCallbacks.get(context2d);
    if (!callbacks) {
        // _onContext2dAttachedToCanvas 需要一个额外的context2d作为参数, 需通过bind传递进去
        callbacks = {
            onContext2dAttachedToCanvas: this._onContext2dAttachedToCanvas.bind(this, context2d),
            onContext2dDetachedFromCanvas: this._onContext2dDetachedFromCanvas.bind(this, context2d),
        };
        this._context2dCallbacks.set(context2d, callbacks);
    }
    return callbacks;
};

Coordinator.prototype.setAttachedCanvasHasVisibleArea = function(context2d, hasArea) {
    if (!context2d) {
        return;
    }
    let context2dShadow = this._context2dShadows.get(context2d);
    if (!context2dShadow) {
        LogUtil.warn(`${this._getLogTag()} context2d has not yet bound to coordinator.`);
        return;
    }

    let canvas = context2dShadow.canvasShadow?.canvas;
    if (canvas) {
        LogUtil.info(`${this._getLogTag()} fix visible area of canvas(${canvas.getUniqueId()})` +
            ` attached to context2d(${context2dShadow._id}) to ${hasArea}`);
        this._onVisibleAreaApproximateChange(canvas, hasArea);
    } else {
        LogUtil.warn(`${this._getLogTag()} context2d(${context2dShadow._id}) has no canvas attached.`);
    }
};

Coordinator.prototype.isContext2dBoundToCoordinator = function (context2d) {
    if (!context2d) {
        return false;
    }
    return this._context2dShadows.has(context2d);
};

Coordinator.prototype.bindContext2dToCoordinator = function(context2d) {
    if (!context2d) {
        return;
    }
    let context2dShadow = this._context2dShadows.get(context2d);
    if (context2dShadow) {
        LogUtil.info(`${this._getLogTag()} context2d(${context2dShadow._id}) already attached to coordinator.`);
        context2dShadow.option.preferredNoArea = true;
        return;
    }
    this.internalBindContext2dToCoordinator(context2d, true);
};

Coordinator.prototype.internalBindContext2dToCoordinator = function (context2d, preferredNoArea) {
    if (deviceInfo.sdkApiVersion < 13 || !context2d?.on) {
        // 影子数据强依赖context2d的on接口, 只有API 13+才具备.
        LogUtil.error(`${this._getLogTag()} API level(${deviceInfo.sdkApiVersion}) is too low.`);
        return;
    }

    let context2dShadow = {
        _id: _nextIdInCoordinator++,
        context2d,
        option: {
            preferredNoArea, // G.OBJ.03 推荐在对象字面量中使用方法简写和属性简写
        },
        animation: undefined, // undefined:不确定是否绑定
        canvasShadow: undefined, // undefined:不确定是否绑定
    };
    this._context2dShadows.set(context2d, context2dShadow);
    LogUtil.info(`${this._getLogTag()} bind context2d(${context2dShadow._id}) to coordinator${preferredNoArea ?
        ' with no area preferred' : ''}.`);

    let callbacks = this._getOrCreateContext2dCallback(context2d);
    context2d.on('onAttach', callbacks.onContext2dAttachedToCanvas);
    context2d.on('onDetach', callbacks.onContext2dDetachedFromCanvas);

    let { canvas } = context2d; // G.MET.11 建议使用参数的解构
    if (canvas) {
        /* 此时context2d有一个关联到的canvas. 它与context2d有可能是attached的, 也有可能是曾经attached过但又被detached了.
         * 为避免误判造成本该活动而未活动, 此处视其为attached的canvas来处理, 并做一次必要的"补调"
         */
        LogUtil.warn(`${this._getLogTag()} canvas(${canvas.getUniqueId()}) indeterminate attached or not, treat it as attached.`);
        callbacks.onContext2dAttachedToCanvas();
    } else {
        context2dShadow.canvasShadow = null;
    }
};

Coordinator.prototype.unbindContext2dFromCoordinator = function (context2d) {
    if (!context2d) {
        return;
    }
    if (deviceInfo.sdkApiVersion < 13) {
        // 影子数据强依赖context2d的on接口, 只有API 13+才具备.
        LogUtil.error(`${this._getLogTag()} API level(${deviceInfo.sdkApiVersion}) is too low.`);
        return;
    }

    let context2dShadow = this._context2dShadows.get(context2d);
    LogUtil.info(`${this._getLogTag()} unbind context2d(${context2dShadow?._id}) from coordinator`);

    if (!context2dShadow) {
        return;
    }

    let canvas = context2dShadow.canvasShadow?.canvas;
    if (canvas) {
        // 这里应该去解注册canvas上的回调, 但解注册接口存在bug, 再次注册时接口会失效.
        // 考虑到canvas节点销毁时回调自然会被解掉, 故这里忽略相关的解注册处理, 直接清理cache.
        this._canvasShadows.delete(canvas);
    }

    let callbacks = this._context2dCallbacks.get(context2d);
    if (callbacks && context2d?.off) {
        context2d.off('onAttach', callbacks.onContext2dAttachedToCanvas);
        context2d.off('onDetach', callbacks.onContext2dDetachedFromCanvas);
    }

    this._context2dShadows.delete(context2d);
    this._context2dCallbacks.delete(context2d);
    this._canvasShadows.delete(context2d.canvas);
};

Coordinator.prototype.attachAnimationToContext2d = function (context2d, animation) {
    if (!context2d) {
        return;
    }
    let context2dShadow = this._context2dShadows.get(context2d);
    if (!context2dShadow) {
        LogUtil.warn(`${this._getLogTag()} context2d must be bound to coordinator firstly. `);
        return;
    }

    if (context2dShadow.animation === animation) {
        LogUtil.warn(`${this._getLogTag()} animation(${animation?.animationID}) already attached to context2d(${context2dShadow._id}).`);
        return;
    }

    context2dShadow.animation = animation;

    let { canvasShadow } = context2dShadow;
    if (canvasShadow) {
        this._onVisibleAreaApproximateChange(canvasShadow.canvas, canvasShadow.status.hasArea);
    }
};

Coordinator.prototype.detachAnimationFromContext2d = function (context2d) {
    if (!context2d) {
        return null;
    }
    let context2dShadow = this._context2dShadows.get(context2d);
    if (!context2dShadow) {
        return null;
    }

    let { animation } = context2dShadow; // G.MET.11 建议使用参数的解构
    context2dShadow.animation = null; // null:确定解绑, undefined:不确定是否绑定

    return animation;
};

/**
 * isSkipFrameByOwn需要在初始化时给出, 不能在运行时动态改变.
 * 若要支持动态改变, 需要做到动态去除displaysync的投票, 暂无合适接口.
 * 销毁后重建displaysync是个可选项, 但涉及到各种状态管理过于复杂.
 * 该场景并不常见, 故暂不实现.
 **/
const _DURATION_BY_MS_ = 20000;
const _ALLOWABLE_ERROR_BY_MS_ = 1.5; // timestamp的时间精度为1个ms, 故让容许误差稍大于该值
const _LEAD_BY_MS_ = 5; // 提前post frameCallback 的时间, 该值不能太小以至于错过vsync, 也不宜太大导致帧率过高.
let _nextIdInLooper = 0;
const Looper = function(uiContext, animations, playFrameCallback, isSkipFrameByOwn) {
    this._id = _nextIdInLooper++;
    this._uiContext = uiContext;
    this._animations = animations;
    this._playingAnimationsNum = 0;
    this._looperStopped = true;
    this._playingFrameRate = 0;
    this._looperType = null;
    this._displaySync = null;
    this._frameCallback = undefined;
    this._frameCallbackPosted = 0;
    this._animator = null;
    this._monotonicTimeStampInMs = 0;
    this._lastAnimatorProgress = 0;
    this._lastOnFrameTs = 0;
    this._lastPlayedFrameTs = 0;
    this._expectedFrameTs = 0;
    this._periodByMs = 0;
    this._playFrameCallback = playFrameCallback;
    this._setExpectedFrameRateRangeWrapper = null;
    this._isSkipFrameByOwn = isSkipFrameByOwn;
    this.__performance = {
        lastTimestamp: 0,
        frames: 0,
        janks: 0,
        maxPeriod: 0,
    };

    if (isSkipFrameByOwn) {
        if (this._initFrameCallbackLooper()) {
            // 主动跳帧时优选frameCallback
            return;
        }
    }

    if (this._initDisplaySyncLooper()) {
        return;
    }

    // fallback to animator
    this._initAnimatorLooper();
};

Looper.prototype._getLogTag = function() {
    if (this._uiContext?.getHostContext()?.abilityInfo?.name) {
        return `<Looper@${this._uiContext.getHostContext().abilityInfo.name}(${this._id})>`;
    } else {
        return `<Looper(${this._id})>`;
    }
};

Looper.prototype._skippingFrame = function (timestamp) {
    if (this._periodByMs === 0) {
        return false;
    }

    let supplyingPeriod = 0;
    if (this._lastOnFrameTs !== 0) {
        supplyingPeriod = timestamp - this._lastOnFrameTs;
    }

    let phaseOffset = this._expectedFrameTs - timestamp;
    if ((phaseOffset < 0 && phaseOffset > -_ALLOWABLE_ERROR_BY_MS_) ||
        (phaseOffset > 0 && phaseOffset < _ALLOWABLE_ERROR_BY_MS_)) {
        phaseOffset = 0; // 在容许误差范围内则忽略偏差
    }

    let halfPeriod = supplyingPeriod >> 1;
    if (phaseOffset > (halfPeriod + _ALLOWABLE_ERROR_BY_MS_)) {
        return true; // 偏差离当前vsync过大, 主动跳过本帧
    }

    // 计算下一帧时间戳. 注意js的取模运算与其它语言不同, 会出现负的余数
    this._expectedFrameTs = timestamp + phaseOffset % this._periodByMs + this._periodByMs;

    return false;
};

Looper.prototype._baseOnframe = function (timestamp, displaySynced) {
    if (this._isSkipFrameByOwn && this._skippingFrame(timestamp)) {
        return;
    }

    this._playFrameCallback(this._uiContext, timestamp, displaySynced);

    this._performancePeriodically(timestamp);

    this._lastPlayedFrameTs = timestamp;
};

Looper.prototype._performancePeriodically = function (timestamp) {
    let _DURATION_ = 2_000; // heartbeat every <_DURATION_>ms elapsed

    try {
        this.__performance.frames++;

        let supplyingPeriod = timestamp - this._lastPlayedFrameTs;
        if (supplyingPeriod > this._periodByMs + _ALLOWABLE_ERROR_BY_MS_ + _ALLOWABLE_ERROR_BY_MS_) {
            this.__performance.janks++;
        }

        if (supplyingPeriod > this.__performance.maxPeriod) {
            this.__performance.maxPeriod = supplyingPeriod;
        }

        let elapsedMs = timestamp - this.__performance.lastTimestamp;
        if (elapsedMs > _DURATION_) {
            this.__performance.frames = 0;
            this.__performance.janks = 0;
            this.__performance.maxPeriod = 0;
            this.__performance.lastTimestamp = timestamp;
        }
    } catch (e) {
        // do nothing. performing does NOT matter
    }
};

Looper.prototype._baseFirst = function () {
    this._monotonicTimeStampInMs = 0;
    this._lastPlayedFrameTs = 0;
    this._expectedFrameTs = 0;
};

Looper.prototype._baseSetExpectedFrameRateRange = function (playingFrameRate) {
    LogUtil.info(`${this._getLogTag()} ${this._looperType} running at ${playingFrameRate} HZ`);
    this._periodByMs = 1000 / playingFrameRate;

    if (!this._isSkipFrameByOwn) {
        if (this._setExpectedFrameRateRangeWrapper) {
            this._setExpectedFrameRateRangeWrapper({ min: 0, max: 120, expected: playingFrameRate });
        } else {
            LogUtil.warn(`${this._getLogTag()} ${this._looperType} has no displaySync. no frame rate set.`);
        }
    } else {
        // 不做投票, 避免拉低ui帧率
    }
};

Looper.prototype._initFrameCallbackLooper = function () {
    let apiVersion = deviceInfo?.sdkApiVersion;
    if (apiVersion >= 13 && this._uiContext) {
        /* 尽管FrameCallback机制在API 12已支持, 但由于它所依赖的uiContext需要从context2d所关联的canvas节点中获取,
         * 而API 13及以上才支持从context2d中获取canvas节点, 故只能在API 13及以上才可以使能frameCallback
         */
        this._frameCallback = {
            onFrame: (timestamp) => {
                this._frameCallbackPosted--; // 每次进入回调均意味着消费掉1次frameCallback

                if (this._looperStopped) {
                    return;
                }

                // 确保有且仅有1个frameCallback被post到管线上, 避免frameCallback堆积
                if (this._uiContext && this._frameCallbackPosted <= 0) {
                    this._uiContext.postDelayedFrameCallback(this._frameCallback, this._periodByMs - _LEAD_BY_MS_);
                    this._frameCallbackPosted++;
                }

                this._lastOnFrameTs = this._monotonicTimeStampInMs;
                this._monotonicTimeStampInMs = Math.floor(timestamp / 1000_000);

                this._baseOnframe(this._monotonicTimeStampInMs, true);
            },
        };
        LogUtil.info(`${this._getLogTag()} frameCallback created.`);

        this._exportApiByFrameCallback();

        return true;
    } else {
        LogUtil.warn(`${this._getLogTag()} api version(${apiVersion}) is too low. frameCallback is disabled.`);
    }

    return false;
};

Looper.prototype._exportApiByFrameCallback = function() {
    // 导出外部可调用方法(内部方法以"_"开头)
    this._looperType = 'frameCallback';

    this.first = function () {
        this._baseFirst();
        LogUtil.info(`${this._getLogTag()} ${this._looperType} first`);
    };

    this.start = function () {
        LogUtil.info(`${this._getLogTag()} ${this._looperType} start`);
        if (this._uiContext) {
            if (this._frameCallbackPosted <= 0) {
                // 不能无条件post. 如果已有callback被posted, 再次post会造成frameCallback堆积导致高帧率
                this._uiContext.postFrameCallback(this._frameCallback);
                this._frameCallbackPosted++;
            }
            this._looperStopped = false;
        } else {
            LogUtil.warn(`${this._getLogTag()} ${this._looperType} no uicontext, frameCallback could not work.`);
        }
    };

    this.stop = function () {
        LogUtil.info(`${this._getLogTag()} ${this._looperType} stop`);
        this._looperStopped = true;
    };

    this.setExpectedFrameRateRange = function (playingFrameRate) {
        this._baseSetExpectedFrameRateRange(playingFrameRate);
    };
};

Looper.prototype._initDisplaySyncLooper = function () {
    try {
        this._displaySync = displaySync.create();
        this._displaySync.on('frame', (frameInfo) => {
            if (this._looperStopped) {
                return;
            }

            this._lastOnFrameTs = this._monotonicTimeStampInMs;
            this._monotonicTimeStampInMs = Math.floor(frameInfo.timestamp / 1000_000);

            this._baseOnframe(this._monotonicTimeStampInMs, true);
        });
        LogUtil.info(`${this._getLogTag()} displaySync created.`);

        this._exportApiByDisplaySync();

        return true;
    } catch (e) {
        LogUtil.info(`${this._getLogTag()} no displaySync. API version(${deviceInfo?.sdkApiVersion}) may be too low: ${e.message}`);
    }

    return false;
};

Looper.prototype._exportApiByDisplaySync = function() {
    // 导出外部可调用方法(内部方法以"_"开头)
    this._looperType = 'displaySync';

    this.first = function () {
        this._baseFirst();
        LogUtil.info(`${this._getLogTag()} ${this._looperType} first`);
    };

    this.start = function () {
        if (this._uiContext.getHostContext() !== getContext()) {
            LogUtil.warn(`${this._getLogTag()} ${this._looperType} could NOT start cause context not matched`);
            return;
        }
        LogUtil.info(`${this._getLogTag()} ${this._looperType} start`);
        this._displaySync.start();
        this._looperStopped = false;
    };

    this.stop = function () {
        if (this._uiContext.getHostContext() !== getContext()) {
            LogUtil.warn(`${this._getLogTag()} ${this._looperType} could NOT stop cause context not matched`);
            return;
        }
        LogUtil.info(`${this._getLogTag()} ${this._looperType} stop`);
        this._looperStopped = true;
        this._displaySync.stop();
    };

    this._setExpectedFrameRateRangeWrapper = this._displaySync.setExpectedFrameRateRange.bind(this._displaySync);
    this.setExpectedFrameRateRange = function (playingFrameRate) {
        this._baseSetExpectedFrameRateRange(playingFrameRate);
    };
};

Looper.prototype._initAnimatorLooper = function () {
    let options = {
        duration: _DURATION_BY_MS_,
        easing: 'linear',
        delay: 0,
        fill: 'forwards',
        direction: 'normal',
        iterations: -1,
        begin: 0,
        end: 1
    };
    this._animator = animator.create(options);
    this._registerCallbackForAnimator();
    LogUtil.info(`${this._getLogTag()} animator created.`);

    this._exportApiByAnimator();

    return true;
};

Looper.prototype._registerCallbackForAnimator = function() {
    let sdkApiVersion = deviceInfo?.sdkApiVersion;

    let oncancel = () => {
        this._lastAnimatorProgress = 0;
        LogUtil.info(`${this._getLogTag()} ${this._looperType} oncancel.`);
    };
    if (sdkApiVersion >= 12) {
        this._animator.onCancel = oncancel;
    } else {
        this._animator.oncancel = oncancel;
    }

    let onfinish = () => {
        this._lastAnimatorProgress = 0;
        LogUtil.info(`${this._getLogTag()} ${this._looperType} onfinish.`);
    };
    if (sdkApiVersion >= 12) {
        this._animator.onFinish = onfinish;
    } else {
        this._animator.onfinish = onfinish;
    }

    let onframe = (progress) => {
        if (this._looperStopped) {
            // animator.cancel -> onframe -> animator.oncancel
            return;
        }
        // 在每一次帧动画回调时，忽略系统时间，仅以动画步进来计算下一次时间戳，避免时间调整引起的跳变
        let positiveProgress = progress - this._lastAnimatorProgress + 1;
        let modularProgress = positiveProgress - (positiveProgress >>> 0); // 高效地取出小数部分, 相当于对1取模
        let step = (_DURATION_BY_MS_ * modularProgress) >>> 0; // Zero-fill right shift for truncation to integer
        if (step > 0) {
            if (step > this._periodByMs + _ALLOWABLE_ERROR_BY_MS_ + _ALLOWABLE_ERROR_BY_MS_) {
                let logInfo =
                    `step(${step}) is too significant. progress(${progress
                    }), last progress(${this._lastAnimatorProgress
                    }), modular progress(${modularProgress
                    })`;
                LogUtil.warn(`${this._getLogTag()} ${this._looperType} ${logInfo}`);
            }

            this._lastOnFrameTs = this._monotonicTimeStampInMs;
            this._monotonicTimeStampInMs += step;
            this._lastAnimatorProgress = progress;

            this._baseOnframe(this._monotonicTimeStampInMs, false);
        }
    };
    if (sdkApiVersion >= 12) {
        this._animator.onFrame = onframe;
    } else {
        this._animator.onframe = onframe;
    }
};

Looper.prototype._exportApiByAnimator = function() {
    this._looperType = 'animator';

    this.first = function () {
        this._baseFirst();
        this._lastAnimatorProgress = 0;
        this._monotonicTimeStampInMs = Math.floor(Date.now());
        LogUtil.info(`${this._getLogTag()} ${this._looperType} first: ${this._monotonicTimeStampInMs}`);
    };

    this.start = function () {
        if (this._uiContext.getHostContext() !== getContext()) {
            LogUtil.warn(`${this._getLogTag()} ${this._looperType} could NOT start cause context not matched`);
            return;
        }
        LogUtil.info(`${this._getLogTag()} ${this._looperType} play`);
        this._animator.play();
        this._looperStopped = false;
    };

    this.stop = function () {
        if (this._uiContext.getHostContext() !== getContext()) {
            LogUtil.warn(`${this._getLogTag()} ${this._looperType} could NOT stop cause context not matched`);
            return;
        }
        LogUtil.info(`${this._getLogTag()} ${this._looperType} cancel`);
        this._looperStopped = true;
        // do not call '_animator.finish' function which will further call animator.onframe causing stack overflow.
        this._animator.cancel();
    };

    this._setExpectedFrameRateRangeWrapper = this._animator.setExpectedFrameRateRange?.bind(this._animator);
    this.setExpectedFrameRateRange = function (playingFrameRate) {
        this._baseSetExpectedFrameRateRange(playingFrameRate);
    };
};

Looper.prototype.onAnimationActive = function(animItem) {
    if (animItem?.getFrameRate() > this._playingFrameRate) {
        // 有更高帧率的动画活动，需要刷新帧率
        this.changeFrameRateIfNeeded();
    }

    this.addPlayingCount();
};

Looper.prototype.onAnimationIdle = function(animItem) {
    this.subtractPlayingCount();

    if (animItem?.getFrameRate() >= this._playingFrameRate) {
        // 最高帧率的动画暂停，需要刷新为第二高的帧率值
        this.changeFrameRateIfNeeded();
    }
};

Looper.prototype.pickMaxFrameRate = function() {
    let maxUserFr = animationManager?.getFrameRate();
    if (maxUserFr > 0 && maxUserFr <= 120) {
        return maxUserFr; // user already set frame rate. so ignore content fr for better performance
    }

    let maxFrameRate = 0;
    let len = this._animations?.length;
    for (let i = 0; i < len; i++) {
        let animItem = this._animations[i]?.animation;
        let uiContext = animItem?.getUiContext();
        if ((!uiContext || (uiContext === this._uiContext)) && !animItem?._idle) {
            let fr = animItem?.getFrameRate();
            LogUtil.info(`${this._getLogTag()} check fr from '${animItem?.name}(${animItem?.animationID})' with ${fr} fps.`);
            if (fr > maxFrameRate) {
                maxFrameRate = fr;
            }
        }
    }
    return maxFrameRate;
};

Looper.prototype.addPlayingCount = function() {
    this._playingAnimationsNum += 1;
    if (this._playingAnimationsNum > 0) {
        this.activate();
    }
};

Looper.prototype.subtractPlayingCount = function() {
    this._playingAnimationsNum -= 1;
    if (this._playingAnimationsNum <= 0) {
        this._playingAnimationsNum = 0;
        this.deactivate();
    }
};

Looper.prototype.activate = function() {
    if (this._playingAnimationsNum > 0 && this._looperStopped) {
        LogUtil.info(`${this._getLogTag()} activate.`);
        this.first();
        this.start();
    }
};

Looper.prototype.deactivate = function() {
    if (!this._looperStopped) {
        LogUtil.info(`${this._getLogTag()} deactivate`);
        this._playingFrameRate = 0;
        this.stop();
    }
};

Looper.prototype.changeFrameRateIfNeeded = function() {
    let maxFr = this.pickMaxFrameRate();
    if (maxFr === 0) {
        this.deactivate();
        return;
    }

    if (maxFr !== this._playingFrameRate) {
        if (maxFr > 0 && maxFr <= 120) {
            this._playingFrameRate = maxFr;
            this.setExpectedFrameRateRange(this._playingFrameRate);
        }
    }
};

const animationManager = (function(){
    let moduleOb = {};
    let registeredAnimations = [];
    let _packageName = '';
    let _userPlayingFrameRate = 0;
    let _contextLoopers = new WeakMap();
    let _coordinator = new Coordinator();

    function _getLogTag() {
        let abilityName = getContext()?.abilityInfo?.name;
        if (abilityName && _packageName !== '') {
            return `<Manager(${abilityName})@${_packageName}>`;
        } else if (abilityName) {
            return `<Manager(${abilityName})>`;
        } else if (_packageName !== '') {
            return `<Manager@${_packageName}>`;
        } else {
            return '<Manager>';
        }
    }

    function _logFunc(funcName, name, onlyCurrentAbility, value) {
        let valueDesc = '';
        if (value) {
            valueDesc = ` with (${value})`;
        }
        let nameDesc = 'all animations';
        if (name) {
            nameDesc = `animation named by '${name}'`;
        }

        let abilityDesc = 'in all abilities';
        if (onlyCurrentAbility) {
            abilityDesc = 'in current ability';
        }

        LogUtil.info(`${_getLogTag()} ${funcName}${valueDesc} for ${nameDesc} ${abilityDesc}`);
    }

    function _isNameMatched(animation, nameTarget) {
        if (!nameTarget || animation?.name === nameTarget) {
            return true;
        }
        return false;
    }

    function _isAbilityMatched(animation, onlyCurrentAbility) {
        let context = getContext();
        if (!onlyCurrentAbility || animation?.getUiContext()?.getHostContext() === context) {
            return true;
        }

        return false;
    }

    function _getAnimationUiContext(animation) {
        /* 多abilities的支持需要依赖于在准确的context上启停Looper, 但displaysync无法完成这个使命.
         * 每次启动displaysync时, start均会将displaysync挂载到当前执行上下文的管线中, 这会导致可能挂错.
         * 为此引入frameCallback, 它能够支持向特定的管线上post回调, 从而确保上下文正确.
         * 但frameCallback需要一个准确的uicontext, 当前并无接口支持.
         * 此处直接借助了animation所关联canvas节点的uiContext_, 这有点类似java中的反射, 属于不规范的做法.
         * FIXME:待后续有正式接口时需做下调整.
         * (引入frameCallback的另一个好处是可以降低负载, ui线程只在必要时才被唤醒)
         */
        return animation?.wrapper?.canvas?.uiContext_;
    }

    function _getAllLooperFromAnimations() {
        let allLooper = new Map();
        let len = registeredAnimations?.length;
        for (let i = len - 1; i >= 0; i--) {
            let context = _getAnimationUiContext(registeredAnimations[i]?.animation)?.getHostContext();
            if (context) {
                let looper = _contextLoopers.get(context);
                if (looper) {
                    allLooper.set(looper, looper);
                }
            }
        }

        return allLooper;
    }

    function _getLooperFromAnimation(animation) {
        let uiContext = _getAnimationUiContext(animation);
        if (!uiContext) {
            LogUtil.warn(`${_getLogTag()} could NOT get current uiContext. no looper created.`);
            return null;
        }

        return _getOrCreateLooper(uiContext);
    }

    function _getOrCreateLooper(uiContext) {
        let looper = _contextLoopers.get(uiContext);
        if (!!looper) {
            return looper;
        }

        looper = new Looper(uiContext, registeredAnimations, resume, true);
        _contextLoopers.set(uiContext, looper);
        return looper;
    }

    function _disposeContext(uiContext) {
        const looper = _contextLoopers.get(uiContext);
        if (looper) {
            _contextLoopers.delete(uiContext); // 从 WeakMap 移除
        }
    }

    // web only
    function registerAnimation(element, animationData) {
        if (!element) {
            return null;
        }

        let len = registeredAnimations?.length
        for (let i = 0; i < len; i++) {
            if (registeredAnimations[i]?.elem !== null && registeredAnimations[i]?.elem === element) {
                return registeredAnimations[i]?.animation;
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
        let len = registeredAnimations?.length;
        for (let i = 0; i < len; i += 1) {
            animations.push(registeredAnimations[i]?.animation);
        }
        return animations;
    }

    function onAnimationItemLoaded(animItem) {
        if (!!animItem.getUiContext()) {
            LogUtil.info(`${animItem._getLogTag()} created with ${animItem.frameRate} fps.`);
        } else {
            LogUtil.warn(`${animItem._getLogTag()} created with ${animItem.frameRate} fps. no UIContext.`);
        }
    }

    function onAnimationItemDestroy(ev) {
        let animItem = ev.target;
        let len = registeredAnimations?.length
        for (let i = len - 1; i >= 0; i--) {
            if (registeredAnimations[i]?.animation === animItem) {
                registeredAnimations[i].animation = null;
                registeredAnimations.splice(i, 1);
                let uiContext = _getAnimationUiContext(animItem);
                _disposeContext(uiContext);
                _coordinator.unbindContext2dFromCoordinator(animItem?.wrapper);
                LogUtil.info(`${animItem._getLogTag()} destroyed with ${animItem.frameRate} fps`);
            }
        }
    }

    function onAnimationItemActive(animItem) {
        if (!!animItem?.getUiContext()) {
            LogUtil.info(`${animItem?._getLogTag()} activated with ${animItem?.getFrameRate()} fps.`);
        } else {
            LogUtil.warn(`${animItem?._getLogTag()} activated with ${animItem?.getFrameRate()} fps. no UiContext.`);
        }

        _getLooperFromAnimation(animItem)?.onAnimationActive(animItem);
    }

    function onAnimationItemIdle(animItem) {
        if (!!animItem?.getUiContext()) {
            LogUtil.info(`${animItem?._getLogTag()} deactivated with ${animItem?.getFrameRate()} fps`);
        } else {
            LogUtil.warn(`${animItem?._getLogTag()} deactivated with ${animItem?.getFrameRate()} fps. no UiContext.`);
        }

        _getLooperFromAnimation(animItem)?.onAnimationIdle(animItem);
    }

    function _destroyAnimationWithSameContext2d(context2d) {
        let len = registeredAnimations?.length;
        for (let i = len - 1; i >= 0; i--) {
            let animation = registeredAnimations[i]?.animation;
            if (animation?.wrapper === context2d) {
                LogUtil.warn(`${_getLogTag()} destroy animation '${animation.name}(${animation?.animationID})' from ${animation?.source},
          because animation using the same context2D. `);
                registeredAnimations.splice(i, 1);
                animation?.destroy();
            }
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
        LogUtil.info(`${_getLogTag()} load animation named '${params.name ? params.name : ''}'` +
            `${params.uri ? ' from ' + params.uri : (params.path ? ' from ' + params.path : '')}` +
            `, canvas uniqueId is: ${params.container?.canvas?.getUniqueId()}`);
        LogUtil.version();
        let context2d = params.wrapper || params.container;
        if (!context2d) {
            LogUtil.warn(`${_getLogTag()} loadAnimation failed because no container`);
            return null;
        }

        _destroyAnimationWithSameContext2d(context2d);
        let animItem = new AnimationItem();
        if (!_coordinator.isContext2dBoundToCoordinator(context2d)) {
            /* 执行 loadAnimation 时还未将 context2d 绑定到 coordinator 上, 即用户尚未显式调用bindContext2dToCoordinator
             * 说明用户还处在旧的处理逻辑中, 需要帮用户做一次调用
             * 出于兼容性考虑, 此时需保持 preferredNoArea 为 false, 即默认 canvas 有可见面积
             */
            _coordinator.internalBindContext2dToCoordinator(context2d, false);
        }
        _coordinator.attachAnimationToContext2d(context2d, animItem);

        setupAnimation(animItem, null);
        animItem.setParams(params);
        return animItem;
    }

    function setSpeed(val, animationName, onlyCurrentAbility) {
        _logFunc('setSpeed', animationName, onlyCurrentAbility, val);

        let len = registeredAnimations.length;
        for (let i = 0; i < len; i += 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                registeredAnimations[i]?.animation.setSpeed(val);
            }
        }
    }

    function setDirection(val, animationName, onlyCurrentAbility) {
        _logFunc('setDirection', animationName, onlyCurrentAbility, val);

        let len = registeredAnimations.length;
        for (let i = 0; i < len; i += 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                registeredAnimations[i]?.animation.setDirection(val);
            }
        }
    }

    function play(animationName, onlyCurrentAbility) {
        _logFunc('play', animationName, onlyCurrentAbility);

        let len = registeredAnimations.length;
        for (let i = 0; i < len; i += 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                registeredAnimations[i]?.animation.play();
            }
        }
    }

    function resume(uiContext, timestamp, displaySynced) {
        let len = registeredAnimations.length;

        for (let i = 0; i < len; i += 1) {
            registeredAnimations[i]?.animation.resume(timestamp, displaySynced);
        }
    }

    function pause(animationName, onlyCurrentAbility) {
        _logFunc('pause', animationName, onlyCurrentAbility);

        let len = registeredAnimations.length;
        for (let i = 0; i < len; i += 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                registeredAnimations[i]?.animation.pause();
            }
        }
    }

    function goToAndStop(value, isFrame, animationName, onlyCurrentAbility) {
        _logFunc('goToAndStop', animationName, onlyCurrentAbility, `${value},${isFrame}`);

        let len = registeredAnimations.length;
        for (let i = 0; i < len; i += 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                registeredAnimations[i]?.animation.goToAndStop(value, isFrame);
            }
        }
    }

    function goToAndPlay(value, isFrame, animationName, onlyCurrentAbility) {
        _logFunc('goToAndPlay', animationName, onlyCurrentAbility, `${value},${isFrame}`);

        let len = registeredAnimations.length;
        for (let i = 0; i < len; i += 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                registeredAnimations[i]?.animation.goToAndPlay(value, isFrame);
            }
        }
    }

    function stop(animationName, onlyCurrentAbility) {
        _logFunc('stop', animationName, onlyCurrentAbility);

        let len = registeredAnimations.length;
        for (let i = 0; i < len; i += 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                registeredAnimations[i]?.animation.stop();
            }
        }
    }

    function togglePause(animationName, onlyCurrentAbility) {
        _logFunc('togglePause', animationName, onlyCurrentAbility);

        let len = registeredAnimations.length;
        for (let i = 0; i < len; i += 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                registeredAnimations[i]?.animation.togglePause();
            }
        }
    }

    /**
     * 设置packageName
     * @param name 应用的包名
     */
    function setPackageName(name) {
        LogUtil.info(`${_getLogTag()} setPackageName: ${name}`);
        _packageName = name;
    }

    /**
     * 设置所有动画的播放帧率
     * @param frameRate 帧率
     */
    function setFrameRate(frameRate) {
        LogUtil.info(`${_getLogTag()} setFrameRate: ${frameRate}`);
        _userPlayingFrameRate = frameRate;

        _getAllLooperFromAnimations()?.forEach((looper) => {
            looper.changeFrameRateIfNeeded();
        });
    }

    /**
     * 获取当前所有动画的播放帧率
     * @returns 帧率
     */
    function getFrameRate() {
        return _userPlayingFrameRate;
    }

    function destroy(animationName, onlyCurrentAbility) {
        _logFunc('destroy', animationName, onlyCurrentAbility);
        LogUtil.version();

        let len = registeredAnimations.length;
        for (let i = (len - 1); i >= 0; i -= 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                // 找到即将要被destroy的动画，销毁之。会触发回调，在回调中进行状态清理
                registeredAnimations[i]?.animation.destroy();
            }
        }
        if (registeredAnimations.length === 0) {
            bez.clearCache();
        }
    }

    // html only
    function searchAnimations(animationData, standalone, renderer) {
        if (!document) {
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

    function setContentMode(contentMode, animationName, onlyCurrentAbility) {
        _logFunc('setContentMode', animationName, onlyCurrentAbility, contentMode);

        let len = registeredAnimations.length
        for (let i = 0; i < len; i += 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                registeredAnimations[i]?.animation.setContentMode(contentMode);
            }
        }
    }

    function resize(width, height, animationName, onlyCurrentAbility) {
        _logFunc('resize', animationName, onlyCurrentAbility, `${width} x ${height}`);

        let len = registeredAnimations.length
        for (let i = 0; i < len; i += 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                registeredAnimations[i]?.animation.resize(width, height);
            }
        }
    }

    function freeze(animationName, onlyCurrentAbility) {
        _logFunc('freeze', animationName, onlyCurrentAbility);

        let len = registeredAnimations.length;
        for (let i = 0; i < len; i += 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                registeredAnimations[i].animation.pause();
            }
        }
    }

    function unfreeze(animationName, onlyCurrentAbility) {
        _logFunc('unfreeze', animationName, onlyCurrentAbility);

        let len = registeredAnimations.length;
        for (let i = 0; i < len; i += 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                registeredAnimations[i].animation.play();
            }
        }
    }

    function setVolume(val, animationName, onlyCurrentAbility) {
        _logFunc('setVolume', animationName, onlyCurrentAbility, val);

        let len = registeredAnimations.length
        for (let i = 0; i < len; i += 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                registeredAnimations[i]?.animation.setVolume(val);
            }
        }
    }

    function mute(animationName, onlyCurrentAbility) {
        _logFunc('mute', animationName, onlyCurrentAbility);

        let len = registeredAnimations.length
        for (let i = 0; i < len; i += 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                registeredAnimations[i]?.animation.mute();
            }
        }
    }

    function unmute(animationName, onlyCurrentAbility) {
        _logFunc('unmute', animationName, onlyCurrentAbility);

        let len = registeredAnimations.length
        for (let i = 0; i < len; i += 1) {
            if (_isNameMatched(registeredAnimations[i]?.animation, animationName) &&
            _isAbilityMatched(registeredAnimations[i]?.animation, onlyCurrentAbility)) {
                registeredAnimations[i]?.animation.unmute();
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
        if (!context) {
            return;
        }

        // 处理HTTP资源路径
        if (path.startsWith('http')) {
            let pathSegments = path.split('/');
            let parentDirName = pathSegments[pathSegments.length - 2]; // 父级目录名
            let originalFileName = pathSegments[pathSegments.length - 1]; // 原始文件名（含扩展名）
            let cleanFileName = originalFileName.replace(/\.(?:zip|json)$/i, ''); // 清理后文件名（去除扩展名）

            let lottieBaseDir = `${context.filesDir}/lottie/${parentDirName}`; // 基础存储目录
            let targetDirectory = `${lottieBaseDir}/${cleanFileName}`; // 目标目录

            // 执行目录清理
            rmdir(targetDirectory, isSync);
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
        let filenames = listFileSyncs(path);
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
    moduleOb.getFrameRate = getFrameRate;
    moduleOb.bindContext2dToCoordinator = _coordinator.bindContext2dToCoordinator.bind(_coordinator);
    moduleOb.unbindContext2dFromCoordinator = _coordinator.unbindContext2dFromCoordinator.bind(_coordinator);
    moduleOb.setAttachedCanvasHasVisibleArea = _coordinator.setAttachedCanvasHasVisibleArea.bind(_coordinator);

    return moduleOb;
}());

export default animationManager;
