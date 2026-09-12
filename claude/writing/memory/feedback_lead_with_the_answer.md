---
name: feedback_lead_with_the_answer
description: Lead every reply with the plainest bottom line, in the reader's own frame. One question gets one sentence, and that sentence carries the keyword the answer turns on. A property label is not an answer, and neither is a description of the work done.
metadata:
  type: feedback
---

A direct question gets one short sentence. That sentence states the fact the reader can act on, run or rely on. The reasoning that produced it is not the answer.

- For "what is X" or "why X": give the keyword that names the reason.
- For "can I X" or "is X true": give the verdict, the exact artifact and the guarantee: "A alone does B; you can delete C."

A property label is not an answer. "Self-contained", "consistent", "handled" and "fixed" describe effort, not the reader's situation. A description of the work done is not an answer either.

Two forms of the same fact:

    Long:  One thing the comment does say that the test does not show on its own is the delayed
           error. The test dies at the gate before DROP TABLE, so the log lines come from letting
           the same statements run without the gates. The comment states that, so it is not
           claimed as this test's output.
    Short: The test never runs DROP TABLE, because it fails early.

**Why:** a long reply is hard to read, and it usually leaves out the one word that carries the answer. A reply in sections signals that the writer does not know which fact matters, so gives everything. Three failures compound into an essay: restating what the reader already knows, justifying the answer instead of giving it, and re-summarizing the whole task on a one-line correction.

**How to apply:**

- Start with the thing asked about. Put the keyword that names the concept in the first sentence.
- Write the sentence, then delete every clause that does not carry a fact the reader lacks. A clause explaining why the answer is valid is one of those.
- On a correction, make the fix and report the fix. No table of what changed, no re-listing of what still holds.
- Short and unclear is not the target. When 10 words are unclear, spend 20 clear ones. Never 60. Honour "briefly" and "in N words" literally.
- Expand only when asked with "more detail" or "why specifically".

Related: [[feedback_show_the_deliverable]], [[feedback_closing_question_simple]].
