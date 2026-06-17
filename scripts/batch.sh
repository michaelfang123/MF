#!/usr/bin/env bash
#
# batch.sh - Process multiple video URLs from a text file
#
# Usage: batch.sh <url-list-file> [video2kb options...]
#
# The URL list file should have one URL per line.
# Lines starting with # are treated as comments and skipped.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -eq 0 ]; then
  echo "Usage: batch.sh <url-list-file> [video2kb options...]"
  echo ""
  echo "Example url-list.txt:"
  echo "  # My learning playlist"
  echo "  https://www.youtube.com/watch?v=abc123"
  echo "  https://www.youtube.com/watch?v=def456"
  exit 1
fi

URL_FILE="$1"; shift
EXTRA_ARGS=("$@")

if [ ! -f "$URL_FILE" ]; then
  echo "[ERROR] File not found: $URL_FILE"
  exit 1
fi

TOTAL=$(grep -cvE '^\s*$|^\s*#' "$URL_FILE" || true)
CURRENT=0
FAILED=0
SUCCEEDED=0

echo "=== Batch Processing: $TOTAL videos ==="
echo ""

while IFS= read -r line; do
  line=$(echo "$line" | xargs)
  [ -z "$line" ] && continue
  [[ "$line" == \#* ]] && continue

  CURRENT=$((CURRENT + 1))
  echo ""
  echo "============================================"
  echo " [$CURRENT/$TOTAL] $line"
  echo "============================================"

  if "$SCRIPT_DIR/video2kb.sh" "$line" "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"; then
    SUCCEEDED=$((SUCCEEDED + 1))
  else
    FAILED=$((FAILED + 1))
    echo "[WARN] Failed to process: $line"
  fi

  if [ "$CURRENT" -lt "$TOTAL" ]; then
    echo "[WAIT] Pausing 3 seconds before next download..."
    sleep 3
  fi
done < "$URL_FILE"

echo ""
echo "=== Batch Complete ==="
echo "  Total:     $TOTAL"
echo "  Succeeded: $SUCCEEDED"
echo "  Failed:    $FAILED"
