#!/bin/zsh
# shot.sh <name>: save a screenshot of the game window as out/shots/<name>.png and
# a copy 1000 pixels wide as <name>_s.png, then print the path of the small one.
set -eu
source "${0:A:h}/../../scripts/common.sh"
finder="$BUILD/dev/find_window"
if [[ ! -x $finder ]]; then
  mkdir -p "$BUILD/dev"
  swiftc -O -o "$finder" "$ROOT/tools/dev/find_window.swift"
fi
id=$("$finder" | grep -o 'id=[0-9]*' | head -1 | cut -d= -f2)
[[ -n $id ]] || die "no game window"
mkdir -p "$LOGS/shots"
screencapture -x -l "$id" "$LOGS/shots/$1.png"
sips -Z 1000 "$LOGS/shots/$1.png" --out "$LOGS/shots/$1_s.png" > /dev/null
echo "$LOGS/shots/$1_s.png"
