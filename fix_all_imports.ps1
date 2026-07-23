# Fix all @ohos/shared -> shared references
$ErrorActionPreference = "SilentlyContinue"
$baseDir = "D:\Electronic-Diary-huawei\Electronic_Diary"

# 1. Fix oh-package.json5 files
$ohPkgFiles = Get-ChildItem -Path $baseDir -Recurse -Filter "oh-package.json5" -Exclude ".hvigor\*"
foreach ($f in $ohPkgFiles) {
    $content = Get-Content $f.FullName -Raw
    $newContent = $content -replace '"@ohos/shared"', '"shared"'
    if ($content -ne $newContent) {
        Set-Content $f.FullName $newContent -NoNewline
        Write-Host "Fixed: $($f.FullName)"
    }
}

# 2. Fix all .ets import statements
$etsFiles = Get-ChildItem -Path $baseDir -Recurse -Filter "*.ets" -Exclude ".hvigor\*"
foreach ($f in $etsFiles) {
    $content = Get-Content $f.FullName -Raw
    $newContent = $content -replace "'@ohos/shared'", "'shared'"
    if ($content -ne $newContent) {
        Set-Content $f.FullName $newContent -NoNewline
        Write-Host "Fixed: $($f.FullName)"
    }
}

Write-Host "ALL DONE"
