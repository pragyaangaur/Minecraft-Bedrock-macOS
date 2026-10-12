#!/bin/zsh
# Build everything needed to run the Windows version of Minecraft Bedrock on
# this Mac, then prepare your copy of the game.
#
# Usage: ./setup.sh [--game <game folder from Windows> --dump <memory dump .dmp>]
#
# Without --game and --dump it only builds the tools (Wine, DXMT and the
# stand-in DLLs), which takes one to two hours the first time. With them it
# also copies the game into game/ and rebuilds the executable. Every step
# skips work that is already done, so it is safe to run again.
set -eu
source "${0:A:h}/scripts/common.sh"

game="" dump=""
while (( $# )); do
  case $1 in
    --game) game=$2; shift 2 ;;
    --dump) dump=$2; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
done
[[ -z $game && -z $dump ]] || [[ -n $game && -n $dump ]] || die "--game and --dump go together"

say "checking the requirements"
[[ $(uname -m) == arm64 ]] || die "this needs an Apple Silicon Mac"
arch -x86_64 /usr/bin/true 2> /dev/null || die "Rosetta 2 is missing. Install it with: softwareupdate --install-rosetta --agree-to-license"
xcode-select -p > /dev/null 2>&1 || die "the Xcode command line tools are missing. Install them with: xcode-select --install"
[[ -x $BREW/bin/brew ]] || die "Homebrew is missing, see https://brew.sh"
missing=()
for f in llvm lld mingw-w64 bison flex meson ninja cmake pkgconf python3; do
  [[ -e $BREW/opt/$f || -e $BREW/bin/$f ]] || missing+=$f
done
(( ${#missing} == 0 )) || die "missing Homebrew packages. Install them with: brew install ${${missing[*]}/python3/python}"
xcrun -f metal > /dev/null 2>&1 || die "Apple's Metal toolchain is missing. Install Xcode, then run: xcodebuild -downloadComponent MetalToolchain"

if [[ ! -x $VENV/bin/python ]]; then
  say "creating the Python environment"
  "$BREW/bin/python3" -m venv "$VENV"
fi
"$VENV/bin/pip" install -q -r "$ROOT/requirements.txt"

"$ROOT/scripts/build-deps.sh"
"$ROOT/scripts/build-wine.sh"
"$ROOT/scripts/build-dxmt.sh"
"$ROOT/stubs/build.sh"
"$ROOT/scripts/create-prefix.sh"
[[ -z $game ]] || "$ROOT/scripts/prepare-game.sh" "$game" "$dump"

if [[ -f $GAME_BUILD/Minecraft.Windows.exe ]]; then
  say "done. Double-click \"Play Minecraft.command\" or run tools/play_minecraft.sh to play."
else
  say "tools built. Run ./setup.sh --game <folder> --dump <file.dmp> next, see docs/getting-the-game-files.md."
fi
