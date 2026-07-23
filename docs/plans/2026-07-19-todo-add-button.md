# Todo Add Button Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep a usable add button on the right side of each non-empty todo group header so users can add multiple todos consecutively.

**Architecture:** Restore the add entry inside `TodoList` because that component already knows the target group and exposes the existing `onAdd` callback. Render the header button only for non-empty groups; empty groups continue to use `EmptyStateView`, so no dialog, ViewModel, or database flow changes are required.

**Tech Stack:** HarmonyOS ArkUI, ArkTS, project theme/icon tokens, PowerShell source-contract regression test, Hvigor release build.

---

### Task 1: Add a failing regression test for the header entry

**Files:**
- Create: `scripts/test-todo-add-button.ps1`
- Inspect: `features/todo/src/main/ets/components/TodoList.ets:33-122`

**Step 1: Write the failing test**

Create `scripts/test-todo-add-button.ps1` with this complete content:

```powershell
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$todoListPath = Join-Path $projectRoot 'features\todo\src\main\ets\components\TodoList.ets'
$source = [System.IO.File]::ReadAllText($todoListPath)

$headerStart = $source.IndexOf('// 分组标题栏')
$listStart = $source.IndexOf('// 列表项（每项之间间距）')
if ($headerStart -lt 0 -or $listStart -le $headerStart) {
  throw '无法定位 TodoList 分组标题栏'
}

$header = $source.Substring($headerStart, $listStart - $headerStart)
$checks = @(
  @{ Name = '非空分组条件'; Pattern = 'if \(this\.items\.length > 0\)' },
  @{ Name = '项目加号图标'; Pattern = 'SymbolGlyph\(IconMapper\.PLUS\)' },
  @{ Name = '48vp 宽触控区'; Pattern = '\.width\(48\)' },
  @{ Name = '48vp 高触控区'; Pattern = '\.height\(48\)' },
  @{ Name = '今日无障碍文案'; Pattern = "'添加今日待办'" },
  @{ Name = '明日无障碍文案'; Pattern = "'添加明日待办'" },
  @{ Name = '复用 onAdd 回调'; Pattern = 'this\.onAdd\(\)' }
)

foreach ($check in $checks) {
  if ($header -notmatch $check.Pattern) {
    throw "缺少：$($check.Name)"
  }
}

if ($source -notmatch "actionText: '添加待办'") {
  throw '空状态添加按钮被意外移除'
}

Write-Host 'PASS: 非空分组显示右侧加号，空分组保留原添加按钮'
```

**Step 2: Run the test to verify it fails**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-todo-add-button.ps1
```

Expected: exit code is non-zero and the message is `缺少：非空分组条件` because the current header has no conditional add button.

### Task 2: Restore the non-empty group header add button

**Files:**
- Modify: `features/todo/src/main/ets/components/TodoList.ets:12`
- Modify: `features/todo/src/main/ets/components/TodoList.ets:55-60`
- Preserve: the existing uncommitted `assigneeName` forwarding near `TodoList.ets:78-79`

**Step 1: Extend the existing shared-token import**

Add `ICON` to the existing import from `@ohos/shared`:

```typescript
import { IconMapper, EmptyStateView, RADIUS, SPACING, TYPO, FONT, SKETCH_TITLE, ICON } from '@ohos/shared';
```

**Step 2: Add the minimal conditional button after `Blank()`**

Replace the removed-button comments with:

```typescript
        // 非空分组保留快捷新增入口；空分组继续使用下方 EmptyStateView 按钮，避免重复。
        if (this.items.length > 0) {
          Button() {
            Stack() {
              SymbolGlyph(IconMapper.PLUS)
                .fontSize(ICON.plus)
                .fontWeight(FontWeight.Bold)
                .fontColor([this.tokens ? this.tokens.btnPrimary : '#738A9C'])
            }
            .width(ICON.plusRing)
            .height(ICON.plusRing)
            .borderRadius(ICON.plusRing / 2)
            .border({
              width: ICON.ringStroke,
              color: this.tokens ? this.tokens.btnPrimary : '#738A9C'
            })
          }
          .width(48)
          .height(48)
          .borderRadius(24)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            if (this.onAdd) {
              this.onAdd();
            }
          })
          .accessibilityText(this.groupType === 'today' ? '添加今日待办' : '添加明日待办')
        }
```

This uses the same outlined-plus visual language as the existing today/tomorrow sections while giving the button a 48vp touch target.

**Step 3: Run the focused test to verify it passes**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-todo-add-button.ps1
```

Expected: exit code `0` and `PASS: 非空分组显示右侧加号，空分组保留原添加按钮`.

**Step 4: Inspect the scoped diff**

Run:

```powershell
git diff --check -- features/todo/src/main/ets/components/TodoList.ets scripts/test-todo-add-button.ps1
git diff -- features/todo/src/main/ets/components/TodoList.ets scripts/test-todo-add-button.ps1
```

Expected: no whitespace errors; the existing `assigneeName` change remains intact and the only new production change is the import plus conditional header button.

### Task 3: Verify compilation and behavior

**Files:**
- Verify: `features/todo/src/main/ets/components/TodoList.ets`
- Verify: `entry/src/main/ets/pages/TimelineTodoView.ets:610-648`

**Step 1: Build the release HAP with the bundled DevEco toolchain**

Run:

```powershell
& 'D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' 'D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js' --mode module -p product=default -p buildMode=release assembleHap --analyze=normal --parallel --incremental
```

Expected: exit code `0` and `BUILD SUCCESSFUL`.

**Step 2: Re-run the regression test after the build**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-todo-add-button.ps1
```

Expected: exit code `0` and the PASS message.

**Step 3: Verify the user-visible flow on a device or preview when available**

1. Open the todo timeline page with an empty today group and confirm only the large empty-state add button is shown.
2. Add the first today todo and confirm a plus appears at the right of the today group title.
3. Tap that plus and confirm the add dialog opens with the today group selected.
4. Repeat for the tomorrow group and confirm its plus opens the tomorrow add flow.
5. Confirm edit, complete, and delete interactions still work.

**Step 4: Report without committing unrelated work**

The target file already contains a user-owned uncommitted `assigneeName` change, and the repository contains other staged/unstaged work. Do not create an implementation commit unless the user explicitly requests it; report the focused diff and verification evidence instead.
