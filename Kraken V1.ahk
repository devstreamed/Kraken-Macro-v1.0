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

global running := false
global capW := 0, capH := 0, hdcMem := 0, hbm := 0, pBits := 0
global baseBuf := 0, curBuf := 0

; presets live in AppData so they can always be written
global presetDir := A_AppData "\Kraken V1"
global presetFile := presetDir "\presets.txt"

global gui1 := Gui("+AlwaysOnTop +Resize +0x200000", "Kraken V1")
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
        }
    }
    return data
}
