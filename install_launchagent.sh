#!/bin/bash
# local-voice-type を launchd の LaunchAgent として登録し、ログイン時に自動常駐させる。
# このスクリプトのある場所を基準に絶対パスを解決するので、どこに置いても動く。
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON="$DIR/venv/bin/python"
SCRIPT="$DIR/local_voice_type.py"
LABEL="com.local-voice-type"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ ! -x "$PYTHON" ]; then
  echo "エラー: venvのpythonが見つかりません: $PYTHON" >&2
  echo "先に 'python3 -m venv venv && venv/bin/pip install -r requirements.txt' を実行してください。" >&2
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PYTHON</string>
    <string>$SCRIPT</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$DIR</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PYTHONUNBUFFERED</key>
    <string>1</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/local-voice-type.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/local-voice-type.err</string>
</dict>
</plist>
EOF

# 既存があれば一度解除してから読み込む
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load -w "$PLIST"

echo "インストール完了: $PLIST"
echo "ログイン時に自動起動します。今すぐメニューバーに 🎤 が出ているはずです。"
echo "ログは /tmp/local-voice-type.log / .err に出ます。"
echo ""
echo "【重要】権限を venv の python に付け直してください:"
echo "  システム設定 → プライバシーとセキュリティ → 入力監視 / アクセシビリティ"
echo "  「＋」から次を追加してON: $PYTHON"
