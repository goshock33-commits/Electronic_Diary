// <!-- agentID: HUI-001 · P1-01 收敛 by HUI-053 · 光晕/书签清理 by HUI-072 -->
// fix: HUI-016
// fix: F5-v2 —— 用户审查后变更：撤 FloatingEntry 浮球挂载；保留 onPageShow 前台剪贴板检测 ClipboardDetector；任务提取入口整合进 AI 伙伴对话
// 页面：首页主容器（底部 5 Tab 悬浮导航 + 骨架屏渐进加载）
// 关联设计稿：UX-001_redesign_report.md §2.1（App 框架 / floating-tab-bar）
// 关联计划：PLN-003 P1-01（底部 6→5 Tab 收敛 + 去标题栏）；HUI-072（删青色 blur 光晕层 + 删 FloatingBookmark）
// 关联规范：PROJECT_SPEC §9 崩溃防范 / §1.4 模块名三者一致 / §10 图标本地库
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：遵守 T042 规范（accessibilityText 不为空、触控热区 >= 48x48vp）
// 适配：手机单列胶囊 / 平板竖向 MiniBar / 折叠屏跟随断点
// 状态管理：@StorageLink 主题 Token + AppStorage 全局状态
// 崩溃防范：@StorageLink tokens 读取全判空回退；TAB_CONFIGS 为模块级 const（非 struct 字段初值）

import type { ThemeColorTokens, TabItemConfig } from '@ohos/shared';
import { IconMapper, EventBus, reportPawTouch, PawOverlayLayer, PersistentState } from '@ohos/shared';
import { FloatingTabBar } from '@ohos/shared';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HomePage } from './HomePage';
import { CalendarPage } from './CalendarPage';
import { TimelineTodoView } from './TimelineTodoView';
import { SettingsPage } from './SettingsPage';
import { AIChatView } from 'features_voice_diary';
// fix: F5-v2 —— 用户审查：撤掉 FloatingEntry 浮球（任务提取整合进 AI 伙伴对话）；仅保留剪贴板检测器
import { ClipboardDetector } from 'features_task_extraction';
// 桌面相机卡片快速拍照悬浮球
import { CameraQuickBall } from '../components/CameraQuickBall';

const TAG: string = 'MainPage';

/**
 * 底部 5 Tab 配置（页面改版：首页/日记/Mimi/待办/我的）
 * 顺序：首页 / 日记 / Mimi / 待办 / 我的
 *   首页   → home (家庭消息流)
 *   日记   → diary (日记列表)
 *   Mimi   → ai (AI助手)
 *   待办   → todo (待办列表)
 *   我的   → profile (设置)
 */
const TAB_CONFIGS: TabItemConfig[] = [
  { key: 'home', icon: IconMapper.TAB_HOME, label: '首页' },
  { key: 'diary', icon: IconMapper.NAV_DIARY, label: '日记' },
  { key: 'ai', icon: IconMapper.AI_COMPANION, label: 'Mimi' },
  { key: 'todo', icon: IconMapper.TAB_TODO, label: '待办' },
  { key: 'profile', icon: IconMapper.NAV_PROFILE, label: '我的' }
];

@Entry
@Component
struct MainPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @StorageLink('app_font_scale') @Watch('onFontScaleChange') fontScale: number = 1;
  @State currentTab: string = 'home';
  @State currentTabIndex: number = 0;
  @State currentTitle: string = '首页';
  @State isLoaded: boolean = false;
  // fix: HUI-016 · T-D04 —— 换肤重建开关：THEME_CHANGED 时翻转，驱动 5 个 TabContent 子树整体重建。
  //   实证依据（hilog + 截图，见交付报告）：懒加载 TabContent 子树内的 @StorageLink 收不到任何
  //   后续 AppStorage 写入（含前台时的全新引用写入），但「新建子树的初读」始终正确——
  //   故集中修法采用"换肤即重建"，一处覆盖全部 tab；代价是换肤瞬间各 tab 页内临时 UI 状态复位（可接受，换肤为低频操作）。
  @State themeRebuildFlip: boolean = false;
  // 桌面相机卡片快速拍照：AppStorage 桥接 camera_quick_mode → 跳 QuickCameraPage
  @StorageLink('camera_quick_mode') cameraQuickMode: boolean = false;
  // 快速拍照悬浮球数据（照片 URI 数组，JSON 字符串）
  @StorageLink('camera_photos_json') cameraPhotosJson: string = '';
  // 悬浮球解析后的照片 URI 列表
  @State cameraPhotoUris: string[] = [];

  aboutToAppear(): void {
    // fix: MAIN-001 · 从 Form 卡片 router 跳转时指定 Tab（AppStorage 桥接）
    const targetTab: string | undefined = AppStorage.get<string>('navTargetTab');
    if (targetTab !== undefined && targetTab.length > 0) {
      this.currentTab = targetTab;
      AppStorage.setOrCreate<string>('navTargetTab', ''); // 消费即清
    }
    // 初始化 Tab 索引和标题
    this.syncTabState(this.currentTab);
    // fix: HUI-016 · T-D04 —— 订阅全局换肤事件（ThemeManager 每次换肤必发，架构 4.6；
    //   EventBus 多订阅已核实；MainPage 与应用同生命周期，不退订）
    EventBus.on(EventBus.EventNames.THEME_CHANGED, (data: Record<string, Object>) => {
      this.themeRebuildFlip = !this.themeRebuildFlip;
    });
    // 模拟首帧加载完成的渐进效果（后续接入 AppStartup 时替换为实际加载状态）
    setTimeout(() => {
      this.isLoaded = true;
    }, 300);
    // fix: F5 —— 剪贴板检测逻辑挂钩：实际触发在 onPageShow（覆盖首帧显示 + 应用回前台两条路径）
    // 冷启动：重置首屏标志，使 onPageShow 首次触发安全锁（AppStorage 进程级，杀进程自动归零）
    AppStorage.setOrCreate('lockFirstShowDone', 0);
    // 桌面相机卡片快速拍照：检测 camera_quick_mode → 跳 QuickCameraPage
    this.checkCameraQuickMode();
    // 解析悬浮球数据（冷启动恢复）
    this.parseCameraPhotosJson();
  }

  // fix: F5 —— 前台剪贴板任务检测：@Entry 页 onPageShow 在首帧显示与应用回前台时均触发；
  //   命中任务关键词 → ClipboardDetector 内部弹确认框 → 用户确认 → receiveFromClipboard（fire-and-forget，不阻塞页面）
  onPageShow(): void {
    // DEV：长辈模式重定向 —— persist_elder_mode=1 时整页替换为长辈模式页（冷启动首帧 + 回前台两条路径均覆盖）；
    //   ElderModePage onPageShow 有对称守卫（键归 0 时 replaceUrl 回本页），两侧均 replaceUrl 不压栈、无循环。
    const elderOn: number | undefined = AppStorage.get<number>(PersistentState.KEY_ELDER_MODE);
    if (elderOn === 1) {
      router.replaceUrl({ url: 'pages/ElderModePage' }).catch(() => {
      });
      return;
    }
    // 安全锁：仅冷启动首次进入触发（lockFirstShowDone=0 → 触发后置 1，回前台不再触发）
    const lockEnabled: boolean | undefined = AppStorage.get<boolean>('app_security_lock');
    const firstShowDone: number | undefined = AppStorage.get<number>('lockFirstShowDone');
    const lockEntryMode: number | undefined = AppStorage.get<number>('lockEntryMode');
    if (lockEnabled && firstShowDone !== 1 && lockEntryMode !== 2) {
      AppStorage.setOrCreate('lockFirstShowDone', 1);
      AppStorage.setOrCreate('lockEntryMode', 1);
      router.replaceUrl({ url: 'pages/SecurityLockPage' }).catch(() => {
      });
      return;
    }
    // 已解锁进入主页，清除入口标志
    if (lockEntryMode === 2) {
      AppStorage.setOrCreate('lockEntryMode', 0);
    }
    ClipboardDetector.checkOnForeground();
    // 桌面相机卡片快速拍照（热启动）
    this.checkCameraQuickMode();
    // 从 DiaryEditPage 返回后清除悬浮球（照片已传递给编辑页）
    const consumed: boolean | undefined = AppStorage.get<boolean>('camera_ball_consumed');
    if (consumed) {
      this.cameraPhotoUris = [];
      this.cameraPhotosJson = '';
      AppStorage.setOrCreate('camera_ball_consumed', false);
    }
    // 解析悬浮球数据（热启动恢复）
    this.parseCameraPhotosJson();
  }

  /** 字号缩放变更：翻转 themeRebuildFlip 驱动全部 TabContent 子树重建，使新字号全局生效 */
  onFontScaleChange(): void {
    this.themeRebuildFlip = !this.themeRebuildFlip;
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // 顶部标题栏已按原型移除（原型无标题栏）；顶部青色 blur 光晕层已删（HUI-069/072）
        // Tab 内容区（5 Tab：首页 / 日记 / Mimi / 待办 / 我的）
        Tabs({
          barPosition: BarPosition.End,
          index: this.currentTabIndex
        }) {
          // fix: HUI-016 · T-D04 —— 各 TabContent 以 themeRebuildFlip 双分支包裹：
          //   换肤时 if/else 分支切换 → 子树销毁重建 → 新建初读拿到当前色板（唯一实证可靠通道）
          TabContent() {
            if (this.themeRebuildFlip) {
              HomePage()
            } else {
              HomePage()
            }
          }
          .tabBar('') // tabBar 文字由 FloatingTabBar 自定义渲染，此处为空占位

          TabContent() {
            if (this.themeRebuildFlip) {
              CalendarPage()
            } else {
              CalendarPage()
            }
          }
          .tabBar('')

          TabContent() {
            if (this.themeRebuildFlip) {
              AIChatView()
            } else {
              AIChatView()
            }
          }
          .tabBar('')

          TabContent() {
            if (this.themeRebuildFlip) {
              TimelineTodoView()
            } else {
              TimelineTodoView()
            }
          }
          .tabBar('')

          TabContent() {
            if (this.themeRebuildFlip) {
              SettingsPage()
            } else {
              SettingsPage()
            }
          }
          .tabBar('')
        }
        .barMode(BarMode.Fixed)
        .barHeight(0) // 隐藏系统 tab bar，由自定义 FloatingTabBar 替代
        .scrollable(false) // 禁止滑动切换
        .onChange((index: number) => {
          this.onTabIndexChange(index);
        })
        .layoutWeight(1)
        .animation({
          duration: 250,
          curve: Curve.EaseInOut,
          iterations: 1
        })

        // 自定义悬浮导航胶囊
        FloatingTabBar({
          tabs: TAB_CONFIGS,
          activeKey: this.currentTab,
          selectedTabIndex: this.currentTabIndex, // HUI-078：传入当前选中索引，供 AI 页浮球收缩判定
          layoutDirection: 'mobile', // 默认手机模式，后续集成断点系统后动态切换
          onTabChange: (key: string) => {
            this.currentTab = key;
            this.syncTabState(key);
          }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.tokens ? this.tokens.bg : '#F5F5F5')

      // HUI-069：删除顶部 blur 光晕层（原 UX-001 §2.1/§1.6 青色渐变）
      // HUI-069：删除 FloatingBookmark 悬浮书签

      // 桌面相机卡片快速拍照悬浮球（照片拍完后显示，点击跳日记编辑）
      if (this.cameraPhotoUris.length > 0) {
        CameraQuickBall({
          photoUris: this.cameraPhotoUris,
          onClose: () => {
            this.cameraPhotoUris = [];
            AppStorage.setOrCreate('camera_photos_json', '');
          }
        })
      }

      // HUI-001: 猫爪视觉层（同树最上层子节点，整层 None 不参与命中，不挡交互）
      // PawOverlayLayer()

      // fix: F5-v2 —— FloatingEntry 浮球已按用户审查意见移除（任务提取整合进 AI 伙伴对话，见 AIChatView）
    }
    .width('100%')
    .height('100%')
    // HUI-001: 猫爪特效触摸捕获（页面树内监听 Down，不消费；视觉层在本页根 Stack 顶层）
    .onTouch((event: TouchEvent) => reportPawTouch(event))
  }

  /**
   * 同步 Tab 状态（索引+标题）
   */
  private syncTabState(key: string): void {
    const idx = TAB_CONFIGS.findIndex((t: TabItemConfig) => t.key === key);
    this.currentTabIndex = idx >= 0 ? idx : 0;
    const titles: Record<string, string> = {
      'home': '首页',
      'diary': '日记',
      'ai': 'Mimi',
      'todo': '待办',
      'profile': '我的'
    };
    this.currentTitle = titles[key] || '首页';
  }

  /**
   * Tab 索引变化回调
   */
  private onTabIndexChange(index: number): void {
    if (index >= 0 && index < TAB_CONFIGS.length) {
      const key: string = TAB_CONFIGS[index].key;
      this.currentTab = key;
      this.currentTabIndex = index;
      this.syncTabState(key);
    }
  }

  /**
   * 桌面相机卡片快速拍照：检测 camera_quick_mode → 跳 QuickCameraPage
   * 由 EntryAbility 设置 AppStorage('camera_quick_mode') = true 后触发
   */
  private checkCameraQuickMode(): void {
    if (this.cameraQuickMode) {
      this.cameraQuickMode = false; // 消费即清
      router.pushUrl({ url: 'pages/QuickCameraPage' }).catch((err: Error) => {
        hilog.error(0x0000, TAG, 'pushUrl QuickCameraPage failed: %{public}s', err.message);
      });
    }
  }

  /**
   * 解析悬浮球照片数据（AppStorage JSON 字符串 → string[]）
   */
  private parseCameraPhotosJson(): void {
    const json: string = this.cameraPhotosJson;
    if (json.length === 0) {
      this.cameraPhotoUris = [];
      return;
    }
    try {
      const parsed: string[] = JSON.parse(json) as string[];
      if (Array.isArray(parsed) && parsed.length > 0) {
        this.cameraPhotoUris = parsed;
      }
    } catch (_e) {
      this.cameraPhotoUris = [];
    }
  }
}
