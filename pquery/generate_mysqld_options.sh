#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

# This script quickly and intelligently generates all available mysqld --option combinations (i.e. including values)

# User variables
OUTPUT_FILE=/tmp/mysqld_options.txt

# Internal variables, do not change
TEMP_FILE=/tmp/mysqld_options.tmp

if [ ! -r ./bin/mysqld ]; then
  if [ ! -r ./mysqld ]; then
    echo "This script quickly and intelligently generates all available mysqld --option combinations (i.e. including values)"
    echo "Error: no ./bin/mysqld or ./mysqld found!"
    exit 1
  else
    cd ..
  fi
fi

IS_PXC=0
if ./bin/mysqld --version | grep -q 'Percona XtraDB Cluster' 2>/dev/null ; then 
  IS_PXC=1
fi

echoit(){
  echo "[$(date +'%T')] $1"
  echo "[$(date +'%T')] $1" >> /tmp/generate_mysqld_options.log
}

# Extract all options, their default values, and do some initial cleaning
./bin/mysqld --no-defaults --help --verbose 2>/dev/null | \
 sed '0,/Value (after reading options)/d' | \
 egrep -v "To see what va.*is using|mysqladmin.*instead of|INFORMATION_SCHEMA.*instead of|^[ \t]*$|\-\-\-" \
 > ${TEMP_FILE}

# mysqld options excluded from list
# RV/HM 18.07.2017 Temporarily added to EXCLUDED_LIST: --binlog-group-commit-sync-delay due to hang issues seen in 5.7 with startup like --no-defaults --plugin-load=tokudb=ha_tokudb.so --tokudb-check-jemalloc=0 --init-file=/home/hrvoje/percona-qa/plugins_57.sql --binlog-group-commit-sync-delay=2047
# RV 24/02/2020 Temporarily added to EXCLUDED_LIST: --gtid-pos-auto-engines  (add later)
# RV 18/09/2021 The --max-session-mem-used exclusion is not ideal as this may provide valuable testing but it often ends runs with a 'SIGSEGV|my_malloc_size_cb_func|Backtrace stopped: Cannot access memory at address' UniqueID which would require fixing whilst low prio
# RV 18/09/2021 --innodb-data-file-size-debug was excluded until https://jira.mariadb.org/browse/MDEV-26068 is fixed. Would produce 'size >= 4U|SIGABRT|Backtrace stopped: Cannot access memory at address'
# Read-only system variables (cannot be set via command line) are excluded:
# --version --version-comment --version-compile-machine --version-compile-os --version-malloc-library --version-source-revision --version-ssl-library --system-time-zone --server-uid --wsrep-patch-version
EXCLUDED_LIST=( --basedir --datadir --plugin-dir --lc-messages-dir --tmpdir --slave-load-tmpdir --bind-address --binlog-checksum --character-sets-dir --init-file --general-log-file --log-error --innodb-data-home-dir --event-scheduler --chroot --init-slave --init-connect --debug --default-time-zone --des-key-file --ft-stopword-file --innodb-page-size --innodb-undo-tablespaces --innodb-data-file-path --innodb-ft-aux-table --innodb-ft-server-stopword-table --innodb-ft-user-stopword-table --innodb-log-arch-dir --innodb-log-group-home-dir --log-bin-index --relay-log-index --report-host --report-password --report-user --secure-file-priv --slave-skip-errors --ssl-ca --ssl-capath --ssl-cert --ssl-cipher --ssl-crl --ssl-crlpath --ssl-key --utility-user --utility-user-password --socket --socket-umask --innodb-trx-rseg-n-slots-debug --innodb-fil-make-page-dirty-debug --initialize --initialize-insecure --port --binlog-group-commit-sync-delay --innodb-directories --keyring-migration-destination --keyring-migration-host --keyring-migration-password --keyring-migration-port --keyring-migration-socket --keyring-migration-source --keyring-migration-user --mysqlx-socket --mysqlx-ssl-ca --mysqlx-bind-address --mysqlx-ssl-capath --mysqlx-ssl-cert --mysqlx-ssl-cipher --mysqlx-ssl-crl --mysqlx-ssl-crlpath --mysqlx-ssl-key --innodb-temp-tablespaces-dir --debug-dbug --feedback-http-proxy --feedback-send-retry-wait --feedback-send-timeout --feedback-url --feedback-user-info --gtid-pos-auto-engines --ignore-db-dirs --innodb-file-format --max-session-mem-used --innodb-data-file-size-debug --version --version-comment --version-compile-machine --version-compile-os --version-malloc-library --version-source-revision --version-ssl-library --system-time-zone --server-uid --wsrep-patch-version )
# Create a file (${OUTPUT_FILE}) with all options/values intelligently handled and included
rm -Rf ${OUTPUT_FILE}
touch ${OUTPUT_FILE}

while read line; do 
  OPTION="--$(echo ${line} | awk '{print $1}')"
  VALUE="$(echo ${line} | awk '{print $2}' | sed 's|^[ \t]*||;s|[ \t]*$||')"
  if [ "${VALUE}" == "(No" ]; then
    echoit "Working on option '${OPTION}' which has no default value..."
  else
    echoit "Working on option '${OPTION}' with default value '${VALUE}'..."
  fi
  # Process options & values
  if [[ " ${EXCLUDED_LIST[@]} " =~ " ${OPTION} " ]]; then 
    echoit "  > Option '${OPTION}' is logically excluded from being handled by this script..."
  elif [ "${OPTION}" == "--enforce-storage-engine" ]; then
    echoit "  > Adding possible values Aria, InnoDB, MyISAM, MEMORY, CSV, MERGE, Sequence, ARCHIVE, BLACKHOLE, FEDERATED, RocksDB, SPIDER for option '${OPTION}' to the final list..."
    echo "${OPTION}=Aria" >> ${OUTPUT_FILE}
    echo "${OPTION}=Aria" >> ${OUTPUT_FILE}
    echo "${OPTION}=Aria" >> ${OUTPUT_FILE}
    echo "${OPTION}=InnoDB" >> ${OUTPUT_FILE}
    echo "${OPTION}=InnoDB" >> ${OUTPUT_FILE}
    echo "${OPTION}=InnoDB" >> ${OUTPUT_FILE}
    echo "${OPTION}=MyISAM" >> ${OUTPUT_FILE}
    echo "${OPTION}=MyISAM" >> ${OUTPUT_FILE}
    echo "${OPTION}=MEMORY" >> ${OUTPUT_FILE}
    echo "${OPTION}=CSV" >> ${OUTPUT_FILE}
    echo "${OPTION}=MERGE" >> ${OUTPUT_FILE}
    echo "${OPTION}=Sequence" >> ${OUTPUT_FILE}
    echo "${OPTION}=ARCHIVE" >> ${OUTPUT_FILE}
    echo "${OPTION}=BLACKHOLE" >> ${OUTPUT_FILE}
    echo "${OPTION}=FEDERATED" >> ${OUTPUT_FILE}
    echo "${OPTION}=RocksDB" >> ${OUTPUT_FILE}
    echo "${OPTION}=SPIDER" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--binlog-error-action" ]; then
    echoit "  > Adding possible values IGNORE_ERROR, ABORT_SERVER for option '${OPTION}' to the final list..."
    echo "${OPTION}=IGNORE_ERROR" >> ${OUTPUT_FILE}
    echo "${OPTION}=ABORT_SERVER" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--enforce-gtid-consistency" ]; then
    echoit "  > Adding possible values OFF, ON, WARN for option '${OPTION}' to the final list..."
    echo "${OPTION}=OFF" >> ${OUTPUT_FILE}
    echo "${OPTION}=ON" >> ${OUTPUT_FILE}
    echo "${OPTION}=WARN" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--gtid-mode" ]; then
    echoit "  > Adding possible values OFF, OFF_PERMISSIVE, ON_PERMISSIVE, ON, ON enforce for option '${OPTION}' to the final list..."
    echo "${OPTION}=OFF" >> ${OUTPUT_FILE}
    echo "${OPTION}=OFF_PERMISSIVE" >> ${OUTPUT_FILE}
    echo "${OPTION}=ON" >> ${OUTPUT_FILE}
    echo "${OPTION}=ON --enforce-gtid-consistency=ON" >> ${OUTPUT_FILE}
    echo "${OPTION}=ON_PERMISSIVE" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--mandatory-roles" ]; then
    echoit "  > Adding possible values '','role1@%,role2,role3,role4@localhost','@%','user1@localhost,testuser@%' for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}='role1@%,role2,role3,role4@localhost'" >> ${OUTPUT_FILE}
    echo "${OPTION}='@%'" >> ${OUTPUT_FILE}
    echo "${OPTION}='user1@localhost,testuser@%'" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--binlog-format" ]; then
    echoit "  > Adding possible values ROW, STATEMENT, MIXED for option '${OPTION}' to the final list..."
    echo "${OPTION}=ROW" >> ${OUTPUT_FILE}
    echo "${OPTION}=STATEMENT" >> ${OUTPUT_FILE}
    echo "${OPTION}=MIXED" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--binlog-row-image" ]; then
    echoit "  > Adding possible values full, minimal, noblob for option '${OPTION}' to the final list..."
    echo "${OPTION}=full" >> ${OUTPUT_FILE}
    echo "${OPTION}=minimal" >> ${OUTPUT_FILE}
    echo "${OPTION}=noblob" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--binlog-row-value-options" ]; then
    echoit "  > Adding possible values '',PARTIAL_JSON for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=PARTIAL_JSON" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--binlogging-impossible-mode" ]; then
    echoit "  > Adding possible values IGNORE_ERROR, ABORT_SERVER for option '${OPTION}' to the final list..."
    echo "${OPTION}=IGNORE_ERROR" >> ${OUTPUT_FILE}
    echo "${OPTION}=ABORT_SERVER" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--character-set-filesystem" -o "${OPTION}" == "--character-set-server" ]; then
    echoit "  > Adding possible values binary, utf8 for option '${OPTION}' to the final list..."
    echo "${OPTION}=binary" >> ${OUTPUT_FILE}
    echo "${OPTION}=utf8" >> ${OUTPUT_FILE}
    echo "${OPTION}=big5" >> ${OUTPUT_FILE}
    echo "${OPTION}=dec8" >> ${OUTPUT_FILE}
    echo "${OPTION}=cp850" >> ${OUTPUT_FILE}
    echo "${OPTION}=hp8" >> ${OUTPUT_FILE}
    echo "${OPTION}=koi8r" >> ${OUTPUT_FILE}
    echo "${OPTION}=latin1" >> ${OUTPUT_FILE}
    echo "${OPTION}=latin2" >> ${OUTPUT_FILE}
    echo "${OPTION}=swe7" >> ${OUTPUT_FILE}
    echo "${OPTION}=ascii" >> ${OUTPUT_FILE}
    echo "${OPTION}=ujis" >> ${OUTPUT_FILE}
    echo "${OPTION}=sjis" >> ${OUTPUT_FILE}
    echo "${OPTION}=hebrew" >> ${OUTPUT_FILE}
    echo "${OPTION}=tis620" >> ${OUTPUT_FILE}
    echo "${OPTION}=euckr" >> ${OUTPUT_FILE}
    echo "${OPTION}=koi8u" >> ${OUTPUT_FILE}
    echo "${OPTION}=gb2312" >> ${OUTPUT_FILE}
    echo "${OPTION}=greek" >> ${OUTPUT_FILE}
    echo "${OPTION}=cp1250" >> ${OUTPUT_FILE}
    echo "${OPTION}=gbk" >> ${OUTPUT_FILE}
    echo "${OPTION}=latin5" >> ${OUTPUT_FILE}
    echo "${OPTION}=armscii8" >> ${OUTPUT_FILE}
    echo "${OPTION}=ucs2" >> ${OUTPUT_FILE}
    echo "${OPTION}=cp866" >> ${OUTPUT_FILE}
    echo "${OPTION}=keybcs2" >> ${OUTPUT_FILE}
    echo "${OPTION}=macce" >> ${OUTPUT_FILE}
    echo "${OPTION}=macroman" >> ${OUTPUT_FILE}
    echo "${OPTION}=cp852" >> ${OUTPUT_FILE}
    echo "${OPTION}=latin7" >> ${OUTPUT_FILE}
    echo "${OPTION}=utf8mb4" >> ${OUTPUT_FILE}
    echo "${OPTION}=cp1251" >> ${OUTPUT_FILE}
    echo "${OPTION}=utf16" >> ${OUTPUT_FILE}
    echo "${OPTION}=utf16le" >> ${OUTPUT_FILE}
    echo "${OPTION}=cp1256" >> ${OUTPUT_FILE}
    echo "${OPTION}=cp1257" >> ${OUTPUT_FILE}
    echo "${OPTION}=utf32" >> ${OUTPUT_FILE}
    echo "${OPTION}=geostd8" >> ${OUTPUT_FILE}
    echo "${OPTION}=cp932" >> ${OUTPUT_FILE}
    echo "${OPTION}=eucjpms" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--collation-server" ]; then
    echoit "  > Adding possible values utf8mb4_general_ci, utf8mb4_bin, utf8mb4_uca1400_ai_ci, latin1_swedish_ci, binary for option '${OPTION}' to the final list..."
    echo "${OPTION}=utf8mb4_general_ci" >> ${OUTPUT_FILE}
    echo "${OPTION}=utf8mb4_bin" >> ${OUTPUT_FILE}
    echo "${OPTION}=utf8mb4_uca1400_ai_ci" >> ${OUTPUT_FILE}
    echo "${OPTION}=utf8mb4_uca1400_as_cs" >> ${OUTPUT_FILE}
    echo "${OPTION}=latin1_swedish_ci" >> ${OUTPUT_FILE}
    echo "${OPTION}=latin1_bin" >> ${OUTPUT_FILE}
    echo "${OPTION}=binary" >> ${OUTPUT_FILE}
    echo "${OPTION}=ascii_general_ci" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--completion-type" ]; then
    echoit "  > Adding possible values 0, 1, 2 for option '${OPTION}' to the final list..."
    echo "${OPTION}=0" >> ${OUTPUT_FILE}
    echo "${OPTION}=1" >> ${OUTPUT_FILE}
    echo "${OPTION}=2" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--concurrent-insert" ]; then
    echoit "  > Adding possible values 0, 1, 2 for option '${OPTION}' to the final list..."
    echo "${OPTION}=0" >> ${OUTPUT_FILE}
    echo "${OPTION}=1" >> ${OUTPUT_FILE}
    echo "${OPTION}=2" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--csv-mode" ]; then
    echoit "  > Adding possible values IETF_QUOTES for option '${OPTION}' to the final list..."
    echo "${OPTION}=IETF_QUOTES" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--log-slow-filter" ]; then
    echoit "  > Adding possible values admin, filesort, filesort_on_disk, filesort_priority_queue, full_join, full_scan, not_using_index, query_cache, query_cache_miss, tmp_table, tmp_table_on_disk, ALL for option '${OPTION}' to the final list..."
    echo "${OPTION}=admin" >> ${OUTPUT_FILE}
    echo "${OPTION}=filesort" >> ${OUTPUT_FILE}
    echo "${OPTION}=filesort_on_disk" >> ${OUTPUT_FILE}
    echo "${OPTION}=filesort_priority_queue" >> ${OUTPUT_FILE}
    echo "${OPTION}=full_join" >> ${OUTPUT_FILE}
    echo "${OPTION}=full_scan" >> ${OUTPUT_FILE}
    echo "${OPTION}=not_using_index" >> ${OUTPUT_FILE}
    echo "${OPTION}=query_cache" >> ${OUTPUT_FILE}
    echo "${OPTION}=query_cache_miss" >> ${OUTPUT_FILE}
    echo "${OPTION}=tmp_table" >> ${OUTPUT_FILE}
    echo "${OPTION}=tmp_table_on_disk" >> ${OUTPUT_FILE}
    echo "${OPTION}=admin,filesort,full_scan,tmp_table" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--log-slow-verbosity" ]; then
    echoit "  > Adding possible values innodb, query_plan, explain, engine, warnings, full, ALL for option '${OPTION}' to the final list..."
    echo "${OPTION}=innodb" >> ${OUTPUT_FILE}
    echo "${OPTION}=query_plan" >> ${OUTPUT_FILE}
    echo "${OPTION}=explain" >> ${OUTPUT_FILE}
    echo "${OPTION}=engine" >> ${OUTPUT_FILE}
    echo "${OPTION}=warnings" >> ${OUTPUT_FILE}
    echo "${OPTION}=full" >> ${OUTPUT_FILE}
    echo "${OPTION}=innodb,query_plan,explain" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-log-files-in-group" ]; then
    echoit "  > Adding possible values 0,1,2,5,10 for option '${OPTION}' to the final list..."
    echo "${OPTION}=0" >> ${OUTPUT_FILE}
    echo "${OPTION}=1" >> ${OUTPUT_FILE}
    echo "${OPTION}=2" >> ${OUTPUT_FILE}
    echo "${OPTION}=5" >> ${OUTPUT_FILE}
    echo "${OPTION}=10" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--log-warnings-suppress" ]; then
    echoit "  > Adding possible values 1592 for option '${OPTION}' to the final list..."
    echo "${OPTION}=1592" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--slave-type-conversions" ]; then
    echoit "  > Adding possible values ALL_LOSSY, ALL_NON_LOSSY for option '${OPTION}' to the final list..."
    echo "${OPTION}=ALL_LOSSY" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL_NON_LOSSY" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL_SIGNED" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL_UNSIGNED" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-checksum-algorithm" ]; then
    echoit "  > Adding possible values innodb, crc32 for option '${OPTION}' to the final list..."
    echo "${OPTION}=innodb" >> ${OUTPUT_FILE}
    echo "${OPTION}=crc32" >> ${OUTPUT_FILE}
    echo "${OPTION}=none" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-cleaner-lsn-age-factor" ]; then
    echoit "  > Adding possible values legacy, high_checkpoint for option '${OPTION}' to the final list..."
    echo "${OPTION}=legacy" >> ${OUTPUT_FILE}
    echo "${OPTION}=high_checkpoint" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-corrupt-table-action" ]; then
    echoit "  > Adding possible values assert, warn for option '${OPTION}' to the final list..."
    echo "${OPTION}=assert" >> ${OUTPUT_FILE}
    echo "${OPTION}=warn" >> ${OUTPUT_FILE}
    echo "${OPTION}=salvage" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-empty-free-list-algorithm" ]; then
    echoit "  > Adding possible values legacy, backoff for option '${OPTION}' to the final list..."
    echo "${OPTION}=legacy" >> ${OUTPUT_FILE}
    echo "${OPTION}=backoff" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-file-format-max" ]; then
    echoit "  > Adding possible values Antelope, Barracuda for option '${OPTION}' to the final list..."
    echo "${OPTION}=Antelope" >> ${OUTPUT_FILE}
    echo "${OPTION}=Barracuda" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-foreground-preflush" ]; then
    echoit "  > Adding possible values sync_preflush, exponential_backoff for option '${OPTION}' to the final list..."
    echo "${OPTION}=sync_preflush" >> ${OUTPUT_FILE}
    echo "${OPTION}=exponential_backoff" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-buffer-pool-evict" ]; then
    echoit "  > Adding possible values uncompressed for option '${OPTION}' to the final list..."
    echo "${OPTION}=uncompressed" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-flush-method" ]; then
    echoit "  > Adding possible values fsync, O_DSYNC for option '${OPTION}' to the final list..."
    echo "${OPTION}=fsync" >> ${OUTPUT_FILE}
    echo "${OPTION}=O_DSYNC" >> ${OUTPUT_FILE}
    echo "${OPTION}=O_DIRECT" >> ${OUTPUT_FILE}
    echo "${OPTION}=O_DIRECT_NO_FSYNC" >> ${OUTPUT_FILE}
    echo "${OPTION}=littlesync" >> ${OUTPUT_FILE}
    echo "${OPTION}=nosync" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-log-checksum-algorithm" ]; then
    echoit "  > Adding possible values innodb, crc32 for option '${OPTION}' to the final list..."
    echo "${OPTION}=innodb" >> ${OUTPUT_FILE}
    echo "${OPTION}=crc32" >> ${OUTPUT_FILE}
    echo "${OPTION}=none" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-monitor-disable" ]; then
    echoit "  > Adding possible values counter, module for option '${OPTION}' to the final list..."
    echo "${OPTION}=counter" >> ${OUTPUT_FILE}
    echo "${OPTION}=module" >> ${OUTPUT_FILE}
    echo "${OPTION}=pattern" >> ${OUTPUT_FILE}
    echo "${OPTION}=all" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-monitor-enable" ]; then
    echoit "  > Adding possible values counter, module for option '${OPTION}' to the final list..."
    echo "${OPTION}=counter" >> ${OUTPUT_FILE}
    echo "${OPTION}=module" >> ${OUTPUT_FILE}
    echo "${OPTION}=pattern" >> ${OUTPUT_FILE}
    echo "${OPTION}=all" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-monitor-reset" ]; then
    echoit "  > Adding possible values counter, module for option '${OPTION}' to the final list..."
    echo "${OPTION}=counter" >> ${OUTPUT_FILE}
    echo "${OPTION}=module" >> ${OUTPUT_FILE}
    echo "${OPTION}=pattern" >> ${OUTPUT_FILE}
    echo "${OPTION}=all" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-monitor-reset-all" ]; then
    echoit "  > Adding possible values counter, module for option '${OPTION}' to the final list..."
    echo "${OPTION}=counter" >> ${OUTPUT_FILE}
    echo "${OPTION}=module" >> ${OUTPUT_FILE}
    echo "${OPTION}=pattern" >> ${OUTPUT_FILE}
    echo "${OPTION}=all" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-stats-method" ]; then
    echoit "  > Adding possible values nulls_equal, nulls_unequal for option '${OPTION}' to the final list..."
    echo "${OPTION}=nulls_equal" >> ${OUTPUT_FILE}
    echo "${OPTION}=nulls_unequal" >> ${OUTPUT_FILE}
    echo "${OPTION}=nulls_ignored" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--log-bin" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
    echo "${OPTION}" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--log-slow-rate-type" ]; then
    echoit "  > Adding possible values session, query for option '${OPTION}' to the final list..."
    echo "${OPTION}=session" >> ${OUTPUT_FILE}
    echo "${OPTION}=query" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--myisam-stats-method" ]; then
    echoit "  > Adding possible values nulls_equal, nulls_unequal for option '${OPTION}' to the final list..."
    echo "${OPTION}=nulls_equal" >> ${OUTPUT_FILE}
    echo "${OPTION}=nulls_unequal" >> ${OUTPUT_FILE}
    echo "${OPTION}=nulls_ignored" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--performance-schema-accounts-size" ]; then
    echoit "  > Adding possible values 0, 1, 2, 12, 24, 254, 1023, 2047, 1048576 for option '${OPTION}' to the final list..."
    echo "${OPTION}=0" >> ${OUTPUT_FILE}
    echo "${OPTION}=1" >> ${OUTPUT_FILE}
    echo "${OPTION}=2" >> ${OUTPUT_FILE}
    echo "${OPTION}=12" >> ${OUTPUT_FILE}
    echo "${OPTION}=24" >> ${OUTPUT_FILE}
    echo "${OPTION}=254" >> ${OUTPUT_FILE}
    echo "${OPTION}=1023" >> ${OUTPUT_FILE}
    echo "${OPTION}=2047" >> ${OUTPUT_FILE}
    echo "${OPTION}=1048576" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--performance-schema-hosts-size" ]; then
    echoit "  > Adding possible values 0, 1, 2, 12, 24, 254, 1023, 2047, 1048576 for option '${OPTION}' to the final list..."
    echo "${OPTION}=0" >> ${OUTPUT_FILE}
    echo "${OPTION}=1" >> ${OUTPUT_FILE}
    echo "${OPTION}=2" >> ${OUTPUT_FILE}
    echo "${OPTION}=12" >> ${OUTPUT_FILE}
    echo "${OPTION}=24" >> ${OUTPUT_FILE}
    echo "${OPTION}=254" >> ${OUTPUT_FILE}
    echo "${OPTION}=1023" >> ${OUTPUT_FILE}
    echo "${OPTION}=2047" >> ${OUTPUT_FILE}
    echo "${OPTION}=1048576" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--performance-schema-max-thread-instances" ]; then
    echoit "  > Adding possible values 0, 1, 2, 12, 24, 254, 1023, 2047, 104857 for option '${OPTION}' to the final list..."
    echo "${OPTION}=0" >> ${OUTPUT_FILE}
    echo "${OPTION}=1" >> ${OUTPUT_FILE}
    echo "${OPTION}=2" >> ${OUTPUT_FILE}
    echo "${OPTION}=12" >> ${OUTPUT_FILE}
    echo "${OPTION}=24" >> ${OUTPUT_FILE}
    echo "${OPTION}=254" >> ${OUTPUT_FILE}
    echo "${OPTION}=1023" >> ${OUTPUT_FILE}
    echo "${OPTION}=2047" >> ${OUTPUT_FILE}
    echo "${OPTION}=104857" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--performance-schema-users-size" ]; then
    echoit "  > Adding possible values 0, 1, 2, 12, 24, 254, 1023, 2047, 104857 for option '${OPTION}' to the final list..."
    echo "${OPTION}=0" >> ${OUTPUT_FILE}
    echo "${OPTION}=1" >> ${OUTPUT_FILE}
    echo "${OPTION}=2" >> ${OUTPUT_FILE}
    echo "${OPTION}=12" >> ${OUTPUT_FILE}
    echo "${OPTION}=24" >> ${OUTPUT_FILE}
    echo "${OPTION}=254" >> ${OUTPUT_FILE}
    echo "${OPTION}=1023" >> ${OUTPUT_FILE}
    echo "${OPTION}=2047" >> ${OUTPUT_FILE}
    echo "${OPTION}=104857" >> ${OUTPUT_FILE} 
  elif [ "${OPTION}" == "--relay-log" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
    echo "${OPTION}" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--slow-query-log-timestamp-precision" ]; then
    echoit "  > Adding possible values second, microsecond for option '${OPTION}' to the final list..."
    echo "${OPTION}=second" >> ${OUTPUT_FILE}
    echo "${OPTION}=microsecond" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--slow-query-log-use-global-control" ]; then
    echoit "  > Adding possible values none, log_slow_filter, log_slow_rate_limit for option '${OPTION}' to the final list..."
    echo "${OPTION}=none" >> ${OUTPUT_FILE}
    echo "${OPTION}=log_slow_filter" >> ${OUTPUT_FILE}
    echo "${OPTION}=log_slow_rate_limit" >> ${OUTPUT_FILE}
    echo "${OPTION}=log_slow_verbosity" >> ${OUTPUT_FILE}
    echo "${OPTION}=long_query_time" >> ${OUTPUT_FILE}
    echo "${OPTION}=min_examined_row_limit" >> ${OUTPUT_FILE}
    echo "${OPTION}=all" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--sql-mode" ]; then
    echoit "  > Adding possible values ALLOW_INVALID_DATES, ANSI_QUOTES for option '${OPTION}' to the final list..."
    echo "${OPTION}=ALLOW_INVALID_DATES" >> ${OUTPUT_FILE}
    echo "${OPTION}=ANSI_QUOTES" >> ${OUTPUT_FILE}
    echo "${OPTION}=ERROR_FOR_DIVISION_BY_ZERO" >> ${OUTPUT_FILE}
    echo "${OPTION}=HIGH_NOT_PRECEDENCE" >> ${OUTPUT_FILE}
    echo "${OPTION}=IGNORE_SPACE" >> ${OUTPUT_FILE}
    echo "${OPTION}=NO_AUTO_CREATE_USER" >> ${OUTPUT_FILE}
    echo "${OPTION}=NO_AUTO_VALUE_ON_ZERO" >> ${OUTPUT_FILE}
    echo "${OPTION}=NO_BACKSLASH_ESCAPES" >> ${OUTPUT_FILE}
    echo "${OPTION}=NO_DIR_IN_CREATE" >> ${OUTPUT_FILE}
    echo "${OPTION}=NO_ENGINE_SUBSTITUTION" >> ${OUTPUT_FILE}
    echo "${OPTION}=NO_FIELD_OPTIONS" >> ${OUTPUT_FILE}
    echo "${OPTION}=NO_KEY_OPTIONS" >> ${OUTPUT_FILE}
    echo "${OPTION}=NO_TABLE_OPTIONS" >> ${OUTPUT_FILE}
    echo "${OPTION}=NO_UNSIGNED_SUBTRACTION" >> ${OUTPUT_FILE}
    echo "${OPTION}=NO_ZERO_DATE" >> ${OUTPUT_FILE}
    echo "${OPTION}=NO_ZERO_IN_DATE" >> ${OUTPUT_FILE}
    echo "${OPTION}=ONLY_FULL_GROUP_BY" >> ${OUTPUT_FILE}
    echo "${OPTION}=PAD_CHAR_TO_FULL_LENGTH" >> ${OUTPUT_FILE}
    echo "${OPTION}=PIPES_AS_CONCAT" >> ${OUTPUT_FILE}
    echo "${OPTION}=REAL_AS_FLOAT" >> ${OUTPUT_FILE}
    echo "${OPTION}=STRICT_ALL_TABLES" >> ${OUTPUT_FILE}
    echo "${OPTION}=STRICT_TRANS_TABLES" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--thread-handling" ]; then
    echoit "  > Adding possible values no-threads, one-thread-per-connection for option '${OPTION}' to the final list..."
    echo "${OPTION}=no-threads" >> ${OUTPUT_FILE}
    echo "${OPTION}=one-thread-per-connection" >> ${OUTPUT_FILE}
    echo "${OPTION}=dynamically-loaded" >> ${OUTPUT_FILE}
    echo "${OPTION}=pool-of-threads" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--thread-pool-high-prio-mode" ]; then
    echoit "  > Adding possible values transactions, statements for option '${OPTION}' to the final list..."
    echo "${OPTION}=transactions" >> ${OUTPUT_FILE}
    echo "${OPTION}=statements" >> ${OUTPUT_FILE}
    echo "${OPTION}=none" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--transaction-isolation" ]; then
    echoit "  > Adding possible values READ-UNCOMMITTED, READ-COMMITTED for option '${OPTION}' to the final list..."
    echo "${OPTION}=READ-UNCOMMITTED" >> ${OUTPUT_FILE}
    echo "${OPTION}=READ-COMMITTED" >> ${OUTPUT_FILE}
    echo "${OPTION}=REPEATABLE-READ" >> ${OUTPUT_FILE}
    echo "${OPTION}=SERIALIZABLE" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--utility-user-schema-access" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--utility-user-privileges" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--proxy-protocol-networks" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--disabled-storage-engines" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--innodb-temp-data-file-path" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--innodb-undo-directory" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--log-syslog-tag" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--innodb-doublewrite-file" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--plugin-load" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--sql-mode" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--innodb-monitor-gaplock-query-filename" ]; then                  ## fb-mysql
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--innodb-tmpdir" ]; then                                          ## fb-mysql
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--rocksdb-compact-cf" ]; then                                     ## fb-mysql
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--rocksdb-default-cf-options" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--rocksdb-override-cf-options" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--rocksdb-snapshot-dir" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--rocksdb-strict-collation-exceptions" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--rocksdb-wal-dir" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--optimizer-trace" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--performance-schema-instrument" ]; then
    echoit "  > Adding possible values ... for option '${OPTION}' to the final list..."
  elif [ "${OPTION}" == "--block-encryption-mode" ]; then
    echoit "  > Adding possible values aes-128-ecb, aes-128-cbc, aes-128-cfb1, aes-192-ecb, aes-192-cbc, aes-192-ofb, aes-256-ecb, aes-256-cbc, aes-256-cfb128 for option '${OPTION}' to the final list..."
    echo "${OPTION}=aes-128-ecb" >> ${OUTPUT_FILE}
    echo "${OPTION}=aes-128-cbc" >> ${OUTPUT_FILE}
    echo "${OPTION}=aes-128-cfb1" >> ${OUTPUT_FILE}
    echo "${OPTION}=aes-192-ecb" >> ${OUTPUT_FILE}
    echo "${OPTION}=aes-192-cbc" >> ${OUTPUT_FILE}
    echo "${OPTION}=aes-192-ofb" >> ${OUTPUT_FILE}
    echo "${OPTION}=aes-256-ecb" >> ${OUTPUT_FILE}
    echo "${OPTION}=aes-256-cbc" >> ${OUTPUT_FILE}
    echo "${OPTION}=aes-256-cfb128" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--tokudb_cache_size" ]; then
    echoit "  > Adding possible values 52428800, 1125899906842624 for option '${OPTION}' to the final list..."
    echo "${OPTION}=52428800" >> ${OUTPUT_FILE}
    echo "${OPTION}=1125899906842624" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--default-authentication-plugin" ]; then
    echoit "  > Adding possible values mysql_native_password, sha256_password for option '${OPTION}' to the final list..."
    echo "${OPTION}=mysql_native_password" >> ${OUTPUT_FILE}
    echo "${OPTION}=sha256_password" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-change-buffering" ]; then
    echoit "  > Adding possible values all, none, inserts, deletes, changes, purges for option '${OPTION}' to the final list..."
    echo "${OPTION}=all" >> ${OUTPUT_FILE}
    echo "${OPTION}=none" >> ${OUTPUT_FILE}
    echo "${OPTION}=inserts" >> ${OUTPUT_FILE}
    echo "${OPTION}=deletes" >> ${OUTPUT_FILE}
    echo "${OPTION}=changes" >> ${OUTPUT_FILE}
    echo "${OPTION}=purges" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-default-row-format" ]; then
    echoit "  > Adding possible values dynamic, compact, redundant for option '${OPTION}' to the final list..."
    echo "${OPTION}=dynamic" >> ${OUTPUT_FILE}
    echo "${OPTION}=compact" >> ${OUTPUT_FILE}
    echo "${OPTION}=redundant" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--internal-tmp-disk-storage-engine" ]; then
    echoit "  > Adding possible values INNODB, MYISAM for option '${OPTION}' to the final list..."
    echo "${OPTION}=INNODB" >> ${OUTPUT_FILE}
    echo "${OPTION}=MYISAM" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--log-output" ]; then
    echoit "  > Adding possible values FILE, TABLE, NONE for option '${OPTION}' to the final list..."
    echo "${OPTION}=FILE" >> ${OUTPUT_FILE}
    echo "${OPTION}=TABLE" >> ${OUTPUT_FILE}
    echo "${OPTION}=NONE" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--log-timestamps" ]; then
    echoit "  > Adding possible values SYSTEM, UTC for option '${OPTION}' to the final list..."
    echo "${OPTION}=UTC" >> ${OUTPUT_FILE}
    echo "${OPTION}=SYSTEM" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--master-info-repository" ]; then
    echoit "  > Adding possible values FILE, TABLE for option '${OPTION}' to the final list..."
    echo "${OPTION}=FILE" >> ${OUTPUT_FILE}
    echo "${OPTION}=TABLE" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--relay-log-info-repository" ]; then
    echoit "  > Adding possible values FILE, TABLE for option '${OPTION}' to the final list..."
    echo "${OPTION}=FILE" >> ${OUTPUT_FILE}
    echo "${OPTION}=TABLE" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--default-storage-engine" -o "${OPTION}" == "--default-tmp-storage-engine" ]; then
    echoit "  > Adding possible values InnoDB, Aria, MyISAM, MEMORY, CSV, Sequence, MERGE, ARCHIVE, BLACKHOLE, FEDERATED, RocksDB, SPIDER for option '${OPTION}' to the final list..."
    if [[ $IS_PXC -eq 1 ]]; then
      echo "${OPTION}=InnoDB" >> ${OUTPUT_FILE}
      echo "${OPTION}=InnoDB" >> ${OUTPUT_FILE}
      echo "${OPTION}=InnoDB" >> ${OUTPUT_FILE}
      echo "${OPTION}=InnoDB" >> ${OUTPUT_FILE}
      echo "${OPTION}=InnoDB" >> ${OUTPUT_FILE}
      echo "${OPTION}=Aria" >> ${OUTPUT_FILE}
      echo "${OPTION}=Aria" >> ${OUTPUT_FILE}
      echo "${OPTION}=MyISAM" >> ${OUTPUT_FILE}
      echo "${OPTION}=MEMORY" >> ${OUTPUT_FILE}
      echo "${OPTION}=RocksDB" >> ${OUTPUT_FILE}
    else
      echo "${OPTION}=InnoDB" >> ${OUTPUT_FILE}
      echo "${OPTION}=InnoDB" >> ${OUTPUT_FILE}
      echo "${OPTION}=InnoDB" >> ${OUTPUT_FILE}
      echo "${OPTION}=InnoDB" >> ${OUTPUT_FILE}
      echo "${OPTION}=InnoDB" >> ${OUTPUT_FILE}
      echo "${OPTION}=Aria" >> ${OUTPUT_FILE}
      echo "${OPTION}=Aria" >> ${OUTPUT_FILE}
      echo "${OPTION}=Aria" >> ${OUTPUT_FILE}
      echo "${OPTION}=MyISAM" >> ${OUTPUT_FILE}
      echo "${OPTION}=MyISAM" >> ${OUTPUT_FILE}
      echo "${OPTION}=MEMORY" >> ${OUTPUT_FILE}
      echo "${OPTION}=MEMORY" >> ${OUTPUT_FILE}
      echo "${OPTION}=CSV" >> ${OUTPUT_FILE}
      echo "${OPTION}=Sequence" >> ${OUTPUT_FILE}
      echo "${OPTION}=MERGE" >> ${OUTPUT_FILE}
      echo "${OPTION}=ARCHIVE" >> ${OUTPUT_FILE}
      echo "${OPTION}=BLACKHOLE" >> ${OUTPUT_FILE}
      echo "${OPTION}=FEDERATED" >> ${OUTPUT_FILE}
      echo "${OPTION}=RocksDB" >> ${OUTPUT_FILE}
      echo "${OPTION}=SPIDER" >> ${OUTPUT_FILE}
    fi
  elif [ "${OPTION}" == "--default-regex-flags" ]; then
    echo "${OPTION}=DOTALL" >> ${OUTPUT_FILE}
    echo "${OPTION}=DUPNAMES" >> ${OUTPUT_FILE}
    echo "${OPTION}=EXTENDED" >> ${OUTPUT_FILE}
    echo "${OPTION}=EXTENDED_MORE" >> ${OUTPUT_FILE}
    echo "${OPTION}=EXTRA" >> ${OUTPUT_FILE}
    echo "${OPTION}=MULTILINE" >> ${OUTPUT_FILE}
    echo "${OPTION}=GREEDY" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--log-error-suppression-list" ]; then
    echoit "  > Adding possible values ER_SERVER_SHUTDOWN_COMPLETE,MY-000001,000001,MY-01,01 for option '${OPTION}' to the final list..."
    echo "${OPTION}=ER_SERVER_SHUTDOWN_COMPLETE" >> ${OUTPUT_FILE}
    echo "${OPTION}=MY-000001" >> ${OUTPUT_FILE}
    echo "${OPTION}=000001" >> ${OUTPUT_FILE}
    echo "${OPTION}=MY-01" >> ${OUTPUT_FILE}
    echo "${OPTION}=01" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--alter-algorithm" ]; then
    echoit "  > Adding possible values DEFAULT, COPY, INPLACE, NOCOPY, INSTANT for option '${OPTION}' to the final list..."
    echo "${OPTION}=DEFAULT" >> ${OUTPUT_FILE}
    echo "${OPTION}=COPY" >> ${OUTPUT_FILE}
    echo "${OPTION}=INPLACE" >> ${OUTPUT_FILE}
    echo "${OPTION}=NOCOPY" >> ${OUTPUT_FILE}
    echo "${OPTION}=INSTANT" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--aria-group-commit" ]; then
    echoit "  > Adding possible values none, hard, soft for option '${OPTION}' to the final list..."
    echo "${OPTION}=none" >> ${OUTPUT_FILE}
    echo "${OPTION}=hard" >> ${OUTPUT_FILE}
    echo "${OPTION}=soft" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--aria-log-dir-path" ]; then
    echoit "  > Adding possible values . (datadir) for option '${OPTION}' to the final list..."
    echo "${OPTION}=." >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--aria-log-purge-type" ]; then
    echoit "  > Adding possible values immediate, external, at_flush for option '${OPTION}' to the final list..."
    echo "${OPTION}=immediate" >> ${OUTPUT_FILE}
    echo "${OPTION}=external" >> ${OUTPUT_FILE}
    echo "${OPTION}=at_flush" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--aria-recover-options" ]; then
    echoit "  > Adding possible values NORMAL, BACKUP, FORCE, QUICK, OFF, BACKUP,QUICK, ALL for option '${OPTION}' to the final list..."
    echo "${OPTION}=NORMAL" >> ${OUTPUT_FILE}
    echo "${OPTION}=BACKUP" >> ${OUTPUT_FILE}
    echo "${OPTION}=FORCE" >> ${OUTPUT_FILE}
    echo "${OPTION}=QUICK" >> ${OUTPUT_FILE}
    echo "${OPTION}=OFF" >> ${OUTPUT_FILE}
    echo "${OPTION}=BACKUP,QUICK" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--aria-stats-method" ]; then
    echoit "  > Adding possible values nulls_equal, nulls_unequal, nulls_ignored for option '${OPTION}' to the final list..."
    echo "${OPTION}=nulls_equal" >> ${OUTPUT_FILE}
    echo "${OPTION}=nulls_unequal" >> ${OUTPUT_FILE}
    echo "${OPTION}=nulls_ignored" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--aria-sync-log-dir" ]; then
    echoit "  > Adding possible values NEVER, NEWFILE, ALWAYS for option '${OPTION}' to the final list..."
    echo "${OPTION}=NEVER" >> ${OUTPUT_FILE}
    echo "${OPTION}=NEWFILE" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALWAYS" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--binlog-row-metadata" ]; then
    echoit "  > Adding possible values NO_LOG, MINIMAL, FULL for option '${OPTION}' to the final list..."
    echo "${OPTION}=NO_LOG" >> ${OUTPUT_FILE}
    echo "${OPTION}=MINIMAL" >> ${OUTPUT_FILE}
    echo "${OPTION}=FULL" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--caching-sha2-password-private-key-path" -o "${OPTION}" == "--caching-sha2-password-public-key-path" ]; then
    echoit "  > Adding possible values empty, private_key.pem for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=private_key.pem" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--character-set-collations" ]; then
    echoit "  > Adding possible values empty, utf8mb4=uca1400_ai_ci, default mapping, utf8mb4=utf8mb4_bin for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=utf8mb4=uca1400_ai_ci" >> ${OUTPUT_FILE}
    echo "${OPTION}=utf8mb3=uca1400_ai_ci,utf8mb4=uca1400_ai_ci,ucs2=uca1400_ai_ci,utf16=uca1400_ai_ci,utf32=uca1400_ai_ci" >> ${OUTPUT_FILE}
    echo "${OPTION}=utf8mb4=utf8mb4_bin" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--column-compression-zlib-strategy" ]; then
    echoit "  > Adding possible values DEFAULT_STRATEGY, FILTERED, HUFFMAN_ONLY, RLE, FIXED for option '${OPTION}' to the final list..."
    echo "${OPTION}=DEFAULT_STRATEGY" >> ${OUTPUT_FILE}
    echo "${OPTION}=FILTERED" >> ${OUTPUT_FILE}
    echo "${OPTION}=HUFFMAN_ONLY" >> ${OUTPUT_FILE}
    echo "${OPTION}=RLE" >> ${OUTPUT_FILE}
    echo "${OPTION}=FIXED" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--create-tmp-table-binlog-formats" ]; then
    echoit "  > Adding possible values STATEMENT, MIXED,STATEMENT, ALL for option '${OPTION}' to the final list..."
    echo "${OPTION}=STATEMENT" >> ${OUTPUT_FILE}
    echo "${OPTION}=MIXED,STATEMENT" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--ft-boolean-syntax" ]; then
    echoit "  > Adding possible values default operator set and variants for option '${OPTION}' to the final list..."
    echo "${OPTION}='+ -><()~*:\"\"&|'" >> ${OUTPUT_FILE}
    echo "${OPTION}='+ -><()~*:\"\"&|@'" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--histogram-type" ]; then
    echoit "  > Adding possible values SINGLE_PREC_HB, DOUBLE_PREC_HB, JSON_HB for option '${OPTION}' to the final list..."
    echo "${OPTION}=SINGLE_PREC_HB" >> ${OUTPUT_FILE}
    echo "${OPTION}=DOUBLE_PREC_HB" >> ${OUTPUT_FILE}
    echo "${OPTION}=JSON_HB" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--init-rpl-role" ]; then
    echoit "  > Adding possible values MASTER, SLAVE for option '${OPTION}' to the final list..."
    echo "${OPTION}=MASTER" >> ${OUTPUT_FILE}
    echo "${OPTION}=SLAVE" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-buffer-pool-filename" ]; then
    echoit "  > Adding possible values ib_buffer_pool, buffer_pool.dump for option '${OPTION}' to the final list..."
    echo "${OPTION}=ib_buffer_pool" >> ${OUTPUT_FILE}
    echo "${OPTION}=buffer_pool.dump" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-compression-algorithm" ]; then
    echoit "  > Adding possible values none, zlib, lz4, lzo, lzma, bzip2, snappy for option '${OPTION}' to the final list..."
    echo "${OPTION}=none" >> ${OUTPUT_FILE}
    echo "${OPTION}=zlib" >> ${OUTPUT_FILE}
    echo "${OPTION}=lz4" >> ${OUTPUT_FILE}
    echo "${OPTION}=lzo" >> ${OUTPUT_FILE}
    echo "${OPTION}=lzma" >> ${OUTPUT_FILE}
    echo "${OPTION}=bzip2" >> ${OUTPUT_FILE}
    echo "${OPTION}=snappy" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-deadlock-report" ]; then
    echoit "  > Adding possible values off, basic, full for option '${OPTION}' to the final list..."
    echo "${OPTION}=off" >> ${OUTPUT_FILE}
    echo "${OPTION}=basic" >> ${OUTPUT_FILE}
    echo "${OPTION}=full" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-instant-alter-column-allowed" ]; then
    echoit "  > Adding possible values never, add_last, add_drop_reorder for option '${OPTION}' to the final list..."
    echo "${OPTION}=never" >> ${OUTPUT_FILE}
    echo "${OPTION}=add_last" >> ${OUTPUT_FILE}
    echo "${OPTION}=add_drop_reorder" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--innodb-linux-aio" ]; then
    echoit "  > Adding possible values auto, io_uring, aio for option '${OPTION}' to the final list..."
    echo "${OPTION}=auto" >> ${OUTPUT_FILE}
    echo "${OPTION}=io_uring" >> ${OUTPUT_FILE}
    echo "${OPTION}=aio" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--lc-messages" -o "${OPTION}" == "--lc-time-names" ]; then
    echoit "  > Adding possible values en_US, ja_JP, de_DE, ru_RU, fr_FR for option '${OPTION}' to the final list..."
    echo "${OPTION}=en_US" >> ${OUTPUT_FILE}
    echo "${OPTION}=ja_JP" >> ${OUTPUT_FILE}
    echo "${OPTION}=de_DE" >> ${OUTPUT_FILE}
    echo "${OPTION}=ru_RU" >> ${OUTPUT_FILE}
    echo "${OPTION}=fr_FR" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--log-basename" ]; then
    echoit "  > Adding possible values mariadb, test for option '${OPTION}' to the final list..."
    echo "${OPTION}=mariadb" >> ${OUTPUT_FILE}
    echo "${OPTION}=test" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--log-ddl-recovery" ]; then
    echoit "  > Adding possible values ddl_recovery.log for option '${OPTION}' to the final list..."
    echo "${OPTION}=ddl_recovery.log" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--log-disabled-statements" ]; then
    echoit "  > Adding possible values empty, slave, sp, slave,sp, ALL for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=slave" >> ${OUTPUT_FILE}
    echo "${OPTION}=sp" >> ${OUTPUT_FILE}
    echo "${OPTION}=slave,sp" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--log-isam" ]; then
    echoit "  > Adding possible values myisam.log for option '${OPTION}' to the final list..."
    echo "${OPTION}=myisam.log" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--log-slow-disabled-statements" ]; then
    echoit "  > Adding possible values empty, admin, call, slave, sp, combination, ALL for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=admin" >> ${OUTPUT_FILE}
    echo "${OPTION}=call" >> ${OUTPUT_FILE}
    echo "${OPTION}=slave" >> ${OUTPUT_FILE}
    echo "${OPTION}=sp" >> ${OUTPUT_FILE}
    echo "${OPTION}=admin,call,slave,sp" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--log-slow-query-file" -o "${OPTION}" == "--slow-query-log-file" ]; then
    echoit "  > Adding possible values slow.log for option '${OPTION}' to the final list..."
    echo "${OPTION}=slow.log" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--log-tc" ]; then
    echoit "  > Adding possible values tc.log for option '${OPTION}' to the final list..."
    echo "${OPTION}=tc.log" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--master-heartbeat-period" ]; then
    echoit "  > Adding possible values 0, 0.5, 1, 30, 4294967 for option '${OPTION}' to the final list..."
    echo "${OPTION}=0" >> ${OUTPUT_FILE}
    echo "${OPTION}=0.5" >> ${OUTPUT_FILE}
    echo "${OPTION}=1" >> ${OUTPUT_FILE}
    echo "${OPTION}=30" >> ${OUTPUT_FILE}
    echo "${OPTION}=4294967" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--master-info-file" ]; then
    echoit "  > Adding possible values master.info, test.info for option '${OPTION}' to the final list..."
    echo "${OPTION}=master.info" >> ${OUTPUT_FILE}
    echo "${OPTION}=test.info" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--master-use-gtid" ]; then
    echoit "  > Adding possible values Slave_Pos, Current_Pos, No for option '${OPTION}' to the final list..."
    echo "${OPTION}=Slave_Pos" >> ${OUTPUT_FILE}
    echo "${OPTION}=Current_Pos" >> ${OUTPUT_FILE}
    echo "${OPTION}=No" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--mhnsw-default-distance" ]; then
    echoit "  > Adding possible values euclidean, cosine for option '${OPTION}' to the final list..."
    echo "${OPTION}=euclidean" >> ${OUTPUT_FILE}
    echo "${OPTION}=cosine" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--myisam-recover-options" ]; then
    echoit "  > Adding possible values DEFAULT, BACKUP, FORCE, QUICK, BACKUP_ALL, OFF, BACKUP,QUICK, ALL for option '${OPTION}' to the final list..."
    echo "${OPTION}=DEFAULT" >> ${OUTPUT_FILE}
    echo "${OPTION}=BACKUP" >> ${OUTPUT_FILE}
    echo "${OPTION}=FORCE" >> ${OUTPUT_FILE}
    echo "${OPTION}=QUICK" >> ${OUTPUT_FILE}
    echo "${OPTION}=BACKUP_ALL" >> ${OUTPUT_FILE}
    echo "${OPTION}=OFF" >> ${OUTPUT_FILE}
    echo "${OPTION}=BACKUP,QUICK" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--note-verbosity" ]; then
    echoit "  > Adding possible values empty, basic, unusable_keys, explain, combination, ALL for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=basic" >> ${OUTPUT_FILE}
    echo "${OPTION}=unusable_keys" >> ${OUTPUT_FILE}
    echo "${OPTION}=explain" >> ${OUTPUT_FILE}
    echo "${OPTION}=basic,unusable_keys,explain" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--old-mode" ]; then
    echoit "  > Adding possible values empty, individual flags and ALL for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=NO_DUP_KEY_WARNINGS_WITH_IGNORE" >> ${OUTPUT_FILE}
    echo "${OPTION}=NO_PROGRESS_INFO" >> ${OUTPUT_FILE}
    echo "${OPTION}=ZERO_DATE_TIME_CAST" >> ${OUTPUT_FILE}
    echo "${OPTION}=UTF8_IS_UTF8MB3" >> ${OUTPUT_FILE}
    echo "${OPTION}=IGNORE_INDEX_ONLY_FOR_JOIN" >> ${OUTPUT_FILE}
    echo "${OPTION}=COMPAT_5_1_CHECKSUM" >> ${OUTPUT_FILE}
    echo "${OPTION}=NO_NULL_COLLATION_IDS" >> ${OUTPUT_FILE}
    echo "${OPTION}=LOCK_ALTER_TABLE_COPY" >> ${OUTPUT_FILE}
    echo "${OPTION}=OLD_FLUSH_STATUS" >> ${OUTPUT_FILE}
    echo "${OPTION}=SESSION_USER_IS_USER" >> ${OUTPUT_FILE}
    echo "${OPTION}=2_DIGIT_YEAR" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--optimizer-disk-read-cost" -o "${OPTION}" == "--optimizer-index-block-copy-cost" -o "${OPTION}" == "--optimizer-key-compare-cost" -o "${OPTION}" == "--optimizer-key-copy-cost" -o "${OPTION}" == "--optimizer-key-lookup-cost" -o "${OPTION}" == "--optimizer-key-next-find-cost" -o "${OPTION}" == "--optimizer-row-copy-cost" -o "${OPTION}" == "--optimizer-row-lookup-cost" -o "${OPTION}" == "--optimizer-row-next-find-cost" -o "${OPTION}" == "--optimizer-rowid-compare-cost" -o "${OPTION}" == "--optimizer-rowid-copy-cost" -o "${OPTION}" == "--optimizer-where-cost" ]; then
    echoit "  > Adding decimal cost values 0, 0.001, 0.1, 1, 10, 100, 10000 for option '${OPTION}' to the final list..."
    echo "${OPTION}=0" >> ${OUTPUT_FILE}
    echo "${OPTION}=0.001" >> ${OUTPUT_FILE}
    echo "${OPTION}=0.1" >> ${OUTPUT_FILE}
    echo "${OPTION}=1" >> ${OUTPUT_FILE}
    echo "${OPTION}=10" >> ${OUTPUT_FILE}
    echo "${OPTION}=100" >> ${OUTPUT_FILE}
    echo "${OPTION}=10000" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--optimizer-disk-read-ratio" ]; then
    echoit "  > Adding ratio values 0, 0.01, 0.1, 0.5, 0.9, 1 for option '${OPTION}' to the final list..."
    echo "${OPTION}=0" >> ${OUTPUT_FILE}
    echo "${OPTION}=0.01" >> ${OUTPUT_FILE}
    echo "${OPTION}=0.1" >> ${OUTPUT_FILE}
    echo "${OPTION}=0.5" >> ${OUTPUT_FILE}
    echo "${OPTION}=0.9" >> ${OUTPUT_FILE}
    echo "${OPTION}=1" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--optimizer-switch" ]; then
    echoit "  > Adding possible values default and tuning variants for option '${OPTION}' to the final list..."
    echo "${OPTION}=default" >> ${OUTPUT_FILE}
    echo "${OPTION}=index_merge=off" >> ${OUTPUT_FILE}
    echo "${OPTION}=materialization=off,semijoin=off" >> ${OUTPUT_FILE}
    echo "${OPTION}=mrr=on,mrr_cost_based=on,mrr_sort_keys=on" >> ${OUTPUT_FILE}
    echo "${OPTION}=rowid_filter=off" >> ${OUTPUT_FILE}
    echo "${OPTION}=condition_pushdown_for_derived=off,condition_pushdown_for_subquery=off" >> ${OUTPUT_FILE}
    echo "${OPTION}=hash_join_cardinality=off" >> ${OUTPUT_FILE}
    echo "${OPTION}=cset_narrowing=off,sargable_casefold=off" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--path" ]; then
    echoit "  > Adding possible values test, test,mysql for option '${OPTION}' to the final list..."
    echo "${OPTION}=test" >> ${OUTPUT_FILE}
    echo "${OPTION}=test,mysql" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--pid-file" ]; then
    echoit "  > Adding possible values mariadb.pid for option '${OPTION}' to the final list..."
    echo "${OPTION}=mariadb.pid" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--plugin-maturity" ]; then
    echoit "  > Adding possible values unknown, experimental, alpha, beta, gamma, stable for option '${OPTION}' to the final list..."
    echo "${OPTION}=unknown" >> ${OUTPUT_FILE}
    echo "${OPTION}=experimental" >> ${OUTPUT_FILE}
    echo "${OPTION}=alpha" >> ${OUTPUT_FILE}
    echo "${OPTION}=beta" >> ${OUTPUT_FILE}
    echo "${OPTION}=gamma" >> ${OUTPUT_FILE}
    echo "${OPTION}=stable" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--relay-log-info-file" ]; then
    echoit "  > Adding possible values relay-log.info for option '${OPTION}' to the final list..."
    echo "${OPTION}=relay-log.info" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--replicate-events-marked-for-skip" ]; then
    echoit "  > Adding possible values REPLICATE, FILTER_ON_SLAVE, FILTER_ON_MASTER for option '${OPTION}' to the final list..."
    echo "${OPTION}=REPLICATE" >> ${OUTPUT_FILE}
    echo "${OPTION}=FILTER_ON_SLAVE" >> ${OUTPUT_FILE}
    echo "${OPTION}=FILTER_ON_MASTER" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--rpl-semi-sync-master-wait-point" ]; then
    echoit "  > Adding possible values AFTER_SYNC, AFTER_COMMIT for option '${OPTION}' to the final list..."
    echo "${OPTION}=AFTER_SYNC" >> ${OUTPUT_FILE}
    echo "${OPTION}=AFTER_COMMIT" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--session-track-system-variables" ]; then
    echoit "  > Adding possible values empty, small list, default list, * (all) for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=autocommit,time_zone" >> ${OUTPUT_FILE}
    echo "${OPTION}=autocommit,character_set_client,character_set_connection,character_set_results,redirect_url,time_zone" >> ${OUTPUT_FILE}
    echo "${OPTION}=*" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--slave-ddl-exec-mode" -o "${OPTION}" == "--slave-exec-mode" ]; then
    echoit "  > Adding possible values STRICT, IDEMPOTENT for option '${OPTION}' to the final list..."
    echo "${OPTION}=STRICT" >> ${OUTPUT_FILE}
    echo "${OPTION}=IDEMPOTENT" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--slave-parallel-mode" ]; then
    echoit "  > Adding possible values optimistic, conservative, aggressive, minimal, none for option '${OPTION}' to the final list..."
    echo "${OPTION}=optimistic" >> ${OUTPUT_FILE}
    echo "${OPTION}=conservative" >> ${OUTPUT_FILE}
    echo "${OPTION}=aggressive" >> ${OUTPUT_FILE}
    echo "${OPTION}=minimal" >> ${OUTPUT_FILE}
    echo "${OPTION}=none" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--slave-transaction-retry-errors" ]; then
    echoit "  > Adding possible values empty, common retryable codes, deadlock-only for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=1158,1159,1160,1161,1205,1213,1429,2013,12701" >> ${OUTPUT_FILE}
    echo "${OPTION}=1213" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--system-versioning-alter-history" ]; then
    echoit "  > Adding possible values ERROR, KEEP for option '${OPTION}' to the final list..."
    echo "${OPTION}=ERROR" >> ${OUTPUT_FILE}
    echo "${OPTION}=KEEP" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--thread-pool-priority" ]; then
    echoit "  > Adding possible values auto, low, high for option '${OPTION}' to the final list..."
    echo "${OPTION}=auto" >> ${OUTPUT_FILE}
    echo "${OPTION}=low" >> ${OUTPUT_FILE}
    echo "${OPTION}=high" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--tls-version" ]; then
    echoit "  > Adding possible values TLSv1.0, TLSv1.1, TLSv1.2, TLSv1.3, combination, ALL for option '${OPTION}' to the final list..."
    echo "${OPTION}=TLSv1.0" >> ${OUTPUT_FILE}
    echo "${OPTION}=TLSv1.1" >> ${OUTPUT_FILE}
    echo "${OPTION}=TLSv1.2" >> ${OUTPUT_FILE}
    echo "${OPTION}=TLSv1.3" >> ${OUTPUT_FILE}
    echo "${OPTION}=TLSv1.2,TLSv1.3" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--use-stat-tables" ]; then
    echoit "  > Adding possible values NEVER, COMPLEMENTARY, PREFERABLY, COMPLEMENTARY_FOR_QUERIES, PREFERABLY_FOR_QUERIES for option '${OPTION}' to the final list..."
    echo "${OPTION}=NEVER" >> ${OUTPUT_FILE}
    echo "${OPTION}=COMPLEMENTARY" >> ${OUTPUT_FILE}
    echo "${OPTION}=PREFERABLY" >> ${OUTPUT_FILE}
    echo "${OPTION}=COMPLEMENTARY_FOR_QUERIES" >> ${OUTPUT_FILE}
    echo "${OPTION}=PREFERABLY_FOR_QUERIES" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--binlog-directory" ]; then
    echoit "  > Adding possible values empty, binlogs for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=binlogs" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--binlog-storage-engine" ]; then
    echoit "  > Adding possible values empty, InnoDB for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=InnoDB" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--default-master-connection" ]; then
    echoit "  > Adding possible values empty, master1 for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=master1" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--master-ssl-ca" -o "${OPTION}" == "--master-ssl-capath" -o "${OPTION}" == "--master-ssl-cert" -o "${OPTION}" == "--master-ssl-cipher" -o "${OPTION}" == "--master-ssl-crl" -o "${OPTION}" == "--master-ssl-crlpath" -o "${OPTION}" == "--master-ssl-key" ]; then
    echoit "  > Adding empty value for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--new-mode" ]; then
    echoit "  > Adding empty value (no currently supported values) for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--redirect-url" ]; then
    echoit "  > Adding possible values empty, mysql://localhost:3306 for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=mysql://localhost:3306" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--ssl-passphrase" ]; then
    echoit "  > Adding empty value for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-OSU-method" ]; then
    echoit "  > Adding possible values TOI, RSU for option '${OPTION}' to the final list..."
    echo "${OPTION}=TOI" >> ${OUTPUT_FILE}
    echo "${OPTION}=RSU" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-SR-store" ]; then
    echoit "  > Adding possible values none, table for option '${OPTION}' to the final list..."
    echo "${OPTION}=none" >> ${OUTPUT_FILE}
    echo "${OPTION}=table" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-allowlist" ]; then
    echoit "  > Adding possible values empty, 127.0.0.1 for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=127.0.0.1" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-certification-rules" ]; then
    echoit "  > Adding possible values strict, optimized for option '${OPTION}' to the final list..."
    echo "${OPTION}=strict" >> ${OUTPUT_FILE}
    echo "${OPTION}=optimized" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-cluster-address" ]; then
    echoit "  > Adding possible values empty, gcomm:// for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=gcomm://" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-cluster-name" ]; then
    echoit "  > Adding possible values my_wsrep_cluster, test_cluster for option '${OPTION}' to the final list..."
    echo "${OPTION}=my_wsrep_cluster" >> ${OUTPUT_FILE}
    echo "${OPTION}=test_cluster" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-data-home-dir" ]; then
    echoit "  > Adding possible values empty, . for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=." >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-dbug-option" ]; then
    echoit "  > Adding empty value for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-debug" ]; then
    echoit "  > Adding possible values NONE, SERVER, TRANSACTION, STREAMING, CLIENT for option '${OPTION}' to the final list..."
    echo "${OPTION}=NONE" >> ${OUTPUT_FILE}
    echo "${OPTION}=SERVER" >> ${OUTPUT_FILE}
    echo "${OPTION}=TRANSACTION" >> ${OUTPUT_FILE}
    echo "${OPTION}=STREAMING" >> ${OUTPUT_FILE}
    echo "${OPTION}=CLIENT" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-forced-binlog-format" ]; then
    echoit "  > Adding possible values MIXED, STATEMENT, ROW, NONE for option '${OPTION}' to the final list..."
    echo "${OPTION}=MIXED" >> ${OUTPUT_FILE}
    echo "${OPTION}=STATEMENT" >> ${OUTPUT_FILE}
    echo "${OPTION}=ROW" >> ${OUTPUT_FILE}
    echo "${OPTION}=NONE" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-mode" ]; then
    echoit "  > Adding possible values empty, individual flags and ALL for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=STRICT_REPLICATION" >> ${OUTPUT_FILE}
    echo "${OPTION}=BINLOG_ROW_FORMAT_ONLY" >> ${OUTPUT_FILE}
    echo "${OPTION}=REQUIRED_PRIMARY_KEY" >> ${OUTPUT_FILE}
    echo "${OPTION}=REPLICATE_MYISAM" >> ${OUTPUT_FILE}
    echo "${OPTION}=REPLICATE_ARIA" >> ${OUTPUT_FILE}
    echo "${OPTION}=DISALLOW_LOCAL_GTID" >> ${OUTPUT_FILE}
    echo "${OPTION}=BF_ABORT_MARIABACKUP" >> ${OUTPUT_FILE}
    echo "${OPTION}=APPLIER_SKIP_FK_CHECKS_IN_IST" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-node-address" ]; then
    echoit "  > Adding possible values empty, 127.0.0.1, 127.0.0.1:4567 for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=127.0.0.1" >> ${OUTPUT_FILE}
    echo "${OPTION}=127.0.0.1:4567" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-node-incoming-address" ]; then
    echoit "  > Adding possible values AUTO, 127.0.0.1 for option '${OPTION}' to the final list..."
    echo "${OPTION}=AUTO" >> ${OUTPUT_FILE}
    echo "${OPTION}=127.0.0.1" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-node-name" ]; then
    echoit "  > Adding possible values node1, node2 for option '${OPTION}' to the final list..."
    echo "${OPTION}=node1" >> ${OUTPUT_FILE}
    echo "${OPTION}=node2" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-notify-cmd" ]; then
    echoit "  > Adding possible values empty, /bin/true for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=/bin/true" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-provider" ]; then
    echoit "  > Adding possible values none, libgalera path for option '${OPTION}' to the final list..."
    echo "${OPTION}=none" >> ${OUTPUT_FILE}
    echo "${OPTION}=/usr/lib/galera/libgalera_smm.so" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-provider-options" ]; then
    echoit "  > Adding possible values empty, pc.weight=2 for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=pc.weight=2" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-reject-queries" ]; then
    echoit "  > Adding possible values NONE, ALL, ALL_KILL for option '${OPTION}' to the final list..."
    echo "${OPTION}=NONE" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL" >> ${OUTPUT_FILE}
    echo "${OPTION}=ALL_KILL" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-sst-auth" ]; then
    echoit "  > Adding possible values empty, root: for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=root:" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-sst-donor" ]; then
    echoit "  > Adding empty value for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-sst-method" ]; then
    echoit "  > Adding possible values rsync, mariabackup, mysqldump for option '${OPTION}' to the final list..."
    echo "${OPTION}=rsync" >> ${OUTPUT_FILE}
    echo "${OPTION}=mariabackup" >> ${OUTPUT_FILE}
    echo "${OPTION}=mysqldump" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-sst-receive-address" ]; then
    echoit "  > Adding possible values AUTO, 127.0.0.1 for option '${OPTION}' to the final list..."
    echo "${OPTION}=AUTO" >> ${OUTPUT_FILE}
    echo "${OPTION}=127.0.0.1" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-start-position" ]; then
    echoit "  > Adding possible values 00000000-0000-0000-0000-000000000000:-1 for option '${OPTION}' to the final list..."
    echo "${OPTION}=00000000-0000-0000-0000-000000000000:-1" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-status-file" ]; then
    echoit "  > Adding possible values empty, wsrep_status for option '${OPTION}' to the final list..."
    echo "${OPTION}=''" >> ${OUTPUT_FILE}
    echo "${OPTION}=wsrep_status" >> ${OUTPUT_FILE}
  elif [ "${OPTION}" == "--wsrep-trx-fragment-unit" ]; then
    echoit "  > Adding possible values bytes, rows, statements for option '${OPTION}' to the final list..."
    echo "${OPTION}=bytes" >> ${OUTPUT_FILE}
    echo "${OPTION}=rows" >> ${OUTPUT_FILE}
    echo "${OPTION}=statements" >> ${OUTPUT_FILE}
  elif [ "${VALUE}" == "TRUE" -o "${VALUE}" == "FALSE" -o "${VALUE}" == "ON" -o "${VALUE}" == "OFF" -o "${VALUE}" == "YES" -o "${VALUE}" == "NO" ]; then
    echoit "  > Adding possible values TRUE/ON/YES/1 and FALSE/OFF/NO/0 (as a universal 1 and 0) for option '${OPTION}' to the final list..."
    echo "${OPTION}=1" >> ${OUTPUT_FILE}
    echo "${OPTION}=0" >> ${OUTPUT_FILE}
  elif [[ "$(echo ${VALUE} | tr -d ' ')" =~ ^-?[0-9]+$ ]]; then
  #elif [[ "$(echo ${VALUE} | tr -d ' ' | tr -d '-')" =~ ^[0-9]+$ ]]; then
  #elif [[ ${VALUE} =~ ^-?[0-9]+$ ]]; then
  #elif [ "$(echo ${VALUE} | sed 's|[0-9]||g')" == "" -a "$(echo ${VALUE} | sed 's|[^0-9]||g')" != "" ]; then  # Fully numerical
    if [ "${VALUE}" != "0" ]; then 
      echoit "  > Adding int values (${VALUE}, -1, 0, 1, 2, 12, 24, 254, 1023, 2047, -1125899906842624, 1125899906842624) for option '${OPTION}' to the final list..."
      echo "${OPTION}=${VALUE}" >> ${OUTPUT_FILE}
    else
      echoit "  > Adding int values (-1, 0, 1, 2, 12, 24, 254, 1023, 2047, -1125899906842624, 1125899906842624) for option '${OPTION}' to the final list..."
    fi
    echo "${OPTION}=0" >> ${OUTPUT_FILE}
    echo "${OPTION}=1" >> ${OUTPUT_FILE}
    echo "${OPTION}=2" >> ${OUTPUT_FILE}
    echo "${OPTION}=12" >> ${OUTPUT_FILE}
    echo "${OPTION}=24" >> ${OUTPUT_FILE}
    echo "${OPTION}=254" >> ${OUTPUT_FILE}
    echo "${OPTION}=1023" >> ${OUTPUT_FILE}
    echo "${OPTION}=2047" >> ${OUTPUT_FILE}
    echo "${OPTION}=-1125899906842624" >> ${OUTPUT_FILE}
    echo "${OPTION}=1125899906842624" >> ${OUTPUT_FILE}
  else
    if [ "${VALUE}" == "" -o "${VALUE}" == "(No" ]; then
      DEFTEXT="no default value"
    else
      DEFTEXT="default='${VALUE}'"
    fi
    echoit "  > ${OPTION} IS NOT COVERED YET (${DEFTEXT}), PLEASE ADD!!!"
    #exit 1
  fi
done < ${TEMP_FILE}
rm -Rf ${TEMP_FILE}

echo "Done! Output file: ${OUTPUT_FILE}"
