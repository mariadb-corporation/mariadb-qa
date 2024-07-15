#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Expanded by Roel Van de Paar, MariaDB
# Updated by Ramesh Sivaraman, MariaDB

# Random entropy init
RANDOM=$(date +%s%N | cut -b10-19 | sed 's|^[0]\+||')

# Filter the following text (regex aware) from INIT_TOOL startup
FILTER_INIT_TEXT='^[ \t]*$|Installing.*system tables|OK|To start mysqld at boot time|To start mariadbd at boot time|to the right place for your system|PLEASE REMEMBER TO SET A PASSWORD|then issue the following command|bin/mysql_secure_installation|which will also give you the option|databases and anonymous user created by default|strongly recommended for production servers|See the MariaDB Knowledgebase at|You can start the MariaDB daemon|mysqld_safe --datadir|You can test the MariaDB daemon|perl mysql-test-run.pl|Please report any problems at|The latest information about MariaDB|strong and vibrant community|mariadb.org/get-involved|^[2-9][0-9][0-9][0-9][0-9][0-9] [0-2][0-9]:|^20[2-9][0-9]|See the manual|start the MySQL daemon|bin/mysqld_safe|test the MySQL daemon with|latest information about|http://|https://|by buying support/|Found existing config file|Because this file might be in use|but was used in bootstrap|when you later start the server|new default config file was created|compare it with your file|root.*new.*password|Alternatively you can run|will be used by default|You may edit this file to change|Filling help tables|TIMESTAMP with implicit DEFAULT value|You can find the latest source|the maria-discuss email list|Please check all of the above|Optimizer switch:|perl mariadb|^cd |bin/mariadb-secure-installation|secure-file-priv value as server is running with|starting as process|Using unique option prefix core|Deprecated program name|Corporation subscription customer|consultative guidance on questions|how to tune for performance'

# Ensure that if AFL variables were set, they are cleared first to avoid the server not starting due to 'shmat for map: Bad file descriptor'
export -n __AFL_SHM_ID
export -n AFL_MAP_SIZE

# Nr of MDG nodes 1-n
NR_OF_NODES=${1}
if [ -z "${NR_OF_NODES}" ] ; then
  NR_OF_NODES=3
fi

if [[ "${PWD}" == *"SAN"* ]]; then sudo sysctl vm.mmap_rnd_bits=28; fi  # Workaround, ref https://github.com/google/sanitizers/issues/856 (also ref the same line in 'start' created below)

PORT=$NEWPORT
MTRT=$((${RANDOM} % 100 + 700))
BUILD=$(pwd | sed 's|^.*/||')
SCRIPT_PWD="$(readlink -f "${0}" | sed "s|$(basename "${0}")||;s|/\+$||")"
source $SCRIPT_PWD/init_empty_port.sh
cp $SCRIPT_PWD/init_empty_port.sh ${PWD}/
cp $SCRIPT_PWD/gencerts.sh ${PWD}/
init_empty_port
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
  echo 'export ASAN_OPTIONS=quarantine_size_mb=512:atexit=0:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1:allocator_may_return_null=1' >>"${1}"
  # check_initialization_order=1 cannot be used due to https://jira.mariadb.org/browse/MDEV-24546 TODO
  # detect_stack_use_after_return=1 will likely require thread_stack increase (check error log after ./all) TODO
  #echo 'export ASAN_OPTIONS=quarantine_size_mb=512:atexit=0:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1:allocator_may_return_null=1' >> "${1}"
  echo 'export UBSAN_OPTIONS=print_stacktrace=1' >>"${1}"
  echo 'export TSAN_OPTIONS=suppress_equal_stacks=1:suppress_equal_addresses=1:history_size=7:verbosity=1' >>"${1}"
  echo 'export MSAN_OPTIONS=abort_on_error=1:poison_in_dtor=0' >>"${1}"
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

# Delete any .cnf files. Whilst the framework takes care of not accidentally reading .cnf files (generally by using --no-defaults everwhere), it is best to delete these unnecessary files. Also cleanup some other non-used files
rm -f *.cnf COPYING CREDITS README-wsrep THIRDPARTY README* LICENSE*

# Get version specific options
BIN=
if [ -r ${PWD}/bin/mariadbd ]; then BIN="${PWD}/bin/mariadbd"; 
elif [ -r ${PWD}/bin/mysqld-debug ]; then BIN="${PWD}/bin/mysqld-debug";  # Needs to come first so it's overwritten in next line if both exist
elif [ -r ${PWD}/bin/mysqld ]; then BIN="${PWD}/bin/mysqld"; 
fi
if [ -z "${BIN}" ]; then
  echo "Assert: no mariadb, mysqld-debug or mysqld binary was found!"
  exit 1
fi
MID=
if [ -r ${BASEDIR}/scripts/mariadb-install-db ]; then MID="${BASEDIR}/scripts/mariadb-install-db"; fi
if [ -r ${PWD}/scripts/mysql_install_db ]; then MID="${PWD}/scripts/mysql_install_db"; fi
if [ -r ${PWD}/bin/mysql_install_db ]; then MID="${PWD}/bin/mysql_install_db"; fi
START_OPT="--core-file"                        # Compatible with 5.6,5.7,8.0
INIT_OPT="--no-defaults --initialize-insecure" # Compatible with     5.7,8.0 (mysqld init)
INIT_TOOL="${BIN}"                             # Compatible with     5.7,8.0 (mysqld init), changed to MID later if version <=5.6
VERSION_INFO=$(${BIN} --version | grep --binary-files=text -oe '[58]\.[01567]' | head -n1)
if [ -z "${VERSION_INFO}" ]; then VERSION_INFO="NA"; fi
VERSION_INFO_2=$(${BIN} --version | grep --binary-files=text -i 'MariaDB' | grep -oe '1[0-1]\.[0-9][0-9]*' | head -n1)
if [ -z "${VERSION_INFO_2}" ]; then VERSION_INFO_2="NA"; fi

if [[ "${VERSION_INFO_2}" =~ ^10.[1-3]$ ]]; then
  VERSION_INFO="5.1"
  INIT_TOOL="${PWD}/scripts/mysql_install_db"
  INIT_OPT="--no-defaults --force"
  START_OPT="--core"
elif [[ "${VERSION_INFO_2}" =~ ^1[0-1].[0-9][0-9]* ]]; then
  VERSION_INFO="5.6"
  INIT_TOOL="${PWD}/scripts/mariadb-install-db"
  INIT_OPT="--no-defaults --force --auth-root-authentication-method=normal ${MYINIT}"
  #START_OPT="--core-file --core"
  START_OPT="--core-file"
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
  echo "Note: Group Replication plugin not found. Skipping Group Replication startup"
  GRP_RPL=0
fi

# Check MariaDB Galera Cluster
MDG=0
GALERA_LIB=
SOCKET=${PWD}/socket.sock
SLAVE_SOCKET=${PWD}/socket_slave.sock
if [ -r lib/libgalera_smm.so ]; then
  echo "CS Galera plugin found. Adding CS Galera startup"
  MDG=1
  GALERA_LIB=${PWD}/lib/libgalera_smm.so
elif [ -r lib/libgalera_enterprise_smm.so ]; then
  echo "ES Galera plugin found. Adding ES Galera startup"
  MDG=1
  GALERA_LIB=${PWD}/lib/libgalera_enterprise_smm.so
else
  echo "Note: Galera plugin not found. Skipping Galera startup"
fi

# Setup scritps
rm -f *_node_cl* *cl cl* *cli all* binlog fixin gal* gdb init loopin *multirun* multitest myrocks_tokudb_init reducer_* repl_setup setup sqlmode stack start* stop* sysbench* test ts tsp test_* wipe* clean_failing_queries memory_use_trace afl* ml mlp master_setup.sql slave_setup.sql mysql.out mysql_slave.out 2>/dev/null
BASIC_SCRIPTS="start | start_valgrind | start_gypsy | start_master | start_slave | start_replication | stop | stop_slave | kill | kill_slave | setup | cl | cl_slave | test | test_pquery | test_timed | test_timed_pquery | test_sanity | test_sanity_pquery | init | wipe | wipe_slave | sqlmode | binlog | all | all_stbe | all_no_cl | all_rr | all_no_cl_rr | reducer_new_text_string.sh | reducer_new_text_string_pquery.sh | reducer_errorlog.sh | reducer_errorlog_pquery.sh | reducer_fireworks.sh | reducer_hang.sh | reducer_hang_pquery.sh | sysbench_prepare | sysbench_run | sysbench_measure | multirun | multirun_loop (ml) | multirun_loop_pquery (mlp) | multirun_rr | multirun_pquery | multirun_pquery_rr | multirun_mysqld | multirun_mysqld_text | multirun_loop_replication | kill_multirun | loopin | gdb | fixin | stack | memory_use_trace | myrocks_tokudb_init | afl | aflnew | multitest | stress.sh"
GRP_RPL_SCRIPTS="start_group_replication (and stop_group_replication is created dynamically on group replication startup)"
GALERA_SCRIPTS="gal_start | gal_start_rr | gal_stop | gal_init | gal_kill | gal_setup | gal_wipe | *_node_cli | gal_test_pquery | gal | gal_cl | gal_sqlmode | gal_binlog | gal_stbe | gal_no_cl | gal_rr | gal_gdb | gal_test | gal_cl_noprompt_nobinary | gal_cl_noprompt | gal_multirun | gal_multirun_pquery | gal_sysbench_measure | gal_sysbench_prepare | gal_sysbench_run"
if [[ $GRP_RPL -eq 1 ]]; then
  echo "Adding scripts: ${BASIC_SCRIPTS} | ${GRP_RPL_SCRIPTS}"
elif [[ $MDG -eq 1 ]]; then
  echo "Adding scripts: ${BASIC_SCRIPTS} ${GALERA_SCRIPTS}"
else
  echo "Adding scripts: ${BASIC_SCRIPTS}"
fi

# AFL Squirrel
# OLD
if [ -r ${HOME}/mariadb-qa/fuzzer/afl ]; then
  ln -s ${HOME}/mariadb-qa/fuzzer/afl ./afl
fi
# NEW  (Note that we can clear __AFL_SHM_ID and AFL_MAP_SIZE ocne server is started as it maintains the same when already started)
echo "export ASAN_OPTIONS=quarantine_size_mb=512:atexit=0:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1:allocator_may_return_null=1; export UBSAN_OPTIONS=print_stacktrace=1; export TSAN_OPTIONS=suppress_equal_stacks=1:suppress_equal_addresses=1:history_size=7:verbosity=1; export MSAN_OPTIONS=abort_on_error=1:poison_in_dtor=0; ./kill >/dev/null 2>&1; rm -f ./AFL_SHM.ID; export -n __AFL_SHM_ID; export -n AFL_MAP_SIZE; echo 'Armed: you can now start squirrel.'; echo 'Doing so will trigger the server to start (and reboot with a clean data dir when crashed)...'; while true; do if ${PWD}/bin/mysqladmin ping -uroot -S${PWD}/socket.sock > /dev/null 2>&1; then export -n __AFL_SHM_ID; export -n AFL_MAP_SIZE; sleep 0.2; else export -n __AFL_SHM_ID; export AFL_MAP_SIZE=50000000; while [ ! -r ${PWD}/AFL_SHM.ID ]; do sleep 0.2; done; export __AFL_SHM_ID=\$(cat AFL_SHM.ID); ./all_no_cl; sleep 0.2; export -n AFL_MAP_SIZE; export -n AFL_MAP_SIZE; fi; done" >aflnew
chmod +x aflnew

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
  echo "wsrep_sst_method=rsync" >>my.cnf
  echo "#wsrep_sst_method=mariabackup" >>my.cnf
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
    echo "$INIT_TOOL ${INIT_OPT} --basedir=${PWD} --datadir=${PWD}/node${i} 2>&1 | grep --binary-files=text -vEi '${FILTER_INIT_TEXT}'" >>./gal_init

    echo "${PWD}/bin/mysql -A -uroot -S${PWD}/node${i}/node${i}_socket.sock test --prompt \"node${i}:\\u@\\h> \"" >${PWD}/${i}_node_cli
    echo "$INIT_TOOL ${INIT_OPT} --basedir=${PWD} --datadir=${PWD}/node${i} 2>&1 | grep --binary-files=text -vEi '${FILTER_INIT_TEXT}'" >>gal_wipe
    echo "if [ -r node1/node${i}.err ]; then rm node${i}/node${i}.err*; fi" >>gal_wipe
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
touch in.sql
MTR_DIR="./mysql-test"
if [ -d "./mariadb-test" ]; then MTR_DIR="./mariadb-test"; fi
if [ -d "${MTR_DIR}" ]; then
  echo 'export UBSAN_OPTIONS=print_stacktrace=1' >${MTR_DIR}/cl_mtr
  echo 'if [ -z "$(netstat -tuln | grep ':16000')" ]; then' >>${MTR_DIR}/cl_mtr
  echo '  ./mtr --start-and-exit' >>${MTR_DIR}/cl_mtr
  echo 'fi' >>${MTR_DIR}/cl_mtr
  echo '../bin/mariadb -P16000 -h127.0.0.1 -uroot' >>${MTR_DIR}/cl_mtr
  sed "s|\/mtr |/mtr --mysqld=--innodb --mysqld=--default-storage-engine=Innodb |" ${MTR_DIR}/cl_mtr > ${MTR_DIR}/cl_mtr_innodb
  chmod +x ${MTR_DIR}/cl_mtr ${MTR_DIR}/cl_mtr_innodb
  echo '#Loop MTR on main/test.test till it fails' >${MTR_DIR}/loop_mtr
  echo "LOG=\"\$(mktemp)\"; echo \"Logfile: \${LOG}\"; LOOP=0; while true; do LOOP=\$[ \${LOOP} + 1 ]; echo \"Loop: \${LOOP}\"; ./mtr test 2>&1 >>\${LOG}; if grep -q 'fail ' \${LOG}; then break; fi; done" >>${MTR_DIR}/loop_mtr
  chmod +x ${MTR_DIR}/loop_mtr
  cp ${MTR_DIR}/loop_mtr ${MTR_DIR}/loop_mtr_multi
  sed -i 's^ ./mtr test^ MTR_MEM=/dev/shm ./mysql-test-run --parallel=100 --repeat 100 --mem --force --retry=0 --retry-failure=0 test{,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,} ^' ${MTR_DIR}/loop_mtr_multi
  cp ${MTR_DIR}/loop_mtr ${MTR_DIR}/loop_mtr_skip_slave_err
  cp ${MTR_DIR}/loop_mtr_multi ${MTR_DIR}/loop_mtr_multi_skip_slave_err
  sed -i 's^ ./mtr^ ./mtr --mysqld=--slave_skip_errors=ALL^' ${MTR_DIR}/loop_mtr_skip_slave_err
  sed -i 's^ ./mysql-test-run^ ./mysql-test-run --mysqld=--slave_skip_errors=ALL^' ${MTR_DIR}/loop_mtr_multi_skip_slave_err
fi
MTR_DIR=
echo 'MYEXTRA_OPT="$*"' >start
echo 'MYEXTRA=" --no-defaults --max_connections=10000 "' >>start
echo '#MYEXTRA=" --no-defaults --ssl=0 "' >>start
echo '#MYEXTRA=" --no-defaults --sql_mode= "' >>start
#echo '#MYEXTRA=" --no-defaults --log-bin --server-id=0 --plugin-load=TokuDB=ha_tokudb.so --tokudb-check-jemalloc=0 --plugin-load-add=RocksDB=ha_rocksdb.so"    # --init-file=${SCRIPT_PWD}/plugins_57.sql --performance-schema --thread_handling=pool-of-threads"' >> start
#echo '#MYEXTRA=" --no-defaults --log-bin --server-id=0 --plugin-load-add=RocksDB=ha_rocksdb.so"    # --init-file=${SCRIPT_PWD}/plugins_57.sql --performance-schema --thread_handling=pool-of-threads"' >> start
echo '#MYEXTRA=" --no-defaults --gtid_mode=ON --enforce_gtid_consistency=ON --log_slave_updates=ON --log_bin=binlog --binlog_format=ROW --master_info_repository=TABLE --relay_log_info_repository=TABLE"' >>start
echo "#MYEXTRA=\" --no-defaults --performance-schema --performance-schema-instrument='%=on'\"" >>start
#echo '#MYEXTRA=" --no-defaults --default-tmp-storage-engine=MyISAM --rocksdb --skip-innodb --default-storage-engine=RocksDB  # For fb-mysql only"' >> start
echo '#MYEXTRA=" --no-defaults --event-scheduler=ON --maximum-bulk_insert_buffer_size=1M --maximum-join_buffer_size=1M --maximum-max_heap_table_size=1M --maximum-max_join_size=1M --maximum-myisam_max_sort_file_size=1M --maximum-myisam_mmap_size=1M --maximum-myisam_sort_buffer_size=1M --maximum-optimizer_trace_max_mem_size=1M --maximum-preload_buffer_size=1M --maximum-query_alloc_block_size=1M --maximum-query_prealloc_size=1M --maximum-range_alloc_block_size=1M --maximum-read_buffer_size=1M --maximum-read_rnd_buffer_size=1M --maximum-sort_buffer_size=1M --maximum-tmp_table_size=1M --maximum-transaction_alloc_block_size=1M --maximum-transaction_prealloc_size=1M --log-output=none --sql_mode=ONLY_FULL_GROUP_BY"' >>start
add_san_options start
echo 'rm -Rf data*/core*' >>start
if [ "${USE_JE}" -eq 1 ]; then
  echo $JE1 >>start
  echo $JE2 >>start
  echo $JE3 >>start
  echo $JE4 >>start
  echo $JE5 >>start
  echo $JE6 >>start
  echo $JE7 >>start
fi
echo "if [[ \"${PWD}\" == *\"SAN\"* ]]; then sudo sysctl vm.mmap_rnd_bits=28; fi  # Workaround, ref https://github.com/google/sanitizers/issues/856" >> start
echo "source ${PWD}/init_empty_port.sh" >>start
echo "init_empty_port" >>start
echo "PORT=\$NEWPORT" >>start
cp start start_valgrind # Idem setup for Valgrind
cp start start_gypsy    # Idem setup for gypsy
cp start start_rr       # Idem setup for rr
echo "$BIN \${MYEXTRA} ${START_OPT} --basedir=${PWD} --tmpdir=${PWD}/data --datadir=${PWD}/data ${TOKUDB} ${ROCKSDB} --socket=${SOCKET} --port=\$PORT --log-error=${PWD}/log/master.err --server-id=100 \${MYEXTRA_OPT} 2>&1 &" >>start
echo "for X in \$(seq 0 90); do if ${PWD}/bin/mysqladmin ping -uroot -S${SOCKET} > /dev/null 2>&1; then break; fi; sleep 0.25; done" >>start
if [ "${VERSION_INFO}" != "5.1" -a "${VERSION_INFO}" != "5.5" -a "${VERSION_INFO}" != "5.6" ]; then
  if [ -r "${PWD}/bin/mariadb" ]; then
    echo "${PWD}/bin/mariadb -uroot --socket=${SOCKET} -e'CREATE DATABASE IF NOT EXISTS test;'" >>start
  else
    echo "${PWD}/bin/mysql -uroot --socket=${SOCKET} -e'CREATE DATABASE IF NOT EXISTS test;'" >>start
  fi
fi
echo " valgrind --suppressions=${PWD}/mysql-test/valgrind.supp --num-callers=40 --show-reachable=yes $BIN \${MYEXTRA} ${START_OPT} --basedir=${PWD} --tmpdir=${PWD}/data --datadir=${PWD}/data ${TOKUDB} --socket=${SOCKET} --port=\$PORT --log-error=${PWD}/log/master.err >>${PWD}/log/master.err 2>&1 &" >>start_valgrind
echo "$BIN \${MYEXTRA} ${START_OPT} --general_log=1 --general_log_file=${PWD}/general.log --basedir=${PWD} --tmpdir=${PWD}/data --datadir=${PWD}/data ${TOKUDB} --socket=${SOCKET} --port=\$PORT --log-error=${PWD}/log/master.err 2>&1 &" >>start_gypsy
echo "export _RR_TRACE_DIR=\"${PWD}/rr\"" >>start_rr
echo "if [ -d \"\${_RR_TRACE_DIR}\" ]; then  # Security measure to avoid incorrect mass-rm" >>start_rr
echo "  if [ \"\${_RR_TRACE_DIR}\" == \"\${PWD}/rr\" ]; then  # Security measure to avoid incorrect mass-rm" >>start_rr
echo "    rm -Rf \"\${_RR_TRACE_DIR}\"" >>start_rr
echo "  fi" >>start_rr
echo "fi" >>start_rr
echo "mkdir -p \"\${_RR_TRACE_DIR}\"" >>start_rr
echo "/usr/bin/rr record --chaos $BIN \${MYEXTRA} \${MYEXTRA_OPT} ${START_OPT} --loose-innodb-flush-method=fsync --general_log=1 --general_log_file=${PWD}/general.log --basedir=${PWD} --tmpdir=${PWD}/data --datadir=${PWD}/data ${TOKUDB} --socket=${SOCKET} --port=\$PORT --log-error=${PWD}/log/master.err 2>&1 &" >>start_rr
echo "echo 'Server socket: ${SOCKET} with datadir: ${PWD}/data'" >>start
tail -n1 start >>start_valgrind
tail -n1 start >>start_gypsy
tail -n1 start >>start_rr
echo 'dd if=/dev/zero of=./tmpdir bs=1G count=1' >smalltmp
echo 'mkfs.ext4 ./tmpdir && mkdir -p ./tmp' >>smalltmp
echo 'sudo mount -o loop -t ext4 tmpdir ./tmp && sudo chown -R $(whoami):$(whoami) ./tmp' >> smalltmp
chmod +x smalltmp
# /path/to/image_file /path/to/directory ext4 loop 0 0 
# TODO: fix the line below somehow, and add binary-files=text for all greps. Also revert redirect to >> for second line
#echo "set +H" > kill  # Fails with odd './kill: 1: set: Illegal option -H' when kill_all is used?
echo "ps -ef | grep \"\$(whoami)\" | grep \"\${PWD}/log/master.err\" | grep -v grep | awk '{print \$2}' | xargs kill -9 2>/dev/null" >kill
if [ -r ./bin/mariadb-admin ]; then
  echo "timeout -k90 -s9 90s ${PWD}/bin/mariadb-admin -uroot -S${SOCKET} shutdown" >stop # 90 seconds to allow core dump to be written if needed (seems ~60 is the minimum for busy high-end severs)
else
  echo "timeout -k90 -s9 90s ${PWD}/bin/mysqladmin -uroot -S${SOCKET} shutdown" >stop # 90 seconds to allow core dump to be written if needed (seems ~60 is the minimum for busy high-end severs)
fi
echo "./kill >/dev/null 2>&1" >>stop
echo "echo 'Server on socket ${SOCKET} with datadir ${PWD}/data halted'" >>stop
echo "./init;./start;./cl;./stop;./kill >/dev/null 2>&1;tail log/master.err" >setup

echo 'MYEXTRA_OPT="$*"' >wipe
echo "./stop >/dev/null 2>&1" >>wipe
echo "rm -Rf ${PWD}/data ${PWD}/rr" >>wipe
echo "rm -Rf ${PWD}/data_slave  # Avoid old slave data interference" >>wipe
if [ "${USE_JE}" -eq 1 ]; then
  echo $JE1 >>wipe
  echo $JE2 >>wipe
  echo $JE3 >>wipe
  echo $JE4 >>wipe
  echo $JE5 >>wipe
  echo $JE6 >>wipe
  echo $JE7 >>wipe
fi
echo "$INIT_TOOL ${INIT_OPT} \${MYEXTRA_OPT} --basedir=${PWD} --datadir=${PWD}/data 2>&1 | grep --binary-files=text -vEi '${FILTER_INIT_TEXT}'" >> wipe
echo "rm -f log/*err*" >>wipe
# Replacement for code below which was disabled. RV/RS considered it necessary to leave this to make it easier to use start and immediately have the test db available so it can be used for quick access. It also does not affect using --init-file=...plugins_80.sql
if [ -r "${PWD}/bin/mariadb" ]; then
  echo "./start \${MYEXTRA_OPT}; ${PWD}/bin/mariadb -uroot --socket=${SOCKET} -e'CREATE DATABASE IF NOT EXISTS test'; ./stop" >>wipe
else
  echo "./start \${MYEXTRA_OPT}; ${PWD}/bin/mysql -uroot --socket=${SOCKET} -e'CREATE DATABASE IF NOT EXISTS test'; ./stop" >>wipe
fi
# Creating init script
echo "./stop >/dev/null 2>&1;./kill >/dev/null 2>&1" >init
echo "rm -Rf ${PWD}/data" >> init
echo "$INIT_TOOL ${INIT_OPT} --basedir=${PWD} --datadir=${PWD}/data 2>&1 | grep --binary-files=text -vEi '${FILTER_INIT_TEXT}'" >>init
echo "rm -f log/master.*" >>init

echo "#!/bin/bash" >loopin
echo 'if [ -z "${1}" ]; then echo "Assert: please specify how many copies to make as the first option to this script"; exit 1; fi' >>loopin
echo 'rm -f out.sql' >>loopin
echo 'if [ "$(grep -o "DROP DATABASE test" ./in.sql)" == "" -o "$(grep -o "CREATE DATABASE test" ./in.sql)" == "" -o "$(grep -o "USE test" ./in.sql)" == "" ]; then' >>loopin
echo '  if [ ! -r ./fixin ]; then echo "Assert: ./fixin not found? Please execute ~/start or ~/mariadb-qa/startup.sh"; exit 1; fi' >>loopin
echo '  ./fixin' >>loopin
echo 'fi' >>loopin
echo 'for i in $(seq 1 ${1}); do cat in.sql >> out.sql; done' >>loopin
echo 'wc -l in.sql' >>loopin
echo 'wc -l out.sql' >>loopin
echo 'echo "Generated out.sql which contains ${1} copies of in.sql, including DROP/CREATE/USE DATABASE test!"' >>loopin
echo 'echo "You may now want to: mv out.sql in.sql and then start ~/b which will then use the multi-looped in.sql"' >>loopin
echo "#!/bin/bash" >multirun_loop
ln -s ./multirun_loop ./ml
echo "# This script will keep looping in.sql until ./data/core* is present/detected. If loop cycles take 90 seconds or more, you may want to check that the server is not hanging in those 90 seconds (there is a 90 second timeout in ./stop which is being used, you could also increase that to establish if it is is the mysqladmin shutdown is hanging). Only other possible reason is a(very) large input SQL testcase. Generally loops will take 5 seconds or less with a small input file." >>multirun_loop
echo "# To look for a specific UniqueID bug, do:" >>multirun_loop
echo "# export BUG='...'    # Where ... is a UniqueID" >>multirun_loop
echo "# or, to look for a specific error log based bug, do:" >>multirun_loop
echo "# export ELBUG='...'  # Where ... is the text you want to scan for in the error log" >>multirun_loop
echo "# Note that you can also use a dummy search (export BUG='dummy') to see all possible UniqueID's a bug produces!" >>multirun_loop
echo "# Please do not set BUG and ELBUG variables at the same time, and remember to clear them before running a new unrelated multirun_loop" >>multirun_loop
echo "NR_OF_LOOPS=0" >>multirun_loop
echo "echo \"Number of lines in in.sql: \$(wc -l in.sql | sed 's| .*||')\"" >>multirun_loop
echo "rm -Rf ./data ./data.multirun" >>multirun_loop
echo "./all_no_cl \${*} > ./last_all_no_cl.multirun.log 2>&1" >>multirun_loop
echo "mv data data.multirun" >>multirun_loop
echo "loop(){" >>multirun_loop
echo "  NR_OF_LOOPS=\$[ \${NR_OF_LOOPS} + 1]; echo \"\$(date +'%F %T') Loop: \${NR_OF_LOOPS}...\"; rm -Rf ./data; cp -r ./data.multirun ./data; ./all_no_cl \${*} > ./last_all_no_cl.multirun.log 2>&1; ./test; ./stop >/dev/null 2>&1; sleep 2" >>multirun_loop
echo "}" >>multirun_loop
echo "if [ ! -z \"\${BUG}\" -a ! -z \"\${ELBUG}\" ]; then" >>multirun_loop
echo "  echo \"Assert: both BUG and ELBUG variables are set, please only set one\"" >>multirun_loop
echo "elif [ ! -z \"\${BUG}\" ]; then" >>multirun_loop
echo "  echo -e \"Looking for UniqueID (As per the BUG environment variable):\n   \${BUG}\"" >>multirun_loop
echo "  BUGSEEN=" >>multirun_loop
echo "  while [ \"\${BUGSEEN}\" != \"\${BUG}\" ]; do BUGSEEN=; loop; BUGSEEN=\"\$(\${HOME}/t | grep -vE '\-\-\-\-\-|Assert:' )\"; if [ ! -z \"\${BUGSEEN}\" -a \"\${BUGSEEN}\" != \"\${BUG}\" ]; then echo \"Another bug than the one being looked for was observed: \${BUGSEEN}\"; fi done" >>multirun_loop
echo "elif [ ! -z \"\${ELBUG}\" ]; then" >>multirun_loop
echo "  echo -e \"Looking for this string in the error log (As per the ELBUG environment variable):\n   \${ELBUG}\"" >>multirun_loop
echo "  BUGSEEN=" >>multirun_loop
echo "  while [ -z \"\$(grep --binary-files=text -iE \"\${ELBUG}\" ./log/master.err)\" ]; do loop; if [ -r ./data/core* ]; then if [ -z \"\$(grep --binary-files=text -iE \"\${ELBUG}\" ./log/master.err)\" ]; then BUGSEEN=\"\$(\${HOME}/t | grep -vE '\-\-\-\-\-' )\"; echo \"While the searched for string was not found in the error log, a crash was observed with UniqueID: \${BUGSEEN}\"; fi; fi; done" >>multirun_loop
echo "else" >>multirun_loop
echo "  echo -e \"BUG/ELBUG environment variables not set: looping testcase till a core* file is found\"" >>multirun_loop
echo "  while [ ! -r ./data/core* ]; do loop; done;" >>multirun_loop
echo "fi" >>multirun_loop
echo "sleep 2" >>multirun_loop
echo "-- tt output:" >>multirun_loop
echo "\${HOME}/tt" >>multirun_loop
echo "--" >>multirun_loop
echo "if [ -z \"\${ELBUG}\" ]; then" >>multirun_loop
echo "  echo \"Number of loops executed to obtain ./data/core*: \${NR_OF_LOOPS}\"" >>multirun_loop
echo "else" >>multirun_loop
echo "  echo \"Number of loops executed to observe \"\${ELBUG}\" in error log: \${NR_OF_LOOPS}\"" >>multirun_loop
echo "fi" >>multirun_loop
echo "rm -Rf ./data.multirun" >>multirun_loop
cp multirun_loop multirun_loop_pquery
ln -s ./multirun_loop_pquery ./mlp
ln -s ${SCRIPT_PWD}/multirun_loop_replication ${PWD}/multirun_loop_replication
sed -i 's|./test;|./test_pquery >/dev/null 2>\&1;|' multirun_loop_pquery
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
echo "REPLICATION=0       # Set to 1 for replication runs" >>multirun
echo "USERANDOM=0         # Set to 1 for random order SQL runs" >>multirun
echo "MULTI_THREADED=0    # Set to 1 for using more than 1 thread" >>multirun
echo "MULTI_THREADS=5000  # When MULTI_THREADED=1, this sets the number of threads used" >>multirun
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
echo "if [ \"\${REPLICATION}\" != \"1\" ]; then" >>multirun
echo "  ./all_no_cl \"\$* --max_connections=10000\"" >>multirun
echo "else" >>multirun
echo "  export SRNOCL=1" >>multirun
echo "  ./start_replication \"\$* --max_connections=10000\"" >>multirun
echo "fi" >>multirun
echo "if [ ! -r ~/mariadb-qa/multirun_cli.sh ]; then echo 'Missing ~/mariadb-qa/multirun_cli.sh - did you pull mariadb-qa from GitHub?'; exit 1; fi" >>multirun
echo "if [ \"\${USERANDOM}\" != \"1\" ]; then" >>multirun
echo "  sed -i 's|^RND_REPLAY_ORDER=[0-9]|RND_REPLAY_ORDER=0|' ~/mariadb-qa/multirun_cli.sh" >>multirun
echo "else" >>multirun
echo "  sed -i 's|^RND_REPLAY_ORDER=[0-9]|RND_REPLAY_ORDER=1|' ~/mariadb-qa/multirun_cli.sh" >>multirun
echo "fi" >>multirun
echo "sed -i 's|^RND_DELAY_FUNCTION=[0-9]|RND_DELAY_FUNCTION=0|' ~/mariadb-qa/multirun_cli.sh" >>multirun
echo "sed -i 's|^REPORT_END_THREAD=[0-9]|REPORT_END_THREAD=0|' ~/mariadb-qa/multirun_cli.sh" >>multirun
echo "sed -i 's|^REPORT_THREADS=[0-9]|REPORT_THREADS=0|' ~/mariadb-qa/multirun_cli.sh" >>multirun
echo "echo '===== Replay mode/order:'" >>multirun
echo "if [ \"\${USERANDOM}\" != \"1\" ]; then echo 'Order: SEQUENTIAL SQL (NON-RANDOM)'; else echo 'Order: RANDOM ORDER!'; fi" >>multirun
echo "echo ''" >>multirun
echo "echo '===== Testcase size:'" >>multirun
echo "wc -l in.sql | tr -d '\n'; echo \" (\$(wc -c in.sql | sed 's| .*||') bytes)\"" >>multirun
echo "echo ''" >>multirun
echo "echo '===== MYEXTRA options:'" >>multirun
echo "echo \"\$* --max_connections=10000\"" >>multirun
echo "echo ''" >>multirun
ln -s ./multirun ./m 2>/dev/null
cp ./multirun ./multirun_pquery

echo "if [ \"\${MULTI_THREADED}\" != \"1\" ]; then" >>multirun
CLIENT_TO_USE="mysql"
if [ -r "${PWD}/bin/mariadb" ]; then
  CLIENT_TO_USE="mariadb"
fi
echo "  ~/mariadb-qa/multirun_cli.sh 1 10000000 in.sql ${PWD}/bin/${CLIENT_TO_USE} ${SOCKET}" >>multirun
echo "else" >>multirun
echo "  ~/mariadb-qa/multirun_cli.sh \${MULTI_THREADS} 100000 in.sql ${PWD}/bin/${CLIENT_TO_USE} ${SOCKET}" >>multirun
echo "fi" >>multirun
echo "if [ \"\${MULTI_THREADED}\" != \"1\" ]; then" >>multirun_pquery
echo "  ~/mariadb-qa/multirun_pquery.sh 1 10000000 in.sql \${HOME}/mariadb-qa/pquery/pquery2-md ${SOCKET} ${PWD} 1" >>multirun_pquery
echo "else" >>multirun_pquery
echo "  ~/mariadb-qa/multirun_pquery.sh 1 10000000 in.sql \${HOME}/mariadb-qa/pquery/pquery2-md ${SOCKET} ${PWD} \${MULTI_THREADS}" >>multirun_pquery
echo "fi" >>multirun_pquery

cp ./multirun ./multirun_rr
sed -i 's|all_no_cl|all_no_cl_rr|g' ./multirun_rr
sed -i 's|start_replication|start_replication_rr|g' ./multirun_rr  # TODO: add start_replication_rr script
cp ./multirun_pquery ./multirun_pquery_rr
sed -i 's|all_no_cl|all_no_cl_rr|g' ./multirun_pquery_rr
sed -i 's|start_replication|start_replication_rr|g' ./multirun_pquery_rr  # Idem ^

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
if [ -r "${PWD}/bin/mariadb" ]; then
  echo "${PWD}/bin/mariadb -A -uroot -S${SOCKET} --force --prompt=\"\$(${PWD}/bin/mariadbd --version | grep -o 'Ver [\\.0-9]\\+' | sed 's|[^\\.0-9]*||')\$(if [ \"\$(pwd | grep -o '...$' | sed 's|[do][bp][gt]|aaa|')\" == \"aaa\" ]; then echo \"-\$(pwd | grep -o '...$')\"; fi)>\" ${BINMODE}test" >>cl
  echo "#${PWD}/bin/mariadb -A -uroot -S${SOCKET} --skip-ssl-verify-server-cert --skip-ssl --force --prompt=\"\$(${PWD}/bin/mariadbd --version | grep -o 'Ver [\\.0-9]\\+' | sed 's|[^\\.0-9]*||')\$(if [ \"\$(pwd | grep -o '...$' | sed 's|[do][bp][gt]|aaa|')\" == \"aaa\" ]; then echo \"-\$(pwd | grep -o '...$')\"; fi)>\" ${BINMODE}test" >>cl
else
  echo "${PWD}/bin/mysql -A -uroot -S${SOCKET} --force --prompt=\"\$(${PWD}/bin/mysqld --version | grep -o 'Ver [\\.0-9]\\+' | sed 's|[^\\.0-9]*||')\$(if [ \"\$(pwd | grep -o '...$' | sed 's|[do][bp][gt]|aaa|')\" == \"aaa\" ]; then echo \"-\$(pwd | grep -o '...$')\"; fi)>\" ${BINMODE}test" >>cl
fi
if [ -r ${PWD}/mariadb-test/mtr ]; then
  echo './mtr 1st --start-and-exit --mysqld=--log-bin && ../bin/mariadb -uroot -S./var/tmp/mysqld.1.sock test' > ${PWD}/mariadb-test/mc && echo 'cd mariadb-test; ./mc' > ${PWD}/mc && chmod +x ${PWD}/mariadb-test/mc ${PWD}/mc
elif [ -r ${PWD}/mysql-test/mtr ]; then
  echo './mtr 1st --start-and-exit --mysqld=--log-bin && ../bin/mariadb -uroot -S./var/tmp/mysqld.1.sock test' > ${PWD}/mysql-test/mc && echo 'cd mysql-test; ./mc' > ${PWD}/mc && chmod +x ${PWD}/mysql-test/mc ${PWD}/mc
fi
touch cl_noprompt
add_san_options cl_noprompt
if [ -r "${PWD}/bin/mariadb" ]; then
  echo "${PWD}/bin/mariadb -A -uroot -S${SOCKET} --force ${BINMODE}test" >>cl_noprompt
else
  echo "${PWD}/bin/mysql -A -uroot -S${SOCKET} --force ${BINMODE}test" >>cl_noprompt
fi
touch cl_noprompt_nobinary
add_san_options cl_noprompt_nobinary
if [ -r "${PWD}/bin/mariadb" ]; then
  echo "${PWD}/bin/mariadb -A -uroot -S${SOCKET} --force test" >>cl_noprompt_nobinary
else
  echo "${PWD}/bin/mysql -A -uroot -S${SOCKET} --force test" >>cl_noprompt_nobinary
fi
echo "#!/bin/bash" > test
add_san_options test
cp test test_pquery
cp test test_timed
echo "sed -i \"s|MYPORT|\$(grep -o 'port=[0-9]\+' start 2>/dev/null | sed 's|port=||')|\" in.sql" >>test
if [ -r "${PWD}/bin/mariadb" ]; then
  echo "${PWD}/bin/mariadb -A -uroot -S${SOCKET} --force ${BINMODE}test < ${PWD}/in.sql > ${PWD}/mysql.out 2>&1" >>test
else
  echo "${PWD}/bin/mysql -A -uroot -S${SOCKET} --force ${BINMODE}test < ${PWD}/in.sql > ${PWD}/mysql.out 2>&1" >>test
fi
echo "if [ -t 1 ]; then echo \"Exit status of client: \${?}\"; fi  # With thanks, https://serverfault.com/a/753459" >> test
echo "${HOME}/mariadb-qa/pquery/pquery2-md --database=test --infile=${PWD}/in.sql --threads=1 --logdir=${PWD} --log-all-queries --log-failed-queries --no-shuffle --user=root --socket=${SOCKET} 2>&1 | tee ${PWD}/pquery.out" >>test_pquery
echo "# Timing code, with thanks, https://stackoverflow.com/a/42359046/1208218 (dormi330)" >>test_timed
echo "start_at=\$(date +%s,%N)" >>test_timed
cp test_timed test_pquery_timed
if [ -r "${PWD}/bin/mariadb" ]; then
  echo "${PWD}/bin/mariadb -A -uroot -S${SOCKET} --force ${BINMODE}test < ${PWD}/in.sql > ${PWD}/mysql.out 2>&1" >>test_timed
else
  echo "${PWD}/bin/mysql -A -uroot -S${SOCKET} --force ${BINMODE}test < ${PWD}/in.sql > ${PWD}/mysql.out 2>&1" >>test_timed
fi
echo "${HOME}/mariadb-qa/pquery/pquery2-md --database=test --infile=${PWD}/in.sql --threads=1 --logdir=${PWD} --log-all-queries --log-failed-queries --log-query-duration --no-shuffle --user=root --socket=${SOCKET} 2>&1 | tee ${PWD}/pquery.out" >>test_pquery_timed
echo "end_at=\$(date +%s,%N)" >t_tmp1  # Temporary file to avoid duplicating commands here
echo "_s1=\$(echo \${start_at} | cut -d',' -f1)   # sec" >>t_tmp1
echo "_s2=\$(echo \${start_at} | cut -d',' -f2)   # nano sec" >>t_tmp1
echo "_e1=\$(echo \${end_at} | cut -d',' -f1)" >>t_tmp1
echo "_e2=\$(echo \${end_at} | cut -d',' -f2)" >>t_tmp1
echo "time_cost=\"\$(bc <<< \"scale=3; \${_e1} - \${_s1} + (\${_e2} - \${_s2})/1000000000\")\"" >>t_tmp1
echo "echo \"\${PWD} Duration: \${time_cost} seconds\" | sed 's|Duration: \\.|Duration: 0.|'" >>t_tmp1
cat t_tmp1 >>test_timed
cat t_tmp1 >>test_pquery_timed
rm -f t_tmp1
echo "#!/bin/bash" >test_sanity
echo "rm -f ts.log; ./kill >/dev/null 2>&1;" >>test_sanity
echo "LOOP=0; COUNT=0; INPUT=\"input.sql\"; if [ -z \"\${1}\" ]; then cat ${HOME}/mariadb-qa/BUGS/*.sql > input.sql; else INPUT=\"\${1}\"; fi;" >>test_sanity
echo "if [ -z \"\${2}\" ]; then NROFLINES=\$(wc -l \"\${INPUT}\" | sed 's| .*||'); else NROFLINES=\"\${2}\"; fi;" >>test_sanity
echo "echo \"INPUT: \${INPUT} | INPUT Lines: \$(wc -l \"\${INPUT}\" | sed 's| .*||') [\${NROFLINES} Used]\"" >>test_sanity
echo "while true; do LOOP=\$[ \${LOOP} + 1 ]; echo \"Loop #\${LOOP} [\${COUNT}] @ \$(date +'%D %T' | tr -d '\n')\" | tee -a ts.log; rm -f tt.res; grep -hvi --binary-files=text 'shutdown' "\${INPUT}" | shuf --random-source=/dev/urandom -n \${NROFLINES} > in.sql; timeout -k180 -s9 180s bash -c './all_no_cl >/dev/null'; timeout -k1300 -s9 1300s bash -c './test >/dev/null 2>&1'; timeout -k150 -s9 150s bash -c './stop >/dev/null 2>&1'; timeout -k150 -s9 150s bash -c './kill >/dev/null 2>&1'; timeout -k150 -s9 150s bash -c './kill >/dev/null 2>&1'; timeout -k120 -s9 120s bash -c '${HOME}/tt > tt.res'; if ! grep -qiE 'ALREADY KNOWN BUG|Assert: no core file found|MEMORY_NOT_FREED|Address already in use' tt.res; then COUNT=\$[ \${COUNT} + 1] ; cat tt.res | tee -a ts.log; cp in.sql \${COUNT}.sql; cp tt.res \${COUNT}.tt; else cat tt.res | head -n2 | tail -n1 | sed 's|^|  |' | tee -a ts.log; fi; done" >>test_sanity
ln -s test_sanity ts
cp test_sanity test_sanity_pquery
sed -i "s|./test |./test_pquery |;s|ts\.log|tsp.log|g" test_sanity_pquery
ln -s test_sanity_pquery tsp
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
    if [ -r "${PWD}/bin/mariadb" ]; then
      echo "${PWD}/bin/mariadb -uroot --socket=${SOCKET} -e \"CREATE USER IF NOT EXISTS sysbench_user@'%' identified with mysql_native_password by 'test';GRANT ALL ON *.* TO sysbench_user@'%'\" 2>&1" >sysbench_prepare
    else
      echo "${PWD}/bin/mysql -uroot --socket=${SOCKET} -e \"CREATE USER IF NOT EXISTS sysbench_user@'%' identified with mysql_native_password by 'test';GRANT ALL ON *.* TO sysbench_user@'%'\" 2>&1" >sysbench_prepare
    fi
    echo "sysbench --test=/usr/share/doc/sysbench/tests/db/parallel_prepare.lua --mysql-engine-trx=yes --mysql-table-engine=innodb --oltp_table_size=10000 --oltp_tables_count=10 --mysql-db=test --mysql-user=sysbench_user --mysql-password=test  --db-driver=mysql --mysql-socket=${SOCKET} prepare" >>sysbench_prepare
    echo "sysbench --report-interval=10 --max-time=50 --max-requests=0 --mysql-engine-trx=yes --test=/usr/share/doc/sysbench/tests/db/oltp.lua --init-rng=on --oltp_index_updates=10 --oltp_non_index_updates=10 --oltp_distinct_ranges=15 --oltp_order_ranges=15 --oltp_tables_count=1 --num-threads=4 --oltp_table_size=1000000 --mysql-db=test --mysql-user=sysbench_user --mysql-password=test  --db-driver=mysql --mysql-socket=${SOCKET} run" >sysbench_run
  else
    echo "sysbench --test=/usr/share/doc/sysbench/tests/db/parallel_prepare.lua --mysql-engine-trx=yes --mysql-table-engine=innodb --oltp_table_size=10000 --oltp_tables_count=10 --mysql-db=test --mysql-user=root  --db-driver=mysql --mysql-socket=${SOCKET} prepare" >sysbench_prepare
    echo "sysbench --report-interval=10 --max-time=50 --max-requests=0 --mysql-engine-trx=yes --test=/usr/share/doc/sysbench/tests/db/oltp.lua --init-rng=on --oltp_index_updates=10 --oltp_non_index_updates=10 --oltp_distinct_ranges=15 --oltp_order_ranges=15 --oltp_tables_count=10 --num-threads=10 --oltp_table_size=10000 --mysql-db=test --mysql-user=root  --db-driver=mysql --mysql-socket=${SOCKET} run" >sysbench_run
  fi
elif [ "$(sysbench --version | cut -d ' ' -f2 | grep -oe '[0-9]\.[0-9]')" == "1.0" ]; then
  if [ "${VERSION_INFO}" == "8.0" ]; then
    if [ -r "${PWD}/bin/mariadb" ]; then
      echo "${PWD}/bin/mariadb -uroot --socket=${SOCKET} -e \"CREATE USER IF NOT EXISTS sysbench_user@'%' identified with mysql_native_password by 'test';GRANT ALL ON *.* TO sysbench_user@'%'\" 2>&1" >sysbench_prepare
    else
      echo "${PWD}/bin/mysql -uroot --socket=${SOCKET} -e \"CREATE USER IF NOT EXISTS sysbench_user@'%' identified with mysql_native_password by 'test';GRANT ALL ON *.* TO sysbench_user@'%'\" 2>&1" >sysbench_prepare
    fi
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
  for i in $(seq 1 "${NR_OF_NODES}"); do
     echo -e "echo 'Starts sysbench oltp run on socket ${SOCKET} for 5 minutes.'\n$(cat gal_sysbench_run) &" >> gal_sysbench_multi_master_run
     sed -i "s|-time=50|-time=300|g" gal_sysbench_multi_master_run
     sed -i "s|${SOCKET}|${PWD}/node${i}/node${i}_socket.sock|g" gal_sysbench_multi_master_run
  done
  sed -i "s|${SOCKET}|${PWD}/node1/node1_socket.sock|g" gal_sysbench_prepare gal_sysbench_run
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
  sed -i 's|^MULTI_THREADS=[0-9]\+|MULTI_THREADS=5|' ./reducer_new_text_string.sh
  sed -i 's|^KNOWN_BUGS_LOC=[^#]\+|KNOWN_BUGS_LOC="${HOME}/mariadb-qa/known_bugs.strings"   |' ./reducer_new_text_string.sh
  sed -i 's|^FORCE_SKIPV=0|FORCE_SKIPV=1|' ./reducer_new_text_string.sh
  sed -i 's|^USE_NEW_TEXT_STRING=0|USE_NEW_TEXT_STRING=1|' ./reducer_new_text_string.sh
  sed -i 's|^STAGE1_LINES=[^#]\+|STAGE1_LINES=13  |' ./reducer_new_text_string.sh
  sed -i 's|^SCAN_FOR_NEW_BUGS=[^#]\+|SCAN_FOR_NEW_BUGS=1   |' ./reducer_new_text_string.sh
  sed -i 's|^NEW_BUGS_COPY_DIR=[^#]\+|NEW_BUGS_COPY_DIR="/data/NEWBUGS"   |' ./reducer_new_text_string.sh
  sed -i 's|^TEXT_STRING_LOC=[^#]\+|TEXT_STRING_LOC="${HOME}/mariadb-qa/new_text_string.sh"   |' ./reducer_new_text_string.sh
  sed -i 's|^PQUERY_LOC=[^#]\+|PQUERY_LOC="${HOME}/mariadb-qa/pquery/pquery2-md"   |' ./reducer_new_text_string.sh
  # ------------------- ./reducer_errorlog.sh creation
  cp ./reducer_new_text_string.sh ./reducer_errorlog.sh
  sed -i 's|^USE_NEW_TEXT_STRING=1|USE_NEW_TEXT_STRING=0|' ./reducer_errorlog.sh
  sed -i 's|^SCAN_FOR_NEW_BUGS=1|SCAN_FOR_NEW_BUGS=0|' ./reducer_errorlog.sh  # SCAN_FOR_NEW_BUGS=1 Not supported yet when using USE_NEW_TEXT_STRING=0
  # ------------------- ./reducer_errorlog_pquery.sh creation
  sed 's|^USE_PQUERY=0|USE_PQUERY=1|' ./reducer_errorlog.sh > ./reducer_errorlog_pquery.sh
  # ------------------- ./reducer_hang.sh creation
  sed 's|^MODE=[0-9]|MODE=0|;s|TIMEOUT_CHECK=[0-9]*|TIMEOUT_CHECK=150|;s|MULTI_THREADS=[0-9]*|MULTI_THREADS=3|;s|^STAGE1_LINES=[0-9]\+|STAGE1_LINES=13|' ./reducer_errorlog.sh > ./reducer_hang.sh  # Timeout of 150s is a best guess, it may need to be higher. 3 Threads is plenty as we need to wait for the timeout in any case (unless sporadic)
  # ------------------- ./reducer_hang_pquery.sh creation
  sed 's|^USE_PQUERY=0|USE_PQUERY=1|' ./reducer_hang.sh > ./reducer_hang_pquery.sh
  # ------------------- ./reducer_new_text_string_pquery.sh creation
  sed 's|^USE_PQUERY=0|USE_PQUERY=1|' ./reducer_new_text_string.sh > ./reducer_new_text_string_pquery.sh
  # ------------------- ./reducer_fireworks.sh creation
  cp ${SCRIPT_PWD}/reducer.sh ./reducer_fireworks.sh
  mkdir -p ./FIREWORKS-BUGS
  sed -i "s|^NEW_BUGS_COPY_DIR=[^#]\+|NEW_BUGS_COPY_DIR=\"${PWD}/FIREWORKS-BUGS\"   |"  ./reducer_fireworks.sh
  sed -i 's|^KNOWN_BUGS_LOC=[^#]\+|KNOWN_BUGS_LOC="${HOME}/mariadb-qa/known_bugs.strings"   |' ./reducer_fireworks.sh
  sed -i 's|^TEXT_STRING_LOC=[^#]\+|TEXT_STRING_LOC="${HOME}/mariadb-qa/new_text_string.sh"   |' ./reducer_fireworks.sh
  sed -i 's|^PQUERY_LOC=[^#]\+|PQUERY_LOC="${HOME}/mariadb-qa/pquery/pquery2-md"   |' ./reducer_fireworks.sh
  sed -i 's|^FIREWORKS=0|FIREWORKS=1|' ./reducer_fireworks.sh
  sed -i 's|^MYEXTRA=.*|MYEXTRA="--no-defaults ${3}"|' ./reducer_fireworks.sh  # It is best not to add --sql_mode=... as this will significantly affect CLI replay attempts as the CLI by default does not set --sql_mode=... as normally defined in reducer.sh's MYEXTRA default (--sql_mode=ONLY_FULL_GROUP_BY). Reason: with either --sql_mode= or --sql_mode=--sql_mode=ONLY_FULL_GROUP_BY engine substituion (to the default storage engine, i.e. InnoDB or MyISAM in MTR) is enabled. Replays at the CLI would thus look significantly different by default (i.e. unless this option was passed and by default it is not)
fi

echo 'rm -f in.tmp' >fixin
echo 'if [ -r ./in.sql ]; then mv in.sql in.tmp; fi' >>fixin
echo 'echo "DROP DATABASE test;" > ./in.sql' >>fixin
echo 'echo "CREATE DATABASE test;" >> ./in.sql' >>fixin
echo 'echo "USE test;" >> ./in.sql' >>fixin
echo 'if [ -r ./in.tmp ]; then cat in.tmp >> in.sql; rm -f in.tmp; fi' >>fixin
echo "echo \"You may want to add  SET sql_mode='';  to the top of the in.sql file also, if the original run had it\"" >>fixin

echo "${SCRIPT_PWD}/stack.sh" >stack
if [ -d ./mysql-test ]; then
  echo "${SCRIPT_PWD}/stack.sh" >mysql-test/stack  # Stack for MTR observed issues
  chmod +x mysql-test/stack
fi
if [ -d ./mariadb-test ]; then
  echo "${SCRIPT_PWD}/stack.sh" >mariadb-test/stack  # Idem
  chmod +x mariadb-test/stack
fi

echo "if [ \$(ls data/*core* 2>/dev/null | wc -l) -eq 0 ]; then" >gdb
echo "  echo \"No core file found in data/*core* - exiting\"" >>gdb
echo "  exit 1" >>gdb
echo "elif [ \$(ls data/*core* 2>/dev/null | wc -l) -gt 1 ]; then" >>gdb
echo "  echo \"More then one core file found in data/*core* - exiting\"" >>gdb
echo "  exit 1" >>gdb
echo "else" >>gdb
echo "  if [ -r bin/mariadbd ]; then" >>gdb
echo "    gdb bin/mariadbd \$(ls data/*core*)" >>gdb
echo "  else" >>gdb
echo "    gdb bin/mysqld \$(ls data/*core*)" >>gdb
echo "  fi" >>gdb
echo "fi" >>gdb

if [[ $MDG -eq 1 ]]; then
  cp gdb gal_gdb
  sed -i "s|ls data/\*core\*|ls node1/\*core\*|g" gal_gdb
fi

# -- Replication setup (MD)
# The master, except for start_master (created to be able to add startup options and master port handling via master_setup.sql port replacement), does not get any special script as the regular ./stop, ./cl, ./kill etc script are used for the master
cp start start_master
cp start start_slave
cp stop stop_slave
cp kill kill_slave
cp wipe wipe_slave 
cp cl cl_slave
sed -i 's|\-\-server-id=[0-9]\+||g' start_master
sed -i 's|\-\-server-id=[0-9]\+||g' start_slave
sed -i 's|master.err|slave.err|g' start_slave cl_slave
sed -i 's|master.err|slave.err|g' kill_slave
sed -i 's|/start|/start_slave|g' wipe_slave
sed -i 's|/stop|/stop_slave|g' wipe_slave
# The DUMMY provision is to prevent /data/ volume references (like in /data/VARIOUS_BUILDS which contains '/data') from being overwritten: swap and swap back
sed -i 's|/data/|DUMMY|g;s|/data|/data_slave|g;s|DUMMY|/data/|g' start_slave
sed -i 's|/data/|DUMMY|g;s|/data|/data_slave|g;s|DUMMY|/data/|g' stop_slave
sed -i 's|/data/|DUMMY|g;s|/data|/data_slave|g;s|DUMMY|/data/|g' wipe_slave
sed -i 's|/kill|/kill_slave|g' stop_slave
sed -i 's|socket.sock|socket_slave.sock|g' start_slave
sed -i 's|socket.sock|socket_slave.sock|g' stop_slave
sed -i 's|socket.sock|socket_slave.sock|g' wipe_slave
sed -i 's|socket.sock|socket_slave.sock|g' cl_slave
sed -i "s|^MYEXTRA=\"[ ]*--no-defaults .*|#MYEXTRA=\" --no-defaults --gtid_strict_mode=1 --relay-log=relaylog --log_bin=binlog --binlog_format=ROW --log_bin_trust_function_creators=1 --max_connections=10000 --server_id=1\"\nMYEXTRA=\" --no-defaults --log_bin=binlog --binlog_format=ROW --max_connections=10000 --server_id=1\"  # Minimal master setup|" start_master
# Replaced --slave-parallel-mode=aggressive with --slave-parallel-mode=conservative, ref various discussions and MDEV's discussing [optimistic|aggressive]
sed -i "s|^MYEXTRA=\"[ ]*--no-defaults .*|# slave_transaction_retries: see #replication 12 Mar 24 discussion between AE/RV\n#MYEXTRA=\" --no-defaults --gtid_strict_mode=1 --relay-log=relaylog --slave-parallel-threads=11 --slave-parallel-mode=conservative --slave-parallel-max-queued=65536 --slave_transaction_retries=4294967295 --innodb_lock_wait_timeout=120 --slave_run_triggers_for_rbr=LOGGING --slave_skip_errors=ALL --max_connections=10000 --server_id=2\"\nMYEXTRA=\" --no-defaults --max_connections=10000 --server_id=2\"  # Minimal slave setup|" start_slave  # --slave_transaction_retries: set to max, default is 10, but with many threads this value is very easily reached leading to:
# [ERROR] Slave worker thread retried transaction 10 time(s) in vain, giving up. Consider raising the value of the slave_transaction_retries variable.
# [ERROR] Slave SQL: Deadlock found when trying to get lock; try restarting transaction, Gtid 0-1-416, Internal MariaDB error code: 1213
# [Warning] Slave: XAER_DUPID: The XID already exists Error_code: 1440
# [Warning] Slave: Deadlock found when trying to get lock; try restarting transaction Error_code: 1213
# [ERROR] Error running query, slave SQL thread aborted. Fix the problem, and restart the slave SQL thread with "SLAVE START". We stopped at log 'binlog.000001' position 8168482; GTID position '0-1-514'
# --innodb_lock_wait_timeout is increased from 50 to 120 for the same reason
sed -i 's%^PORT=$.*%PORT=$NEWPORT; sed -i "s|MASTER_PORT=[0-9]\\+|MASTER_PORT=${NEWPORT}|" slave_setup.sql%' start_master
echo "DELETE FROM mysql.user WHERE user='';" >master_setup.sql
echo "GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%' IDENTIFIED BY 'repl_pass'; FLUSH PRIVILEGES;" >>master_setup.sql
echo "#ALTER TABLE mysql.gtid_slave_pos ENGINE=InnoDB;  # sysbench_lua Testing" >>master_setup.sql
if [[ "${PWD}" == *"MS"* ]]; then
  echo "CHANGE MASTER TO MASTER_HOST='127.0.0.1', MASTER_PORT=00000, MASTER_USER='repl_user', MASTER_PASSWORD='repl_pass';" >slave_setup.sql  # The 00000 is a dummy entry, and any number will be replaced by start_master to the actual port in slave_setup.sql at master startup time
else
  echo "CHANGE MASTER TO MASTER_HOST='127.0.0.1', MASTER_PORT=00000, MASTER_USER='repl_user', MASTER_PASSWORD='repl_pass', MASTER_USE_GTID=slave_pos ;" >slave_setup.sql  # The 00000 is a dummy entry, and any number will be replaced by start_master to the actual port in slave_setup.sql at master startup time
fi
echo "START SLAVE;" >>slave_setup.sql
echo './stop_slave; ./stop' >stop_replication
echo './kill_slave; ./kill' >kill_replication
echo 'MYEXTRA_OPT="$*"' >start_replication
echo './kill_replication >/dev/null 2>&1' >>start_replication
echo 'rm -f socket.sock socket.sock.lock socket_slave.sock socket_slave.sock.lock; sync' >>start_replication
echo './wipe ${MYEXTRA_OPT}' >>start_replication
echo './wipe_slave ${MYEXTRA_OPT}' >>start_replication  # TODO: MYEXTRA_OPT handling may need work
echo './start_master ${MYEXTRA_OPT}' >>start_replication
echo 'rm -f mysql.out mysql_slave.out data*/core*' >>start_replication
if [ -r "${PWD}/bin/mariadb" ]; then
  echo "${PWD}/bin/mariadb -A -uroot -S${SOCKET} --force ${BINMODE}test < ${PWD}/master_setup.sql > ${PWD}/mysql.out 2>&1" >>start_replication
else
  echo "${PWD}/bin/mysql -A -uroot -S${SOCKET} --force ${BINMODE}test < ${PWD}/master_setup.sql > ${PWD}/mysql.out 2>&1" >>start_replication
fi
echo './start_slave ${MYEXTRA_OPT}' >>start_replication  # idem 
if [ -r "${PWD}/bin/mariadb" ]; then
  echo "${PWD}/bin/mariadb -A -uroot -S${SLAVE_SOCKET} --force ${BINMODE}test < ${PWD}/slave_setup.sql > ${PWD}/mysql_slave.out" >>start_replication
else
  echo "${PWD}/bin/mysql -A -uroot -S${SLAVE_SOCKET} --force ${BINMODE}test < ${PWD}/slave_setup.sql > ${PWD}/mysql_slave.out" >>start_replication
fi
echo 'sleep 2' >>start_replication
echo 'if [ -z "${SRNOCL}" ]; then ./cl; fi' >>start_replication

# -- MENT-1905/MDEV-31949 lua replication XA testing, also handy for other sysbench/XA/replication tests
rm -f sysbench_lua* MENT-1905*
if [ -r "${SCRIPT_PWD}/replication_xa_sysbench_1.lua" ]; then cp ${SCRIPT_PWD}/replication_xa_sysbench_1.lua .; fi
if [ -r "${SCRIPT_PWD}/replication_xa_sysbench_2.lua" ]; then cp ${SCRIPT_PWD}/replication_xa_sysbench_2.lua .; fi
if [ -r "${SCRIPT_PWD}/replication_xa_sysbench_3.lua" ]; then cp ${SCRIPT_PWD}/replication_xa_sysbench_3.lua .; fi
echo '# MENT-1905/MDEV-31949 lua replication XA testing, also handy for other sysbench/XA/replication tests' >sysbench_lua_1
echo 'sed -i "s|#ALTER TABLE mysql.gtid_slave_pos|ALTER TABLE mysql.gtid_slave_pos|" master_setup.sql' >>sysbench_lua_1
echo 'sed -i "s|^MYEXTRA|#MYEXTRA|" start_slave  # Disable the common MYEXTRA' >>sysbench_lua_1
echo 'sed -i "0,/MYEXTRA=.*slave-parallel-threads/{s|.*\(MYEXTRA=.*slave-parallel-threads.*\)|\1|}" start_slave  # Enable the first slave-parallel-threads MYEXTRA' >>sysbench_lua_1
echo 'sed -i "s|slave-parallel-threads=[0-9]\+|slave-parallel-threads=32|" start_slave' >>sysbench_lua_1
echo 'export SRNOCL=1' >>sysbench_lua_1
echo './start_replication' >>sysbench_lua_1
cp sysbench_lua_1 sysbench_lua_2
cp sysbench_lua_1 sysbench_lua_3
SYSB='sysbench --mysql-user=root --mysql-socket="${PWD}/socket.sock" --tables=1 --table_size=10000 --mysql-db=test --mysql-ignore-errors=1062,1213,1614,1205 --threads=3000 --time=0 ./replication_xa_sysbench_'
echo "${SYSB}1.lua prepare" >>sysbench_lua_1
echo "${SYSB}1.lua run &" >>sysbench_lua_1
echo "${SYSB}2.lua prepare" >>sysbench_lua_2
echo "${SYSB}2.lua run &" >>sysbench_lua_2
echo "${SYSB}3.lua prepare" >>sysbench_lua_3
echo "${SYSB}3.lua run &" >>sysbench_lua_3
SYSB=
echo 'sleep 1; ./cl' >>sysbench_lua_1
echo 'sleep 1; ./cl' >>sysbench_lua_2
echo 'sleep 1; ./cl' >>sysbench_lua_3
chmod +x sysbench_lua*

# -- Replication setup (old PS/MS)
#echo '#!/usr/bin/env bash' >repl_setup
#echo "REPL_TYPE=\$1" >>repl_setup
#echo "if [[ \"\$REPL_TYPE\" = \"MSR\" ]]; then" >>repl_setup
#echo "  NODES=2" >>repl_setup
#echo "else" >>repl_setup
#echo "  NODES=1" >>repl_setup
#echo "fi" >>repl_setup
#echo 'MYEXTRA=" --no-defaults --gtid_mode=ON --enforce_gtid_consistency=ON --log_slave_updates=ON --log_bin=binlog --binlog_format=ROW --master_info_repository=TABLE --relay_log_info_repository=TABLE"' >>repl_setup
#echo "RPORT=$(($RANDOM % 10000 + 10000))" >>repl_setup
#echo "echo \"\" > stop_repl" >>repl_setup
#echo "if ${PWD}/bin/mysqladmin -uroot -S$PWD/socket.sock ping > /dev/null 2>&1; then" >>repl_setup
#echo "  ${PWD}/bin/mysql -A -uroot -S${SOCKET}  -Bse\"create user repl@'%' identified by 'repl';\"" >>repl_setup
#echo "  ${PWD}/bin/mysql -A -uroot -S${SOCKET}  -Bse\"grant all on *.* to repl@'%'; flush privileges;\"" >>repl_setup
#echo "  MASTER_PORT=\$(\${PWD}/bin/mysql -A -uroot -S\${SOCKET}  -Bse\"select @@port\")" >>repl_setup
#echo "else" >>repl_setup
#echo "  echo \"ERROR! Master server is not started. Make sure to start master with GTID enabled. Terminating!\"" >>repl_setup
#echo "  exit 1" >>repl_setup
#echo "fi" >>repl_setup
#echo "for i in \`seq 1 \$NODES\`;do" >>repl_setup
#echo "  RBASE=\"\$(( RPORT + \$i ))\"" >>repl_setup
#echo "  if [[ \"\$REPL_TYPE\" = \"MSR\" ]]; then" >>repl_setup
#echo "    if [ \$i -eq 1 ]; then" >>repl_setup
#echo "      node=\"${PWD}/masternode2\"" >>repl_setup
#echo "    else" >>repl_setup
#echo "      node=\"${PWD}/slavenode\"" >>repl_setup
#echo "    fi" >>repl_setup
#echo "  else" >>repl_setup
#echo "    node=\"${PWD}/slavenode\"" >>repl_setup
#echo "  fi" >>repl_setup
#echo "  if [ ! -d \$node ]; then" >>repl_setup
#echo "    $INIT_TOOL ${INIT_OPT} --basedir=${PWD} --datadir=\${node} > ${PWD}/startup_node\$i.err 2>&1 | grep --binary-files=text -vEi '${FILTER_INIT_TEXT}'" >>repl_setup
#echo '    if [ "${?}" -eq 1 ]; then exit 1; fi' >>repl_setup
#echo '  fi' >>repl_setup
#echo "  $BIN  \${MYEXTRA} ${START_OPT} --basedir=${PWD} --tmpdir=\${node} --datadir=\${node} ${TOKUDB} ${ROCKSDB} --socket=\$node/socket.sock --port=\$RBASE --report-host=$ADDR --report-port=\$RBASE  --server-id=10\$i --log-error=\$node/mysql.err 2>&1 &" >>repl_setup
#echo "  for X in \$(seq 0 90); do if ${PWD}/bin/mysqladmin ping -uroot -S\$node/socket.sock > /dev/null 2>&1; then break; fi; sleep 0.25; done" >>repl_setup
#echo "  if [[ \"\$REPL_TYPE\" = \"MSR\" ]]; then" >>repl_setup
#echo "    if [ \$i -eq 1 ]; then" >>repl_setup
#echo "      ${PWD}/bin/mysql -A -uroot --socket=\$node/socket.sock  -Bse\"create user repl@'%' identified by 'repl';\"" >>repl_setup
#echo "      ${PWD}/bin/mysql -A -uroot --socket=\$node/socket.sock  -Bse\"grant all on *.* to repl@'%';flush privileges;\"" >>repl_setup
#echo "      echo -e \"${PWD}/bin/mysql -A -uroot -S\$node/socket.sock --prompt \\\"masternode2> \\\"\" > ${PWD}/masternode2_cl " >>repl_setup
#echo "    else" >>repl_setup
#echo "      echo -e \"${PWD}/bin/mysql -A -uroot -S\$node/socket.sock --prompt \\\"slavenode> \\\"\" > ${PWD}/\slavenode_cl " >>repl_setup
#echo "    fi" >>repl_setup
#echo "  else" >>repl_setup
#echo "    echo -e \"${PWD}/bin/mysql -A -uroot -S\$node/socket.sock --prompt \\\"slavenode> \\\"\" > ${PWD}/\slavenode_cl " >>repl_setup
#echo "  fi" >>repl_setup
#echo "  echo \"${PWD}/bin/mysqladmin -uroot -S\$node/socket.sock shutdown\" >> stop_repl" >>repl_setup
#echo "  echo \"echo 'Server on socket \$node/socket.sock with datadir \$node halted'\" >> stop_repl" >>repl_setup
#echo "  if [[ \"\$REPL_TYPE\" = \"MSR\" ]]; then" >>repl_setup
#echo "    if [ \$i -eq 2 ]; then" >>repl_setup
#echo "      MASTER_PORT2=\$(${PWD}/bin/mysql -A -uroot -S${PWD}/masternode2/socket.sock  -Bse\"SELECT @@port\")" >>repl_setup
#if [ "${VERSION_INFO}" == "8.0" ]; then
#  echo "      ${PWD}/bin/mysql -A -uroot -S\$node/socket.sock  -Bse\"CHANGE MASTER TO MASTER_HOST='127.0.0.1',MASTER_PORT=\$MASTER_PORT, MASTER_USER='repl',MASTER_PASSWORD='repl',MASTER_AUTO_POSITION=1,GET_MASTER_PUBLIC_KEY=1 FOR CHANNEL 'master1';\"" >>repl_setup
#  echo "      ${PWD}/bin/mysql -A -uroot -S\$node/socket.sock  -Bse\"CHANGE MASTER TO MASTER_HOST='127.0.0.1',MASTER_PORT=\$MASTER_PORT2, MASTER_USER='repl',MASTER_PASSWORD='repl',MASTER_AUTO_POSITION=1,GET_MASTER_PUBLIC_KEY=1 FOR CHANNEL 'master2';\"" >>repl_setup
#else
#  echo "      ${PWD}/bin/mysql -A -uroot -S\$node/socket.sock  -Bse\"CHANGE MASTER TO MASTER_HOST='127.0.0.1',MASTER_PORT=\$MASTER_PORT, MASTER_USER='repl',MASTER_PASSWORD='repl',MASTER_AUTO_POSITION=1 FOR CHANNEL 'master1';\"" >>repl_setup
#  echo "      ${PWD}/bin/mysql -A -uroot -S\$node/socket.sock  -Bse\"CHANGE MASTER TO MASTER_HOST='127.0.0.1',MASTER_PORT=\$MASTER_PORT2, MASTER_USER='repl',MASTER_PASSWORD='repl',MASTER_AUTO_POSITION=1 FOR CHANNEL 'master2';\"" >>repl_setup
#fi
#echo "      ${PWD}/bin/mysql -A -uroot -S\$node/socket.sock  -Bse\"START SLAVE;\"" >>repl_setup
#echo "    fi" >>repl_setup
#echo "  else" >>repl_setup
#if [ "${VERSION_INFO}" == "8.0" ]; then
#  echo "    ${PWD}/bin/mysql -A -uroot -S\$node/socket.sock  -Bse\"CHANGE MASTER TO MASTER_HOST='127.0.0.1',MASTER_PORT=\$MASTER_PORT, MASTER_USER='repl',MASTER_PASSWORD='repl',MASTER_AUTO_POSITION=1,GET_MASTER_PUBLIC_KEY=1;START SLAVE;\"" >>repl_setup
#else
#  echo "    ${PWD}/bin/mysql -A -uroot -S\$node/socket.sock  -Bse\"CHANGE MASTER TO MASTER_HOST='127.0.0.1',MASTER_PORT=\$MASTER_PORT, MASTER_USER='repl',MASTER_PASSWORD='repl',MASTER_AUTO_POSITION=1;START SLAVE;\"" >>repl_setup
#fi
#echo "  fi" >>repl_setup
#echo "done" >>repl_setup
#echo "if [[ \"\$REPL_TYPE\" = \"MSR\" ]]; then" >>repl_setup
#echo "  chmod +x  masternode2_cl slavenode_cl stop_repl" >>repl_setup
#echo "else" >>repl_setup
#echo "  chmod +x  slavenode_cl stop_repl" >>repl_setup
#echo "fi" >>repl_setup

if [ ! -r ./in.sql ]; then touch ./in.sql; fi  # Make new empty file if does not exist yet
echo './all --sql_mode=' >sqlmode
echo './all --log_bin' >binlog
echo 'MYEXTRA_OPT="$*"' >all
echo "./kill >/dev/null 2>&1;./kill_replication >/dev/null 2>&1;rm -f socket.sock socket.sock.lock;sync;./wipe \${MYEXTRA_OPT};./start \${MYEXTRA_OPT};./cl" >>all
ln -s ./all ./a 2>/dev/null
echo 'MYEXTRA_OPT="$*"' >all_stbe
echo "./all --early-plugin-load=keyring_file.so --keyring_file_data=keyring --innodb_sys_tablespace_encrypt=ON \${MYEXTRA_OPT}" >>all_stbe # './all_stbe' is './all' with system tablespace encryption
echo 'MYEXTRA_OPT="$*"' >all_no_cl
echo "./kill >/dev/null 2>&1;rm -f socket.sock socket.sock.lock;sync;./wipe \${MYEXTRA_OPT};./start \${MYEXTRA_OPT}" >>all_no_cl
echo 'MYEXTRA_OPT="$*"' >all_no_cl_rr
echo "./kill >/dev/null 2>&1;rm -f socket.sock socket.sock.lock;sync;./wipe \${MYEXTRA_OPT};./start_rr \${MYEXTRA_OPT};sleep 10" >>all_no_cl_rr
echo 'MYEXTRA_OPT="$*"' >all_rr
echo "./kill >/dev/null 2>&1;rm -f socket.sock socket.sock.lock;sync;./wipe \${MYEXTRA_OPT};./start_rr \${MYEXTRA_OPT};sleep 10;./cl" >>all_rr
echo "echo '1/4th sec memory snapshots, for the mysqld in this directory, logged to memory.txt'; rm -f memory.txt; echo '    PID %MEM   RSS    VSZ COMMAND'; while :; do if [ \"\$(ps -ef | grep 'port=${PORT}' | grep -v grep)\" ]; then ps --sort -rss -eo pid,pmem,rss,vsz,comm | grep \"\$(ps -ef | grep 'port=${PORT}' | grep -v grep | head -n1 | awk '{print \$2}')\" | tee -a memory.txt ; sleep 0.25; else sleep 0.05; fi; done" >memory_use_trace
if [ -r ${SCRIPT_PWD}/startup_scripts/multitest ]; then cp ${SCRIPT_PWD}/startup_scripts/multitest .; fi
if [ -r ${SCRIPT_PWD}/stress.sh ]; then cp ${SCRIPT_PWD}/stress.sh .; fi
chmod +x insert_start_marker insert_stop_marker start* stop* setup cl* test test_* kill* init wipe* sqlmode binlog all all_stbe all_no_cl all_rr all_no_cl_rr sysbench_prepare sysbench_run sysbench_measure gdb stack fixin loopin myrocks_tokudb_init repl_setup *multirun* reducer_* clean_failing_queries memory_use_trace 2>/dev/null

# Adding galera all script
echo './gal --sql_mode=' >gal_sqlmode
echo './gal --log_bin' >gal_binlog
echo 'MYEXTRA_OPT="$*"' >gal
echo "./gal_kill >/dev/null 2>&1;rm -f node*/*socket.sock node*/*socket.sock.lock;sync;./gal_wipe \${MYEXTRA_OPT};./gal_start \${MYEXTRA_OPT};./gal_cl" >>gal
ln -s ./gal ./g 2>/dev/null
echo 'MYEXTRA_OPT="$*"' >gal_stbe
echo "./gal --early-plugin-load=keyring_file.so --keyring_file_data=keyring --innodb_sys_tablespace_encrypt=ON \${MYEXTRA_OPT}" >>gal_stbe # './gal_stbe' is './gal' with system tablespace encryption
echo 'MYEXTRA_OPT="$*"' >gal_no_cl
echo "./gal_kill >/dev/null 2>&1;rm -f node*/*socket.sock node*/*socket.sock.lock;sync;./gal_wipe \${MYEXTRA_OPT};./gal_start \${MYEXTRA_OPT}" >>gal_no_cl
echo 'MYEXTRA_OPT="$*"' >gal_rr
echo "./gal_kill >/dev/null 2>&1;rm -f node*/*socket.sock node*/*socket.sock.lock;sync;./gal_wipe \${MYEXTRA_OPT};./gal_start_rr \${MYEXTRA_OPT};./gal_cl" >>gal_rr
chmod +x gal gal_cl gal_sqlmode gal_binlog gal_stbe gal_no_cl gal_rr gal_gdb gal_test gal_test_pquery gal_cl_noprompt_nobinary gal_cl_noprompt gal_multirun gal_multirun_pquery gal_sysbench_measure gal_sysbench_prepare gal_sysbench_run gal_sysbench_multi_master_run 2>/dev/null
echo "Setting up server with default directories"

if [[ $MDG -eq 0 ]]; then
  ./stop >/dev/null 2>&1
  ./kill_replication >/dev/null 2>&1  # Will also kill master in case ./stop failed
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
