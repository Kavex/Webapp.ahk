﻿#NoEnv

FileRead,data,webapp.json
j:=JSON_ToObj(data)


__Webapp_Name := j.name
__Webapp_Width := j.width
__Webapp_height := j.height
__Webapp_protocol := j.protocol
__Webapp_protocol_call:=Func(j.protocol_call)
__Webapp_html_url := getFileFullPath("index.html")


OnExit,GuiClose
Gui Margin, 0, 0
Gui +LastFound +Resize
OnMessage(0x100, "gui_KeyDown", 2)
Gui Add, ActiveX, v__Webapp_wb w%__Webapp_Width% h%__Webapp_height%, Shell.Explorer
__Webapp_wb.silent := true ;Surpress JS Error boxes
__Webapp_wb.Navigate("file://" . __Webapp_html_url)
ComObjConnect(__Webapp_wb, __Webapp_wb_events)
__Webapp_w := __Webapp_wb.Document.parentWindow
__Webapp_w.AHK := Func("JS_AHK")
;Wait for IE to load the page, before we connect the event handlers
while __Webapp_wb.readystate != 4 or __Webapp_wb.busy
	sleep 10

Gui Show, w%__Webapp_Width% h%__Webapp_height%, %__Webapp_Name%
gosub,_AppStart
return

GuiSize:
    GuiControl, Move, __Webapp_wb, W%A_GuiWidth% H%A_GuiHeight%
return

GuiEscape:
	MsgBox 0x34, Webapp.ahk, Are you sure you want to quit?
	IfMsgBox No
		return
GuiClose:
	Gui Destroy
	ExitApp
return

class __Webapp_wb_events
{
	;for more events and other, see http://msdn.microsoft.com/en-us/library/aa752085
	
	NavigateComplete2(wb) { ;blocked all navigation, we want our own stuff happening
		wb.Stop()
	}
	DownloadComplete(wb, NewURL) {
		wb.Stop()
	}
	DocumentComplete(wb, NewURL) {
		wb.Stop()
	}
	
	BeforeNavigate2(wb, NewURL)
	{
		wb.Stop() ;blocked all navigation, we want our own stuff happening
		
		global __Webapp_protocol
		global __Webapp_protocol_call
        
        ;parse the url
		if (InStr(NewURL,__Webapp_protocol "://")==1) { ;if url starts with "myapp://"
			what := SubStr(NewURL,Strlen(__Webapp_protocol)+4) ;get stuff after "myapp://"
			__Webapp_protocol_call.call(what)
		}
		;else do nothing
	}
}



;javascript:AHK('Func') --> Func()
JS_AHK(func, prms*) {
	wb := getDOM()
	; Stop navigation prior to calling the function, in case it uses Exit.
	wb.Stop(),  %func%(prms*)
}

getWindow() {
	wb := getDOM()
	return wb.document.parentWindow
}

getDOM(){
    global __Webapp_wb
    return __Webapp_wb
}

ErrorExit(errMsg) {
	MsgBox 16, Webapp.ahk, %errMsg%
	ExitApp 1
}

;{ other stuff

GetErrorMessage(error_code="") {
	VarSetCapacity(buf, 1024) ; Probably won't exceed 1024 chars.
	if DllCall("FormatMessage", "uint", 0x1200, "ptr", 0, "int", error_code!=""
		? error_code : A_LastError, "uint", 1024, "str", buf, "uint", 1024, "ptr", 0)
	return buf
}

getFileFullPath(f) {
    Loop, Files, %f%
    {
        if (A_LoopFileLongPath)
            return A_LoopFileLongPath    
    }
}

_InitUI() {
    local w
    SetWBClientSite()
    ;gosub DefineUI
    wb.Silent := true
    wb.Navigate("about:blank")
    while wb.ReadyState != 4 {
        Sleep 10
        if (A_TickCount-initTime > 2000)
            throw 1
    }
    wb.Document.open()
    wb.Document.write(html)
    wb.Document.close()
    w := wb.Document.parentWindow
    if !w || !w.initOptions
        throw 1
    w.AHK := Func("JS_AHK")
    if (!CurrentType && A_ScriptDir != DefaultPath)
        CurrentName := ""  ; Avoid showing the Reinstall option since we don't know which version it was.
    w.initOptions(CurrentName, CurrentVersion, CurrentType
                , ProductVersion, DefaultPath, DefaultStartMenu
                , DefaultType, A_Is64bitOS = 1)
    if (A_ScriptDir = DefaultPath) {
        w.installdir.disabled := true
        w.installdir_browse.disabled := true
        w.installcompiler.disabled := !DefaultCompiler
        w.installcompilernote.style.display := "block"
        w.ci_nav_install.innerText := "apply"
        w.install_button.innerText := "Apply"
        w.extract.style.display := "None"
        w.opt1.disabled := true
        w.opt1.firstChild.innerText := "Checking for updates..."
    }
    w.installcompiler.checked := DefaultCompiler
    w.enabledragdrop.checked := DefaultDragDrop
    w.separatebuttons.checked := DefaultIsHostApp
    ; w.defaulttoutf8.checked := DefaultToUTF8
    if !A_Is64bitOS
        w.it_x64.style.display := "None"
    if A_OSVersion in WIN_2000,WIN_2003,WIN_XP ; i.e. not WIN_7, WIN_8 or a future OS.
        w.separatebuttons.parentNode.style.display := "none"
    ;w.switchPage("start")
    w.document.body.focus()
    ; Scale UI by screen DPI.  My testing showed that Vista with IE7 or IE9
    ; did not scale by default, but Win8.1 with IE10 did.  The scaling being
    ; done by the control itself = deviceDPI / logicalDPI.
    logicalDPI := w.screen.logicalXDPI, deviceDPI := w.screen.deviceXDPI
    if (A_ScreenDPI != 96)
        w.document.body.style.zoom := A_ScreenDPI/96 * (logicalDPI/deviceDPI)
    ;if (A_ScriptDir = DefaultPath)
    ;    CheckForUpdates()
}

/*  Complex workaround to override "Active scripting" setting
 *  and ensure scripts can run within the WebBrowser control.
 */

global WBClientSite

SetWBClientSite()
{
    interfaces := {
    (Join,
        IOleClientSite: [0,3,1,0,1,0]
        IServiceProvider: [3]
        IInternetSecurityManager: [1,1,3,4,8,7,3,3]
    )}
    unkQI      := RegisterCallback("WBClientSite_QI", "Fast")
    unkAddRef  := RegisterCallback("WBClientSite_AddRef", "Fast")
    unkRelease := RegisterCallback("WBClientSite_Release", "Fast")
    WBClientSite := {_buffers: bufs := {}}, bufn := 0, 
    for name, prms in interfaces
    {
        bufn += 1
        bufs.SetCapacity(bufn, (4 + prms.MaxIndex()) * A_PtrSize)
        buf := bufs.GetAddress(bufn)
        NumPut(unkQI,       buf + 1*A_PtrSize)
        NumPut(unkAddRef,   buf + 2*A_PtrSize)
        NumPut(unkRelease,  buf + 3*A_PtrSize)
        for i, prmc in prms
            NumPut(RegisterCallback("WBClientSite_" name, "Fast", prmc+1, i), buf + (3+i)*A_PtrSize)
        NumPut(buf + A_PtrSize, buf + 0)
        WBClientSite[name] := buf
    }
    global wb
    if pOleObject := ComObjQuery(wb, "{00000112-0000-0000-C000-000000000046}")
    {   ; IOleObject::SetClientSite
        DllCall(NumGet(NumGet(pOleObject+0)+3*A_PtrSize), "ptr"
            , pOleObject, "ptr", WBClientSite.IOleClientSite, "uint")
        ObjRelease(pOleObject)
    }
}

WBClientSite_QI(p, piid, ppvObject)
{
    static IID_IUnknown := "{00000000-0000-0000-C000-000000000046}"
    static IID_IOleClientSite := "{00000118-0000-0000-C000-000000000046}"
    static IID_IServiceProvider := "{6d5140c1-7436-11ce-8034-00aa006009fa}"
    iid := _String4GUID(piid)
    if (iid = IID_IOleClientSite || iid = IID_IUnknown)
    {
        NumPut(WBClientSite.IOleClientSite, ppvObject+0)
        return 0 ; S_OK
    }
    if (iid = IID_IServiceProvider)
    {
        NumPut(WBClientSite.IServiceProvider, ppvObject+0)
        return 0 ; S_OK
    }
    NumPut(0, ppvObject+0)
    return 0x80004002 ; E_NOINTERFACE
}

WBClientSite_AddRef(p)
{
    return 1
}

WBClientSite_Release(p)
{
    return 1
}

WBClientSite_IOleClientSite(p, p1="", p2="", p3="")
{
    if (A_EventInfo = 3) ; GetContainer
    {
        NumPut(0, p1+0) ; *ppContainer := NULL
        return 0x80004002 ; E_NOINTERFACE
    }
    return 0x80004001 ; E_NOTIMPL
}

WBClientSite_IServiceProvider(p, pguidService, piid, ppvObject)
{
    static IID_IUnknown := "{00000000-0000-0000-C000-000000000046}"
    static IID_IInternetSecurityManager := "{79eac9ee-baf9-11ce-8c82-00aa004ba90b}"
    if (_String4GUID(pguidService) = IID_IInternetSecurityManager)
    {
        iid := _String4GUID(piid)
        if (iid = IID_IInternetSecurityManager || iid = IID_IUnknown)
        {
            NumPut(WBClientSite.IInternetSecurityManager, ppvObject+0)
            return 0 ; S_OK
        }
        NumPut(0, ppvObject+0)
        return 0x80004002 ; E_NOINTERFACE
    }
    NumPut(0, ppvObject+0)
    return 0x80004001 ; E_NOTIMPL
}

WBClientSite_IInternetSecurityManager(p, p1="", p2="", p3="", p4="", p5="", p6="", p7="", p8="")
{
    if (A_EventInfo = 5) ; ProcessUrlAction
    {
        if (p2 = 0x1400) ; dwAction = URLACTION_SCRIPT_RUN
        {
            NumPut(0, p3+0)  ; *pPolicy := URLPOLICY_ALLOW
            return 0 ; S_OK
        }
    }
    return 0x800C0011 ; INET_E_DEFAULT_ACTION
}

_String4GUID(pGUID)
{
	VarSetCapacity(String,38*2)
	DllCall("ole32\StringFromGUID2", "ptr", pGUID, "str", String, "int", 39)
	Return	String
}


/*  Fix keyboard shortcuts in WebBrowser control.
 *  References:
 *    http://www.autohotkey.com/community/viewtopic.php?p=186254#p186254
 *    http://msdn.microsoft.com/en-us/library/ms693360
 */

gui_KeyDown(wParam, lParam, nMsg, hWnd) {
    global wb
    if (Chr(wParam) ~= "[A-Z]" || wParam = 0x74) ; Disable Ctrl+O/L/F/N and F5.
        return
    pipa := ComObjQuery(wb, "{00000117-0000-0000-C000-000000000046}")
    VarSetCapacity(kMsg, 48), NumPut(A_GuiY, NumPut(A_GuiX
    , NumPut(A_EventInfo, NumPut(lParam, NumPut(wParam
    , NumPut(nMsg, NumPut(hWnd, kMsg)))), "uint"), "int"), "int")
    Loop 2
    r := DllCall(NumGet(NumGet(1*pipa)+5*A_PtrSize), "ptr", pipa, "ptr", &kMsg)
    ; Loop to work around an odd tabbing issue (it's as if there
    ; is a non-existent element at the end of the tab order).
    until wParam != 9 || wb.Document.activeElement != ""
    ObjRelease(pipa)
    if r = 0 ; S_OK: the message was translated to an accelerator.
        return 0
}

;}

;-----end-----