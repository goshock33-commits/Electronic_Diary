# HUI-048 T-W01 卡片数据源验证 · 2026-07-18

## 编译结果
hvigor BUILD SUCCESSFUL (53s, 0 errors, 0 new warnings)
All pre-existing deprecation warnings remain (not introduced by this change).

## 修改文件清单

| 文件 | 变更 |
|------|------|
| `entry/src/main/ets/formextensions/CheckInFormAbility.ets` | +60s 周期刷新定时器, +onFormEvent, +formIds 跟踪, +onDestroy 清理。DB 查询已有 DEV-003 |
| `entry/src/main/ets/formextensions/TodoFormAbility.ets` | 重写: onAddForm/onUpdateForm/onFormEvent 接入 TodoDao.queryByDateAndType(today,'today') 真实数据; 60s 刷新 |
| `entry/src/main/ets/formextensions/QuoteFormAbility.ets` | 重写: onAddForm/onUpdateForm 接入 QuoteDao.count()+getByOffset(日期偏移) 确定性每日选取; 60s 刷新 |
| `entry/src/main/ets/formextensions/PomodoroFormAbility.ets` | 重写: onAddForm/onUpdateForm 接入 PomodoroDao.queryByDateRange(today,today); 活跃会话检测→1s 快定时器; 无活跃→60s 慢定时器; 本地缓存 endTime 避免每秒查 DB |

FormPage 文件（4个）未修改。

## 数据源映射

### 打卡卡 CheckInFormAbility → CheckInFormPage
| FormPage Key | 数据来源 | 类型 |
|-------------|---------|------|
| `isChecked` | `CheckInDao.exists(DateUtils.today())` | number (0/1) |
| `streak` | `CheckInDao.queryStreak(DateUtils.today())` | number |
| `monthRate` | `CheckInDao.queryByMonth()` → 当月打卡天数/当月总天数*100 | number |
| `dateStr` | `DateUtils.today()` | string |
| `progressText` | `checkedDays + '/' + totalDays + ' ' + monthRate + '%'` | string |

### 待办卡 TodoFormAbility → TodoFormPage
| FormPage Key | 数据来源 | 类型 |
|-------------|---------|------|
| `dateStr` | `DateUtils.today()` | string |
| `totalCount` | `todos.length` (今日待办总数) | number |
| `completedCount` | 统计 completed===1 的条目数 | number |
| `todos` | `JSON.stringify(items[])` — 每项 {id, title, isCompleted: completed, type} | string |

### 名言卡 QuoteFormAbility → QuoteFormPage
| FormPage Key | 数据来源 | 类型 |
|-------------|---------|------|
| `quoteText` | `QuoteDao.getByOffset(dayOfYear % totalCount).content` | string |
| `quoteAuthor` | `'—— ' + quote.author` (作者空→'佚名') | string |
| `dateStr` | `DateUtils.today()` | string |

### 番茄卡 PomodoroFormAbility → PomodoroFormPage
| FormPage Key | 数据来源 | 类型 |
|-------------|---------|------|
| `state` | 活跃会话 preset_type, 否则 'idle' | string |
| `remainingStr` | 活跃会话: 剩余 MM:SS; 否则 '25:00' | string |
| `progress` | 活跃会话: elapsed/total*100; 否则 0 | number |
| `preset` | 活跃会话 preset_type; 否则 'focus' | string |
| `totalStr` | 活跃会话: 总时长 MM:SS; 否则 '25:00' | string |

## 用户验证步骤

### 前置条件
- DevEco Studio 已连接真机或模拟器
- 应用已安装（编译产物: `entry/build/default/outputs/default/entry-default-signed.hap`）
- 主 App 中已有一些数据（至少有一两条待办）以便看到真实数据

### 验证步骤
1. **安装应用**: `hdc install entry/build/default/outputs/default/entry-default-signed.hap`
2. **长按桌面** → **添加卡片** (服务卡片)
3. **选择打卡卡 (CheckInForm)**: 应显示今日打卡状态（已打卡/未打卡）、连续天数、当月进度环。初始瞬间可能显示占位值 (streak=0)，1-2秒内异步刷新为真实数据。
4. **选择待办卡 (TodoForm)**: 应显示今日待办列表（多条则显示前3条）、完成数/总数统计。DB 无待办时显示空列表不白屏。
5. **选择名言卡 (QuoteForm)**: 应显示一句中文名言+作者。首次安装 DB 中有 120 条内置名言，按日期确定性选取（同日同句）。
6. **选择番茄卡 (PomodoroForm)**: 应显示 "待开始 25:00" idle 状态。如果主 App 中有正在计时的番茄钟会话，卡片会每秒实时更新倒计时。

### 手动触发刷新
- 系统每 60 秒自动刷新（番茄卡活跃时 1 秒刷新）
- 系统定时刷新时间（form_checkin.json 10:30, form_quote.json 00:01 等）触发 `onUpdateForm`
- 可在 FormPage 中添加 `postCardAction({action: 'message'})` 触发热刷新（本次未加，留给需要时再加）

### 预期异常行为
- 卡片初始显示占位值（onAddForm 同步返回），1-2 秒内异步刷新为真实值
- DB 完全为空时，卡片显示合理默认值（不白屏）
- 番茄卡在无活跃会话时始终显示 idle 状态

## Form 合规注意事项（给后续开发者）

1. **FormPage vs FormAbility 编译器规则不同**
   - FormPage (@Entry @Component `struct` for Form widget): 受最严格 ArkTS widget 规则限制
   - FormAbility (FormExtensionAbility): 运行在主进程，规则相对宽松，可使用 `Record<string, string|number>`, `JSON.stringify`, `Set`, `setInterval` 等

2. **onAddForm 必须同步返回**
   - 先返回占位 `formBindingData`，再 `fire-and-forget` 异步刷新
   - 禁止在 `onAddForm` 中 `await` DB 查询后返回（会超时/阻塞卡片创建）

3. **formId 提取必须用 `formInfo.FormParam.IDENTITY_KEY`**
   - 不能硬编码 `'ohos.extra.param.key.form_identity'`
   - `want.parameters` 是 `Record<string, Object>`，用 `String()` 转换取值

4. **FormPage 键名必须与 FormAbility formData 键名完全一致**
   - FormPage: `@LocalStorageProp('keyName')` 
   - FormAbility: `formData['keyName'] = value`
   - 不一致 → FormPage 收不到数据（显示初始值）

5. **Boolean 在 Form Widget 中用 number (0/1) 代替**
   - DB 的 `completed: number` 直接传递给 FormPage
   - FormPage 中用 `=== 1` 判断

6. **FormPage 字符串拼接用 `+` 不用模板字符串**
   - 所有 FormPage `.ets` 中禁止 `` `${var}` ``
   - 用 `'prefix ' + var + ' suffix'` 形式

7. **FormPage 禁止使用 `any`/`Object`/索引签名**
   - 待办列表数据通过 `JSON.parse(json) as TodoFormItem[]` 解析（有明确 interface）

8. **卡片定时器放在 FormAbility 中，不放在 FormPage 中**
   - FormPage 生命周期短（可能被回收），定时器会被销毁
   - FormAbility 中的定时器在 `onDestroy` 时统一清理

9. **periodic refresh (formProvider.updateForm) 频率控制**
   - 非活跃卡片: 60s 足够，生产环境可放宽到 5min
   - 活跃倒计时（番茄钟）: 1s 快定时器 + 本地缓存避免每秒查 DB
   - `updateDuration: 0` 在 form_*.json 中表示不依赖系统自动刷新，靠自己 push

10. **`@Entry` 在 Form widget 中必须带参数**
    - SDK 6.1.1 编译 warn: `@Entry should have a parameter, like '@Entry(storage)'`
    - 当前使用 `@Entry @Component struct` 可编译但有警告，后续建议改为 `@Entry({storage: 'localStorageName'})`
