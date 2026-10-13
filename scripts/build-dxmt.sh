#!/bin/zsh
# Fetch DXMT at the pinned tag, build the LLVM 15 it links against, apply
# patches/dxmt, build it and copy its DLLs into build/wine. DXMT translates
# Direct3D 11 to Metal, so the game renders through the Mac's GPU.
set -eu
source "${0:A:h}/common.sh"
use_build_alias

SRC="$BUILD/src/dxmt"
LLVM_SRC="$SRC/toolchains/llvm-project"
LLVM_OUT="$SRC/toolchains/llvm"
LLVM_OBJ="$BUILD/llvm-build"
OBJ="$BUILD/dxmt-build"
OUT="$BUILD/dxmt"

[[ -x $WINE_DIR/bin/wine ]] || die "build Wine first (scripts/build-wine.sh)"
if [[ -f $OUT/x86_64-windows/d3d11.dll && -f $WINE_DIR/lib/wine/x86_64-unix/winemetal.so ]]; then
  say "DXMT already built"
  exit 0
fi
xcrun -f metal > /dev/null 2>&1 || die "Apple's Metal toolchain is missing. Install it with: xcodebuild -downloadComponent MetalToolchain"

if [[ ! -d $SRC/.git ]]; then
  say "fetching DXMT $DXMT_TAG"
  git clone -q --depth 1 --branch "$DXMT_TAG" --recurse-submodules --shallow-submodules "$DXMT_URL" "$SRC"
  for p in "$ROOT"/patches/dxmt/*.patch; do
    git -C "$SRC" apply "$p" || die "patch ${p:t} does not apply"
  done
fi

if [[ ! -f $LLVM_OUT/lib/libLLVMCore.a ]]; then
  [[ -d $LLVM_SRC/.git ]] || { say "fetching LLVM 15.0.7 (large download)"; git clone -q --depth 1 --branch "$LLVM_TAG" "$LLVM_URL" "$LLVM_SRC"; }
  say "building LLVM 15 for DXMT's shader converter (30 to 60 minutes)"
  cmake -B "$LLVM_OBJ" -S "$LLVM_SRC/llvm" -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$LLVM_OUT" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 -DLLVM_HOST_TRIPLE=x86_64-apple-darwin \
    -DLLVM_ENABLE_ASSERTIONS=On -DLLVM_ENABLE_ZSTD=Off -DLLVM_TARGETS_TO_BUILD="" \
    -DLLVM_BUILD_TOOLS=Off -DLLVM_VERSION_PRINTER_SHOW_HOST_TARGET_INFO=Off > "$BUILD/llvm-configure.log" 2>&1 \
    || die "LLVM configure failed, see $BUILD/llvm-configure.log"
  cmake --build "$LLVM_OBJ" -j"$JOBS" > "$BUILD/llvm-build.log" 2>&1 || die "LLVM build failed, see $BUILD/llvm-build.log"
  cmake --install "$LLVM_OBJ" > /dev/null
fi

say "building DXMT"
cd "$SRC"
[[ -d $OBJ ]] || meson setup "$OBJ" --cross-file=build-win64.txt --buildtype=release -Dstrip=true \
  -Dnative_llvm_path=toolchains/llvm -Dwine_install_path="$WINE_DIR" -Dprefix="$OUT" > "$BUILD/dxmt-configure.log" 2>&1 \
  || die "DXMT configure failed, see $BUILD/dxmt-configure.log"
meson compile -C "$OBJ" > "$BUILD/dxmt-build.log" 2>&1 || die "DXMT build failed, see $BUILD/dxmt-build.log"
meson install -C "$OBJ" > /dev/null

# Put DXMT's DLLs where Wine looks for builtins. tools/run_wine.sh copies them
# into the prefix on every start and tells Wine to prefer them.
for dll in d3d11 dxgi d3d10core winemetal; do
  cp -f "$OUT/x86_64-windows/$dll.dll" "$WINE_DIR/lib/wine/x86_64-windows/$dll.dll"
done
cp -f "$OUT/x86_64-unix/winemetal.so" "$WINE_DIR/lib/wine/x86_64-unix/winemetal.so"
say "DXMT installed into $WINE_DIR"
