#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
TASK_OUTPUT="$TASK_ROOT/build-local"
# Build outside synced folders: File Provider metadata can invalidate signing.
TASK_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/mactilt-build.XXXXXX")"
TASK_APP="$TASK_BUILD/macTilt Duo.app"
mkdir -p "$TASK_OUTPUT"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
cp "$TASK_ROOT/Info.plist" "$TASK_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.david.mactilt-duo' "$TASK_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName macTilt Duo' "$TASK_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName macTilt Duo' "$TASK_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDevelopmentRegion zh_CN' "$TASK_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleLocalizations array' "$TASK_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleLocalizations:0 string zh-Hans' "$TASK_APP/Contents/Info.plist"
cp "$TASK_ROOT/Sources/FoldShaders.metal" "$TASK_APP/Contents/Resources/"
cp "$TASK_ROOT/Resources/default.png" "$TASK_ROOT/Resources/AppIcon.icns" "$TASK_APP/Contents/Resources/"
cp -R "$TASK_ROOT/ThirdParty" "$TASK_APP/Contents/Resources/"
swiftc -target arm64-apple-macos14.0 -O "$TASK_ROOT"/Sources/*.swift \
    -o "$TASK_APP/Contents/MacOS/macTilt" \
    -framework AppKit -framework SwiftUI -framework Metal -framework MetalKit \
    -framework ScreenCaptureKit -framework IOKit -framework QuartzCore -framework UserNotifications
# File Provider may add Finder metadata to a newly created .app in Documents.
# Strip only the two metadata keys disallowed by codesign, on this build output.
xattr -dr com.apple.FinderInfo "$TASK_APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$TASK_APP" 2>/dev/null || true
bash "$TASK_ROOT/sign-local.sh" "$TASK_APP"
codesign --verify --strict "$TASK_APP"
ditto -c -k --keepParent --norsrc --noextattr "$TASK_APP" "$TASK_OUTPUT/macTilt Duo.zip"
printf 'Built: %s\n' "$TASK_APP"
printf 'Archive: %s\n' "$TASK_OUTPUT/macTilt Duo.zip"
