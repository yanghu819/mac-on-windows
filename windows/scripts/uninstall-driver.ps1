#Requires -RunAsAdministrator
<#
.SYNOPSIS
    卸载本方案安装的 Apple 精密触摸板驱动。
.DESCRIPTION
    在 %WINDIR%\INF\oem*.inf 中按内容找到 AmtPtpDevice 对应的发布包名，再交给 pnputil 删除，
    避免依赖 pnputil 本地化的输出格式。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$inf = Get-ChildItem (Join-Path $env:WINDIR 'INF\oem*.inf') -ErrorAction SilentlyContinue |
    Where-Object { (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'AmtPtpDevice' } |
    Select-Object -First 1

if (-not $inf) {
    Write-Host '没有找到 AmtPtpDevice 驱动包，可能已经卸载。' -ForegroundColor Yellow
    exit 0
}

Write-Host "找到驱动包: $($inf.Name)" -ForegroundColor Cyan
& pnputil.exe /delete-driver $inf.Name /uninstall /force
& pnputil.exe /scan-devices

Write-Host "`n完成。建议重启一次，让触摸板回到默认 HID 鼠标模式。" -ForegroundColor Green
