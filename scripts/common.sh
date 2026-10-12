# Shared settings for the setup and run scripts. Source it from zsh.
#
# Everything the scripts build or download goes under build/. The Windows
# game files go under game/ and the Wine prefix under prefix/. All three are
# ignored by git.

ROOT="${${(%):-%x}:A:h:h}"
BUILD="$ROOT/build"
GAME="$ROOT/game"
GAME_BUILD="$BUILD/game"
WINE_PREFIX_DIR="$ROOT/prefix"
WINE_DIR="$BUILD/wine"
LOGS="$ROOT/out"
VENV="$ROOT/.venv"

# Pinned upstream sources. The patches in patches/ apply to exactly these.
WINEGDK_URL="https://github.com/Weather-OS/WineGDK.git"
WINEGDK_COMMIT="b03ba49c4f326c36aa6930fbe6cf72841ef3738c"
DXMT_URL="https://github.com/3Shain/dxmt.git"
DXMT_TAG="v0.80"
LLVM_URL="https://github.com/llvm/llvm-project.git"
LLVM_TAG="llvmorg-15.0.7"

BREW="${HOMEBREW_PREFIX:-/opt/homebrew}"
JOBS="$(sysctl -n hw.ncpu)"

say() { print -P "%F{cyan}==>%f $*"; }
die() { print -P "%F{red}error:%f $*" >&2; exit 1; }

# Run a command as x86_64 with Homebrew's bison and flex first on the PATH.
x86() { arch -x86_64 /usr/bin/env PATH="$BREW/opt/bison/bin:$BREW/opt/flex/bin:$BREW/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$@"; }

wine_cmd() { WINEPREFIX="$WINE_PREFIX_DIR" WINEDEBUG=-all arch -x86_64 "$WINE_DIR/bin/wine" "$@"; }
wineserver_cmd() { WINEPREFIX="$WINE_PREFIX_DIR" arch -x86_64 "$WINE_DIR/bin/wineserver" "$@"; }
