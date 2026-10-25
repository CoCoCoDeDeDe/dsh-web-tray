Option Explicit
' Starts the dsh web server inside WSL with no console window.
Dim sh
Set sh = CreateObject("WScript.Shell")
sh.Run """C:\Windows\System32\wsl.exe"" -d Ubuntu -u yanyifan -- /home/yanyifan/.local/bin/dsh-web start", 0, False
