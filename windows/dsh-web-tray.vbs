Option Explicit
' Launches the DSH Web tray controller without a console window.
Dim sh, fso, dir, ps1
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = dir & "\dsh-web-tray.ps1"
sh.Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """", 0, False
