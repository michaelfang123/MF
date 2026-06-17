# Video to Skill — 视频教程转技能

Watch a video tutorial, understand what it teaches, and generate a reusable Claude skill (slash command) from it.

## Pipeline

1. **Transcribe** — use the existing video2kb pipeline to download and transcribe the video
2. **Analyze** — identify the core technique, workflow, or methodology taught
3. **Generate** — create a `.md` skill file in `.claude/commands/` that encapsulates the learned skill
4. **Register** — the skill is immediately available as a `/command` in Claude Code and as a project prompt in claude.ai

## Instructions

When the user provides a video URL:

### Step 1: Transcribe the video

Run the existing pipeline to get the transcript:

```bash
bash scripts/video2kb.sh "$URL" $ARGUMENTS
```

If setup hasn't been done yet, run `bash scripts/setup.sh` first.

### Step 2: Read and deeply analyze the transcript

Read the generated output file from `output/`. Identify:

- **What skill is being taught?** — The core technique, tool usage, workflow, or methodology
- **What are the concrete steps?** — The procedural knowledge (do X, then Y, then Z)
- **What are the inputs and outputs?** — What does the user provide, what do they get back?
- **What are the key rules/constraints?** — Best practices, gotchas, edge cases mentioned
- **What domain knowledge is assumed?** — Prerequisites the user should know
- **What examples are given?** — Concrete demonstrations shown in the video

### Step 3: Generate the skill file

Create a new `.md` file in `.claude/commands/` with this structure:

```markdown
# <Skill Name> — <简短中文描述>

<One-line description of what this skill does.>

## When to use

<1-2 sentences: what situation or user request triggers this skill.>

## Instructions

<Detailed step-by-step instructions that Claude should follow when this skill is invoked.
Write these as imperative instructions TO Claude, not as documentation for the user.
Include:>

1. <Step 1 — what to check, ask, or set up>
2. <Step 2 — core action>
3. <Step N — deliver result>

## Key rules

<Bullet list of constraints, best practices, and gotchas extracted from the video.
These are the "expert knowledge" that makes the skill valuable.>

## Examples

<Show 1-3 concrete examples of how to invoke the skill and what output to expect.>

```
/skill-name <input>
```

## Source

Learned from: <video title>
Channel: <channel name>
URL: <video url>
Captured: <date>
```

### Step 4: Naming conventions

- Filename: lowercase, kebab-case, descriptive — e.g. `git-bisect-debug.md`, `prompt-chain.md`
- Keep it short: 2-4 words max
- If the user doesn't specify a name, derive one from the core skill taught

### Step 5: Confirm and refine

After generating the skill:

1. Show the user the generated skill file content
2. Ask if they want to adjust the name, add/remove steps, or change the scope
3. Save the final version to `.claude/commands/<skill-name>.md`
4. Tell the user they can now use it as `/<skill-name>` in Claude Code

## Quality guidelines

- **Write instructions for Claude, not for humans.** The skill file tells Claude what to do when invoked.
- **Be specific over generic.** "Run `ffmpeg -i input.mp4 -vf scale=1280:-1 output.mp4`" beats "resize the video".
- **Preserve the expert's language** for domain-specific terms — don't over-simplify jargon that Claude needs to use correctly.
- **Include error handling** if the video mentioned common failure modes.
- **One skill per video** by default. If a video teaches multiple independent techniques, ask the user if they want separate skills or one combined skill.
- **Bilingual support** — write the skill in the same language as the video transcript. If mixed, default to the primary language.

## Arguments

The user may provide these optional arguments after the URL:
- `-l <lang>` — Language code (en, zh, ja, ko, etc.)
- `--name <name>` — Override the skill filename
- `--keep-video` — Keep the downloaded video file
- `--no-subs` — Skip subtitle fetch, force audio transcription

## Example usage

```
/video2skill https://www.youtube.com/watch?v=example -l en
/video2skill https://www.bilibili.com/video/BV1xx411c7mD -l zh --name prompt-engineering
/video2skill https://v.douyin.com/xxx -l zh
```
