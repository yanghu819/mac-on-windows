#Requires -Version 5.1
<#
.SYNOPSIS
    编译并安装三指拖拽工具 + AutoHotkey 键位脚本，并加入开机启动。

.DESCRIPTION
    不需要 .NET SDK：使用 Windows 自带的 .NET Framework 4.x 编译器（csc.exe）。
    AutoHotkey v2 需另行安装：winget install AutoHotkey.AutoHotkey --scope user

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install-tools.ps1
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'MacOnWindows'),
    [switch]$NoStartup
)

$ErrorActionPreference = 'Stop'
function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # ...\mac-on-windows
$srcDir   = Join-Path $repoRoot 'windows\three-finger-drag'
$ahkDir   = Join-Path $repoRoot 'windows\autohotkey'

# ---------- 1. 找 csc.exe ----------
$csc = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) { throw '找不到 .NET Framework 编译器 csc.exe（需要 Windows 自带的 .NET Framework 4.x）' }
Write-Step "编译器: $csc"

# ---------- 2. 编译 ----------
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$exe = Join-Path $InstallDir 'tfd.exe'
Write-Step "编译 tfd.exe -> $InstallDir"
& $csc /nologo /target:winexe "/out:$exe" /r:System.Windows.Forms.dll /r:System.Drawing.dll `
    (Join-Path $srcDir 'src\tfd.cs')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) { throw '编译失败' }

Copy-Item (Join-Path $srcDir 'tfd.ini') (Join-Path $InstallDir 'tfd.ini') -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $ahkDir 'mac-keys.ahk') (Join-Path $InstallDir 'mac-keys.ahk') -Force

# ---------- 3. 找 AutoHotkey ----------
$ahk = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'),
    (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ahk) {
    Write-Warning '没有找到 AutoHotkey v2，键位脚本不会自启。安装：winget install AutoHotkey.AutoHotkey --scope user'
}

# ---------- 4. 开机启动 ----------
if (-not $NoStartup) {
    $startup = [Environment]::GetFolderPath('Startup')
    $ws = New-Object -ComObject WScript.Shell

    $l1 = $ws.CreateShortcut((Join-Path $startup 'ThreeFingerDrag.lnk'))
    $l1.TargetPath = $exe
    $l1.WorkingDirectory = $InstallDir
    $l1.Description = '三指拖拽（三指按住拖动 = 划选）'
    $l1.Save()

    if ($ahk) {
        $l2 = $ws.CreateShortcut((Join-Path $startup 'MacKeys.lnk'))
        $l2.TargetPath = $ahk
        $l2.Arguments = '"' + (Join-Path $InstallDir 'mac-keys.ahk') + '"'
        $l2.WorkingDirectory = $InstallDir
        $l2.Description = 'MacKeys - ⌘ = Ctrl'
        $l2.Save()
    }
    Write-Step "已创建启动快捷方式: $startup"
}

# ---------- 5. 立即运行 ----------
Get-Process -Name 'tfd' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $exe -WorkingDirectory $InstallDir
if ($ahk) { Start-Process -FilePath $ahk -ArgumentList ('"' + (Join-Path $InstallDir 'mac-keys.ahk') + '"') }

Start-Sleep -Seconds 2
Write-Step '运行状态'
Get-Process -Name 'tfd', 'AutoHotkey64' -ErrorAction SilentlyContinue |
    Select-Object ProcessName, Id | Format-Table -AutoSize

Write-Host "`n完成。托盘区应出现两个图标（tfd 的三指拖拽、AutoHotkey 的 H）。" -ForegroundColor Green
Write-Host "调参: $InstallDir\tfd.ini    日志: $InstallDir\tfd.log" -ForegroundColor DarkGray
