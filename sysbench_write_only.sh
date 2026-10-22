#!/bin/bash
# Run a sysbench write-only load (prepare, run, cleanup) against one MariaDB node and
# print the total execution time at the end. sysbench runs on this machine, so it must
# be installed here (sudo apt install -y sysbench) and be able to reach <host>:3306.
#
# Usage: ./sysbench_write_only.sh [-h|--help] [host]
# host defaults to temp-4.
#
# Settings (environment variables, defaults in brackets):
#   SB_PORT [3306]  SB_USER [sbtest]  SB_PASSWORD [sbtest]  SB_DB [sbtest]
#   SB_TABLES [10]  SB_TABLE_SIZE [100000]  (prepare loads SB_TABLES x SB_TABLE_SIZE rows)
#   SB_THREADS [16]  SB_TIME [300] (seconds)  SB_REPORT_INTERVAL [10] (seconds)
#   SB_STEPS ["prepare run cleanup"]  Steps to run, in order. SB_STEPS="prepare run" keeps
#     the tables for inspection, SB_STEPS=run reuses them, SB_STEPS=cleanup drops them.
#
# Example:
#   SB_THREADS=64 SB_TIME=600 ./sysbench_write_only.sh temp-5
#
# One-time setup on the node (this script does not create the user or the database):
#   sudo mariadb -e "CREATE DATABASE IF NOT EXISTS sbtest; CREATE USER IF NOT EXISTS 'sbtest'@'%' IDENTIFIED BY 'Admin123$'; GRANT ALL ON sbtest.* TO 'sbtest'@'%';"
#
# Note: the cnf in raft_cluster_setup_steps.txt has general_log=1, which writes every
# statement of the load to /tmp/general.log. Turn it off first: SET GLOBAL general_log=OFF
# Note: if a step fails, the script stops and leaves the sbtest tables behind. A rerun then
# fails at prepare ("table already exists"); clear them with SB_STEPS=cleanup.

set -euo pipefail

SECONDS=0  # bash builtin counter, read at exit for the total execution time

case ${1:-} in
  -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  -*) echo "ERROR: unknown option $1" >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo "ERROR: too many arguments (see --help)" >&2; exit 2; }

HOST=${1:-temp-4}
PORT=${SB_PORT:-3306}
DB_USER=${SB_USER:-sbtest}
DB_PASSWORD=${SB_PASSWORD:-Admin123$}
DB_NAME=${SB_DB:-sbtest}
TABLES=${SB_TABLES:-10}
TABLE_SIZE=${SB_TABLE_SIZE:-1000}
THREADS=${SB_THREADS:-16}
RUN_TIME=${SB_TIME:-30}
REPORT_INTERVAL=${SB_REPORT_INTERVAL:-1}
STEPS=${SB_STEPS:-prepare run cleanup}
TEST=oltp_write_only

command -v sysbench > /dev/null || { echo "Assert: sysbench not found in PATH (sudo apt install -y sysbench)" >&2; exit 1; }
timeout 5 bash -c "< /dev/tcp/$HOST/$PORT" 2> /dev/null || { echo "Assert: cannot connect to $HOST:$PORT" >&2; exit 1; }
# Check all steps up front, so a typo in the last one does not surface after a long run
for STEP in $STEPS; do
  case $STEP in
    prepare|run|cleanup) ;;
    *) echo "ERROR: unknown step '$STEP' in SB_STEPS (use prepare, run, cleanup)" >&2; exit 2 ;;
  esac
done

log() { echo "=== $(date +%T) $*"; }

# Runs on every exit, so a failed step still reports how long it took
total_time() {
  local rc=$? status=""
  [ $rc -eq 0 ] || status=" - FAILED with exit status $rc"
  log "Total execution time: $(( SECONDS / 3600 ))h $(( SECONDS % 3600 / 60 ))m $(( SECONDS % 60 ))s (${SECONDS} seconds)${status}"
}
trap total_time EXIT
# Ctrl-C / kill: stop after the current command (no further steps) and exit with the usual
# 128+signal status, so total_time reports it as FAILED instead of looking like a clean finish
trap 'exit 130' INT
trap 'exit 143' TERM

COMMON_OPTS=(--db-driver=mysql --mysql-host="$HOST" --mysql-port="$PORT" --mysql-user="$DB_USER" --mysql-db="$DB_NAME" --tables="$TABLES" --table-size="$TABLE_SIZE")

# $1 = prepare|run|cleanup, remaining args = extra sysbench options. The logged command
# line shows exactly what is run, with the password masked.
sb() {
  local step=$1; shift
  log "[$step] sysbench $TEST ${COMMON_OPTS[*]} --mysql-password=*** ${*:+$* }$step"
  sysbench "$TEST" "${COMMON_OPTS[@]}" --mysql-password="$DB_PASSWORD" "$@" "$step"
}

for STEP in $STEPS; do
  case $STEP in
    run) sb run --threads="$THREADS" --time="$RUN_TIME" --report-interval="$REPORT_INTERVAL" ;;
    *) sb "$STEP" ;;
  esac
done
