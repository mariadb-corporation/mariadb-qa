#!/bin/bash
# Set up and start testing SQL runs through gomd.
#
#   qa-run                                   Show the current settings
#   qa-run <basedir> <conf> [opt] [dbg]      Set them, then start the runs
#
# <basedir> is a directory in /test, either the -opt or the -dbg name.
# <conf> is a pquery-run-*.conf in ~/mariadb-qa.
# [opt] and [dbg] are the number of parallel runs per build, 1 each by default.
#
# gomd prints a MON[N]=... line per run. Put those lines in /data/results.list
# with vr, so that r and the reducer handlers see the runs.

set -u
GOMD="${HOME}/gomd"
QA_DIR="${HOME}/mariadb-qa"
[ -x "${GOMD}" ] || { echo "[qa-run] ${GOMD} is missing. Run linkit"; exit 1; }

if [ $# -eq 0 ]; then
  echo "[qa-run] current settings in ${GOMD}"
  grep -E '^(BASEDIR|CONF|RUNSOPT|RUNSDBG)=' "${GOMD}"
  echo "[qa-run] builds available:"
  (cd /test && ./gendirs.sh ALLALL) 2> /dev/null | sed 's|^|  |'
  echo "[qa-run] to start: qa-run <basedir> <conf> [opt runs] [dbg runs]"
  exit 0
fi

BASEDIR="${1}"
CONF="${2:-}"
RUNSOPT="${3:-1}"
RUNSDBG="${4:-1}"
[ -n "${CONF}" ] || { echo "[qa-run] give a configuration, for example pquery-run-MD.conf"; exit 2; }
case "${BASEDIR}" in /*) ;; *) BASEDIR="/test/${BASEDIR}" ;; esac
[ -d "${BASEDIR}" ] || { echo "[qa-run] ${BASEDIR} is not there"; exit 1; }
[ -r "${QA_DIR}/${CONF}" ] || { echo "[qa-run] ${QA_DIR}/${CONF} is not there"; exit 1; }

sed -i "s|^BASEDIR=.*|BASEDIR=${BASEDIR}|" "${GOMD}"
sed -i "s|^CONF=.*|CONF=${CONF}|" "${GOMD}"
sed -i "s|^RUNSOPT=.*|RUNSOPT=${RUNSOPT}|" "${GOMD}"
sed -i "s|^RUNSDBG=.*|RUNSDBG=${RUNSDBG}|" "${GOMD}"
grep -E '^(BASEDIR|CONF|RUNSOPT|RUNSDBG)=' "${GOMD}" | sed 's|^|[qa-run] |'

exec "${GOMD}"
