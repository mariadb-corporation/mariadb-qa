---
name: feedback_paste_ready_text_clean
description: A paste-ready deliverable longer than one to three paragraphs goes in a file, with its absolute path. In chat, no blockquote prefix and no indentation, because both corrupt the paste. Keep the blank lines between points.
metadata:
  type: feedback
---

A paste-ready deliverable must copy cleanly in one action. This covers a Jira comment, a commit message and a paragraph for a report.

- Longer than one to three paragraphs: write it to a file and give the absolute path in chat instead of the content. The chat breaks newlines, indents lines and mangles Jira markup.
- Never wrap it in a markdown blockquote. A copy carries the "> " prefix.
- Never indent it. A copy carries the leading spaces.
- Keep the blank lines between points that are separate. The paragraph structure is wanted.

**Why:** the text goes straight into the tracker. A prefix and a leading space have to be removed by hand every time.

**How to apply:** a file plus its absolute path by default. In chat only when it is one to three paragraphs, as plain prose in one block.

Related: [[feedback_show_the_deliverable]], [[feedback_jira_markup_habits]].
