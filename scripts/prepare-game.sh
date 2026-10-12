#!/bin/zsh
# Copy the Windows game files into game/ and rebuild a runnable executable.
#
# Usage: scripts/prepare-game.sh <game folder from Windows> <memory dump .dmp>
#
# The executable in the Store and GDK install is encrypted on disk, so it is
# rebuilt from a full-memory dump of the running game instead. See
# docs/getting-the-game-files.md for how to make both inputs.
set -eu
source "${0:A:h}/common.sh"

(( $# == 2 )) || die "usage: scripts/prepare-game.sh <game folder> <dump.dmp>"
src="${1:A}" dump="${2:A}"
py=("$PYTHON" -I)
[[ -f $src/layout.xml ]] || die "$src does not look like the game folder (no layout.xml)"
[[ -f $dump ]] || die "no dump at $dump"
[[ -x $py[1] ]] || die "the Python environment is missing. Run ./setup.sh first."

version=$(grep -o 'Identity Name="Microsoft.MinecraftUWP"[^>]*Version="[^"]*"' "$src/appxmanifest.xml" | grep -o 'Version="[^"]*"' | cut -d'"' -f2 || true)
say "game version ${version:-unknown}"
[[ $version == 1.26.5203.0 ]] || print -P "%F{yellow}warning:%f this was only tested with 1.26.5203.0. Other versions may need new addresses in the tools."

if [[ $src != ${GAME:A} ]]; then
  say "copying the game files into game/"
  mkdir -p "$GAME"
  rsync -a --exclude Minecraft.Windows.exe "$src/" "$GAME/"
fi

say "checking the copy against layout.xml"
if ! report=$("${py[@]}" "$ROOT/tools/check_layout.py" "$GAME"); then
  print -P "%F{yellow}warning:%f ${report##*$'\n'}. Run .venv/bin/python tools/check_layout.py game to list them, and copy them again from Windows if you can."
fi

mkdir -p "$GAME_BUILD"
say "rebuilding the executable from the dump"
"${py[@]}" "$ROOT/tools/extract_module.py" "$dump" Minecraft.Windows.exe "$GAME_BUILD/Minecraft.Windows.dumped.exe"
"${py[@]}" "$ROOT/tools/make_loadable.py" "$GAME_BUILD/Minecraft.Windows.dumped.exe" "$GAME_BUILD/Minecraft.Windows.loadable.exe"
"${py[@]}" "$ROOT/tools/clean_data.py" "$GAME_BUILD/Minecraft.Windows.loadable.exe" "$dump" "$GAME_BUILD/Minecraft.Windows.exe"
rm -f "$GAME_BUILD"/Minecraft.Windows.{dumped,loadable}.exe "$GAME_BUILD"/Minecraft.Windows.dumped.exe.mem

say "guarding FMOD's mixer against a divide by zero"
"${py[@]}" "$ROOT/tools/patch_fmod.py" "$GAME/fmod.dll" "$GAME_BUILD/fmod.dll" > /dev/null

if [[ ! -f $GAME/data/skin_packs/vanilla/skins.json || ! -f $GAME/data/skin_packs/persona/skins.json ]]; then
  say "data/skin_packs is missing, writing stand-ins"
  GAME="$GAME" "${py[@]}" "$ROOT/tools/make_skin_pack.py"
fi
say "game prepared"
