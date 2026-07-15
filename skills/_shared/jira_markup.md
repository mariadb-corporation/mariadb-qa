# Shared rule: Jira wiki markup (jira.mariadb.org)

Jira wiki markup, NOT markdown. Applies to any Jira-bound text (bug reports, comments, descriptions).
Referenced by the `jira-comment`, `mtr_testcase`, and `jira-ticket` skills.

## Markup

- Inline monospace: `{{double-curly}}`, never backticks. Wrap in `{{..}}` EVERY: function/method name; SQL (every inline statement, keyword, clause, token - not just short tokens); system-variable / constant / type / identifier; and file:line ref. Two repeatedly-forgotten cases: (1) a whole inline SQL statement (e.g. `{{SET GLOBAL x = 1}}`), and (2) a function name followed by a file:line - wrap BOTH: `{{find_user}} ({{sql_acl.cc:15740}})`. Plain prose words stay unwrapped. Content inside a `{code}` block is already monospace - do not add `{{..}}` there.
- Multi-line code: `{code:lang}` blocks (lang = `cpp`, `sql`, `bash`, `c`, `java`, `python`, `text`). SQL and MTR always go in `{code:sql}`, never bare `{code}`. Always carry the `:lang` tag.
- Plain unformatted multi-line (aligned tables, blocks): `{noformat}` ... `{noformat}`.
- Bold: single `*asterisks*`, never double.
- Italic: `_underscores_`.
- Headers: `h2.` / `h3.` at column 0. Rarely needed in a short comment.
- Tables: `|| header || header ||` then `| cell | cell |`.

## Escaping (high-frequency error class)

- Backslash-escape the hyphen in two cases only: (1) inside `MDEV-` / `MENT-` issue keys: `{{MDEV\-12345}}`, `{{MENT\-1234}}`; (2) a leading `--` option name inside `{{..}}`: `{{\--ssl-crl}}` - one backslash before the leading `--`, intra-word hyphens stay unescaped (`{{\--ssl-crl}}`, not `{{\-\-ssl\-crl}}`), else the leading `--` renders as strikethrough. Nowhere else: do NOT escape hyphens after a `}}` closer, in compound words (follow-up, server-side), in version ranges (10.6-13.1), or anywhere else in prose. Over-escaping is a recurring error.
- Never use an em-dash. Use a plain hyphen `-`. A lone hyphen with surrounding spaces is safe; strikethrough triggers only on `-text-` hugging a word with no spaces.
- Never start a prose line with `#`; Jira turns it into a numbered-list item. Rephrase so the line starts with a word, or escape as `\#`.
- Identifiers containing `*` or `_` go inside `{{...}}` (no escaping needed inside the braces): `{{char*}}`, `{{auth_string_length}}`.

## Naming and style

- Timeless prose: describe the current state only. No "originally was", "previously this was", "in the prior thread".
- Use full product/version names: `CS 13.0.1` (Community Server) / `ES 12.3.1-1` (Enterprise Server), not internal basedir prefixes.
- Professional, neutral, brief, factual. No hyperbole, no idioms. No teaching/explanatory padding - state the fact.
