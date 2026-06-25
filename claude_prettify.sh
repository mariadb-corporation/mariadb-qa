#!/bin/bash
# Created by Roel Van de Paar, MariaDB

# CLP = CLaude Prettify
# Reflows indented Claude Code terminal output into copy-and-paste ready text.
# Per input block it strips 2+ leading spaces from each line, joins wrapped lines
# with a single space, and keeps one blank line between paragraphs (a blank line
# in the input). Loops: paste a block, then Ctrl-D to prettify it. Ctrl-D on empty
# input, or Ctrl-C, exits. Prompts go to stderr so stdout holds only the result
# (handy for piping: clp < file > out).

set +H

prettify() {
  awk '
    function flush() {
      if (para != "") {
        if (printed) print ""
        print para
        printed = 1
        para = ""
      }
    }
    {
      line = $0
      sub(/^  +/, "", line)
      sub(/[ \t]+$/, "", line)
      if (line == "") flush()
      else para = (para == "" ? line : para " " line)
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
