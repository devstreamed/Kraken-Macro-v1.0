;@Ahk2Exe-SetName Kraken V1
;@Ahk2Exe-SetDescription Kraken V1
;@Ahk2Exe-SetVersion 1.0.0
;@Ahk2Exe-UpdateManifest 1

#Requires AutoHotkey v2.0
#SingleInstance Force

; Roblox ignores clicks from non-admin scripts, so relaunch as admin
if !A_IsAdmin {
    try Run('*RunAs "' A_ScriptFullPath '"')
    ExitApp
}

CoordMode "Pixel", "Screen"
CoordMode "Mouse", "Screen"
SendMode "Event"
SetMouseDelay 10

; ===== Kraken V1: Cast + Scan (new GUI) + Shake (Triads + regular shakes) =====
; F3 = Start / Stop     F5 = Refresh (reload)     F1 = Close
; Phase 1: Casting | Phase 2: Shaking | Phase 3: Finished, restarting loop
; Triads = the first 3 shake clicks of every cast (their own settings)

; ---------- credit tag ----------
global CREDIT := Chr(68) Chr(101) Chr(118) Chr(83) Chr(116) Chr(114) Chr(101) Chr(97) Chr(109) Chr(101) Chr(100)
CreditOK() {
    total := 0
    for ch in StrSplit(CREDIT)
        total += Ord(ch)
    return (total = 1108 && StrLen(CREDIT) = 11)
}
if !CreditOK() {
    MsgBox "The credit tag was modified. This macro will not run without it."
    ExitApp
}

global running := false
global capW := 0, capH := 0, hdcMem := 0, hbm := 0, pBits := 0
global baseBuf := 0, curBuf := 0

; presets live in AppData so they can always be written
global presetDir := A_AppData "\Kraken V1"
global presetFile := presetDir "\presets.txt"

global gui1 := Gui("+AlwaysOnTop +Resize +0x200000", "Kraken V1 - by " CREDIT)
gui1.SetFont("s9")

AddRow(label, default, sec := false) {
    gui1.Add("Text", (sec ? "Section" : "xs") " w225", label)
    return gui1.Add("Edit", "x+5 yp w75", default)
}

AddCoords() {
    gui1.Add("Text", "xs w16 h22 +0x200", "X")
    ex := gui1.Add("Edit", "x+2 yp w50", "")
    gui1.Add("Text", "x+8 yp w16 h22 +0x200", "Y")
    ey := gui1.Add("Edit", "x+2 yp w50", "")
    gui1.Add("Text", "x+8 yp w16 h22 +0x200", "W")
    ew := gui1.Add("Edit", "x+2 yp w50", "")
    gui1.Add("Text", "x+8 yp w16 h22 +0x200", "H")
    eh := gui1.Add("Edit", "x+2 yp w50", "")
    return [ex, ey, ew, eh]
}

; ---------- presets bar ----------
gui1.Add("Text", "xm w330", "Presets (pick one, or type a new name and press Save)")
cmbPreset := gui1.Add("ComboBox", "xm w330 r8")
saveBtn := gui1.Add("Button", "xm w105", "Save")
saveBtn.OnEvent("Click", (*) => SavePreset())
loadBtn := gui1.Add("Button", "x+5 yp w105", "Load")
loadBtn.OnEvent("Click", (*) => LoadPreset())
delBtn := gui1.Add("Button", "x+5 yp w105", "Delete")
delBtn.OnEvent("Click", (*) => DeletePreset())

stText := gui1.Add("Text", "xm y+10 w330 Center", "Status: STOPPED   |   F3 start/stop  F5 refresh  F1 close")
creditText := gui1.Add("Text", "xm w330 Center", "Made by " CREDIT)
creditText.SetFont("s9 bold")

tab := gui1.Add("Tab3", "xm y+10 w330 h300", ["Radar", "Casting", "Triads", "Fish"])

; ================= RADAR (the areas) =================
tab.UseTab(1)
gui1.Add("Text", "Section w300", "Cast area - cast is held at its center (empty = center of Roblox window)")
cc := AddCoords()
eCx := cc[1], eCy := cc[2], eCw := cc[3], eCh := cc[4]
selCastBtn := gui1.Add("Button", "xs w190", "Select cast area (drag)")
selCastBtn.OnEvent("Click", (*) => SelectArea(eCx, eCy, eCw, eCh, "2D8CFF"))
rstCastBtn := gui1.Add("Button", "x+5 yp w95", "Reset area")
rstCastBtn.OnEvent("Click", (*) => ResetArea(eCx, eCy, eCw, eCh))

gui1.Add("Text", "xs y+16 w300", "Shake scan area - where the shake is searched (empty = whole Roblox window)")
sc := AddCoords()
eAx := sc[1], eAy := sc[2], eAw := sc[3], eAh := sc[4]
selBtn := gui1.Add("Button", "xs w190", "Select shake area (drag)")
selBtn.OnEvent("Click", (*) => SelectArea(eAx, eAy, eAw, eAh, "FF2D2D"))
rstBtn := gui1.Add("Button", "x+5 yp w95", "Reset area")
rstBtn.OnEvent("Click", (*) => ResetArea(eAx, eAy, eAw, eAh))

chkShow := gui1.Add("Checkbox", "xs y+16", "Show area outlines (blue = cast, red = shake)")
chkShow.OnEvent("Click", (*) => UpdateOutline())

; ================= CASTING (cast settings) =================
tab.UseTab(2)
eCastHold := AddRow("Cast hold time (ms)", "600", true)
ePostCast := AddRow("Delay between Casting and Shaking (ms)", "1500")
eCycle    := AddRow("Delay before next cast (ms)", "2000")

; ================= TRIADS (first 3 shakes of each cast) =================
tab.UseTab(3)
chkTriad := gui1.Add("Checkbox", "Section Checked", "Enable Triads (first 3 shakes of every cast)")
eTScan  := AddRow("Triad scan interval (ms)", "30")
eTClick := AddRow("Triad delay before click (ms)", "40")
eTHold  := AddRow("Triad click hold time (ms)", "40")
eTNext  := AddRow("Triad delay before next click (ms)", "100")
gui1.Add("Text", "xs y+10 w300", "These only apply to the first 3 shake clicks of each cast. Every shake after that uses the Fish tab.")

; ================= FISH (the rest of the shake) =================
tab.UseTab(4)
eScan      := AddRow("Shake scan interval (ms)", "30", true)
eClick     := AddRow("Delay before shake click (ms)", "40")
eClickHold := AddRow("Shake click hold time (ms)", "40")
eNextClick := AddRow("Delay before next shake click (ms)", "100")
eTimeout   := AddRow("Stop after no new GUI for (ms)", "8000")
eSens      := AddRow("Sensitivity (0-765, higher = less)", "90")
eMin       := AddRow("Min new GUI size (samples)", "12")
eStep      := AddRow("Sample step (px, higher = faster)", "8")

tab.UseTab()

for ctrl in [eAx, eAy, eAw, eAh, eCx, eCy, eCw, eCh]
    ctrl.OnEvent("Change", (*) => UpdateOutline())

global fields := Map(
    "castHold", eCastHold, "postCast", ePostCast, "cycleDelay", eCycle,
    "triadOn", chkTriad, "triadScan", eTScan, "triadClickDelay", eTClick,
    "triadClickHold", eTHold, "triadNextDelay", eTNext,
    "scanInterval", eScan, "clickDelay", eClick, "clickHold", eClickHold,
    "nextClickDelay", eNextClick, "timeout", eTimeout, "sensitivity", eSens,
    "minSize", eMin, "step", eStep,
    "castX", eCx, "castY", eCy, "castW", eCw, "castH", eCh,
    "areaX", eAx, "areaY", eAy, "areaW", eAw, "areaH", eAh, "showOutline", chkShow)

gui1.OnEvent("Close", (*) => ExitApp())
global contentH := 0
gui1.OnEvent("Size", (*) => UpdateScroll())
OnMessage(0x115, OnVScroll)   ; scrollbar
OnMessage(0x20A, OnWheel)     ; mouse wheel
gui1.Show("AutoSize")
gui1.GetClientPos(, , , &fullH)
gui1.GetPos(&gx, , &gw, &gh)
contentH := fullH
gui1.Move(gx, 20, gw, Min(gh, A_ScreenHeight - 120))   ; fit the screen, scroll for the rest
UpdateScroll()
RefreshPresets()
SetTimer(CheckCredit, 1000)

; keeps the credit tag in place (restores it if it is changed or hidden)
CheckCredit() {
    if !CreditOK() {
        ExitApp
    }
    want := "Made by " CREDIT
    if (creditText.Value != want)
        creditText.Value := want
    if !creditText.Visible
        creditText.Visible := true
    title := "Kraken V1 - by " CREDIT
    if (gui1.Title != title)
        gui1.Title := title
}

; ---------- phase label (top of screen) ----------
global phaseGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
phaseGui.BackColor := "1E1E1E"
phaseGui.SetFont("s14 bold cWhite")
phaseText := phaseGui.Add("Text", "w460 Center", "Phase 1: Casting")

; ---------- area outlines (4 thin bars just outside each area) ----------
MakeBars(color) {
    arr := []
    Loop 4 {
        b := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
        b.BackColor := color
        arr.Push(b)
    }
    return arr
}
global barsShake := MakeBars("FF2D2D")
global barsCast := MakeBars("2D8CFF")

F3:: ToggleMacro()
F5:: Reload()
F1:: ExitApp()

ToggleMacro() {
    global running
    running := !running
    if running {
        phaseGui.Show("NA y8 x" ((A_ScreenWidth - 490) // 2))
        SetPhase(1)
        SetTimer(MacroLoop, -10)
    } else {
        phaseGui.Hide()
        stText.Value := "Status: STOPPED   |   F3 start"
    }
}

SetPhase(n) {
    txt := (n = 1) ? "Phase 1: Casting"
        : (n = 2) ? "Phase 2: Shaking"
        : "Phase 3: Finished, restarting loop"
    phaseText.Value := txt
    stText.Value := "Status: RUNNING   |   " txt
}

; ---------- presets (own simple file format, saved in AppData\Kraken V1) ----------
LoadAllPresets() {
    data := Map()
    data.CaseSense := "Off"
    if !FileExist(presetFile)
        return data
    cur := ""
    for line in StrSplit(FileRead(presetFile, "UTF-8"), "`n", "`r") {
        line := Trim(line)
        if (line = "")
            continue
        if (SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]") {
            cur := SubStr(line, 2, StrLen(line) - 2)
            data[cur] := Map()
        } else if (cur != "") {
            p := InStr(line, "=")
            if (p > 1)
                data[cur][SubStr(line, 1, p - 1)] := SubStr(line, p + 1)
        }
    }
    return data
}

WriteAllPresets(data) {
    DirCreate presetDir
    out := ""
    for name, kv in data {
        out .= "[" name "]`n"
        for k, v in kv
            out .= k "=" v "`n"
        out .= "`n"
    }
    f := FileOpen(presetFile, "w", "UTF-8")
    f.Write(out)
    f.Close()
}

RefreshPresets() {
    cur := cmbPreset.Text
    cmbPreset.Delete()
    try {
        names := []
        for name in LoadAllPresets()
            names.Push(name)
        if (names.Length)
            cmbPreset.Add(names)
    }
    cmbPreset.Text := cur
}

SavePreset() {
    name := Trim(cmbPreset.Text)
    if (name = "") {
        stText.Value := "Type a preset name first, then press Save"
        return
    }
    if RegExMatch(name, "[\[\]=]") {
        stText.Value := "Preset names can't contain [ ] or ="
        return
    }
    try {
        data := LoadAllPresets()
        kv := Map()
        for key, ctrl in fields
            kv[key] := ctrl.Value
        data[name] := kv
        WriteAllPresets(data)
    } catch as err {
        MsgBox "Could not save the preset:`n" err.Message "`n`nFile: " presetFile
        return
    }
    RefreshPresets()
    cmbPreset.Text := name
    stText.Value := "Preset saved: " name
}

LoadPreset() {
    name := Trim(cmbPreset.Text)
    if (name = "") {
        stText.Value := "Pick a preset to load first"
        return
    }
    try {
        data := LoadAllPresets()
    } catch as err {
        MsgBox "Could not read the presets:`n" err.Message "`n`nFile: " presetFile
        return
    }
    if !data.Has(name) {
        stText.Value := "Preset not found: " name
        return
    }
    kv := data[name]
    for key, ctrl in fields {
        if !kv.Has(key)
            continue
        if (ctrl.Type = "Checkbox")
            ctrl.Value := (kv[key] = "1") ? 1 : 0
        else
            ctrl.Value := kv[key]
    }
    UpdateOutline()
    stText.Value := "Preset loaded: " name
}

DeletePreset() {
    name := Trim(cmbPreset.Text)
    if (name = "") {
        stText.Value := "Pick a preset to delete first"
        return
    }
    try {
        data := LoadAllPresets()
        if !data.Has(name) {
            stText.Value := "Preset not found: " name
            return
        }
        data.Delete(name)
        WriteAllPresets(data)
    } catch as err {
        MsgBox "Could not delete the preset:`n" err.Message
        return
    }
    cmbPreset.Text := ""
    RefreshPresets()
    stText.Value := "Preset deleted: " name
}

; ---------- scrolling for the main window ----------
UpdateScroll() {
    global contentH
    if (contentH <= 0)
        return
    gui1.GetClientPos(, , , &vh)
    si := Buffer(28, 0)
    NumPut("uint", 28, si, 0)
    NumPut("uint", 0xF, si, 4)            ; range | page | pos | disable-no-scroll
    NumPut("int", 0, si, 8)
    NumPut("int", contentH - 1, si, 12)
    NumPut("uint", vh, si, 16)
    NumPut("int", ScrollPos(), si, 20)
    DllCall("SetScrollInfo", "ptr", gui1.Hwnd, "int", 1, "ptr", si, "int", 1)
    maxPos := Max(0, contentH - vh)
    if (ScrollPos() > maxPos)
        ScrollTo(maxPos)
}

ScrollPos() {
    si := Buffer(28, 0)
    NumPut("uint", 28, si, 0)
    NumPut("uint", 0x4, si, 4)            ; SIF_POS
    DllCall("GetScrollInfo", "ptr", gui1.Hwnd, "int", 1, "ptr", si)
    return NumGet(si, 20, "int")
}

ScrollTo(newPos) {
    gui1.GetClientPos(, , , &vh)
    newPos := Max(0, Min(newPos, Max(0, contentH - vh)))
    cur := ScrollPos()
    if (newPos = cur)
        return
    DllCall("ScrollWindowEx", "ptr", gui1.Hwnd, "int", 0, "int", cur - newPos
        , "ptr", 0, "ptr", 0, "ptr", 0, "ptr", 0, "uint", 7)   ; scroll children + redraw
    si := Buffer(28, 0)
    NumPut("uint", 28, si, 0)
    NumPut("uint", 0x4, si, 4)
    NumPut("int", newPos, si, 20)
    DllCall("SetScrollInfo", "ptr", gui1.Hwnd, "int", 1, "ptr", si, "int", 1)
}

OnVScroll(wParam, lParam, msg, hwnd) {
    if (hwnd != gui1.Hwnd)
        return
    si := Buffer(28, 0)
    NumPut("uint", 28, si, 0)
    NumPut("uint", 0x17, si, 4)           ; range | page | pos | track pos
    DllCall("GetScrollInfo", "ptr", gui1.Hwnd, "int", 1, "ptr", si)
    page := NumGet(si, 16, "uint")
    pos := NumGet(si, 20, "int")
    track := NumGet(si, 24, "int")
    switch (wParam & 0xFFFF) {
        case 0: pos -= 30
        case 1: pos += 30
        case 2: pos -= page
        case 3: pos += page
        case 4, 5: pos := track
        case 6: pos := 0
        case 7: pos := contentH
    }
    ScrollTo(pos)
    return 0
}

OnWheel(wParam, lParam, msg, hwnd) {
    MouseGetPos , , &under
    if (under != gui1.Hwnd)
        return
    d := (wParam >> 16) & 0xFFFF
    if (d >= 0x8000)
        d -= 0x10000
    ScrollTo(ScrollPos() - (d // 120) * 60)
    return 0
}

Num(ctrl, fallback) {
    try
        return Integer(ctrl.Value)
    catch
        return fallback
}

; ---------- regions ----------
GetRegion(&l, &t, &w, &h) {
    if WinExist("ahk_exe RobloxPlayerBeta.exe")
        WinGetClientPos &l, &t, &w, &h, "ahk_exe RobloxPlayerBeta.exe"
    else {
        l := 0, t := 0, w := A_ScreenWidth, h := A_ScreenHeight
    }
}

GetScanArea(&sl, &st, &sw, &sh, wl, wt, ww, wh) {
    sw := Num(eAw, 0), sh := Num(eAh, 0)
    if (sw > 0 && sh > 0) {
        sl := Num(eAx, 0), st := Num(eAy, 0)
    } else {
        sl := wl, st := wt, sw := ww, sh := wh
    }
}

; cast position = center of the cast area (or center of the Roblox window)
GetCastPoint(&px, &py, wl, wt, ww, wh) {
    cw := Num(eCw, 0), ch := Num(eCh, 0)
    if (cw > 0 && ch > 0) {
        px := Num(eCx, 0) + cw // 2, py := Num(eCy, 0) + ch // 2
    } else {
        px := wl + ww // 2, py := wt + wh // 2
    }
}

ResetArea(ex, ey, ew, eh) {
    ex.Value := "", ey.Value := "", ew.Value := "", eh.Value := ""
    UpdateOutline()
}

UpdateOutline() {
    DrawBars(barsShake, eAx, eAy, eAw, eAh)
    DrawBars(barsCast, eCx, eCy, eCw, eCh)
}

DrawBars(arr, ex, ey, ew, eh) {
    w := Num(ew, 0), h := Num(eh, 0)
    if (!chkShow.Value || w <= 0 || h <= 0) {
        for b in arr
            b.Hide()
        return
    }
    x := Num(ex, 0), y := Num(ey, 0), t := 3
    arr[1].Show("NA x" (x - t) " y" (y - t) " w" (w + 2 * t) " h" t)
    arr[2].Show("NA x" (x - t) " y" (y + h) " w" (w + 2 * t) " h" t)
    arr[3].Show("NA x" (x - t) " y" y " w" t " h" h)
    arr[4].Show("NA x" (x + w) " y" y " w" t " h" h)
}

; drag a rectangle on screen to set an area (Esc = cancel)
SelectArea(ex, ey, ew, eh, color) {
    ToolTip "Drag with the left mouse button to select the area (Esc = cancel)"
    ov := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale")
    ov.BackColor := "000000"
    ov.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
    WinSetTransparent 60, "ahk_id " ov.Hwnd
    box := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
    box.BackColor := color

    Sleep 200
    while !GetKeyState("LButton", "P") {
        if GetKeyState("Escape", "P") {
            ToolTip
            ov.Destroy(), box.Destroy()
            return
        }
        Sleep 10
    }
    MouseGetPos &x1, &y1
    box.Show("NA x" x1 " y" y1 " w2 h2")
    WinSetTransparent 130, "ahk_id " box.Hwnd
    while GetKeyState("LButton", "P") {
        MouseGetPos &x2, &y2
        box.Move(Min(x1, x2), Min(y1, y2), Abs(x2 - x1) + 2, Abs(y2 - y1) + 2)
        Sleep 10
    }
    MouseGetPos &x2, &y2
    ToolTip
    ov.Destroy(), box.Destroy()

    w := Abs(x2 - x1), h := Abs(y2 - y1)
    if (w > 5 && h > 5) {
        ex.Value := Min(x1, x2), ey.Value := Min(y1, y2)
        ew.Value := w, eh.Value := h
        UpdateOutline()
    }
}

; ---------- screen capture (fast, in memory) ----------
InitCapture(w, h) {
    global capW, capH, hdcMem, hbm, pBits, baseBuf, curBuf
    if (capW = w && capH = h && hdcMem)
        return
    if hdcMem {
        DllCall("DeleteObject", "ptr", hbm)
        DllCall("DeleteDC", "ptr", hdcMem)
    }
    hdcS := DllCall("GetDC", "ptr", 0, "ptr")
    hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcS, "ptr")
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0)
    NumPut("int", w, bi, 4)
    NumPut("int", -h, bi, 8)
    NumPut("ushort", 1, bi, 12)
    NumPut("ushort", 32, bi, 14)
    pBits := 0
    hbm := DllCall("CreateDIBSection", "ptr", hdcS, "ptr", bi, "uint", 0, "ptr*", &pBits, "ptr", 0, "uint", 0, "ptr")
    DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcS)
    capW := w, capH := h
    baseBuf := Buffer(w * h * 4)
    curBuf := Buffer(w * h * 4)
}

Grab(l, t, w, h) {
    hdcS := DllCall("GetDC", "ptr", 0, "ptr")
    DllCall("BitBlt", "ptr", hdcMem, "int", 0, "int", 0, "int", w, "int", h
        , "ptr", hdcS, "int", l, "int", t, "uint", 0x00CC0020)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcS)
    DllCall("RtlMoveMemory", "ptr", curBuf, "ptr", pBits, "uptr", w * h * 4)
}

SaveBaseline(w, h) {
    DllCall("RtlMoveMemory", "ptr", baseBuf, "ptr", curBuf, "uptr", w * h * 4)
}

; ---------- scan: find a NEW GUI (something that wasn't there before) ----------
FindNewGui(w, h, &ox, &oy) {
    step := Max(2, Num(eStep, 8))
    sens := Num(eSens, 90)
    minArea := Num(eMin, 12)
    bs := step * 8
    xs := [], ys := []
    counts := Map()
    y := 0
    while y < h {
        row := y * w
        x := 0
        while x < w {
            off := (row + x) * 4
            a := NumGet(baseBuf, off, "uint")
            c := NumGet(curBuf, off, "uint")
            if (a != c) {
                d := Abs((a & 255) - (c & 255)) + Abs(((a >> 8) & 255) - ((c >> 8) & 255)) + Abs(((a >> 16) & 255) - ((c >> 16) & 255))
                if (d > sens) {
                    xs.Push(x), ys.Push(y)
                    k := (x // bs) * 10000 + (y // bs)
                    counts[k] := counts.Get(k, 0) + 1
                }
            }
            x += step
        }
        y += step
    }
    if (xs.Length < minArea)
        return false

    ; densest cluster of changes = the new GUI (ignores scattered noise)
    bestK := 0, best := 0
    for k, cnt in counts {
        if (cnt > best)
            best := cnt, bestK := k
    }
    mx := bestK // 10000, my := Mod(bestK, 10000)
    sx := 0, sy := 0, total := 0
    i := 1
    while i <= xs.Length {
        if (Abs(xs[i] // bs - mx) <= 1 && Abs(ys[i] // bs - my) <= 1)
            sx += xs[i], sy += ys[i], total++
        i++
    }
    if (total < minArea)
        return false
    ox := sx // total, oy := sy // total
    return true
}

; ---------- shake: click it ----------
ClickAt(x, y, beforeMs, holdMs) {
    MouseMove x, y, 0
    Sleep 15
    MouseMove x + 1, y + 1, 0
    MouseMove x, y, 0
    Sleep beforeMs
    Click "Down"
    Sleep holdMs
    Click "Up"
}

MacroLoop() {
    global running
    while running {
        if WinExist("ahk_exe RobloxPlayerBeta.exe")
            WinActivate
        GetRegion(&wl, &wt, &ww, &wh)

        ; ===== Phase 1: Casting (hold left mouse button inside the cast area) =====
        SetPhase(1)
        GetCastPoint(&px, &py, wl, wt, ww, wh)
        MouseMove px, py, 0
        Sleep 15
        MouseMove px + 1, py + 1, 0
        MouseMove px, py, 0
        Click "Down"
        Sleep Num(eCastHold, 600)
        Click "Up"
        Sleep Num(ePostCast, 1500)   ; delay between Casting and Shaking
        if !running
            break

        ; ===== Phase 2: Shaking (first 3 clicks = Triads, then regular shakes) =====
        SetPhase(2)
        GetScanArea(&sl, &st, &sw, &sh, wl, wt, ww, wh)
        InitCapture(sw, sh)
        Grab(sl, st, sw, sh)
        SaveBaseline(sw, sh)
        lastSeen := A_TickCount
        timeout := Num(eTimeout, 8000)
        shakeCount := 0
        while running && (A_TickCount - lastSeen < timeout) {
            Grab(sl, st, sw, sh)
            if FindNewGui(sw, sh, &cx, &cy) {
                lastSeen := A_TickCount
                if (chkTriad.Value && shakeCount < 3) {
                    stText.Value := "Status: RUNNING   |   Triad " (shakeCount + 1) "/3 - new GUI at " (sl + cx) ", " (st + cy)
                    ClickAt(sl + cx, st + cy, Num(eTClick, 40), Num(eTHold, 40))
                    Sleep Num(eTNext, 100)
                } else {
                    stText.Value := "Status: RUNNING   |   Shake - new GUI at " (sl + cx) ", " (st + cy)
                    ClickAt(sl + cx, st + cy, Num(eClick, 40), Num(eClickHold, 40))
                    Sleep Num(eNextClick, 100)
                }
                shakeCount++
            } else {
                SaveBaseline(sw, sh)
            }
            Sleep((chkTriad.Value && shakeCount < 3) ? Num(eTScan, 30) : Num(eScan, 30))
        }
        if !running
            break

        ; ===== Phase 3: Finished, restarting loop =====
        SetPhase(3)
        Sleep Num(eCycle, 2000)
    }
}
