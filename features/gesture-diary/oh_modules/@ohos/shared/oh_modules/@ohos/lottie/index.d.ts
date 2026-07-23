/**
 * The MIT License (MIT)
 *
 * Copyright (c) 2015 Bodymovin
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
import common from '@ohos.app.ability.common';
import { image } from '@kit.ImageKit';
import { AsyncCallback } from '@kit.BasicServicesKit';

/**
 * 动画运行方向
 * @since 8
 * @design
 */
export type AnimationDirection = 1 | -1;

/**
 * 动画片段声明
 * @since 8
 * @design
 */
export type AnimationSegment = [number, number];

/**
 * 动画事件类型
 * @since 8
 * @design
 */
export type AnimationEventName = 'drawnFrame' | 'enterFrame' | 'loopComplete' | 'complete' | 'segmentStart' | 'destroy' | 'config_ready' | 'data_ready' | 'DOMLoaded' | 'error' | 'data_failed' | 'loaded_images';
/**
 * 动画事件回调函数声明
 * @since 8
 * @design
 */
export type AnimationEventCallback<T = any> = (args: T) => void;


/** Specifies the data for each event type. */
export interface AnimationEvents {
    DOMLoaded: undefined;
    complete: BMCompleteEvent;
    config_ready: undefined;
    data_failed: undefined;
    data_ready: undefined;
    destroy: BMDestroyEvent;
    drawnFrame: BMEnterFrameEvent;
    enterFrame: BMEnterFrameEvent;
    error: undefined;
    loaded_images: undefined;
    loopComplete: BMCompleteLoopEvent;
    segmentStart: BMSegmentStartEvent;
}

export interface BMCompleteEvent {
    direction: number;
    type: "complete";
}

export interface BMCompleteLoopEvent {
    currentLoop: number;
    direction: number;
    totalLoops: number;
    type: "loopComplete";
}

export interface BMDestroyEvent {
    type: "destroy";
}

export interface BMEnterFrameEvent {
    /** The current time in frames. */
    currentTime: number;
    direction: number;
    /** The total number of frames. */
    totalTime: number;
    type: "enterFrame";
}

export interface BMSegmentStartEvent {
    firstFrame: number;
    totalFrames: number;
    type: "segmentStart";
}

/**
 * 动画实例, Lottie.loadAnimation接口返回值
 * @since 8
 * @design
 */
export type AnimationItem = {
    /**
     * 动画所属的上下文
     * @since 13
     * @design
     */
    context: common.UIAbilityContext;

    /**
     * 动画名称
     * @since 8
     * @design
     */
    name: string;

    /**
     * 动画是否已加载
     * @since 8
     * @design
     */
    isLoaded: boolean;

    /**
     * 当前播放的帧号, 默认精度为>=0.0的浮点数, 调用setSubframe(false)后精度为去小数点后的正整数
     * @since 8
     * @design
     */
    currentFrame: number;

    /**
     * 当前播放帧数, 精度为>=0.0的浮点数
     * @since 8
     * @design
     */
    currentRawFrame: number;

    /**
     * 当前播放片段的第一帧帧号
     * @since 8
     * @design
     */
    firstFrame: number;

    /**
     * 当前播放片段的总帧数
     * @since 8
     * @design
     */
    totalFrames: number;

    /**
     * 帧率 (frame/s)
     * @since 8
     * @design
     */
    frameRate: number;

    /**
     * 帧率 (frame/ms)
     * @since 8
     * @design
     */
    frameMult: number;

    /**
     * 播放速率, 值为>=1的正整数
     * @since 8
     * @design
     */
    playSpeed: number;

    /**
     * 播放方向, 1为正放, -1为倒放
     * @since 8
     * @design
     */
    playDirection: number;

    /**
     * 动画完成播放的次数
     * @since 8
     * @design
     */
    playCount: number;

    /**
     * 当前动画是否已暂停, 值为true动画已暂停
     * @since 8
     * @design
     */
    isPaused: boolean;

    /**
     * 当前动画是否网络加载
     * @since 8
     * @design
     */
    isNetLoad: boolean;

    /**
     * 加载动画后是否自动播放, 若值为false需要再调用play()接口开始播放
     * @since 8
     * @design
     */
    autoplay: boolean;

    /**
     * 类型为boolean时是否循环播放, 类型为number时播放次数
     * @since 8
     * @design
     */
    loop: boolean | number;

    /**
     * 动画渲染对象, 根据渲染类型而定
     * @since 8
     * @design
     */
    renderer: any;

    /**
     * 动画ID
     * @since 8
     * @design
     */
    animationID: string;

    /**
     * 当前动画片段完成单次播放的帧数, 受AnimationSegment设置影响, 与totalFrames属性值相同
     * @since 8
     * @design
     */
    timeCompleted: number;

    /**
     * 当前动画片段序号, 值为>=0的正整数;
     * @since 8
     * @design
     */
    segmentPos: number;

    /**
     * 是否尽可能地更新动画帧率
     * @since 8
     * @design
     */
    isSubframeEnabled: boolean;

    /**
     * 当前动画待播放片段
     * @since 8
     * @design
     */
    segments: AnimationSegment | AnimationSegment[];

    /**
     * 播放动画
     * @param name 被指定的动画名, 缺省默认为空
     * @since 8
     * @design
     */
    play(name?: string): void;

    /**
     * 停止动画
     * @param name 被指定的动画名, 可缺省默认为空
     * @since 8
     * @design
     */
    stop(name?: string): void;

    /**
     * 播放或暂停动画
     * @param name 被指定的动画名, 可缺省默认为空
     * @since 8
     * @design
     */
    togglePause(name?: string): void;

    /**
     * 销毁动画
     * @param name 被指定的动画名, 可缺省默认为空
     * @since 8
     * @design
     */
    destroy(name?: string): void;

    /**
     * 暂停动画
     * @param name 被指定的动画名, 可缺省默认为空
     * @since 8
     * @design
     */
    pause(name?: string): void;

    /**
     * 控制动画画面停止在某一帧或某个时刻
     * @param value 帧号(值>=0)或时刻(ms)
     * @param isFrame true按帧控制, false按时间控制, 缺省默认false
     * @param name 被指定的动画名, 可缺省默认为空
     * @since 8
     * @design
     */
    goToAndStop(value: number, isFrame?: boolean, name?: string): void;

    /**
     * 控制动画画面从在某一帧或某个时刻开始播放
     * @param value 帧号(>=0)或时刻(ms)
     * @param isFrame true按帧控制, false按时间控制, 缺省默认false
     * @param name 被指定的动画名, 可缺省默认为空
     * @since 8
     * @design
     */
    goToAndPlay(value: number, isFrame?: boolean, name?: string): void;

    /**
     * 限定动画资源播放时的整体帧范围
     * @param init 起始帧号
     * @param end 结束帧号
     * @since 8
     * @design
     */
    setSegment(init: number, end: number): void;

    /**
     * 重置动画播放片段, 使动画重新从第一帧开始播放完整动画
     * @param forceFlag 值为true立刻生效, 值为false循环下次播放的时候生效
     * @since 8
     * @design
     */
    resetSegments(forceFlag: boolean): void;

    /**
     * 刷新动画布局
     * @since 8
     * @design
     */
    resize(width?: number, height?: number): void;

    /**
     * 设置播放速度
     * @param speed 值为浮点类型, speed>0正向播放, speed<0反向播放, speed=0暂停播放, speed=1.0/-1.0正常速度播放
     * @since 8
     * @design
     */
    setSpeed(speed: number): void;

    /**
     * 设置播放方向
     * @param direction 1为正向, -1为反向
     * @since 8
     * @design
     */
    setDirection(direction: AnimationDirection): void;

    /**
     * 设置仅播放指定范围的帧动画
     * @param segments 片段或片段数组; 若传入的是数组, 且当前loop!=0, 播放结束后, 仅循环播放最后一个片段
     * @param forceFlag 值为true立刻生效, 值为false循环下次播放的时候生效
     * @since 8
     * @design
     */
    playSegments(segments: AnimationSegment | AnimationSegment[], forceFlag?: boolean): void;

    /**
     * 设置是否尽可能地更新动画帧率
     * @param useSubFrames 默认值是true, 值为true时尽可能的更新动画帧率, 值为false时尊重原始AE fps
     * @since 8
     * @design
     */
    setSubframe(useSubFrames: boolean): void;

    /**
     * 获取动画单次完整播放的时间(与播放速度无关)或帧数, 与Lottie.loadAnimation接口入参initialSegment有关
     * @param inFrames 值为true时获取帧数, 值为false时获取时间(单位ms)
     * @since 8
     * @design
     */
    getDuration(inFrames?: boolean): number;

    /**
     * 直接触发指定事件的所有已设置的回调
     * @param name 事件名称, 有效范围见AnimationEventName声明
     * @param args 用户自定义回调参数
     * @since 8
     * @design
     */
    triggerEvent<T extends AnimationEventName>(name: T, args: AnimationEvents[T]): void;

    /**
     * 添加侦听事件, 事件完成后会触发指定回调函数
     * @param name 事件名称, 有效范围见AnimationEventName声明
     * @param AnimationEventCallback 用户自定义回调函数
     * @since 8
     * @design
     */
    addEventListener<T extends AnimationEventName>(name: T, callback: AnimationEventCallback<AnimationEvents[T]>): () => void;

    /**
     * 删除侦听事件
     * @param name 事件名称, 有效范围见AnimationEventName声明
     * @param AnimationEventCallback 用户自定义回调函数； 缺省为空时, 删除此事件的所有回调函数。
     * @since 8
     * @design
     */
    removeEventListener<T extends AnimationEventName>(name: T, callback?: AnimationEventCallback<AnimationEvents[T]>): void;

    /**
     * 修改动画颜色
     * @param color 颜色数组RGBA
     * @param layer 层次的下标值
     * @param index 对应层次里面的elements的下标值
     */
    changeColor(color: number[], layer?: number, index?: number): void;

    /**
     * 修改动画的关键帧颜色
     * @param startColor 开始颜色数组RGBA
     * @param endColor 结束颜色数组RGBA
     * @param layer 层次的下标值
     * @param index 对应层次里面的elements的下标值
     */
    changeColor(startColor: number[],endColor: number[], layer?: number, index?: number): void;

    /**
     * 动画填充模式，默认的填充模式是：Contain
     * @param contentMode 模式：'Fill','Top','Bottom','Cover','Contain'
     */
    setContentMode(contentMode: string): void;

    /**
     * 设置当前动画的播放帧率，范围1~120。
     * 可通过设置0帧率来取消该限制。
     * @param frameRate 播放帧率
     * @since 12
     */
    setFrameRate(frameRate: number): void;


};

export type AnimationConfig = {
    /**
     * 与canvas组件绑定的上下文CanvasRenderingContext2D, 提供最基础的绘制渲染能力
     * @since 8
     *
     * @design
     */
    container: CanvasRenderingContext2D;

    /**
     * 渲染类型, 目前支持canvas方式
     * @since 8
     * @design
     */
    renderer?: string;

    /**
     * 动画播放结束后, 是否循环播放，默认值true, 值为true时无限循环播放; 值类型为number, 且>=1时为设置重复播放的次数
     * @since 8
     * @design
     */
    loop?: boolean | number;

    /**
     * 自动播放设置
     * @since 8
     * @design
     */
    autoplay?: boolean;

    /**
     * 初始化动画资源播放时的整体帧范围
     * @since 8
     * @design
     */
    initialSegment?: AnimationSegment;

    /**
     * 动画名称, 动画成功加载后, 可在Lottie相关接口上, 应用该名称进行动画控制
     * @since 8
     * @design
     */
    name?: string;

    /**
     * 应用上下文 Context 在HSP场景下需要传正确的context，非HSP场景不影响，context可以不传
     * @since 8
     * @design
     */
    context?: common.UIAbilityContext;

    /**
     * 应用包名 用于打印日志区分不同模块调用启动aniamtor，packageName可以不传
     * @since 8
     * @design
     */
    packageName?: string;

    /**
     * 动画填充模式 支持填充模式：Fill, Top, Cover, Bottom, Contain  默认模式是：Contain
     * @since 8
     * @design
     */
    contentMode?: string;

    /**
     * 设置animator的刷帧率，范围1~120
     * @since 8
     * @design
     */
    frameRate?: number;

    /**
     * 读取来自网络路径的动画数据，支持json和zip格式
     * @since 8
     * @design
     */
    uri?: string;

    /**
     * true优先读取网络资源,false优先读取本地缓存资源
     * @since 8
     * @design
     */
    isNetwork?: boolean;

    /**
     * 读取指定路径下的图片资源
     * @since 8
     * @design
     */
    imagePath?: string;

    /**
     * 当动画不可见时，是否跳过绘制：设为true则跳过绘制，设为false则不跳过绘制(即无条件绘制)，默认值为true
     * @since 13
     * @design
     */
    autoSkip?: boolean;

    /**
     * 在加载图片时，调用此接口获取获取绘制的 PixelMap 对象
     */
    imageAssetDelegate?: (imagePath: string, callback: AsyncCallback<image.PixelMap>) => void;

    /**
     * 动画是否随系统设字体放大，设为false则不随系统字体放大，设为true则随系统字体放大，默认值为true
     * @since 13
     * @design
     */
    autoFontSize?: boolean;
};

/**
 * 动画文件配置信息, 推荐此方式
 * @since 8
 * @design
 */
export type AnimationConfigWithPath = AnimationConfig & {
    /**
     * 应用内的动画数据文件路径, 仅限json格式
     * path 路径仅支持entry/src/main/ets 路径下的相对路径，不支持跨包路径设置
     * @example path: 'common/lottie/data.json'
     * @since 8
     * @design
     */
    path?: string;
};

/**
 * 数据动画配置信息
 * @since 8
 * @design
 */
export type AnimationConfigWithData = AnimationConfig & {
    /**
     * json格式的动画数据, 仅限json格式
     * @since 8
     * @design
     */
    animationData?: any;
};

/**
 * LottiePlayer组件提供动画加载与控制播放能力
 * @since 8
 * @design
 */
export type LottiePlayer = {

    /**
     * 通过动画名称控制, 播放动画
     * @param name 被指定的动画名, 同loadAnimation接口参数name, 缺省时播放所有动画
     * @param onlyCurrentAbility 仅播放当前ability内的动画. 缺省时播放所有动画
     * @since 8
     * @design
     */
    play(name?: string, onlyCurrentAbility?: boolean): void;

    /**
     * 通过动画名称控制，暂停动画
     * @param name 被指定的动画名, 同loadAnimation接口入参name, 缺省时暂停所有动画
     * @param onlyCurrentAbility 仅暂停当前ability内的动画. 缺省时暂停所有动画
     * @since 8
     * @design
     */
    pause(name?: string, onlyCurrentAbility?: boolean): void;

    /**
     * 通过动画名称控制，停止动画
     * @param name 被指定的动画名, 同loadAnimation接口参数name, 缺省时停止所有动画
     * @param onlyCurrentAbility 仅停止当前ability内的动画. 缺省时停止所有动画
     * @since 8
     * @design
     */
    stop(name?: string, onlyCurrentAbility?: boolean): void;

    /**
     * 通过动画名称控制，设置播放速度
     * @param speed 值为浮点类型, speed>0正向播放, speed<0反向播放, speed=0暂停播放, speed=1.0/-1.0正常速度播放
     * @param name 被指定的动画名, 同loadAnimation接口参数name, 缺省时设置所有动画速度
     * @param onlyCurrentAbility 仅设置当前ability内的动画. 缺省时设置所有动画速度
     * @since 8
     * @design
     */
    setSpeed(speed: number, name?: string, onlyCurrentAbility?: boolean): void;

    /**
     * 通过动画名称控制，设置播放方向
     * @param direction 1为正向, -1为反向; 当设置为反向时, 从当前播放进度开始回播直到首帧, loop值为true时可无限倒放, speed<0叠加时也是倒放
     * @param name 被指定的动画名, 同loadAnimation接口参数name, 缺省时设置所有动画方向
     * @param onlyCurrentAbility 仅设置当前ability内的动画. 缺省时设置所有动画方向
     * @since 8
     * @design
     */
    setDirection(direction: AnimationDirection, name?: string, onlyCurrentAbility?: boolean): void;

    /**
     * 通过动画名称控制，暂停或播放动画
     * @param name 被指定的动画名, 同loadAnimation接口参数name, 缺省时停止所有动画
     * @param onlyCurrentAbility 仅停止当前ability内的动画. 缺省时停止所有动画
     * @since 8
     * @design
     */
    togglePause(name?: string, onlyCurrentAbility?: boolean): void

    /**
     * 加载动画, 须在组件完成布局后调用, 如可在点击事件回调中及Canvas组件的onReady()生命周期回调内调用;
     * 页面退出时, 须与destory()配对使用;
     * 目前支持canvas渲染方式, 支持传入json动画资源路径或json格式动画数据;
     * 声明式范式下可配合组件生命周期onPageShow()使用, web范式下可配合生命周期onShow()使用;
     * @param params 详见AnimationConfigWithPath或AnimationConfigWithData的声明
     * @return AnimationItem 动画对象, 可控制动画播放。
     * @since 9
     * @design
     */
    loadAnimation(params: AnimationConfigWithPath | AnimationConfigWithData): AnimationItem;

    /**
     * 通过动画名称控制, 销毁动画; 声明式范式下可配合组件生命周期onDisappear()与onPageHide()使用, web范式下可配合配合生命周期onHide()使用
     * @param name 被指定的动画名, 同loadAnimation接口参数name, 缺省时销毁所有动画
     * @param onlyCurrentAbility 仅销毁当前ability内的动画. 缺省时销毁所有动画
     * @since 8
     * @design
     */
    destroy(name?: string, onlyCurrentAbility?: boolean): void;

    /**
     * 设置所有动画的播放帧率，范围1~120。
     * 该设置具备持久性，即不论对于已加载还是新加载的动画都生效。可通过设置0帧率来取消该限制。
     * @param frameRate 播放帧率
     * @since 12
     */
    setFrameRate(frameRate: number): void;

    /**
     * 异步清除缓存
     * @param url 具体动画被清除缓存的地址
     * @param container 与canvas组件绑定的上下文CanvasRenderingContext2D,用于本地资源路径json文件
     * @design
     */
    clearFileCache(url?: string, container?: CanvasRenderingContext2D): void;

    /**
     * 同步清除缓存
     * @param url 具体动画被清除缓存的地址
     * @param container 与canvas组件绑定的上下文CanvasRenderingContext2D,用于本地资源路径json文件
     * @design
     */
    clearFileCacheSync(url?: string, container?: CanvasRenderingContext2D): void;

    /**
     * 把CanvasRenderingContext2D绑定到用来跟踪生命周期变化的协调器coordinator上.
     *
     * 借助coordinator, 可跟踪"lottie动画", "CanvasRenderingContext2D"以及"Canvas"三者之间的动态关联关系,
     * coordinator伺机通知"lottie动画"是否跳过绘制，以达到有效控制冗余绘制的目的.
     *
     * 当coordinator跟踪节点变化时, 可能各相关节点已完成其各自的生命周期活动, 因此会存在coordinator未知状态的情形. 比如:
     *   某个canvas曾经关联了其它context2d对象, 并处于可见状态, 其可见性回调已经发生过.
     *   现在canvas要attached到本context2d对象上来, 由于canvas可见性状态并未改变, 因此canvas的可见性回调也并不会再发生.
     *   尽管coordinator会获取当前节点的visibility以及attached的状态，但即便两个状态均为true也并不意味着canvas节点具备可见面积.
     * 为了避免这种情况发生, 需要调用者在所有与动画相关的canvas节点被创建之前，把该canvas所关联的CanvasRenderingContext2D对象绑定给coordinator,
     * 以便coordinator有能力跟踪到相关canvas节点的准确状态.
     *
     * 该接口建议在CanvasRenderingContext2D对象刚刚创建之时进行调用, 以做到第一时间感知其生命周期.
     *
     * @param context2d 待绑定给coordinator的CanvasRenderingContext2D对象
     */
    bindContext2dToCoordinator(context2d: CanvasRenderingContext2D): void;

    /**
     * 从coordinator中把CanvasRenderingContext2D剔除, 不再监听相关节点的生命周期.
     *
     * 需要注意的是, 该接口一旦调用, coordinator将不再跟踪相关节点的状态变化.
     * 因此通常应该在所有相关的"lottie动画", "CanvasRenderingContext2D"以及"Canvas"均销毁后才可调用.
     *
     * @param context2d 待从coordinator中剔除的CanvasRenderingContext2D对象
     */
    unbindContext2dFromCoordinator(context2d: CanvasRenderingContext2D): void;

    /**
     * 对 CanvasRenderingContext2D 所绑定的canvas节点可见性进行修正.
     *
     * coordinator会认为新绑定的canvas节点初始并无可见面积, 等待可见性回调发生时再做判断, 从而有效避免冗余绘制.
     * 但是当canvas节点在绑定context2d之前已经完成了可见性回调时, coordinator就无法正常处理.
     * 通常, 调用者可以在该canvas节点创建之前, 对其所(即将)关联的context2d做一次bindContextToCoordinator调用, 即可让coordinator正常感知.
     * 但为了处理可能的难以预知的复杂场景, 此处提供一个逃生接口, 给调用者显式调整canvas节点可见性的选择.
     *
     * 该接口仅建议在通过bindContextToCoordinator接口无法跟踪canvas节点可见性状态时才需要被使用.
     * 注意: 当context2d尚未绑定任何canvas时, 该接口不做任何处理.
     *
     * @param context2d 已经绑定给coordinator的CanvasRenderingContext2D对象
     * @param visible 与context2d所绑定的canvas节点可见性状态.
     */
    setAttachedCanvasHasVisibleArea(context2d: CanvasRenderingContext2D, visible?: boolean): void;

    /**
     * 获取当前存活的动画, 以数组形式返回.
     * @design
     */
    getRegisteredAnimations(): AnimationItem[];

    /**
     * 动画填充模式，默认的填充模式是：Contain
     * @param contentMode 模式：'Fill','Top','Bottom','Cover','Contain'
     * @param name 被指定的动画名, 同loadAnimation接口参数name, 缺省时设置所有动画
     * @param onlyCurrentAbility 仅设置当前ability内的动画. 缺省时设置所有动画
     */
    setContentMode(contentMode: string, name?: string, onlyCurrentAbility?: boolean): void;

    /**
     * 刷新动画布局
     * @param width 布局宽度
     * @param height 布局高度
     * @param name 被指定的动画名, 同loadAnimation接口参数name, 缺省时刷新所有动画
     * @param onlyCurrentAbility 仅刷新当前ability内的动画. 缺省时刷新所有动画
     * @design
     */
    resize(width: number, height: number, name?: string, onlyCurrentAbility?: boolean): void;

    /**
     * 控制动画画面停止在某一帧或某个时刻
     * @param value 帧号(值>=0)或时刻(ms)
     * @param isFrame true按帧控制, false按时间控制, 缺省默认false
     * @param name 被指定的动画名, 同loadAnimation接口参数name, 缺省时处理所有动画
     * @param onlyCurrentAbility 仅处理当前ability内的动画. 缺省时处理所有动画
     * @design
     */
    goToAndStop(value:number, isFrame:boolean, name?: string, onlyCurrentAbility?: boolean): void;

    /**
     * 控制动画画面从在某一帧或某个时刻开始播放
     * @param value 帧号(>=0)或时刻(ms)
     * @param isFrame true按帧控制, false按时间控制, 缺省默认false
     * @param name 被指定的动画名, 同loadAnimation接口参数name, 缺省时处理所有动画
     * @param onlyCurrentAbility 仅处理当前ability内的动画. 缺省时处理所有动画
     * @design
     */
    goToAndPlay(value:number, isFrame:boolean, name?: string, onlyCurrentAbility?: boolean): void;

    /**
     * 冻结动画
     * @param name 被指定的动画名, 同loadAnimation接口参数name, 缺省时冻结所有动画
     * @param onlyCurrentAbility 仅冻结当前ability内的动画. 缺省时冻结所有动画
     * TODO: 暂不放开
     */
    //freeze(name?: string, onlyCurrentAbility?: boolean): void;

    /**
     * 动画解冻
     * @param name 被指定的动画名, 同loadAnimation接口参数name, 缺省时解冻所有动画
     * @param onlyCurrentAbility 仅解冻当前ability内的动画. 缺省时解冻所有动画
     * TODO: 暂不放开
     */
    //unfreeze(name?: string, onlyCurrentAbility?: boolean): void;

    /**
     * 动画静音
     * @param name 被指定的动画名, 同loadAnimation接口参数name, 缺省时静音所有动画
     * @param onlyCurrentAbility 仅静音当前ability内的动画. 缺省时静音所有动画
     * TODO: 暂不放开
     */
    // mute(name?: string, onlyCurrentAbility?: boolean): void;

    /**
     * 动画放音
     * @param name 被指定的动画名, 同loadAnimation接口参数name, 缺省时放音所有动画
     * @param onlyCurrentAbility 仅放音当前ability内的动画. 缺省时放音所有动画
     * TODO: 暂不放开
     */
    // unmute(name?: string, onlyCurrentAbility?: boolean): void;

    /**
     * 设置动画音量
     * @param volume 动画音量
     * @param name 被指定的动画名, 同loadAnimation接口参数name, 缺省时设置所有动画
     * @param onlyCurrentAbility 仅设置当前ability内的动画. 缺省时设置所有动画
     * TODO: 暂不放开
     */
    // setVolume(volume: number, name?: string, onlyCurrentAbility?: boolean): void;
};

export { LogUtil } from './src/main/js/utils/LogUtil';

/**
 * Lottie 声明Lottie实例
 * @since 8
 * @design
 */
declare const Lottie: LottiePlayer;

/**
 * 默认仅导出Lottie示例对象
 * @since 8
 * @design
 */
export default Lottie;
