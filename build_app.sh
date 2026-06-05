#!/bin/bash
# local-voice-type を軽量な .app ラッパーにビルドする。
# torch/mlx は同梱せず、中身は venv の python を呼ぶだけ。
# .app に独自のバンドルIDを与えることで、マイク/アクセシビリティの許可ダイアログが
# 正しく「Local Voice Type」として出て、TCCに記憶される（launchd直起動のマイク問題を回避）。
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON="$DIR/venv/bin/python"
SCRIPT="$DIR/local_voice_type.py"
APP="$DIR/LocalVoiceType.app"

if [ ! -x "$PYTHON" ]; then
  echo "エラー: venvのpythonが見つかりません: $PYTHON" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Info.plist（バンドルID・メニューバー常駐・マイク用途説明）
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>LocalVoiceType</string>
  <key>CFBundleDisplayName</key>
  <string>Local Voice Type</string>
  <key>CFBundleIdentifier</key>
  <string>com.local-voice-type</string>
  <key>CFBundleExecutable</key>
  <string>LocalVoiceType</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>音声入力のためにマイクを使用します。</string>
</dict>
</plist>
EOF

# 起動本体: arm64ネイティブの小さなランチャをコンパイルして埋め込む。
# （CFBundleExecutableがシェルスクリプトだと、macOSがアーキを判定できず
#  「Rosettaが必要」と誤認するため、Mach-Oバイナリにする必要がある）
LAUNCH_C="$(mktemp /tmp/lvt_launcher.XXXXXX).c"
cat > "$LAUNCH_C" <<EOF
#include <stdio.h>
#include <unistd.h>
int main(void) {
    freopen("/tmp/local-voice-type.log", "a", stdout);
    freopen("/tmp/local-voice-type.err", "a", stderr);
    execl("$PYTHON", "$PYTHON", "$SCRIPT", (char *)0);
    perror("execl failed");
    _exit(127);
}
EOF
clang -arch arm64 -o "$APP/Contents/MacOS/LocalVoiceType" "$LAUNCH_C"
rm -f "$LAUNCH_C"

# アドホック署名（TCCが許可を記憶しやすくなる）。
# 拡張属性が残っていると署名が通らないため、先に除去する。
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP" 2>/dev/null \
  && echo "アドホック署名: OK" \
  || echo "アドホック署名: スキップ（codesign未使用でも動作はします）"

echo "ビルド完了: $APP"
echo ""
echo "次の手順:"
echo "  1. 起動:  open \"$APP\"   （またはFinderでダブルクリック）"
echo "  2. 「\"Local Voice Type\"がマイクへのアクセスを求めています」→ 許可"
echo "  3. システム設定 → プライバシーとセキュリティ → 入力監視 / アクセシビリティ"
echo "     に「Local Voice Type」を追加してON（出ていなければ「＋」でこの.appを追加）"
echo "  4. ログイン時自動起動: システム設定 → 一般 → ログイン項目 に LocalVoiceType.app を追加"
