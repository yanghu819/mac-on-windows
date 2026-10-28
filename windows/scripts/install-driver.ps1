#Requires -RunAsAdministrator
<#
.SYNOPSIS
    安装 Apple 妙控板 的 Windows 精密触摸板驱动（维生素王 / Vito Plantamura 分支，微软 WHQL 签名）。

.DESCRIPTION
    从 GitHub Release 下载 MT2FW11-*-MSSigned.zip，校验目录签名后交给 pnputil 安装。
    不包含任何二进制，也不修改 Secure Boot / 测试签名设置。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install-driver.ps1
#>
[CmdletBinding()]
param(
    [string]$ReleaseTag = 'v2.2',
    [string]$AssetName  = 'MT2FW11-20261012-MSSigned.zip'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

Write-Step "准备工作目录"
$work = Join-Path $env:TEMP ('mac-on-windows-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null

$url = "https://github.com/vitoplantamura/MagicTrackpad2ForWindows/releases/download/$ReleaseTag/$AssetName"
$zip = Join-Path $work $AssetName

Write-Step "下载 $AssetName"
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
Write-Host ("    {0:N0} bytes" -f (Get-Item $zip).Length)

Write-Step '解压'
$dir = Join-Path $work 'driver'
Expand-Archive -Path $zip -DestinationPath $dir -Force

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'ARM64' } else { 'AMD64' }
$inf  = Join-Path $dir "$arch\AmtPtpDevice.inf"
if (-not (Test-Path $inf)) { throw "找不到 $inf，请检查压缩包结构" }

$cat = Get-AuthenticodeSignature (Join-Path $dir "$arch\amtptpdevice.cat")
Write-Step "校验签名: $($cat.Status) / $($cat.SignerCertificate.Subject)"
if ($cat.Status -ne 'Valid') { throw '驱动目录签名无效，已中止' }

Write-Step '安装驱动'
& pnputil.exe /add-driver $inf /install
& pnputil.exe /scan-devices
Start-Sleep -Seconds 5

Write-Step '验证'
$ptp = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match 'Precision Touchpad' }
if ($ptp) {
    $ptp | Select-Object FriendlyName, Status | Format-Table -AutoSize
    Write-Host '驱动已加载。请打开 设置 > 蓝牙和设备 > 触摸板 确认显示「设备有一个精密的触摸板」。' -ForegroundColor Green
} else {
    Write-Warning '没有发现 Apple Precision Touchpad 设备。请检查触摸板是否插好（USB 线连接时才会出现），或设备是否已被其他驱动占用。'
}

Write-Host "`n临时文件: $work" -ForegroundColor DarkGray
