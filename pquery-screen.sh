#!/bin/bash
# Reattach to a screen when a name is passed, then list all screens in columns.
# A pid can also be that of a process inside a screen: the attach then goes to
# the screen holding it, straight to the window it runs in.
# The windows of a screen are listed below it, each with the process running in
# it. A screen that was started inside another screen, or that is attached from
# inside one now, is listed below that screen as well. A screen or window that
# holds a claude session shows that session's short id after the pid.

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

MONTHS='JanFebMarAprMayJunJulAugSepOctNovDec'

pretty_time(){  # ${1}=month ${2}=day ${3}=year ${4}=hh:mm:ss. Sets PRETTY
  local HOUR="$(( 10#${4%%:*} ))" HOUR12 HALF='AM'
  HOUR12="$(( HOUR % 12 ))"
  if [ "${HOUR12}" -eq 0 ]; then HOUR12=12; fi
  if [ "${HOUR}" -ge 12 ]; then HALF='PM'; fi
  printf -v PRETTY '%02d/%02d/%04d %02d:%s %s' "$(( 10#${1} ))" "$(( 10#${2} ))" "$(( 10#${3} ))" "${HOUR12}" "${4#*:}" "${HALF}"
}

# The screens, in the order screen -ls lists them
LIST="$(screen -ls)"
SCREENS=' '
ORDER=()
BEFORE=()
AFTER=()
declare -A NAMEOF WHENOF STATEOF PARENTOF SUBSCREENS
while IFS=$'\t' read -r ID WHEN STATE; do
  if [[ ! "${ID}" =~ ^[0-9]+\. ]]; then  # The header and total lines carry no columns
    if [ "${#ORDER[@]}" -eq 0 ]; then BEFORE+=("${ID}"); else AFTER+=("${ID}"); fi
    continue
  fi
  WHEN="${WHEN//[()]/}"
  if [[ "${WHEN}" =~ ^([0-9]{2})/([0-9]{2})/([0-9]{2})\ ([0-9:]{8})$ ]]; then
    pretty_time "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "20${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"
    WHEN="${PRETTY}"
  fi
  ORDER+=("${ID%%.*}")
  SCREENS+="${ID%%.*} "
  NAMEOF["${ID%%.*}"]="${ID#*.}"
  WHENOF["${ID%%.*}"]="${WHEN}"
  STATEOF["${ID%%.*}"]="${STATE}"
done <<<"${LIST}"

# One process snapshot. Only a window of a screen, and a screen client, need more than a name
declare -A COMM TTYOF TICKS FGROUP KIDS SCREENAT CLIENTS WINDOWAT PPIDOF ALLKIDS SIDOF
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
SIDMAP="/tmp/.claude_session_ids.${UID}"
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
for CLAUDE in "${CLAUDES[@]}"; do
  session_of "${CLAUDE}"
  UP="${CLAUDE}"
  while [ ! -z "${UP}" ] && [ "${UP}" != '0' ] && [ "${UP}" != '1' ]; do
    if [ -z "${SIDOF[${UP}]}" ]; then SIDOF["${UP}"]="${SESSION:0:8}"; fi
    UP="${PPIDOF[${UP}]}"
  done
done

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
        if [ "${STATEOF[${SCREEN}]}" = '(Attached)' ] && [[ "${SCREEN}.${NAMEOF[${SCREEN}]}" == *"${WORD}"* ]]; then TARGET="${SCREEN}"; fi
      done
    done
  fi
  if [ ! -z "${TARGET}" ] && [ "${TARGET}" != "${HOST}" ]; then PARENTOF["${TARGET}"]="${HOST}"; fi
done

for SCREEN in "${ORDER[@]}"; do
  if [ ! -z "${PARENTOF[${SCREEN}]}" ]; then SUBSCREENS["${PARENTOF[${SCREEN}]}"]="${SUBSCREENS[${PARENTOF[${SCREEN}]}]} ${SCREEN}"; fi
done

# Build the rows first, so the columns can be sized to the widest entry
ROWS=()
WIDTH=4
PIDWIDTH=3
SIDWIDTH=1
WHENWIDTH=4
HERE="$(ps -o tty= -p $$)"  # The window this runs in, to mark it in the list
HERE="${HERE// /}"

add_row(){  # ${1}=depth ${2}=tree mark ${3}=name ${4}=pid ${5}=middle column ${6}=tail
  local INDENT="$(( 2 * ${1} ))" SID="${SIDOF[${4}]:--}"
  ROWS+=("${INDENT}"$'\t'"${2}"$'\t'"${3}"$'\t'"${4}"$'\t'"${SID}"$'\t'"${5}"$'\t'"${6}")
  if [ "$(( ${#3} + INDENT ))" -gt "${WIDTH}" ]; then WIDTH="$(( ${#3} + INDENT ))"; fi
  if [ "${#4}" -gt "${PIDWIDTH}" ]; then PIDWIDTH="${#4}"; fi
  if [ "${#SID}" -gt "${SIDWIDTH}" ]; then SIDWIDTH="${#SID}"; fi
  if [ "${#5}" -gt "${WHENWIDTH}" ]; then WHENWIDTH="${#5}"; fi
}

add_screen(){  # ${1}=screen ${2}=depth ${3}=tree mark
  local SUBS=(${SUBSCREENS[${1}]}) WINS LEFT WINDOW INDEX MARK YOU=
  windows_of "${1}"
  WINS=("${ORDERED[@]}")
  if [ "${#WINS[@]}" -lt 2 ]; then  # A lone window is the screen itself, so it adds no depth
    for WINDOW in "${WINS[@]}"; do
      if [ "${TTYOF[${WINDOW}]}" = "${HERE}" ]; then YOU='  <- you are here'; fi
    done
    WINS=()
  fi
  add_row "${2}" "${3}" "${NAMEOF[${1}]}" "${1}" "${WHENOF[${1}]}" "${STATEOF[${1}]}${YOU}"
  LEFT="$(( ${#WINS[@]} + ${#SUBS[@]} ))"
  for WINDOW in "${WINS[@]}"; do
    LEFT="$(( LEFT - 1 ))"
    MARK='├'
    if [ "${LEFT}" -eq 0 ]; then MARK='└'; fi
    window_number "${WINDOW}"
    running_in "${WINDOW}"
    YOU=
    if [ "${TTYOF[${WINDOW}]}" = "${HERE}" ]; then YOU='  <- you are here'; fi
    add_row "$(( ${2} + 1 ))" "${MARK}" "window ${NUMBER}" "${WINDOW}" "${TTYOF[${WINDOW}]}" "${RUNNING}${YOU}"
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

printf '%s\n' "${BEFORE[@]}"
for ROW in "${ROWS[@]}"; do
  IFS=$'\t' read -r INDENT MARK NAME PROC SID WHEN STATE <<<"${ROW}"
  PAD="$(( WHENWIDTH - ${#WHEN} ))"
  if [ "${MARK}" = 'row' ]; then
    printf '    %-*s    %*s  %-*s  (%s)%*s  %s\n' "${WIDTH}" "${NAME}" "${PIDWIDTH}" "${PROC}" "${SIDWIDTH}" "${SID}" "${WHEN}" "${PAD}" '' "${STATE}"
  else
    printf '    %*s%s %-*s    %*s  %-*s  (%s)%*s  %s\n' "$(( INDENT - 2 ))" '' "${MARK}" "$(( WIDTH - INDENT ))" "${NAME}" "${PIDWIDTH}" "${PROC}" "${SIDWIDTH}" "${SID}" "${WHEN}" "${PAD}" '' "${STATE}"
  fi
done
printf '%s\n' "${AFTER[@]}"
