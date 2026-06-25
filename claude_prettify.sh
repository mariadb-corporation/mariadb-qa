#!/bin/bash
# Created by Roel Van de Paar, MariaDB

# CLP = CLaude Prettify
# Reflows indented Claude Code terminal output into copy-and-paste ready text.
# Per input block it strips 2+ leading spaces from each line, joins wrapped lines
# with a single space, and keeps one blank line between paragraphs (a blank line
# in the input). Jira {code}/{noformat} fences pass through verbatim (only the
# base indent is removed), and lines beginning with a "- " or "* " bullet each
# stay on their own line. Loops: paste a block, then Ctrl-D to prettify it.
# Ctrl-D on empty input, or Ctrl-C, exits. Prompts go to stderr so stdout holds
# only the result (handy for piping: clp < file > out).

set +H

prettify() {
  awk '
    function flush(   bullet) {
      if (para == "") return
      bullet = (para ~ /^[-*] /)
      if (printed && !(bullet && lastbullet)) print ""
      print para
      printed = 1
      lastbullet = bullet
      para = ""
    }
    {
      raw = $0
      sub(/[ \t]+$/, "", raw)
      if (incode) {
        bare = raw; sub(/^[ \t]+/, "", bare)
        if (bare == fence) { print bare; incode = 0; next }
        code = raw; sub(/^  /, "", code); print code; next
      }
      line = raw
      sub(/^  +/, "", line)
      if (line ~ /^\{(code|noformat)(:[^}]*)?\}$/) {
        flush()
        if (printed) print ""
        print line
        printed = 1; lastbullet = 0; incode = 1
        fence = (line ~ /^\{code/) ? "{code}" : "{noformat}"
        next
      }
      if (line == "") { flush(); next }
      if (line ~ /^[-*] /) { flush(); para = line; next }
      para = (para == "" ? line : para " " line)
    }
    END { flush() }
  '
}

while true; do
  echo "--- Paste Claude output, then Ctrl-D to prettify (Ctrl-D empty / Ctrl-C to exit) ---" >&2
  mapfile -t LINES
  if [ ${#LINES[@]} -eq 0 ]; then
    echo "Done." >&2
    break
  fi
  echo "--------------------------------------------------------------------------------" >&2
  printf '%s\n' "${LINES[@]}" | prettify
  echo "--------------------------------------------------------------------------------" >&2
done

exit 0
