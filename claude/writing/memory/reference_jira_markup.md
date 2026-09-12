---
name: reference_jira_markup
description: The Jira wiki syntax for a comment or a bug report on a Jira Server or Data Center instance. {code:lang}, {noformat:title=}, {{inline}}, lists, tables, links and the escape rules. It is not markdown.
metadata:
  type: reference
---

Jira Server and Data Center render the classic wiki markup, not markdown. A markdown backtick or a triple-backtick fence renders as itself.

## Code blocks

    {code:cpp}
    int x = 0;
    return uint4korr(buf);
    {code}

Languages include java, cpp, c, python, bash, sh, sql, xml, html, javascript and none. {code:lang} is short for {code:language=lang}. Attributes are separated by a pipe: {code:title=Bar.java|collapse=true}.

## Plain preformatted text

For a crash dump, a sanitizer report, a stack or a build configuration, which keep their exact spacing:

    {noformat:title=CS 13.0.1 ... (Debug) Build NN/NN/NNNN}
    mariadb-binlog: sql/log_event.cc:3297: ...: Assertion `...' failed.
    Aborted (core dumped)
    {noformat}

{noformat} with no title also works. nopanel=true removes the border.

## Inline monospace

{{like this}} prints as fixed-width text. Use it for a file path, a function name, a field name, an option and a short piece of code in prose. A letter straight after the closing braces is a parse error: write {{THDs}}, never {{THD}}s.

## Inline text effects

| Want | Markup |
|---|---|
| bold | *bold* |
| italic | _italic_ |
| citation | ??cited?? |
| strikethrough | -strikethrough- |
| inserted | +inserted+ |
| superscript | text^sup^ |
| subscript | text~sub~ |

Strikethrough needs a pair of dashes directly against a word, as in -like this-. A single hyphen with a space on either side strikes nothing, so a normal hyphen prints correctly and needs no escape.

The \- escape is allowed only inside a {{..}} span, for an issue key ({{MDEV\-12345}}, {{MENT\-1234}}) or a leading -- option name ({{\--ssl-crl}}). Ordinary prose always takes the plain hyphen: a compound word, a version range, a line range, a hyphen or arrow after a }} token, and a bare issue key in prose, which Jira then links.

## Blockquote

One line: bq. quoted line. More than one line: {quote} ... {quote}.

## Headings

h1. through h6. at the start of a line. Leave them out of a bug report body. A section label is a plain line or a "* " bullet line.

## Lists

- Bullet list: a line starting with *; ** and *** for deeper levels.
- Numbered list: a line starting with #; ## and ### for deeper levels.
- A prose line must not start with *, # or ||, or Jira parses it as a list item or a table row.

## Tables

    ||header 1||header 2||header 3||
    |cell|cell|cell|

## Links and images

[link text|https://example.com/] with the text first. [https://example.com/] for a bare URL. !attachment.png! shows an attached image in place; !attachment.png|thumbnail! for a thumbnail.

## Punctuation

Plain ASCII: the hyphen, straight quotes, three dots. A Unicode dash, a curly quote or an ellipsis character looks wrong in a tracker that otherwise holds plain output and code, and it breaks later processing with grep and sed.

## Drafting for Jira

Write the text in Jira markup from the start. {{..}} for an identifier from the first draft; {code:sql} or {code:bash} at once; {noformat:title=...} for crash output, a stack, a version banner and a detection table; a "* " bullet line for a label, never bold. It does not matter that a chat tool shows {{ as itself. Jira renders the text, not the chat tool.
