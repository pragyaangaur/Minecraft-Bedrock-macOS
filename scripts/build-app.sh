#!/bin/zsh
# Package the built Wine, DXMT and stand-in DLLs as Bedrock Launcher.app and
# put it in a disk image, dist/Bedrock-Launcher.dmg.
#
# Run ./setup.sh first. The app holds no game files. On its first start it
# asks for the game folder and the memory dump and prepares them on the
# user's Mac, as scripts/prepare-game.sh does here.
set -eu
source "${0:A:h}/common.sh"

DIST="$ROOT/dist"
APP="$DIST/Bedrock Launcher.app"
RES="$APP/Contents/Resources"
CACHE="$BUILD/app-cache"
STRIP="$BREW/opt/llvm/bin/llvm-strip"
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --always 2> /dev/null || echo dev)}"

[[ -x $WINE_DIR/bin/wine && -f $WINE_DIR/lib/wine/x86_64-windows/d3d11.dll ]] || die "build Wine and DXMT first (./setup.sh)"
[[ -f $STUBS_DIR/XCurl.dll ]] || die "build the stand-in DLLs first (stubs/build.sh)"

rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$RES" "$CACHE"

say "copying Wine and DXMT"
rsync -a --exclude include --exclude share/man --exclude '*.a' "$WINE_DIR/" "$RES/wine/"
# The Windows DLLs carry DWARF debug information, which is most of their size.
find "$RES/wine/lib/wine/x86_64-windows" -type f -print0 | xargs -0 -n 64 "$STRIP" --strip-debug 2> /dev/null || true

say "copying the stand-in DLLs"
mkdir -p "$RES/stubs/hang"
cp "$STUBS_DIR"/*.dll "$RES/stubs/"
cp "$STUBS_DIR"/hang/*.dll "$RES/stubs/hang/"

say "adding Python for the preparation tools"
py_tar="$CACHE/${${PYTHON_URL:t}//\%2B/+}"
[[ -f $py_tar ]] || curl -fsSL -o "$py_tar" "$PYTHON_URL"
[[ $(shasum -a 256 "$py_tar" | cut -d' ' -f1) == $PYTHON_SHA256 ]] || die "checksum mismatch for ${py_tar:t}"
tar -xf "$py_tar" -C "$RES"
grep -v '^numpy' "$ROOT/requirements.txt" > "$CACHE/requirements.txt"
"$RES/python/bin/python3" -m pip install -q --no-cache-dir --disable-pip-version-check -r "$CACHE/requirements.txt"
find "$RES/python" -name __pycache__ -type d -prune -exec rm -rf {} +

say "copying the scripts"
mkdir -p "$RES/repo/tools" "$RES/repo/stubs"
cp -R "$ROOT/scripts" "$RES/repo/"
cp "$ROOT"/tools/*.py "$ROOT"/tools/*.sh "$RES/repo/tools/"
cp -R "$ROOT/stubs/seed" "$RES/repo/stubs/"
cp "$ROOT/LICENSE" "$ROOT/README.md" "$RES/repo/"
cp "$ROOT/app/launcher.sh" "$APP/Contents/MacOS/Bedrock Launcher"
chmod +x "$APP/Contents/MacOS/Bedrock Launcher"

say "collecting the licences"
lic="$RES/licenses"
mkdir -p "$lic"/{wine,dxmt,python}
cp "$BUILD"/src/wine-gdk/{COPYING.LIB,LICENSE,AUTHORS} "$lic/wine/"
cp "$BUILD/src/dxmt/LICENSE" "$lic/dxmt/"
cp "$RES"/python/lib/python3.*/LICENSE.txt "$lic/python/" 2> /dev/null || true
for t in "$BUILD"/deps-src/*.tar.*; do
  name=${${t:t}%.tar.*}
  mkdir -p "$lic/$name"
  files=(${(f)"$(tar -tf "$t" | grep -E "^$name/(COPYING|LICENSE|docs/FTL\.TXT|docs/GPLv2\.TXT)")"})
  tar -xf "$t" -C "$lic/$name" --strip-components 1 $files
done
cat > "$lic/SOURCE.txt" <<EOF
Bedrock Launcher $VERSION

Wine (WineGDK) and the libraries it uses (GnuTLS, Nettle, GMP) are under the
GNU LGPL, FreeType is under the FreeType licence, DXMT is under the MIT
licence and Python is under the PSF licence. Their licence texts are in this
folder.

The complete source of this build is the WineGDK commit $WINEGDK_COMMIT
from $WINEGDK_URL,
DXMT $DXMT_TAG from $DXMT_URL,
the tarballs listed in scripts/common.sh, and the patches and scripts in
https://github.com/pragyaangaur/Minecraft-Bedrock-macOS at $VERSION.
./setup.sh in that repository rebuilds every binary in this app from them.
EOF

say "drawing the icon"
iconset="$CACHE/AppIcon.iconset"
rm -rf "$iconset" && mkdir -p "$iconset"
swift "$ROOT/app/make_icon.swift" "$CACHE/icon.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$CACHE/icon.png" --out "$iconset/icon_${s}x${s}.png" > /dev/null
  sips -z $((s * 2)) $((s * 2)) "$CACHE/icon.png" --out "$iconset/icon_${s}x${s}@2x.png" > /dev/null
done
iconutil -c icns -o "$RES/AppIcon.icns" "$iconset"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Bedrock Launcher</string>
  <key>CFBundleDisplayName</key><string>Bedrock Launcher</string>
  <key>CFBundleIdentifier</key><string>io.github.pragyaangaur.bedrock-launcher</string>
  <key>CFBundleExecutable</key><string>Bedrock Launcher</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION#v}</string>
  <key>CFBundleVersion</key><string>${VERSION#v}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSArchitecturePriority</key><array><string>arm64</string></array>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Not affiliated with Mojang or Microsoft.</string>
</dict>
</plist>
EOF

say "signing the app (ad hoc)"
codesign --force --deep --sign - "$APP"

say "making the disk image"
stage="$CACHE/dmg"
rm -rf "$stage" && mkdir -p "$stage"
cp -R "$APP" "$stage/"
ln -s /Applications "$stage/Applications"
rm -f "$DIST/Bedrock-Launcher.dmg"
hdiutil create -quiet -volname "Bedrock Launcher" -srcfolder "$stage" -fs APFS -format ULMO "$DIST/Bedrock-Launcher.dmg"
rm -rf "$stage"
say "wrote $DIST/Bedrock-Launcher.dmg ($(du -h "$DIST/Bedrock-Launcher.dmg" | cut -f1))"
