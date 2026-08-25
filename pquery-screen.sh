#!/bin/bash
# Reattach to a screen when a name is passed, then list all screens in columns.
# A pid can also be that of a process inside a screen: the attach then goes to
# the screen holding it, straight to the window it runs in.
# The windows of a screen are listed below it, each with the process running in
# it. A screen that was started inside another screen, or that is attached from
# inside one now, is listed below that screen as well. A screen or window that
# holds a claude session shows that session's short id and name after the pid.
# A session that has ended is shown in brackets while its window is still there.

screen_of(){  # ${1}=process. Sets INSIDE to the screen it was started under
  local ENTRY
  INSIDE=
  while IFS= read -r -d '' ENTRY; do
    if [ "${ENTRY:0:4}" = 'STY=' ]; then INSIDE="${ENTRY:4}"; return; fi
  done 2>/dev/null < "/proc/${1}/environ"
}

window_number(){  # ${1}=window. Sets NUMBER to the number screen gave that window
  local ENTRY
  NUMBER=
  while IFS= read -r -d '' ENTRY; do
    if [ "${ENTRY:0:7}" = 'WINDOW=' ]; then NUMBER="${ENTRY:7}"; return; fi
  done 2>/dev/null < "/proc/${1}/environ"
}

if [ ! -z "${1}" ]; then
  ATTACH=("${*}")
  if [[ "${1}" =~ ^[0-9]+$ ]] && [[ "$(screen -ls)" != *$'\t'"${1}".* ]]; then
    screen_of "${1}"  # Not a screen of its own, so find the one it runs inside
    window_number "${1}"
    if [ ! -z "${INSIDE}" ]; then
      ATTACH=("${INSIDE}")
      if [ ! -z "${NUMBER}" ]; then ATTACH+=('-p' "${NUMBER}"); fi
    fi
  fi
  screen -d -r "${ATTACH[@]}"
fi

pretty_time(){  # ${1}=month ${2}=day ${3}=hh:mm:ss. Sets PRETTY to dd/mm hh:mm
  printf -v PRETTY '%02d/%02d %s' "$(( 10#${2} ))" "$(( 10#${1} ))" "${3%:*}"
}

# The screens, in the order screen -ls lists them
LIST="$(screen -ls)"
SCREENS=' '
ORDER=()
BEFORE=()
declare -A NAMEOF WHENOF STATEOF PARENTOF SUBSCREENS
while IFS=$'\t' read -r ID WHEN STATE; do
  if [[ ! "${ID}" =~ ^[0-9]+\. ]]; then  # The header and total lines carry no columns
    if [ "${#ORDER[@]}" -eq 0 ]; then BEFORE+=("${ID}"); fi  # Only needed if there is nothing to list
    continue
  fi
  WHEN="${WHEN//[()]/}"
  STATE="${STATE//[()]/}"
  if [[ "${WHEN}" =~ ^([0-9]{2})/([0-9]{2})/([0-9]{2})\ ([0-9:]{8})$ ]]; then
    pretty_time "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[4]}"
    WHEN="${PRETTY}"
  fi
  ORDER+=("${ID%%.*}")
  SCREENS+="${ID%%.*} "
  NAMEOF["${ID%%.*}"]="${ID#*.}"
  WHENOF["${ID%%.*}"]="${WHEN}"
  STATEOF["${ID%%.*}"]="${STATE}"
done <<<"${LIST}"

# One process snapshot. Only a window of a screen, and a screen client, need more than a name
declare -A COMM TTYOF TICKS FGROUP KIDS SCREENAT CLIENTS WINDOWAT PPIDOF ALLKIDS SIDOF SNAMEOF
CLAUDES=()
while read -r PROC PARENT TPGRP TTY CMD ARGS; do
  COMM["${PROC}"]="${CMD}"
  PPIDOF["${PROC}"]="${PARENT}"
  ALLKIDS["${PARENT}"]="${ALLKIDS[${PARENT}]} ${PROC}"
  if [ "${CMD}" = 'claude' ]; then CLAUDES+=("${PROC}"); fi
  if [ "${CMD}" = 'screen' ] && [ "${TTY}" != '?' ]; then CLIENTS["${PROC}"]="${TTY} ${ARGS}"; fi
  if [[ "${SCREENS}" == *" ${PROC} "* ]]; then SCREENAT["${PARENT}"]="${PROC}"; fi  # A screen, as seen from the client that started it
  if [[ "${SCREENS}" != *" ${PARENT} "* ]]; then continue; fi
  TTYOF["${PROC}"]="${TTY}"
  FGROUP["${PROC}"]="${TPGRP}"
  KIDS["${PARENT}"]="${KIDS[${PARENT}]} ${PROC}"
  WINDOWAT["${TTY}"]="${PARENT}"  # Which screen this window belongs to
  STAT=
  read -r STAT < "/proc/${PROC}/stat" 2>/dev/null
  STAT="${STAT#*) }"  # Drop the pid and the command name, as the name can hold spaces
  set -- ${STAT}
  TICKS["${PROC}"]="${20:-0}"  # Start time in clock ticks, which orders the windows by age
done <<<"$(ps -eo pid=,ppid=,tpgid=,tty=,comm=,args=)"

# The claude session in a screen or window, mapped to every process above it.
# The statusline keeps /tmp/.claude_session_ids.<uid>/<claude pid> map files.
# Without one yet, a child's environment or a --resume id fills the gap.
# Its short name, the one the statusline shows, comes from ~/.claude/sessions/.
SIDMAP="/tmp/.claude_session_ids.${UID}"
TTYMAP="${SIDMAP}/tty"
SESSIONS="${HOME}/.claude/sessions"
session_of(){  # ${1}=claude process. Sets SESSION to its session id, or to ?
  local KID ENTRY WORD PREV=
  SESSION=
  if [ -s "${SIDMAP}/${1}" ] && [ "${SIDMAP}/${1}" -nt "/proc/${1}" ]; then
    read -r SESSION < "${SIDMAP}/${1}"
    if [ ! -z "${SESSION}" ]; then return; fi
  fi
  for KID in ${ALLKIDS[${1}]}; do
    while IFS= read -r -d '' ENTRY; do
      if [ "${ENTRY:0:23}" = 'CLAUDE_CODE_SESSION_ID=' ]; then SESSION="${ENTRY:23}"; return; fi
    done 2>/dev/null < "/proc/${KID}/environ"
  done
  while IFS= read -r -d '' WORD; do
    if [[ "${PREV}" =~ ^(--resume|-r|--session-id)$ ]] && [[ "${WORD}" =~ ^[0-9a-f-]{36}$ ]]; then SESSION="${WORD}"; return; fi
    PREV="${WORD}"
  done 2>/dev/null < "/proc/${1}/cmdline"
  SESSION='?'
}
name_of(){  # ${1}=claude process. Sets SNAME to its session name, empty when it has none
  local JSON
  SNAME=
  if [ -s "${SESSIONS}/${1}.json" ] && [ "${SESSIONS}/${1}.json" -nt "/proc/${1}" ]; then
    read -r JSON < "${SESSIONS}/${1}.json"
    if [[ "${JSON}" =~ \"name\":\"([^\"]*)\" ]]; then SNAME="${BASH_REMATCH[1]}"; fi
  fi
}
for CLAUDE in "${CLAUDES[@]}"; do
  session_of "${CLAUDE}"
  name_of "${CLAUDE}"
  UP="${CLAUDE}"
  while [ ! -z "${UP}" ] && [ "${UP}" != '0' ] && [ "${UP}" != '1' ]; do
    if [ -z "${SIDOF[${UP}]}" ]; then SIDOF["${UP}"]="${SESSION:0:8}"; SNAMEOF["${UP}"]="${SNAME}"; fi
    UP="${PPIDOF[${UP}]}"
  done
done

last_in(){  # ${1}=window ${2}=its tty. Sets LAST to the session last seen there, empty when there is none
  local FILE="${TTYMAP}/${2//\//-}"
  LAST=
  if [ -s "${FILE}" ] && [ "${FILE}" -nt "/proc/${1}" ]; then read -r LAST < "${FILE}"; fi
}

windows_of(){  # ${1}=screen. Sets ORDERED to its windows, oldest first
  local WINDOW SLOT
  ORDERED=()
  for WINDOW in ${KIDS[${1}]}; do
    SLOT="${#ORDERED[@]}"
    while [ "${SLOT}" -gt 0 ] && [ "${TICKS[${ORDERED[$(( SLOT - 1 ))]}]}" -gt "${TICKS[${WINDOW}]}" ]; do
      ORDERED["${SLOT}"]="${ORDERED[$(( SLOT - 1 ))]}"
      SLOT="$(( SLOT - 1 ))"
    done
    ORDERED["${SLOT}"]="${WINDOW}"
  done
}

running_in(){  # ${1}=window. Sets RUNNING to what is in the foreground in that window
  local FRONT="${FGROUP[${1}]}"
  if [ -z "${COMM[${FRONT}]}" ]; then FRONT="${1}"; fi
  RUNNING="${COMM[${FRONT}]}"
}

# A screen started inside another screen keeps that screen in its environment
for SCREEN in "${ORDER[@]}"; do
  screen_of "${SCREEN}"
  if [ ! -z "${INSIDE}" ] && [ "${INSIDE%%.*}" != "${SCREEN}" ] && [[ "${SCREENS}" == *" ${INSIDE%%.*} "* ]]; then
    PARENTOF["${SCREEN}"]="${INSIDE%%.*}"
  fi
done

# A screen attached from inside another screen right now sits below that screen instead
for CLIENT in "${!CLIENTS[@]}"; do
  CLIENTTTY="${CLIENTS[${CLIENT}]%% *}"
  HOST="${WINDOWAT[${CLIENTTTY}]}"
  if [ -z "${HOST}" ]; then continue; fi  # This client does not run inside a screen
  TARGET="${SCREENAT[${CLIENT}]}"  # The screen this client started itself
  if [ -z "${TARGET}" ]; then  # A reconnect, so take the screen its command line names
    for WORD in ${CLIENTS[${CLIENT}]#* }; do
      for SCREEN in "${ORDER[@]}"; do
        if [ "${STATEOF[${SCREEN}]}" = 'Attached' ] && [[ "${SCREEN}.${NAMEOF[${SCREEN}]}" == *"${WORD}"* ]]; then TARGET="${SCREEN}"; fi
      done
    done
  fi
  if [ ! -z "${TARGET}" ] && [ "${TARGET}" != "${HOST}" ]; then PARENTOF["${TARGET}"]="${HOST}"; fi
done

for SCREEN in "${ORDER[@]}"; do
  if [ ! -z "${PARENTOF[${SCREEN}]}" ]; then SUBSCREENS["${PARENTOF[${SCREEN}]}"]="${SUBSCREENS[${PARENTOF[${SCREEN}]}]} ${SCREEN}"; fi
done

# Build the rows first, so the columns can be sized to the widest entry, up to
# these caps. A value longer than its cap is cut, and the cut is marked with a +
NAMEMAX=30
SNAMEMAX=13
TITLE=("SCREEN (${#ORDER[@]})" 'PID' 'CLAUDE SID' 'CLAUDE INT' 'STARTED' 'STATE')  # Also the minimum widths
ROWS=()
WIDTH="${#TITLE[0]}"
PIDWIDTH="${#TITLE[1]}"
SIDWIDTH="${#TITLE[2]}"
SNAMEWIDTH="${#TITLE[3]}"
WHENWIDTH="${#TITLE[4]}"
HERE="$(ps -o tty= -p $$)"  # The window this runs in, to mark it in the list
HERE="${HERE// /}"
BOLD= GREY= OFF=
if [ -t 1 ]; then BOLD=$'\033[1m'; GREY=$'\033[38;2;145;145;145m'; OFF=$'\033[0m'; fi

add_row(){  # ${1}=depth ${2}=tree mark ${3}=name ${4}=pid ${5}=middle column ${6}=tail ${7}=session that ended
  local INDENT="$(( 2 * ${1} ))" NAME="${3}" SID="${SIDOF[${4}]:--}" SNAME="${SNAMEOF[${4}]:--}"
  if [ "${SID}" = '-' ] && [ ! -z "${7}" ]; then SID="(${7:0:8})"; fi
  if [ "$(( ${#NAME} + INDENT ))" -gt "${NAMEMAX}" ]; then NAME="${NAME:0:$(( NAMEMAX - INDENT - 1 ))}+"; fi
  if [ "${#SNAME}" -gt "${SNAMEMAX}" ]; then SNAME="${SNAME:0:$(( SNAMEMAX - 1 ))}+"; fi
  ROWS+=("${INDENT}"$'\t'"${2}"$'\t'"${NAME}"$'\t'"${4}"$'\t'"${SID}"$'\t'"${SNAME}"$'\t'"${5}"$'\t'"${6}")
  if [ "$(( ${#NAME} + INDENT ))" -gt "${WIDTH}" ]; then WIDTH="$(( ${#NAME} + INDENT ))"; fi
  if [ "${#4}" -gt "${PIDWIDTH}" ]; then PIDWIDTH="${#4}"; fi
  if [ "${#SID}" -gt "${SIDWIDTH}" ]; then SIDWIDTH="${#SID}"; fi
  if [ "${#SNAME}" -gt "${SNAMEWIDTH}" ]; then SNAMEWIDTH="${#SNAME}"; fi
  if [ "${#5}" -gt "${WHENWIDTH}" ]; then WHENWIDTH="${#5}"; fi
}

add_screen(){  # ${1}=screen ${2}=depth ${3}=tree mark
  local SUBS=(${SUBSCREENS[${1}]}) WINS LEFT WINDOW INDEX MARK YOU= LAST=
  windows_of "${1}"
  WINS=("${ORDERED[@]}")
  if [ "${#WINS[@]}" -lt 2 ]; then  # A lone window is the screen itself, so it adds no depth
    for WINDOW in "${WINS[@]}"; do
      if [ "${TTYOF[${WINDOW}]}" = "${HERE}" ]; then YOU='  <- you are here'; fi
      last_in "${WINDOW}" "${TTYOF[${WINDOW}]}"
    done
    WINS=()
  fi
  add_row "${2}" "${3}" "${NAMEOF[${1}]}" "${1}" "${WHENOF[${1}]}" "${STATEOF[${1}]}${YOU}" "${LAST}"
  LEFT="$(( ${#WINS[@]} + ${#SUBS[@]} ))"
  for WINDOW in "${WINS[@]}"; do
    LEFT="$(( LEFT - 1 ))"
    MARK='├'
    if [ "${LEFT}" -eq 0 ]; then MARK='└'; fi
    window_number "${WINDOW}"
    running_in "${WINDOW}"
    YOU=
    if [ "${TTYOF[${WINDOW}]}" = "${HERE}" ]; then YOU='  <- you are here'; fi
    last_in "${WINDOW}" "${TTYOF[${WINDOW}]}"
    add_row "$(( ${2} + 1 ))" "${MARK}" "window ${NUMBER}" "${WINDOW}" "${TTYOF[${WINDOW}]}" "${RUNNING}${YOU}" "${LAST}"
  done
  for INDEX in "${!SUBS[@]}"; do
    LEFT="$(( LEFT - 1 ))"
    MARK='├'
    if [ "${LEFT}" -eq 0 ]; then MARK='└'; fi
    add_screen "${SUBS[${INDEX}]}" "$(( ${2} + 1 ))" "${MARK}"
  done
}

for SCREEN in "${ORDER[@]}"; do
  if [ -z "${PARENTOF[${SCREEN}]}" ]; then add_screen "${SCREEN}" 0 'row'; fi
done

# One layout for the titles and every row. The first column is composed first,
# as a tree mark is more than one byte and printf pads a field by its bytes
LAYOUT='  %s   %-*s   %s   %-*s   %-*s   %s\n'
if [ "${#ROWS[@]}" -eq 0 ]; then  # No screens, so the screen -ls message says so itself
  printf '%s\n' "${BEFORE[@]}"
else
  printf -v COL1 '%-*s' "${WIDTH}" "${TITLE[0]}"
  printf -v SIDCOL '%-*s' "${SIDWIDTH}" "${TITLE[2]}"
  printf -v HEAD "${LAYOUT}" "${COL1}" "${PIDWIDTH}" "${TITLE[1]}" "${SIDCOL}" "${SNAMEWIDTH}" "${TITLE[3]}" "${WHENWIDTH}" "${TITLE[4]}" "${TITLE[5]}"
  printf '%s%s%s\n' "${BOLD}" "${HEAD%$'\n'}" "${OFF}"
fi
for ROW in "${ROWS[@]}"; do
  IFS=$'\t' read -r INDENT MARK NAME PROC SID SNAME WHEN STATE <<<"${ROW}"
  if [ "${MARK}" = 'row' ]; then
    printf -v COL1 '%-*s' "${WIDTH}" "${NAME}"
  else  # A window or a sub-screen, so the tree mark leads the name
    printf -v COL1 '%*s%s %-*s' "$(( INDENT - 2 ))" '' "${MARK}" "$(( WIDTH - INDENT ))" "${NAME}"
  fi
  printf -v SIDCOL '%-*s' "${SIDWIDTH}" "${SID}"
  if [ "${SID:0:1}" = '(' ]; then SIDCOL="${GREY}${SIDCOL}${OFF}"; fi
  printf "${LAYOUT}" "${COL1}" "${PIDWIDTH}" "${PROC}" "${SIDCOL}" "${SNAMEWIDTH}" "${SNAME}" "${WHENWIDTH}" "${WHEN}" "${STATE}"
done
