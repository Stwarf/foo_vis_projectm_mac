#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$ROOT/.." && pwd)"
SDK_ROOT="$WORKSPACE_ROOT/foobar2000-SDK"
PROJECTM_PREFIX="$WORKSPACE_ROOT/projectm-install"
SDK_PRODUCTS="$HOME/Library/Developer/Xcode/DerivedData/foo_sample-fwcgerucbrsoscfuxwoujesstxpl/Build/Products/Release"
BUILD_DIR="$ROOT/build"
BUNDLE="$BUILD_DIR/Release/foo_vis_projectm_mac.component"
BIN="$BUNDLE/Contents/MacOS/foo_vis_projectm_mac"
FRAMEWORKS="$BUNDLE/Contents/Frameworks"

mkdir -p "$BUILD_DIR/obj" "$BUNDLE/Contents/MacOS" "$FRAMEWORKS"

COMMON_FLAGS="
  -arch arm64
  -target arm64-apple-macos11.0
  -isysroot $(xcrun --sdk macosx --show-sdk-path)
  -std=gnu++20
  -stdlib=libc++
  -fobjc-arc
  -fmodules
  -DNDEBUG=1
  -DNS_BLOCK_ASSERTIONS=1
  -DGL_SILENCE_DEPRECATION=1
  -I$ROOT/src
  -I$SDK_ROOT
  -I$SDK_ROOT/foobar2000
  -I$PROJECTM_PREFIX/include
"

clang++ $COMMON_FLAGS -x objective-c++ -c "$ROOT/src/projectm_view.mm" -o "$BUILD_DIR/obj/projectm_view.o"
clang++ $COMMON_FLAGS -x objective-c++ -c "$ROOT/src/preferences_mac.mm" -o "$BUILD_DIR/obj/preferences_mac.o"
clang++ $COMMON_FLAGS -x objective-c++ -c "$ROOT/src/ui_element_mac.mm" -o "$BUILD_DIR/obj/ui_element_mac.o"
clang++ $COMMON_FLAGS -x c++ -c "$ROOT/src/projectm_audio_bridge.cpp" -o "$BUILD_DIR/obj/projectm_audio_bridge.o"
clang++ $COMMON_FLAGS -x c++ -c "$ROOT/src/main.cpp" -o "$BUILD_DIR/obj/main.o"

clang++ \
  -arch arm64 \
  -target arm64-apple-macos11.0 \
  -bundle \
  -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
  -o "$BIN" \
  "$BUILD_DIR/obj/main.o" \
  "$BUILD_DIR/obj/projectm_audio_bridge.o" \
  "$BUILD_DIR/obj/preferences_mac.o" \
  "$BUILD_DIR/obj/projectm_view.o" \
  "$BUILD_DIR/obj/ui_element_mac.o" \
  -L"$SDK_PRODUCTS" \
  -L"$PROJECTM_PREFIX/lib" \
  -lfoobar2000_component_client \
  -lshared \
  -lfoobar2000_SDK \
  -lfoobar2000_SDK_helpers \
  -lpfc-Mac \
  -lprojectM-4 \
  -framework Cocoa \
  -framework CoreVideo \
  -framework OpenGL \
  -Wl,-rpath,@loader_path/../Frameworks \
  -Wl,-no_adhoc_codesign

cp "$PROJECTM_PREFIX/lib/libprojectM-4.4.dylib" "$FRAMEWORKS/libprojectM-4.4.dylib"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>foo_vis_projectm_mac</string>
  <key>CFBundleIdentifier</key>
  <string>com.foobar2000.foo-vis-projectm-mac</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>foo_vis_projectm_mac</string>
  <key>CFBundlePackageType</key>
  <string>BNDL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.2.1</string>
  <key>CFBundleVersion</key>
  <string>1.2.1</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$FRAMEWORKS/libprojectM-4.4.dylib"
codesign --force --sign - "$BUNDLE"

echo "$BUNDLE"
