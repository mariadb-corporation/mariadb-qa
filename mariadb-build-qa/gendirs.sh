# Created by Roel Van de Paar, MariaDB

set "${1^^}" # Make ${1} uppercase ('san' > 'SAN')
REGEX_EXCLUDE="$(cat REGEX_EXCLUDE 2>/dev/null)"  # Handy to exclude a particular build
if [ -z "${REGEX_EXCLUDE}" ]; then REGEX_EXCLUDE="DUMMYSTRINGNEVERSEEN"; fi

GEN_FILTER="tar|_opt|_dbg"  # _opt/_dbg: build dirs, not basedirs which are -opt/-dbg

if [ "${1}" == "SAN" ]; then
  ls --color=never -d UBASAN_M* TSAN_M* 2>/dev/null | grep -vE "${REGEX_EXCLUDE}" | grep -vE "${GEN_FILTER}"
elif [ "${1}" == "GAL" ]; then
    ls --color=never -d GAL_MD*   2>/dev/null | grep -vE "${GEN_FILTER}"
    ls --color=never -d GAL_EMD* 2>/dev/null | grep -vE "${GEN_FILTER}"
else
  ls --color=never -d EMD*1[0-5].[0-9]* 2>/dev/null | grep -vE "${REGEX_EXCLUDE}" | grep -vE "${GEN_FILTER}" | grep -vE "SAN|GAL"
  ls --color=never -d MD*1[0-5].[0-9]* 2>/dev/null | grep -vE "${REGEX_EXCLUDE}" | grep -vE "${GEN_FILTER}" | grep -vE "SAN|GAL"
  ls --color=never -d MS*[589].[0-9]* 2>/dev/null | grep -vE "${REGEX_EXCLUDE}" | grep -vE "${GEN_FILTER}" | grep -vE "SAN|GAL"
  if [ "${1}" == "ALLALL" ]; then
    ls --color=never -d UBASAN_M* TSAN_M* 2>/dev/null | grep -vE "${GEN_FILTER}"
    ls --color=never -d GAL_M*   2>/dev/null | grep -vE "${GEN_FILTER}"
    ls --color=never -d MONTY_M* 2>/dev/null | grep -vE "${GEN_FILTER}"
  elif [ "${1}" == "ALL" ]; then
    ls --color=never -d UBASAN_M* TSAN_M* 2>/dev/null | grep -vE "${REGEX_EXCLUDE}" | grep -vE "${GEN_FILTER}"
    ls --color=never -d GAL_M*   2>/dev/null | grep -vE "${REGEX_EXCLUDE}" | grep -vE "${GEN_FILTER}"
    ls --color=never -d MONTY_M* 2>/dev/null | grep -vE "${REGEX_EXCLUDE}" | grep -vE "${GEN_FILTER}"
  fi
fi
