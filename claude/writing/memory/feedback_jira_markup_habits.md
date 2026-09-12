---
name: feedback_jira_markup_habits
description: Jira-bound text is written in Jira wiki markup from the first line, never markdown. Wrap every identifier in {{..}}, tag every {code} block with a language, no bold and no headers, never open a prose line with #, and escape a hyphen only inside a {{..}} span.
metadata:
  type: feedback
---

Write text bound for Jira in wiki markup from the first line. Do not write markdown and convert afterwards. A conversion loses detail and is easy to forget.

**Wrap in {{..}}** every function name, SQL statement or token, system variable, constant, type, identifier, option and file:line. A whole inline statement is wrapped too: {{SET GLOBAL x = 1}}. A function followed by a location wraps both: {{find_user}} ({{sql_acl.cc:15740}}). Plain prose words stay unwrapped. Inside a {code} block nothing is wrapped. A letter straight after a closing }} is a parse error, so write {{THDs}} and never {{THD}}s.

**SQL keywords and data types in UPPERCASE**, always: {{SELECT}}, {{VARCHAR}}, {{FOREIGN KEY}}. Identifiers keep their real case. Quoted output, a stack or someone else's DDL stays byte-exact.

**Blocks.** {code:lang} with a language tag, always. SQL and a test file go in {code:sql}. Logs, stacks, diffs and aligned tables go in {noformat}. A block of run output carries the build version as its title: {noformat:title=CS 11.4.5 ... (Debug)}.

**No bold, no headers.** A labeled point is a "* " bullet line opening with the label. Never h1., h2. or h3., and never *bold* around a label or a sentence.

**Never open a prose line with #, * or ||.** Jira parses it as a list item or a table row. Rephrase so the line opens with a word.

**The hyphen escape** \- is allowed only inside a {{..}} span, and only for an issue key ({{MDEV\-12345}}, {{MENT\-1234}}) or a leading -- option name ({{\--ssl-crl}}, one backslash, inner hyphens bare). Ordinary prose always takes the plain hyphen: "non-default", "10.6 - 13.1", "{{a}} -> {{b}}". A bare issue key in prose stays unescaped, so Jira links it.

**Check before posting:**

    grep -nE '^h[1-6]\.' <file>       # headers: none
    grep -nE '^#' <file>              # lines opening with #: none
    grep -nE 'MDEV\\-|MENT\\-' <file>  # an escaped key outside {{..}}: none
    grep -n '\\-' <file>              # every hit sits inside a {{..}} span

**Why:** the tracker runs Jira Server, which renders wiki markup. A backtick, a fence, a bold label or a stray # renders wrongly, and every over-escaped hyphen shows its backslash to the reader.

**How to apply:** pause when you find yourself typing a backtick, and write {{..}} or a {code} block instead. Run the checks before declaring the text ready.

Related: [[reference_jira_markup]], [[feedback_paste_ready_text_clean]].
