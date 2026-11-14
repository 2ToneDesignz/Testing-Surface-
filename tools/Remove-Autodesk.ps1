#requires -RunAsAdministrator
# Remove-Autodesk.ps1  -  removes every Autodesk program listed in Windows "Installed apps".
# It shows you the list first and does nothing until you type REMOVE.
# After that it offers to delete the leftover Autodesk folders and registry entries (type CLEAN).
# A log is saved to your Desktop: Autodesk-Remove-Log.txt

$ErrorActionPreference = 'Continue'
$log = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Autodesk-Remove-Log.txt'
function Say($msg) { Write-Host $msg; Add-Content -Path $log -Value ("{0}  {1}" -f (Get-Date -Format 's'), $msg) }

# 1. Find everything Autodesk that Windows knows about
$keys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$found = foreach ($k in $keys) {
    Get-ItemProperty -Path $k -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -and ($_.UninstallString -or $_.QuietUninstallString) -and
            ($_.Publisher -like '*Autodesk*' -or $_.DisplayName -match '^(Autodesk|AutoCAD|Forma Add-in)')
        }
}
$apps = $found | Sort-Object DisplayName, UninstallString -Unique

if (-not $apps) {
    Write-Host 'No Autodesk programs found in Installed apps.'
    Read-Host 'Press Enter to close'
    return
}

# 2. Put shared pieces last (libraries, Access, licensing), products first
function Weight($name) {
    if ($name -match 'Genuine Service|Licensing')      { return 9 }
    if ($name -match 'Autodesk Access|Desktop App')    { return 8 }
    if ($name -match 'Medium Resolution')              { return 5 }
    if ($name -match 'Base Resolution')                { return 6 }
    if ($name -match 'Material Library')               { return 7 }
    return 0
}
$apps = $apps | Sort-Object @{ Expression = { Weight $_.DisplayName } }, DisplayName

Write-Host ''
Write-Host 'These Autodesk programs will be removed, in this order:' -ForegroundColor Yellow
$apps | ForEach-Object { Write-Host ('  - {0}  {1}' -f $_.DisplayName, $_.DisplayVersion) }
Write-Host ''
$answer = Read-Host 'Type REMOVE to uninstall all of them (anything else cancels)'
if (($answer -replace '\s','') -ine 'REMOVE') { Write-Host 'Cancelled. Nothing was changed.'; Read-Host 'Press Enter to close'; return }

# 3. Uninstall one by one
foreach ($app in $apps) {
    Say ("Removing: " + $app.DisplayName)
    try {
        $cmd = if ($app.QuietUninstallString) { $app.QuietUninstallString } else { $app.UninstallString }
        $guid = [regex]::Match($cmd, '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}').Value

        if ($cmd -match 'msiexec' -and $guid) {
            $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
        } else {
            $p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$cmd`"" -Wait -PassThru
        }
        Say ("   finished, exit code " + $p.ExitCode + "  (0 = ok, 3010 = ok but restart needed)")
    } catch {
        Say ("   FAILED: " + $_.Exception.Message)
    }
}

# 4. Autodesk Access (installer helper)
$odis = 'C:\Program Files\Autodesk\AdODIS\V1\RemoveODIS.exe'
if (Test-Path $odis) {
    Say 'Removing Autodesk Access (RemoveODIS.exe)'
    Start-Process -FilePath $odis -Wait
}

# 5. Leftovers: folders, license files and registry keys
$folders = @(
    "$env:ProgramFiles\Autodesk",
    "${env:ProgramFiles(x86)}\Autodesk",
    "$env:ProgramData\Autodesk",
    "$env:LOCALAPPDATA\Autodesk",
    "$env:APPDATA\Autodesk"
) | Where-Object { Test-Path $_ }
$flex = @()
if (Test-Path "$env:ProgramData\FLEXnet") { $flex = @(Get-ChildItem -Path "$env:ProgramData\FLEXnet" -Filter 'adsk*' -Force -ErrorAction SilentlyContinue) }
$regKeys = @('HKLM:\SOFTWARE\Autodesk', 'HKLM:\SOFTWARE\WOW6432Node\Autodesk', 'HKCU:\SOFTWARE\Autodesk') | Where-Object { Test-Path $_ }

Write-Host ''
Write-Host 'Leftover Autodesk folders, license files and registry entries:' -ForegroundColor Yellow
$folders | ForEach-Object { Write-Host ('  folder  ' + $_) }
$flex    | ForEach-Object { Write-Host ('  file    ' + $_.FullName) }
$regKeys | ForEach-Object { Write-Host ('  registry ' + $_) }
Write-Host 'Deleting these also deletes your saved Autodesk settings (Revit and AutoCAD options, menus, templates kept in those folders).'
$clean = Read-Host 'Type CLEAN to delete them too (anything else skips this)'
if (($clean -replace '\s','') -ieq 'CLEAN') {
    Say 'Saving a registry backup to your Desktop first'
    $desk = [Environment]::GetFolderPath('Desktop')
    reg export 'HKLM\SOFTWARE\Autodesk' (Join-Path $desk 'Autodesk-HKLM-backup.reg') /y 2>$null | Out-Null
    reg export 'HKCU\SOFTWARE\Autodesk' (Join-Path $desk 'Autodesk-HKCU-backup.reg') /y 2>$null | Out-Null
    foreach ($f in $folders) { Say ('Deleting ' + $f); Remove-Item -LiteralPath $f -Recurse -Force -ErrorAction SilentlyContinue; if (Test-Path $f) { Say '   some files are in use; run this script again after the restart' } }
    foreach ($f in $flex)    { Say ('Deleting ' + $f.FullName); Remove-Item -LiteralPath $f.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    foreach ($k in $regKeys) { Say ('Deleting ' + $k); Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction SilentlyContinue }
} else {
    Say 'Leftovers skipped.'
}

Write-Host ''
Say 'Done. Restart the computer now.'
Say ('Log saved to ' + $log)
Read-Host 'Press Enter to close'
