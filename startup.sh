#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Expanded by Roel Van de Paar, MariaDB
# Updated by Ramesh Sivaraman, MariaDB

# Random entropy init
RANDOM=$(date +%s%N | cut -b10-19)

# Find empty port
# (**) IMPORTANT WARNING! The init_empty_port scan in startup.sh uses a different range than the matching function in
# pquery-run.sh, reducer.sh and reducer-STABLE.sh. These scripts use 13-65K whereas here we use 10-13K to avoid
# conflicts between the initially-random, but hard coded (whenever ~/start is run) port allocations in the basedir
# scripts which use port numbers, like ./start. The script further checks that a given random port is not already
# in use in the startup script of other basedirs. These two methods should avoid as good as all possible port conflicts.
# Originally all scripts used 10-65K but it was relatively easy to get a port conflict as non-started basedir servers
# may have had their ports allocated by for example a reducer, and then cause a conflict when started. The result of the
# port alloc range difference is that this function here (in startup.sh) cannot be copied verbatim to other scripts.
init_empty_port(){
  # Choose a random port number in 10-13K range (**), with triple check to confirm it is free
  NEWPORT=$[ 10001 + ( ${RANDOM} % 3000 ) ]
  DOUBLE_CHECK=0
  while :; do
    # Check if the port is free in three different ways
    ISPORTFREE1="$(netstat -an | tr '\t' ' ' | grep -E --binary-files=text "[ :]${NEWPORT} " | wc -l)"
    ISPORTFREE2="$(ps -ef | grep --binary-files=text "port=${NEWPORT}" | grep --binary-files=text -v 'grep')"
    ISPORTFREE3="$(grep --binary-files=text -o "port=${NEWPORT}" /test/*/start 2>/dev/null | wc -l)"
    if [ "${ISPORTFREE1}" -eq 0 -a -z "${ISPORTFREE2}" -a "${ISPORTFREE3}" -eq 0 ]; then
      if [ "${DOUBLE_CHECK}" -eq 2 ]; then  # If true, then the port was triple checked (to avoid races) to be free
        break  # Suitable port number found
      else
        DOUBLE_CHECK=$[ ${DOUBLE_CHECK} + 1 ]
        sleep 0.0${RANDOM}  # Random Microsleep to further avoid races
        continue  # Loop the check
      fi
    else
      NEWPORT=$[ 10001 + ( ${RANDOM} % 3000 ) ]  # Try a new port
      DOUBLE_CHECK=0  # Reset the double check
      continue  # Recheck the new port
    fi
  done
}

# Nr of MDG nodes 1-n
NR_OF_NODES=${1}
if [ -z "${NR_OF_NODES}" ] ; then
  NR_OF_NODES=3
fi
init_empty_port
PORT=$NEWPORT
MTRT=$((${RANDOM} % 100 + 700))
BUILD=$(pwd | sed 's|^.*/||')
SCRIPT_PWD=$(cd "$(dirname $0)" && pwd)
ADDR="127.0.0.1"
USE_JE=0 # Use jemalloc (requires builds which were made with jemalloc enabled. Current build scripts explicitly disable jemalloc with -DWITH_JEMALLOC=no hardcoded, as TokuDB is deprecated in MariaDB 10.5)

if [ "${USE_JE}" -eq 1 ]; then
  JE1="if [ -r /usr/lib/x86_64-linux-gnu/libjemalloc.so.2 ]; then export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2"
  JE2=" elif [ -r /usr/lib/x86_64-linux-gnu/libjemalloc.so ]; then export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so"
  JE3=" elif [ -r /usr/lib64/libjemalloc.so.1 ]; then export LD_PRELOAD=/usr/lib64/libjemalloc.so.1"
  JE4=" elif [ -r /usr/lib/x86_64-linux-gnu/libjemalloc.so.1 ]; then export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.1"
  JE5=" elif [ -r /usr/local/lib/libjemalloc.so ]; then export LD_PRELOAD=/usr/local/lib/libjemalloc.so"
  JE6=" elif [ -r ${PWD}/lib/mysql/libjemalloc.so.1 ]; then export LD_PRELOAD=${PWD}/lib/mysql/libjemalloc.so.1"
  JE7=" else echo 'Error: jemalloc not found, please install it first'; exit 1; fi"
fi

add_san_options() {
  # detect_invalid_pointer_pairs changed from 1 to 3 at start of 2021 (effectively used since)
  echo 'export ASAN_OPTIONS=quarantine_size_mb=512:atexit=0:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1  # Set atexit=1 to get full at-binary-exit memory stats' >>"${1}"
  # check_initialization_order=1 cannot be used due to https://jira.mariadb.org/browse/MDEV-24546 TODO
  # detect_stack_use_after_return=1 will likely require thread_stack increase (check error log after ./all) TODO
  #echo 'export ASAN_OPTIONS=quarantine_size_mb=512:atexit=1:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:check_initialization_order=1:detect_stack_use_after_return=1:abort_on_error=1' >> "${1}"
  echo 'export UBSAN_OPTIONS=print_stacktrace=1' >>"${1}"
  echo 'export TSAN_OPTIONS=suppress_equal_stacks=1:suppress_equal_addresses=1:history_size=7:verbosity=1' >>"${1}"
}

# Ubuntu mysqld runtime provisioning
if [ "$(uname -v | grep 'Ubuntu')" != "" ]; then
  if [ $(dpkg -l | grep -c libaio1) -eq 0 ]; then
    sudo apt-get install libaio1
  fi
  if [ "${USE_JE}" -eq 1 ]; then # TODO: this only checks for libjemalloc1, whereas newer Ubuntu releases seem to be using libjemalloc2, but it is not sure if TokuDB still works with libjemalloc2.
    if [ $(dpkg -l | grep -c libjemalloc1) -eq 0 ]; then
      sudo apt-get install libjemalloc1
    fi
  fi
  if [ ! -r /lib/x86_64-linux-gnu/libssl.so.6 ]; then
    sudo ln -s /lib/x86_64-linux-gnu/libssl.so.1.0.0 /lib/x86_64-linux-gnu/libssl.so.6 2>/dev/null
  fi
  if [ ! -r /lib/x86_64-linux-gnu/libcrypto.so.6 ]; then
    sudo ln -s /lib/x86_64-linux-gnu/libcrypto.so.1.0.0 /lib/x86_64-linux-gnu/libcrypto.so.6 2>/dev/null
  fi
fi

# Get version specific options
BIN=
if [ -r ${PWD}/bin/mysqld-debug ]; then BIN="${PWD}/bin/mysqld-debug"; fi # Needs to come first so it's overwritten in next line if both exist
if [ -r ${PWD}/bin/mysqld ]; then BIN="${PWD}/bin/mysqld"; fi
if [ -z "${BIN}" ]; then
  echo "Assert: no mysqld or mysqld-debug binary was found!"
  exit 1
fi
MID=
if [ -r ${PWD}/scripts/mysql_install_db ]; then MID="${PWD}/scripts/mysql_install_db"; fi
if [ -r ${PWD}/bin/mysql_install_db ]; then MID="${PWD}/bin/mysql_install_db"; fi
START_OPT="--core-file"                        # Compatible with 5.6,5.7,8.0
INIT_OPT="--no-defaults --initialize-insecure" # Compatible with     5.7,8.0 (mysqld init)
INIT_TOOL="${BIN}"                             # Compatible with     5.7,8.0 (mysqld init), changed to MID later if version <=5.6
VERSION_INFO=$(${BIN} --version | grep --binary-files=text -oe '[58]\.[01567]' | head -n1)
if [ -z "${VERSION_INFO}" ]; then VERSION_INFO="NA"; fi
VERSION_INFO_2=$(${BIN} --version | grep --binary-files=text -i 'MariaDB' | grep -oe '10\.[1-9]' | head -n1)
if [ -z "${VERSION_INFO_2}" ]; then VERSION_INFO_2="NA"; fi

if [ "${VERSION_INFO_2}" == "10.4" -o "${VERSION_INFO_2}" == "10.5" -o "${VERSION_INFO_2}" == "10.6" -o "${VERSION_INFO_2}" == "10.7" -o "${VERSION_INFO_2}" == "10.8" -o "${VERSION_INFO_2}" == "10.9" ]; then
  VERSION_INFO="5.6"
  INIT_TOOL="${PWD}/scripts/mariadb-install-db"
  INIT_OPT="--no-defaults --force --auth-root-authentication-method=normal ${MYINIT}"
  #START_OPT="--core-file --core"
  START_OPT="--core-file"
elif [ "${VERSION_INFO_2}" == "10.1" -o "${VERSION_INFO_2}" == "10.2" -o "${VERSION_INFO_2}" == "10.3" ]; then
  VERSION_INFO="5.1"
  INIT_TOOL="${PWD}/scripts/mysql_install_db"
  INIT_OPT="--no-defaults --force"
  START_OPT="--core"
elif [ "${VERSION_INFO}" == "5.1" -o "${VERSION_INFO}" == "5.5" -o "${VERSION_INFO}" == "5.6" ]; then
  if [ -z "${MID}" ]; then
    echo "Assert: Version was detected as ${VERSION_INFO}, yet ./scripts/mysql_install_db nor ./bin/mysql_install_db is present!"
    exit 1
  fi
  INIT_TOOL="${MID}"
  INIT_OPT="--no-defaults --force"
  START_OPT="--core"
elif [ "${VERSION_INFO}" != "5.7" -a "${VERSION_INFO}" != "8.0" ]; then
  echo "=========================================================================================="
  echo "WARNING: mysqld (${BIN}) version detection failed. This is likely caused by using this script with a non-supported distribution or version of mysqld, or simply because this directory is not a proper MySQL[-fork] base directory. Please expand this script to handle (which shoud be easy to do). Even so, the scipt will now try and continue as-is, but this may and will likely fail."
  echo "=========================================================================================="
fi

if echo "${PWD}" | grep -q EMD ; then
  if [ "${VERSION_INFO_2}" == "10.3" -o "${VERSION_INFO_2}" == "10.2" ]; then
    INIT_OPT="${INIT_OPT} --auth-root-authentication-method=normal ${MYINIT}"
  fi
fi

# Check GR
if find . -name group_replication.so | grep -q .; then
  GRP_RPL=1
else
  echo "Warning! Group Replication plugin not found. Skipping Group Replication startup"
  GRP_RPL=0
fi

# Check MariaDB Galera Cluster
MDG=0
GALERA_LIB=
SOCKET=${PWD}/socket.sock
if [ -r lib/libgalera_smm.so ]; then
  echo "CS Galera plugin found. Adding CS Galera startup"
  MDG=1
  GALERA_LIB=${PWD}/lib/libgalera_smm.so
elif [ -r lib/libgalera_enterprise_smm.so ]; then
  echo "ES Galera plugin found. Adding ES Galera startup"
  MDG=1
  GALERA_LIB=${PWD}/lib/libgalera_enterprise_smm.so
else
  echo "Warning! Galera plugin not found. Skipping Galera startup"
fi

# Setup scritps
rm -f *_node_cl* *cl cl* *cli all* binlog fixin gal* gdb init loopin *multirun* multitest myrocks_tokudb_init reducer_* repl_setup setup sqlmode stack start* stop* sysbench* test test_pquery wipe* clean_failing_queries memory_use_trace
BASIC_SCRIPTS="start | start_valgrind | start_gypsy | repl_setup | stop | kill | setup | cl | test | test_pquery | init | wipe | sqlmode | binlog | all | all_stbe | all_no_cl | all_rr | all_no_cl_rr | reducer_new_text_string.sh | reducer_new_text_string_pquery.sh | reducer_errorlog.sh | reducer_errorlog_pquery.sh | reducer_fireworks.sh | sysbench_prepare | sysbench_run | sysbench_measure | multirun | multirun_rr | multirun_pquery | multirun_pquery_rr | multirun_mysqld | multirun_mysqld_text | kill_multirun | loopin | gdb | fixin | stack | memory_use_trace | myrocks_tokudb_init"
GRP_RPL_SCRIPTS="start_group_replication (and stop_group_replication is created dynamically on group replication startup)"
GALERA_SCRIPTS="gal_start | gal_start_rr | gal_stop | gal_init | gal_kill | gal_setup | gal_wipe | *_node_cli | gal_test_pquery | gal | gal_cl | gal_sqlmode | gal_binlog | gal_stbe | gal_no_cl | gal_rr | gal_gdb | gal_test | gal_cl_noprompt_nobinary | gal_cl_noprompt | gal_multirun | gal_multirun_pquery | gal_sysbench_measure | gal_sysbench_prepare | gal_sysbench_run"
if [[ $GRP_RPL -eq 1 ]]; then
  echo "Adding scripts: ${BASIC_SCRIPTS} | ${GRP_RPL_SCRIPTS}"
elif [[ $MDG -eq 1 ]]; then
  echo "Adding scripts: ${BASIC_SCRIPTS} ${GALERA_SCRIPTS}"
else
  echo "Adding scripts: ${BASIC_SCRIPTS}"
fi

#GR startup scripts
if [[ $GRP_RPL -eq 1 ]]; then
  echo -e "#!/bin/bash" >./start_group_replication
  echo -e "NODES=\$1" >>./start_group_replication
  echo -e "ADDR=\"127.0.0.1\"" >>./start_group_replication
  echo -e "RPORT=$((RANDOM % 21 + 10))" >>./start_group_replication
  echo -e "RBASE=\"\$(( RPORT*1000 ))\"" >>./start_group_replication
  echo -e "MYEXTRA=\"\"" >>./start_group_replication
  echo -e "GR_START_TIMEOUT=300" >>./start_group_replication
  echo -e "BUILD=\$(pwd)\n" >>./start_group_replication
  echo -e "touch ./stop_group_replication " >>./start_group_replication
  echo -e "if [ -z \"\$NODES\" ]; then" >>./start_group_replication
  echo -e "  echo \"No valid parameter is passed. Please indicate how many nodes to start. Please retry.\"" >>./start_group_replication
  echo -e "  echo \"Usage example:\"" >>./start_group_replication
  echo -e "  echo \"   $./start_group_replication 2\"" >>./start_group_replication
  echo -e "  echo \"   Will start a 2 node Group Replication cluster.\"" >>./start_group_replication
  echo -e "  exit 1" >>./start_group_replication
  echo -e "else" >>./start_group_replication
  echo -e "  echo \"Starting \$NODES node Group Replication, please wait...\"" >>./start_group_replication
  echo -e "  rm -f ./stop_group_replication ./*cl ./wipe_group_replication" >>./start_group_replication
  echo -e "  touch ./stop_group_replication" >>./start_group_replication
  echo -e "fi" >>./start_group_replication

  echo -e "MID=\"\${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=\${BUILD}\"" >>./start_group_replication

  if [[ $i -eq 1 ]]; then
    GR_GROUP_SEEDS=$LADDR
  else
    GR_GROUP_SEEDS=$GR_GROUP_SEEDS,$LADDR
  fi
  echo -e "for i in \`seq 1 \$NODES\`;do" >>./start_group_replication
  echo -e "  LADDR=\"\$ADDR:\$(( RBASE + 100 + \$i ))\"" >>./start_group_replication
  echo -e "  if [[ \$i -eq 1 ]]; then" >>./start_group_replication
  echo -e "    GR_GROUP_SEEDS="\$LADDR"" >>./start_group_replication
  echo -e "  else" >>./start_group_replication
  echo -e "    GR_GROUP_SEEDS=\"\$GR_GROUP_SEEDS,\$LADDR\"" >>./start_group_replication
  echo -e "  fi" >>./start_group_replication
  echo -e "done" >>./start_group_replication

  echo -e "function start_multi_node(){" >>./start_group_replication
  echo -e "  NODE_CHK=0" >>./start_group_replication
  echo -e "  for i in \`seq 1 \$NODES\`;do" >>./start_group_replication
  echo -e "    RBASE1=\"\$(( RBASE + \$i ))\"" >>./start_group_replication
  echo -e "    LADDR1=\"\$ADDR:\$(( RBASE + 100 + \$i ))\"" >>./start_group_replication
  echo -e "    node=\"\${BUILD}/node\$i\"" >>./start_group_replication
  echo -e "    if [ ! -d \$node ]; then" >>./start_group_replication
  echo -e "      \${MID} --datadir=\$node  > \${BUILD}/startup_node\$i.err 2>&1 || exit 1;" >>./start_group_replication
  echo -e "      NODE_CHK=1" >>./start_group_replication
  echo -e "    fi\n" >>./start_group_replication

  echo -e "    \${BUILD}/bin/mysqld --no-defaults \\" >>./start_group_replication
  echo -e "      --basedir=\${BUILD} --datadir=\$node \\" >>./start_group_replication
  echo -e "      --innodb_file_per_table \$MYEXTRA --innodb_autoinc_lock_mode=2 --innodb_locks_unsafe_for_binlog=1 \\" >>./start_group_replication
  echo -e "      --server_id=1 --gtid_mode=ON --enforce_gtid_consistency=ON \\" >>./start_group_replication
  echo -e "      --master_info_repository=TABLE --relay_log_info_repository=TABLE \\" >>./start_group_replication
  echo -e "      --binlog_checksum=NONE --log_slave_updates=ON --log_bin=binlog \\" >>./start_group_replication
  echo -e "      --binlog_format=ROW --innodb_flush_method=O_DIRECT \\" >>./start_group_replication
  echo -e "      --core-file  --sql-mode=no_engine_substitution \\" >>./start_group_replication
  echo -e "      --secure-file-priv= --loose-innodb-status-file=1 \\" >>./start_group_replication
  echo -e "      --log-error=\$node/node\$i.err --socket=\$node/socket.sock --log-output=none \\" >>./start_group_replication
  echo -e "      --port=\$RBASE1 --transaction_write_set_extraction=XXHASH64 \\" >>./start_group_replication
  echo -e "      --loose-group_replication_group_name=\"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa\" \\" >>./start_group_replication
  echo -e "      --loose-group_replication_start_on_boot=off --loose-group_replication_local_address=\$LADDR1 \\" >>./start_group_replication
  echo -e "      --loose-group_replication_group_seeds=\$GR_GROUP_SEEDS \\" >>./start_group_replication
  echo -e "      --loose-group_replication_bootstrap_group=off --super_read_only=OFF > \$node/node\$i.err 2>&1 &\n" >>./start_group_replication

  echo -e "    for X in \$(seq 0 \${GR_START_TIMEOUT}); do" >>./start_group_replication
  echo -e "      sleep 1" >>./start_group_replication
  echo -e "      if \${BUILD}/bin/mysqladmin -uroot -S\$node/socket.sock ping > /dev/null 2>&1; then" >>./start_group_replication
  echo -e "        if [ \$NODE_CHK -eq 1 ]; then" >>./start_group_replication
  echo -e "          \${BUILD}/bin/mysql -uroot -S\$node/socket.sock -Bse \"SET SQL_LOG_BIN=0;CREATE USER rpl_user@'%';GRANT REPLICATION SLAVE ON *.* TO rpl_user@'%' IDENTIFIED BY 'rpl_pass';FLUSH PRIVILEGES;SET SQL_LOG_BIN=1;\" > /dev/null 2>&1" >>./start_group_replication
  echo -e "          \${BUILD}/bin/mysql -uroot -S\$node/socket.sock -Bse \"CHANGE MASTER TO MASTER_USER='rpl_user', MASTER_PASSWORD='rpl_pass' FOR CHANNEL 'group_replication_recovery';\" > /dev/null 2>&1" >>./start_group_replication
  echo -e "          if [[ \$i -eq 1 ]]; then" >>./start_group_replication
  echo -e "            \${BUILD}/bin/mysql -uroot -S\$node/socket.sock -Bse \"INSTALL PLUGIN group_replication SONAME 'group_replication.so';SET GLOBAL group_replication_bootstrap_group=ON;START GROUP_REPLICATION;SET GLOBAL group_replication_bootstrap_group=OFF;\" > /dev/null 2>&1" >>./start_group_replication
  echo -e "            \${BUILD}/bin/mysql -uroot -S\$node/socket.sock -Bse \"create database if not exists test\" > /dev/null 2>&1" >>./start_group_replication
  echo -e "          else" >>./start_group_replication
  echo -e "            \${BUILD}/bin/mysql -uroot -S\$node/socket.sock -Bse \"INSTALL PLUGIN group_replication SONAME 'group_replication.so';START GROUP_REPLICATION;\" > /dev/null 2>&1" >>./start_group_replication
  echo -e "          fi" >>./start_group_replication
  echo -e "        else" >>./start_group_replication
  echo -e "          if [[ \$i -eq 1 ]]; then" >>./start_group_replication
  echo -e "            \${BUILD}/bin/mysql -uroot -S\$node/socket.sock -Bse \"SET GLOBAL group_replication_bootstrap_group=ON;START GROUP_REPLICATION;SET GLOBAL group_replication_bootstrap_group=OFF;\" > /dev/null 2>&1" >>./start_group_replication
  echo -e "          else" >>./start_group_replication
  echo -e "            \${BUILD}/bin/mysql -uroot -S\$node/socket.sock -Bse \"START GROUP_REPLICATION;\" > /dev/null 2>&1" >>./start_group_replication
  echo -e "          fi" >>./start_group_replication
  echo -e "        fi" >>./start_group_replication
  echo -e "        echo \"Started node\$i.\"" >>./start_group_replication
  echo -e "        CLI_SCRIPTS=\"\$CLI_SCRIPTS | \${i}cl \"" >>./start_group_replication
  echo -e "        break" >>./start_group_replication
  echo -e "      else" >>./start_group_replication
  echo -e "        echo \"This should not happen\"" >>./start_group_replication
  echo -e "        exit 1" >>./start_group_replication
  echo -e "      fi" >>./start_group_replication
  echo -e "    done" >>./start_group_replication

  echo -e "    echo -e \"echo 'Server on socket \$node/socket.sock with datadir \$node halted'\" | cat - ./stop_group_replication > ./temp && mv ./temp ./stop_group_replication" >>./start_group_replication
  echo -e "    echo -e \"\${BUILD}/bin/mysqladmin -uroot -S\$node/socket.sock shutdown\" | cat - ./stop_group_replication > ./temp && mv ./temp ./stop_group_replication" >>./start_group_replication
  #echo -e "    echo -e \"rm -Rf \$node.PREV; mv \$node \$node.PREV 2>dev/null\" >> ./wipe_group_replication" >> ./start_group_replication  # Removed to save disk space, changed to next line
  echo -e "    echo -e \"rm -Rf \$node\" >> ./wipe_group_replication" >>./start_group_replication
  echo -e "    echo -e \"\$BUILD/bin/mysql -A -uroot -S\$node/socket.sock --prompt \\\"node\$i> \\\"\" > \${BUILD}/\${i}cl " >>./start_group_replication
  echo -e "  done\n" >>./start_group_replication
  echo -e "}\n" >>./start_group_replication

  echo -e "start_multi_node" >>./start_group_replication
  echo -e "chmod +x ./stop_group_replication ./*cl ./wipe_group_replication" >>./start_group_replication
  echo -e "echo \"Added scripts: \$CLI_SCRIPTS | wipe_group_replication | stop_group_replication \"" >>./start_group_replication
  echo -e "echo \"Started \$NODES Node Group Replication. You may access the clients using the scripts above\"" >>./start_group_replication
  echo -e "echo \"Please note the wipe_group_replication script is specific for this number of nodes. To setup a completely new Group Replication setup, please use ./start_group_replication again.\"" >>./start_group_replication
  chmod +x ./start_group_replication
fi

#Galera startup scripts
if [[ $MDG -eq 1 ]]; then
  rm -rf my.cnf
  echo "[mysqld]" >my.cnf
  echo "basedir=${PWD}" >>my.cnf
  echo "wsrep-debug=1" >>my.cnf
  echo "innodb_file_per_table" >>my.cnf
  echo "innodb_autoinc_lock_mode=2" >>my.cnf
  echo "wsrep-provider=${GALERA_LIB}" >>my.cnf
  echo "#wsrep_sst_method=rsync" >>my.cnf
  echo "wsrep_sst_method=mariabackup" >>my.cnf
  echo "wsrep_sst_auth=root:" >>my.cnf
  echo "binlog_format=ROW" >>my.cnf
  echo "core-file" >>my.cnf
  echo "log-output=none" >>my.cnf
  echo "wsrep_slave_threads=2" >>my.cnf
  echo "wsrep_on=1" >>my.cnf
  echo "#gtid_strict_mode=1" >>my.cnf
  echo "#log_slave_updates=ON" >>my.cnf
  echo "#log_bin=binlog" >>my.cnf

  init_empty_port
  PORT=$NEWPORT
  MDG_PORTS=""
  MDG_LADDRS=""
  for i in $(seq 1 "${NR_OF_NODES}"); do
    node=node${i}
    mkdir -p ${PWD}/tmp${i}
    init_empty_port
    RBASE=$NEWPORT
    NEWPORT=
    init_empty_port
    LADDR="127.0.0.1:${NEWPORT}"
    NEWPORT=
    init_empty_port
    SST_PORT="127.0.0.1:${NEWPORT}"
    NEWPORT=
    init_empty_port
    IST_PORT="127.0.0.1:${NEWPORT}"
    NEWPORT=
    MDG_PORTS+=("$RBASE")
    MDG_LADDRS+=("$LADDR")
    cp my.cnf n${i}.cnf
    sed -i "2i server-id=10${i}" n${i}.cnf
    sed -i "2i wsrep_node_incoming_address=$ADDR" n${i}.cnf
    sed -i "2i wsrep_node_address=$ADDR" n${i}.cnf
    sed -i "2i wsrep_sst_receive_address=$SST_PORT" n${i}.cnf
    sed -i "2i log-error=${PWD}/$node/node${i}.err" n${i}.cnf
    sed -i "2i port=$RBASE" n${i}.cnf
    sed -i "2i datadir=${PWD}/$node" n${i}.cnf
    sed -i "2i socket=${PWD}/$node/node${i}_socket.sock" n${i}.cnf
    sed -i "2i tmpdir=${PWD}/tmp${i}" n${i}.cnf
    sed -i "2i wsrep_provider_options=\"gmcast.listen_addr=tcp://$LADDR;ist.recv_addr=$IST_PORT;$WSREP_PROVIDER_OPTIONS\"" n${i}.cnf
  done
  WSREP_CLUSTER_ADDRESS=$(printf "%s,"  "${MDG_LADDRS[@]}")
  for j in $(seq 1 ${NR_OF_NODES}); do
    sed -i "2i wsrep_cluster_address=gcomm://${WSREP_CLUSTER_ADDRESS:1}" n${j}.cnf
  done

  echo -e "#!/bin/bash" >./gal_start
  echo -e "NODES=\$1" >>./gal_start
  echo -e "MYEXTRA=\"\"" >>./gal_start
  echo -e "GALERA_START_TIMEOUT=120" >>./gal_start
  echo -e "BUILD=\$(pwd)\n" >>./gal_start
  echo -e "check_node_startup(){" >>./gal_start
  echo -e "  for X in \$(seq 0 \${GALERA_START_TIMEOUT}); do" >>./gal_start
  echo -e "    sleep 1" >>./gal_start
  echo -e "    if \${BUILD}/bin/mysqladmin -uroot -S\$BUILD/node\$1/node\$1_socket.sock ping > /dev/null 2>&1; then" >>./gal_start
  echo -e "      if [ \"\`\${BUILD}/bin/mysql -uroot -S\$BUILD/node\$1/node\$1_socket.sock -Bse\"show global status like 'wsrep_local_state_comment'\" | awk '{print \$2}'\`\" == \"Synced\" ]; then" >>./gal_start
  echo -e "        echo \"Server on socket \$BUILD/node\$1/node\$1_socket.sock with datadir \$BUILD/node\$1 started\"" >>./gal_start
  echo -e "        echo \" Configuration file : ${BUILD}/n\$1.cnf\"" >>./gal_start
  echo -e "        break" >>./gal_start
  echo -e "      fi" >>./gal_start
  echo -e "    fi" >>./gal_start
  echo -e "    if [[ \${X} -eq 200 ]] ; then" >>./gal_start
  echo -e "      echo \"Server on socket \$BUILD/node\$1/node\$1_socket.sock with datadir \${node} failed\"" >>./gal_start
  echo -e "      echo \"************************* ERROR *******************************\"" >>./gal_start
  echo -e "      grep -i '\\[ERROR\\]' \$BUILD/node\$1/node\$1.err" >>./gal_start
  echo -e "      echo \"************************* ERROR *******************************\"" >>./gal_start
  echo -e "      exit 1" >>./gal_start
  echo -e "    fi" >>./gal_start
  echo -e "  done" >>./gal_start
  echo -e "}" >>./gal_start

  cat gal_start > ./gal_start_rr
  echo "export _RR_TRACE_DIR=\"${PWD}/rr\"" >> ./gal_start_rr
  echo "if [ -d \"\${_RR_TRACE_DIR}\" ]; then  # Security measure to avoid incorrect mass-rm" >> ./gal_start_rr
  echo "  if [ \"\${_RR_TRACE_DIR}\" == \"\${PWD}/rr\" ]; then  # Security measure to avoid incorrect mass-rm" >> ./gal_start_rr
  echo "    rm -Rf \"\${_RR_TRACE_DIR}\"" >> ./gal_start_rr
  echo "  fi" >> ./gal_start_rr
  echo "fi" >> ./gal_start_rr
  echo "mkdir -p \"\${_RR_TRACE_DIR}\"" >> ./gal_start_rr
  echo "./gal_stop >/dev/null 2>&1;./gal_kill >/dev/null 2>&1" >./gal_init
  echo "rm -Rf ${PWD}/node*" >>./gal_init
  echo "" > ./gal_stop
  echo "./gal_stop >/dev/null 2>&1" >gal_wipe
  echo "rm -Rf ${PWD}/node* ${PWD}/galera_rr" >>gal_wipe
  for i in $(seq 1 "${NR_OF_NODES}"); do
    if [ "${i}" -eq 1 ] ; then
      echo "/usr/bin/rr record --chaos ${PWD}/bin/mysqld --defaults-file=${PWD}/n${i}.cnf \$MYEXTRA --loose-innodb-flush-method=fsync --wsrep-new-cluster > ${PWD}/node${i}/node${i}.err 2>&1 & " >> ./gal_start_rr
      echo "check_node_startup ${i}" >> ./gal_start_rr
      echo "${PWD}/bin/mysqld --defaults-file=${PWD}/n${i}.cnf \$MYEXTRA --wsrep-new-cluster > ${PWD}/node${i}/node${i}.err 2>&1 & " >> ./gal_start
      echo "check_node_startup ${i}" >> ./gal_start
    else
      echo "${PWD}/bin/mysqld --defaults-file=${PWD}/n${i}.cnf \$MYEXTRA > $PWD/node${i}/node${i}.err 2>&1 &" >> ./gal_start_rr
      echo "check_node_startup ${i}" >> ./gal_start_rr
      echo "${PWD}/bin/mysqld --defaults-file=${PWD}/n${i}.cnf \$MYEXTRA > $PWD/node${i}/node${i}.err 2>&1 &" >> ./gal_start
      echo "check_node_startup ${i}" >> ./gal_start
    fi
    echo "$INIT_TOOL ${INIT_OPT} --basedir=${PWD} --datadir=${PWD}/node${i}" >>./gal_init

    echo "${PWD}/bin/mysql -A -uroot -S${PWD}/node${i}/node${i}_socket.sock test --prompt \"node${i}:\\u@\\h> \"" >${PWD}/${i}_node_cli
    echo "$INIT_TOOL ${INIT_OPT} --basedir=${PWD} --datadir=${PWD}/node${i}" >>gal_wipe
    echo "if [ -r node1/node${i}.err ]; then mv node${i}/node${i}.err node${i}/node${i}.err.PREV; fi" >>gal_wipe
  done
  for i in $(seq "${NR_OF_NODES}" -1 1); do
    echo "${PWD}/bin/mysqladmin -uroot -S${PWD}/node${i}/node${i}_socket.sock shutdown" >> ./gal_stop
    echo "echo \"Server on socket ${PWD}/node${i}/node${i}_socket.sock halted\"" >>./gal_stop
  done
  echo "${PWD}/bin/mysql -A -uroot -S${PWD}/node1/node1_socket.sock -e 'CREATE DATABASE IF NOT EXISTS test;'" >> ./gal_start_rr
  echo "${PWD}/bin/mysql -A -uroot -S${PWD}/node1/node1_socket.sock -e 'CREATE DATABASE IF NOT EXISTS test;'" >> ./gal_start
  echo "ps -ef | grep \"\$(whoami)\" | grep \"\${PWD}/n.*.cnf\" | grep -v grep | awk '{print \$2}' | xargs kill -9 2>/dev/null" >gal_kill
  echo "./gal_kill >/dev/null 2>&1" >>./gal_stop
  echo "./gal_init;./gal_start;./1_node_cli;./gal_stop;./gal_kill >/dev/null 2>&1;tail node1/node1.err" > gal_setup
  chmod +x *_node_cli gal_wipe gal_start gal_stop gal_init gal_kill gal_setup gal_start_rr
fi
mkdir -p data data/mysql log
if [ "${USE_JE}" -eq 1 ]; then
  if [ -r ${PWD}/lib/mysql/plugin/ha_tokudb.so ]; then
    TOKUDB="--plugin-load-add=tokudb=ha_tokudb.so --tokudb-check-jemalloc=0"
  else
    TOKUDB=
  fi
fi
if [ -r ${PWD}/lib/mysql/plugin/ha_rocksdb.so ]; then
  ROCKSDB="--plugin-load-add=rocksdb=ha_rocksdb.so"
else
  ROCKSDB=
fi

if [[ ! -z "$TOKUDB" ]]; then
  LOAD_TOKUDB_INIT_FILE="${SCRIPT_PWD}/TokuDB.sql"
else
  LOAD_TOKUDB_INIT_FILE=
fi
if [[ ! -z "$ROCKSDB" ]]; then
  LOAD_ROCKSDB_INIT_FILE="${SCRIPT_PWD}/MyRocks.sql"
else
  LOAD_ROCKSDB_INIT_FILE=
fi

echo "echo '---------- START ----------' >> ./log/master.err" >insert_start_marker
echo "echo '---------- STOP  ----------' >> ./log/master.err" >insert_stop_marker
echo 'MYEXTRA_OPT="$*"' >start
echo 'MYEXTRA=" --no-defaults "' >>start
echo '#MYEXTRA=" --no-defaults --sql_mode="' >>start
#echo '#MYEXTRA=" --no-defaults --log-bin --server-id=0 --plugin-load=TokuDB=ha_tokudb.so --tokudb-check-jemalloc=0 --plugin-load-add=RocksDB=ha_rocksdb.so"    # --init-file=${SCRIPT_PWD}/plugins_57.sql --performance-schema --thread_handling=pool-of-threads"' >> start
#echo '#MYEXTRA=" --no-defaults --log-bin --server-id=0 --plugin-load-add=RocksDB=ha_rocksdb.so"    # --init-file=${SCRIPT_PWD}/plugins_57.sql --performance-schema --thread_handling=pool-of-threads"' >> start
echo '#MYEXTRA=" --no-defaults --gtid_mode=ON --enforce_gtid_consistency=ON --log_slave_updates=ON --log_bin=binlog --binlog_format=ROW --master_info_repository=TABLE --relay_log_info_repository=TABLE"' >>start
echo "#MYEXTRA=\" --no-defaults --performance-schema --performance-schema-instrument='%=on'\"" >>start
#echo '#MYEXTRA=" --no-defaults --default-tmp-storage-engine=MyISAM --rocksdb --skip-innodb --default-storage-engine=RocksDB  # For fb-mysql only"' >> start
echo '#MYEXTRA=" --no-defaults --event-scheduler=ON --maximum-bulk_insert_buffer_size=1M --maximum-join_buffer_size=1M --maximum-max_heap_table_size=1M --maximum-max_join_size=1M --maximum-myisam_max_sort_file_size=1M --maximum-myisam_mmap_size=1M --maximum-myisam_sort_buffer_size=1M --maximum-optimizer_trace_max_mem_size=1M --maximum-preload_buffer_size=1M --maximum-query_alloc_block_size=1M --maximum-query_prealloc_size=1M --maximum-range_alloc_block_size=1M --maximum-read_buffer_size=1M --maximum-read_rnd_buffer_size=1M --maximum-sort_buffer_size=1M --maximum-tmp_table_size=1M --maximum-transaction_alloc_block_size=1M --maximum-transaction_prealloc_size=1M --log-output=none --sql_mode=ONLY_FULL_GROUP_BY"' >>start
add_san_options start
if [ "${USE_JE}" -eq 1 ]; then
  echo $JE1 >>start
  echo $JE2 >>start
  echo $JE3 >>start
  echo $JE4 >>start
  echo $JE5 >>start
  echo $JE6 >>start
  echo $JE7 >>start
fi
cp start start_valgrind # Idem setup for Valgrind
cp start start_gypsy    # Idem setup for gypsy
cp start start_rr       # Idem setup for rr
echo "$BIN  \${MYEXTRA} ${START_OPT} --basedir=${PWD} --tmpdir=${PWD}/data --datadir=${PWD}/data ${TOKUDB} ${ROCKSDB} --socket=${SOCKET} --port=$PORT --log-error=${PWD}/log/master.err --server-id=100 \${MYEXTRA_OPT}  2>&1 &" >>start
echo "for X in \$(seq 0 70); do if ${PWD}/bin/mysqladmin ping -uroot -S${SOCKET} > /dev/null 2>&1; then break; fi; sleep 0.25; done" >>start
if [ "${VERSION_INFO}" != "5.1" -a "${VERSION_INFO}" != "5.5" -a "${VERSION_INFO}" != "5.6" ]; then
  echo "${PWD}/bin/mysql -uroot --socket=${SOCKET}  -e'CREATE DATABASE IF NOT EXISTS test;'" >>start
fi
echo " valgrind --suppressions=${PWD}/mysql-test/valgrind.supp --num-callers=40 --show-reachable=yes $BIN \${MYEXTRA} ${START_OPT} --basedir=${PWD} --tmpdir=${PWD}/data --datadir=${PWD}/data ${TOKUDB} --socket=${SOCKET} --port=$PORT --log-error=${PWD}/log/master.err >>${PWD}/log/master.err 2>&1 &" >>start_valgrind
echo "$BIN \${MYEXTRA} ${START_OPT} --general_log=1 --general_log_file=${PWD}/general.log --basedir=${PWD} --tmpdir=${PWD}/data --datadir=${PWD}/data ${TOKUDB} --socket=${SOCKET} --port=$PORT --log-error=${PWD}/log/master.err 2>&1 &" >>start_gypsy
echo "export _RR_TRACE_DIR=\"${PWD}/rr\"" >>start_rr
echo "if [ -d \"\${_RR_TRACE_DIR}\" ]; then  # Security measure to avoid incorrect mass-rm" >>start_rr
echo "  if [ \"\${_RR_TRACE_DIR}\" == \"\${PWD}/rr\" ]; then  # Security measure to avoid incorrect mass-rm" >>start_rr
echo "    rm -Rf \"\${_RR_TRACE_DIR}\"" >>start_rr
echo "  fi" >>start_rr
echo "fi" >>start_rr
echo "mkdir -p \"\${_RR_TRACE_DIR}\"" >>start_rr
echo "/usr/bin/rr record --chaos $BIN \${MYEXTRA} ${START_OPT} --loose-innodb-flush-method=fsync --general_log=1 --general_log_file=${PWD}/general.log --basedir=${PWD} --tmpdir=${PWD}/data --datadir=${PWD}/data ${TOKUDB} --socket=${SOCKET} --port=$PORT --log-error=${PWD}/log/master.err 2>&1 &" >>start_rr
echo "echo 'Server socket: ${SOCKET} with datadir: ${PWD}/data'" >>start
tail -n1 start >>start_valgrind
tail -n1 start >>start_gypsy
tail -n1 start >>start_rr

# -- Replication setup
echo '#!/usr/bin/env bash' >repl_setup
echo "REPL_TYPE=\$1" >>repl_setup
echo "if [[ \"\$REPL_TYPE\" = \"MSR\" ]]; then" >>repl_setup
echo "  NODES=2" >>repl_setup
echo "else" >>repl_setup
echo "  NODES=1" >>repl_setup
echo "fi" >>repl_setup
echo 'MYEXTRA=" --no-defaults --gtid_mode=ON --enforce_gtid_consistency=ON --log_slave_updates=ON --log_bin=binlog --binlog_format=ROW --master_info_repository=TABLE --relay_log_info_repository=TABLE"' >>repl_setup
echo "RPORT=$(($RANDOM % 10000 + 10000))" >>repl_setup
echo "echo \"\" > stop_repl" >>repl_setup
echo "if ${PWD}/bin/mysqladmin -uroot -S$PWD/socket.sock ping > /dev/null 2>&1; then" >>repl_setup
echo "  ${PWD}/bin/mysql -A -uroot -S${SOCKET}  -Bse\"create user repl@'%' identified by 'repl';\"" >>repl_setup
echo "  ${PWD}/bin/mysql -A -uroot -S${SOCKET}  -Bse\"grant all on *.* to repl@'%'; flush privileges;\"" >>repl_setup
echo "  MASTER_PORT=\$(\${PWD}/bin/mysql -A -uroot -S\${SOCKET}  -Bse\"select @@port\")" >>repl_setup
echo "else" >>repl_setup
echo "  echo \"ERROR! Master server is not started. Make sure to start master with GTID enabled. Terminating!\"" >>repl_setup
echo "  exit 1" >>repl_setup
echo "fi" >>repl_setup
echo "for i in \`seq 1 \$NODES\`;do" >>repl_setup
echo "  RBASE=\"\$(( RPORT + \$i ))\"" >>repl_setup
echo "  if [[ \"\$REPL_TYPE\" = \"MSR\" ]]; then" >>repl_setup
echo "    if [ \$i -eq 1 ]; then" >>repl_setup
echo "      node=\"${PWD}/masternode2\"" >>repl_setup
echo "    else" >>repl_setup
echo "      node=\"${PWD}/slavenode\"" >>repl_setup
echo "    fi" >>repl_setup
echo "  else" >>repl_setup
echo "    node=\"${PWD}/slavenode\"" >>repl_setup
echo "  fi" >>repl_setup
echo "  if [ ! -d \$node ]; then" >>repl_setup
echo "    $INIT_TOOL ${INIT_OPT} --basedir=${PWD} --datadir=\${node} > ${PWD}/startup_node\$i.err 2>&1 || exit 1;" >>repl_setup
echo "  fi" >>repl_setup
echo "  $BIN  \${MYEXTRA} ${START_OPT} --basedir=${PWD} --tmpdir=\${node} --datadir=\${node} ${TOKUDB} ${ROCKSDB} --socket=\$node/socket.sock --port=\$RBASE --report-host=$ADDR --report-port=\$RBASE  --server-id=10\$i --log-error=\$node/mysql.err 2>&1 &" >>repl_setup
echo "  for X in \$(seq 0 70); do if ${PWD}/bin/mysqladmin ping -uroot -S\$node/socket.sock > /dev/null 2>&1; then break; fi; sleep 0.25; done" >>repl_setup
echo "  if [[ \"\$REPL_TYPE\" = \"MSR\" ]]; then" >>repl_setup
echo "    if [ \$i -eq 1 ]; then" >>repl_setup
echo "      ${PWD}/bin/mysql -A -uroot --socket=\$node/socket.sock  -Bse\"create user repl@'%' identified by 'repl';\"" >>repl_setup
echo "      ${PWD}/bin/mysql -A -uroot --socket=\$node/socket.sock  -Bse\"grant all on *.* to repl@'%';flush privileges;\"" >>repl_setup
echo "      echo -e \"${PWD}/bin/mysql -A -uroot -S\$node/socket.sock --prompt \\\"masternode2> \\\"\" > ${PWD}/masternode2_cl " >>repl_setup
echo "    else" >>repl_setup
echo "      echo -e \"${PWD}/bin/mysql -A -uroot -S\$node/socket.sock --prompt \\\"slavenode> \\\"\" > ${PWD}/\slavenode_cl " >>repl_setup
echo "    fi" >>repl_setup
echo "  else" >>repl_setup
echo "    echo -e \"${PWD}/bin/mysql -A -uroot -S\$node/socket.sock --prompt \\\"slavenode> \\\"\" > ${PWD}/\slavenode_cl " >>repl_setup
echo "  fi" >>repl_setup

echo "  echo \"${PWD}/bin/mysqladmin -uroot -S\$node/socket.sock shutdown\" >> stop_repl" >>repl_setup
echo "  echo \"echo 'Server on socket \$node/socket.sock with datadir \$node halted'\" >> stop_repl" >>repl_setup
echo "  if [[ \"\$REPL_TYPE\" = \"MSR\" ]]; then" >>repl_setup
echo "    if [ \$i -eq 2 ]; then" >>repl_setup
echo "      MASTER_PORT2=\$(${PWD}/bin/mysql -A -uroot -S${PWD}/masternode2/socket.sock  -Bse\"SELECT @@port\")" >>repl_setup
if [ "${VERSION_INFO}" == "8.0" ]; then
  echo "      ${PWD}/bin/mysql -A -uroot -S\$node/socket.sock  -Bse\"CHANGE MASTER TO MASTER_HOST='127.0.0.1',MASTER_PORT=\$MASTER_PORT, MASTER_USER='repl',MASTER_PASSWORD='repl',MASTER_AUTO_POSITION=1,GET_MASTER_PUBLIC_KEY=1 FOR CHANNEL 'master1';\"" >>repl_setup
  echo "      ${PWD}/bin/mysql -A -uroot -S\$node/socket.sock  -Bse\"CHANGE MASTER TO MASTER_HOST='127.0.0.1',MASTER_PORT=\$MASTER_PORT2, MASTER_USER='repl',MASTER_PASSWORD='repl',MASTER_AUTO_POSITION=1,GET_MASTER_PUBLIC_KEY=1 FOR CHANNEL 'master2';\"" >>repl_setup
else
  echo "      ${PWD}/bin/mysql -A -uroot -S\$node/socket.sock  -Bse\"CHANGE MASTER TO MASTER_HOST='127.0.0.1',MASTER_PORT=\$MASTER_PORT, MASTER_USER='repl',MASTER_PASSWORD='repl',MASTER_AUTO_POSITION=1 FOR CHANNEL 'master1';\"" >>repl_setup
  echo "      ${PWD}/bin/mysql -A -uroot -S\$node/socket.sock  -Bse\"CHANGE MASTER TO MASTER_HOST='127.0.0.1',MASTER_PORT=\$MASTER_PORT2, MASTER_USER='repl',MASTER_PASSWORD='repl',MASTER_AUTO_POSITION=1 FOR CHANNEL 'master2';\"" >>repl_setup
fi
echo "      ${PWD}/bin/mysql -A -uroot -S\$node/socket.sock  -Bse\"START SLAVE;\"" >>repl_setup
echo "    fi" >>repl_setup
echo "  else" >>repl_setup
if [ "${VERSION_INFO}" == "8.0" ]; then
  echo "    ${PWD}/bin/mysql -A -uroot -S\$node/socket.sock  -Bse\"CHANGE MASTER TO MASTER_HOST='127.0.0.1',MASTER_PORT=\$MASTER_PORT, MASTER_USER='repl',MASTER_PASSWORD='repl',MASTER_AUTO_POSITION=1,GET_MASTER_PUBLIC_KEY=1;START SLAVE;\"" >>repl_setup
else
  echo "    ${PWD}/bin/mysql -A -uroot -S\$node/socket.sock  -Bse\"CHANGE MASTER TO MASTER_HOST='127.0.0.1',MASTER_PORT=\$MASTER_PORT, MASTER_USER='repl',MASTER_PASSWORD='repl',MASTER_AUTO_POSITION=1;START SLAVE;\"" >>repl_setup
fi
echo "  fi" >>repl_setup
echo "done" >>repl_setup
echo "if [[ \"\$REPL_TYPE\" = \"MSR\" ]]; then" >>repl_setup
echo "  chmod +x  masternode2_cl slavenode_cl stop_repl" >>repl_setup
echo "else" >>repl_setup
echo "  chmod +x  slavenode_cl stop_repl" >>repl_setup
echo "fi" >>repl_setup

# TODO: fix the line below somehow, and add binary-files=text for all greps. Also revert redirect to >> for second line
#echo "set +H" > kill  # Fails with odd './kill: 1: set: Illegal option -H' when kill_all is used?
echo "ps -ef | grep \"\$(whoami)\" | grep \"\${PWD}/log/master.err\" | grep -v grep | awk '{print \$2}' | xargs kill -9 2>/dev/null" >kill
echo "timeout -k90 -s9 90s ${PWD}/bin/mysqladmin -uroot -S${SOCKET} shutdown" >stop # 90 seconds to allow core dump to be written if needed (seems ~60 is the minimum for busy high-end severs)
echo "./kill >/dev/null 2>&1" >>stop
echo "echo 'Server on socket ${SOCKET} with datadir ${PWD}/data halted'" >>stop
echo "./init;./start;./cl;./stop;./kill >/dev/null 2>&1;tail log/master.err" >setup

echo 'MYEXTRA_OPT="$*"' >wipe
echo "./stop >/dev/null 2>&1" >>wipe
#echo "rm -Rf ${PWD}/data.PREV; mv ${PWD}/data ${PWD}/data.PREV 2>/dev/null" >> wipe  # Removed to save disk space, changed to next line
echo "rm -Rf ${PWD}/data ${PWD}/rr" >>wipe
if [ "${USE_JE}" -eq 1 ]; then
  echo $JE1 >>wipe
  echo $JE2 >>wipe
  echo $JE3 >>wipe
  echo $JE4 >>wipe
  echo $JE5 >>wipe
  echo $JE6 >>wipe
  echo $JE7 >>wipe
fi
echo "$INIT_TOOL ${INIT_OPT} \${MYEXTRA_OPT} --basedir=${PWD} --datadir=${PWD}/data" >> wipe
echo "rm -f log/master.err.PREV" >>wipe
echo "if [ -r log/master.err ]; then mv log/master.err log/master.err.PREV; fi" >>wipe
# Replacement for code below which was disabled. RV/RS considered it necessary to leave this to make it easier to use start and immediately have the test db available so it can be used for quick access. It also does not affect using --init-file=...plugins_80.sql
echo "./start \${MYEXTRA_OPT}; ${PWD}/bin/mysql -uroot --socket=${SOCKET}  -e'CREATE DATABASE IF NOT EXISTS test' ; ./stop" >>wipe
# Creating init script
echo "./stop >/dev/null 2>&1;./kill >/dev/null 2>&1" >init
echo "rm -Rf ${PWD}/data" >> init
echo "$INIT_TOOL ${INIT_OPT} --basedir=${PWD} --datadir=${PWD}/data" >>init
echo "rm -f log/master.*" >>init



echo "#!/bin/bash" >loopin
echo 'if [ -z "${1}" ]; then echo "Assert: please specify how many copies to make as the first option to this script"; exit 1; fi' >>loopin
echo 'if [ -r out.sql ]; then mv out.sql out.PREV; fi' >>loopin
echo 'if [ "$(grep -o "DROP DATABASE test" ./in.sql)" == "" -o "$(grep -o "CREATE DATABASE test" ./in.sql)" == "" -o "$(grep -o "USE test" ./in.sql)" == "" ]; then' >>loopin
echo '  if [ ! -r ./fixin ]; then echo "Assert: ./fixin not found? Please execute ~/start or ~/mariadb-qa/startup.sh"; exit 1; fi' >>loopin
echo '  ./fixin' >>loopin
echo 'fi' >>loopin
echo 'for i in $(seq 1 ${1}); do cat in.sql >> out.sql; done' >>loopin
echo 'wc -l in.sql' >>loopin
echo 'wc -l out.sql' >>loopin
echo 'echo "Generated out.sql which contains ${1} copies of in.sql, including DROP/CREATE/USE DATABASE test!"' >>loopin
echo 'echo "You may now want to: mv out.sql in.sql and then start ~/b which will then use the multi-looped in.sql"' >>loopin
echo "#!/bin/bash" >multirun_mysqld
echo "~/mariadb-qa/multirun_mysqld.sh \"\${*}\"" >>multirun_mysqld
echo "#!/bin/bash" >multirun_mysqld_text
echo "# First option passed to ./multirun_mysqld_text should be the string to look for" >>multirun_mysqld_text
echo "# Second option passed to ./multirun_mysqld_text can be the MYEXTRA string, if any (optional)" >>multirun_mysqld_text
echo "if [ -z \"\${1}\" ]; then echo \"Assert: first variable passed to ./multirun_mysqld_text should be the TEXT string to look for. Do not use uniqueID's (not implemented yet), instead use a string to look for in the error log, like a single mangled frameor a partial error message\"; exit 1; fi" >>multirun_mysqld_text
echo "MODTEXT=\"\$(echo \"\${1}\" | sed \"s|^[ '\t]||g;s|[ '\t]$||\")\"" >>multirun_mysqld_text
echo "~/mariadb-qa/multirun_mysqld.sh TEXT \"\${1}\" \"\$(echo \"\${*}\" | sed \"s|^[ ]*\${MODTEXT}[ ]*||\")\" " >>multirun_mysqld_text
echo "#!/bin/bash" >kill_multirun
echo "ps -ef | grep \"\$(whoami)\" | grep -v grep | grep \"\$(echo \"\${PWD}\" | sed 's|[do][bp][g[t]||')\" | grep 'multirun' | awk '{print \$2}' | xargs kill -9 2>/dev/null" >>kill_multirun
echo "#!/bin/bash" >multirun
echo "if [ ! -r ./in.sql ]; then echo 'Missing ./in.sql - please create it!'; exit 1; fi" >>multirun
echo "if [ ! -r ./all_no_cl ]; then echo 'Missing ./all_no_cl - perhaps run ~/start or ~/mariadb-qa/startup.sh again?'; exit 1; fi" >>multirun
echo "if [ \"\$(grep -o 'DROP DATABASE test' ./in.sql)\" == \"\" -o \"\$(grep -o 'CREATE DATABASE test' ./in.sql)\" == \"\" -o \"\$(grep -o 'USE test' ./in.sql)\" == \"\" ]; then" >>multirun
echo "  echo \"Warning: 'DROP/CREATE/USE DATABASE test;' queries NOT all present in in.sql, which may negatively affect issue reproducibilitiy when using multiple executions of the same code (due to pre-exisiting server states)! Consider adding:\"" >>multirun
echo "  echo '--------------------'" >>multirun
echo "  echo 'DROP DATABASE test;'" >>multirun
echo "  echo 'CREATE DATABASE test;'" >>multirun
echo "  echo 'USE test;'" >>multirun
echo "  echo '--------------------'" >>multirun
echo "  echo 'To the top of in.sql to improve issue reproducibility when executing via multirun'" >>multirun
echo "  echo 'NOTE: This can be done easily by pressing CTRL+C now and running ./fixin which fix this'" >>multirun
echo "  read -p 'Press enter to continue, or press CTRL+C to action this now...'" >>multirun
echo "fi" >>multirun
echo "./all_no_cl \"\$* --max_connections=10000\"" >>multirun
echo "if [ ! -r ~/mariadb-qa/multirun_cli.sh ]; then echo 'Missing ~/mariadb-qa/multirun_cli.sh - did you pull mariadb-qa from GitHub?'; exit 1; fi" >>multirun
echo "sed -i 's|^RND_DELAY_FUNCTION=[0-9]|RND_DELAY_FUNCTION=0|' ~/mariadb-qa/multirun_cli.sh" >>multirun
echo "sed -i 's|^RND_REPLAY_ORDER=[0-9]|RND_REPLAY_ORDER=0|' ~/mariadb-qa/multirun_cli.sh" >>multirun
echo "sed -i 's|^REPORT_END_THREAD=[0-9]|REPORT_END_THREAD=0|' ~/mariadb-qa/multirun_cli.sh" >>multirun
echo "sed -i 's|^REPORT_THREADS=[0-9]|REPORT_THREADS=0|' ~/mariadb-qa/multirun_cli.sh" >>multirun
echo "echo '===== Replay mode/order:'" >>multirun
echo "echo \"Order: \$(if grep -qi 'RND_REPLAY_ORDER=1' ~/mariadb-qa/multirun_cli.sh; then echo -n 'RANDOM ORDER!'; else echo 'SEQUENTIAL SQL (NON-RANDOM)'; fi)\"" >>multirun
echo "echo ''" >>multirun
ln -s ./multirun ./m 2>/dev/null
cp ./multirun ./multirun_pquery

echo "#~/mariadb-qa/multirun_cli.sh 200 100000 in.sql ${PWD}/bin/mysql ${SOCKET}" >>multirun
echo "~/mariadb-qa/multirun_cli.sh 1 10000000 in.sql ${PWD}/bin/mysql ${SOCKET}" >>multirun
echo "# Note that there are two levels of threading: the number of pquery clients started (as set by $1), and the number of pquery threads initiated/used by each of those pquery clients (as set by $7)." >>multirun_pquery
echo "" >>multirun_pquery
echo "## 10 pquery clients, 20 threads each (almost never used)" >>multirun_pquery
echo "#~/mariadb-qa/multirun_pquery.sh 10 100000 in.sql /home/\$(whoami)/mariadb-qa/pquery/pquery2-md ${SOCKET} ${PWD} 20" >>multirun_pquery
echo "" >>multirun_pquery
echo "## Single pquery client, 220 threads (common)" >>multirun_pquery
echo "~/mariadb-qa/multirun_pquery.sh 1 10000000 in.sql /home/\$(whoami)/mariadb-qa/pquery/pquery2-md ${SOCKET} ${PWD} 220" >>multirun_pquery
echo "" >>multirun_pquery
echo "## Single pquery client, single thread (most common)" >>multirun_pquery
echo "#~/mariadb-qa/multirun_pquery.sh 1 10000000 in.sql /home/\$(whoami)/mariadb-qa/pquery/pquery2-md ${SOCKET} ${PWD} 1" >>multirun_pquery

cp ./multirun ./multirun_rr
sed -i 's|all_no_cl|all_no_cl_rr|g' ./multirun_rr
cp ./multirun_pquery ./multirun_pquery_rr
sed -i 's|all_no_cl|all_no_cl_rr|g' ./multirun_pquery_rr

if [[ $MDG -eq 1 ]]; then
  cp multirun gal_multirun
  cp multirun_pquery gal_multirun_pquery
  sed -i "s|${SOCKET}|${PWD}/node1/node1_socket.sock|g" gal_multirun*
  sed -i "s|all_no_cl|gal_no_cl|g" gal_multirun*
  ln -s ./gal_multirun ./g_m 2>/dev/null
fi

if [[ $MDG -eq 0 ]]; then
  if [ ! -z "$LOAD_TOKUDB_INIT_FILE" ]; then
    echo "./start; ${PWD}/bin/mysql -A -uroot -S${SOCKET} < ${LOAD_TOKUDB_INIT_FILE}" >myrocks_tokudb_init
    if [ ! -z "$LOAD_ROCKSDB_INIT_FILE" ]; then
      echo " ${PWD}/bin/mysql -A -uroot -S${SOCKET} < ${LOAD_ROCKSDB_INIT_FILE} ; ./stop " >>myrocks_tokudb_init
    else
      echo "./stop " >>myrocks_tokudb_init
    fi
  else
    if [[ ! -z "$LOAD_ROCKSDB_INIT_FILE" ]]; then
      echo "./start; ${PWD}/bin/mysql -A -uroot -S${SOCKET} < ${LOAD_ROCKSDB_INIT_FILE} ; ./stop" >myrocks_tokudb_init
    fi
  fi
fi

BINMODE=
if [ "${VERSION_INFO}" != "5.1" -a "${VERSION_INFO}" != "5.5" ]; then
  BINMODE="--binary-mode " # Leave trailing space
fi
touch cl
add_san_options cl
echo "${PWD}/bin/mysql -A -uroot -S${SOCKET} --force --prompt=\"\$(${PWD}/bin/mysqld --version | grep -o 'Ver [\\.0-9]\\+' | sed 's|[^\\.0-9]*||')\$(if [ \"\$(pwd | grep -o '...$' | sed 's|[do][bp][gt]|aaa|')\" == \"aaa\" ]; then echo \"-\$(pwd | grep -o '...$')\"; fi)>\" ${BINMODE}test" >>cl
touch cl_noprompt
add_san_options cl_noprompt
echo "${PWD}/bin/mysql -A -uroot -S${SOCKET} --force ${BINMODE}test" >>cl_noprompt
touch cl_noprompt_nobinary
add_san_options cl_noprompt_nobinary
echo "${PWD}/bin/mysql -A -uroot -S${SOCKET} --force test" >>cl_noprompt_nobinary
touch test test_pquery
add_san_options test
add_san_options test_pquery
echo "${PWD}/bin/mysql -A -uroot -S${SOCKET} --force ${BINMODE}test < ${PWD}/in.sql > ${PWD}/mysql.out 2>&1" >>test
echo "/home/$(whoami)/mariadb-qa/pquery/pquery2-md --database=test --infile=${PWD}/in.sql --threads=1 --logdir=${PWD} --log-all-queries --log-failed-queries --no-shuffle --user=root --socket=${SOCKET} 2>&1 | tee ${PWD}/pquery.out" >>test_pquery

echo '#!/bin/bash' > clean_failing_queries
echo '# This script elimiates failing queries from in.sql in two different ways and saves the results in cleaned1.sql and cleaned2.sql' >> clean_failing_queries
echo "echo ''" >> clean_failing_queries
echo 'rm -f ./cleaned1.sql.safe ./cleaned2.sql.safe' >> clean_failing_queries
echo 'if [ -r ./cleaned1.sql ]; then mv ./cleaned1.sql ./cleaned1.sql.safe; fi' >> clean_failing_queries
echo 'if [ -r ./cleaned2.sql ]; then mv ./cleaned2.sql ./cleaned2.sql.safe; fi' >> clean_failing_queries
echo 'grep --binary-files=text "#NOERROR" in.sql > cleaned1.sql' >> clean_failing_queries
echo './all_no_cl "${*}"' >> clean_failing_queries
echo "echo ''" >> clean_failing_queries
echo "echo 'Executing testcase...'" >> clean_failing_queries
echo './test' >> clean_failing_queries
echo "echo 'Processing queries...'" >> clean_failing_queries
echo "grep --binary-files=text '^ERROR' mysql.out | grep -o ') at line [0-9]\+:' | grep -o '[0-9]\+' | sort -nr | sed 's|$|d;|' | tr -d '\n' | sed \"s|^|sed '|;s|$|' in.sql > cleaned2.sql\n|\" > ./cln_in && chmod +x ./cln_in && ./cln_in && rm -f ./cln_in" >> clean_failing_queries
echo "echo ''" >> clean_failing_queries
echo "echo 'Done! Failing queries from in.sql were eliminated.'" >> clean_failing_queries
echo "echo '      The result (via #NOERROR selection) is stored in: cleaned1.sql'" >> clean_failing_queries
echo "echo '      The result (from re-execution test) is stored in: cleaned2.sql'" >> clean_failing_queries
echo "echo ''" >> clean_failing_queries
echo "echo 'You can also have a look at mysql.out to see the output of the orginal in.sql execution (i.e. with errors intact)'" >> clean_failing_queries
echo "echo ''" >> clean_failing_queries
echo "echo 'Warning #1: mysqld options can easily change the outcome of replays. For example setting --sql_mode= as a startup option will result in engine substituion (with the default engine) where a specified engine is unkown, thereby completely altering any error vs no error results.'" >> clean_failing_queries
echo "echo 'Warning #2: currently all errors are filtered out. However, an error may show on a statement which partially executed correctly. For example, DROP TABLE t1,t2; where t1 exists but t2 does not will seem to fail with ERROR 1051 (42S02) however on closer inspection, it will show that only t2 is reported as an unknown table whereas t1 was dropped and thereby all execution thereafter is changed between the cleaned and non-cleaned versions.'" >> clean_failing_queries

if [[ $MDG -eq 1 ]]; then
  cp cl gal_cl
  cp cl_noprompt gal_cl_noprompt
  cp cl_noprompt_nobinary gal_cl_noprompt_nobinary
  cp test gal_test
  cp test_pquery gal_test_pquery
  sed -i "s|${SOCKET}|${PWD}/node1/node1_socket.sock|g" gal_cl gal_cl_noprompt gal_cl_noprompt_nobinary gal_test gal_test_pquery
fi

if [ "$(sysbench --version | cut -d ' ' -f2 | grep -oe '[0-9]\.[0-9]')" == "0.5" ]; then
  if [ "${VERSION_INFO}" == "8.0" ]; then
    echo "${PWD}/bin/mysql -uroot --socket=${SOCKET} -e \"CREATE USER IF NOT EXISTS sysbench_user@'%' identified with mysql_native_password by 'test';GRANT ALL ON *.* TO sysbench_user@'%'\" 2>&1" >sysbench_prepare
    echo "sysbench --test=/usr/share/doc/sysbench/tests/db/parallel_prepare.lua --mysql-engine-trx=yes --mysql-table-engine=innodb --oltp_table_size=10000 --oltp_tables_count=10 --mysql-db=test --mysql-user=sysbench_user --mysql-password=test  --db-driver=mysql --mysql-socket=${SOCKET} prepare" >>sysbench_prepare
    echo "sysbench --report-interval=10 --max-time=50 --max-requests=0 --mysql-engine-trx=yes --test=/usr/share/doc/sysbench/tests/db/oltp.lua --init-rng=on --oltp_index_updates=10 --oltp_non_index_updates=10 --oltp_distinct_ranges=15 --oltp_order_ranges=15 --oltp_tables_count=1 --num-threads=4 --oltp_table_size=1000000 --mysql-db=test --mysql-user=sysbench_user --mysql-password=test  --db-driver=mysql --mysql-socket=${SOCKET} run" >sysbench_run
  else
    echo "sysbench --test=/usr/share/doc/sysbench/tests/db/parallel_prepare.lua --mysql-engine-trx=yes --mysql-table-engine=innodb --oltp_table_size=10000 --oltp_tables_count=10 --mysql-db=test --mysql-user=root  --db-driver=mysql --mysql-socket=${SOCKET} prepare" >sysbench_prepare
    echo "sysbench --report-interval=10 --max-time=50 --max-requests=0 --mysql-engine-trx=yes --test=/usr/share/doc/sysbench/tests/db/oltp.lua --init-rng=on --oltp_index_updates=10 --oltp_non_index_updates=10 --oltp_distinct_ranges=15 --oltp_order_ranges=15 --oltp_tables_count=10 --num-threads=10 --oltp_table_size=10000 --mysql-db=test --mysql-user=root  --db-driver=mysql --mysql-socket=${SOCKET} run" >sysbench_run
  fi
elif [ "$(sysbench --version | cut -d ' ' -f2 | grep -oe '[0-9]\.[0-9]')" == "1.0" ]; then
  if [ "${VERSION_INFO}" == "8.0" ]; then
    echo "${PWD}/bin/mysql -uroot --socket=${SOCKET} -e \"CREATE USER IF NOT EXISTS sysbench_user@'%' identified with mysql_native_password by 'test';GRANT ALL ON *.* TO sysbench_user@'%'\" 2>&1" >sysbench_prepare
    echo "sysbench /usr/share/sysbench/oltp_insert.lua  --mysql-storage-engine=innodb --table-size=10000 --tables=10 --threads=10 --mysql-db=test --mysql-user=sysbench_user --mysql-password=test  --db-driver=mysql --mysql-socket=${SOCKET} prepare" >>sysbench_prepare
    echo "sysbench /usr/share/sysbench/oltp_read_write.lua --report-interval=10 --time=50 --events=0 --index_updates=10 --non_index_updates=10 --distinct_ranges=15 --order_ranges=15 --tables=10 --threads=10  --table-size=1000000 --mysql-db=test --mysql-user=sysbench_user --mysql-password=test  --db-driver=mysql --mysql-socket=${SOCKET} run" >sysbench_run
  else
    echo "sysbench /usr/share/sysbench/oltp_insert.lua  --mysql-storage-engine=innodb --table-size=10000 --tables=10 --threads=10 --mysql-db=test --mysql-user=root --db-driver=mysql --mysql-socket=${SOCKET} prepare" >sysbench_prepare
    echo "sysbench /usr/share/sysbench/oltp_read_write.lua --report-interval=10 --time=50 --events=0 --index_updates=10 --non_index_updates=10 --distinct_ranges=15 --order_ranges=15 --tables=10 --threads=10  --table-size=100000  --mysql-db=test --mysql-user=root --db-driver=mysql --mysql-socket=${SOCKET} run" >sysbench_run
  fi
fi
if [[ $MDG -eq 0 ]]; then
  echo "./stop 2>/dev/null;./kill >/dev/null 2>&1;./wipe;./start;./sysbench_prepare;./sysbench_run;./stop;./kill >/dev/null 2>&1;" >sysbench_measure
else
  cp sysbench_prepare gal_sysbench_prepare
  cp sysbench_run gal_sysbench_run
  sed -i "s|${SOCKET}|${PWD}/node1/node1_socket.sock|g" gal_sysbench*
  echo "./gal_stop 2>/dev/null;./gal_kill >/dev/null 2>&1;./gal_wipe;./gal_start;./gal_sysbench_prepare;./gal_sysbench_run;./gal_stop;./gal_kill >/dev/null 2>&1;" >gal_sysbench_measure
fi

# RV/RS discussed this code 19/12/18 and decided we should disable and ultimately remove it. There is myrocks_tokudb_init already, which can do the same if needed (i.e. load extra TokuDB and RocksDB plugins). The main reason to remove this code is that loading these extra plugins always by defaut will make --init-file=...plugins_80.sql not work with errors like 'Function 'tokudb_file_map' already exists.' which can affect issue reproducibility (as not all plugins are loaded), or even hide bugs with plugins_80.sql if there are any (when it's used with ./start).
#if [ ! -z "$LOAD_TOKUDB_INIT_FILE" ]; then
#  echo "./start \${MYEXTRA_OPT}; ${PWD}/bin/mysql -A -uroot -S${SOCKET} < ${LOAD_TOKUDB_INIT_FILE} ; ${PWD}/bin/mysql -uroot --socket=${SOCKET}  -e'CREATE DATABASE IF NOT EXISTS test' ;" >> wipe
#  if [ ! -z "$LOAD_ROCKSDB_INIT_FILE" ] ; then
#    echo " ${PWD}/bin/mysql -A -uroot -S${SOCKET} < ${LOAD_ROCKSDB_INIT_FILE} ; ./stop " >> wipe
#  else
#    echo "./stop" >> wipe
#  fi
#else
#  if [[ ! -z "$LOAD_ROCKSDB_INIT_FILE" ]];then
#    echo "./start \${MYEXTRA_OPT}; ${PWD}/bin/mysql -A -uroot -S${SOCKET} < ${LOAD_ROCKSDB_INIT_FILE} ;${PWD}/bin/mysql -uroot --socket=${SOCKET}  -e'CREATE DATABASE IF NOT EXISTS test' ; ./stop" >> wipe
#  else
#    echo "./start \${MYEXTRA_OPT}; ${PWD}/bin/mysql -uroot --socket=${SOCKET}  -e'CREATE DATABASE IF NOT EXISTS test' ; ./stop" >> wipe
#  fi
#fi

# Add handy local reducers
if [ -r ${SCRIPT_PWD}/reducer.sh ]; then
  # ------------------- ./reducer_new_text_string.sh creation
  cp ${SCRIPT_PWD}/reducer.sh ./reducer_new_text_string.sh
  sed -i 's|somebug|${2}|' ./reducer_new_text_string.sh
  sed -i 's|^\(MYEXTRA="[^"]\+\)"|\1 ${3}"|' ./reducer_new_text_string.sh
  sed -i 's|^MODE=4|MODE=3|' ./reducer_new_text_string.sh
  sed -i 's|^MULTI_THREADS=[0-9]\+|MULTI_THREADS=13|' ./reducer_new_text_string.sh
  sed -i 's|^KNOWN_BUGS_LOC=[^#]\+|KNOWN_BUGS_LOC="/home/$(whoami)/mariadb-qa/known_bugs.strings"   |' ./reducer_new_text_string.sh
  sed -i 's|^FORCE_SKIPV=0|FORCE_SKIPV=1|' ./reducer_new_text_string.sh
  sed -i 's|^USE_NEW_TEXT_STRING=0|USE_NEW_TEXT_STRING=1|' ./reducer_new_text_string.sh
  sed -i 's|^STAGE1_LINES=[^#]\+|STAGE1_LINES=10   |' ./reducer_new_text_string.sh
  sed -i 's|^SCAN_FOR_NEW_BUGS=[^#]\+|SCAN_FOR_NEW_BUGS=1   |' ./reducer_new_text_string.sh
  sed -i 's|^NEW_BUGS_COPY_DIR=[^#]\+|NEW_BUGS_COPY_DIR="/data/NEWBUGS"   |' ./reducer_new_text_string.sh
  sed -i 's|^TEXT_STRING_LOC=[^#]\+|TEXT_STRING_LOC="/home/$(whoami)/mariadb-qa/new_text_string.sh"   |' ./reducer_new_text_string.sh
  sed -i 's|^PQUERY_LOC=[^#]\+|PQUERY_LOC="/home/$(whoami)/mariadb-qa/pquery/pquery2-md"   |' ./reducer_new_text_string.sh
  # ------------------- ./reducer_errorlog.sh creation
  cp ./reducer_new_text_string.sh ./reducer_errorlog.sh
  sed -i 's|^USE_NEW_TEXT_STRING=1|USE_NEW_TEXT_STRING=0|' ./reducer_errorlog.sh
  sed -i 's|^SCAN_FOR_NEW_BUGS=1|SCAN_FOR_NEW_BUGS=0|' ./reducer_errorlog.sh  # SCAN_FOR_NEW_BUGS=1 Not supported yet when using USE_NEW_TEXT_STRING=0
  # ------------------- ./reducer_errorlog_pquery.sh creation
  cp ./reducer_errorlog.sh ./reducer_errorlog_pquery.sh
  sed -i 's|^USE_PQUERY=0|USE_PQUERY=1|' ./reducer_errorlog_pquery.sh
  # ------------------- ./reducer_new_text_string_pquery.sh creation
  cp ./reducer_new_text_string.sh ./reducer_new_text_string_pquery.sh
  sed -i 's|^USE_PQUERY=0|USE_PQUERY=1|' ./reducer_new_text_string_pquery.sh
  # ------------------- ./reducer_fireworks.sh creation
  cp ${SCRIPT_PWD}/reducer.sh ./reducer_fireworks.sh
  mkdir -p ./FIREWORKS-BUGS
  sed -i "s|^NEW_BUGS_COPY_DIR=[^#]\+|NEW_BUGS_COPY_DIR=\"${PWD}/FIREWORKS-BUGS\"   |"  ./reducer_fireworks.sh
  sed -i 's|^KNOWN_BUGS_LOC=[^#]\+|KNOWN_BUGS_LOC="/home/$(whoami)/mariadb-qa/known_bugs.strings"   |' ./reducer_fireworks.sh
  sed -i 's|^TEXT_STRING_LOC=[^#]\+|TEXT_STRING_LOC="/home/$(whoami)/mariadb-qa/new_text_string.sh"   |' ./reducer_fireworks.sh
  sed -i 's|^PQUERY_LOC=[^#]\+|PQUERY_LOC="/home/$(whoami)/mariadb-qa/pquery/pquery2-md"   |' ./reducer_fireworks.sh
  sed -i 's|^FIREWORKS=0|FIREWORKS=1|' ./reducer_fireworks.sh
  sed -i 's|^MYEXTRA=.*|MYEXTRA="--no-defaults ${3}"|' ./reducer_fireworks.sh  # It is best not to add --sql_mode=... as this will significantly affect CLI replay attempts as the CLI by default does not set --sql_mode=... as normally defined in reducer.sh's MYEXTRA default (--sql_mode=ONLY_FULL_GROUP_BY). Reason: with either --sql_mode= or --sql_mode=--sql_mode=ONLY_FULL_GROUP_BY engine substituion (to the default storage engine, i.e. InnoDB or MyISAM in MTR) is enabled. Replays at the CLI would thus look significantly different by default (i.e. unless this option was passed and by default it is not)
fi

echo 'rm -f in.tmp' >fixin
echo 'if [ -r ./in.sql ]; then mv in.sql in.tmp; fi' >>fixin
echo 'echo "DROP DATABASE test;" > ./in.sql' >>fixin
echo 'echo "CREATE DATABASE test;" >> ./in.sql' >>fixin
echo 'echo "USE test;" >> ./in.sql' >>fixin
echo 'if [ -r ./in.tmp ]; then cat in.tmp >> in.sql; rm -f in.tmp; fi' >>fixin

echo "${SCRIPT_PWD}/stack.sh" >stack
echo "if [ \$(ls data/*core* 2>/dev/null | wc -l) -eq 0 ]; then" >gdb
echo "  echo \"No core file found in data/*core* - exiting\"" >>gdb
echo "  exit 1" >>gdb
echo "elif [ \$(ls data/*core* 2>/dev/null | wc -l) -gt 1 ]; then" >>gdb
echo "  echo \"More then one core file found in data/*core* - exiting\"" >>gdb
echo "  exit 1" >>gdb
echo "else" >>gdb
echo "  gdb bin/mysqld \$(ls data/*core*)" >>gdb
echo "fi" >>gdb

if [[ $MDG -eq 1 ]]; then
  cp gdb gal_gdb
  sed -i "s|ls data/\*core\*|ls node1/\*core\*|g" gal_gdb
fi

if [ ! -r ./in.sql ]; then touch ./in.sql; fi  # Make new empty file if does not exist yet
echo './all --sql_mode=' >sqlmode
echo './all --log_bin' >binlog
echo 'MYEXTRA_OPT="$*"' >all
echo "./kill >/dev/null 2>&1;./stop >/dev/null 2>&1;./kill >/dev/null 2>&1;rm -f socket.sock socket.sock.lock;./wipe \${MYEXTRA_OPT};./start \${MYEXTRA_OPT};./cl" >>all
ln -s ./all ./a 2>/dev/null
echo 'MYEXTRA_OPT="$*"' >all_stbe
echo "./all --early-plugin-load=keyring_file.so --keyring_file_data=keyring --innodb_sys_tablespace_encrypt=ON \${MYEXTRA_OPT}" >>all_stbe # './all_stbe' is './all' with system tablespace encryption
echo 'MYEXTRA_OPT="$*"' >all_no_cl
echo "./kill >/dev/null 2>&1;./stop >/dev/null 2>&1;./kill >/dev/null 2>&1;rm -f socket.sock socket.sock.lock;./wipe \${MYEXTRA_OPT};./start \${MYEXTRA_OPT}" >>all_no_cl
echo 'MYEXTRA_OPT="$*"' >all_no_cl_rr
echo "./kill >/dev/null 2>&1;./stop >/dev/null 2>&1;./kill >/dev/null 2>&1;rm -f socket.sock socket.sock.lock;./wipe \${MYEXTRA_OPT};./start_rr \${MYEXTRA_OPT};sleep 10" >>all_no_cl_rr
echo 'MYEXTRA_OPT="$*"' >all_rr
echo "./kill >/dev/null 2>&1;./stop >/dev/null 2>&1;./kill >/dev/null 2>&1;rm -f socket.sock socket.sock.lock;./wipe \${MYEXTRA_OPT};./start_rr \${MYEXTRA_OPT};sleep 10;./cl" >>all_rr
echo "echo '1/4th sec memory snapshots, for the mysqld in this directory, logged to memory.txt'; rm -f memory.txt; echo '    PID %MEM   RSS    VSZ COMMAND'; while true; do if [ \"\$(ps -ef | grep ${PORT} | grep -v grep)\" ]; then ps --sort -rss -eo pid,pmem,rss,vsz,comm | grep \"\$(ps -ef | grep ${PORT} | grep -v grep | head -n1 | awk '{print \$2}')\" | tee -a memory.txt ; sleep 0.25; else sleep 0.05; fi; done" >memory_use_trace
if [ -r ${SCRIPT_PWD}/startup_scripts/multitest ]; then cp ${SCRIPT_PWD}/startup_scripts/multitest .; fi
chmod +x insert_start_marker insert_stop_marker start start_valgrind start_gypsy start_rr stop setup cl cl_noprompt cl_noprompt_nobinary test test_pquery kill init wipe sqlmode binlog all all_stbe all_no_cl all_rr all_no_cl_rr sysbench_prepare sysbench_run sysbench_measure gdb stack fixin loopin myrocks_tokudb_init repl_setup *multirun* reducer_* clean_failing_queries memory_use_trace 2>/dev/null

# Adding galera all script
echo './gal --sql_mode=' >gal_sqlmode
echo './gal --log_bin' >gal_binlog
echo 'MYEXTRA_OPT="$*"' >gal
echo "./gal_kill >/dev/null 2>&1;./gal_stop >/dev/null 2>&1;./gal_kill >/dev/null 2>&1;rm -f node*/*socket.sock node*/*socket.sock.lock;./gal_wipe \${MYEXTRA_OPT};./gal_start \${MYEXTRA_OPT};./gal_cl" >>gal
ln -s ./gal ./g 2>/dev/null
echo 'MYEXTRA_OPT="$*"' >gal_stbe
echo "./gal --early-plugin-load=keyring_file.so --keyring_file_data=keyring --innodb_sys_tablespace_encrypt=ON \${MYEXTRA_OPT}" >>gal_stbe # './gal_stbe' is './gal' with system tablespace encryption
echo 'MYEXTRA_OPT="$*"' >gal_no_cl
echo "./gal_kill >/dev/null 2>&1;rm -f node*/*socket.sock node*/*socket.sock.lock;./gal_wipe \${MYEXTRA_OPT};./gal_start \${MYEXTRA_OPT}" >>gal_no_cl
echo 'MYEXTRA_OPT="$*"' >gal_rr
echo "./gal_kill >/dev/null 2>&1;./gal_stop >/dev/null 2>&1;./gal_kill >/dev/null 2>&1;rm -f node*/*socket.sock node*/*socket.sock.lock;./gal_wipe \${MYEXTRA_OPT};./gal_start_rr \${MYEXTRA_OPT};./gal_cl" >>gal_rr
chmod +x gal gal_cl gal_sqlmode gal_binlog gal_stbe gal_no_cl gal_rr gal_gdb gal_test gal_test_pquery gal_cl_noprompt_nobinary gal_cl_noprompt gal_multirun gal_multirun_pquery gal_sysbench_measure gal_sysbench_prepare gal_sysbench_run 2>/dev/null
echo "Setting up server with default directories"

if [[ $MDG -eq 0 ]]; then
  ./stop >/dev/null 2>&1
  ./init
  if [[ -r ${PWD}/lib/mysql/plugin/ha_tokudb.so ]] || [[ -r ${PWD}/lib/mysql/plugin/ha_rocksdb.so ]]; then
    echo "Enabling additional TokuDB/ROCKSDB engine plugin items if exists"
    ./myrocks_tokudb_init
  fi
  echo "Done! To get a fresh instance at any time, execute: ./all (executes: stop;kill;wipe;start;cl)"
  echo "      To get a fresh instance now, execute: ./start then wait 3 seconds and execute ./cl"
else
  ./gal_stop >/dev/null 2>&1
  ./gal_init
  echo "Done! To get a fresh instance at any time, execute: ./all (executes: gal_stop;gal_kill;gal_wipe;gal_start;1_node_cli)"
  echo "      To get a fresh instance now, execute: ./gal_start then wait 3 seconds and execute ./1_node_cli"
fi
exit 0

