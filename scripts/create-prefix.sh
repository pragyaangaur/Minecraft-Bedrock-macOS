#!/bin/zsh
# Create the Wine prefix in prefix/ and give it an offline player profile.
set -eu
source "${0:A:h}/common.sh"

[[ -x $WINE_DIR/bin/wine ]] || die "build Wine first (scripts/build-wine.sh)"
if [[ ! -d $WINE_PREFIX_DIR/drive_c/windows/system32 ]]; then
  say "creating the Wine prefix (about a minute)"
  WINEDLLOVERRIDES="mscoree,mshtml=" wine_cmd wineboot --init > /dev/null 2>&1
  wineserver_cmd -w
fi

# Without a persona profile the game never draws the local player (no hand,
# no body, an empty figure in the inventory). Offline it cannot fetch one, so
# seed the profile of one of the default characters.
games="$WINE_PREFIX_DIR/drive_c/users/$USER/AppData/Roaming/Minecraft Bedrock/Users/Shared/games/com.mojang"
mkdir -p "$games/minecraftpe"
[[ -f $games/ud1544803905_fb.dat ]] || cp "$ROOT/stubs/seed/ud1544803905_fb.dat" "$games/"

# The game picks a 41 chunk render distance on a 16 GB Mac, which keeps the
# frame rate near 26. Start new installs at 12 chunks, which runs near 100.
# It can be changed in the game later.
"$VENV/bin/python" -I "$ROOT/tools/options.py" "$games/minecraftpe/options.txt" gfx_viewdistance=192
say "prefix ready in $WINE_PREFIX_DIR"
