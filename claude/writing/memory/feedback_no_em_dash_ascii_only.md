---
name: feedback_no_em_dash_ascii_only
description: Never write the em-dash (U+2014), in any output. Plain ASCII punctuation everywhere. The hyphen, straight quotes, three dots, "->" and ">=".
metadata:
  type: feedback
---

Never write the em-dash character U+2014, in a chat reply, a Jira body, a code comment, a memory, a commit message or a title. Use a spaced hyphen where an em-dash would separate two clauses, or rewrite the sentence. The en-dash (U+2013) stays out as well.

The same for the other one-character glyphs. Straight quotes, not curly. "..." and not the ellipsis character. "->" and not the arrow. ">=" and "<=" and not the single glyphs. Plain ASCII multi-character forms only.

**Why:** the em-dash and the smart glyphs read as machine-written, somebody has to remove them, and they break later processing with grep and sed in a tracker that otherwise holds plain output and code.

**How to apply:** sweep each new artifact before calling it done:

    grep -rlP '\x{2014}|\x{2013}|\x{2018}|\x{2019}|\x{201C}|\x{201D}|\x{2026}|\x{2192}' <dir>

It must return nothing. Sweep silently and never report it.

Related: [[feedback_ai_tells]], [[reference_jira_markup]].
