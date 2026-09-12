---
name: feedback_write_to_the_reader
description: Pitch a comment at the person who reads it. A senior developer needs two words to get twenty. Three to five lines is a full comment. Short, and still warm and courteous, never clipped.
metadata:
  type: feedback
---

Pitch each comment at the developer who will read it, not at a general audience. For a senior developer, state the claim in the first sentence, give the mechanism in one clause, give the number, and stop. Three to five lines is a full comment. Cut every framing sentence, every "I ran into this", every restatement of what the ticket already says, and every column of a table that does not change the decision.

The default reader is a professional. They know the subsystem, the standard terms and the tools, and they use the short forms daily. Give the fact and skip the background, the definition of a standard term and the walk-through of what they work with every day.

**Short is not abrupt.** Keep the tone warm, collegial and courteous. Cut the word count, never the courtesy. A bare list of facts with no human tone reads as a complaint. The same facts with one friendly opening or closing clause read as help.

**Shorten the prose, not the proof.** Keep the compact proof in the comment even for a very senior reader: a small result table, or the one command that reproduces the behavior. The concrete evidence makes the point beyond argument and saves them the work.

**Why:** these readers wrote the code under discussion. Explaining the mechanism to them costs their time and reads as condescending. A long comment also hides the one line that changes what they do.

**How to apply:** draft the comment, then delete until only the claim, the mechanism, the evidence and one courteous line remain. If a sentence would not change the reader's next action and carries no warmth, it goes.

Related: [[feedback_brevity_in_bug_reports]], [[feedback_report_dont_direct]], [[feedback_consider_the_audience]].
