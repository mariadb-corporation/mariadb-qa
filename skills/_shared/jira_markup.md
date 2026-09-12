# Shared rule: Jira wiki markup (jira.mariadb.org)

Jira wiki markup, NOT markdown. Applies to any Jira-bound text (bug reports, comments, descriptions).
Referenced by the `jira-comment`, `mtr_testcase`, and `jira-ticket` skills.

## Markup

- Inline monospace: `{{double-curly}}`, never backticks. Wrap in `{{..}}` EVERY: function/method name; SQL (every inline statement, keyword, clause, token - not just short tokens); system-variable / constant / type / identifier; and file:line ref. Two repeatedly-forgotten cases: (1) a whole inline SQL statement (e.g. `{{SET GLOBAL x = 1}}`), and (2) a function name followed by a file:line - wrap BOTH: `{{find_user}} ({{sql_acl.cc:15740}})`. Plain prose words stay unwrapped. Content inside a `{code}` block is already monospace - do not add `{{..}}` there.
- SQL keywords and data types are UPPERCASE, always: `{{SELECT}}`, `{{UPDATE}}`, `{{FOREIGN KEY}}`, `{{UUID}}`, `{{VARCHAR}}`, `{{TIMESTAMP}}`, `{{BINARY(16)}}`, `{{INET6}}`. Lowercase `{{uuid}}` / `{{varchar}}` is not acceptable, in prose or in a `{code:sql}` block, and that holds even where the DDL or source under test writes them lowercase. Identifiers keep their real case, copied exactly: `{{child_tbl.parent_id}}`, `{{wsrep_normalize_string()}}`, `{{mysql.global_priv}}`.
- Multi-line code: `{code:lang}` blocks (lang = `cpp`, `sql`, `bash`, `c`, `java`, `python`, `text`). SQL and MTR always go in `{code:sql}`, never bare `{code}`. Always carry the `:lang` tag.
- Plain unformatted multi-line (aligned tables, blocks): `{noformat}` ... `{noformat}`.
- Bold: single `*asterisks*`, never double.
- Italic: `_underscores_`.
- Headers: `h2.` / `h3.` at column 0. Rarely needed in a short comment.
- Tables: `|| header || header ||` then `| cell | cell |`.

## Escaping (high-frequency error class)

- Hyphen escape - the one rule: `\-` is allowed ONLY inside a `{{..}}` monospace span. Never anywhere else. Not in a compound word (write `non-default`, `follow-up`, `server-side`), not in a version range (`10.6 - 13.1`), not after a `}}` closer (`{{a}} - {{b}}`, `{{a}} -> {{b}}`), not as a standalone dash, not at all in ordinary prose. Over-escaping is the recurring error; `non\-default` in prose is the current form of it.
- Inside `{{..}}` there are exactly two escapes: (1) an issue key, `{{MDEV\-12345}}` / `{{MENT\-1234}}`; (2) a LEADING `--` option name, `{{\--ssl-crl}}` - one backslash before the leading `--` only, intra-word hyphens stay bare (`{{\--ssl-crl}}`, not `{{\-\-ssl\-crl}}`), else the leading `--` renders as strikethrough. A bare `MDEV-12345` in prose stays unescaped, so Jira auto-links the key.
- Check before posting: `grep -n '\\-' <file>`. Every hit must sit inside a `{{..}}` span. Any other hit is wrong - remove the backslash.
- Never use an em-dash. Use a plain hyphen `-`. A lone hyphen with surrounding spaces is safe; strikethrough triggers only on `-text-` hugging a word with no spaces.
- Never start a prose line with `#`; Jira turns it into a numbered-list item. Rephrase so the line starts with a word, or escape as `\#`.
- Identifiers containing `*` or `_` go inside `{{...}}` (no escaping needed inside the braces): `{{char*}}`, `{{auth_string_length}}`.

## Naming and style

- Timeless prose: describe the current state only. No "originally was", "previously this was", "in the prior thread".
- Use full product/version names: `CS 13.0.1` (Community Server) / `ES 12.3.1-1` (Enterprise Server), not internal basedir prefixes.
- An error number carries its symbol: `{{ERROR 1205}}` (`{{ER_LOCK_WAIT_TIMEOUT}}`).
- Try deleting before rewording. When a sentence reads wrong, cut it and read the paragraph without it. Very often nothing is lost, because the sentence was a lead-in, a framing line or a restatement, and the paragraph is better starting on the fact. Reword only what survives the cut.
- Professional, neutral, brief, factual. No hyperbole, no idioms. No teaching/explanatory padding - state the fact.
- Facts only. A MENT or MDEV comment can be read by the customer, so it carries what was run, what came out, what the code does and what the operator sees, and nothing else. Nothing that reads as criticism even if true: not what a defect, a message or a wait cost anyone, not a verdict on our product, a customer, another team's work or anyone's handling of the case. Leave the impact out rather than imply it. An internal judgementi, if ever remotely neeeed, goes in a dev-only comment in the most friendly and collegial manner possible, or off the ticket.
- The reader is a professional: they know the subsystem, the standard terms and the tools, and they use the short forms daily. Give the fact and skip the background, the definition of a standard term and the walk-through of behaviour they work with every day.
