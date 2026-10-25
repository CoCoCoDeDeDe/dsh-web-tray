Option Explicit
' Starts the dsh web server inside WSL with no console window.
' The distro, user, script path and port come from dsh-web-tray.config.ps1,
' which install.sh generates for this machine.

Dim fso, sh, appDir, cfgPath, logPath
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
appDir = fso.GetParentFolderName(WScript.ScriptFullName)
cfgPath = appDir & "\dsh-web-tray.config.ps1"
logPath = appDir & "\autostart-error.log"

Function Fail(msg)
    On Error Resume Next
    Dim f
    Set f = fso.OpenTextFile(logPath, 8, True)
    f.WriteLine "[" & Now & "] " & msg
    f.Close
    WScript.Quit 1
End Function

Function ReadConfig(path)
    Dim d, re, line, m, f
    Set d = CreateObject("Scripting.Dictionary")
    d.CompareMode = 1
    Set re = New RegExp
    re.Pattern = "^\s*\$script:(\w+)\s*=\s*'([^']*)'"
    re.IgnoreCase = True
    Set f = fso.OpenTextFile(path, 1)
    Do Until f.AtEndOfStream
        line = f.ReadLine
        If re.Test(line) Then
            Set m = re.Execute(line)
            d(m(0).SubMatches(0)) = m(0).SubMatches(1)
        End If
    Loop
    f.Close
    Set ReadConfig = d
End Function

Function CfgOr(d, key, fallback)
    If d.Exists(key) Then
        If Len(Trim(d(key))) > 0 Then
            CfgOr = Trim(d(key))
            Exit Function
        End If
    End If
    CfgOr = fallback
End Function

Dim cfg, distro, wslUser, script, port, cmd

If Not fso.FileExists(cfgPath) Then
    Fail "missing config: " & cfgPath
End If

Set cfg = ReadConfig(cfgPath)
distro = CfgOr(cfg, "Distro", "")
wslUser = CfgOr(cfg, "WslUser", "")
script = CfgOr(cfg, "WslScript", "")
port = CfgOr(cfg, "WebPort", "3080")

If distro = "" Or wslUser = "" Or script = "" Then
    Fail "incomplete config: " & cfgPath
End If
If InStr(script, " ") > 0 Then
    Fail "WslScript contains a space; not supported: " & script
End If

cmd = """" & sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\wsl.exe"" -d " & _
      distro & " -u " & wslUser & " -- /usr/bin/env DSH_WEB_PORT=" & port & _
      " " & script & " start"
sh.Run cmd, 0, False
