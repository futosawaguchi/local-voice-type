"""local-voice-type — macOSで動く完全ローカルの音声入力ツール。

右Optionキーを押している間だけ録音し、離すとmlx-whisperで文字起こしして
最前面のテキストフィールドに挿入する。メニューバーに常駐する。

権限（システム設定 → プライバシーとセキュリティ）が必要：
  - 入力監視: pynputのキー監視に必要
  - アクセシビリティ: osascript経由のCmd+V（テキスト挿入）に必要
"""

import subprocess
import threading
import time

import numpy as np
import pyperclip
import rumps
import sounddevice as sd
from pynput import keyboard

import mlx_whisper

# ===== 設定（ここを変えれば挙動を変更できる / ADR-003, ADR-007）=====
TRIGGER_KEY = keyboard.Key.alt_r      # 右Option。押している間だけ録音
MODEL = "mlx-community/whisper-large-v3-turbo"
LANGUAGE = "ja"
SAMPLE_RATE = 16000                   # Whisperが前提とする16kHz
MIN_DURATION = 0.3                    # これより短い録音はタップ誤爆として無視（秒）
TRAILING_SILENCE = 0.5                # 末尾に足す無音（秒）。文末の句読点を確定させやすくする

# 句読点を付けさせるためのヒント文体（Whisperは直前の文体に倣う）。
# 句読点入りの自然文を与えると、出力にも句読点が付きやすくなる。
INITIAL_PROMPT = "今日はいい天気ですね。そうですね、本当に。"

# メニューバー表示
ICON_IDLE = "🎤"
ICON_RECORDING = "🔴"
ICON_PROCESSING = "⏳"


class VoiceTyper(rumps.App):
    def __init__(self):
        super().__init__(ICON_IDLE, quit_button="終了")
        self.recording = False
        self._frames = []          # 録音中の音声フレームを貯める
        self._stream = None        # sounddeviceの入力ストリーム

        # 起動時にモデルをバックグラウンドで先読みし、初回の文字起こしを速くする
        threading.Thread(target=self._warm_up, daemon=True).start()

        # キー監視を別スレッドで開始
        self._listener = keyboard.Listener(
            on_press=self._on_press, on_release=self._on_release
        )
        self._listener.start()

    # ----- モデル先読み -----
    def _warm_up(self):
        silent = np.zeros(SAMPLE_RATE, dtype=np.float32)  # 1秒の無音
        try:
            mlx_whisper.transcribe(
                silent, path_or_hf_repo=MODEL, language=LANGUAGE
            )
        except Exception as e:
            print(f"[warm_up] モデル先読み失敗: {e}")

    # ----- キーイベント -----
    def _on_press(self, key):
        if key == TRIGGER_KEY and not self.recording:
            self._start_recording()

    def _on_release(self, key):
        if key == TRIGGER_KEY and self.recording:
            self._stop_recording()

    # ----- 録音 -----
    def _audio_callback(self, indata, frames, time_info, status):
        if status:
            print(f"[audio] {status}")
        self._frames.append(indata.copy())

    def _start_recording(self):
        self.recording = True
        self._frames = []
        self.title = ICON_RECORDING
        self._stream = sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=1,
            dtype="float32",
            callback=self._audio_callback,
        )
        self._stream.start()

    def _stop_recording(self):
        self.recording = False
        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None

        if not self._frames:
            self.title = ICON_IDLE
            return

        audio = np.concatenate(self._frames, axis=0).flatten()
        if len(audio) / SAMPLE_RATE < MIN_DURATION:
            self.title = ICON_IDLE   # タップ誤爆は無視
            return

        # 文字起こし〜挿入は重いのでワーカースレッドへ（メニューバーを固めない）
        self.title = ICON_PROCESSING
        threading.Thread(
            target=self._transcribe_and_insert, args=(audio,), daemon=True
        ).start()

    # ----- 文字起こし + 挿入 -----
    def _transcribe_and_insert(self, audio):
        try:
            # 末尾に無音を足して、文末の句読点を確定しやすくする
            pad = np.zeros(int(SAMPLE_RATE * TRAILING_SILENCE), dtype=np.float32)
            audio = np.concatenate([audio, pad])
            result = mlx_whisper.transcribe(
                audio, path_or_hf_repo=MODEL, language=LANGUAGE,
                initial_prompt=INITIAL_PROMPT,
            )
            text = result["text"].strip()
            if text:
                self._insert_text(text)
        except Exception as e:
            print(f"[transcribe] 失敗: {e}")
        finally:
            self.title = ICON_IDLE

    def _insert_text(self, text):
        """クリップボード経由でCmd+V挿入。元のクリップボードは復元する（ADR-005）。"""
        previous = pyperclip.paste()
        pyperclip.copy(text)
        subprocess.run(
            ["osascript", "-e",
             'tell application "System Events" to keystroke "v" using command down'],
            check=False,
        )
        time.sleep(0.15)            # 貼り付け完了を待ってから復元
        pyperclip.copy(previous)


if __name__ == "__main__":
    VoiceTyper().run()
