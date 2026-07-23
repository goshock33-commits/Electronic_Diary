# 工作日志

## 2026-07-22 全量替换图标 + Mimi 聊天气泡改用猫耳手绘气泡图

### 新增资源文件（base/media/）
| 文件 | 用途 |
|------|------|
| `icon_pomodoro.png` | 番茄钟图标（侧边栏） |
| `icon_todo.png` | 待办图标（侧边栏） |
| `icon_schedule.png` | 明日日程图标（侧边栏） |
| `icon_diary.png` | 日记本图标（底部菜单栏） |
| `icon_timeline.png` | 时光轴图标（底部菜单栏） |
| `icon_explore.png` | 时光探索图标（底部菜单栏） |
| `icon_profile.png` | 我的图标（底部菜单栏） |
| `icon_bubble.png` | AI 聊天气泡背景（猫耳+尾巴朝左） |
| `icon_bubble_user.png` | 用户聊天气泡背景（水平翻转，尾巴朝右） |

### 修改文件
1. **`entry/.../pages/HomePage.ets`**
   - menuItems 图标：`IconMapper.CLOCK/TAB_TODO/TAB_CALENDAR` → `$r('app.media.icon_*')` 自定义 PNG
   - 侧边栏菜单渲染：`SymbolGlyph` + 青色圆底 → `Image` 直接渲染（去圆底，图标 24vp）

2. **`entry/.../pages/MainPage.ets`**
   - `TAB_CONFIGS` 图标：4 个 `IconMapper.NAV_*` → `$r('app.media.icon_*')` 自定义 PNG（AI Tab 保留 Lottie）

3. **`shared/.../components/FloatingTabBar.ets`**
   - 新增 `tabKeyToImage()` 方法，映射 tab key → PNG 资源
   - 手机/平板 Tab 图标渲染：`SymbolGlyph` → `Image`（24vp，选中 opacity 1.0 / 未选中 0.5）

4. **`features/voice-diary/.../pages/AIChatView.ets`**
   - AI 气泡：`border + borderRadius` → `Image($r('app.media.icon_bubble'))` 猫耳气泡图背景（Stack 叠加 Text）
   - 用户气泡：同上但用翻转图 `icon_bubble_user.png`（尾巴朝右）
   - StreamingBubble：同步改用猫耳气泡图背景
   - 气泡宽高随文字自适应（`constraintSize maxWidth 74%`，Stack wrap content）
   - BusyIndicator 保持原 borderRadius 样式不变（加载指示非对话气泡）

---

## 2026-07-21 侧边栏展开动画替换为拉绳子序列动画

### 新增资源文件（rawfile/animations/）
| 文件 | 用途 |
|------|------|
| `拉绳子1.json` | 侧边栏拉绳子动画第一段 |
| `拉绳子2.json` | 侧边栏拉绳子动画第二段（第一段播完立即接） |

### 修改文件
1. **`shared/src/main/ets/components/LottieAnimation.ets`**
   - 新增 `onComplete` 回调属性（loop=false 时动画播完触发）
   - 添加 `complete` 事件监听器

2. **`entry/src/main/ets/pages/HomePage.ets`**
   - 新增 `@State ropeAnimPath` 控制当前播放的拉绳子动画路径
   - 侧边栏动画替换为 `拉绳子1.json`，onComplete 回调中切换到 `拉绳子2.json`
   - `openMenu()` 中重置 `ropeAnimPath` 为 `拉绳子1.json`（每次打开菜单从第一段开始）

---

## 2026-07-21 侧边栏展开动画 + 小猫探头动画：放大 + 透明底 + 上移

### 修改文件
1. **`entry/src/main/ets/pages/HomePage.ets`**
   - 侧边栏底部"展开"动画：80vp → 120vp → 160vp → **200vp**
   - 透明背景（移除白底 Stack 容器）
   - 底部间距 12 → 0 → 60（动画上移，避免被底部菜单栏遮挡）
   - 移除 opacity 0.6

2. **`shared/src/main/ets/components/EmptyStateView.ets`**
   - Lottie 动画：64vp → 96vp → 128vp → **160vp**
   - 透明背景（移除白底 Stack 容器）

---

## 2026-07-21 替换"保存时光"页面"今日心情"图标为 Lottie 动画

### 修改文件
1. **`features/diary/src/main/ets/pages/DiaryEditPage.ets`**
   - import 新增 `LottieAnimation`（从 `@ohos/shared`）
   - `MoodOption` 接口：`icon: Resource` → `animPath: string`
   - `aboutToAppear()` 中 moodOptions 赋值改用 Lottie 路径
   - build 中 `SymbolGlyph(opt.icon)` 替换为 `LottieAnimation({ animPath, ... })`，40vp 尺寸 + 选中态 opacity/scale 动画

### 新增资源文件（rawfile/animations/）
| 文件名 | 对应心情 | 说明 |
|--------|---------|------|
| `sunny.json` | 风和 (sunny) | 晴天 Lottie 动画 |
| `night.json` | 繁星 (star) | 夜晚/星空 Lottie 动画 |
| `happy.json` | 欢喜 (heart) | 开心 Lottie 动画 |
| `sunclouds.json` | 多云 (cloudy) | 多云 Lottie 动画 |
| `rain.json` | 微雨 (rainy) | 下雨 Lottie 动画 |

### 映射关系
- sunny (风和) → sunny.json
- star (繁星) → night.json
- heart (欢喜) → happy.json
- cloudy (多云) → sunclouds.json
- rainy (微雨) → rain.json

### 技术要点
- 使用项目已有的 `LottieAnimation` 组件（shared 模块），40vp 方形画布
- 选中态：opacity 1.0 + scale 1.15；未选中态：opacity 0.6 + scale 1.0
- 动画循环播放（loop: true），自动播放（autoPlay: true）
- 背景色、文字色等选中交互逻辑保持不变

---

## 2026-07-21 日记详情页心情图标同步替换为 Lottie 动画

### 修改文件
1. **`features/diary/src/main/ets/pages/DiaryDetailPage.ets`**
   - import 新增 `LottieAnimation`（从 `@ohos/shared`）
   - 新增 `moodAnimPathFor(mood)` 方法，返回 Lottie JSON 路径（替代原 `moodIconFor` 返回 Resource）
   - build 中 `SymbolGlyph(this.moodIconFor(...))` 替换为 `LottieAnimation({ animPath, ... })`，48vp 尺寸
   - 删除不再使用的 `moodColorFor()` 方法（原返回语义色，Lottie 自带颜色无需覆盖）
   - `MOOD_COLOR_*` 常量保留——仍被"开心的事"模块引用

---

## 2026-07-21 安全锁 PIN 验证改为仅冷启动触发

### 需求变更
原行为：每次应用从后台回前台都弹出 PIN 解锁页。
新行为：仅冷启动（进程首次启动）时触发 PIN 验证，后续后台回前台不再弹出。

### 修改文件
1. **`entry/src/main/ets/pages/MainPage.ets`**
   - `aboutToAppear()` 新增 `AppStorage.setOrCreate('lockFirstShowDone', 0)`（冷启动重置标志）
   - `onPageShow()` 安全锁检查新增 `firstShowDone !== 1` 条件
   - 触发锁屏时同步置 `lockFirstShowDone = 1`（消费后不再触发）
   - 更新注释

### 技术要点
- `lockFirstShowDone` 使用 AppStorage（进程级生命周期），杀进程自动归零 = 天然标记冷启动
- 不影响其他场景：设置页手动进入安全锁页 / PinSetupModal 设置流程 / SecurityLockAbility 独立入口
- SecurityLockPage 的 `lockEntryMode` 逻辑完全不变

---

## 2026-07-21 时光检索页心情图标同步替换为 Lottie 动画

### 修改文件
1. **`features/search/src/main/ets/pages/SearchPage.ets`**
   - import 新增 `LottieAnimation`（从 `@ohos/shared`）
   - `MoodOption` 接口：`icon: Resource` → `animPath: string`
   - `aboutToAppear()` 中 moodOptions 赋值改用 Lottie 路径
   - `getSelectedMoodIcon()` 重命名为 `getSelectedMoodAnimPath()`，返回 Lottie 路径
   - 心绪触发按钮：`SymbolGlyph` → `LottieAnimation`（20vp）
   - 心绪选项面板：`SymbolGlyph(mo.icon)` → `LottieAnimation({ animPath: mo.animPath })`（20vp）
   - 删除不再使用的 `getSelectedMoodColor()` 方法

---

## 2026-07-21 侧边栏底部展开动画 + 时光轴空态小猫探头动画

### 新增资源文件（rawfile/animations/）
| 文件 | 用途 |
|------|------|
| `展开.json` | 首页侧边栏底部装饰动画 |
| `小猫探头.json` | 时光轴"暂无备忘/日程"空态图标 |

### 修改文件
1. **`entry/.../pages/HomePage.ets`**
   - 侧边栏底部：`Blank()` + `LottieAnimation('animations/展开.json')`（80vp，播放一次，opacity 0.6）

2. **`shared/.../components/EmptyStateView.ets`**
   - 新增 `@Prop animPath: string`（可选，设置后渲染 Lottie 替代 SymbolGlyph）
   - import `LottieAnimation`
   - 64vp Lottie 尺寸，`loop: true`，向后兼容（无 animPath 时仍走 SymbolGlyph）

3. **`features/todo/.../components/TodoList.ets`**
   - 空态 `EmptyStateView` 新增 `animPath: 'animations/小猫探头.json'`
   - "暂无今日备忘"和"暂无明日日程"均显示小猫探头动画

### 变更
- 图标格式从 Lottie JSON 改为 JPG 静态图片（用户更新了图标文件）
- 删除旧 `.json` 文件，复制新 `.jpg` 文件到 `rawfile/animations/`

### 修改文件
1. **`features/search/src/main/ets/pages/SearchPage.ets`**
   - `CategoryOption` 接口：`animPath` → `imagePath`
   - categoryOptions 赋值改用 `.jpg` 路径
   - 选项面板：`LottieAnimation` → `Image($rawfile(co.imagePath))`（24vp，Contain + 圆角 4）
   - 新增 `getSelectedCategoryImagePath()` 辅助方法
   - 分类触发按钮：选中时显示对应分类图片，未选中时显示通用 TAG 图标

### 新增资源文件（rawfile/animations/）
| 文件名 | 对应分类 |
|--------|---------|
| `日常.json` | 日常 |
| `学习.json` | 学习 |
| `工作.json` | 工作 |
| `日记.json` | 日记 |
| `微信.json` | 微信 |
| `语音.json` | 语音 |

### 修改文件
1. **`features/search/src/main/ets/pages/SearchPage.ets`**
   - `CategoryOption` 接口：`icon: Resource` → `animPath: string`
   - `aboutToAppear()` 中 categoryOptions 改用 Lottie 路径（中文文件名直接引用）
   - 分类选项面板：`SymbolGlyph(co.icon)` → `LottieAnimation({ animPath: co.animPath })`（20vp）

---

## 2026-07-21 替换应用图标为 logo.png（去背景 + 透明居中）

### 处理过程
- logo.png 原始尺寸 2048x2048，RGB 不透明（检测到背景色 RGB [248,249,249] 近白色）
- 用 Pillow 去除背景色（阈值 30）→ RGBA 透明底
- 缩放至 1024x1024 画布居中放置（透明 padding）

### 替换文件
| 位置 | 说明 |
|------|------|
| `entry/.../media/foreground.png` | 自适应图标前景层（logo + 透明底） |
| `AppScope/.../media/foreground.png` | AppScope 级前景层 |
| `entry/.../media/background.png` | 自适应图标背景层 → 全透明 |
| `AppScope/.../media/background.png` | AppScope 级背景层 → 全透明 |
| `entry/.../media/startIcon.png` | 启动窗口图标（同 foreground） |
