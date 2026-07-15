#!/bin/bash
# Persistent query watchdog for the coverage harness. KILL QUERY any COMMAND='Query'
# running longer than THRESH seconds, so one pathological generated statement cannot peg
# a core for a whole chunk timeout. Replication/Galera apply threads are never touched,
# so it is safe alongside cov_replication.sh / cov_galera.sh. Run it during all coverage work
set -u
SOCK="${1:?usage: cov_qkiller.sh <socket> [threshold_s]}"
THRESH="${2:-12}"
BT="${BT:-/tmp/13.0_cov_opt}"
CLIENT="$BT/client/mariadb --no-defaults -uroot --socket=$SOCK"
while sleep 2; do
  [ -S "$SOCK" ] || continue
  $CLIENT -Nse "SELECT ID FROM information_schema.PROCESSLIST
      WHERE COMMAND='Query' AND TIME > $THRESH
        AND INFO NOT LIKE '%PROCESSLIST%'
        AND USER <> 'system user'" 2>/dev/null \
  | while read -r id; do
      [ -n "$id" ] && $CLIENT -Nse "KILL QUERY $id" 2>/dev/null
    done
done
