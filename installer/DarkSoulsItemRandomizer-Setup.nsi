; =====================================================================
;  Dark Souls Item Randomizer - Windows installer (NSIS 3, Unicode)
;  Randomizer by HotPocketRemix:
;    https://github.com/HotPocketRemix/DarkSoulsItemRandomizer
;
;  What it automates (from the project's README):
;   * finds the Dark Souls Remastered (or unpacked PTDE) folder via Steam
;   * copies DarkSoulsItemRandomizer.exe next to the game executable
;   * creates shortcuts whose "Start in" folder is the game folder
;     (the randomizer looks for GameParam relative to its working dir)
;   * adds a "Restore original items" shortcut (.bak -> GameParam),
;     implemented as "<uninstaller> /RESTORE" so its messages are localized
;   * the uninstaller restores the original GameParam automatically
;   * optional Windows Firewall rule that blocks the game from going
;     online (removed only on uninstall) + an "offline safety" info page
;   * 10 UI languages, chosen at startup (English preselected)
;
;  Build (from this folder, i.e. <repo>/installer):
;      makensis DarkSoulsItemRandomizer-Setup.nsi
;  Uses the repo's ../dist/DarkSoulsItemRandomizer.exe and ../favicon.ico,
;  plus lang/*.nsh (one file of strings per language).
;  Output: DarkSoulsItemRandomizer-Setup.exe in this folder (git-ignored).
; =====================================================================

Unicode true
SetCompressor /SOLID lzma
RequestExecutionLevel admin          ; game usually lives under Program Files

!define APPNAME     "Dark Souls Item Randomizer"
!define APPVER      "0.3"
!define PUBLISHER   "HotPocketRemix"
!define RANDO_EXE   "DarkSoulsItemRandomizer.exe"
!define RANDO_SRC   "../dist/${RANDO_EXE}"      ; randomizer build inside the repo
!define ICON_SRC    "../favicon.ico"
!define OLD_RESTORE_CMD "RestoreOriginalItems.cmd"   ; shipped by v1, removed on uninstall
!define UNINST_EXE  "DarkSoulsItemRandomizer-Uninstall.exe"
!define LANG_KEY    "Software\DarkSoulsItemRandomizer"
!define UNINST_KEY  "Software\Microsoft\Windows\CurrentVersion\Uninstall\DarkSoulsItemRandomizer"
!define DSR_APPID   "570940"
!define PTDE_APPID  "211420"
!define GP_DIR      "param\GameParam"
!define FW_RULE     "Dark Souls Item Randomizer - block online"   ; fixed, language-independent

Name "${APPNAME}"
OutFile "DarkSoulsItemRandomizer-Setup.exe"
; Trailing backslash = the Browse button won't append a folder name
InstallDir "$PROGRAMFILES32\Steam\steamapps\common\DARK SOULS REMASTERED\"
ShowInstDetails show
ShowUninstDetails show
BrandingText "${APPNAME} ${APPVER} - installer"

VIProductVersion "0.3.0.0"
VIAddVersionKey "ProductName"     "${APPNAME} Installer"
VIAddVersionKey "FileDescription" "${APPNAME} Installer"
VIAddVersionKey "FileVersion"     "${APPVER}"
VIAddVersionKey "ProductVersion"  "${APPVER}"
VIAddVersionKey "LegalCopyright"  "Randomizer (c) ${PUBLISHER}"

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "WordFunc.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"
!include "nsDialogs.nsh"

Var StartMenuDir

; ---------------------------------------------------------------- UI --
!define MUI_ICON   "${ICON_SRC}"
!define MUI_UNICON "${ICON_SRC}"
!define MUI_ABORTWARNING

; Language picker shown at startup; remembers the last choice
!define MUI_LANGDLL_ALWAYSSHOW
!define MUI_LANGDLL_REGISTRY_ROOT      HKLM
!define MUI_LANGDLL_REGISTRY_KEY       "${LANG_KEY}"
!define MUI_LANGDLL_REGISTRY_VALUENAME "InstallerLanguage"
!define MUI_LANGDLL_WINDOWTITLE "Dark Souls Item Randomizer"
!define MUI_LANGDLL_INFO "Please select a language."

!define MUI_WELCOMEPAGE_TITLE "${APPNAME}"
!define MUI_WELCOMEPAGE_TEXT  "$(TXT_WelcomeText)"
!insertmacro MUI_PAGE_WELCOME

!define MUI_DIRECTORYPAGE_TEXT_TOP "$(TXT_DirTop)"
!define MUI_DIRECTORYPAGE_TEXT_DESTINATION "$(TXT_DirDest)"
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE DirLeave
!insertmacro MUI_PAGE_DIRECTORY

Page custom OfflinePageShow

!define MUI_COMPONENTSPAGE_NODESC
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "$(TXT_RunNow)"
!define MUI_FINISHPAGE_RUN_FUNCTION LaunchRandomizer
!define MUI_FINISHPAGE_TEXT "$(TXT_FinishText)"
!define MUI_FINISHPAGE_TEXT_LARGE
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

;  English is first = fallback language and preselected in the picker.
;  To add a language: create lang/<MUI name>.nsh and add a line below.
!macro AddLanguage NAME
  !insertmacro MUI_LANGUAGE "${NAME}"
  !include "lang/${NAME}.nsh"
!macroend
!insertmacro AddLanguage "English"
!insertmacro AddLanguage "Italian"
!insertmacro AddLanguage "Spanish"
!insertmacro AddLanguage "French"
!insertmacro AddLanguage "German"
!insertmacro AddLanguage "PortugueseBR"
!insertmacro AddLanguage "Russian"
!insertmacro AddLanguage "Polish"
!insertmacro AddLanguage "Japanese"
!insertmacro AddLanguage "SimpChinese"
!insertmacro MUI_RESERVEFILE_LANGDLL

; ======================================================== detection ==
; A candidate folder is valid if it has a game exe + a GameParam file.
; Push <dir> ; Call IsGameDir ; Pop <"1"|"0">
Function IsGameDir
  Exch $0
  Push $1
  StrCpy $1 "0"
  ${If} ${FileExists} "$0\DarkSoulsRemastered.exe"
  ${OrIf} ${FileExists} "$0\DARKSOULS.exe"
    ${If} ${FileExists} "$0\${GP_DIR}\GameParam.parambnd.dcx"
    ${OrIf} ${FileExists} "$0\${GP_DIR}\GameParam.parambnd"
      StrCpy $1 "1"
    ${EndIf}
  ${EndIf}
  StrCpy $0 $1
  Pop $1
  Exch $0
FunctionEnd

; Extract the text between the first pair of double quotes.
; Push <string> ; Call FirstQuoted ; Pop <result or "">
Function FirstQuoted
  Exch $0          ; input
  Push $1          ; index
  Push $2          ; char
  Push $3          ; result
  Push $4          ; state 0=before, 1=inside
  StrCpy $1 0
  StrCpy $3 ""
  StrCpy $4 0
  ${Do}
    StrCpy $2 $0 1 $1
    ${If} $2 == ""
      ${ExitDo}
    ${EndIf}
    ${If} $2 == '"'
      ${If} $4 == 0
        StrCpy $4 1
      ${Else}
        ${ExitDo}
      ${EndIf}
    ${ElseIf} $4 == 1
      StrCpy $3 "$3$2"
    ${EndIf}
    IntOp $1 $1 + 1
  ${Loop}
  StrCpy $0 $3
  Pop $4
  Pop $3
  Pop $2
  Pop $1
  Exch $0
FunctionEnd

; Look in one Steam library for DSR, then PTDE.  Sets $R9 when found.
; Push <library root> ; Call CheckSteamLibrary
Function CheckSteamLibrary
  Exch $0
  ${If} $R9 == ""
    Push "$0\steamapps\common\DARK SOULS REMASTERED"
    Call IsGameDir
    Pop $1
    ${If} $1 == "1"
      StrCpy $R9 "$0\steamapps\common\DARK SOULS REMASTERED"
    ${Else}
      Push "$0\steamapps\common\Dark Souls Prepare to Die Edition\DATA"
      Call IsGameDir
      Pop $1
      ${If} $1 == "1"
        StrCpy $R9 "$0\steamapps\common\Dark Souls Prepare to Die Edition\DATA"
      ${EndIf}
    ${EndIf}
  ${EndIf}
  Pop $0
FunctionEnd

; Result in $R9 ("" if not found)
Function DetectGame
  StrCpy $R9 ""

  ; 1) Steam writes an uninstall entry per game with InstallLocation
  ${If} ${RunningX64}
    SetRegView 64
  ${EndIf}
  ReadRegStr $0 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App ${DSR_APPID}" "InstallLocation"
  ${If} $0 == ""
    SetRegView 32
    ReadRegStr $0 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App ${DSR_APPID}" "InstallLocation"
  ${EndIf}
  ${If} $0 != ""
    Push $0
    Call IsGameDir
    Pop $1
    ${If} $1 == "1"
      StrCpy $R9 $0
    ${EndIf}
  ${EndIf}

  ${If} $R9 == ""
    SetRegView 32
    ReadRegStr $0 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App ${PTDE_APPID}" "InstallLocation"
    ${If} $0 != ""
      Push "$0\DATA"
      Call IsGameDir
      Pop $1
      ${If} $1 == "1"
        StrCpy $R9 "$0\DATA"
      ${EndIf}
    ${EndIf}
  ${EndIf}
  SetRegView default

  ; 2) Steam root + every library listed in libraryfolders.vdf
  ${If} $R9 == ""
    ReadRegStr $2 HKCU "Software\Valve\Steam" "SteamPath"
    ${If} $2 == ""
      SetRegView 32
      ReadRegStr $2 HKLM "Software\Valve\Steam" "InstallPath"
      SetRegView default
    ${EndIf}
    ${If} $2 != ""
      ${WordReplace} $2 "/" "\" "+" $2          ; SteamPath uses forward slashes
      Push $2
      Call CheckSteamLibrary

      ClearErrors
      FileOpen $3 "$2\steamapps\libraryfolders.vdf" r
      ${IfNot} ${Errors}
        ${Do}
          ${If} $R9 != ""
            ${ExitDo}
          ${EndIf}
          ClearErrors
          FileRead $3 $4
          ${If} ${Errors}
            ${ExitDo}
          ${EndIf}
          ; new format:  "path"   "D:\\SteamLibrary"
          ${WordFind} $4 '"path"' "E+1}" $5
          ${IfNot} ${Errors}
            Push $5
            Call FirstQuoted
            Pop $5
            ${If} $5 != ""
              ${WordReplace} $5 "\\" "\" "+" $5  ; unescape VDF backslashes
              Push $5
              Call CheckSteamLibrary
            ${EndIf}
          ${EndIf}
        ${Loop}
        FileClose $3
      ${EndIf}
    ${EndIf}
  ${EndIf}

  ; 3) Common default locations
  ${If} $R9 == ""
    Push "$PROGRAMFILES32\Steam"
    Call CheckSteamLibrary
  ${EndIf}
FunctionEnd

; ============================================================ events ==
Function .onInit
  StrCpy $LANGUAGE ${LANG_ENGLISH}     ; default selection in the picker
  !insertmacro MUI_LANGDLL_DISPLAY     ; (a remembered choice overrides it)
  Call DetectGame
  ${If} $R9 != ""
    StrCpy $INSTDIR $R9
  ${EndIf}
FunctionEnd

Function DirLeave
  Push $INSTDIR
  Call IsGameDir
  Pop $0
  ${If} $0 != "1"
    ${If} ${FileExists} "$INSTDIR\DARKSOULS.exe"
      MessageBox MB_OK|MB_ICONEXCLAMATION "$(TXT_PtdePacked)"
    ${Else}
      MessageBox MB_OK|MB_ICONEXCLAMATION "$(TXT_BadDir)"
    ${EndIf}
    Abort
  ${EndIf}
FunctionEnd

; "Play offline safely" info page (between folder and components pages)
Function OfflinePageShow
  !insertmacro MUI_HEADER_TEXT "$(TXT_OffTitle)" "$(TXT_OffSub)"
  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}
  ${NSD_CreateLabel} 0 0 100% 100% "$(TXT_OffBody)"
  Pop $1
  nsDialogs::Show
FunctionEnd

; Remove every firewall rule with our name (all directions / programs)
!macro RemoveFirewallRule
  nsExec::ExecToLog '"$SYSDIR\netsh.exe" advfirewall firewall delete rule name="${FW_RULE}"'
  Pop $0
!macroend

; Add in+out block rules for one game executable.  $R7 = "fail" on error
!macro AddFirewallRule EXE DIR
  ${If} ${FileExists} "$INSTDIR\${EXE}"
    nsExec::ExecToLog '"$SYSDIR\netsh.exe" advfirewall firewall add rule name="${FW_RULE}" dir=${DIR} action=block program="$INSTDIR\${EXE}" enable=yes profile=any'
    Pop $0
    ${If} $0 != 0
      StrCpy $R7 "fail"
    ${EndIf}
  ${EndIf}
!macroend

Function LaunchRandomizer
  ; The randomizer resolves GameParam from its working directory,
  ; so it must be started from the game folder.
  SetOutPath "$INSTDIR"
  Exec '"$INSTDIR\${RANDO_EXE}"'
FunctionEnd

; ========================================================== sections ==
Section "!$(SEC_Core_Name)" SecCore
  SectionIn RO
  SetOutPath "$INSTDIR"
  SetOverwrite on
  File "${RANDO_SRC}"
  WriteUninstaller "$INSTDIR\${UNINST_EXE}"

  ; Entry in Settings > Apps
  ${If} ${RunningX64}
    SetRegView 64
  ${EndIf}
  WriteRegStr   HKLM "${UNINST_KEY}" "DisplayName"     "${APPNAME}"
  WriteRegStr   HKLM "${UNINST_KEY}" "DisplayVersion"  "${APPVER}"
  WriteRegStr   HKLM "${UNINST_KEY}" "Publisher"       "${PUBLISHER}"
  WriteRegStr   HKLM "${UNINST_KEY}" "DisplayIcon"     "$INSTDIR\${RANDO_EXE}"
  WriteRegStr   HKLM "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr   HKLM "${UNINST_KEY}" "URLInfoAbout"    "https://github.com/HotPocketRemix/DarkSoulsItemRandomizer"
  WriteRegStr   HKLM "${UNINST_KEY}" "UninstallString" '"$INSTDIR\${UNINST_EXE}"'
  WriteRegStr   HKLM "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\${UNINST_EXE}" /S'
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "EstimatedSize" 8600
  SetRegView default
SectionEnd

Section "$(SEC_Firewall_Name)" SecFirewall
  StrCpy $R7 ""
  !insertmacro RemoveFirewallRule                 ; idempotent on reinstall
  !insertmacro AddFirewallRule "DarkSoulsRemastered.exe" out
  !insertmacro AddFirewallRule "DarkSoulsRemastered.exe" in
  !insertmacro AddFirewallRule "DARKSOULS.exe" out
  !insertmacro AddFirewallRule "DARKSOULS.exe" in
  ${If} $R7 == "fail"
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(TXT_FwFail)" /SD IDOK
  ${Else}
    WriteRegDWORD HKLM "${LANG_KEY}" "FirewallRule" 1
  ${EndIf}
SectionEnd

Section "$(SEC_StartM_Name)" SecStartMenu
  SetShellVarContext all
  StrCpy $StartMenuDir "$SMPROGRAMS\${APPNAME}"
  CreateDirectory "$StartMenuDir"
  SetOutPath "$INSTDIR"           ; = "Start in" of the shortcuts below
  CreateShortCut "$StartMenuDir\${APPNAME}.lnk"   "$INSTDIR\${RANDO_EXE}"
  CreateShortCut "$StartMenuDir\$(LNK_Restore).lnk" "$INSTDIR\${UNINST_EXE}" "/RESTORE" "$SYSDIR\shell32.dll" 238
  CreateShortCut "$StartMenuDir\$(LNK_Folder).lnk"  "$INSTDIR"
  CreateShortCut "$StartMenuDir\$(LNK_Uninst).lnk"  "$INSTDIR\${UNINST_EXE}"
SectionEnd


Section "$(SEC_Desktop_Name)" SecDesktop
  SetShellVarContext all
  SetOutPath "$INSTDIR"
  CreateShortCut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\${RANDO_EXE}"
SectionEnd

; ========================================================= uninstall ==
; Restore one GameParam variant from its .bak.  $R8: 0 none, 1 ok, 2 fail
; KEEP=1 leaves the .bak in place (restore shortcut), 0 removes it (uninstall)
!macro RestoreVariant FILE KEEP
  ${If} ${FileExists} "$INSTDIR\${GP_DIR}\${FILE}.bak"
    ClearErrors
    CopyFiles /SILENT "$INSTDIR\${GP_DIR}\${FILE}.bak" "$INSTDIR\${GP_DIR}\${FILE}"
    ${If} ${Errors}
      StrCpy $R8 2
    ${Else}
      ${If} ${KEEP} == 0
        Delete "$INSTDIR\${GP_DIR}\${FILE}.bak"
      ${EndIf}
      DetailPrint "Restored ${GP_DIR}\${FILE}"
      ${If} $R8 != 2
        StrCpy $R8 1
      ${EndIf}
    ${EndIf}
  ${EndIf}
!macroend

Function un.onInit
  ; Uninstaller lives in the game folder, so $INSTDIR is already right.
  !insertmacro MUI_UNGETLANGUAGE

  ; "Restore original items" shortcut: <uninstaller> /RESTORE
  ${GetParameters} $0
  ClearErrors
  ${GetOptions} $0 "/RESTORE" $1
  ${IfNot} ${Errors}
    StrCpy $R8 0
    !insertmacro RestoreVariant "GameParam.parambnd.dcx" 1
    !insertmacro RestoreVariant "GameParam.parambnd" 1
    ${If} $R8 == 1
      MessageBox MB_OK|MB_ICONINFORMATION "$(UN_Restored)$\r$\n$\r$\n$(UN_Reminder)" /SD IDOK
    ${ElseIf} $R8 == 2
      MessageBox MB_OK|MB_ICONEXCLAMATION "$(UN_RestoreFail)" /SD IDOK
    ${Else}
      MessageBox MB_OK|MB_ICONINFORMATION "$(UN_NoBak)" /SD IDOK
    ${EndIf}
    Quit
  ${EndIf}
FunctionEnd

Section "Uninstall"
  StrCpy $R8 0
  !insertmacro RestoreVariant "GameParam.parambnd.dcx" 0
  !insertmacro RestoreVariant "GameParam.parambnd" 0
  ${If} $R8 == 1
    DetailPrint "$(UN_Restored)"
  ${ElseIf} $R8 == 2
    ; Keep everything installed so the user can retry after closing the game
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(UN_RestoreFail)" /SD IDOK
    Abort
  ${Else}
    MessageBox MB_OK|MB_ICONINFORMATION "$(UN_NoBak)" /SD IDOK
  ${EndIf}

  ; Optional: generated seed folders (random-seed-YYYY-MM-DD--...)
  FindFirst $0 $1 "$INSTDIR\random-seed-*"
  ${If} $1 != ""
    MessageBox MB_YESNO|MB_ICONQUESTION "$(UN_AskSeeds)" /SD IDNO IDNO seeds_done
    ${Do}
      ${If} $1 == ""
        ${ExitDo}
      ${EndIf}
      ${If} ${FileExists} "$INSTDIR\$1\*.*"
        RMDir /r "$INSTDIR\$1"
      ${EndIf}
      FindNext $0 $1
    ${Loop}
  seeds_done:
  ${EndIf}
  FindClose $0

  ; Lift the online block only now, together with the GameParam restore
  !insertmacro RemoveFirewallRule
  DetailPrint "Firewall rule removed: ${FW_RULE}"

  Delete "$INSTDIR\${RANDO_EXE}"
  Delete "$INSTDIR\${OLD_RESTORE_CMD}"
  Delete "$INSTDIR\${UNINST_EXE}"

  SetShellVarContext all
  Delete "$DESKTOP\${APPNAME}.lnk"
  RMDir /r "$SMPROGRAMS\${APPNAME}"

  ${If} ${RunningX64}
    SetRegView 64
  ${EndIf}
  DeleteRegKey HKLM "${UNINST_KEY}"
  SetRegView default
  DeleteRegKey HKLM "${LANG_KEY}"

  MessageBox MB_OK|MB_ICONINFORMATION "$(UN_Reminder)" /SD IDOK
SectionEnd
