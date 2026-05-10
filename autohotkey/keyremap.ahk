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
;
; SwitchInput first forces the keyboard layout to English (0409) or
; Japanese (0411) via WM_INPUTLANGCHANGEREQUEST, then sets the IME
; open state.  Toggling IME state alone is unreliable when Windows
; auto-switches the layout to "English (US)", because no IME window
; exists in that layout.
; ===================================================================

~LAlt Up:: {
    if (A_PriorKey = "LAlt")
        SwitchInput(0x0409, 0)
}

~RAlt Up:: {
    if (A_PriorKey = "RAlt")
        SwitchInput(0x0411, 1)
}

; Find an already-loaded HKL whose low word matches the requested language ID.
; Returns 0 if no matching layout is loaded in the system.
FindHKLByLangID(langID) {
    count := DllCall("GetKeyboardLayoutList", "Int", 0, "Ptr", 0)
    buf := Buffer(A_PtrSize * count, 0)
    DllCall("GetKeyboardLayoutList", "Int", count, "Ptr", buf.Ptr)
    Loop count {
        hkl := NumGet(buf.Ptr, (A_Index - 1) * A_PtrSize, "Ptr")
        if ((hkl & 0xFFFF) = langID)
            return hkl
    }
    return 0
}

; Switch the foreground window's input language to targetLangID, then set IME
; open state.  AttachThreadInput is required because ActivateKeyboardLayout
; only affects the calling thread; without attaching, our AHK process would
; switch its own layout while the foreground app stays put.  PostMessage is
; sent in addition as a fallback for apps that listen for it explicitly.
SwitchInput(targetLangID, imeState) {
    targetHkl := FindHKLByLangID(targetLangID)
    if (!targetHkl)
        return

    fgWnd := WinExist("A")
    if (!fgWnd)
        return

    fgThread := DllCall("GetWindowThreadProcessId", "Ptr", fgWnd, "Ptr", 0, "UInt")
    ourThread := DllCall("GetCurrentThreadId", "UInt")

    if (fgThread && fgThread != ourThread) {
        DllCall("AttachThreadInput", "UInt", ourThread, "UInt", fgThread, "Int", 1)
        DllCall("ActivateKeyboardLayout", "Ptr", targetHkl, "UInt", 0)
        PostMessage(0x50, 0, targetHkl, , "ahk_id " fgWnd)
        DllCall("AttachThreadInput", "UInt", ourThread, "UInt", fgThread, "Int", 0)
    }

    Sleep 80
    IME_SET(imeState)
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

