#!/bin/zsh
# Run the game once under WineGDK and write Wine's output to a log in out/.
#
# Usage: [PREFIX=dir] [TAG=name] [EXE=file] [XCURL=hang] [AUDIO=off]
#        tools/run_wine.sh [WINEDEBUG channels] [seconds before the game is stopped]
#
# PREFIX picks another Wine prefix (the default is prefix/). TAG is added to
# the log name. EXE runs another rebuilt executable, such as the trace build.
# XCURL=hang uses the offline XCurl whose requests never complete. AUDIO=off
# disables Wine's CoreAudio driver, so the game sees no sound device.
#
# drive_c/Minecraft is rebuilt on each run from symlinks into game/, with the
# rebuilt executable from build/game and the stand-in DLLs
# from build/stubs placed beside them so that they win over the originals.
set -eu
source "${0:A:h}/../scripts/common.sh"

export WINEPREFIX="${PREFIX:-$WINE_PREFIX_DIR}"
export WINEDEBUG="${1:-+loaddll,+seh,+module}"
limit="${2:-60}"
wine=("$WINE_DIR/bin/wine")
run="$WINEPREFIX/drive_c/Minecraft"
system32="$WINEPREFIX/drive_c/windows/system32"

[[ -x $wine[1] ]] || die "Wine is not built yet. Run ./setup.sh first."
[[ -f $GAME_BUILD/Minecraft.Windows.exe ]] || die "the game is not prepared yet. Run ./setup.sh with --game and --dump."

rm -rf "$run" && mkdir -p "$run"
for f in "$GAME"/*(N); do
  case "${f:t}" in
    Minecraft.Windows.exe|XCurl.dll|dumps|.DS_Store) ;;
    *) ln -s "$f" "$run/${f:t}" ;;
  esac
done
ln -s "${EXE:-$GAME_BUILD/Minecraft.Windows.exe}" "$run/Minecraft.Windows.exe"
for d in "$BUILD"/stubs/*.dll(N); do ln -sf "$d" "$run/${d:t}"; done
[[ ${XCURL:-} == hang ]] && ln -sf "$BUILD/stubs/hang/XCurl.dll" "$run/XCurl.dll"

[[ -d $system32 ]] || WINEDLLOVERRIDES="mscoree,mshtml=" WINEDEBUG=-all arch -x86_64 $wine wineboot --init > /dev/null 2>&1

# Wine loads builtin DLLs from the copies it put in system32 when the prefix
# was created, so the patched and DXMT DLLs are copied there on every start.
for d in xgameruntime d3d11 dxgi d3d10core winemetal winhttp gameinput mmdevapi ntdll ws2_32; do
  cp "$WINE_DIR/lib/wine/x86_64-windows/$d.dll" "$system32/$d.dll"
done

# Prefer DXMT's Direct3D DLLs, never start the debugger on a crash, and skip
# the Mono and Gecko installers.
export WINEDLLOVERRIDES="d3d11,dxgi,d3d10core=n,b;winedbg.exe=d;mscoree,mshtml=${AUDIO:+;winecoreaudio.drv=d}${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
WINEDEBUG=-all arch -x86_64 $wine reg delete 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\AeDebug' /v Debugger /f > /dev/null 2>&1 || true

mkdir -p "$LOGS"
log="$LOGS/wine${TAG:+_$TAG}_$(date +%Y%m%d_%H%M%S).log"
echo "logging to ${log#$ROOT/} (WINEDEBUG=$WINEDEBUG, ${limit}s limit)"
cd "$run"
( arch -x86_64 $wine 'C:\Minecraft\Minecraft.Windows.exe' > "$log" 2>&1 ) &
pid=$!
for i in {1..$limit}; do kill -0 $pid 2> /dev/null || break; sleep 1; done
kill -0 $pid 2> /dev/null && { echo "still running after ${limit}s, stopping it"; arch -x86_64 "$WINE_DIR/bin/wineserver" -k; }
wait $pid 2> /dev/null || true
echo "log: $(wc -l < "$log") lines"
