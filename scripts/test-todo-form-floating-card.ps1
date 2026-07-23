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
