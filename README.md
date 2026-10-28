# Mac on Windows — 让苹果键盘 + 妙控板在 Windows 上当 Mac 用

> 一套经过实机验证的完整方案：**妙控板变精密触摸板**（多指手势 / 自然滚动 / 捏合缩放）、
> **三指按住拖动 = 划选文字**、**⌘ 就是 Ctrl**。
> 在 Windows 11（26200）+ Apple Magic Keyboard with Numeric Keypad + Magic Trackpad（USB-C, 2024）上验证。

[![Windows](https://img.shields.io/badge/Windows-11-0078D4)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()

---

## 效果

| 手势 | 行为 | macOS 对应 |
| --- | --- | --- |
| 单指轻点 / 双指轻点 | 左键 / 右键单击 | 单击 / 右键 |
| 双指滑动 | 自然滚动（内容跟手） | 自然滚动 |
| 双指捏合 | 缩放 | 缩放 |
| **三指按住拖动** | **拖拽划选文字 / 拖窗口 / 拖文件** | **三指拖移** |
| 四指 | 可自定义（本方案默认关闭） | Mission Control |

| 按键 | 映射 | 说明 |
| --- | --- | --- |
| ⌘ Command（左） | **Ctrl** | ⌘C / ⌘V / ⌘S / ⌘Z / ⌘W / ⌘T 全部对上 |
| ⌘ Command（右） | **Win** | 右⌘E 资源管理器、右⌘←/→ 分屏、右⌘L 锁屏 |
| ⌃ Control | Ctrl（不变） | 终端 Ctrl+C、输入法 Ctrl+Space 保留 |
| ⌥ Option | Alt（不变） | ⌥Tab 切应用 |

---

## 为什么需要这套东西

1. **妙控板在 Windows 上默认只是个鼠标**：没有精密触摸板（PTP）驱动，就没有多指手势、没有自然滚动、没有捏合缩放。
   官方的开源驱动 [imbushuo/mac-precision-touchpad](https://github.com/imbushuo/mac-precision-touchpad) 最后一版是 2021-06，
   INF 里**没有 2024 款 USB-C 妙控板的 `USB\VID_05AC&PID_0324`**，装了也不生效。
   → 用维护分支 [vitoplantamura/MagicTrackpad2ForWindows](https://github.com/vitoplantamura/MagicTrackpad2ForWindows) **v2.2**（微软 WHQL 签名，含 USB-C 款支持）。
2. **Windows 没有「三指拖移」**。商店里的 `ThreeFingerDragOnWindows` 在部分机器（包括本方案验证机）上会在
   三指操作瞬间崩溃（`Microsoft.UI.Xaml.dll`, `0xc000027b`），且它依赖独占打开 HID 设备读取报告描述符。
   → 本仓库自带一个 10 KB 的 `tfd.exe`，直接解析这块触摸板的原始报文做拖拽，无框架、无崩溃。
3. **⌘ 位置不对**：Windows 把 Command 当 Win 键。→ 一个 AutoHotkey 脚本把左⌘ 变 Ctrl、右⌘ 留作 Win。

---

## 快速开始

### 1. 装驱动（管理员）

```powershell
# 下载 v2.2（微软签名）并安装
powershell -ExecutionPolicy Bypass -File windows\scripts\install-driver.ps1
```

装完在 `设置 > 蓝牙和设备 > 触摸板` 里能看到「设备有一个精密的触摸板」。

### 2. 装三指拖拽 + 键位（普通用户）

```powershell
powershell -ExecutionPolicy Bypass -File windows\scripts\install-tools.ps1
```

它会：编译 `tfd.exe` → 装到 `%LOCALAPPDATA%\MacOnWindows` → 复制 AutoHotkey 键位脚本 →
在启动文件夹建两个快捷方式并立即启动。

> 需要已安装 [AutoHotkey v2](https://www.autohotkey.com/)（`winget install AutoHotkey.AutoHotkey --scope user`）。

### 3. 调整触摸板手势

见 [`docs/findings.md`](docs/findings.md#手势设置)；核心是：
自然滚动、双指轻点=右键、三指手势**全部关掉**（让位给三指拖拽）。

---

### 4. 作为 Agent Skill 使用

`skill/mac-on-windows/` 是一个标准技能包（`SKILL.md` + `references/`），任何支持 skills 的 Agent 都能直接加载：

```powershell
# DeepSeek Harness
Copy-Item -Recurse skill\mac-on-windows "$env:USERPROFILE\.dsh\skills\"
# Claude Code 等：复制到 ~/.claude/skills/
```

之后对 Agent 说「苹果键盘和妙控板插在 Windows 上了，帮我配成 Mac 手感」即可触发这套流程。

---

## 仓库结构

```
windows/
  scripts/
    install-driver.ps1    # 下载 + 安装精密触摸板驱动（管理员）
    install-tools.ps1     # 编译并安装 tfd + 键位脚本（普通用户）
    uninstall-driver.ps1  # 卸载驱动
  three-finger-drag/
    src/tfd.cs            # 三指拖拽源码（.NET Framework 4.x，单文件）
    tfd.ini               # 灵敏度 / 起步阈值
  autohotkey/
    mac-keys.ahk          # ⌘=Ctrl，右⌘=Win
docs/
  findings.md             # 踩坑记录：HID 报文格式、崩溃分析、Windows 手势设置的坑
skill/
  mac-on-windows/
    SKILL.md              # Agent Skill：让 AI 在新机器上复现这套方案
    references/
      hid-report-format.md
```

---

## 技术要点（细节见 docs/findings.md）

妙控板通过 vitoplantamura 驱动暴露的 PTP 报文是 **112 字节**，`ReportID=0x05`：

```
[0]            ReportID 0x05
[1 + 21*i]     第 i 个触点（共 5 个）:
                 flags(1)  bit0=Confidence bit1=TipSwitch
                 ContactID(4)  X(2)  Y(2)  Width(2)  Height(2)  Pressure(2)
                 Size(1) TouchMajor(1) TouchMinor(1) Orientation(1) Finger(1) State(1)
[108]          ContactCount
[109..110]     MechanicalForce
[111]          Button
```

`tfd.exe` 用 `RegisterRawInputDevices(0x0D/0x05)` 拿报文，三指按下并移动超过阈值 → `mouse_event(LEFTDOWN)` +
按触点 ID 逐帧计算平均位移移动光标；全部抬起 → `LEFTUP`。按 ID 对齐可以做到「中途抬起一两根手指不中断、不跳」。

---

## 兼容性

- Windows 11（实测 26200 / 25H2），Windows 10 未验证。
- 驱动分支支持：Magic Trackpad 2 / 3（USB 与蓝牙）、USB-C 款。
- 触摸板必须是**精密触摸板**（装完驱动后即是）；`tfd` 依赖该驱动的报文格式，其他触摸板的报文布局不同，需改 `tfd.cs` 里的偏移。
- 键盘方案（AutoHotkey）与硬件无关，任何键盘都能用。

## 已知坑

- 商店的 `ThreeFingerDragOnWindows` 与本方案二选一，不要同时装（它可能崩，且会抢 HID 句柄）。
- Windows 把「四指上滑 = 任务视图」和「四指左右滑」绑在同一个下拉选项里，**无法只保留上滑**。
- 设备管理器里 `MI_00`（Actuator）黄色感叹号是触觉马达接口，正常现象。

## 许可

MIT。第三方组件：驱动来自 [MagicTrackpad2ForWindows](https://github.com/vitoplantamura/MagicTrackpad2ForWindows)（GPL-2.0，本仓库不包含其二进制，安装脚本从官方 Release 下载）。
