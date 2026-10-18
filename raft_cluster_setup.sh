#!/bin/bash
# Set up an N-node MariaDB RAFT cluster (see raft_cluster_setup_steps.txt).
# Run from any host with passwordless ssh + sudo access to all nodes.
#
# Usage: ./raft_cluster_setup.sh [-s key=value]... [node ...]
# Any number of nodes; default: temp-4 temp-5 temp-6. The first node bootstraps
# the cluster; raft_node_id is node1..nodeN by position.
#
# Options:
#   -s, --set key=value   Override a config setting (repeatable). Replaces the
#                         default line(s) for that key, or adds it if not in the
#                         default config. Repeat the same key to emit it several
#                         times (e.g. plugin_load_add). Applied to all nodes.
#                         raft_node_id cannot be set (it is per node).
#   -h, --help            Show this help
#
# Example:
#   ./raft_cluster_setup.sh -s raft_log_level=DEBUG -s wsrep_cluster_name='"qa"' a b c d e
#
# Note: the config references /etc/mysql/encryption/keyfile (file_key_management).
# This script does not create it; it must exist on every node before mariadb starts.

set -euo pipefail

OVERRIDES=""
POSITIONAL=()
while [ $# -gt 0 ]; do
  case $1 in
    -s|--set)
      [ $# -ge 2 ] || { echo "ERROR: $1 needs key=value" >&2; exit 2; }
      kv=$2; shift 2 ;;
    --set=*) kv=${1#--set=}; shift ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "ERROR: unknown option $1" >&2; exit 2 ;;
    *) POSITIONAL+=("$1"); shift; continue ;;
  esac
  case $kv in
    [A-Za-z_]*=*) ;;
    *) echo "ERROR: invalid setting '$kv' (expected key=value)" >&2; exit 2 ;;
  esac
  if [ "${kv%%=*}" = raft_node_id ]; then
    echo "ERROR: raft_node_id is per node and cannot be overridden" >&2; exit 2
  fi
  OVERRIDES+="$kv"$'\n'
done

case ${#POSITIONAL[@]} in
  0) NODES=(temp-4 temp-5 temp-6) ;;
  *) NODES=("${POSITIONAL[@]}") ;;
esac
if [ $(( ${#NODES[@]} % 2 )) -eq 0 ]; then
  echo "WARNING: ${#NODES[@]} nodes (even); an odd number is recommended for raft quorum" >&2
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes"
CONF_DIR=/etc/mysql/mariadb.conf.d
CONF=mariadb-raft.cnf
REPO_LINES='deb [trusted=yes] https://es-repo.mariadb.net/jenkins/ENTERPRISE/12.3-enterprise/latest/DEB/ ubuntu-2404/
deb [trusted=yes] https://es-repo.mariadb.net/jenkins/CRAFT/main/latest/DEB/ ubuntu-2404/'

CLUSTER_ADDRESS=$(IFS=,; echo "${NODES[*]}")

run() { local node=$1; shift; ssh $SSH_OPTS "$node" "$@"; }
log() { echo "=== $(date +%T) $*"; }

# Step 1: binary package repos (identical on all nodes)
setup_repo() {
  local node=$1
  log "[$node] configuring apt repos"
  run "$node" "
    while IFS= read -r line; do
      grep -qxF \"\$line\" /etc/apt/sources.list || echo \"\$line\" | sudo tee -a /etc/apt/sources.list >/dev/null
    done <<'EOF'
$REPO_LINES
EOF
  "
}

# Default config; $1 = raft_node_id
base_config() {
  local id=$1
  cat <<EOF
[mariadb]
# Standard MariaDB settings
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
bind_address=0.0.0.0
general_log = 1
general_log_file = /tmp/general.log
log_error = /tmp/error.log

# MariaDB wsrep Configuration
# Binlog format must be ROW for wsrep
binlog_format=ROW
wsrep_provider=raft
wsrep_on=ON
wsrep_cluster_name="my_raft_cluster"

# MariaDB RAFT Configuration
plugin_maturity=gamma
plugin_load_add=raft
raft_tls_mode=encrypt
raft_node_id=$id
raft_log_level=INFO
raft_flow_control_drift_limit=1000
raft_flow_control_max_throttle_rate=1000

# List of all nodes in the cluster (IP)
wsrep_cluster_address="$CLUSTER_ADDRESS"

# MGL-178
plugin_load_add=file_key_management
file_key_management_filename=/etc/mysql/encryption/keyfile
log_bin=mysql-bin
encrypt_binlog=ON
EOF
}

# Apply CLI overrides: replace all default lines for an overridden key with the
# override value(s) (at the position of the first one); append keys not present.
apply_overrides() {
  awk -v ov="$OVERRIDES" '
    BEGIN {
      n = split(ov, o, "\n")
      for (i = 1; i <= n; i++) {
        if (o[i] == "") continue
        k = o[i]; sub(/=.*/, "", k)
        if (!(k in vals)) order[++m] = k
        vals[k] = vals[k] o[i] "\n"
      }
    }
    /^[ \t]*[A-Za-z_][A-Za-z0-9_-]*[ \t]*=/ {
      k = $0; sub(/[ \t]*=.*/, "", k); sub(/^[ \t]+/, "", k)
      if (k in vals) {
        if (!(k in done)) { printf "%s", vals[k]; done[k] = 1 }
        next
      }
    }
    { print }
    END {
      first = 1
      for (i = 1; i <= m; i++) {
        if (order[i] in done) continue
        if (first) { print "\n# CLI overrides"; first = 0 }
        printf "%s", vals[order[i]]
      }
    }'
}

# Step 2: config file (identical except raft_node_id)
write_config() {
  local node=$1 id=$2
  log "[$node] writing $CONF (raft_node_id=$id)"
  base_config "$id" | apply_overrides |
    run "$node" "sudo mkdir -p $CONF_DIR && sudo tee $CONF_DIR/$CONF >/dev/null"
}

# Step 3 @ AllNodes: purge old packages, wipe datadir, install fresh, keep config aside as .bk
install_node() {
  local node=$1
  log "[$node] purge + install"
  run "$node" "
    set -x
    sudo systemctl stop mariadb || true
    sleep 5
    sudo apt -y purge 'mysql*'
    sleep 5
    echo 'mariadb-server mariadb-server/postrm_remove_databases boolean true' | sudo debconf-set-selections
    sudo apt -y purge 'mariadb*'
    sleep 5
    sudo apt -y autoremove
    sleep 5
    # Wipe stale datadir/raft state (grastate.dat etc.) left by earlier clusters
    sudo find /var/lib/mysql -mindepth 1 -delete 2>/dev/null || true
    sudo rm -f /tmp/error.log /tmp/general.log
    sudo apt update -y
    sleep 5
    cd $CONF_DIR
    [ -f $CONF ] && sudo mv $CONF $CONF.bk
    sudo apt install -y mariadb-server mariadb-raft
    sleep 5
    sudo systemctl status mariadb --no-pager || true
  "
}

restore_config() {
  local node=$1
  run "$node" "
    sudo systemctl stop mariadb || true
    sleep 5
    cd $CONF_DIR
    sudo mv $CONF.bk $CONF
  "
}

# --- main ---
for i in "${!NODES[@]}"; do
  n=${NODES[$i]}
  setup_repo "$n"
  write_config "$n" "node$((i + 1))"
  install_node "$n"
done

# Node1: bootstrap
log "[${NODES[0]}] bootstrapping cluster"
restore_config "${NODES[0]}"
run "${NODES[0]}" "sudo mariadb-new-cluster; sleep 5"

# Remaining nodes: join
for n in "${NODES[@]:1}"; do
  log "[$n] joining cluster"
  restore_config "$n"
  run "$n" "sudo systemctl start mariadb; sleep 5"
done

# Verify
log "[${NODES[0]}] checking cluster size (expect ${#NODES[@]})"
size=$(run "${NODES[0]}" "sudo mariadb -N -e \"show status like 'wsrep_cluster_size'\"" | awk '{print $2}')
echo "wsrep_cluster_size=$size"
if [ "$size" = "${#NODES[@]}" ]; then
  log "Cluster is up with ${#NODES[@]} nodes"
else
  log "ERROR: expected ${#NODES[@]} nodes, got '$size'"
  exit 1
fi
