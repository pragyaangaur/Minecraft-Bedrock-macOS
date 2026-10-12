#!/bin/zsh
# Build x86_64 copies of GMP, Nettle, GnuTLS and FreeType into build/deps.
# Wine loads GnuTLS for TLS (schannel) and FreeType for fonts. Homebrew on
# Apple Silicon only ships arm64 builds, which an x86_64 Wine cannot load.
set -eu
source "${0:A:h}/common.sh"

DEPS_PREFIX="$BUILD/deps"
SRC="$BUILD/deps-src"
WORK="$BUILD/deps-build"
mkdir -p "$SRC" "$WORK"

if [[ -f $DEPS_PREFIX/lib/libgnutls.30.dylib && -f $DEPS_PREFIX/lib/libfreetype.6.dylib ]]; then
  say "dependencies already built"
  exit 0
fi

for entry in $DEPS; do
  url="${entry%% *}"; sum="${entry##* }"; file="$SRC/${url:t}"
  [[ -f $file ]] || { say "downloading ${url:t}"; curl -fL --retry 3 -o "$file.part" "$url" && mv "$file.part" "$file"; }
  echo "$sum  $file" | shasum -a 256 -c --quiet || die "checksum mismatch for ${url:t}"
  tar -xf "$file" -C "$WORK"
done

common=(--host=x86_64-apple-darwin --build=aarch64-apple-darwin --prefix="$DEPS_PREFIX")
export CC="clang -arch x86_64" CXX="clang++ -arch x86_64"
export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig" CPPFLAGS="-I$DEPS_PREFIX/include" LDFLAGS="-L$DEPS_PREFIX/lib"

build() {  # build <source dir> <configure args...>
  local dir="$WORK/$1"; shift
  say "building ${dir:t}"
  ( cd "$dir" && x86 ./configure "${common[@]}" "$@" > "$dir/setup-configure.log" 2>&1 \
      && x86 make -j"$JOBS" > "$dir/setup-make.log" 2>&1 && x86 make install > "$dir/setup-install.log" 2>&1 ) \
    || die "building ${dir:t} failed, see the logs in $dir"
}

build gmp-6.3.0 --disable-assembly --enable-shared --enable-static
build nettle-3.10 --disable-documentation --disable-assembler --enable-shared --enable-static
build gnutls-3.8.13 --with-included-libtasn1 --with-included-unistring --without-p11-kit \
  --disable-doc --disable-tests --disable-tools --without-idn --without-brotli --without-zstd \
  --disable-guile --disable-cxx --disable-nls --disable-libdane --disable-openssl-compatibility \
  --disable-hardware-acceleration --enable-shared --enable-static=no
build freetype-2.14.3 --without-harfbuzz --without-png --without-bzip2 --without-brotli

say "dependencies installed in $DEPS_PREFIX"
