; -*- coding: utf-8-with-signature -*-
#Requires AutoHotkey v2.0
; Kill any already-running instance of this script on reload/re-launch.
#SingleInstance Force

; CapsLock -> Ctrl is handled at the keyboard driver level via Scancode Map
; in the registry (set by windows.ps1), not here.  AHK's hook-level remap
; cannot fully suppress CapsLock from the IME layer, which causes unwanted
; IME toggling with Google Japanese Input.

; ===================================================================
; IME Switching (Left Alt = English, Right Alt = Japanese)
;
; Based on karakaram/alt-ime-ahk.
; ~ passes through the native key event so Alt+Tab etc. still work.
; A_PriorKey (tracked by the keyboard hook) equals "LAlt"/"RAlt" only
; when no other key was pressed between Alt-down and Alt-up — i.e., a
; standalone tap.
; ===================================================================

~LAlt Up:: {
    if (A_PriorKey = "LAlt")
        IME_SET(0)
}

~RAlt Up:: {
    if (A_PriorKey = "RAlt")
        IME_SET(1)
}

; ===================================================================
; IME Helper Functions
;
; Port of IMEv2.ahk (k-ayaki) — the standard AHK v2 IME library used
; by alt-ime-ahk-v2f.  Works with Microsoft IME and Google Japanese Input.
;
; GetGUIThreadInfo obtains the focused control's HWND, which
; ImmGetDefaultIMEWnd requires (not the top-level window handle).
; DllCall("SendMessage") targets the IME window directly — AHK's
; built-in SendMessage cannot do this because the IME window is not a
; child control.
; ===================================================================

IME_GET(WinTitle := "A") {
    hwnd := WinExist(WinTitle)
    if (WinActive(WinTitle)) {
        ptrSize := !A_PtrSize ? 4 : A_PtrSize
        cbSize := 4 + 4 + (ptrSize * 6) + 16
        stGTI := Buffer(cbSize, 0)
        NumPut("UInt", cbSize, stGTI.Ptr, 0)
        hwnd := DllCall("GetGUIThreadInfo", "UInt", 0, "Ptr", stGTI.Ptr)
            ? NumGet(stGTI.Ptr, 8 + ptrSize, "UPtr") : hwnd
    }
    return DllCall("SendMessage"
        , "Ptr", DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
        , "UInt", 0x0283    ; WM_IME_CONTROL
        , "Int",  0x0005    ; IMC_GETOPENSTATUS
        , "Int",  0)
}

IME_SET(SetSts, WinTitle := "A") {
    hwnd := WinExist(WinTitle)
    if (WinActive(WinTitle)) {
        ptrSize := !A_PtrSize ? 4 : A_PtrSize
        cbSize := 4 + 4 + (ptrSize * 6) + 16
        stGTI := Buffer(cbSize, 0)
        NumPut("UInt", cbSize, stGTI.Ptr, 0)
        hwnd := DllCall("GetGUIThreadInfo", "UInt", 0, "Ptr", stGTI.Ptr)
            ? NumGet(stGTI.Ptr, 8 + ptrSize, "UPtr") : hwnd
    }
    return DllCall("SendMessage"
        , "Ptr", DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
        , "UInt", 0x0283    ; WM_IME_CONTROL
        , "Int",  0x006     ; IMC_SETOPENSTATUS
        , "Int",  SetSts)   ; 0 = off, 1 = on
}
