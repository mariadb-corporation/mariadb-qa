---
name: feedback_plain_language
description: Write plain, literal, neutral language. Keep idioms, metaphors, heavy engineering words and dramatic framing out of explanations, commit messages, code comments and summaries. Say plainly what the thing does.
metadata:
  type: feedback
---

Write plain, literal, neutral language in an explanation, a commit message, a comment and a summary.

**Idioms and metaphors stay out.** "Belt-and-braces", "kick the tyres", "ducks in a row", "smoking gun", "low-hanging fruit", "moving parts", "rabbit hole", "north star". Say the literal thing: "plus a COMMIT at the end", "then it runs", "steps", "direct evidence".

**Heavy words go to plain words** when the plain word does the same work: "invariant" becomes "rule"; "canonical" goes; "contract" and "guarantee" become "rule", or state the rule; "executes" becomes "runs"; "validated" becomes "checked"; "pinned" becomes "configured", "set" or "required"; "no-op" becomes "does nothing"; "guard" becomes "check" or "assertion". A coined hyphen compound counts: "it appears only with the mode set", not "it is mode-dependent". When two words fit, the shorter and more common one is right.

**Verb choice.** The server gives or returns an error. It does not raise, throw, emit, surface or yield one.

**Dramatic wording goes to neutral wording.** "Critical", "severe", "violation", "broken state", "must never" and "absolutely" go. State what happens. A crash is a crash, never "benign"; an assertion failure on a debug build is a real bug.

**A note a developer reads** opens with the point itself, as a colleague would say it. No abstract label first ("A trust-model note", "Observation:", "Summary:") and no scaffolding ("Suggestions:", "Repro:", "Impact:"). A short note is a few sentences of flowing prose. Bullets only for a real list of separate items.

**A code comment** says what the code does, or why a non-obvious decision stands. Nothing else.

**A review or QA summary** is plain English. Function names, file and line citations and macro names stay out of the prose. One evidence line may carry a code detail, only when the point needs it. Start each item with the plain outcome and what it means: "a revoked certificate still logs in, so revocation does nothing".

**One trap:** keep dramatic wording out of the exceptions too. An invented exception such as "unless literally X" brings back the problem.

**Why:** a flourish slows the reader, who must translate it before reaching the fact. A word that sounds precise to a programmer reads as heavy to a reader who only wants the rule. Dramatic wording overstates a known edge case and carries no information.

**How to apply:** read each sentence as if saying it to a colleague across a desk. Replace every image with the thing itself and every borrowed word with the common one. When a phrase fails and no plain replacement comes, the sentence carries a thought that is not yet clear: work out what was seen, and write that.

Related: [[feedback_ai_tells]], [[feedback_consider_the_audience]].
