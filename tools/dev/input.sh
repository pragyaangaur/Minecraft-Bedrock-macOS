#!/bin/zsh
# input.sh <winput arguments>: bring the game window to the front and send one
# input with winput.exe from inside Wine. The game reads keys only while its
# window is frontmost. Examples:
#   input.sh hold 2000 0x57          walk forward for 2 s (W)
#   input.sh hold 3000 0x11 0x57     sprint forward for 3 s (Ctrl+W)
#   input.sh look 300 0              turn right
#   input.sh mouse l 1500            mine for 1.5 s
#   input.sh click 0.5 0.4           click at a fraction of the window size
#   input.sh type /gamemode_s        type text, with _ for a space
set -eu
source "${0:A:h}/../../scripts/common.sh"
export WINEPREFIX="${PREFIX:-$WINE_PREFIX_DIR}"
cp -f "$BUILD/stubs/winput.exe" "$WINEPREFIX/drive_c/winput.exe"
pid=$(ps -axo pid,command | grep -v grep | grep 'C:\\Minecraft\\Minecraft.Windows.exe' | head -1 | awk '{print $1}')
[[ -n $pid ]] || die "the game is not running"
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true" 2> /dev/null
WINEDEBUG=-all arch -x86_64 "$WINE_DIR/bin/wine" 'C:\winput.exe' "$@" 2> /dev/null
