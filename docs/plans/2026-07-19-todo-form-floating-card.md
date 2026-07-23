# Todo Form Floating Card Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Give the todo service card a clear paper-on-base elevation hierarchy, cap visible todos at three, and show the remaining count without changing its data or navigation behavior.

**Architecture:** Keep `TodoFormPage` as the only active UI entry and preserve its existing `LocalStorageProp` parsing and `postCardAction` wiring. Add todo-form-specific light/dark resources so the outer base and inner sheet no longer share one color, then style the shared list sheet with elevation, border, overflow text, badge, and progress track.

**Tech Stack:** HarmonyOS ArkUI service cards, ArkTS, light/dark color resources, PowerShell source-contract regression test, Hvigor release build, HDC device screenshot verification.

---

### Task 1: Add a failing contract test

**Files:**
- Create: `scripts/test-todo-form-floating-card.ps1`
- Inspect: `entry/src/main/ets/formpages/TodoFormPage.ets:62-191`
- Inspect: `entry/src/main/resources/base/element/color.json`
- Inspect: `entry/src/main/resources/dark/element/color.json`

**Step 1: Write the failing test**

Create `scripts/test-todo-form-floating-card.ps1`:

```powershell
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$pagePath = Join-Path $projectRoot 'entry\src\main\ets\formpages\TodoFormPage.ets'
$lightPath = Join-Path $projectRoot 'entry\src\main\resources\base\element\color.json'
$darkPath = Join-Path $projectRoot 'entry\src\main\resources\dark\element\color.json'
$source = [System.IO.File]::ReadAllText($pagePath)

function Assert-Contains([string]$text, [string]$needle, [string]$label) {
  if (-not $text.Contains($needle)) {
    throw "缺少 UI 合同：$label"
  }
}

Assert-Contains $source 'const maxCount: number = (parsed.length > 3) ? 3 : parsed.length;' '最多显示 3 条'
Assert-Contains $source 'private getOverflowCount(): number' '溢出计数方法'
Assert-Contains $source "'还有 ' + this.getOverflowCount() + ' 项'" '还有 N 项提示'
Assert-Contains $source "'今日暂无待办'" '空态文案'
Assert-Contains $source ".backgroundColor(`$r('app.color.form_todo_base_bg'))" '独立底卡颜色'
Assert-Contains $source ".backgroundColor(`$r('app.color.form_todo_sheet_bg'))" '独立纸片颜色'
Assert-Contains $source ".border({ width: 1, color: `$r('app.color.form_todo_sheet_border') })" '纸片描边'
Assert-Contains $source ".shadow({ radius: 12, color: `$r('app.color.form_todo_sheet_shadow'), offsetY: 6 })" '纸片投影'
Assert-Contains $source '.translate({ y: -6 })' '纸片上移'
Assert-Contains $source ".backgroundColor(`$r('app.color.form_todo_badge_bg'))" '完成计数徽章'
Assert-Contains $source ".backgroundColor(`$r('app.color.form_todo_progress_track'))" '进度条轨道'

$requiredColors = @(
  'form_todo_base_bg',
  'form_todo_sheet_bg',
  'form_todo_sheet_border',
  'form_todo_sheet_shadow',
  'form_todo_badge_bg',
  'form_todo_progress_track'
)

foreach ($path in @($lightPath, $darkPath)) {
  $json = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  $names = @($json.color | ForEach-Object { $_.name })
  foreach ($name in $requiredColors) {
    if ($names -notcontains $name) {
      throw "颜色资源缺失：$name in $path"
    }
  }
}

Write-Host 'PASS: 待办服务卡片具备 3 条上限、溢出提示与深浅色纸片悬浮层级'
```

**Step 2: Run the test to verify it fails**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-todo-form-floating-card.ps1
```

Expected: non-zero exit code with `缺少 UI 合同：溢出计数方法`.

### Task 2: Implement the floating sheet and bounded list

**Files:**
- Modify: `entry/src/main/ets/formpages/TodoFormPage.ets:62-191`
- Modify: `entry/src/main/resources/base/element/color.json:7-14`
- Modify: `entry/src/main/resources/dark/element/color.json:7-14`
- Preserve: all existing uncommitted first-frame parsing and `postCardAction` changes in `TodoFormPage.ets`

**Step 1: Add light-mode todo form resources**

Insert after `form_card_bg` in the base color array:

```json
    {
      "name": "form_todo_base_bg",
      "value": "#FFF1F0EC"
    },
    {
      "name": "form_todo_sheet_bg",
      "value": "#FFFFFFFF"
    },
    {
      "name": "form_todo_sheet_border",
      "value": "#24000000"
    },
    {
      "name": "form_todo_sheet_shadow",
      "value": "#33000000"
    },
    {
      "name": "form_todo_badge_bg",
      "value": "#1F4CAF50"
    },
    {
      "name": "form_todo_progress_track",
      "value": "#1A000000"
    },
```

**Step 2: Add dark-mode todo form resources**

Insert the same names after `form_card_bg` in the dark color array with these values:

```json
    {
      "name": "form_todo_base_bg",
      "value": "#FF1E1E1E"
    },
    {
      "name": "form_todo_sheet_bg",
      "value": "#FF2C2C2C"
    },
    {
      "name": "form_todo_sheet_border",
      "value": "#38FFFFFF"
    },
    {
      "name": "form_todo_sheet_shadow",
      "value": "#66000000"
    },
    {
      "name": "form_todo_badge_bg",
      "value": "#2966BB6A"
    },
    {
      "name": "form_todo_progress_track",
      "value": "#33FFFFFF"
    },
```

**Step 3: Add the overflow helper**

Add after `parseTodos()`:

```typescript
  /** 最多展示 3 条，其余数量用于纸片底部提示。 */
  private getOverflowCount(): number {
    return this.totalCount > 3 ? this.totalCount - 3 : 0;
  }
```

**Step 4: Turn the completion count into a badge**

Keep the current count text and append:

```typescript
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(10)
          .backgroundColor($r('app.color.form_todo_badge_bg'))
```

**Step 5: Replace the current inner list wrapper with the floating sheet**

The sheet content must retain the existing `renderItem(0..2)` calls and dividers, and add bounded overflow/empty states:

```typescript
        Column() {
          if (this.parseTodos().length > 0) {
            this.renderItem(0)
            if (this.parseTodos().length > 1) {
              Divider().strokeWidth(1).color($r('app.color.form_divider')).margin({ top: 5, bottom: 5 })
            }
            this.renderItem(1)
            if (this.parseTodos().length > 2) {
              Divider().strokeWidth(1).color($r('app.color.form_divider')).margin({ top: 5, bottom: 5 })
            }
            this.renderItem(2)

            if (this.getOverflowCount() > 0) {
              Row() {
                Blank()
                Text('还有 ' + this.getOverflowCount() + ' 项')
                  .fontSize(11)
                  .fontColor($r('app.color.form_text_secondary'))
              }
              .width('100%')
              .margin({ top: 5 })
            }
          } else {
            Row() {
              Image(IconMapper.TAB_TODO)
                .width(16)
                .height(16)
                .fillColor($r('app.color.form_icon_muted'))
                .objectFit(ImageFit.Contain)
              Text('今日暂无待办')
                .fontSize(12)
                .fontColor($r('app.color.form_text_secondary'))
                .margin({ left: 6 })
            }
            .height(48)
            .justifyContent(FlexAlign.Center)
          }
        }
        .width('100%')
        .padding({ top: 8, bottom: 8, left: 10, right: 10 })
        .borderRadius(12)
        .backgroundColor($r('app.color.form_todo_sheet_bg'))
        .border({ width: 1, color: $r('app.color.form_todo_sheet_border') })
        .shadow({ radius: 12, color: $r('app.color.form_todo_sheet_shadow'), offsetY: 6 })
        .translate({ y: -6 })
```

Keep the surrounding list area at `.width('100%').layoutWeight(1)`.

**Step 6: Improve the progress track and outer base**

Add the progress track resource after `.color(...)`:

```typescript
        .backgroundColor($r('app.color.form_todo_progress_track'))
```

Replace only the outer `Column` background resource:

```typescript
    .backgroundColor($r('app.color.form_todo_base_bg'))
```

**Step 7: Run the focused test to verify it passes**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-todo-form-floating-card.ps1
```

Expected: exit code `0` and the PASS message.

**Step 8: Inspect the scoped diff**

Run:

```powershell
git diff --check -- entry/src/main/ets/formpages/TodoFormPage.ets entry/src/main/resources/base/element/color.json entry/src/main/resources/dark/element/color.json
git diff -- entry/src/main/ets/formpages/TodoFormPage.ets entry/src/main/resources/base/element/color.json entry/src/main/resources/dark/element/color.json
```

Expected: no whitespace errors; the existing parsing and routing changes remain present.

### Task 3: Build and verify the real service card

**Files:**
- Verify: `entry/src/main/ets/formpages/TodoFormPage.ets`
- Verify: `entry/build/default/outputs/default/entry-default-signed.hap`

**Step 1: Build the release HAP**

Run:

```powershell
& 'D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' 'D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js' --mode module -p product=default -p buildMode=release assembleHap --analyze=normal --parallel --incremental
```

Expected: exit code `0` and `BUILD SUCCESSFUL`; existing project warnings may remain but no new error may reference `TodoFormPage.ets` or the new resources.

**Step 2: Install without clearing service-card data**

Run:

```powershell
& 'D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' install -r 'entry\build\default\outputs\default\entry-default-signed.hap'
```

Expected: `install bundle successfully`.

**Step 3: Refresh and capture the launcher card**

Return the connected local device to the launcher, wait for the dynamic form to refresh, then capture `snapshot_display` as JPEG. If the launcher retains an old render, recreate only the todo form on the local test device; do not clear application data.

Expected visual result: paper-gray base, visibly elevated white/charcoal shared sheet, at most three rows, correct overflow text when data count exceeds three, and no clipping of the shadow or progress track.

**Step 4: Run final verification**

Run the focused test, full release build, and `git diff --check` again immediately before reporting completion.

**Step 5: Preserve the dirty workspace**

The target page and both color resource files already contain user-owned changes. Do not create an implementation commit unless explicitly requested; report the focused diff and verification evidence without staging unrelated work.
