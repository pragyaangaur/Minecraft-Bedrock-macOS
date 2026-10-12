# Shared settings for the setup and run scripts. Source it from zsh.
#
# Everything the scripts build or download goes under build/. The Windows
# game files go under game/ and the Wine prefix under prefix/. All three are
# ignored by git.
#
# The Mac app runs these scripts from inside its bundle. It sets MCB_DATA to a
# folder in Application Support for the game, the prefix and the logs, and
# MCB_WINE, MCB_STUBS and MCB_PYTHON to the copies it ships.

ROOT="${${(%):-%x}:A:h:h}"
DATA="${MCB_DATA:-$ROOT}"
BUILD="$DATA/build"
GAME="$DATA/game"
GAME_BUILD="$BUILD/game"
WINE_PREFIX_DIR="$DATA/prefix"
WINE_DIR="${MCB_WINE:-$BUILD/wine}"
STUBS_DIR="${MCB_STUBS:-$BUILD/stubs}"
LOGS="$DATA/out"
VENV="$ROOT/.venv"
PYTHON="${MCB_PYTHON:-$VENV/bin/python}"

# Pinned upstream sources. The patches in patches/ apply to exactly these.
WINEGDK_URL="https://github.com/Weather-OS/WineGDK.git"
WINEGDK_COMMIT="b03ba49c4f326c36aa6930fbe6cf72841ef3738c"
DXMT_URL="https://github.com/3Shain/dxmt.git"
DXMT_TAG="v0.80"
LLVM_URL="https://github.com/llvm/llvm-project.git"
LLVM_TAG="llvmorg-15.0.7"

# Wine runs as x86_64 under Rosetta 2, so its dependencies must be x86_64 too.
# Each entry is the URL and the SHA-256 of a tarball whose GPG signature was checked.
DEPS=(
  "https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898"
  "https://ftp.gnu.org/gnu/nettle/nettle-3.10.tar.gz b4c518adb174e484cb4acea54118f02380c7133771e7e9beb98a0787194ee47c"
  "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.13.tar.xz ffed8ec1bf09c2426d4f14aae377de4753b53e537d685e604e99a8b16ca9c97e"
  "https://download.savannah.gnu.org/releases/freetype/freetype-2.14.3.tar.xz 36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f"
)

BREW="${HOMEBREW_PREFIX:-/opt/homebrew}"
JOBS="$(sysctl -n hw.ncpu)"

say() { print -P "%F{cyan}==>%f $*"; }
die() { print -P "%F{red}error:%f $*" >&2; exit 1; }

# Run a command as x86_64 with Homebrew's bison and flex first on the PATH.
x86() { arch -x86_64 /usr/bin/env PATH="$BREW/opt/bison/bin:$BREW/opt/flex/bin:$BREW/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$@"; }

wine_cmd() { WINEPREFIX="$WINE_PREFIX_DIR" WINEDEBUG=-all arch -x86_64 "$WINE_DIR/bin/wine" "$@"; }
wineserver_cmd() { WINEPREFIX="$WINE_PREFIX_DIR" arch -x86_64 "$WINE_DIR/bin/wineserver" "$@"; }
