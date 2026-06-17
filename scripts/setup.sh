#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WHISPER_DIR="$PROJECT_DIR/vendor/whisper.cpp"
MODEL_DIR="$PROJECT_DIR/models"

echo "=== Video2KB Setup ==="

# ---- yt-dlp ----
if command -v yt-dlp &>/dev/null; then
  echo "[OK] yt-dlp $(yt-dlp --version)"
else
  echo "[INSTALL] yt-dlp ..."
  pip install --quiet yt-dlp || {
    echo "pip install failed, trying curl..."
    sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
    sudo chmod a+rx /usr/local/bin/yt-dlp
  }
  echo "[OK] yt-dlp installed"
fi

# ---- ffmpeg ----
if command -v ffmpeg &>/dev/null; then
  echo "[OK] ffmpeg $(ffmpeg -version 2>&1 | head -1)"
else
  echo "[INSTALL] ffmpeg ..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y -qq ffmpeg
  elif command -v brew &>/dev/null; then
    brew install ffmpeg
  else
    echo "[ERROR] Cannot auto-install ffmpeg. Please install manually."
    exit 1
  fi
  echo "[OK] ffmpeg installed"
fi

# ---- whisper.cpp ----
if [ -f "$WHISPER_DIR/build/bin/whisper-cli" ]; then
  echo "[OK] whisper.cpp already built"
else
  echo "[BUILD] whisper.cpp ..."
  mkdir -p "$PROJECT_DIR/vendor"
  if [ ! -d "$WHISPER_DIR" ]; then
    git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
  fi
  cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$WHISPER_DIR/build" --config Release -j "$(nproc 2>/dev/null || echo 4)"
  echo "[OK] whisper.cpp built"
fi

# ---- whisper model ----
mkdir -p "$MODEL_DIR"
MODEL_FILE="$MODEL_DIR/ggml-base.bin"
if [ -f "$MODEL_FILE" ]; then
  echo "[OK] whisper model: ggml-base.bin"
else
  echo "[DOWNLOAD] whisper base model ..."
  curl -L --progress-bar \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin" \
    -o "$MODEL_FILE"
  echo "[OK] model downloaded"
fi

echo ""
echo "=== Setup complete ==="
echo "Usage: ./scripts/video2kb.sh <video-url> [language]"
