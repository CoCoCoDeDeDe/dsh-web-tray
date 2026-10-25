# Installs the DSH Web tray controller for the current Windows user.
# Icons are pre-built multi-size whale ICOs; this script only creates
# shortcuts and optionally enables logon autostart / starts the tray.
param(
    [switch]$Autostart,
    [switch]$WebAutostart,
    [switch]$StartTray,
    [switch]$Restart
)

$ErrorActionPreference = 'Stop'

$AppDir = $PSScriptRoot
if (-not $AppDir) { $AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$TrayVbs   = Join-Path $AppDir 'dsh-web-tray.vbs'
$ServerVbs = Join-Path $AppDir 'dsh-web-autostart.vbs'
$IconOn    = Join-Path $AppDir 'dsh-web-running.ico'
$IconOff   = Join-Path $AppDir 'dsh-web-stopped.ico'
$Wscript   = Join-Path $env:SystemRoot 'System32\wscript.exe'

foreach ($icon in @($IconOn, $IconOff)) {
    if (-not (Test-Path -LiteralPath $icon)) {
        throw "Missing icon: $icon"
    }
}

$ws = New-Object -ComObject WScript.Shell

function New-TrayShortcut([string]$Path) {
    $sc = $ws.CreateShortcut($Path)
    $sc.TargetPath = $Wscript
    $sc.Arguments = '"' + $TrayVbs + '"'
    $sc.WorkingDirectory = $AppDir
    $sc.IconLocation = $IconOn + ',0'
    $sc.Description = 'DSH Web tray controller'
    $sc.Save()
}

function New-ServerShortcut([string]$Path) {
    $sc = $ws.CreateShortcut($Path)
    $sc.TargetPath = $Wscript
    $sc.Arguments = '"' + $ServerVbs + '"'
    $sc.WorkingDirectory = $AppDir
    $sc.IconLocation = $IconOn + ',0'
    $sc.Description = 'Start dsh web at logon'
    $sc.Save()
}

$programs = [Environment]::GetFolderPath('Programs')
$startMenuLnk = Join-Path $programs 'DSH Web Tray.lnk'
New-TrayShortcut $startMenuLnk
Write-Output "shortcut: $startMenuLnk"

$desktopLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'DSH Web Tray.lnk'
New-TrayShortcut $desktopLnk
Write-Output "desktop: $desktopLnk"

$trayStartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'DSH Web Tray.lnk'
if ($Autostart) {
    New-TrayShortcut $trayStartupLnk
    Write-Output "autostart-tray: $trayStartupLnk"
}

$webStartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'DSH Web Server.lnk'
if ($WebAutostart) {
    if (-not (Test-Path -LiteralPath $ServerVbs)) {
        throw "Missing script: $ServerVbs"
    }
    New-ServerShortcut $webStartupLnk
    Write-Output "autostart-web: $webStartupLnk"
}

if ($Restart) {
    $target = Join-Path $AppDir 'dsh-web-tray.ps1'
    Get-CimInstance Win32_Process | Where-Object {
        $_.ProcessId -ne $PID -and $_.Name -eq 'powershell.exe' -and
        $_.CommandLine -and $_.CommandLine.Contains($target)
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 700
    Start-Process -FilePath $Wscript -ArgumentList ('"' + $TrayVbs + '"')
    Write-Output 'tray: restarted'
} elseif ($StartTray) {
    Start-Process -FilePath $Wscript -ArgumentList ('"' + $TrayVbs + '"')
    Write-Output 'tray: launched'
}

Write-Output 'OK'
