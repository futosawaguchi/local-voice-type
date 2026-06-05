#!/bin/bash
# local-voice-type を終了する（メニューバーアイコンが無いとき用）。
if pkill -f local_voice_type.py; then
  echo "停止しました。"
else
  echo "起動していません。"
fi
