# Video to Knowledge Base

Process a video tutorial into a structured markdown note for a personal knowledge base.

## Pipeline

1. **Download** the video with `yt-dlp` (supports YouTube, Bilibili, and 1000+ sites)
2. **Extract** audio with `ffmpeg` (convert to 16kHz mono WAV)
3. **Transcribe** with `whisper.cpp` (local, offline speech-to-text)
4. **Generate** a structured markdown note with metadata, transcript, and note sections

## Instructions

When the user provides a video URL:

1. First check if dependencies are installed by running: `ls vendor/whisper.cpp/build/bin/whisper-cli models/ggml-base.bin 2>/dev/null`
2. If not set up yet, run: `bash scripts/setup.sh`
3. Run the pipeline: `bash scripts/video2kb.sh "<URL>" $ARGUMENTS`
4. After the transcript is generated, read the output markdown file
5. Enhance the note by:
   - Summarizing the key points in the "Key Takeaways" section
   - Suggesting action items
   - Adding relevant topic tags
   - Breaking long transcripts into logical sections with headers

## Arguments

The user may provide these optional arguments after the URL:
- `-l <lang>` - Language code (en, zh, ja, ko, etc.)
- `--keep-video` - Keep the downloaded video file
- `--srt` - Also generate SRT subtitles
- `-m <model>` - Use a different whisper model

## Example usage

```
/video2kb https://www.youtube.com/watch?v=example -l en
/video2kb https://www.bilibili.com/video/BV1xx411c7mD -l zh
```
