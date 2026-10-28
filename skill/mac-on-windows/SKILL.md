---
name: mac-on-windows
description: Configure an Apple Magic Keyboard and/or Magic Trackpad on Windows 11 so it feels like macOS — precision-touchpad driver, natural scrolling and gestures, three-finger drag-to-select, and Cmd-as-Ctrl key mapping. Use when Apple input hardware is connected to a Windows PC, when the trackpad has no gestures, or when the user asks to make Windows input behave like a Mac.
---

# Mac-like input on Windows

Reproduce a verified setup for **Apple Magic Keyboard + Magic Trackpad on Windows 11**.
Everything below was validated on Windows 11 build 26200 with `VID_05AC&PID_0324` (USB-C Magic Trackpad, 2024)
and `VID_05AC&PID_026C` (Magic Keyboard with Numeric Keypad).

Work in this order. Do not skip the identification step — the correct driver depends on the exact USB product ID.

## 1. Identify the hardware

```powershell
Get-PnpDevice -PresentOnly |
  Where-Object { $_.InstanceId -like '*VID_05AC*' } |
  Select-Object Class, FriendlyName, Status, InstanceId |
  Format-Table -AutoSize
```

Record the product IDs. `Get-PnpDeviceProperty -InstanceId <id> -KeyName DEVPKEY_Device_BusReportedDeviceDesc`
gives the marketing name. Check whether a precision touchpad already exists:

```powershell
Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like '*VID_8910*' }
```

`VID_8910` is the pseudo-VID Windows assigns to precision touchpads. If it exists, skip step 2.

## 2. Install the precision-touchpad driver

The original [imbushuo/mac-precision-touchpad](https://github.com/imbushuo/mac-precision-touchpad) release
(`2105-3979`, 2021-06) does **not** contain `USB\VID_05AC&PID_0324&MI_01`, so 2021+ trackpads stay generic mice.
Use the maintained fork with a Microsoft-signed build:

- repo: `vitoplantamura/MagicTrackpad2ForWindows`
- asset: `MT2FW11-<date>-MSSigned.zip` (Windows 11, WHQL-signed — no test-signing, no Secure Boot changes)

Run `windows/scripts/install-driver.ps1` from this skill's repository, or manually:

```powershell
# elevated
Invoke-WebRequest "https://github.com/vitoplantamura/MagicTrackpad2ForWindows/releases/download/v2.2/MT2FW11-20261012-MSSigned.zip" -OutFile $env:TEMP\mt2.zip
Expand-Archive $env:TEMP\mt2.zip $env:TEMP\mt2 -Force
pnputil /add-driver "$env:TEMP\mt2\AMD64\AmtPtpDevice.inf" /install
pnputil /scan-devices
```

Verify all three:

1. `Get-PnpDevice` shows `Apple USB Precision Touchpad Device (User-mode)` with status `OK`.
2. The touchpad HID node's hardware IDs contain `HID\VID_8910&UP:000D_U:0005`.
3. `ms-settings:devices-touchpad` shows “Your device has a precision touchpad”.

Before installing, confirm the INF actually lists the device's hardware ID:

```powershell
Select-String -Path .\AMD64\AmtPtpDevice.inf -Pattern 'Pid_0324'
```

## 3. Configure macOS-style touchpad behaviour

Settings that live in the registry (`HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad`):
`TapsEnabled`, `TwoFingerTapEnabled`, `ScrollDirection`, `TapAndDrag`, `RightClickZoneEnabled`, `CursorSpeed`.

Three/four-finger gesture **actions are not in the registry** — they are stored by the Settings app.
Change them through the UI (`ms-settings:devices-touchpad`), or via UI Automation:

| Setting | Value |
| --- | --- |
| Scroll direction | natural (content follows fingers) |
| Tap with one finger | on (left click) |
| Tap with two fingers | on (right click) |
| Right-click corner | **off** |
| Three-finger swipes / taps | **off** (reserved for drag) |
| Four-finger swipes / taps | off unless the user wants Task View / virtual desktops |

Warn the user: Windows binds “four-finger swipe up = Task View” and “left/right = switch desktops” to a **single**
dropdown. There is no way to keep only the up swipe.

## 4. Three-finger drag (drag-to-select)

Windows has no three-finger drag. `ThreeFingerDragOnWindows` (Store) crashes on some machines
(`Microsoft.UI.Xaml.dll`, `0xc000027b`) and needs an exclusive HID handle to read the report descriptor, which can fail
with `ERROR_SHARING_VIOLATION`. Prefer the bundled `tfd` tool, which parses the raw PTP reports directly.

```powershell
powershell -ExecutionPolicy Bypass -File windows\scripts\install-tools.ps1
```

This compiles `three-finger-drag/src/tfd.cs` with the in-box .NET Framework compiler, installs it to
`%LOCALAPPDATA%\MacOnWindows`, copies the AutoHotkey map, and registers both in the Startup folder.

Behaviour: three fingers down + move past threshold → `LEFTDOWN`; movement is applied from the average delta of
contacts matched by ContactID (lifting one or two fingers neither jumps nor ends the drag); all fingers up → `LEFTUP`.

Tune with `tfd.ini`: `sensitivity` (touchpad units → screen pixels, default 0.55), `threshold` (start distance, default 60).
Diagnose with `tfd.log` — it logs `armed n=3` and `drag start` / `drag end`.

## 5. Keyboard mapping

`windows/autohotkey/mac-keys.ahk` (AutoHotkey v2, per-user install: `winget install AutoHotkey.AutoHotkey --scope user`):

- left ⌘ → **Ctrl** (⌘C/⌘V/⌘S/⌘Z/⌘W/⌘T all match macOS)
- right ⌘ → **Win** (right-⌘E, right-⌘←/→, right-⌘L)
- ⌃ → Ctrl unchanged (keeps terminal Ctrl+C and IME Ctrl+Space working)
- ⌥ → Alt unchanged

Trade-off to state explicitly: ⌘Tab becomes Ctrl+Tab (tab switching), so app switching is ⌥Tab.
A fully swapped mode (⌃ → Win) is available as commented lines at the end of the script.

## 6. Verify and hand over

- Open Notepad, drag three fingers across text → selection follows.
- Press ⌘C / ⌘V in a text field.
- Right-⌘E opens File Explorer.
- Two-finger scroll moves content with the fingers.
- Check `tfd.log` and the AutoHotkey tray icon if anything is silent.

Report what was installed, where the scripts live, how to pause each piece, and how to uninstall the driver
(`pnputil /delete-driver oemNN.inf /uninstall /force`).

## Pitfalls

| Symptom | Cause |
| --- | --- |
| No Touchpad page in Settings | INF does not match the PID, or the device still uses `HidUsb` |
| Touchpad page exists, no gestures | Three-finger gestures disabled in Settings, or the drag tool is not running |
| Drag does nothing | `tfd.log` has no `armed` → reports not arriving (check the device, USB port, or a competing app holding the HID handle) |
| Cursor moves too slowly while dragging | raise `sensitivity` in `tfd.ini` |
| Drag triggers while just resting fingers | raise `threshold` |
| `MI_00` yellow bang in Device Manager | Apple haptic actuator interface — expected, not an error |
