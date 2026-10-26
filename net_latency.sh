#!/bin/bash
# Induce / revert network latency on an interface using tc netem.
# Usage:
#   sudo ./net_latency.sh add    [-i IFACE] [-d DELAY_MS] [-j JITTER_MS] [-l LOSS_PCT] [-p PORT]
#   sudo ./net_latency.sh revert [-i IFACE]
#   sudo ./net_latency.sh status [-i IFACE]
# Examples:
#   sudo ./net_latency.sh add -i eth0 -d 200 -j 50          # 200ms +-50ms on all egress traffic
#   sudo ./net_latency.sh add -i eth0 -d 100 -p 4567        # only traffic to/from port 4567 (e.g. Galera)
#   sudo ./net_latency.sh revert -i eth0

set -u

IFACE=""
DELAY=100
JITTER=0
LOSS=0
PORT=""

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

[ $# -ge 1 ] || usage
ACTION=$1; shift

while getopts "i:d:j:l:p:h" opt; do
  case $opt in
    i) IFACE=$OPTARG ;;
    d) DELAY=$OPTARG ;;
    j) JITTER=$OPTARG ;;
    l) LOSS=$OPTARG ;;
    p) PORT=$OPTARG ;;
    *) usage ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (use sudo)" >&2; exit 1; }
command -v tc >/dev/null || { echo "ERROR: 'tc' not found (install iproute2)" >&2; exit 1; }

# Default to the interface of the default route
if [ -z "$IFACE" ]; then
  IFACE=$(ip route show default | awk '/default/ {print $5; exit}')
fi
[ -n "$IFACE" ] && ip link show "$IFACE" >/dev/null 2>&1 || { echo "ERROR: invalid interface '$IFACE'" >&2; exit 1; }

revert() {
  if tc qdisc show dev "$IFACE" | grep -qE 'netem|prio'; then
    tc qdisc del dev "$IFACE" root 2>/dev/null
    echo "Latency removed from $IFACE"
  else
    echo "No netem/prio qdisc found on $IFACE, nothing to revert"
  fi
}

add() {
  # Clear any previous rule so add is idempotent
  tc qdisc del dev "$IFACE" root 2>/dev/null

  local netem="delay ${DELAY}ms"
  [ "$JITTER" -gt 0 ] && netem="$netem ${JITTER}ms distribution normal"
  [ "$LOSS" != "0" ] && netem="$netem loss ${LOSS}%"

  if [ -z "$PORT" ]; then
    tc qdisc add dev "$IFACE" root netem $netem || exit 1
  else
    # Only delay traffic with src or dst port = PORT
    tc qdisc add dev "$IFACE" root handle 1: prio || exit 1
    tc qdisc add dev "$IFACE" parent 1:3 handle 30: netem $netem || exit 1
    tc filter add dev "$IFACE" protocol ip parent 1:0 prio 3 u32 match ip dport "$PORT" 0xffff flowid 1:3 || exit 1
    tc filter add dev "$IFACE" protocol ip parent 1:0 prio 3 u32 match ip sport "$PORT" 0xffff flowid 1:3 || exit 1
  fi
  echo "Applied on $IFACE: $netem${PORT:+ (port $PORT only)}"
  echo "Revert with: sudo $0 revert -i $IFACE"
}

case $ACTION in
  add|on|induce)      add ;;
  revert|off|remove)  revert ;;
  status)             tc qdisc show dev "$IFACE"; tc filter show dev "$IFACE" ;;
  *) usage ;;
esac
