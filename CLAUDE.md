# Video2KB - 视频教程知识库工具

Turn video tutorials into structured markdown notes for your personal knowledge base.

## Architecture

```
URL → yt-dlp (download) → ffmpeg (audio extraction) → whisper.cpp (transcription) → Markdown note
```

## Project Structure

```
scripts/
  setup.sh       # Install dependencies (yt-dlp, ffmpeg, whisper.cpp, model)
  video2kb.sh    # Main pipeline: download → extract → transcribe → format
  batch.sh       # Process multiple URLs from a text file
vendor/
  whisper.cpp/   # Built from source by setup.sh (git-ignored)
models/
  ggml-base.bin  # Whisper base model (git-ignored)
output/
  *.md           # Generated knowledge base notes
  *.srt          # Optional subtitle files
.claude/
  commands/
    video2kb.md  # Claude Code slash command: /video2kb <url>
```

## Quick Start

```bash
bash scripts/setup.sh                                          # one-time setup
bash scripts/video2kb.sh "https://youtube.com/watch?v=..." -l en  # single video
bash scripts/batch.sh urls.txt -l zh                           # batch mode
```

## Commands

- `/video2kb <url> [options]` - Process a video via Claude Code
- `/video2skill <url> [options]` - Watch a video tutorial and generate a reusable Claude skill from it
- `/enrich [file]` - Add AI-generated summaries and key takeaways to a note
- `/kb <subcommand>` - Search, list, or manage the knowledge base

## Supported Languages

Pass `-l <code>`: en, zh, ja, ko, es, fr, de, it, pt, ru, ar, hi, and more.
Use `-l auto` (default) for automatic detection.

## Whisper Models

Default: `ggml-base.bin` (141 MB, good balance of speed and accuracy).
For better accuracy, download a larger model and pass `-m models/<model>.bin`:

- `ggml-tiny.bin` (75 MB) - Fastest, lower accuracy
- `ggml-base.bin` (141 MB) - Default
- `ggml-small.bin` (465 MB) - Better accuracy
- `ggml-medium.bin` (1.5 GB) - High accuracy
- `ggml-large-v3.bin` (3.1 GB) - Best accuracy, slowest
