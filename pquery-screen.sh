#!/bin/bash
# Reattach to a screen when a name is passed, then list all screens in columns.
# A screen that was started inside another screen, or that is attached from
# inside one now, is listed below that screen, with the process running in it.

if [ ! -z "${1}" ]; then screen -d -r "${*}"; fi

MONTHS='JanFebMarAprMayJunJulAugSepOctNovDec'

pretty_time(){  # ${1}=month ${2}=day ${3}=year ${4}=hh:mm:ss. Sets PRETTY
  local HOUR="$(( 10#${4%%:*} ))" HOUR12 HALF='AM'
  HOUR12="$(( HOUR % 12 ))"
  if [ "${HOUR12}" -eq 0 ]; then HOUR12=12; fi
  if [ "${HOUR}" -ge 12 ]; then HALF='PM'; fi
  printf -v PRETTY '%02d/%02d/%04d %02d:%s %s' "$(( 10#${1} ))" "$(( 10#${2} ))" "$(( 10#${3} ))" "${HOUR12}" "${4#*:}" "${HALF}"
}

screen_of(){  # ${1}=process. Sets INSIDE to the screen it was started under
  local ENTRY
  INSIDE=
  while IFS= read -r -d '' ENTRY; do
    if [ "${ENTRY:0:4}" = 'STY=' ]; then INSIDE="${ENTRY:4}"; return; fi
  done < "/proc/${1}/environ" 2>/dev/null
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
declare -A COMM TTYOF TICKS FGROUP KIDS SCREENAT CLIENTS WINDOWAT
while read -r PROC PARENT TPGRP TTY CMD ARGS; do
  COMM["${PROC}"]="${CMD}"
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

running_in(){  # ${1}=screen. Sets RUNNING to what is in the foreground in its first window
  local FRONT
  RUNNING=
  windows_of "${1}"
  if [ "${#ORDERED[@]}" -eq 0 ]; then return; fi
  FRONT="${FGROUP[${ORDERED[0]}]}"
  if [ -z "${COMM[${FRONT}]}" ]; then FRONT="${ORDERED[0]}"; fi
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
HERE="$(ps -o tty= -p $$)"  # The window this runs in, to mark it in the list
HERE="${HERE// /}"

add_screen(){  # ${1}=screen ${2}=depth ${3}=tree mark
  local SUBS=(${SUBSCREENS[${1}]}) INDENT="$(( 2 * ${2} ))" YOU= EXTRA= INDEX MARK
  windows_of "${1}"
  for WINDOW in "${ORDERED[@]}"; do
    if [ "${TTYOF[${WINDOW}]}" = "${HERE}" ]; then YOU='  <- you are here'; fi
  done
  if [ "${2}" -gt 0 ]; then
    running_in "${1}"
    EXTRA="  (${RUNNING})"
  fi
  ROWS+=("${INDENT}"$'\t'"${3}"$'\t'"${NAMEOF[${1}]}"$'\t'"${1}"$'\t'"${WHENOF[${1}]}"$'\t'"${STATEOF[${1}]}${EXTRA}${YOU}")
  if [ "$(( ${#NAMEOF[${1}]} + INDENT ))" -gt "${WIDTH}" ]; then WIDTH="$(( ${#NAMEOF[${1}]} + INDENT ))"; fi
  if [ "${#1}" -gt "${PIDWIDTH}" ]; then PIDWIDTH="${#1}"; fi
  for INDEX in "${!SUBS[@]}"; do
    MARK='├'
    if [ "${INDEX}" -eq "$(( ${#SUBS[@]} - 1 ))" ]; then MARK='└'; fi
    add_screen "${SUBS[${INDEX}]}" "$(( ${2} + 1 ))" "${MARK}"
  done
}

for SCREEN in "${ORDER[@]}"; do
  if [ -z "${PARENTOF[${SCREEN}]}" ]; then add_screen "${SCREEN}" 0 'row'; fi
done

printf '%s\n' "${BEFORE[@]}"
for ROW in "${ROWS[@]}"; do
  IFS=$'\t' read -r INDENT MARK NAME PROC WHEN STATE <<<"${ROW}"
  if [ "${MARK}" = 'row' ]; then
    printf '    %-*s    %*s  (%s)  %s\n' "${WIDTH}" "${NAME}" "${PIDWIDTH}" "${PROC}" "${WHEN}" "${STATE}"
  else
    printf '    %*s%s %-*s    %*s  (%s)  %s\n' "$(( INDENT - 2 ))" '' "${MARK}" "$(( WIDTH - INDENT ))" "${NAME}" "${PIDWIDTH}" "${PROC}" "${WHEN}" "${STATE}"
  fi
done
printf '%s\n' "${AFTER[@]}"
