---
name: feedback_ai_tells
description: The markers that make text read as machine-written, and the plain-language test that catches the ones no list holds. Every sentence passes the test before the text is handed over.
metadata:
  type: feedback
---

A list of banned phrases can never be complete. The rule is a test that every sentence passes before the text is handed over. The markers below are worked examples of the test failing.

**The test.** Read each sentence as if saying it to the reader across a desk:

1. Would I say this out loud to a colleague? If it only works on paper, write the spoken version.
2. Does every word carry information? Delete each candidate word and re-read. If the meaning is unchanged, it stays deleted.
3. Is every word one a colleague uses in ordinary speech?
4. Is it literal? Replace any image or figure of speech with the thing itself.
5. Is it one idea? Split a sentence that stacks clauses, semicolons or parentheses.
6. Is it a report, not a verdict? Give what was run, read or seen.
7. Does it add, rather than frame? Cut anything that only labels, announces or grades what follows.
8. Would the reader learn something? Cut what they already know, their own subsystem included.
9. Is it timeless? No drafting history, no account of the analysis.

**The markers.**

- Legalese and retraction narration: "I concede", "I withdraw", "taking these in turn", "for the record", "scratch that", "my mistake", "disregard that". Agree plainly instead.
- Em-dashes anywhere. Smart quotes, the ellipsis character, one-character arrows.
- Opener fluff: "Great question", "I'd be happy to", "Certainly", "Sure thing", "Of course" as a filler.
- Narration: "Let me ...", "Now, let's ...", "Here's what I found:".
- Signposts: "It's worth noting that", "It's important to note", "Note that" overused, "As you may know".
- Filler words: "actually", "basically", "essentially", "simply", "just", "quite", "very", "really", "in fact", "at this point", "going forward", "overall", and "here" or "in this ticket" pointing at the ticket the comment is already on. Also phrases that only say work was thorough: "to be thorough", "for completeness", "as a sanity check", "just to confirm".
- Announcing that more follows: "A few extra observations.", "Two more points." Write the next paragraph.
- Correction wording where nothing is corrected: "This still reproduces", "As noted above". A new result is a report.
- Transition chains: "Furthermore", "Moreover", "Additionally", "In addition", "Overall,", "Ultimately,", "In conclusion,", "That being said,".
- Both-sides padding: "On one hand ... on the other hand ...".
- Marketing words: "comprehensive", "robust", "powerful", "seamless", "elegant", "delve", "underscore", "pivotal", "crucial", "vital", "leverage", "realm", "landscape", "testament", "boasts".
- Hyperbole: "trivially", "easily", "obviously", "clearly", "catastrophic", "game over".
- Over-structuring: a bulleted list where one sentence would do, bold labels with colons, fixed sections such as "What / Why / How".
- A noun doing the work of a sentence: "the ask", "the shape", "the lever", "the release-build silence". Say what happens, with a verb.
- The "on why" construction: "On why X reaches Y: ...". It announces an explanation. Give the fact.
- Stiff noun phrases and borrowed verbs: "drove the captured shape", "trips that assertion", "the code read". Use the plain verb: "ran the sequence", "hits that assertion", "from the code it seems that".
- Pronouns with no clear referent: "this sits before it". Name the thing.
- Figurative redundancy framing: "belt-and-suspenders", "defense in depth", "to be safe". If a check is redundant, drop it. If it is needed, name it plainly.
- "Measured" as a label on your own evidence. End the sentence with a colon and give the numbers.
- "Honest" and "honestly" in any form.
- Emoji, tickboxes and status icons in text another person receives.
- Offering work not done and not asked for: "I can attach the testcase", "Happy to run further benchmarks", "Let me know and I will ...".
- Pointing at evidence by position: "the third testcase above", "the matrix answers the question". Name what it does and give the answer in words.

**Try deleting before rewording.** When a sentence reads wrong, cut it and read the paragraph without it. Very often nothing is lost, because the sentence was a lead-in, a framing line or a restatement. Reword only what survives the cut.

**Why:** each marker has reached a reader and been recognized as machine-written. A reader who spots one stops trusting the rest.

**How to apply:** run the test on every sentence, silently, before handing over. Never report the check.

Related: [[feedback_plain_language]], [[feedback_agree_plainly]], [[feedback_no_em_dash_ascii_only]].
