# Fix oh_modules for @ohos/shared
$ErrorActionPreference = "Stop"
$baseDir = "D:\Electronic-Diary-huawei\Electronic_Diary"

# List of modules that need oh_modules fix
$modules = @("entry", "features/checkin", "features/todo", "features/diary", "features/gesture-diary", "features/pomodoro", "features/quote", "features/search", "features/statistics", "features/voice-memo", "features/weather")

foreach ($mod in $modules) {
    $modPath = Join-Path $baseDir $mod
    $ohModules = Join-Path $modPath "oh_modules"
    $sharedLink = Join-Path $ohModules "shared"
    $ohosDir = Join-Path $ohModules "@ohos"
    $newLink = Join-Path $ohosDir "shared"
    
    if (Test-Path $sharedLink) {
        Write-Host "Fixing $mod ..."
        # Create @ohos directory if needed
        if (-not (Test-Path $ohosDir)) {
            New-Item -ItemType Directory -Path $ohosDir -Force | Out-Null
        }
        # Remove old link if exists
        if (Test-Path $newLink) {
            Remove-Item $newLink -Force -Recurse
        }
        # Move the link
        Move-Item $sharedLink $newLink -Force
        Write-Host "  OK: Moved shared -> @ohos/shared"
    } else {
        Write-Host "Skipping $mod (no shared link)"
    }
}

Write-Host "Done!"
