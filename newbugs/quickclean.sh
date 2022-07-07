#!/bin/bash
set +H

grep --binary-files=text -vE '^[ \t]*$|^#' ${KNOWN_BUGS} 2>/dev/null | sed 's|[ \t]\+##.*$||' | xargs -I{} grep --binary-files=text -Fi "{}" ${PWD}/*.string 2>/dev/null | sed 's|.string:.*$|.*|' | xargs -I{} echo "rm {}" | xargs -I{} bash -c "{}"
