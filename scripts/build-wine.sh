#!/bin/zsh
# Fetch WineGDK at the pinned commit, apply patches/wine-gdk, build it for
# x86_64 and install it into build/wine. WineGDK is Wine with an
# implementation of the Xbox GDK runtime (xgameruntime.dll), which the Windows
# version of Minecraft Bedrock needs.
set -eu
source "${0:A:h}/common.sh"
use_build_alias

SRC="$BUILD/src/wine-gdk"
OBJ="$BUILD/wine-build"
DEPS_PREFIX="$BUILD/deps"

if [[ -x $WINE_DIR/bin/wine && -f $WINE_DIR/.patched-$WINEGDK_COMMIT ]]; then
  say "Wine already built"
  exit 0
fi

if [[ ! -d $SRC/.git ]]; then
  say "fetching WineGDK"
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin "$WINEGDK_URL"
fi
git -C "$SRC" fetch -q --depth 1 origin "$WINEGDK_COMMIT"
git -C "$SRC" checkout -q --force --detach FETCH_HEAD
git -C "$SRC" clean -qfdx
patches=("$ROOT"/patches/wine-gdk/*.patch)
say "applying ${#patches} patches"
for p in $patches; do
  git -C "$SRC" apply --whitespace=nowarn "$p" || die "patch ${p:t} does not apply"
done

mkdir -p "$OBJ"
cd "$OBJ"
if [[ ! -f Makefile ]]; then
  say "configuring Wine (a few minutes)"
  x86 "$SRC/configure" --prefix="$WINE_DIR" --enable-archs=x86_64 \
    CC="clang -arch x86_64" CXX="clang++ -arch x86_64" \
    CFLAGS="-g -O2 -I$DEPS_PREFIX/include" LDFLAGS="-L$DEPS_PREFIX/lib -Wl,-rpath,@loader_path/../.." \
    PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig" \
    FREETYPE_CFLAGS="-I$DEPS_PREFIX/include/freetype2" FREETYPE_LIBS="-L$DEPS_PREFIX/lib -lfreetype" \
    GNUTLS_CFLAGS="-I$DEPS_PREFIX/include" GNUTLS_LIBS="-L$DEPS_PREFIX/lib -lgnutls" \
    --without-gstreamer --without-sdl --without-cups --without-sane --without-krb5 \
    --without-netapi --without-pcap --without-usb --without-v4l2 --without-capi \
    --without-gphoto --without-x --without-wayland --without-pulse --without-alsa \
    --without-oss --without-udev --without-inotify --without-vulkan --without-opencl \
    --without-ffmpeg > "$OBJ/setup-configure.log" 2>&1 || die "configure failed, see $OBJ/setup-configure.log"
fi
say "building Wine (this is the long step, 20 to 40 minutes)"
x86 make -j"$JOBS" > "$OBJ/setup-make.log" 2>&1 || die "build failed, see $OBJ/setup-make.log"
x86 make install > "$OBJ/setup-install.log" 2>&1 || die "install failed, see $OBJ/setup-install.log"

# Wine's unix libraries (lib/wine/x86_64-unix) load GnuTLS and FreeType
# through the @loader_path/../.. rpath added above, which is build/wine/lib.
cp -f "$DEPS_PREFIX"/lib/lib{gmp.10,nettle.8,hogweed.6,gnutls.30,freetype.6}.dylib "$WINE_DIR/lib/"
touch "$WINE_DIR/.patched-$WINEGDK_COMMIT"
say "Wine installed in $WINE_DIR"
