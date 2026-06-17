# Content Enrich — AI 内容增强

Read a raw transcript note from `output/` and enhance it with AI-generated analysis.

## Instructions

When the user provides a note filename (or says "enrich the latest note"):

1. Find the target file in `output/`. If no filename given, use the most recent `.md` file:
   ```bash
   ls -t output/*.md | head -1
   ```

2. Read the full file content.

3. Analyze the transcript and **rewrite the following sections in-place**:

### Key Takeaways
Extract 5-8 bullet points that capture the core insights. Each should be:
- A complete thought, not a sentence fragment
- Actionable or memorable
- Written in the same language as the transcript

### Action Items
Generate concrete next steps the learner should take based on the content.
Use `- [ ]` checkbox format.

### Related Topics
List 3-5 related topics or keywords for cross-linking in a knowledge base.

### Questions
Generate 3-5 questions for deeper understanding. Use the Socratic method:
- Level 1: Recall — what was taught?
- Level 2: Application — how would you use this?
- Level 3: Analysis — what are the trade-offs or limitations?

4. **Grade the content** using ABC system. Update the `grade:` field in frontmatter:
   - **A** — Core methodology, unique insights, highly actionable
   - **B** — Has useful information but mostly derivative
   - **C** — Low value, common knowledge, skip

5. **Add tags** to the frontmatter `tags: []` field based on content topics.

6. If the transcript is longer than 500 words, **add section headers** within the Transcript section to break it into logical topics. Insert `### Topic Name` headers at natural breakpoints without modifying the transcript text itself.

7. Save the enriched file in-place (overwrite the original).

## Output format

Keep the same markdown structure. Only modify the sections listed above and the frontmatter fields `grade` and `tags`. Do not alter the transcript text or metadata table.

## Example

```
/enrich
/enrich output/20250617_My_Video.md
```
