#!/bin/zsh
# Start the game for a normal play session. Run ./setup.sh once before this.
#
# Usage: [HUD=1] [LOG=full] [PLAYER_NAME=name] [LIMIT=seconds] tools/play_minecraft.sh
#
# HUD=1 shows Apple's Metal performance HUD (frame rate and GPU time) in the
# top right corner. Logging is warn+seh, which keeps the game's own messages
# and Wine's "Unhandled page fault" line if it crashes. LOG=full uses +seh,
# which also traces every std::uncaught_exceptions() call. That is tens of
# thousands of lines a second in a world and costs frame rate. The session
# stops after LIMIT seconds, eight hours by default.
#
# Wine's output goes to out/wine_play_<date>_<time>.log. The game's content
# log is in prefix/drive_c/users/<you>/AppData/Roaming/Minecraft Bedrock/logs.
set -eu
source "${0:A:h}/../scripts/common.sh"

"$ROOT/scripts/create-prefix.sh" > /dev/null
wineserver_cmd -k 2> /dev/null || true
[[ ${HUD:-0} == 1 ]] && export MTL_HUD_ENABLED=1
debug='warn+seh'
[[ ${LOG:-} == full ]] && debug='+seh'
TAG=play exec "$ROOT/tools/run_wine.sh" "$debug" "${LIMIT:-28800}"
