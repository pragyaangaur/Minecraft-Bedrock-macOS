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

# Offline there is no gamertag, so the game would use an untranslated
# character name. A 12 chunk render distance keeps the frame rate near 100;
# the game picks 41 on a 16 GB Mac. Both can be changed in the game later.
# The game always starts in a window. When it starts in fullscreen it keeps
# drawing at the window size, so the picture is stretched and clicks land
# below the cursor. Pressing F11 in the game switches to fullscreen correctly.
"$PYTHON" -I "$ROOT/tools/options.py" "$games/minecraftpe/options.txt" \
  "mp_username=${PLAYER_NAME:-$USER}" gfx_viewdistance=192 gfx_fullscreen:=0
say "prefix ready in $WINE_PREFIX_DIR"
