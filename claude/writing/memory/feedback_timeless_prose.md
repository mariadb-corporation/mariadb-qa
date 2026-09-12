---
name: feedback_timeless_prose
description: A code comment, a report, a ticket text and a doc describe the current state only. Keep out the discussion that produced it, what it was before, status markers, drafting history and line numbers.
metadata:
  type: feedback
---

One rule, several places it is broken. A code comment, a bug report, a comment file, a doc and a README all describe the current state only. A later reader wants the code, the bug and the behavior as they are now, not the path taken to them.

**Keep out**

- The discussion that produced it: "as agreed", "after we discussed", "as you noted".
- What it was before: "originally", "previously", "was X", "historically".
- Status markers and journal entries: "Done", "Fixed", "Updated", "Finding 12", "as of today", "idea 3".
- The account of the analysis or a correction of an earlier version: "re-scored", "revised", "on re-examination".
- A cross-reference by purpose: "mirrors X", "same scheme as Y".
- A version line, unless the file is a patch or a security report.
- A line number as an anchor. Line numbers move on every edit. Name the function, the option, the message or the section.
- A first-person account of the work in a doc.

**Keep in**

- The current purpose and behavior, and the reason a reader cannot see from the code or the text.
- A hidden rule the code depends on: "must be called before X".
- A short workaround with its reason.
- An open option worded as an option, with the cost of taking it.

**Why:** prose about the past becomes wrong as the code changes, and it reads as one side of a conversation the later reader cannot see. Git holds why a line changed. The ticket holds the discussion.

**How to apply:** ask whether the text would still make sense to a reader in two years who knows nothing about how it got here. Drop any line opening with "Without this", "Fixes", "Mirrors", "Originally", "Before" or "added for". Before saving, search the text for "originally", "previously", "revised", "re-score" and "as agreed", and rewrite each hit to describe the current state. Write less when unsure.

Related: [[feedback_brevity_in_bug_reports]].
