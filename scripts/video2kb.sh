#!/usr/bin/env bash
#
# video2kb - Download, transcribe, and convert video tutorials into
#            structured markdown notes for a personal knowledge base.
#
# Strategy: subtitle-first — grab existing captions before falling
#           back to expensive audio transcription.
#
# Dependencies: yt-dlp, ffmpeg, whisper.cpp (or SenseVoice for Chinese)
# Usage: video2kb.sh <url> [options]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WHISPER_BIN="$PROJECT_DIR/vendor/whisper.cpp/build/bin/whisper-cli"
MODEL_PATH="$PROJECT_DIR/models/ggml-base.bin"
OUTPUT_DIR="$PROJECT_DIR/output"

# ---------- defaults ----------
LANG="auto"
MODEL=""
KEEP_VIDEO=false
KEEP_AUDIO=false
THREADS=$(nproc 2>/dev/null || echo 4)
GEN_SRT=false

usage() {
  cat <<'USAGE'
video2kb - Video tutorial to knowledge base (subtitle-first strategy)

USAGE:
  video2kb.sh <url> [options]

OPTIONS:
  -l, --lang LANG        Language code for transcription (default: auto)
                         Examples: en, zh, ja, ko, es, fr, de
  -m, --model PATH       Path to whisper model (default: models/ggml-base.bin)
  -t, --threads N        CPU threads for whisper (default: nproc)
  -o, --output DIR       Output directory (default: ./output)
  --keep-video           Keep the downloaded video file
  --keep-audio           Keep the extracted audio file
  --srt                  Also generate SRT subtitle file
  --no-subs              Skip subtitle fetch, force audio transcription
  -h, --help             Show this help

EXAMPLES:
  video2kb.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
  video2kb.sh "https://www.bilibili.com/video/BV1xx411c7mD" -l zh
  video2kb.sh "https://v.douyin.com/xxx" -l zh
  video2kb.sh "https://youtu.be/abc123" -l en --keep-video --srt
USAGE
  exit 0
}

# ---------- parse args ----------
[ $# -eq 0 ] && usage
URL="$1"; shift

SKIP_SUBS=false

while [ $# -gt 0 ]; do
  case "$1" in
    -l|--lang)    LANG="$2"; shift 2 ;;
    -m|--model)   MODEL="$2"; shift 2 ;;
    -t|--threads) THREADS="$2"; shift 2 ;;
    -o|--output)  OUTPUT_DIR="$2"; shift 2 ;;
    --keep-video) KEEP_VIDEO=true; shift ;;
    --keep-audio) KEEP_AUDIO=true; shift ;;
    --srt)        GEN_SRT=true; shift ;;
    --no-subs)    SKIP_SUBS=true; shift ;;
    -h|--help)    usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[ -n "$MODEL" ] && MODEL_PATH="$MODEL"

# ---------- preflight checks ----------
if command -v yt-dlp &>/dev/null; then
  YTDLP="yt-dlp"
elif python3 -m yt_dlp --version &>/dev/null; then
  YTDLP="python3 -m yt_dlp"
else
  echo "[ERROR] yt-dlp not found. Run: ./scripts/setup.sh"
  exit 1
fi

if ! command -v ffmpeg &>/dev/null; then
  echo "[ERROR] ffmpeg not found. Run: ./scripts/setup.sh"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ---------- temp workspace ----------
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# ---------- detect platform ----------
detect_platform() {
  case "$1" in
    *douyin.com*|*iesdouyin.com*)  echo "douyin" ;;
    *bilibili.com*|*b23.tv*)      echo "bilibili" ;;
    *youtube.com*|*youtu.be*)      echo "youtube" ;;
    *xiaohongshu.com*|*xhslink.*) echo "xiaohongshu" ;;
    *weibo.com*|*weibo.cn*)        echo "weibo" ;;
    *x.com*|*twitter.com*)         echo "x" ;;
    *)                             echo "generic" ;;
  esac
}

PLATFORM=$(detect_platform "$URL")
echo ""
echo "=========================================="
echo " Platform: $PLATFORM"
echo "=========================================="

# ============================================================
# STEP 1: Try subtitle-first strategy
# ============================================================
TRANSCRIPT_FILE=""
SUBTITLE_SOURCE=""

if [ "$SKIP_SUBS" = false ]; then
  echo ""
  echo "=========================================="
  echo " STEP 1/4  Trying subtitle-first strategy..."
  echo "=========================================="

  # Try fetching existing subtitles via yt-dlp
  SUB_LANG="$LANG"
  [ "$SUB_LANG" = "auto" ] && SUB_LANG="zh,en,ja,ko"

  $YTDLP \
    --no-playlist \
    --skip-download \
    --write-subs \
    --write-auto-subs \
    --sub-langs "$SUB_LANG" \
    --sub-format "srt/vtt/best" \
    --convert-subs srt \
    --output "$WORK_DIR/subs" \
    "$URL" 2>/dev/null || true

  # Check if any subtitle files were downloaded
  SUB_FILE=$(ls "$WORK_DIR"/subs*.srt 2>/dev/null | head -1)

  if [ -n "$SUB_FILE" ] && [ -s "$SUB_FILE" ]; then
    echo "[OK] Found existing subtitles!"
    SUBTITLE_SOURCE="platform-subtitles"

    # Parse SRT: strip timestamps, sequence numbers, HTML tags, deduplicate
    python3 -c "
import re, sys

content = sys.stdin.read()

# Remove sequence numbers and timestamps
lines = []
for line in content.split('\n'):
    line = line.strip()
    if not line:
        continue
    if re.match(r'^\d+$', line):
        continue
    if re.match(r'\d{2}:\d{2}:\d{2}', line):
        continue
    # Remove HTML tags
    line = re.sub(r'<[^>]+>', '', line)
    # Remove VTT positioning
    line = re.sub(r'align:.*|position:.*|size:.*', '', line).strip()
    if line and line not in lines[-1:]:
        lines.append(line)

print('\n'.join(lines))
" < "$SUB_FILE" > "$WORK_DIR/transcript_raw.txt"

    WORD_COUNT=$(wc -c < "$WORK_DIR/transcript_raw.txt")
    if [ "$WORD_COUNT" -gt 50 ]; then
      TRANSCRIPT_FILE="$WORK_DIR/transcript_raw.txt"
      echo "[OK] Subtitle transcript: $(wc -w < "$TRANSCRIPT_FILE") words"
    else
      echo "[WARN] Subtitle content too short, will try audio transcription"
    fi
  else
    echo "[INFO] No subtitles available, will use audio transcription"
  fi
fi

# ============================================================
# STEP 2: Download video (needed for metadata + audio fallback)
# ============================================================
echo ""
echo "=========================================="
echo " STEP 2/4  Downloading video..."
echo "=========================================="

$YTDLP \
  --no-playlist \
  --write-info-json \
  --output "$WORK_DIR/video.%(ext)s" \
  --format "bestvideo[height<=1080]+bestaudio/best[height<=1080]/best" \
  --merge-output-format mp4 \
  "$URL"

VIDEO_FILE=$(ls "$WORK_DIR"/video.* 2>/dev/null | grep -v '\.json$' | head -1)
INFO_JSON=$(ls "$WORK_DIR"/video.*.json 2>/dev/null | head -1)

if [ -z "$VIDEO_FILE" ]; then
  echo "[ERROR] Download failed."
  exit 1
fi

# extract metadata
TITLE=""
CHANNEL=""
UPLOAD_DATE=""
DESCRIPTION=""
DURATION=""
VIDEO_URL=""

if [ -n "$INFO_JSON" ] && [ -f "$INFO_JSON" ]; then
  TITLE=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('title',''))" < "$INFO_JSON" 2>/dev/null || true)
  CHANNEL=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('channel','') or d.get('uploader',''))" < "$INFO_JSON" 2>/dev/null || true)
  UPLOAD_DATE=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('upload_date',''))" < "$INFO_JSON" 2>/dev/null || true)
  DESCRIPTION=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('description','')[:500])" < "$INFO_JSON" 2>/dev/null || true)
  DURATION=$(python3 -c "import json,sys; d=json.load(sys.stdin); s=int(d.get('duration',0)); print(f'{s//3600}h{(s%3600)//60:02d}m{s%60:02d}s' if s>3600 else f'{s//60}m{s%60:02d}s')" < "$INFO_JSON" 2>/dev/null || true)
  VIDEO_URL=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('webpage_url','') or d.get('original_url',''))" < "$INFO_JSON" 2>/dev/null || true)
fi

[ -z "$TITLE" ] && TITLE="Untitled Video"
[ -z "$VIDEO_URL" ] && VIDEO_URL="$URL"

SAFE_TITLE=$(echo "$TITLE" | sed 's/[^a-zA-Z0-9一-鿿 _-]/_/g' | head -c 80)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "[OK] Title: $TITLE"
echo "[OK] Channel: $CHANNEL"
echo "[OK] Duration: $DURATION"

# ============================================================
# STEP 3: Audio transcription (only if subtitles not found)
# ============================================================
if [ -z "$TRANSCRIPT_FILE" ]; then
  echo ""
  echo "=========================================="
  echo " STEP 3/4  Audio transcription fallback..."
  echo "=========================================="

  # Check whisper availability
  if [ ! -f "$WHISPER_BIN" ]; then
    echo "[ERROR] whisper-cli not found at $WHISPER_BIN"
    echo "        Run: ./scripts/setup.sh"
    exit 1
  fi

  if [ ! -f "$MODEL_PATH" ]; then
    echo "[ERROR] Whisper model not found at $MODEL_PATH"
    echo "        Run: ./scripts/setup.sh"
    exit 1
  fi

  AUDIO_WAV="$WORK_DIR/audio.wav"
  ffmpeg -y -i "$VIDEO_FILE" \
    -ar 16000 -ac 1 -c:a pcm_s16le \
    -loglevel warning \
    "$AUDIO_WAV"

  AUDIO_SIZE=$(du -h "$AUDIO_WAV" | cut -f1)
  echo "[OK] Audio extracted: $AUDIO_SIZE (16kHz mono WAV)"

  WHISPER_ARGS=(
    -m "$MODEL_PATH"
    -f "$AUDIO_WAV"
    -t "$THREADS"
    -pp
    -otxt
  )

  if [ "$LANG" != "auto" ]; then
    WHISPER_ARGS+=(-l "$LANG")
  fi

  if [ "$GEN_SRT" = true ]; then
    WHISPER_ARGS+=(-osrt)
  fi

  "$WHISPER_BIN" "${WHISPER_ARGS[@]}" -of "$WORK_DIR/transcript"

  TRANSCRIPT_FILE="$WORK_DIR/transcript.txt"
  SUBTITLE_SOURCE="whisper-transcription"

  if [ ! -f "$TRANSCRIPT_FILE" ]; then
    echo "[ERROR] Transcription failed."
    exit 1
  fi

  echo "[OK] Transcription complete: ~$(wc -w < "$TRANSCRIPT_FILE") words"

  if [ "$KEEP_AUDIO" = true ]; then
    cp "$AUDIO_WAV" "$OUTPUT_DIR/${TIMESTAMP}_${SAFE_TITLE}.wav"
    echo "[OK] Audio kept in output/"
  fi
else
  echo ""
  echo "=========================================="
  echo " STEP 3/4  Skipped (subtitles found)"
  echo "=========================================="
fi

# ============================================================
# STEP 4: Generate knowledge base note
# ============================================================
echo ""
echo "=========================================="
echo " STEP 4/4  Generating knowledge base note..."
echo "=========================================="

OUTPUT_FILE="$OUTPUT_DIR/${TIMESTAMP}_${SAFE_TITLE}.md"
TRANSCRIPT_CONTENT=$(cat "$TRANSCRIPT_FILE")

FORMATTED_DATE=""
if [ -n "$UPLOAD_DATE" ] && [ ${#UPLOAD_DATE} -eq 8 ]; then
  FORMATTED_DATE="${UPLOAD_DATE:0:4}-${UPLOAD_DATE:4:2}-${UPLOAD_DATE:6:2}"
fi

cat > "$OUTPUT_FILE" << MARKDOWN
---
platform: ${PLATFORM}
source: ${VIDEO_URL}
author: ${CHANNEL}
created: $(date +%Y-%m-%d)
upload_date: ${FORMATTED_DATE:-Unknown}
duration: ${DURATION}
language: ${LANG}
transcript_source: ${SUBTITLE_SOURCE}
note_type: video
grade:
tags: []
---

# ${TITLE}

## Metadata

| Field       | Value |
|-------------|-------|
| Source       | [Link](${VIDEO_URL}) |
| Platform     | ${PLATFORM} |
| Channel      | ${CHANNEL} |
| Upload Date  | ${FORMATTED_DATE:-Unknown} |
| Duration     | ${DURATION} |
| Language     | ${LANG} |
| Transcript   | ${SUBTITLE_SOURCE} |
| Captured     | $(date +%Y-%m-%d) |

## Description

${DESCRIPTION}

---

## Transcript

${TRANSCRIPT_CONTENT}

---

## Key Takeaways

<!-- Claude will fill this section when using /enrich -->

-

## Action Items

- [ ]

## Related Topics

-

## Questions

<!-- Questions for deeper understanding -->

-
MARKDOWN

echo "[OK] Note saved: $OUTPUT_FILE"

# copy SRT if generated
if [ "$GEN_SRT" = true ] && [ -f "$WORK_DIR/transcript.srt" ]; then
  SRT_FILE="$OUTPUT_DIR/${TIMESTAMP}_${SAFE_TITLE}.srt"
  cp "$WORK_DIR/transcript.srt" "$SRT_FILE"
  echo "[OK] SRT saved: $SRT_FILE"
fi

if [ "$KEEP_VIDEO" = true ]; then
  EXT="${VIDEO_FILE##*.}"
  cp "$VIDEO_FILE" "$OUTPUT_DIR/${TIMESTAMP}_${SAFE_TITLE}.${EXT}"
  echo "[OK] Video kept in output/"
fi

echo ""
echo "=========================================="
echo " DONE"
echo "=========================================="
echo ""
echo "  Title:      $TITLE"
echo "  Transcript: $SUBTITLE_SOURCE"
echo "  Output:     $OUTPUT_FILE"
echo ""
echo "  Next: run /enrich to add AI-generated summaries and key takeaways"
echo ""
