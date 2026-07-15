---
name: jira-comment
description: Draft a short, clear Jira comment for a MariaDB ticket using Jira wiki markup. Use for assignee Q&A, patch-coverage verification, dup-merge clarification, follow-up questions, and similar tester-to-dev exchanges that go into jira.mariadb.org and are paste-ready.
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater
---

# jira-comment

Draft a short, Jira-paste-ready comment for a MariaDB ticket.

## When to use

- Asking the assignee whether a patch fully addresses a reported issue.
- Pointing out a gap in a candidate fix.
- Disclosing that an LLM-assisted analysis surfaced a follow-up concern.
- Suggesting a separate follow-up ticket for an out-of-scope sub-issue.
- Any short tester-to-dev exchange that lives as a comment on a Jira issue page.

Do not use for full bug reports; a comment is a short tester-to-dev exchange, not a bug filing.

## Output format

Plain text, single fenced block in the response, Jira-paste-ready. No surrounding prose outside the block; the user copies it straight into a Jira comment field.

Frame the block with a line of 80 em-dashes (U+2014) directly above and below it. These delimiter lines are display-only - they are not part of the comment and are not copied into Jira (the user copies only the content between them). Use em-dashes, not hyphens: a hyphen line is reinterpreted by the markdown renderer and shows as a thin rule instead of a visible separator. Em-dashes never appear inside the comment content itself.

Write the way a senior developer writes a review comment:

- Lead with the answer or conclusion in the first line.
- Put the evidence in `{code}` / `{noformat}` blocks (code snippets, a small aligned table), not in prose.
- Short declarative lines. No multi-sentence prose paragraphs, no teaching prose, no restating what the dev already said.
- Close with one short, direct question.
- No tickboxes, no status-icon markers, no `(/)` `(x)` `(!)`, no emoji.

Target the whole comment at well under 15 lines. If it needs more, file a separate Jira issue instead.

## Markup rules

Follow `~/mariadb-qa/skills/_shared/jira_markup.md` (Jira wiki markup, `{{monospace}}`, single `*bold*`, hyphen-escape in `MDEV-`/`MENT-` keys and before a leading `--` option (`{{\--ssl-crl}}`), no leading `#`, timeless prose, full CS/ES version names). Two comment-specific reminders:

- Tester-to-dev tone: professional, neutral, brief, factual. No hyperbole ("obviously / clearly / unfortunately"), no idioms.
- Username casing: `[~handle]` mentions use the lowercase Jira username/key (e.g. `[~some_user]`), never the capitalised display form. If matching a comment's author programmatically, note `author.name` is capitalised (`Some_user`) while the key is lowercase (`some_user`) - compare `author.key`, not `author.name`.
- When the comment surfaces a concern produced via an LLM analysis (not direct code reading), say so in one short sentence ("I ran the patch through an LLM-based analysis as a sanity check; the following surfaced:") so the dev knows they are evaluating an LLM-surfaced concern, not a tested reproducer.

## Asking vs. asserting

A question gets a faster response than an assertion that the patch is wrong. Default to a question ("Could you confirm whether...") unless the gap is unambiguous and verified end to end. When asserting an unfixed gap, cite the exact file and line of the missing change.

## Skeleton

```
{one line: the answer or conclusion}

{evidence in a {code} or {noformat} block, file:line carried inside it}

{one line stating the single remaining concern, with file:line}

{one short closing question}
```

## Worked example

User: "draft a comment for MDEV-12345 asking whether commit X fully fixes the reported crash in {{ha_innobase::open}}; the patch adds a null check at {{ha_innodb.cc:5210}} but the same pointer is dereferenced again a few lines down"

Comment:

```
The null check at {{ha_innodb.cc:5210}} closes the reported crash path.

The same pointer is dereferenced again without a guard:
{noformat}
  ha_innodb.cc:5260   second dereference, no null check
{noformat}
A case reaching that path would still fault.

Could you confirm whether {{ha_innodb.cc:5260}} needs the same guard?
```

## Self-check before declaring done

- No backticks (markdown code) and no `**bold**` (markdown bold).
- No em-dash inside the comment content (only the two display-only delimiter lines use them).
- Hyphen escaped inside `MDEV-` / `MENT-` issue keys and before a leading `--` option (`{{\--ssl-crl}}`); nowhere else.
- No leading `#` in any prose line.
- No tickboxes, status icons, or emoji.
- One file:line citation per concern, in a code/noformat block where possible.
- Leads with the conclusion; closes with one short question.
- LLM-assisted analysis disclosed if applicable.
