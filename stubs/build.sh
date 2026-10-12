#!/bin/zsh
# Build the stand-in DLLs in stubs/src into build/stubs.
# They are freestanding x64 Windows binaries with no C runtime, built with
# Homebrew's clang and lld. The import libraries come from the .def files.
set -eu
source "${0:A:h}/../scripts/common.sh"

LLVM="$BREW/opt/llvm/bin"
OUT="$BUILD/stubs"
LIBS="$OUT/lib"
mkdir -p "$LIBS" "$OUT/hang"

for def in "$ROOT"/stubs/lib/*.def; do
  "$LLVM/llvm-dlltool" -m i386:x86-64 -d "$def" -l "$LIBS/${def:t:r}.lib"
done

dll() {  # dll <source> <output> [extra clang flags]
  local src=$1 out=$2; shift 2
  "$LLVM/clang" --target=x86_64-pc-windows-msvc -O2 -ffreestanding -fno-stack-protector \
    -nostdlib -fuse-ld=lld -shared -Wl,/noentry -Wl,/nodefaultlib "$@" \
    -o "$out" "$src" "$LIBS/kernel32.lib" "$LIBS/combase.lib"
  rm -f "${out:r}.lib" "${out:r}.exp"
}

for c in "$ROOT"/stubs/src/*.c; do
  dll "$c" "$OUT/${c:t:r}.dll"
done
# A variant of the offline XCurl whose requests never complete.
dll "$ROOT/stubs/src/XCurl.c" "$OUT/hang/XCurl.dll" -DFAIL_DELAY_MS=1000000000000ULL

say "stubs built in $OUT"
