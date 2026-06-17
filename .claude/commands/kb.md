# Knowledge Base Management — 知识库管理

Manage and query the personal knowledge base stored in `output/`.

## Instructions

Respond to user commands about the knowledge base:

### Search / Query
When the user asks to search or find content:
```bash
grep -rl "<keyword>" output/*.md
```
Then read matching files and summarize what was found.

### List
When the user asks to list or show the knowledge base:
```bash
ls -lt output/*.md
```
Show a table of notes with title, date, platform, and grade.

### Stats
When the user asks for stats:
- Count total notes: `ls output/*.md | wc -l`
- Count by platform: `grep -h "^platform:" output/*.md | sort | uniq -c | sort -rn`
- Count by grade: `grep -h "^grade:" output/*.md | sort | uniq -c | sort -rn`
- Show ungraded notes (need `/enrich`)

### Health Check
When the user asks for a health check:
1. Find notes missing frontmatter fields (grade, tags, platform)
2. Find notes with empty Key Takeaways sections
3. Find notes with no Action Items
4. Report which notes need `/enrich`

### Review
When the user asks to review a topic across notes:
1. Search all notes for the topic
2. Compile a cross-note summary pulling from multiple sources
3. Highlight contradictions or complementary viewpoints

## Example usage

```
/kb search whisper
/kb list
/kb stats
/kb health
/kb review "AI transcription tools"
```
