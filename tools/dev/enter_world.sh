#!/bin/zsh
# enter_world.sh <tag> [seconds] [WINEDEBUG]: start the game in the background,
# open the first world on the Play screen (unless the game rejoins the last
# world by itself), wait for "Player Spawned", close the pause menu and print
# the log path. Other settings such as EXE or MTL_HUD_ENABLED=1 are passed on
# to tools/run_wine.sh. The game keeps running until the time limit.
set -eu
source "${0:A:h}/../../scripts/common.sh"
tag=$1 secs=${2:-1500} debug=${3:-+seh}
input="$ROOT/tools/dev/input.sh"
wineserver_cmd -k 2> /dev/null || true
sleep 2
TAG=$tag nohup "$ROOT/tools/run_wine.sh" "$debug" "$secs" > "$LOGS/$tag.out" 2>&1 &
sleep 3
log=$(ls -t "$LOGS"/wine_${tag}_*.log | head -1)
for i in {1..90}; do grep -aq "Time played notifier\|Player Spawned" "$log" && break; sleep 2; done
sleep 8
if ! grep -aq "Opening level" "$log"; then
  "$input" click 0.5 0.5 > /dev/null; sleep 5     # Play
  "$input" click 0.2 0.45 > /dev/null             # the first world tile
fi
for i in {1..90}; do grep -aq "Player Spawned\|Unhandled" "$log" && break; sleep 2; done
grep -aq "Unhandled" "$log" && die "the game crashed, see $log"
sleep 12
"$input" key 0x1B > /dev/null
sleep 2
echo "$log"
