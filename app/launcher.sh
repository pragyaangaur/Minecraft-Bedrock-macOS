#!/bin/zsh
# The main executable of Bedrock Launcher.app.
#
# On the first start it asks for the game folder and the memory dump from a
# Windows PC and prepares them, then it starts the game. Everything it writes
# goes to ~/Library/Application Support/Bedrock Launcher. The scripts it runs
# are the same ones as in the repository, shipped in Contents/Resources/repo.
set -u

app="${0:A:h:h:h}"
res="$app/Contents/Resources"
export MCB_DATA="$HOME/Library/Application Support/Bedrock Launcher"
export MCB_WINE="$res/wine"
export MCB_STUBS="$res/stubs"
export MCB_PYTHON="$res/python/bin/python3"
repo="$res/repo"
title="Bedrock Launcher"
guide="https://pragyaangaur.github.io/Minecraft-Bedrock-macOS/#get-the-files"
mkdir -p "$MCB_DATA/out"
log="$MCB_DATA/out/launcher.log"
exec >> "$log" 2>&1
print -r -- "--- $(date) $app"

# Show a dialog with the given buttons, the last one being the default, and
# print the button that was pressed. It fails when the user presses "Quit".
ask() {
  local text=$1; shift
  local buttons="\"${(j:", ":)@}\""
  local answer
  answer=$(osascript -e "button returned of (display dialog \"$text\" with title \"$title\" buttons {$buttons} default button \"${@[-1]}\" with icon note)") || return 1
  [[ $answer != Quit ]] && print -r -- "$answer"
}
notify() { osascript -e "display notification \"$1\" with title \"$title\"" > /dev/null 2>&1; }
fail() {
  print "error: $1"
  osascript -e "display alert \"$title\" message \"$1

The details are in $log.\" as critical" > /dev/null 2>&1
  exit 1
}

[[ $(uname -m) == arm64 ]] || fail "This app needs a Mac with Apple silicon (M1 or later)."
[[ $app == */AppTranslocation/* ]] && fail "Please drag Bedrock Launcher into your Applications folder first, then open it from there."

# Rosetta 2 runs the Windows parts, which are Intel code.
if ! arch -x86_64 /usr/bin/true 2> /dev/null; then
  ask "Bedrock Launcher needs Apple's Rosetta 2 to run Windows programs. Install it now? macOS will ask for your password." Quit Install > /dev/null || exit 0
  osascript -e 'do shell script "/usr/sbin/softwareupdate --install-rosetta --agree-to-license" with administrator privileges' \
    || fail "Rosetta 2 could not be installed."
fi

# A downloaded app is quarantined, and macOS then refuses to start the Wine
# programs inside it. Once the user has opened the app, clear the flag.
if xattr -p com.apple.quarantine "$app" > /dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$app" || fail "macOS did not let the app clear its download flag. Move it to the Applications folder and try again."
fi

if [[ ! -f $MCB_DATA/build/game/Minecraft.Windows.exe ]]; then
  choice=$(ask "Welcome! This app runs your own copy of Minecraft for Windows (Bedrock Edition) on this Mac.

It needs two things from a Windows PC on which you own the game. The first is the game folder. The second is a memory dump of the game, taken at the title screen. The guide shows how to get both in about 15 minutes." Quit "Open the guide" "I have both") || exit 0
  if [[ $choice == "Open the guide" ]]; then
    open "$guide"
    exit 0
  fi

  game=$(osascript -e 'POSIX path of (choose folder with prompt "Choose the game folder you copied from Windows. It has a file called layout.xml and a folder called data.")') || exit 0
  [[ -f $game/layout.xml ]] || fail "That folder has no layout.xml, so it is not the game folder. The guide shows which folder to copy."
  dump=$(osascript -e 'POSIX path of (choose file with prompt "Choose the memory dump of the game. Its name ends in .dmp.")') || exit 0

  name=$(osascript -e "text returned of (display dialog \"Choose a player name. You can change it later in the game's settings.\" with title \"$title\" default answer \"$USER\")") || exit 0
  export PLAYER_NAME="${name:-$USER}"

  notify "Preparing the game. This takes about five minutes, and the game starts by itself when it is done."
  "$repo/scripts/prepare-game.sh" "$game" "$dump" || fail "Preparing the game failed."
fi

[[ -d $MCB_DATA/prefix/drive_c ]] || notify "Setting up Windows for the first time. This takes about a minute."
"$repo/tools/play_minecraft.sh" || fail "The game stopped with an error."
