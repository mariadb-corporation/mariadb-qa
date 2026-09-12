---
name: feedback_bug_report_wording
description: Wording rules for a bug report a developer reads. "The proposed fix", never "attached". The full version string in every row. The build version on every block of output. One bug per report. No internal identifiers or paths.
metadata:
  type: feedback
---

- **The fix** is "the proposed fix" or "the fix", pasted in the body. Never "the attached fix.diff" or "the fix in another comment". In a public report, no provenance or confidence tag on the fix ("confidence: high", "likely"). State any limit of the fix as a fact.
- **Versions** are written in full in every row: "ES 11.8.7-4 opt", never "FAIL (-4)", which reads as an exit code, an errno or an index. One row per build. Write the plain edition and version a developer knows, never an internal build-directory prefix.
- **Every block of run output** carries the version of the build that produced it, as the block title. A bare {noformat} block is wrong. Two builds mean two blocks, each with its own title.
- **One bug per report.** The developer sees one ticket. Cross-references to sibling findings, catalog numbers, audit logs or chains stay out of the body. Record them in a file beside the report.
- **No internal identifiers or paths.** A job number, a working-directory number, a local path or an internal tool name means nothing to the reader. Name the evidence by what it is: "one core", "the second core", "in one case".
- **Evidence by name, not position.** Not "the third testcase above" or "the matrix answers the question". Name what the testcase does and give the answer in words.

**Why:** the reader sees one comment that stands on its own, and reads it once. Anything they cannot look up or place is noise.

**How to apply:** before saving, search the text for "attached", "(-", a bare {noformat}, and any internal path or number. Fix each hit.

Related: [[feedback_brevity_in_bug_reports]], [[feedback_consider_the_audience]], [[feedback_jira_markup_habits]].
