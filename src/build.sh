#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TASK_APP="$TASK_ROOT/Codock.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources" "$TASK_ROOT/Data" "$TASK_ROOT/build-cache"
/usr/bin/swiftc -O -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$TASK_ROOT/build-cache" "$TASK_ROOT"/src/*.swift -o "$TASK_APP/Contents/MacOS/Codock" -framework AppKit -framework SwiftUI -framework Carbon
cp "$TASK_ROOT/src/backend.py" "$TASK_ROOT/src/hook.py" "$TASK_ROOT/src/install_hooks.py" "$TASK_ROOT/USER_GUIDE.txt" "$TASK_APP/Contents/Resources/"
if [ -n "${DOCK_BUNDLED_READER:-}" ]; then
    cp "$DOCK_BUNDLED_READER" "$TASK_APP/Contents/Resources/reader"
    chmod +x "$TASK_APP/Contents/Resources/reader"
else
    rm -f "$TASK_APP/Contents/Resources/reader"
fi
cat > "$TASK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.gregogambino.projectbells</string>
<key>CFBundleName</key><string>Codock</string>
<key>CFBundleDisplayName</key><string>Codock</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string></array>
<key>CFBundleExecutable</key><string>Codock</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2.3.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$TASK_APP"
printf '%s\n' "$TASK_APP"
