; -*- coding: utf-8-with-signature -*-
#Requires AutoHotkey v2.0
; Kill any already-running instance of this script on reload/re-launch.
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

; ~ lets the native Alt keydown pass through so Alt+Tab etc. still work.
; A_PriorKey guard fires only when Alt was released without pressing another
; key in between — i.e., a standalone tap.
~LAlt Up:: {
    if (A_PriorKey = "LAlt")
        IME_Set(0)  ; 0 = IME off (direct / English input)
}

~RAlt Up:: {
    if (A_PriorKey = "RAlt")
        IME_Set(1)  ; 1 = IME on (Japanese input)
}

; ===================================================================
; IME Helper Functions
;
; Talks to the IME via ImmGetDefaultIMEWnd + WM_IME_CONTROL messages.
; This is the standard approach used by karakaram/alt-ime-ahk and works
; with both Microsoft IME and Google Japanese Input.
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
