# Video to Knowledge Base

Process a video tutorial into a structured markdown note for a personal knowledge base.

## Pipeline (Subtitle-First Strategy)

1. **Try subtitles first** — use `yt-dlp` to grab existing platform captions (auto-generated or official). This is faster and often higher quality than audio transcription.
2. **Download** the video with `yt-dlp` (supports YouTube, Bilibili, Douyin, and 1000+ sites)
3. **Fallback: transcribe** — only if no subtitles found, extract audio with `ffmpeg` and transcribe with `whisper.cpp`
4. **Generate** a structured markdown note with YAML frontmatter, metadata, transcript, and note sections

## Instructions

When the user provides a video URL:

1. First check if dependencies are installed by running: `ls vendor/whisper.cpp/build/bin/whisper-cli models/ggml-base.bin 2>/dev/null`
2. If not set up yet, run: `bash scripts/setup.sh`
3. Run the pipeline: `bash scripts/video2kb.sh "<URL>" $ARGUMENTS`
4. After the note is generated, read the output markdown file
5. Automatically run the `/enrich` workflow:
   - Summarize key takeaways (5-8 bullet points)
   - Generate action items
   - Add topic tags to frontmatter
   - Grade the content (A/B/C)
   - Break long transcripts into logical sections
   - Generate comprehension questions

## Arguments

The user may provide these optional arguments after the URL:
- `-l <lang>` - Language code (en, zh, ja, ko, etc.)
- `--keep-video` - Keep the downloaded video file
- `--srt` - Also generate SRT subtitles
- `--no-subs` - Skip subtitle fetch, force audio transcription
- `-m <model>` - Use a different whisper model

## Example usage

```
/video2kb https://www.youtube.com/watch?v=example -l en
/video2kb https://www.bilibili.com/video/BV1xx411c7mD -l zh
/video2kb https://v.douyin.com/xxx -l zh
```
