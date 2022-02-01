#!/bin/bash
# Created by Ramesh Sivaraman, MariaDB
# This script is for MariaDB Galera SST test

# Bash internal variables
set -o nounset    # no undefined variables

#Global variables
declare SCRIPT_PWD=$(cd "$(dirname $0)" && pwd)
declare WORKDIR=${PWD}
# Internal variables: DO NOT CHANGE!
declare -i NR_OF_NODES=2
declare -i SERVER_START_TIMEOUT=200
declare SUSER="root"
declare SPASS=""
declare SST=""
declare SYSBENCH_OPTIONS
declare ENCRYPTION
declare CONF=""
declare VERIFY_ENCRYPTION_OPT=""
declare SST_LOST_FOUND_TEST=""
declare CONF_TEST=""

# Dispay script usage details
usage () {
  echo "Usage:"
  echo "./mariadb-galera-sst-test.sh  --basedir=PATH"
  echo ""
  echo "Options:"
  echo "  -b, --basedir=PATH                                 Specify MariaDB Galera base directory, mention full path"
  echo "  -s, --sst-test=[all|mysql_dump|rsync|mariabackup]  Specify SST method for cluster data transfer"
}

# Check if we have a functional getopt(1)
if ! getopt --test
  then
  go_out="$(getopt --options=w:b:s:h --longoptions=basedir:,sst-test:,help \
  --name="$(basename "$0")" -- "$@")"
  test $? -eq 0 || exit 1
  eval set -- "$go_out"
fi

if [[ $go_out == " --" ]];then
  usage
  exit 1
fi

for arg
do
  case "$arg" in
    -- ) shift; break;;
    -b | --basedir )
    export BASEDIR="$2"
    if [[ ! -d "$BASEDIR" ]]; then
      echo "ERROR: Basedir ($BASEDIR) directory does not exist. Terminating!"
      exit 1
    fi
    shift 2
    ;;
    -s | --sst-test )
    SST="$2"
    shift 2
    if [[ "$SST" != "mysql_dump" ]] && [[ "$SST" != "rsync" ]] && [[ "$SST" != "mariabackup" ]] && [[ "$SST" != "all" ]]; then
      echo "ERROR: Invalid --sst-test passed:"
      echo "  Please choose any of these sst-test options: 'mysql_dump', 'rsync' or 'mariabackup'"
      exit 1
    fi
    ;;
    -h | --help )
    usage
    exit 0
    ;;
  esac
done

echo "Initiating SST test"
echo "Work directory: ${WORKDIR}"
echo "Log directory: ${WORKDIR}/logs"

#######################
# SST run sanity check
#######################
sst_sanity(){
  # Copy SSL certiticates to work directory
  if [[ ! -d "${WORKDIR}/cert" ]]; then
    if [[ -d "${SCRIPT_PWD}/cert" ]]; then
      cp -r ${SCRIPT_PWD}/cert  ${WORKDIR}/
    else
      echo "WARNING: SSL certificate directory does not exist. SST will encryption will be skipped"
    fi
  fi

  # Checking pv binary location
  if [[ ! -e $(which pv 2> /dev/null) ]]; then
    echo "The pv binary was not found. Please install the pv package."
    exit 1
  fi
  # Checking stunnel binary location
  if [[ ! -e $(which stunnel 2> /dev/null) ]]; then
    echo "The stunnel binary was not found. Please install the stunnel package."
    exit 1
  fi
}

sst_sanity

if [[ -z "$SST" ]]; then
  declare SST="all"
fi

# Create directory to log the script output.
rm -rf $WORKDIR/logs
mkdir -p $WORKDIR/logs

#Check MariaDB Galera binary
if [ ! -r ${BASEDIR}/bin/mysqld ]; then
  echo "Assert: there is no (script readable) mysqld binary at ${BASEDIR}/bin/mysqld ?"
  exit 1
fi

#############################
# Store mariadb version info
#############################
declare MYSQL_VERSION=$(${BASEDIR}/bin/mysqld --version | grep --binary-files=text -i 'MariaDB' | grep -oe '10\.[1-6]' | head -n1)
export PATH="$BASEDIR/bin:$PATH"

rm -rf ${WORKDIR}/logs/mariadb-galera-sst-test.log &> /dev/null

#function to store the script output
echoit(){
  if [ "${WORKDIR}" != "" ]; then
    echo "[$(date +'%T')] $1" >> ${WORKDIR}/logs/mariadb-galera-sst-test.log;
  fi
}

sysbench_run(){
  TEST_TYPE="${1-}"
  if [ "$(sysbench --version | grep -oe '[0-9]\.[0-9]')" == "0.5" ]; then
    if [ "$TEST_TYPE" == "load_data" ];then
      SYSBENCH_OPTIONS="--test=/usr/share/doc/sysbench/tests/db/parallel_prepare.lua --oltp-table-size=1000 --oltp_tables_count=10 --mysql-db=test --mysql-user=root  --num-threads=10 --db-driver=mysql"
    elif [ "$TEST_TYPE" == "oltp" ];then
      SYSBENCH_OPTIONS="--test=/usr/share/doc/sysbench/tests/db/oltp.lua --oltp-table-size=1000 --oltp_tables_count=10 --max-time=200 --report-interval=1 --max-requests=1870000000 --mysql-db=test --mysql-user=root  --num-threads=10 --db-driver=mysql"
    fi
  elif [ "$(sysbench --version | grep -oe '[0-9]\.[0-9]')" == "1.0" ]; then
    if [ "$TEST_TYPE" == "load_data" ];then
      SYSBENCH_OPTIONS="/usr/share/sysbench/oltp_insert.lua --table-size=1000 --tables=10 --mysql-db=test --mysql-user=root  --threads=10 --db-driver=mysql"
    elif [ "$TEST_TYPE" == "oltp" ];then
      SYSBENCH_OPTIONS="/usr/share/sysbench/oltp_insert.lua --table-size=1000 --tables=10 --mysql-db=test --mysql-user=root  --threads=10 --time=200 --report-interval=1 --events=1870000000 --db-driver=mysql"
    fi
  fi
}


cd ${WORKDIR} || true

#######################################
# Setting seeddb creation configuration
#######################################
if [ "${MYSQL_VERSION}" == "10.4" -o "${MYSQL_VERSION}" == "10.5" -o "${MYSQL_VERSION}" == "10.6" ]; then
  INIT_TOOL="${BASEDIR}/scripts/mariadb-install-db"
  INIT_OPT="--no-defaults --force --auth-root-authentication-method=normal "
  START_OPT="--core-file --core"
elif [ "${MYSQL_VERSION}" == "10.1" -o "${MYSQL_VERSION}" == "10.2" -o "${MYSQL_VERSION}" == "10.3" ]; then
  INIT_TOOL="${BASEDIR}/scripts/mysql_install_db"
  INIT_OPT="--no-defaults --force "
  START_OPT="--core"
fi

#######################################
# select empty port to run galera node
#######################################
init_empty_port(){
  NEWPORT=
  # Choose a random port number in 3307-5500 range, check if free, increase if needbe
  NEWPORT=$[ 3307 + ( ${RANDOM} % 5500 ) ]
  while :; do
    ISPORTFREE="$(netstat -an | tr '\t' ' ' | grep -E --binary-files=text "[ :]${NEWPORT} " | wc -l)"
    ISPORTFREE2="$(ps -ef | grep --binary-files=text "port=${NEWPORT}" | grep --binary-files=text -v 'grep')"
    if [ "${ISPORTFREE}" -ge 1 -o ! -z "${ISPORTFREE2}" ]; then
      NEWPORT=$[ ${NEWPORT} + 100 ]  # +100 to avoid 'clusters of ports'
    else
      break
    fi
  done
}

#######################################
# Check Galera node startup status
#######################################
mdg_startup_status() {
  SOCKET=${1-}
  for X in $(seq 0 ${SERVER_START_TIMEOUT}); do
    sleep 1
    if ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} ping > /dev/null 2>&1; then
      break
    fi
    if [[ $X -eq $((SERVER_START_TIMEOUT - 1)) ]]; then
      echo "Assert: Could not start cluster node on socket: $SOCKET. Check the error log to get more info"
      exit 1
    fi
  done
}

############################################
# Prepare galera node startup configuration
############################################
prepare_galera_startup() {
  ENCRYPTION="${1-}"
  MYINIT=${2-}

  # Creating default my-template.cnf file
  echo "[mysqld]" > my-template.cnf
  echo "basedir=${BASEDIR}" >> my-template.cnf
  echo "wsrep-debug=1" >> my-template.cnf
  echo "innodb_file_per_table" >> my-template.cnf
  echo "innodb_autoinc_lock_mode=2" >> my-template.cnf
  echo "wsrep-provider=${BASEDIR}/lib/libgalera_smm.so" >> my-template.cnf
  echo "wsrep_sst_auth=$SUSER:$SPASS" >> my-template.cnf
  echo "wsrep_sst_method=$SST" >> my-template.cnf
  echo "binlog_format=ROW" >> my-template.cnf
  echo "log-output=none" >> my-template.cnf
  echo "wsrep_on=1" >> my-template.cnf
  echo "wsrep_slave_threads=2" >> my-template.cnf

  # clean existing mysqld process
  ps -ef | grep 'mysqld' | grep -v grep | grep "$(basename "${WORKDIR}")" | awk '{print $2}' | xargs kill -9 > /dev/null 2>&1 || true
  TEST_START_TIME=$(date '+%s')
  ADDR="127.0.0.1"

  unset MDG_PORTS
  unset MDG_LADDRS
  MDG_PORTS=""
  MDG_LADDRS=""
  for i in $(seq 1 ${NR_OF_NODES}); do
    init_empty_port
    RBASE=$NEWPORT
    NEWPORT=
    init_empty_port
    LADDR="127.0.0.1:${NEWPORT}"
    NEWPORT=
    MDG_PORTS+=("$RBASE")
    MDG_LADDRS+=("$LADDR")
    node="${WORKDIR}/node${i}"
    rm -rf ${WORKDIR}/node${i}
    mkdir -p $WORKDIR/tmp${i}
    cp my-template.cnf ${WORKDIR}/n${i}.cnf
    sed -i "2i server-id=10${i}" ${WORKDIR}/n${i}.cnf
    sed -i "2i wsrep_node_incoming_address=$ADDR" ${WORKDIR}/n${i}.cnf
    sed -i "2i wsrep_node_address=$ADDR" ${WORKDIR}/n${i}.cnf
    sed -i "2i log-error=${WORKDIR}/logs/node${i}.err" ${WORKDIR}/n${i}.cnf
    sed -i "2i port=$RBASE" ${WORKDIR}/n${i}.cnf
    sed -i "2i datadir=$node" ${WORKDIR}/n${i}.cnf
    sed -i "2i socket=$node/node${i}_socket.sock" ${WORKDIR}/n${i}.cnf
    sed -i "2i tmpdir=${WORKDIR}/tmp${i}" ${WORKDIR}/n${i}.cnf
    sed -i "2i wsrep_provider_options=\"gmcast.listen_addr=tcp://$LADDR;\"" ${WORKDIR}/n${i}.cnf
    echoit "${INIT_TOOL} ${INIT_OPT} --basedir=${BASEDIR} --datadir=$node ${MYINIT} > ${WORKDIR}/logs/startup_node${i}.err 2>&1"
    ${INIT_TOOL} ${INIT_OPT} --basedir=${BASEDIR} --datadir=$node ${MYINIT} > ${WORKDIR}/logs/startup_node${i}.err 2>&1
  done
  WSREP_CLUSTER_ADDRESS=$(printf "%s,"  "${MDG_LADDRS[@]}")
  for i in $(seq 1 ${NR_OF_NODES}); do
    sed -i "2i wsrep_cluster_address=gcomm://${WSREP_CLUSTER_ADDRESS:1}" ${WORKDIR}/n${i}.cnf
    if [[ "${ENCRYPTION}" == "crypt" ]]; then
      cat "${SCRIPT_PWD}"/conf/encryption.cnf >> ${WORKDIR}/n${j}.cnf
    fi
  done
}

sample_data_load(){
  declare TABLE_OPTS=('PAGE_COMPRESSED=1' 'ROW_FORMAT=COMPRESSED' 'ROW_FORMAT=REDUNDANT' 'ROW_FORMAT=COMPACT')
  declare -i a=1
  for TABLE_OPT in "${TABLE_OPTS[@]}"; do
    a=$((a + 1))
    ${BASEDIR}/bin/mysql -uroot -S${WORKDIR}/node1/node1_socket.sock -e "CREATE TABLE test.t${a} (f1 CHAR(255)) ENGINE=InnoDB ${TABLE_OPT};" > /dev/null 2>&1
    for i in $(seq 1 100); do
      STR=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 100 | head -n 1)
      ${BASEDIR}/bin/mysql -uroot -S${WORKDIR}/node1/node1_socket.sock -e "INSERT INTO test.t${a}(f1) VALUES('${STR}');" > /dev/null 2>&1
    done
  done
}

sample_crypt_data_load(){
  declare TABLE_OPTS=('PAGE_COMPRESSED=1 ENCRYPTED=YES' 'ROW_FORMAT=COMPRESSED ENCRYPTED=YES' 'ROW_FORMAT=REDUNDANT ENCRYPTED=YES' 'ROW_FORMAT=COMPACT ENCRYPTED=YES')
  declare -i a=1
  for TABLE_OPT in "${TABLE_OPTS[@]}"; do
    a=$((a + 1))
    ${BASEDIR}/bin/mysql -uroot -S${WORKDIR}/node1/node1_socket.sock -e "CREATE TABLE test.en_t${a} (f1 CHAR(255)) ENGINE=InnoDB ${TABLE_OPT};" > /dev/null 2>&1
    for i in $(seq 1 100); do
      STR=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 100 | head -n 1)
      ${BASEDIR}/bin/mysql -uroot -S${WORKDIR}/node1/node1_socket.sock -e "INSERT INTO test.en_t${a}(f1) VALUES('${STR}');" > /dev/null 2>&1
    done
  done
}

lost_found_test(){
  LOST_FOUND_DB_1="\`lost+found\`"
  LOST_FOUND_DB_2="\`#mysql50#not_lost+found\`"
  ${BASEDIR}/bin/mysql -uroot -S${WORKDIR}/node1/node1_socket.sock -e "CREATE DATABASE IF NOT EXISTS ${LOST_FOUND_DB_1};CREATE DATABASE IF NOT EXISTS ${LOST_FOUND_DB_2};" > /dev/null 2>&1
  for i in $(seq 1 10); do
    ${BASEDIR}/bin/mysql -uroot -S${WORKDIR}/node1/node1_socket.sock -e "CREATE TABLE ${LOST_FOUND_DB_1}.t${i} (f1 CHAR(255)) ENGINE=InnoDB;CREATE TABLE ${LOST_FOUND_DB_2}.t${i} (f1 CHAR(255)) ENGINE=InnoDB;" > /dev/null 2>&1
    for j in $(seq 1 50); do
      STR=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 100 | head -n 1)
      ${BASEDIR}/bin/mysql -uroot -S${WORKDIR}/node1/node1_socket.sock -e "INSERT INTO ${LOST_FOUND_DB_1}.t${i}(f1) VALUES('${STR}');INSERT INTO ${LOST_FOUND_DB_2}.t${i}(f1) VALUES('${STR}');" > /dev/null 2>&1
    done
  done
}

#####################
# Start Galera node
#####################
start_galera_nodes(){
  MYEXTRA=${1-}
  for j in $(seq 1 ${NR_OF_NODES}); do
    if [ -n "${CONF_TEST}" ]; then
     cat ${SCRIPT_PWD}/conf/${CONF}.cnf-node${j} >> ${WORKDIR}/n${j}.cnf
    fi
    if [[ -n ${VERIFY_ENCRYPTION_OPT} ]]; then
      sed -i  "0,/^[ \t]*tkey[ \t]*=.*$/s|^[ \t]*tkey[ \t]*=.*$|tkey=${WORKDIR}/cert/server-key.pem|" ${WORKDIR}/n${j}.cnf
      sed -i  "0,/^[ \t]*tcert[ \t]*=.*$/s|^[ \t]*tcert[ \t]*=.*$|tcert=${WORKDIR}/cert/server-cert.pem|" ${WORKDIR}/n${j}.cnf
    fi
    if [ ${j} -eq 1 ]; then
      echoit "${BASEDIR}/bin/mysqld --defaults-file=${WORKDIR}/n${j}.cnf ${MYEXTRA} --wsrep-new-cluster > ${WORKDIR}/logs/node${j}.err 2>&1 &"
      ${BASEDIR}/bin/mysqld --defaults-file=${WORKDIR}/n${j}.cnf ${MYEXTRA} --wsrep-new-cluster > ${WORKDIR}/logs/node${j}.err 2>&1 &
      mdg_startup_status "${WORKDIR}/node${j}/node${j}_socket.sock"
      echoit "${BASEDIR}/bin/mysql -uroot -S${WORKDIR}/node${j}/node${j}_socket.sock -e 'create database if not exists test' > /dev/null 2>&1"
      ${BASEDIR}/bin/mysql -uroot -S${WORKDIR}/node${j}/node${j}_socket.sock -e "create database if not exists test" > /dev/null 2>&1
      if [[ -z "${SST_LOST_FOUND_TEST}" ]]; then
        sysbench_run load_data
        echoit "sysbench $SYSBENCH_OPTIONS --mysql-socket=${WORKDIR}/node${j}/node${j}_socket.sock prepare > ${WORKDIR}/logs/sysbench_load.log 2>&1"
        sysbench $SYSBENCH_OPTIONS --mysql-socket=${WORKDIR}/node${j}/node${j}_socket.sock prepare > ${WORKDIR}/logs/sysbench_load.log 2>&1
        sample_data_load
        if [[ "${ENCRYPTION}" == "crypt" ]]; then
          sample_crypt_data_load
        fi
      else
        lost_found_test
      fi
    else
      echoit "${BASEDIR}/bin/mysqld --defaults-file=${WORKDIR}/n${j}.cnf ${MYEXTRA} > ${WORKDIR}/logs/node${j}.err 2>&1 &"
      ${BASEDIR}/bin/mysqld --defaults-file=${WORKDIR}/n${j}.cnf ${MYEXTRA} > ${WORKDIR}/logs/node${j}.err 2>&1 &
      mdg_startup_status "${WORKDIR}/node${j}/node${j}_socket.sock"
    fi
  done
}

####################
# Verify SST status
####################
check_sst_status(){
  if [[ "${SST}" == "mariabackup" ]]; then
    WSREP_LOCAL_STATE_UUID=$(${BASEDIR}/bin/mysql -uroot -S${WORKDIR}/node1/node1_socket.sock -Ns -e "SHOW STATUS LIKE 'wsrep_local_state_uuid'"| awk {'print $2'})
    WSREP_LAST_COMMITED=$(${BASEDIR}/bin/mysql -uroot -S${WORKDIR}/node1/node1_socket.sock -Ns -e "SHOW STATUS LIKE 'wsrep_last_committed'"| awk {'print $2'})

    ## thanks to PXC sst test script: xb_galera_sst.sh
    if [[ "${WSREP_LOCAL_STATE_UUID}" == "$(sed  -re 's/:.+$//' ${WORKDIR}/node2/xtrabackup_galera_info_SST)" && "${WSREP_LAST_COMMITED}" == "$(sed  -re 's/^.+://' ${WORKDIR}/node2/xtrabackup_galera_info_SST)" ]]; then
	    echo "SST successful"
    else
	    echo "SST failed"
	    exit 1
    fi
  fi
}

##############################
# Save SST test run artifacts
##############################
save_artifacts(){
  COMMENT=${1-}
  if [[ -n "${CONF_TEST}" ]]; then
    TESTCASE="${CONF}_cnf-node_${COMMENT}"
  elif [[ -n "${SST_LOST_FOUND_TEST}" ]]; then
    TESTCASE="${SST_LOST_FOUND_TEST}_${COMMENT}"
  else
    TESTCASE="inno_page_size_${size}_${COMMENT}"
  fi
  rm -rf ${WORKDIR}/logs/${SST}_${TESTCASE}/ > /dev/null 2>&1
  mkdir ${WORKDIR}/logs/${SST}_${TESTCASE}/
  cp ${WORKDIR}/logs/node1.err ${WORKDIR}/logs/${SST}_${TESTCASE}/
  cp ${WORKDIR}/logs/node2.err ${WORKDIR}/logs/${SST}_${TESTCASE}/
  cp ${WORKDIR}/logs/mariadb-galera-sst-test.log ${WORKDIR}/logs/${SST}_${TESTCASE}/
  if [[ -z "${SST_LOST_FOUND_TEST}" ]]; then
   cp ${WORKDIR}/logs/sysbench_load.log ${WORKDIR}/logs/${SST}_${TESTCASE}/
  fi
  echoit "SST ${SST} logs saved in ${WORKDIR}/logs/${SST}_${TESTCASE}/"
}

########################
# Verify table checksum
########################
validate_table_checksum(){
  IS_ENCRYPTION="${1}"
  if [[ -n "${SST_LOST_FOUND_TEST}" ]]; then
    # Get checkdum from lost+found DB for lost found SST test
    NODE1_MD5SUM=$(${BASEDIR}/bin/mysql -uroot -S${WORKDIR}/node1/node1_socket.sock -e "select * from ${LOST_FOUND_DB_1}.t1;" | md5sum | cut -d" " -f1)
    NODE2_MD5SUM=$(${BASEDIR}/bin/mysql -uroot -S${WORKDIR}/node2/node2_socket.sock -e "select * from ${LOST_FOUND_DB_1}.t1;" | md5sum | cut -d" " -f1)
  else
    # Get checkdum from sysbench table
    NODE1_MD5SUM=$(${BASEDIR}/bin/mysql -uroot -S${WORKDIR}/node1/node1_socket.sock -e "select * from test.sbtest1;" | md5sum | cut -d" " -f1)
    NODE2_MD5SUM=$(${BASEDIR}/bin/mysql -uroot -S${WORKDIR}/node2/node2_socket.sock -e "select * from test.sbtest1;" | md5sum | cut -d" " -f1)
  fi
  if [[ "${NODE1_MD5SUM}" != "${NODE2_MD5SUM}" ]];then
    echo "Integrity verification failed: found: ${NODE1_MD5SUM} expected: ${NODE2_MD5SUM}"
    exit 1
  fi
  if [[ -n "${CONF_TEST}" ]]; then
    TEST_NAME="galera_sst_${SST} - $(head -1 ${SCRIPT_PWD}/conf/${CONF}.cnf-node1) - ${IS_ENCRYPTION}"
  elif [[ -n "${SST_LOST_FOUND_TEST}" ]]; then
    TEST_NAME="galera_sst_${SST} - # lost+found test - ${IS_ENCRYPTION}"
  else
    TEST_NAME="galera_sst_${SST} - # innodb_page_size(${size}),${IS_ENCRYPTION}"
  fi
  TEST_TIME=$(($(date '+%s') - TEST_START_TIME))
  if [ "$NODE1_MD5SUM" == "$NODE2_MD5SUM" ]; then
    printf "%-90s  %-10s %-10s\n" "$TEST_NAME" "[passed]" "$TEST_TIME"
  else
    printf "%-90s  %-10s %-10s\n" "$TEST_NAME" "[failed]" "$TEST_TIME"
  fi
}

########################
# Shutdown galera nodes
########################
shutdown_nodes(){
  for i in $(seq ${NR_OF_NODES} -1 1); do
    ${BASEDIR}/bin/mysqladmin -uroot -S${WORKDIR}/node${i}/node${i}_socket.sock shutdown > /dev/null 2>&1
  done
}

########################
# Initiate SST test run
########################
sst_run(){
    INNO_PAGE_SIZE=${1:+--innodb-page-size="$1"}
    ## Non encryption run
    prepare_galera_startup "clear" "${INNO_PAGE_SIZE}"
    start_galera_nodes "${INNO_PAGE_SIZE}"
    save_artifacts "clear"
    if [[ "${SST}" == "mysqldump" ]]; then
      # Pausing 10 sec to sync node2 after mysqldump SST"
      sleep 10
    fi
    validate_table_checksum "clear"
    shutdown_nodes
    ## Encryption run
    prepare_galera_startup "crypt" "${INNO_PAGE_SIZE}"
    start_galera_nodes "--plugin-load-add=file_key_management.so --loose-file-key-management --loose-file-key-management-filename=${SCRIPT_PWD}/conf/keys.txt --file-key-management-encryption-algorithm=aes_cbc ${INNO_PAGE_SIZE}"
    save_artifacts "crypt"
    if [[ "${SST}" == "mysqldump" ]]; then
      # Pausing 10 sec to sync node2 after mysqldump SST"
      sleep 10
    fi
    validate_table_checksum "crypt"
    shutdown_nodes
}

##################
# Invoke SST test
##################
invoke_sst_run(){
  SST=${1-}
  printf "%-112s\n" | tr " " "="
  printf "%-90s  %-10s %-10s\n" "TEST" "RESULT" "TIME(s)"
  printf "%-112s\n" | tr " " "-"

  ###################################
  # Test SST using innodb_page_size
  ###################################
  declare inno_page_size=( 16K 8K 4K )
  for size in "${inno_page_size[@]}"; do
    sst_run "${size}"
  done

  ############################################
  # Test SST using sst/mariadb/mysqld options
  ############################################
  CONF_ARRAY=()
  while IFS='' read -r line; do CONF_ARRAY+=("$line"); done < <(find ${SCRIPT_PWD}/conf/ -type f -exec basename {} \; 2>/dev/null | grep conf*.*node | cut -d'.' -f1 | sort | uniq)
  if [[ "${SST}" == "mariabackup" ]]; then
    CONF_TEST="multiple_config_test"
    for CONF in "${CONF_ARRAY[@]}"; do
      BACKUP_LOCK=$(grep -o no-backup ${SCRIPT_PWD}/conf/${CONF}.cnf-node* 2>1)
      if [[ -n ${BACKUP_LOCK} ]]; then
        if [[ ${MYSQL_VERSION} != "10.6" ]]; then
          continue
        fi
      fi
      VERIFY_ENCRYPTION_OPT=$(grep -o encrypt ${SCRIPT_PWD}/conf/${CONF}.cnf-node* 2>1)
      if [[ -n ${VERIFY_ENCRYPTION_OPT} ]]; then
        if [[ ! -f ${WORKDIR}/cert/server-cert.pem ]]; then
          echo "SSL certificates not found: Skipping SST encryption test"
          continue
        fi
      fi
      sst_run
    done
    CONF_TEST=''
    # Run lost+found SST test
    SST_LOST_FOUND_TEST="lost_found_test"
    sst_run
    SST_LOST_FOUND_TEST=""
  elif [[ "${SST}" == "rsync" ]]; then
    CONF_TEST="encrypt_config_test"
    CONF=conf3
    sst_run
    CONF_TEST=""
  fi
  printf "%-112s\n" | tr " " "="
}

if [[ "${SST}" == "all" ]]; then
  invoke_sst_run "rsync"
  invoke_sst_run "mariabackup"
  invoke_sst_run "mysqldump"
elif [[ "${SST}" == "rsync" ]]; then
  invoke_sst_run "rsync"
elif [[ "${SST}" == "mariabackup" ]]; then
  invoke_sst_run "mariabackup"
elif [[ "${SST}" == "mysql_dump" ]]; then
  invoke_sst_run "mysqldump"
fi
