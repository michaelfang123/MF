#!/usr/bin/env bash
#
# video2kb - Download, transcribe, and convert video tutorials into
#            structured markdown notes for a personal knowledge base.
#
# Dependencies: yt-dlp, ffmpeg, whisper.cpp
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
FORMAT="markdown"

usage() {
  cat <<'USAGE'
video2kb - Video tutorial to knowledge base

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
  -h, --help             Show this help

EXAMPLES:
  video2kb.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
  video2kb.sh "https://www.bilibili.com/video/BV1xx411c7mD" -l zh
  video2kb.sh "https://youtu.be/abc123" -l en --keep-video --srt
USAGE
  exit 0
}

# ---------- parse args ----------
[ $# -eq 0 ] && usage
URL="$1"; shift

GEN_SRT=false

while [ $# -gt 0 ]; do
  case "$1" in
    -l|--lang)    LANG="$2"; shift 2 ;;
    -m|--model)   MODEL="$2"; shift 2 ;;
    -t|--threads) THREADS="$2"; shift 2 ;;
    -o|--output)  OUTPUT_DIR="$2"; shift 2 ;;
    --keep-video) KEEP_VIDEO=true; shift ;;
    --keep-audio) KEEP_AUDIO=true; shift ;;
    --srt)        GEN_SRT=true; shift ;;
    -h|--help)    usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[ -n "$MODEL" ] && MODEL_PATH="$MODEL"

# ---------- preflight checks ----------
for cmd in yt-dlp ffmpeg; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "[ERROR] $cmd not found. Run: ./scripts/setup.sh"
    exit 1
  fi
done

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

mkdir -p "$OUTPUT_DIR"

# ---------- temp workspace ----------
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# ============================================================
# STEP 1: Download video and extract metadata
# ============================================================
echo ""
echo "=========================================="
echo " STEP 1/4  Downloading video..."
echo "=========================================="

yt-dlp \
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

# extract metadata from info json
TITLE=""
CHANNEL=""
UPLOAD_DATE=""
DESCRIPTION=""
DURATION=""
VIDEO_URL=""

if [ -n "$INFO_JSON" ] && [ -f "$INFO_JSON" ]; then
  TITLE=$(python3 -c "import json,sys; d=json.load(open('$INFO_JSON')); print(d.get('title',''))" 2>/dev/null || true)
  CHANNEL=$(python3 -c "import json,sys; d=json.load(open('$INFO_JSON')); print(d.get('channel','') or d.get('uploader',''))" 2>/dev/null || true)
  UPLOAD_DATE=$(python3 -c "import json,sys; d=json.load(open('$INFO_JSON')); print(d.get('upload_date',''))" 2>/dev/null || true)
  DESCRIPTION=$(python3 -c "import json,sys; d=json.load(open('$INFO_JSON')); print(d.get('description','')[:500])" 2>/dev/null || true)
  DURATION=$(python3 -c "import json,sys; d=json.load(open('$INFO_JSON')); s=int(d.get('duration',0)); print(f'{s//3600}h{(s%3600)//60:02d}m{s%60:02d}s' if s>3600 else f'{s//60}m{s%60:02d}s')" 2>/dev/null || true)
  VIDEO_URL=$(python3 -c "import json,sys; d=json.load(open('$INFO_JSON')); print(d.get('webpage_url','') or d.get('original_url',''))" 2>/dev/null || true)
fi

[ -z "$TITLE" ] && TITLE="Untitled Video"
[ -z "$VIDEO_URL" ] && VIDEO_URL="$URL"

SAFE_TITLE=$(echo "$TITLE" | sed 's/[^a-zA-Z0-9一-鿿 _-]/_/g' | head -c 80)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "[OK] Title: $TITLE"
echo "[OK] Channel: $CHANNEL"
echo "[OK] Duration: $DURATION"

# ============================================================
# STEP 2: Extract audio (16kHz mono WAV for whisper.cpp)
# ============================================================
echo ""
echo "=========================================="
echo " STEP 2/4  Extracting audio..."
echo "=========================================="

AUDIO_WAV="$WORK_DIR/audio.wav"

ffmpeg -y -i "$VIDEO_FILE" \
  -ar 16000 -ac 1 -c:a pcm_s16le \
  -loglevel warning \
  "$AUDIO_WAV"

AUDIO_SIZE=$(du -h "$AUDIO_WAV" | cut -f1)
echo "[OK] Audio extracted: $AUDIO_SIZE (16kHz mono WAV)"

# ============================================================
# STEP 3: Transcribe with whisper.cpp
# ============================================================
echo ""
echo "=========================================="
echo " STEP 3/4  Transcribing with whisper.cpp..."
echo "=========================================="

WHISPER_ARGS=(
  -m "$MODEL_PATH"
  -f "$AUDIO_WAV"
  -t "$THREADS"
  -pp          # print progress
  -otxt        # output .txt
)

if [ "$LANG" != "auto" ]; then
  WHISPER_ARGS+=(-l "$LANG")
fi

if [ "$GEN_SRT" = true ]; then
  WHISPER_ARGS+=(-osrt)
fi

"$WHISPER_BIN" "${WHISPER_ARGS[@]}" -of "$WORK_DIR/transcript"

TRANSCRIPT_FILE="$WORK_DIR/transcript.txt"

if [ ! -f "$TRANSCRIPT_FILE" ]; then
  echo "[ERROR] Transcription failed."
  exit 1
fi

WORD_COUNT=$(wc -w < "$TRANSCRIPT_FILE")
echo "[OK] Transcription complete: ~${WORD_COUNT} words"

# ============================================================
# STEP 4: Generate knowledge base note
# ============================================================
echo ""
echo "=========================================="
echo " STEP 4/4  Generating knowledge base note..."
echo "=========================================="

OUTPUT_FILE="$OUTPUT_DIR/${TIMESTAMP}_${SAFE_TITLE}.md"
TRANSCRIPT_CONTENT=$(cat "$TRANSCRIPT_FILE")

# format upload date
FORMATTED_DATE=""
if [ -n "$UPLOAD_DATE" ] && [ ${#UPLOAD_DATE} -eq 8 ]; then
  FORMATTED_DATE="${UPLOAD_DATE:0:4}-${UPLOAD_DATE:4:2}-${UPLOAD_DATE:6:2}"
fi

cat > "$OUTPUT_FILE" << MARKDOWN
# ${TITLE}

## Metadata

| Field       | Value |
|-------------|-------|
| Source       | [Link](${VIDEO_URL}) |
| Channel      | ${CHANNEL} |
| Upload Date  | ${FORMATTED_DATE:-Unknown} |
| Duration     | ${DURATION} |
| Language     | ${LANG} |
| Captured     | $(date +%Y-%m-%d) |

## Description

${DESCRIPTION}

---

## Transcript

${TRANSCRIPT_CONTENT}

---

## Notes

<!-- Add your own notes, key takeaways, and action items below -->

### Key Takeaways

-

### Action Items

- [ ]

### Related Topics

-
MARKDOWN

echo "[OK] Note saved: $OUTPUT_FILE"

# copy SRT if generated
if [ "$GEN_SRT" = true ] && [ -f "$WORK_DIR/transcript.srt" ]; then
  SRT_FILE="$OUTPUT_DIR/${TIMESTAMP}_${SAFE_TITLE}.srt"
  cp "$WORK_DIR/transcript.srt" "$SRT_FILE"
  echo "[OK] SRT saved: $SRT_FILE"
fi

# optionally keep video/audio
if [ "$KEEP_VIDEO" = true ]; then
  EXT="${VIDEO_FILE##*.}"
  cp "$VIDEO_FILE" "$OUTPUT_DIR/${TIMESTAMP}_${SAFE_TITLE}.${EXT}"
  echo "[OK] Video kept in output/"
fi

if [ "$KEEP_AUDIO" = true ]; then
  cp "$AUDIO_WAV" "$OUTPUT_DIR/${TIMESTAMP}_${SAFE_TITLE}.wav"
  echo "[OK] Audio kept in output/"
fi

echo ""
echo "=========================================="
echo " DONE"
echo "=========================================="
echo ""
echo "  Title:  $TITLE"
echo "  Words:  ~$WORD_COUNT"
echo "  Output: $OUTPUT_FILE"
echo ""
echo "  Next steps:"
echo "    1. Review and edit the transcript"
echo "    2. Add your own notes and key takeaways"
echo "    3. Tag and file into your knowledge base"
echo ""
