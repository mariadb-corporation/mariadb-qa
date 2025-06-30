#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC  (PS Version, original, still available in old_files/ps-async-repl-test.sh)
# Updated by Roel Van de Paar, MariaDB      (MD Version, this script, md-replication-test.sh)

# This script tests replication features:
#   Master-Slave replication
#   Master-Master replication
#   Multi Source replication
#   Multi thread replication

# Bash internal configuration
set -o nounset    # no undefined variables

# Global variables
declare ADDR="127.0.0.1"
declare PORT=$[50000 + ( $RANDOM % ( 9999 ) ) ]
declare -i RPORT=$(( (RANDOM%21 + 10)*1000 ))
declare LADDR="$ADDR:$(( RPORT + 8 ))"
declare SUSER=root
declare SPASS=""
declare SBENCH="sysbench"
declare SCRIPT_PWD=$(cd "`dirname $0`" && pwd)
declare -i MD_START_TIMEOUT=60
declare WORKDIR=""
declare BUILD_NUMBER
declare ENGINE=""
declare KEYRING_PLUGIN=""
declare TESTCASE=""
declare ENCRYPTION=""
declare BINLOG_FORMAT=""
declare TC_ARRAY=""
declare ROOT_FS=""
declare SDURATION=""
declare TSIZE=""
declare NUMT=""
declare TCOUNT=""
declare MD_TAR=""
declare MD_BASEDIR=""
declare MID=""
declare SYSBENCH_OPTIONS=""
declare SYSBENCH_INSERT_PERCENTILE=""
declare SYSBENCH_DELETE_PERCENTILE=""
declare SYSBENCH_UPDATE_PERCENTILE=""
declare SYSBENCH_XAS_PERCENTILE=""
declare SYSBENCH_ADD_UNIQ_INDEX_PERCENTILE=""
declare SYSBENCH_ADD_INDEX_PERCENTILE=""

# Dispay script usage details
usage () {
  echo "Usage: [ options ]"
  echo "Options:"
  echo "  -d, --basedir                         Specify the basedirectory (e.g. /test/MD220623-mariadb-11.1.2-linux-x86_64-dbg)"
  echo "  -w, --workdir                         Specify work directory"
  echo "  -s, --storage-engine                  Specify mysql server storage engine"
  echo "  -b, --build-number                    Specify work build directory"
  echo "  -t, --testcase=<testcases|all>        Run only following comma-separated list of testcases"
  echo "                                          master_slave_test"
  echo "                                          master_multi_slave_test"
  echo "                                          master_master_test"
  echo "                                          msr_test"
  echo "                                          mtr_test"
  echo "                                        If you specify 'all', the script will execute all testcases"
  echo "  -e, --with-encryption                 Run the script with encryption feature"
  echo "  -f, --binlog-format                   Specify binlog_format"
  echo "  --sysbench-inserts-percentile         Specify sysbench insert percentile"
  echo "  --sysbench-deletes-percentile         Specify sysbench delete percentile"
  echo "  --sysbench-updates-percentile         Specify sysbench update percentile"
  echo "  --sysbench-xas-percentile             Specify sysbench XA percentile"
  echo "  --sysbench-add-index-percentile       Specify sysbench ADD INDEX percentile"
  echo "  --sysbench-add-uniq-index-percentile  Specify sysbench UNIQUE INDEX percentile"
}

# Check if we have a functional getopt(1)
if ! getopt --test
  then
  go_out="$(getopt --options=d:w:b:s:k:t:f:eh --longoptions=basedir:,workdir:,storage-engine:,build-number:,testcase:,with-encryption,binlog-format:,sysbench-inserts-percentile:,sysbench-deletes-percentile:,sysbench-updates-percentile:,sysbench-xas-percentile:,sysbench-add-index-percentile:,sysbench-add-uniq-index-percentile:,help \
  --name="$(basename "$0")" -- "$@")"
  test $? -eq 0 || exit 1
  eval set -- "$go_out"
fi

if [[ $go_out == " --" ]];then
  usage
  exit 1
fi

for arg do
  case "$arg" in
    -- ) shift; break;;
    -d | --basedir )
    MD_BASEDIR="$2"
    if [[ ! -d "$MD_BASEDIR" ]]; then
      echo "ERROR: Basedir ($MD_BASEDIR) directory does not exist. Terminating!"
      exit 1
    fi
    shift 2
    ;;
    -w | --workdir )
    WORKDIR="$2"
    if [[ ! -d "$WORKDIR" ]]; then
      echo "ERROR: Workdir ($WORKDIR) directory does not exist. Terminating!"
      exit 1
    fi
    shift 2
    ;;
    -b | --build-number )
    BUILD_NUMBER="$2"
    shift 2
    ;;
    -s | --storage-engine )
    ENGINE="$2"
    if [ "$ENGINE" != "innodb" ] && [ "$ENGINE" != "rocksdb" ] && [ "$ENGINE" != "tokudb" ]; then
      echo "ERROR: Invalid --storage-engine passed:"
      echo "  Please choose any of these storage engine options: innodb, rocksdb, tokudb"
      exit 1
    fi
    shift 2
    ;;
    -t | --testcase )
    TESTCASE="$2"
    shift 2
    ;;
    -f | --binlog-format )
    BINLOG_FORMAT="$2"
    shift 2
    ;;
    -e | --with-encryption )
    shift
    ENCRYPTION=1
    ;;
    --sysbench-inserts-percentile )
    SYSBENCH_INSERT_PERCENTILE="$2"
    shift 2
    ;;
    --sysbench-deletes-percentile )
    SYSBENCH_DELETE_PERCENTILE="$2"
    shift 2
    ;;
    --sysbench-updates-percentile )
    SYSBENCH_UPDATE_PERCENTILE="$2"
    shift 2
    ;;
    --sysbench-xas-percentile )
    SYSBENCH_XAS_PERCENTILE="$2"
    shift 2
    ;;
    --sysbench-add-index-percentile )
    SYSBENCH_ADD_INDEX_PERCENTILE="$2"
    shift 2
    ;;
    --sysbench-add-uniq-index-percentile )
    SYSBENCH_ADD_UNIQ_INDEX_PERCENTILE="$2"
    shift 2
    ;;
    -h | --help )
    usage
    exit 0
    ;;
  esac
done

#Format version string (thanks to wsrep_sst_xtrabackup-v2)
normalize_version(){
  local major=0
  local minor=0
  local patch=0

  # Only parses purely numeric version numbers, 1.2.3
  # Everything after the first three values are ignored
  if [[ $1 =~ ^([0-9]+)\.([0-9]+)\.?([0-9]*)([\.0-9])*$ ]]; then
    major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    patch=${BASH_REMATCH[3]}
  fi
  printf %02d%02d%02d $major $minor $patch
}

#Version comparison script (thanks to wsrep_sst_xtrabackup-v2)
check_for_version()
{
  local local_version_str="$( normalize_version $1 )"
  local required_version_str="$( normalize_version $2 )"

  if [[ "$local_version_str" < "$required_version_str" ]]; then
    return 1
  else
    return 0
  fi
}

# generic variables
if [[ -z "$WORKDIR" ]]; then
  WORKDIR=${PWD}
fi

if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="100"
fi

if [[ -z "$KEYRING_PLUGIN" ]]; then
  KEYRING_PLUGIN="file"
fi

if [[ ! -z "$TESTCASE" ]]; then
  IFS=', ' read -r -a TC_ARRAY <<< "$TESTCASE"
else
  TC_ARRAY=(all)
fi

ROOT_FS=$WORKDIR
cd $WORKDIR

if [ -z ${SDURATION} ]; then
  SDURATION=5
fi

if [ -z ${TSIZE} ]; then
  TSIZE=50
fi

if [ -z ${NUMT} ]; then
  NUMT=4
fi

if [ -z ${TCOUNT} ]; then
  TCOUNT=4
fi

if [ -z "$ENGINE" ]; then
  ENGINE="innodb"
fi

if [ -z "$BINLOG_FORMAT" ]; then
  BINLOG_FORMAT="MIXED"
fi

if [ -z "$SYSBENCH_INSERT_PERCENTILE" ]; then
  SYSBENCH_INSERT_PERCENTILE="20"
fi

if [ -z "$SYSBENCH_DELETE_PERCENTILE" ]; then
  SYSBENCH_DELETE_PERCENTILE="20"
fi

if [ -z "$SYSBENCH_UPDATE_PERCENTILE" ]; then
  SYSBENCH_UPDATE_PERCENTILE="20"
fi

if [ -z "$SYSBENCH_XAS_PERCENTILE" ]; then
  SYSBENCH_XAS_PERCENTILE="20"
fi

if [ -z "$SYSBENCH_ADD_INDEX_PERCENTILE" ]; then
  SYSBENCH_ADD_INDEX_PERCENTILE="5"
fi

if [ -z "$SYSBENCH_ADD_UNIQ_INDEX_PERCENTILE" ]; then
  SYSBENCH_ADD_UNIQ_INDEX_PERCENTILE="5"
fi

WORKDIR="${ROOT_FS}/$BUILD_NUMBER"
mkdir -p $WORKDIR/logs

echoit(){
  echo "[$(date +'%T')] $1"
  if [ "${WORKDIR}" != "" ]; then echo "[$(date +'%T')] $1" >> ${WORKDIR}/logs/md_async_test.log; fi
}

if [ "$ENCRYPTION" == 1 ];then
  if [[ "$KEYRING_PLUGIN" == "vault" ]]; then
    echoit "Setting up vault server"
    mkdir $WORKDIR/vault
    rm -rf $WORKDIR/vault/*
    killall vault
    echoit "********************************************************************************************"
    ${SCRIPT_PWD}/vault_test_setup.sh --workdir=$WORKDIR/vault --use-ssl
    echoit "********************************************************************************************"
  fi
fi

#Kill existing mysqld process
ps -ef | grep 'md[0-9].sock' | grep ${BUILD_NUMBER} | grep -v grep | awk '{print $2}' | xargs kill -9 >/dev/null 2>&1 || true
ps -ef | grep 'bkmdlave.sock' | grep ${BUILD_NUMBER} | grep -v grep | awk '{print $2}' | xargs kill -9 >/dev/null 2>&1 || true

cleanup(){
  cp -f ${MD_BASEDIR}/*.cnf $WORKDIR/logs
  if [ -d "$WORKDIR/vault" ]; then
    rm -f $WORKDIR/vault/vault
    cp -af $WORKDIR/vault $WORKDIR/logs
  fi
  echoit "Test logs are saved in ${ROOT_FS}/results-${BUILD_NUMBER}${TEST_DESCRIPTION:-}.tar.gz"
  tar czf ${ROOT_FS}/results-${BUILD_NUMBER}${TEST_DESCRIPTION:-}.tar.gz $WORKDIR/logs || true
}

trap cleanup EXIT KILL

# Find empty port
init_empty_port(){
  # Choose a random port number in 13-47K range, with triple check to confirm it is free
  NEWPORT=$((13001 + ((RANDOM << 15) | RANDOM) % 34001))  # 'RANDOM << 15': 1st $RANDOM is bit-shifted left by 15 places (i.e. * 2^15), '| RANDOM': Bitwise OR operation with a 2nd $RANDOM, which fills the lower 15 bits with a new random number. Result: 30-bit random integer
  DOUBLE_CHECK=0
  while :; do
    # Check if the port is free in four different ways
    ISPORTFREE1="$(netstat -an | tr '\t' ' ' | grep -E --binary-files=text "[ :]${NEWPORT} " | wc -l)"
    ISPORTFREE2="$(ps -ef | grep --binary-files=text "port=${NEWPORT}" | grep --binary-files=text -v 'grep')"
    ISPORTFREE3="$(grep --binary-files=text -o "port=${NEWPORT}" /test/*/start 2>/dev/null | wc -l)"
    ISPORTFREE4="$(netstat -tuln | grep :${NEWPORT})"
    if [ "${ISPORTFREE1}" -eq 0 -a -z "${ISPORTFREE2}" -a "${ISPORTFREE3}" -eq 0 -a -z "${ISPORTFREE4}" ]; then
      if [ "${DOUBLE_CHECK}" -eq 2 ]; then  # If true, then the port was triple checked (to avoid races) to be free
        break  # Suitable port number found
      else
        DOUBLE_CHECK=$[ ${DOUBLE_CHECK} + 1 ]
        sleep 0.0${RANDOM}  # Random Microsleep to further avoid races
        continue  # Loop the check
      fi
    else
      NEWPORT=$((13001 + ((RANDOM << 15) | RANDOM) % 34001))  # Try a new port
      DOUBLE_CHECK=0  # Reset the double check
      continue  # Recheck the new port
    fi
  done
}

function check_xb_dir(){
  #Check Percona XtraBackup binary tar ball
  pushd $ROOT_FS
  PXB_TAR=`ls -1td ?ercona-?trabackup* | grep ".tar" | head -n1`
  if [ ! -z $PXB_TAR ];then
    tar -xzf $PXB_TAR
    PXBBASE=`ls -1td ?ercona-?trabackup* | grep -v ".tar" | head -n1`
    export PATH="$ROOT_FS/$PXBBASE/bin:$PATH"
  else
    PXB_TAR=`ls -1td ?ercona-?trabackup* | grep ".tar" | head -n1`
    tar -xzf $PXB_TAR
    PXBBASE=`ls -1td ?ercona-?trabackup* | grep -v ".tar" | head -n1`
    export PATH="$ROOT_FS/$PXBBASE/bin:$PATH"
  fi
  PXBBASE="$ROOT_FS/$PXBBASE"
  popd
}

#Check sysbench
if [[ ! -e `which sysbench` ]];then
  echoit "Sysbench not found"
  exit 1
fi

if [ ! -r ${ROOT_FS}/oltp_mix_queries_repl.lua ] && [ ! -r ${ROOT_FS}/oltp_common_repl.lua ] ; then
  cp $SCRIPT_PWD/oltp_mix_queries_repl.lua ${ROOT_FS}/oltp_mix_queries_repl.lua
  cp $SCRIPT_PWD/oltp_common_repl.lua ${ROOT_FS}/oltp_common_repl.lua
fi


#sysbench command should compatible with versions 0.5 and 1.0
sysbench_run(){
  local TEST_TYPE="${1:-}"
  local DB="${2:-}"
  if [ "$(sysbench --version | cut -d ' ' -f2 | grep -oe '[0-9]\.[0-9]')" == "0.5" ]; then
    if [ "$TEST_TYPE" == "load_data" ];then
      SYSBENCH_OPTIONS="--test=/usr/share/doc/sysbench/tests/db/parallel_prepare.lua --oltp-table-size=$TSIZE --oltp_tables_count=$TCOUNT --mysql-db=$DB --mysql-storage-engine=$ENGINE --mysql-user=test_user --mysql-password=test  --num-threads=$NUMT --db-driver=mysql"
    elif [ "$TEST_TYPE" == "oltp" ];then
      SYSBENCH_OPTIONS="--test=/usr/share/doc/sysbench/tests/db/oltp.lua --oltp-table-size=$TSIZE --oltp_tables_count=$TCOUNT --max-time=$SDURATION --report-interval=1 --max-requests=1870000000 --mysql-db=$DB --mysql-user=test_user --mysql-password=test  --num-threads=$NUMT --db-driver=mysql"
    elif [ "$TEST_TYPE" == "insert_data" ];then
      SYSBENCH_OPTIONS="--test=/usr/share/doc/sysbench/tests/db/parallel_prepare.lua --oltp-table-size=$TSIZE --oltp_tables_count=$TCOUNT --max-time=10 --max-requests=1870000000 --mysql-db=$DB --mysql-user=test_user --mysql-password=test  --num-threads=$NUMT --db-driver=mysql"
    fi
  elif [ "$(sysbench --version | cut -d ' ' -f2 | grep -oe '[0-9]\.[0-9]')" == "1.0" ]; then
    if [ "$TEST_TYPE" == "load_data" ];then
      SYSBENCH_OPTIONS="${ROOT_FS}/oltp_mix_queries_repl.lua --table-size=$TSIZE --tables=$TCOUNT --mysql-storage-engine=$ENGINE --mysql-db=$DB --mysql-user=test_user --mysql-password=test  --threads=$NUMT --db-driver=mysql --mysql-ignore-errors=1062,1213,1614,1205"
    elif [ "$TEST_TYPE" == "oltp" ];then
      SYSBENCH_OPTIONS="${ROOT_FS}/oltp_mix_queries_repl.lua --table-size=$TSIZE --tables=$TCOUNT --mysql-db=$DB --mysql-user=test_user --mysql-password=test  --threads=$NUMT --time=$SDURATION --report-interval=1 --events=1870000000 --db-driver=mysql --db-ps-mode=disable --inserts=$SYSBENCH_INSERT_PERCENTILE --deletes=$SYSBENCH_DELETE_PERCENTILE --updates=$SYSBENCH_UPDATE_PERCENTILE --xas=$SYSBENCH_XAS_PERCENTILE --add_uniq_index=$SYSBENCH_ADD_UNIQ_INDEX_PERCENTILE --add_index=$SYSBENCH_ADD_INDEX_PERCENTILE --mysql-ignore-errors=1062,1213,1614,1205,1061,1091,1440"
    elif [ "$TEST_TYPE" == "insert_data" ];then
      SYSBENCH_OPTIONS="${ROOT_FS}/oltp_mix_queries_repl.lua --table-size=$TSIZE --tables=$TCOUNT --mysql-db=$DB --mysql-user=test_user --mysql-password=test  --threads=$NUMT --time=10 --events=1870000000 --db-driver=mysql --db-ps-mode=disable --inserts=$SYSBENCH_INSERT_PERCENTILE --deletes=$SYSBENCH_DELETE_PERCENTILE --updates=$SYSBENCH_UPDATE_PERCENTILE --xas=$SYSBENCH_XAS_PERCENTILE --add_uniq_index=$SYSBENCH_ADD_UNIQ_INDEX_PERCENTILE --add_index=$SYSBENCH_ADD_INDEX_PERCENTILE --mysql-ignore-errors=1062,1213,1614,1205,1061,1091,1440"
    fi
  fi
}

# Find mysqld binary
if [ -r ${MD_BASEDIR}/bin/mariadbd ]; then
  BIN=${MD_BASEDIR}/bin/mariadbd
elif [ -r ${MD_BASEDIR}/bin/mariadbd ]; then
  BIN=${MD_BASEDIR}/bin/mariadbd
else
  # Check if this is a debug build by checking if debug string is present in dirname
  if [[ ${MD_BASEDIR} = *debug* ]]; then
    if [ -r ${BASMD_BASEDIREDIR}/bin/mariadbd-debug ]; then
      BIN=${MD_BASEDIR}/bin/mariadbd-debug
    else
      echo "Assert: there is no (script readable) mysqld binary at ${MD_BASEDIR}/bin/mariadbd[-debug] ?"
      exit 1
    fi
  else
    echo "Assert: there is no (script readable) mysqld/mariadbd binary at ${MD_BASEDIR}/bin ?"
    exit 1
  fi
fi

# Get version specific options
MID=
if [ -r ${MD_BASEDIR}/scripts/mariadb-install-db ]; then MID="${MD_BASEDIR}/scripts/mariadb-install-db --no-defaults --force --auth-root-authentication-method=normal --basedir=${MD_BASEDIR}"; fi
if [ -r ${MD_BASEDIR}/scripts/mysql_install_db ]; then MID="${MD_BASEDIR}/scripts/mysql_install_db --no-defaults --force --auth-root-authentication-method=normal --basedir=${MD_BASEDIR} "; fi
declare MARIADB_VERSION=$(${BIN} --version | grep --binary-files=text -i 'MariaDB' | grep -oe '1[0-1]\.[0-9][0-9]*' | head -n1)

if [ -z "${MID}" ]; then
  echoit "Assert: Version was detected as ${MARIADB_VERSION}, yet ./scripts/mariadb-install-db nor ./scripts/mysql_install_db is present!"
  exit 1
fi

#Check command failure
check_cmd(){
  local MPID=${1:-}
  local ERROR_MSG=${2:-}
  if [ ${MPID} -ne 0 ]; then echoit "ERROR: $ERROR_MSG. Terminating!"; exit 1; fi
}

#Async replication test
function async_rpl_test(){
  local MYEXTRA_CHECK="${1:-}"
  function md_start(){
    local INTANCES="${1:-}"
    local EXTRA_OPT="${2:-}"
    if [ -z $INTANCES ];then
      INTANCES=1
    fi
    for i in `seq 1 $INTANCES`;do
      local STARTUP_OPTION="${2:-}"
      init_empty_port
      local RBASE1=${NEWPORT}
      NEWPORT=
      echoit "Starting independent MD node${i}.."
      local node="${WORKDIR}/mdnode${i}"
      rm -rf $node

      # Initialize database directory
      ${MID} --datadir=$node  > ${WORKDIR}/logs/mdnode${i}.err 2>&1 || exit 1;

      # Creating MD configuration file
      rm -rf ${MD_BASEDIR}/n${i}.cnf
      echo "[mysqld]" > ${MD_BASEDIR}/n${i}.cnf
      echo "basedir=${MD_BASEDIR}" >> ${MD_BASEDIR}/n${i}.cnf
      echo "datadir=$node" >> ${MD_BASEDIR}/n${i}.cnf
      echo "log-error=$WORKDIR/logs/mdnode${i}.err" >> ${MD_BASEDIR}/n${i}.cnf
      echo "socket=/tmp/md${i}.sock" >> ${MD_BASEDIR}/n${i}.cnf
      echo "port=$RBASE1" >> ${MD_BASEDIR}/n${i}.cnf
      echo "innodb_file_per_table" >> ${MD_BASEDIR}/n${i}.cnf
      echo "log-bin=mysql-bin" >> ${MD_BASEDIR}/n${i}.cnf
      if [ "$BINLOG_FORMAT" == "STATEMENT" ]; then
        echo "binlog-format=ROW" >> ${MD_BASEDIR}/n${i}.cnf
      elif [ "$BINLOG_FORMAT" == "ROW" ]; then
        echo "binlog-format=ROW" >> ${MD_BASEDIR}/n${i}.cnf
      else
        echo "binlog-format=ROW" >> ${MD_BASEDIR}/n${i}.cnf
      fi
      echo "log-slave-updates" >> ${MD_BASEDIR}/n${i}.cnf
      echo "relay_log_recovery=1" >> ${MD_BASEDIR}/n${i}.cnf
      echo "binlog-stmt-cache-size=1M">> ${MD_BASEDIR}/n${i}.cnf
      echo "sync-binlog=0">> ${MD_BASEDIR}/n${i}.cnf
      echo "master-info-repository=TABLE" >> ${MD_BASEDIR}/n${i}.cnf
      echo "relay-log-info-repository=TABLE" >> ${MD_BASEDIR}/n${i}.cnf
      echo "core-file" >> ${MD_BASEDIR}/n${i}.cnf
      echo "log-output=none" >> ${MD_BASEDIR}/n${i}.cnf
      echo "server-id=10${i}" >> ${MD_BASEDIR}/n${i}.cnf
      echo "gtid_domain_id=1${i}" >> ${MD_BASEDIR}/n${i}.cnf
      echo "report-host=$ADDR" >> ${MD_BASEDIR}/n${i}.cnf
      echo "report-port=$RBASE1" >> ${MD_BASEDIR}/n${i}.cnf
      if [ "$ENGINE" == "innodb" ]; then
        echo "default-storage-engine=innodb" >> ${MD_BASEDIR}/n${i}.cnf
      elif [ "$ENGINE" == "rocksdb" ]; then
        echo "plugin-load-add=rocksdb=ha_rocksdb.so" >> ${MD_BASEDIR}/n${i}.cnf
        echo "init-file=${SCRIPT_PWD}/MyRocks.sql" >> ${MD_BASEDIR}/n${i}.cnf
        echo "default-storage-engine=rocksdb" >> ${MD_BASEDIR}/n${i}.cnf
        echo "rocksdb-flush-log-at-trx-commit=2" >> ${MD_BASEDIR}/n${i}.cnf
        echo "rocksdb-wal-recovery-mode=2" >> ${MD_BASEDIR}/n${i}.cnf
      elif [ "$ENGINE" == "tokudb" ]; then
        echo "plugin-load-add=tokudb=ha_tokudb.so" >> ${MD_BASEDIR}/n${i}.cnf
        echo "tokudb-check-jemalloc=0" >> ${MD_BASEDIR}/n${i}.cnf
        echo "init-file=${SCRIPT_PWD}/TokuDB.sql" >> ${MD_BASEDIR}/n${i}.cnf
        echo "default-storage-engine=tokudb" >> ${MD_BASEDIR}/n${i}.cnf
      fi
      if [[ "$EXTRA_OPT" == "MTR" ]]; then
        echo "slave-parallel-workers=5" >> ${MD_BASEDIR}/n${i}.cnf
      fi
      if [[ "$MYEXTRA_CHECK" == "GTID" ]]; then
        echo "gtid_strict_mode=1" >> ${MD_BASEDIR}/n${i}.cnf
        echo "log_slave_updates=ON" >> ${MD_BASEDIR}/n${i}.cnf
      fi
      if [[ "$ENCRYPTION" == 1 ]];then
        if ! check_for_version $MARIADB_VERSION "8.0.16" ; then
          echo "encrypt_binlog=ON" >> ${MD_BASEDIR}/n${i}.cnf
          echo "innodb_encrypt_tables=OFF" >> ${MD_BASEDIR}/n${i}.cnf
        else
          echo "binlog_encryption=ON" >> ${MD_BASEDIR}/n${i}.cnf
          echo "default_table_encryption=OFF" >> ${MD_BASEDIR}/n${i}.cnf
        fi
        echo "master_verify_checksum=on" >> ${MD_BASEDIR}/n${i}.cnf
        echo "binlog_checksum=crc32" >> ${MD_BASEDIR}/n${i}.cnf.
        echo "innodb_temp_tablespace_encrypt=ON" >> ${MD_BASEDIR}/n${i}.cnf
        echo "encrypt-tmp-files=ON" >> ${MD_BASEDIR}/n${i}.cnf
        if [[ "$EXTRA_OPT" != "XB" ]]; then
          echo "innodb_sys_tablespace_encrypt=ON" >> ${MD_BASEDIR}/n${i}.cnf
        fi
  	    if [[ "$KEYRING_PLUGIN" == "file" ]]; then
          echo "early-plugin-load=keyring_file.so" >> ${MD_BASEDIR}/n${i}.cnf
          echo "keyring_file_data=$node/keyring" >> ${MD_BASEDIR}/n${i}.cnf
  	    elif [[ "$KEYRING_PLUGIN" == "vault" ]]; then
          echo "early-plugin-load=keyring_vault.so" >> ${MD_BASEDIR}/n${i}.cnf
          echo "keyring_vault_config=$WORKDIR/vault/keyring_vault_md.cnf" >> ${MD_BASEDIR}/n${i}.cnf
        fi
      fi

      ${MD_BASEDIR}/bin/mariadbd --defaults-file=${MD_BASEDIR}/n${i}.cnf > $WORKDIR/logs/mdnode${i}.err 2>&1 &

      for X in $(seq 0 ${MD_START_TIMEOUT}); do
        sleep 1
        if ${MD_BASEDIR}/bin/mariadb-admin -uroot -S/tmp/md${i}.sock ping > /dev/null 2>&1; then
          if [[ "$ENCRYPTION" == 1 ]];then
            if ! check_for_version $MARIADB_VERSION "8.0.16" ; then
              ${MD_BASEDIR}/bin/mariadb  -uroot -S/tmp/md${i}.sock -e"SET GLOBAL innodb_encrypt_tables=ON;"  > /dev/null 2>&1
            else
              ${MD_BASEDIR}/bin/mariadb  -uroot -S/tmp/md${i}.sock -e"SET GLOBAL default_table_encryption=ON;"  > /dev/null 2>&1
            fi
          fi
          sleep 5
          ${MD_BASEDIR}/bin/mariadb  -uroot -S/tmp/md${i}.sock -e"SET sql_log_bin=0; DELETE FROM mysql.user WHERE user='';FLUSH PRIVILEGES; SET sql_log_bin=1;"  > /dev/null 2>&1
          ${MD_BASEDIR}/bin/mariadb  -uroot -S/tmp/md${i}.sock -e"GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%' IDENTIFIED BY 'repl_pass'; FLUSH PRIVILEGES;"  > /dev/null 2>&1
          break
        fi
        if [ $X -eq ${MD_START_TIMEOUT} ]; then
          echoit "MD startup failed.."
          grep "ERROR" ${WORKDIR}/logs/mdnode${i}.err
          exit 1
          fi
      done
    done
  }

  function run_pt_table_checksum(){
    local DATABASES=${1:-}
    local SOCKET=${2:-}
    local CHANNEL=${3:-}

    local CHANNEL_OPT=""
    if [[ "${CHANNEL}" != "none" ]]; then
      CHANNEL_OPT="--channel=${CHANNEL}"
    fi
    pt-table-checksum S=${SOCKET},u=test_user,p=test -d ${DATABASES} --recursion-method hosts --no-check-binlog-format ${CHANNEL_OPT}
    check_cmd $?
  }

  function run_mysqlchecksum(){
    local DATABASE=${1:-}
    local MASTER_SOCKET=${2:-}
    local SLAVE_SOCKET=${3:-}
    local TABLES_MASTER=''
    #$(${MD_BASEDIR}/bin/mariadb -sN -uroot --socket=${MASTER_SOCKET} -e "SELECT GROUP_CONCAT(TABLE_NAME SEPARATOR \", \") FROM information_schema.tables WHERE table_schema = \"${DATABASE}\";")
    readarray -t TABLES_MASTER < <(${MD_BASEDIR}/bin/mariadb -sN -uroot --socket=${MASTER_SOCKET} -e "SELECT TABLE_NAME FROM information_schema.tables WHERE table_schema = \"${DATABASE}\";" 2>/dev/null)
    local TABLES_SLAVE=''
    #$(${MD_BASEDIR}/bin/mariadb -sN -uroot --socket=${SLAVE_SOCKET} -e "SELECT GROUP_CONCAT(TABLE_NAME SEPARATOR \", \") FROM information_schema.tables WHERE table_schema = \"${DATABASE}\";")
    readarray -t TABLES_SLAVE < <(${MD_BASEDIR}/bin/mariadb -sN -uroot --socket=${SLAVE_SOCKET} -e "SELECT TABLE_NAME FROM information_schema.tables WHERE table_schema = \"${DATABASE}\";" 2>/dev/null)
    for TABLE in "${TABLES_MASTER[@]}" ; do
      local CHECKSUM_MASTER=$(${MD_BASEDIR}/bin/mariadb -sN -uroot --socket=${MASTER_SOCKET} -e "checksum table ${TABLE};" -D ${DATABASE} 2>/dev/null)
      local CHECKSUM_SLAVE=$(${MD_BASEDIR}/bin/mariadb -sN -uroot --socket=${SLAVE_SOCKET} -e "checksum table ${TABLE};" -D ${DATABASE} 2>/dev/null)

      if [[ -z "${TABLE}" || -z "${CHECKSUM_MASTER}" || -z "${CHECKSUM_SLAVE}" ]]; then
        echoit "One of the checksum values is empty!"
        exit 1
      elif [[ "${CHECKSUM_MASTER}" != "${CHECKSUM_SLAVE}" ]]; then
        echoit "Difference noticed in the checksums! Master socket ${MASTER_SOCKET} - Slave socket "
        echoit "Source  checksum : ${CHECKSUM_MASTER}"
        echoit "Replica checksum : ${CHECKSUM_SLAVE}"
        exit 1
      fi
    done  
  }

  function invoke_slave(){
    local MASTER_SOCKET=${1:-}
    local SLAVE_SOCKET=${2:-}
    local REPL_STRING=${3:-}
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=$MASTER_SOCKET -e"FLUSH LOGS" 2>/dev/null
    local MASTER_LOG_FILE=`${MD_BASEDIR}/bin/mariadb -uroot --socket=$MASTER_SOCKET -Bse "show master logs" 2>/dev/null | awk '{print $1}' | tail -1`
    local MASTER_HOST_PORT=`${MD_BASEDIR}/bin/mariadb -uroot --socket=$MASTER_SOCKET -Bse "select @@port" 2>/dev/null`
    if [ "$MYEXTRA_CHECK" == "GTID" ]; then
      ${MD_BASEDIR}/bin/mariadb -uroot --socket=$SLAVE_SOCKET -e"CHANGE MASTER TO MASTER_HOST='${ADDR}', MASTER_PORT=$MASTER_HOST_PORT, MASTER_USER='repl_user', MASTER_PASSWORD='repl_pass', MASTER_USE_GTID=slave_pos $REPL_STRING" 2>/dev/null
    else
      ${MD_BASEDIR}/bin/mariadb -uroot --socket=$SLAVE_SOCKET -e"CHANGE MASTER TO MASTER_HOST='${ADDR}', MASTER_PORT=$MASTER_HOST_PORT, MASTER_USER='repl_user', MASTER_PASSWORD='repl_pass', MASTER_LOG_FILE='$MASTER_LOG_FILE', MASTER_LOG_POS=4 $REPL_STRING" 2>/dev/null
    fi
  }

  function slave_startup_check(){
    local SOCKET_FILE=${1:-}
    local SLAVE_STATUS=${2:-}
    local ERROR_LOG=${3:-}
    local MSR_SLAVE_STATUS=${4:-}
    local SB_MASTER=`${MD_BASEDIR}/bin/mariadb -uroot --socket=$SOCKET_FILE -Bse "show slave status $MSR_SLAVE_STATUS\G" 2>/dev/null | grep Seconds_Behind_Master | awk '{ print $2 }'`
    local COUNTER=0
    while ! [[  "$SB_MASTER" =~ ^[0-9]+$ ]]; do
      SB_MASTER=`${MD_BASEDIR}/bin/mariadb -uroot --socket=$SOCKET_FILE -Bse "show slave status $MSR_SLAVE_STATUS\G" 2>/dev/null | grep Seconds_Behind_Master | awk '{ print $2 }'`
      let COUNTER=COUNTER+1
      if [ $COUNTER -eq 10 ];then
        ${MD_BASEDIR}/bin/mariadb -uroot --socket=$SOCKET_FILE -Bse "show slave status $MSR_SLAVE_STATUS\G" 2>/dev/null > $SLAVE_STATUS
        echoit "Slave is not started yet. Please check error log and slave status : $ERROR_LOG, $SLAVE_STATUS"
        exit 1
      fi
      sleep 1;
    done
  }

  function slave_sync_check(){
    local SOCKET_FILE=${1:-}
    local SLAVE_STATUS=${2:-}
    local ERROR_LOG=${3:-}
    local SB_MASTER=`${MD_BASEDIR}/bin/mariadb -uroot --socket=$SOCKET_FILE -Bse "show slave status\G" 2>/dev/null | grep Seconds_Behind_Master | awk '{ print $2 }'`
    local COUNTER=0
    if [ "$SB_MASTER" = "NULL" ] || [ -z "$SB_MASTER" ]; then
      ${MD_BASEDIR}/bin/mariadb -uroot --socket=$SOCKET_FILE -Bse "show slave status\G" > $WORKDIR/logs/slave_status.log 2>/dev/null 
      echoit "Replica is not running. Please check error log and slave status : $ERROR_LOG,  $WORKDIR/logs/slave_status.log"
      exit 1
    fi
    while [[ $SB_MASTER -gt 0 ]]; do
      SB_MASTER=`${MD_BASEDIR}/bin/mariadb -uroot --socket=$SOCKET_FILE -Bse "show slave status\G" 2>/dev/null | grep Seconds_Behind_Master | awk '{ print $2 }'`
      if ! [[ "$SB_MASTER" =~ ^[0-9]+$ ]]; then
        ${MD_BASEDIR}/bin/mariadb -uroot --socket=$SOCKET_FILE -Bse "show slave status\G" 2>/dev/null > $WORKDIR/logs/slave_status_mdnode1.log
        echoit "Slave is not started yet. Please check error log and slave status : $WORKDIR/logs/mdnode1.err,  $WORKDIR/logs/slave_status_mdnode1.log"
        exit 1
      fi
      let COUNTER=COUNTER+1
      sleep 5
      if [ $COUNTER -eq 300 ]; then
        echoit "WARNING! Seems slave second behind master is not moving forward, skipping slave sync status check"
        break
      fi
    done
  }

  function create_test_user(){
    local SOCKET=${1:-}
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=$SOCKET -e "SET sql_log_bin=0; DELETE FROM mysql.user WHERE user=''; SET sql_log_bin=1; FLUSH PRIVILEGES;" 2>/dev/null
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=$SOCKET -e "CREATE USER IF NOT EXISTS test_user@'%' IDENTIFIED BY 'test';GRANT ALL ON *.* TO test_user@'%'; FLUSH PRIVILEGES;" 2>/dev/null
  }

  function async_sysbench_rw_run(){
    local DB=${1:-}
    local SOCKET=${2:-}
    #OLTP RW run
    echoit "OLTP RW run on database: $DB - socket: $SOCKET "
    sysbench_run oltp $DB
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=$SOCKET run  > $WORKDIR/logs/sysbench_rw.log 2>&1 &
    check_cmd $? "Failed to execute sysbench oltp read/write run ($SOCKET)"
  }

  function async_sysbench_insert_run(){
    local DATABASE_NAME=${1:-}
    local SOCKET=${2:-}
    echoit "Sysbench insert run (Database: $DATABASE_NAME)"
    sysbench_run insert_data $DATABASE_NAME
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=$SOCKET run  > $WORKDIR/logs/sysbench_insert.log 2>&1
    check_cmd $? "Failed to execute sysbench insert run ($SOCKET)"
  }

  function async_sysbench_load(){
    local DATABASE_NAME=${1:-}
    local SOCKET=${2:-}
    echoit "Sysbench Run: Prepare stage (Database: $DATABASE_NAME)"
    sysbench_run load_data $DATABASE_NAME
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=$SOCKET prepare  > $WORKDIR/logs/sysbench_prepare.txt 2>&1
    check_cmd $? "Failed to execute sysbench prepare stage ($SOCKET)"
  }

  function gt_test_run(){
    local DATABASE_NAME=${1:-}
    local SOCKET=${2:-}
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=$SOCKET $DATABASE_NAME -e "CREATE TABLESPACE ${DATABASE_NAME}_gen_ts1 ADD DATAFILE '${DATABASE_NAME}_gen_ts1.ibd' ENCRYPTION='Y'"  2>&1
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=$SOCKET $DATABASE_NAME -e "CREATE TABLE ${DATABASE_NAME}_gen_ts_tb1(id int auto_increment, str varchar(32), primary key(id)) TABLESPACE ${DATABASE_NAME}_gen_ts1" 2>&1
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=$SOCKET $DATABASE_NAME -e "CREATE TABLE ${DATABASE_NAME}_sys_ts_tb1(id int auto_increment, str varchar(32), primary key(id)) TABLESPACE=innodb_system" 2>&1
    local NUM_ROWS=$(shuf -i 50-100 -n 1)
    for i in `seq 1 $NUM_ROWS`; do
      local STRING=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
      ${MD_BASEDIR}/bin/mariadb -uroot --socket=$SOCKET $DATABASE_NAME -e "INSERT INTO ${DATABASE_NAME}_gen_ts_tb1 (str) VALUES ('${STRING}')" 2>/dev/null
      ${MD_BASEDIR}/bin/mariadb -uroot --socket=$SOCKET $DATABASE_NAME -e "INSERT INTO ${DATABASE_NAME}_sys_ts_tb1 (str) VALUES ('${STRING}')" 2>/dev/null
    done
  }

  function backup_database(){
    rm -rf ${WORKDIR}/backupdir ${WORKDIR}/bkmdlave; mkdir ${WORKDIR}/backupdir
    local SOCKET=${1:-}

    if [[ -z $ENCRYPTION ]]; then
      ${PXBBASE}/bin/xtrabackup --user=root --password='' --backup --target-dir=${WORKDIR}/backupdir/full -S${SOCKET} --datadir=${WORKDIR}/mdnode1 > $WORKDIR/logs/xb_backup.log 2>&1

      echoit "Prepare xtrabackup"
	  ${PXBBASE}/bin/xtrabackup --prepare --target-dir=${WORKDIR}/backupdir/full > $WORKDIR/logs/xb_prepare_backup.log 2>&1

    else
      if [[ "$KEYRING_PLUGIN" == "file" ]]; then
        ${PXBBASE}/bin/xtrabackup --user=root --password='' --backup --target-dir=${WORKDIR}/backupdir/full -S${SOCKET} --datadir=${WORKDIR}/mdnode1 --keyring-file-data=${WORKDIR}/mdnode1/keyring --xtrabackup-plugin-dir=${PXBBASE}/lib/plugin --generate-transition-key > $WORKDIR/logs/xb_backup.log 2>&1

        echoit "Prepare xtrabackup"
        ${PXBBASE}/bin/xtrabackup --prepare --target-dir=${WORKDIR}/backupdir/full --keyring-file-data=${WORKDIR}/mdnode1/keyring --xtrabackup-plugin-dir=${PXBBASE}/lib/plugin > $WORKDIR/logs/xb_prepare_backup.log 2>&1

      elif [[ "$KEYRING_PLUGIN" == "vault" ]]; then
        ${PXBBASE}/bin/xtrabackup --user=root --password='' --backup --target-dir=${WORKDIR}/backupdir/full -S${SOCKET} --datadir=${WORKDIR}/mdnode1 --xtrabackup-plugin-dir=${PXBBASE}/lib/plugin --keyring-vault-config=$WORKDIR/vault/keyring_vault_md.cnf --generate-transition-key > $WORKDIR/logs/xb_backup.log 2>&1

        echoit "Prepare xtrabackup"
        ${PXBBASE}/bin/xtrabackup --prepare --target-dir=${WORKDIR}/backupdir/full --xtrabackup-plugin-dir=${PXBBASE}/lib/plugin --keyring-vault-config=$WORKDIR/vault/keyring_vault_md.cnf > $WORKDIR/logs/xb_prepare_backup.log 2>&1
      fi
    fi
    echoit "Restore backup to slave datadir"
    rsync -avpP ${WORKDIR}/backupdir/full/ ${WORKDIR}/bkmdlave > $WORKDIR/logs/xb_restore_backup.log 2>&1
    if [ -f ${WORKDIR}/mdnode1/keyring ]; then
      cp ${WORKDIR}/mdnode1/keyring ${WORKDIR}/bkmdlave/
    fi
    cat ${MD_BASEDIR}/n1.cnf |
      sed "0,/^[ \t]*port[ \t]*=.*$/s|^[ \t]*port[ \t]*=.*$|port=3308|" |
      sed "0,/^[ \t]*report-port[ \t]*=.*$/s|^[ \t]*report-port[ \t]*=.*$|report-port=3308|" |
      sed "0,/^[ \t]*server-id[ \t]*=.*$/s|^[ \t]*server-id[ \t]*=.*$|server-id=200|" |
      sed "s|mdnode1|bkmdlave|g" |
      sed "0,/^[ \t]*socket[ \t]*=.*$/s|^[ \t]*socket[ \t]*=.*$|socket=/tmp/bkmdlave.sock|"  > ${MD_BASEDIR}/bkmdlave.cnf 2>&1

    ${MD_BASEDIR}/bin/mariadbd --defaults-file=${MD_BASEDIR}/bkmdlave.cnf > $WORKDIR/logs/bkmdlave.err 2>&1 &

    for X in $(seq 0 ${MD_START_TIMEOUT}); do
      sleep 1
      if ${MD_BASEDIR}/bin/mariadb-admin -uroot -S/tmp/bkmdlave.sock ping > /dev/null 2>&1; then
        break
      fi
      if [ $X -eq ${MD_START_TIMEOUT} ]; then
        echoit "MD Slave startup failed.."
        grep "ERROR" ${WORKDIR}/logs/bkmdlave.err
        exit 1
        fi
    done
  }

  function master_slave_test(){
    echoit "******************** $MYEXTRA_CHECK master slave test ************************"
    #MD server initialization
    echoit "MD server initialization"
    md_start 2

    invoke_slave "/tmp/md1.sock" "/tmp/md2.sock" ";START SLAVE;"

    echoit "Checking slave startup"
    slave_startup_check "/tmp/md2.sock" "$WORKDIR/logs/slave_status_mdnode2.log" "$WORKDIR/logs/mdnode2.err"

    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -e "drop database if exists sbtest_md_master;create database sbtest_md_master;" 2>/dev/null
	  create_test_user "/tmp/md1.sock"
    async_sysbench_load sbtest_md_master "/tmp/md1.sock"
    async_sysbench_rw_run sbtest_md_master "/tmp/md1.sock"
    sleep 5

    if [ "$ENCRYPTION" == 1 ];then
      echoit "Running general tablespace encryption test run"
      gt_test_run sbtest_md_master "/tmp/md1.sock"
      gt_test_run sbtest_md_slave "/tmp/md2.sock"
    fi
    sleep 5

    echoit "Checking slave sync status"
    slave_sync_check "/tmp/md2.sock" "$WORKDIR/logs/slave_status_mdnode2.log" "$WORKDIR/logs/mdnode2.err"
    sleep 10
    echoit "MD master slave: Checking data consistency"
    run_mysqlchecksum "sbtest_md_master" "/tmp/md1.sock" "/tmp/md2.sock"
    
    $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/md1.sock -u root shutdown
    $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/md2.sock -u root shutdown
  }

  function master_multi_slave_test(){
    echoit "********************$MYEXTRA_CHECK master multiple slave test ************************"
    #MD server initialization
    echoit "MD server initialization"
    md_start 4

    invoke_slave "/tmp/md1.sock" "/tmp/md2.sock" ";START SLAVE;"
    invoke_slave "/tmp/md1.sock" "/tmp/md3.sock" ";START SLAVE;"
    invoke_slave "/tmp/md1.sock" "/tmp/md4.sock" ";START SLAVE;"

    echoit "Checking slave startup"
    slave_startup_check "/tmp/md2.sock" "$WORKDIR/logs/slave_status_mdnode2.log" "$WORKDIR/logs/mdnode2.err"
    slave_startup_check "/tmp/md3.sock" "$WORKDIR/logs/slave_status_mdnode3.log" "$WORKDIR/logs/mdnode3.err"
    slave_startup_check "/tmp/md4.sock" "$WORKDIR/logs/slave_status_mdnode4.log" "$WORKDIR/logs/mdnode4.err"

    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -e"drop database if exists sbtest_md_master;create database sbtest_md_master;" 2>/dev/null
    create_test_user "/tmp/md1.sock"
    async_sysbench_load sbtest_md_master "/tmp/md1.sock"
    async_sysbench_rw_run sbtest_md_master "/tmp/md1.sock"
    
    sleep 5

    if [ "$ENCRYPTION" == 1 ];then
      echoit "Running general tablespace encryption test run"
      gt_test_run sbtest_md_master "/tmp/md1.sock"
      gt_test_run sbtest_md_slave_1 "/tmp/md2.sock"
      gt_test_run sbtest_md_slave_2 "/tmp/md3.sock"
      gt_test_run sbtest_md_slave_3 "/tmp/md4.sock"
    fi
    sleep 5

    echoit "Checking slave sync status"
    slave_sync_check "/tmp/md2.sock" "$WORKDIR/logs/slave_status_mdnode2.log" "$WORKDIR/logs/mdnode2.err"
    slave_sync_check "/tmp/md3.sock" "$WORKDIR/logs/slave_status_mdnode3.log" "$WORKDIR/logs/mdnode3.err"
    slave_sync_check "/tmp/md4.sock" "$WORKDIR/logs/slave_status_mdnode4.log" "$WORKDIR/logs/mdnode4.err"
    sleep 10
    echoit "MD master multi slave: Checking data consistency."
    run_mysqlchecksum "sbtest_md_master" "/tmp/md1.sock" "/tmp/md2.sock"
    run_mysqlchecksum "sbtest_md_master" "/tmp/md1.sock" "/tmp/md3.sock"
    run_mysqlchecksum "sbtest_md_master" "/tmp/md1.sock" "/tmp/md4.sock"

    $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/md1.sock -u root shutdown 2>/dev/null
    $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/md2.sock -u root shutdown 2>/dev/null
    $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/md3.sock -u root shutdown 2>/dev/null
    $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/md4.sock -u root shutdown 2>/dev/null
  }

  function master_master_test(){
    echoit "********************$MYEXTRA_CHECK master master test ************************"
    #MD server initialization
    echoit "MD server initialization"
    md_start 2

    invoke_slave "/tmp/md1.sock" "/tmp/md2.sock" ";START SLAVE;"
    invoke_slave "/tmp/md2.sock" "/tmp/md1.sock" ";START SLAVE;"

    echoit "Checking slave startup"
    slave_startup_check "/tmp/md1.sock" "$WORKDIR/logs/slave_status_mdnode1.log" "$WORKDIR/logs/mdnode1.err"
    slave_startup_check "/tmp/md2.sock" "$WORKDIR/logs/slave_status_mdnode2.log" "$WORKDIR/logs/mdnode2.err"

    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -e"drop database if exists sbtest_md_master_1;create database sbtest_md_master_1;" 2>/dev/null
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md2.sock -e"drop database if exists sbtest_md_master_2;create database sbtest_md_master_2;" 2>/dev/null
    create_test_user "/tmp/md1.sock"
    create_test_user "/tmp/md2.sock"
    async_sysbench_load sbtest_md_master_1 "/tmp/md1.sock"
    async_sysbench_load sbtest_md_master_2 "/tmp/md2.sock"

    async_sysbench_rw_run sbtest_md_master_1 "/tmp/md1.sock"
    async_sysbench_rw_run sbtest_md_master_2 "/tmp/md2.sock"

    sleep 5

    if [ "$ENCRYPTION" == 1 ];then
      echoit "Running general tablespace encryption test run"
      gt_test_run sbtest_md_master_1 "/tmp/md1.sock"
      gt_test_run sbtest_md_master_2 "/tmp/md2.sock"
    fi
    sleep 5

    echoit "Checking slave sync status"
    slave_sync_check "/tmp/md1.sock" "$WORKDIR/logs/slave_status_mdnode1.log" "$WORKDIR/logs/mdnode1.err"
    slave_sync_check "/tmp/md2.sock" "$WORKDIR/logs/slave_status_mdnode2.log" "$WORKDIR/logs/mdnode2.err"

    sleep 10
    echoit "MD master master: Checking data consistency."
    run_mysqlchecksum "sbtest_md_master_1" "/tmp/md1.sock" "/tmp/md2.sock"
    run_mysqlchecksum "sbtest_md_master_2" "/tmp/md1.sock" "/tmp/md2.sock"
    $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/md1.sock -u root shutdown 2>/dev/null
    $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/md2.sock -u root shutdown 2>/dev/null
  }

  function msr_test(){
    echo "********************$MYEXTRA_CHECK multi source replication test ************************"
    #MD server initialization
    echoit "MD server initialization"
    md_start 4
    invoke_slave "/tmp/md2.sock" "/tmp/md1.sock" "FOR CHANNEL 'master1';"
    invoke_slave "/tmp/md3.sock" "/tmp/md1.sock" "FOR CHANNEL 'master2';"
    invoke_slave "/tmp/md4.sock" "/tmp/md1.sock" "FOR CHANNEL 'master3';"

    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -e"START SLAVE FOR CHANNEL 'master1';" 2>/dev/null
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -e"START SLAVE FOR CHANNEL 'master2';" 2>/dev/null
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -e"START SLAVE FOR CHANNEL 'master3';" 2>/dev/null

    slave_startup_check "/tmp/md1.sock" "$WORKDIR/logs/slave_status_mdnode1.log" "$WORKDIR/logs/mdnode1.err" "for channel 'master1'"
    slave_startup_check "/tmp/md1.sock" "$WORKDIR/logs/slave_status_mdnode1.log" "$WORKDIR/logs/mdnode1.err" "for channel 'master2'"
    slave_startup_check "/tmp/md1.sock" "$WORKDIR/logs/slave_status_mdnode1.log" "$WORKDIR/logs/mdnode1.err" "for channel 'master3'"

    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md2.sock -e "drop database if exists msr_db_master1;create database msr_db_master1;" 2>/dev/null
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md3.sock -e "drop database if exists msr_db_master2;create database msr_db_master2;" 2>/dev/null
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md4.sock -e "drop database if exists msr_db_master3;create database msr_db_master3;" 2>/dev/null
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -e "drop database if exists msr_db_slave;create database msr_db_slave;" 2>/dev/null
	  create_test_user "/tmp/md2.sock"
	  create_test_user "/tmp/md3.sock"
	  create_test_user "/tmp/md4.sock"
    sleep 5
    # Sysbench dataload for MSR test
    async_sysbench_load msr_db_master1 "/tmp/md2.sock"
    async_sysbench_load msr_db_master2 "/tmp/md3.sock"
    async_sysbench_load msr_db_master3 "/tmp/md4.sock"

    sysbench_run oltp msr_db_master1
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=/tmp/md2.sock  run  > $WORKDIR/logs/sysbench_md_channel1_rw.log 2>&1 &
    check_cmd $? "Failed to execute sysbench read/write run (/tmp/md2.sock)"
    sysbench_run oltp msr_db_master2
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=/tmp/md3.sock  run  > $WORKDIR/logs/sysbench_md_channel2_rw.log 2>&1 &
    check_cmd $? "Failed to execute sysbench read/write run (/tmp/md3.sock)"
    sysbench_run oltp msr_db_master3
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=/tmp/md4.sock  run  > $WORKDIR/logs/sysbench_md_channel3_rw.log 2>&1
    check_cmd $? "Failed to execute sysbench read/write run (/tmp/md4.sock)"

	  sleep 5

    if [ "$ENCRYPTION" == 1 ];then
      echoit "Running general tablespace encryption test run"
      gt_test_run msr_db_master1 "/tmp/md2.sock"
      gt_test_run msr_db_master2 "/tmp/md3.sock"
      gt_test_run msr_db_master3 "/tmp/md4.sock"
    fi

    sleep 10
    local SB_CHANNEL1=`$MD_BASEDIR/bin/mariadb -uroot --socket=/tmp/md1.sock -Bse "show slave status for channel 'master1'\G" 2>/dev/null | grep Seconds_Behind_Master | awk '{ print $2 }'`
    local SB_CHANNEL2=`$MD_BASEDIR/bin/mariadb -uroot --socket=/tmp/md1.sock -Bse "show slave status for channel 'master2'\G" 2>/dev/null | grep Seconds_Behind_Master | awk '{ print $2 }'`
    local SB_CHANNEL3=`$MD_BASEDIR/bin/mariadb -uroot --socket=/tmp/md1.sock -Bse "show slave status for channel 'master3'\G" 2>/dev/null | grep Seconds_Behind_Master | awk '{ print $2 }'`

    if ! [[ "$SB_CHANNEL1" =~ ^[0-9]+$ ]]; then
      echo "Slave is not started yet. Please check error log : $WORKDIR/logs/mdnode1.err"
      exit 1
    fi
    if ! [[ "$SB_CHANNEL2" =~ ^[0-9]+$ ]]; then
      echo "Slave is not started yet. Please check error log : $WORKDIR/logs/mdnode1.err"
      exit 1
    fi
    if ! [[ "$SB_CHANNEL3" =~ ^[0-9]+$ ]]; then
      echo "Slave is not started yet. Please check error log : $WORKDIR/logs/mdnode1.err"
      exit 1
    fi

    while [ $SB_CHANNEL3 -gt 0 ]; do
      SB_CHANNEL3=`$MD_BASEDIR/bin/mariadb -uroot --socket=/tmp/md1.sock -Bse "show slave status for channel 'master3'\G" 2>/dev/null | grep Seconds_Behind_Master | awk '{ print $2 }'`
      if ! [[ "$SB_CHANNEL3" =~ ^[0-9]+$ ]]; then
        echo "Slave is not started yet. Please check error log : $WORKDIR/logs/mdnode1.err"
        exit 1
      fi
      sleep 5
    done
    sleep 10
    echoit "Multi source replication: Checking data consistency."

    run_mysqlchecksum "msr_db_master1" "/tmp/md2.sock" "/tmp/md1.sock"
    run_mysqlchecksum "msr_db_master2" "/tmp/md3.sock" "/tmp/md1.sock"
    run_mysqlchecksum "msr_db_master3" "/tmp/md4.sock" "/tmp/md1.sock"

    #Shutdown MD servers for MSR test
    $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/md1.sock -u root shutdown 2>/dev/null
    $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/md2.sock -u root shutdown 2>/dev/null
    $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/md3.sock -u root shutdown 2>/dev/null
    $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/md4.sock -u root shutdown 2>/dev/null
  }

  function mtr_test(){
    echo "********************$MYEXTRA_CHECK multi thread replication test ************************"
    #MD server initialization
    echoit "MD server initialization"
    md_start 2 "MTR"

    invoke_slave "/tmp/md1.sock" "/tmp/md2.sock" ";START SLAVE;"
    invoke_slave "/tmp/md2.sock" "/tmp/md1.sock" ";START SLAVE;"

    slave_startup_check "/tmp/md2.sock" "$WORKDIR/logs/slave_status_mdnode2.log" "$WORKDIR/logs/mdnode2.err"
    slave_startup_check "/tmp/md1.sock" "$WORKDIR/logs/slave_status_mdnode1.log" "$WORKDIR/logs/mdnode1.err"

    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -e "drop database if exists mtr_db_md1_1;create database mtr_db_md1_1;" 2>/dev/null
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -e "drop database if exists mtr_db_md1_2;create database mtr_db_md1_2;" 2>/dev/null
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -e "drop database if exists mtr_db_md1_3;create database mtr_db_md1_3;" 2>/dev/null
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -e "drop database if exists mtr_db_md1_4;create database mtr_db_md1_4;" 2>/dev/null
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -e "drop database if exists mtr_db_md1_5;create database mtr_db_md1_5;" 2>/dev/null

    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md2.sock -e "drop database if exists mtr_db_md2_1;create database mtr_db_md2_1;" 2>/dev/null
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md2.sock -e "drop database if exists mtr_db_md2_2;create database mtr_db_md2_2;" 2>/dev/null
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md2.sock -e "drop database if exists mtr_db_md2_3;create database mtr_db_md2_3;" 2>/dev/null
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md2.sock -e "drop database if exists mtr_db_md2_4;create database mtr_db_md2_4;" 2>/dev/null
    ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md2.sock -e "drop database if exists mtr_db_md2_5;create database mtr_db_md2_5;" 2>/dev/null
	  create_test_user "/tmp/md1.sock"
    create_test_user "/tmp/md2.sock"
    sleep 5
    # Sysbench dataload for MTR test
    echoit "Sysbench dataload for MTR test"
    async_sysbench_load mtr_db_md1_1 "/tmp/md1.sock"
    async_sysbench_load mtr_db_md1_2 "/tmp/md1.sock"
    async_sysbench_load mtr_db_md1_3 "/tmp/md1.sock"
    async_sysbench_load mtr_db_md1_4 "/tmp/md1.sock"
    async_sysbench_load mtr_db_md1_5 "/tmp/md1.sock"

    async_sysbench_load mtr_db_md2_1 "/tmp/md2.sock"
    async_sysbench_load mtr_db_md2_2 "/tmp/md2.sock"
    async_sysbench_load mtr_db_md2_3 "/tmp/md2.sock"
    async_sysbench_load mtr_db_md2_4 "/tmp/md2.sock"
    async_sysbench_load mtr_db_md2_5 "/tmp/md2.sock"

    # Sysbench RW MTR test run...
    sysbench_run oltp mtr_db_md1_1
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=/tmp/md1.sock  run  > $WORKDIR/logs/sysbench_mtr_db_md1_1_rw.log 2>&1 &
    check_cmd $? "Failed to execute sysbench read/write run (DB : mtr_db_md1_1 ,socket : /tmp/md1.sock)"
    sysbench_run oltp mtr_db_md1_2
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=/tmp/md1.sock  run  > $WORKDIR/logs/sysbench_mtr_db_md1_2_rw.log 2>&1 &
    check_cmd $? "Failed to execute sysbench read/write run (DB : mtr_db_md1_2 ,socket : /tmp/md1.sock)"
    sysbench_run oltp mtr_db_md1_3
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=/tmp/md1.sock  run  > $WORKDIR/logs/sysbench_mtr_db_md1_3_rw.log 2>&1 &
    check_cmd $? "Failed to execute sysbench read/write run (DB : mtr_db_md1_3 ,socket : /tmp/md1.sock)"
    sysbench_run oltp mtr_db_md1_4
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=/tmp/md1.sock  run  > $WORKDIR/logs/sysbench_mtr_db_md1_4_rw.log 2>&1 &
    check_cmd $? "Failed to execute sysbench read/write run (DB : mtr_db_md1_4 ,socket : /tmp/md1.sock)"
    sysbench_run oltp mtr_db_md1_5
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=/tmp/md1.sock  run  > $WORKDIR/logs/sysbench_mtr_db_md1_5_rw.log 2>&1 &
    check_cmd $? "Failed to execute sysbench read/write run (DB : mtr_db_md1_5 ,socket : /tmp/md1.sock)"
    # Sysbench RW MTR test run...
    sysbench_run oltp mtr_db_md2_1
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=/tmp/md2.sock  run  > $WORKDIR/logs/sysbench_mtr_db_md2_1_rw.log 2>&1 &
    check_cmd $? "Failed to execute sysbench read/write run (DB : mtr_db_md2_1 ,socket : /tmp/md2.sock)"
    sysbench_run oltp mtr_db_md2_2
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=/tmp/md2.sock  run  > $WORKDIR/logs/sysbench_mtr_db_md2_2_rw.log 2>&1 &
    check_cmd $? "Failed to execute sysbench read/write run (DB : mtr_db_md2_2 ,socket : /tmp/md2.sock)"
    sysbench_run oltp mtr_db_md2_3
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=/tmp/md2.sock  run  > $WORKDIR/logs/sysbench_mtr_db_md2_3_rw.log 2>&1 &
    check_cmd $? "Failed to execute sysbench read/write run (DB : mtr_db_md2_3 ,socket : /tmp/md2.sock)"
    sysbench_run oltp mtr_db_md2_4
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=/tmp/md2.sock  run  > $WORKDIR/logs/sysbench_mtr_db_md2_4_rw.log 2>&1 &
    check_cmd $? "Failed to execute sysbench read/write run (DB : mtr_db_md2_4 ,socket : /tmp/md2.sock)"
    sysbench_run oltp mtr_db_md2_5
    $SBENCH $SYSBENCH_OPTIONS --mysql-socket=/tmp/md2.sock  run  > $WORKDIR/logs/sysbench_mtr_db_md2_5_rw.log 2>&1
    check_cmd $? "Failed to execute sysbench read/write run (DB : mtr_db_md2_5 ,socket : /tmp/md2.sock)"

    # Sysbench data insert run for MTR test
    echoit "Sysbench data insert run for MTR test"
    async_sysbench_insert_run mtr_db_md1_1 "/tmp/md1.sock"
    async_sysbench_insert_run mtr_db_md1_2 "/tmp/md1.sock"
    async_sysbench_insert_run mtr_db_md1_3 "/tmp/md1.sock"
    async_sysbench_insert_run mtr_db_md1_4 "/tmp/md1.sock"
    async_sysbench_insert_run mtr_db_md1_5 "/tmp/md1.sock"

    async_sysbench_insert_run mtr_db_md2_1 "/tmp/md2.sock"
    async_sysbench_insert_run mtr_db_md2_2 "/tmp/md2.sock"
    async_sysbench_insert_run mtr_db_md2_3 "/tmp/md2.sock"
    async_sysbench_insert_run mtr_db_md2_4 "/tmp/md2.sock"
    async_sysbench_insert_run mtr_db_md2_5 "/tmp/md2.sock"
    sleep 5

    if [ "$ENCRYPTION" == 1 ];then
      echoit "Running general tablespace encryption test run"
      gt_test_run mtr_db_md1_1 "/tmp/md1.sock"
      gt_test_run mtr_db_md2_1 "/tmp/md2.sock"
    fi

    sleep 10
    local SB_MD_1=`$MD_BASEDIR/bin/mariadb -uroot --socket=/tmp/md2.sock -Bse "show slave status\G" 2>/dev/null | grep Seconds_Behind_Master | awk '{ print $2 }'`
    local SB_MD_2=`$MD_BASEDIR/bin/mariadb -uroot --socket=/tmp/md1.sock -Bse "show slave status\G" 2>/dev/null | grep Seconds_Behind_Master | awk '{ print $2 }'`

    while [ $SB_MD_1 -gt 0 ]; do
      SB_MD_1=`$MD_BASEDIR/bin/mariadb -uroot --socket=/tmp/md2.sock -Bse "show slave status\G" 2>/dev/null | grep Seconds_Behind_Master | awk '{ print $2 }'`
      if ! [[ "$SB_MD_1" =~ ^[0-9]+$ ]]; then
        ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md2.sock -Bse "show slave status\G" 2>/dev/null > $WORKDIR/logs/slave_status_mdnode2.log
        echo "Slave is not started yet. Please check error log and slave status : $WORKDIR/logs/mdnode2.err,  $WORKDIR/logs/slave_status_mdnode2.log"
        exit 1
      fi
      sleep 5
    done

    while [ $SB_MD_2 -gt 0 ]; do
      SB_MD_2=`$MD_BASEDIR/bin/mariadb -uroot --socket=/tmp/md1.sock -Bse "show slave status\G" 2>/dev/null | grep Seconds_Behind_Master | awk '{ print $2 }'`
      if ! [[ "$SB_MD_2" =~ ^[0-9]+$ ]]; then
        ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -Bse "show slave status\G" 2>/dev/null > $WORKDIR/logs/slave_status_mdnode1.log
        echo "Slave is not started yet. Please check error log and slave status : $WORKDIR/logs/mdnode1.err,  $WORKDIR/logs/slave_status_mdnode1.log"
        exit 1
      fi
      sleep 5
    done

    sleep 10
    echoit "Multi thread replication: Checking data consistency."
    run_mysqlchecksum "mtr_db_md1_1" "/tmp/md1.sock" "/tmp/md2.sock"
    run_mysqlchecksum "mtr_db_md1_2" "/tmp/md1.sock" "/tmp/md2.sock"
    run_mysqlchecksum "mtr_db_md1_3" "/tmp/md1.sock" "/tmp/md2.sock"
    run_mysqlchecksum "mtr_db_md1_4" "/tmp/md1.sock" "/tmp/md2.sock"
    run_mysqlchecksum "mtr_db_md1_5" "/tmp/md1.sock" "/tmp/md2.sock"
    run_mysqlchecksum "mtr_db_md2_1" "/tmp/md1.sock" "/tmp/md2.sock"
    run_mysqlchecksum "mtr_db_md2_2" "/tmp/md1.sock" "/tmp/md2.sock"
    run_mysqlchecksum "mtr_db_md2_3" "/tmp/md1.sock" "/tmp/md2.sock"
    run_mysqlchecksum "mtr_db_md2_4" "/tmp/md1.sock" "/tmp/md2.sock"
    run_mysqlchecksum "mtr_db_md2_5" "/tmp/md1.sock" "/tmp/md2.sock"

    #Shutdown MD servers
    echoit "Shuttingdown MD servers"
    $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/md1.sock -u root shutdown 2>/dev/null
    $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/md2.sock -u root shutdown 2>/dev/null
  }

  function xb_master_slave_test(){
    if [[ "$ENGINE" == "tokudb" ]]; then
      echoit "XtraBackup doesn't support tokudb backup so skipping!"
      return 0
    elif ! check_for_version $MARIADB_VERSION "8.0.15" && [[ "$ENGINE" == "rocksdb" ]]; then
      echoit "XtraBackup 2.4 with MD 5.7 doesn't support rocksdb backup so skipping!"
      return 0
    elif ! check_for_version $MARIADB_VERSION "8.0.15" && [[ "$ENCRYPTION" == 1 ]]; then
      echoit "XtraBackup 2.4 with MD 5.7 supports only limited functionality for encryption so skipping!"
      return 0
    else
      echoit "********************$MYEXTRA_CHECK master slave test using xtrabackup ************************"
      #MD server initialization
      echoit "MD server initialization"
      md_start 1 "XB"
      ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -e "drop database if exists sbtest_xb_db;create database sbtest_xb_db;" 2>/dev/null
      create_test_user "/tmp/md1.sock"
      async_sysbench_load sbtest_xb_db "/tmp/md1.sock"
      async_sysbench_insert_run sbtest_xb_db "/tmp/md1.sock"

      echoit "Check xtrabackup binary"
      check_xb_dir
      echoit "Initiate xtrabackup"
      backup_database "/tmp/md1.sock"

      ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -e "drop database if exists sbtest_xb_check;create database sbtest_xb_check;" 2>/dev/null
      ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -e "create table sbtest_xb_check.t1(id int);" 2>/dev/null
      local BINLOG_FILE=$(cat ${WORKDIR}/backupdir/full/xtrabackup_binlog_info | awk '{print $1}')
      local BINLOG_POS=$(cat ${WORKDIR}/backupdir/full/xtrabackup_binlog_info | awk '{print $2}')
      echoit "Starting replication on restored slave"
      local PORT=$(${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/md1.sock -Bse "select @@port" 2>/dev/null)
      ${MD_BASEDIR}/bin/mariadb -uroot --socket=/tmp/bkmdlave.sock -e"CHANGE MASTER TO MASTER_HOST='${ADDR}', MASTER_PORT=$PORT, MASTER_USER='repl_user', MASTER_PASSWORD='repl_pass', MASTER_LOG_FILE='$BINLOG_FILE',MASTER_LOG_POS=$BINLOG_POS;START SLAVE" 2>/dev/null

      slave_startup_check "/tmp/bkmdlave.sock" "$WORKDIR/logs/slave_status_bkmdlave.log" "$WORKDIR/logs/bkmdlave.err"

      echoit "XB master slave replication: Checking data consistency."
      
      run_mysqlchecksum "sbtest_xb_db" "/tmp/md1.sock" "/tmp/bkmdlave.sock"
      run_mysqlchecksum "sbtest_xb_check" "/tmp/md1.sock" "/tmp/bkmdlave.sock"

      $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/md1.sock -u root shutdown 2>/dev/null
      $MD_BASEDIR/bin/mariadb-admin  --socket=/tmp/bkmdlave.sock -u root shutdown 2>/dev/null
    fi
  }

  if [[ ! " ${TC_ARRAY[@]} " =~ " all " ]]; then
    for i in "${TC_ARRAY[@]}"; do
      if [[ "$i" == "master_slave_test" ]]; then
  	    master_slave_test
  	  elif [[ "$i" == "master_multi_slave_test" ]]; then
  	    master_multi_slave_test
  	  elif [[ "$i" == "master_master_test" ]]; then
  	    master_master_test
  	  elif [[ "$i" == "msr_test" ]]; then
        if check_for_version $MARIADB_VERSION "5.7.0" ; then
          msr_test
        fi
      elif [[ "$i" == "mtr_test" ]]; then
  	    mtr_test
      fi
    done
  else
    master_slave_test
    master_multi_slave_test
    master_master_test
    if check_for_version $MARIADB_VERSION "5.7.0" ; then
      msr_test
    fi
    mtr_test
  fi
}

async_rpl_test
async_rpl_test GTID

