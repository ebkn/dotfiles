; -*- coding: utf-8-with-signature -*-
#Requires AutoHotkey v2.0
#SingleInstance Force

; ===================================================================
; Key Remapping
; ===================================================================

; Caps Lock -> Left Control
CapsLock::LCtrl

; ===================================================================
; IME Switching (Left Alt = English, Right Alt = Japanese)
;
; Tapping Left/Right Alt alone switches IME mode.
; Alt+<key> combinations still work normally thanks to the ~ prefix.
; ===================================================================

~LAlt Up:: {
    if (A_PriorKey = "LAlt")
        IME_Set(0)
}

~RAlt Up:: {
    if (A_PriorKey = "RAlt")
        IME_Set(1)
}

; ===================================================================
; IME Helper Functions
;
; Uses the Input Method Manager API to get/set IME open status.
; Reference: karakaram/alt-ime-ahk
; ===================================================================

IME_Get(winTitle := "A") {
    try {
        hwnd := WinGetID(winTitle)
        ime := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
        if (ime)
            return SendMessage(0x283, 0x005, 0, ime)  ; WM_IME_CONTROL, IMC_GETOPENSTATUS
    }
    return -1
}

IME_Set(setSts, winTitle := "A") {
    try {
        hwnd := WinGetID(winTitle)
        ime := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
        if (ime)
            return SendMessage(0x283, 0x006, setSts, ime)  ; WM_IME_CONTROL, IMC_SETOPENSTATUS
    }
    return -1
}
