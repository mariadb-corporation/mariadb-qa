---
name: voice-profile
description: Write Jira comments, dev-facing prose, emails, reports and Slack messages in the user's own voice, not generic AI prose. Distilled from <N> of the user's real comments. Use for any text drafted on the user's behalf that another person reads. Other skills defer to this for voice. Improve grammar and professionalism, never at the cost of the user's style or tone.
---

# voice-profile

The voice layer for anything written as the user. The mechanics of a deliverable (Jira markup, test format, report layout) live in the writing rules and the memories. This file defines how the text reads. Goal: a colleague reading the text recognizes the user wrote it, not an assistant.

Grounded in <N> of the user's real comments from <source and years covered>. When unsure, imitate those, not a generic assistant register.

## Role understanding (read first; it governs the whole register)

> fill: the user's role and what it means for the register. A tester reports and suggests. A developer decides on their own code and suggests on others'. Support writes to a customer. Four to eight bullets, each a rule the corpus shows.

<role sentence>

- <rule>
- <rule>

## Principles

> fill: five to nine principles, in the user's own words where the corpus gives them, each with a short quoted example from the corpus.

1. <principle>: "<quoted example>"

## Openings

> fill: how the user opens a reply to a contributor, a fresh question to a person, and a comment with no one to address. Quote three to six real openings verbatim. Replace other people's handles with [~assignee].

- Replying to a contribution: "<quote>"
- Raising a fresh point to a person: "<quote>"
- No one to address: <label examples>

## Agreeing and responding to points

> fill: the exact words the user uses to agree, to acknowledge, to say they were wrong, and to disagree. Quote them. Show how a multi-point message is answered (mirrored numbers, "On your points", inline "#1:").

- Agree: <quotes>
- Wrong: "<quote>"
- Disagree: "<quote>", and the shape it takes
- Multi-point: <the shape, with a short example>

## Connectives, phrase bank and abbreviations

> fill: connectives the user reaches for, phrases seen more than twice, abbreviations they use naturally (keep them), and hedges they use when unsure. Frequencies help: "in about a third of comments".

- Connectives: <list>
- Phrases: <list>
- Abbreviations: <list>
- Hedges when unsure: <list>

## Questions to others

> fill: how the user asks for work or input. Quote three real questions. Note the "please" habit and whether they ask yes/no or open questions.

- "<quote>"

## Closings

> fill: how comments end: a hand-off, a thanks, a terse close. Quote three to five.

- "<quote>"

## Vocabulary

> fill: terms the user always uses and the alternatives they never use; product and team words ("the server", "we"); words in the corpus that a generic rewrite would remove but that must stay.

- Always "<term>", never "<alternative>"
- Keep: <list>

## Mechanics

> fill: spelling variant (check -ize/-ise, -or/-our, "whilst"); sentence length; punctuation habits (a semicolon before a list, a colon before a block); how identifiers are marked per channel; list style. Only what the corpus shows.

- Spelling: <variant>, kept consistent within a piece
- Sentences: <typical length and shape>
- Punctuation: <habits>
- Jira: wiki markup; {{monospace}} for identifiers; evidence in {code:lang} or {noformat}
- Slack: the same voice, a few flowing sentences, backticks for identifiers, no headers or lists unless the content is a list
- The hyphen, never the em-dash. Plain ASCII punctuation.

## Anti-patterns: the markers that are not the user

The generic markers in the ai_tells memory apply in full: legalese and retraction narration, opener fluff, narration, signposts, filler, transition chains, both-sides padding, marketing words, hyperbole, over-structuring, noun labels standing in for a sentence, the "on why" construction, borrowed verbs, pronouns with no referent, figurative idioms, emoji in a deliverable, "measured" as a label, offering undone work, pointing at evidence by position.

> fill: add the markers specific to this user: words or shapes that never appear in the corpus and would read as foreign in their voice. Three to ten items, each with the plain form the user writes instead.

- <marker> -> <what the user writes instead>

## Improvement latitude

> fill: what the user allows to be improved: recurring typos (list them from the corpus), grammar, a stray word. State what a rewrite must never remove: the brevity, the connectives, the abbreviations, the way of agreeing, the team "we".

Fix: <typos and grammar the user allows>. Never use that latitude to turn the voice into neutral corporate or AI prose. Keep <the markers to keep>. If a "more professional" rewrite would erase one of them, keep the marker.

## Worked example

> fill: take one real comment from the corpus that is not quoted above. Write a generic AI draft of the same content first, then show the user's original as the target. Replace handles with [~assignee].

AI draft:

    <generic draft>

The user:

    <the real comment>

## Self-check before handing over

Run this list silently and fix what it catches. Never report it. The absence of a defect is not a result.

- Agreement is plain: no legalese, no retraction narration.
- No em-dash. Plain ASCII.
- No opener fluff, narration, signposts, transition chains, marketing words or hyperbole.
- Leads with the conclusion or a label. A multi-point reply mirrors the other side's structure. Evidence sits in a block.
- Thanks, if any, is brief and specific. Only the person who has to act is mentioned.
- Every request that asks for work carries "please".
- Every sentence read once with each candidate filler word deleted.
- The user's typos fixed. The user's style and abbreviations kept.
- Every sentence passes the plain-language test: spoken, literal, one idea, a report and not a verdict.
- Reads like the corpus, not like a generic assistant.
