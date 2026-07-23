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
