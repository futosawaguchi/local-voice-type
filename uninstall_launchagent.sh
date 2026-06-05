#!/bin/bash
# local-voice-type の LaunchAgent を解除・削除する（自動起動をやめる）。
set -e

LABEL="com.local-voice-type"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ -f "$PLIST" ]; then
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "アンインストール完了: $PLIST を削除しました。"
else
  echo "LaunchAgentは登録されていません: $PLIST"
fi
