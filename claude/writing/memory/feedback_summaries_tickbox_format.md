---
name: feedback_summaries_tickbox_format
description: An end-of-turn work summary in chat is a short column of status bullets, each 10 words or fewer, with no closing paragraph. A flow or a precedence question gets a short ASCII diagram in a code fence. Neither belongs in text another person receives.
metadata:
  type: feedback
---

A work summary in chat, the closing block that says what changed and what is still open, uses a status column:

- One artifact, check or step per line, 10 words or fewer. Longer is prose: write it as prose or cut it.
- A finished line opens with ✅, a blocked line with ❌ and the blocker, a waiting line with ⏳.
- 5 to 15 lines. End on the last bullet, with no closing paragraph. No tables, no dense asides.

**When not to use it:** a one-line answer, a short recommendation of two or three sentences, a direct answer to a question. Two or three remarks that answer a question are plain sentences, not fragments in a column.

**A flow, a precedence or a decision** gets a short ASCII diagram in a code fence, not a column. The diagram shows order and branches at once.

**Never in a deliverable.** Marks, tickboxes and diagrams belong in an internal chat summary only. A Jira comment, an email or a Slack message carries none.

**Why:** a prose summary hides the gaps. A column shows the state at a glance.

**How to apply:** after a multi-step task, close with the column. Otherwise leave the reply bare.

Related: [[feedback_no_boasting_no_false_warnings]], [[feedback_lead_with_the_answer]].
