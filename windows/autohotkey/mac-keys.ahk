#Requires AutoHotkey v2.0
#SingleInstance Force
; ============================================================================
;  MacKeys  让 Apple 妙控键盘在 Windows 上用出 macOS 的手感
;  ---------------------------------------------------------------------------
;  ⌘ Command（左）= Ctrl     → ⌘C 复制、⌘V 粘贴、⌘S 保存、⌘Z 撤销、⌘W 关闭标签
;  ⌘ Command（右）= Win      → 右⌘E 资源管理器、右⌘←/→ 分屏、右⌘D 桌面、右⌘L 锁屏
;  ⌃ Control      = Ctrl     → 不改变（终端里的 Ctrl+C / Ctrl+D、输入法 Ctrl+Space 照旧）
;  ⌥ Option       = Alt      → 不改变
;
;  想临时停用：右键任务栏右下角的 H 图标 → Exit / Suspend
;  想改键位：直接编辑本文件，保存后右键托盘图标 → Reload
; ============================================================================

SendMode "Input"
SetKeyDelay -1, 0
InstallKeybdHook
A_IconTip := "MacKeys：⌘ = Ctrl（右键可退出）"

; 脚本退出 / 重载时释放所有已按下的修饰键，避免“卡键”
OnExit(ReleaseModifiers)
ReleaseModifiers(*) {
    Send "{Blind}{LCtrl up}{LWin up}"
}

; ---------- 左 ⌘ (Command) → Ctrl ----------
*LWin::Send "{Blind}{LCtrl down}"
*LWin Up::Send "{Blind}{LCtrl up}"

; ---------- 右 ⌘ (Command) 保持 Windows 键 ----------
; 不拦截 RWin，它本身就是 Win 键。若想让两个 ⌘ 都等于 Ctrl，把下面两行取消注释：
; *RWin::Send "{Blind}{LCtrl down}"
; *RWin Up::Send "{Blind}{LCtrl up}"

; ---------- 可选：把 ⌃(Control) 也换成 Win，做成 macOS「修饰键互换」的完全体 ----------
; 注意：开启后终端里 Ctrl+C 会变成 Win+C，输入法 Ctrl+Space 也会变成 Win+Space。
; *LCtrl::Send "{Blind}{LWin down}"
; *LCtrl Up::Send "{Blind}{LWin up}"
