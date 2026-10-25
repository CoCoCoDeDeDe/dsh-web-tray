#!/usr/bin/env bash
# Deploy dsh-web-tray to WSL and the Windows user profile.
#
# Usage:
#   ./install.sh              # deploy, keep the running tray untouched
#   ./install.sh --restart    # deploy and restart the tray
#
# Environment:
#   DSH_WIN_APPDIR   Windows app dir in WSL form
#                    (default: %LOCALAPPDATA%\DSH resolved via PowerShell)
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WSL_BIN_DIR="${HOME}/.local/bin"

PS_EXE="$(command -v powershell.exe || true)"
if [[ -z "$PS_EXE" && -x "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" ]]; then
  PS_EXE="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
fi
if [[ -z "$PS_EXE" ]]; then
  echo "powershell.exe not found; WSL interop is required." >&2
  exit 1
fi

if [[ -z "${DSH_WIN_APPDIR:-}" ]] && command -v wslpath >/dev/null 2>&1; then
  win_local="$("$PS_EXE" -NoProfile -Command '$env:LOCALAPPDATA' | tr -d '\r')"
  if [[ -n "$win_local" ]]; then
    DSH_WIN_APPDIR="$(wslpath -u "$win_local")/DSH"
  fi
fi
DSH_WIN_APPDIR="${DSH_WIN_APPDIR:-/mnt/c/Users/13282/AppData/Local/DSH}"

echo "repo:       $ROOT"
echo "WSL:        $WSL_BIN_DIR/dsh-web"
echo "Windows:    $DSH_WIN_APPDIR"
echo "PowerShell: $PS_EXE"

mkdir -p "$WSL_BIN_DIR" "$DSH_WIN_APPDIR"
install -m 755 "$ROOT/bin/dsh-web" "$WSL_BIN_DIR/dsh-web"

cp "$ROOT/windows/dsh-web-tray.ps1" "$DSH_WIN_APPDIR/"
cp "$ROOT/windows/dsh-web-tray.vbs" "$DSH_WIN_APPDIR/"
cp "$ROOT/windows/dsh-web-autostart.vbs" "$DSH_WIN_APPDIR/"
cp "$ROOT/windows/install.ps1" "$DSH_WIN_APPDIR/"
cp "$ROOT/windows/README.txt" "$DSH_WIN_APPDIR/"
cp "$ROOT/windows/icons/"*.ico "$DSH_WIN_APPDIR/"

win_app_win="$(wslpath -w "$DSH_WIN_APPDIR")"
ps_args=()
if [[ "${1:-}" == "--restart" ]]; then
  ps_args+=("-Restart")
fi
"$PS_EXE" -NoProfile -ExecutionPolicy Bypass -File "${win_app_win}\\install.ps1" "${ps_args[@]}"

echo
echo "Done. Shortcuts: desktop and Start Menu -> DSH Web Tray"
echo "If the tray is not running, launch it from the desktop shortcut."
