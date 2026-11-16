#!/bin/zsh
# [INPUT]: 依赖 app/*.swift、data/questions.sqlite 和 macOS Command Line Tools。
# [OUTPUT]: 生成 build/三级解题助手.app，包含只读题库与固定签名标识。
# [POS]: scripts 的本机构建入口；本地签名身份不随二进制内容改变。
# [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/三级解题助手.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
  "$ROOT"/app/*.swift -lsqlite3 -o "$APP/Contents/MacOS/三级解题助手"
cp "$ROOT/data/questions.sqlite" "$APP/Contents/Resources/questions.sqlite"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>net.local.trainerlevel3</string>
<key>CFBundleName</key><string>三级解题助手</string>
<key>CFBundleExecutable</key><string>三级解题助手</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.4</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --identifier net.local.trainerlevel3 \
  --requirements '=designated => identifier "net.local.trainerlevel3"' "$APP" >/dev/null
print "已生成 $APP"
