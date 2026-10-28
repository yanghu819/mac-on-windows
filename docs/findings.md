# 踩坑记录与技术细节

> 记录 2026-10-28 在一台 Windows 11（build 26200 / 25H2）设备上，
> 把 **Magic Keyboard with Numeric Keypad（USB）+ Magic Trackpad USB-C 2024（USB）** 配置成 macOS 手感的全过程。

---

## 1. 设备识别

接入后 `Get-PnpDevice` 能看到：

| 设备 | VID/PID | 说明 |
| --- | --- | --- |
| Magic Keyboard with Numeric Keypad | `VID_05AC&PID_026C` | 标准 HID 键盘，Windows 直接能用 |
| Magic Trackpad（USB-C, 2024） | `VID_05AC&PID_0324` | **关键**：MI_00 是触觉马达（Actuator，Code 10），MI_01 是 HID，MI_02 是厂商集合 |

没有 PTP 驱动时，MI_01 只表现为 `HID-compliant mouse` + `HID-compliant touch pad`（非精密），
系统里没有「触摸板」设置页，没有多指手势、没有自然滚动、没有捏合缩放。

## 2. 驱动选型

官方 [imbushuo/mac-precision-touchpad](https://github.com/imbushuo/mac-precision-touchpad) 的最后一个 release
（`2105-3979`, 2021-06）里的 INF **不包含** `USB\VID_05AC&PID_0324&MI_01`：

```inf
; 3979 的 INF 只到 0265 / 0291 ...
%AmtPtpDeviceUsbUm.DeviceDesc%=AmtPtpDeviceUsbUm_Install, USB\Vid_05ac&Pid_0265&MI_01
```

2024 款 USB-C 妙控板是 2021-08 之后发布的，所以装上也不会匹配 —— 这是最容易踩的坑。

**采用**：[vitoplantamura/MagicTrackpad2ForWindows](https://github.com/vitoplantamura/MagicTrackpad2ForWindows) **v2.2**
（2026-10-12，GPL-2.0），INF 里已有：

```inf
%AmtPtpDeviceUsbUm.DeviceDesc%=AmtPtpDeviceUsbUm_Install, USB\Vid_05ac&Pid_0324&MI_01
%AmtPtpHidFilter.DeviceDesc%=AmtPtpHidFilter_MiniPortDevice, HID\{00001124-...}_VID&0001004c_PID&0324&Col01
```

包是**微软 WHQL 签名**（`MT2FW11-20261012-MSSigned.zip`），无需关闭 Secure Boot、无需测试签名模式。
USB 分支是 **UMDF 用户态驱动**，不加载内核模块，风险低。

安装：

```powershell
pnputil /add-driver .\AMD64\AmtPtpDevice.inf /install
pnputil /scan-devices
```

验证（三条都满足才算成功）：

1. `Get-PnpDevice` 出现 `Apple USB Precision Touchpad Device (User-mode)`，状态 OK；
2. 触摸板 HID 集合的硬件 ID 里出现 `HID\VID_8910&UP:000D_U:0005`（`VID_8910` 是 Windows 给精密触摸板的专用 VID）；
3. `设置 > 蓝牙和设备 > 触摸板` 显示「设备有一个精密的触摸板」。

## 3. 手势设置

触控板的点击 / 滚动 / 缩放开关在注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad`
（`TapsEnabled`、`TwoFingerTapEnabled`、`ScrollDirection`、`TapAndDrag`、`RightClickZoneEnabled`、`CursorSpeed`…）。

但**三指/四指手势的动作配置不在注册表里**（`HKCU` 搜 `ThreeFinger` 为 0 结果），它在 Settings 应用自己的存储中，
只能通过设置页修改。没有 UI 自动化时，用 `ms-settings:devices-touchpad` 打开让用户点。

本方案的选择：

| 项目 | 值 | 原因 |
| --- | --- | --- |
| 滚动方向 | 自然（内容跟手） | macOS 默认 |
| 双指轻点 | 右键 | macOS 默认 |
| 单指点按 | 左键 | macOS 默认 |
| 右下角单击=右键 | 关 | Mac 没有，容易误触 |
| 三指轻扫 / 三指轻点 | **关** | 让位给三指拖拽 |
| 四指轻扫 / 四指轻点 | 关 | 按需求关闭 |

> ⚠️ Windows 把「四指上滑 = 任务视图」和「四指左右滑 = 切换桌面」绑定在**同一个下拉选项**里，
> 选「无」时两者一起消失，**没有**只保留上滑的办法。

## 4. 三指拖拽：为什么不用现成的

商店应用 `ThreeFingerDragOnWindows`（MIT，C#/WinUI3）在这台机器上表现为「三指拖动毫无反应」。实测证据：

- 三指操作时事件日志记录：`Application Error` + `MoAppCrash`，`Microsoft.UI.Xaml.dll`，异常码 `0xc000027b`（stowed exception）；
- 该应用通过 `CreateFile` 打开 HID 设备读取报告描述符，而本机该设备句柄被独占，`CreateFile` 返回 `ERROR_SHARING_VIOLATION (32)`，
  拿不到描述符就无法解析报文。

结论：不是驱动的问题（见下一节的报文实测），是该应用与本机环境不兼容。

## 5. HID 报文格式（实测）

驱动按 `AmtPtp Mt2` 描述符上报，**112 字节**，`ReportID = 0x05`：

| 偏移 | 长度 | 含义 |
| --- | --- | --- |
| 0 | 1 | ReportID `0x05` |
| 1 + 21·i | 21 | 第 i 个触点（i = 0..4） |
| 108 | 1 | ContactCount |
| 109 | 2 | MechanicalForce（各触点压力之和） |
| 111 | 1 | Button（物理按压） |

单个触点 21 字节：

| 偏移(+i·21) | 长度 | 含义 |
| --- | --- | --- |
| 0 | 1 | flags：bit0 = Confidence，bit1 = TipSwitch |
| 1 | 4 | ContactID（uint32） |
| 5 | 2 | X（逻辑范围 0..7612） |
| 7 | 2 | Y（逻辑范围 0..5065） |
| 9 | 2 | Width |
| 11 | 2 | Height |
| 13 | 2 | Pressure |
| 15 | 6 | Size / TouchMajor / TouchMinor / Orientation / Finger / State（厂商定义） |

实测三指报文解码：

```
count=3  force=23  btn=0
  c0: tip=True id=1   x=4500 y=2347 w=324 h=380 p=10
  c1: tip=True id=2   x=3651 y=3024 w=328 h=351 p=5
  c2: tip=True id=10  x=5636 y=2580 w=328 h=272 p=8
  c3/c4: tip=False（空槽）
```

→ 驱动上报 3 个独立触点、ID 稳定、坐标随手指移动，**完全正常**。

## 6. `tfd.exe` 的实现要点

1. `RegisterRawInputDevices`，UsagePage `0x0D` / Usage `0x05`，`RIDEV_INPUTSINK`，隐藏窗口接收 `WM_INPUT`；
2. 只处理 112 字节、首字节 `0x05` 的报文；
3. 取 TipSwitch 为真的触点，按 ContactID 建索引；
4. 三指且位移超过阈值（默认 60 单位）→ `mouse_event(LEFTDOWN)`；
5. 拖拽中按**同 ID 的逐帧位移取平均**移动光标（`SetCursorPos`），所以抬起一两根手指不会跳、不会中断；
6. 全部抬起 → `LEFTUP`；
7. 灵敏度 `sensitivity`（触摸板单位 → 屏幕像素）可在 `tfd.ini` 调，默认 0.55。

编译（无需 SDK，用系统自带的 .NET Framework 编译器）：

```powershell
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /target:winexe /out:tfd.exe `
  /r:System.Windows.Forms.dll /r:System.Drawing.dll tfd.cs
```

## 7. 键盘映射的取舍

**方案 A（本仓库默认）**：左 ⌘ → Ctrl，右 ⌘ → Win，⌃ 保持 Ctrl。

优点：终端里的 Ctrl+C/Ctrl+D、中文输入法 Ctrl+Space 全部照旧。
代价：⌘Tab 变成 Ctrl+Tab（切标签），切换应用要用 ⌥Tab。这是刻意取舍。

**方案 B（macOS「修饰键互换」完全体）**：左 ⌘ → Ctrl，⌃ → Win。
更接近 macOS 的物理布局，但终端里 Ctrl+C 会变成 Win+C、输入法 Ctrl+Space 也变 Win+Space。
`mac-keys.ahk` 末尾保留了两行注释，取消注释即可切换。

实现用 AutoHotkey v2 的 `*LWin::` 通配热键（不是注册表 Scancode Map），好处是即改即生效、可随时退出，
代价是对管理员权限窗口（UAC、任务管理器）不生效。

## 8. 排错清单

| 现象 | 检查 |
| --- | --- |
| 设置里没有「触摸板」页 | 驱动没绑上：看设备管理器 `VID_05AC&PID_0324&MI_01` 的驱动是否是 `Apple USB Precision Touchpad Device` |
| 有触摸板页但手势无效 | 三指/四指手势设置是否被关；`tfd` 是否在运行 |
| 三指拖拽没反应 | `tfd.log` 有没有 `armed n=3` / `drag start`；没有 `armed` 说明报文没进来（换 USB 口 / 检查是否被商店版应用占用） |
| 拖拽时光标太慢 | 调大 `tfd.ini` 的 `sensitivity` |
| 拖拽误触发 | 调大 `threshold` |
| 键盘映射无效 | 托盘 H 图标是否存在；管理员窗口内本来就不生效 |
