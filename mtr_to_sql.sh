#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# USAGE TIP: ./gendirs.sh | xargs -P30 -I{} ~/mariadb-qa/mtr_to_sql.sh {} &

# Information
# - The --binary-files=text option to grep is absolutely essential to avoid output being terminated early
# - Originally, there were two versions of SQL generation, and they could be selected interdependently by passing an option to this script. This new version instead uses both approaches in sequence - i.e. it first adds the SQL as generated by approach #1 (ref below) to the final SQL file, and then proceeds to add the SQL as generated by approach #2
#   This results in a larger, but more varied (and thus better), final SQL file/grammar. The new version also re-parses the generated SQL and adds more storage engine variations.
# - This script no longer creates any RQG grammars; RQG use was deprecated in favor of pquery. For a historical still-working no-longer-maintained version, see mtr_to_sql_RQG.sh
# - Current Filter list
#   - Not scanning for "^REVOKE " commands as these drop access and this hinders CLI/pquery testing. However, REVOKE may work for RQG/yy (TBD)
#   - grep --binary-files=text -viE Inline filters
#     - 'strict': this causes corruption bugs - see http://dev.mysql.com/doc/refman/5.6/en/innodb-parameters.html#sysvar_innodb_checksum_algorithm
#     - 'innodb_track_redo_log_now'  - https://bugs.launchpad.net/percona-server/+bug/1368530
#     - 'innodb_log_checkpoint_now'  - https://bugs.launchpad.net/percona-server/+bug/1369357 (dup of 1368530)
#     - 'innodb_purge_stop_now'      - https://bugs.launchpad.net/percona-server/+bug/1368552
#     - 'innodb_track_changed_pages' - https://bugs.launchpad.net/percona-server/+bug/1368530
#     - global/session debug         - https://bugs.launchpad.net/percona-server/+bug/1372675
# - Ideas for further improvement
#   - Scan original MTR file for multi-line statements and reconstruct (tr '\n' ' ' for example) to avoid half-statements ending up in resulting file

# Internal variables
DIRECTORY="${PWD}"
if [ ! -z "${1}" ]; then
  if [ ! -d "${1}" ]; then
    echo "The 1st option to this script was specified as ${1} however this is not an existing directory"
    exit 1
  fi
  DIRECTORY="${1}"  # Should contain mariadb-test or mysql-test directory as a first level subdirectory
  cd "${DIRECTORY}"
  if [ ! -d "./mariadb-test" -a ! -d "./mysql-test" ]; then
    echo "Assert: neither mariadb-test nor mysql-test was found in ${PWD}"
    exit 1
  fi
fi
RANDOM=$(date +%s%N | cut -b10-19 | sed 's|^[0]\+||')  # RANDOM: Random entropy pool init
RANDOMF=$(echo $RANDOM$RANDOM$RANDOM$RANDOM | sed 's/..\(.........\).*/\1/')
FINAL_SQL=${HOME}/mtr_to_sql${RANDOMF}.sql  # Result SQL grammar (i.e. file name for output generated by this script)
TEMP_SQL="${FINAL_SQL}.tmp"

echoit(){
  echo "[$(date +'%T')] $1"
}

# Setup
rm -f ${TEMP_SQL};  if [ -r ${TEMP_SQL} ]; then echoit "Assert: this script tried to remove ${TEMP_SQL}, but the file is still there afterwards."; exit 1; fi
rm -f ${FINAL_SQL}; if [ -r ${FINAL_SQL} ]; then echoit "Assert: this script tried to remove ${FINAL_SQL}, but the file is still there afterwards."; exit 1; fi
touch ${TEMP_SQL};  if [ ! -r ${TEMP_SQL} ]; then echoit "Assert: this script tried to create ${TEMP_SQL}, but the file was not there afterwards."; exit 1; fi
touch ${FINAL_SQL}; if [ ! -r ${FINAL_SQL} ]; then echoit "Assert: this script tried to create ${FINAL_SQL}, but the file was not there afterwards."; exit 1; fi
echoit "Generating SQL grammar for pquery..."
echoit "* Note this takes ~11 minutes on a very high end (i7/SSD/16GB) machine, and 1h+ on a high end Google cloud instance..."
echoit "Output file: ${FINAL_SQL}"

# Stage 1: Approach #1
echoit "> Stage 1: Generating SQL with approach #1..."
find . -type f \( -name "*.test" -o -name "*.inc" \) -exec cat {} + 2>/dev/null | grep --binary-files=text -ihE "^SELECT |^INSERT |^UPDATE |^DROP |^CREATE |^RENAME |^TRUNCATE |^REPLACE |^START |^SAVEPOINT |^ROLLBACK |^RELEASE |^LOCK |^UNLOCK|^XA |^PURGE |^RESET |^SHOW |^CHANGE |^START |^STOP |^PREPARE |^EXECUTE |^DEALLOCATE |^BEGIN |^DECLARE |^FETCH |^CASE |^IF |^ITERATE |^LEAVE |^LOOP |^REPEAT |^RETURN |^WHILE |^CLOSE |^GET |^RESIGNAL |^SIGNAL |^EXPLAIN |^DESCRIBE |^HELP |^USE |^GRANT |^ANALYZE |^CHECK |^CHECKSUM |^OPTIMIZE |^REPAIR |^INSTALL |^UNINSTALL |^BINLOG |^CACHE |^FLUSH |^KILL |^LOAD |^CALL |^DELETE |^DO |^HANDLER |^LOAD DATA |^LOAD XML |^ALTER |^SET " | \
 grep --binary-files=text -viE "innodb_fil_make_page_dirty_debug|innodb_trx_rseg_n_slots_debug|innodb_spin_wait_delay|innodb_replication_delay|strict|restart_server_args|json_binary::parse_binary|^\-\-|^print|delete.*mysql.user|drop.*mysql.user|update.*mysql.user|where.*user.*root|default_password_lifetime|innodb[-_]track[-_]redo[-_]log[-_]now|innodb[-_]log[-_]checkpoint[-_]now|innodb[-_]purge[-_]stop[-_]now|innodb[-_]track_changed[-_]pages|yfos|set[ @globalsession\.\t]*debug[ \.\t]*=|^[# \t]$|^#" | \
 sed 's|SLEEP[ \t]*([\.0-9]\+)|SLEEP(0.1)|gi' | sed 's///g' | \
 sed 's/.*[^;]$//' | grep --binary-files=text -v "^[ \t]*$" | \
 sed 's/$/ ;;;/' | sed 's/[ \t;]*$/;/' >> ${TEMP_SQL}

# Approach #2
# DEPRECATED: Tabs are filtered, as they are highly likely CLI result output.  sed 's|\t|FILTERTHIS|' | \
# First two sed lines (change | and $$ to ; for Stored Procedures) are significant changes, more review/testing later may show better solutions
echoit "> Stage 2: Generating SQL with approach #2..."
find . -type f \( -name "*.test" -o -name "*.inc" \) -exec cat {} + 2>/dev/null | \
 sed 's/|/;\n/g' | \
 sed 's/$$/;\n/g' | \
 sed 's|^ERROR |FILTERTHIS|i' | \
 sed 's|^Warning|FILTERTHIS|i' | \
 sed 's|^Note|FILTERTHIS|i' | \
 sed 's|^Got one of the listed errors|FILTERTHIS|i' | \
 sed 's|^variable_value|FILTERTHIS|i' | \
 sed 's|^Antelope|FILTERTHIS|i' | \
 sed 's|^Barracuda|FILTERTHIS|i' | \
 sed 's|^count|FILTERTHIS|i' | \
 sed 's|^source.*include.*inc|FILTERTHIS|i' | \
 sed 's|^#|FILTERTHIS|' | \
 sed 's|^\-\-|FILTERTHIS|' | \
 sed 's|^@|FILTERTHIS|' | \
 sed 's|^{|FILTERTHIS|' | \
 sed 's|^\*|FILTERTHIS|' | \
 sed 's|^"|FILTERTHIS|' | \
 sed 's|ENGINE[= \t]*NDB|ENGINE=INNODB|gi' | \
 sed 's|^.$|FILTERTHIS|' | sed 's|^..$|FILTERTHIS|' | sed 's|^...$|FILTERTHIS|' | \
 sed 's|^[-0-9]*$|FILTERTHIS|' | sed 's|^c[0-9]*$|FILTERTHIS|' | sed 's|^t[0-9]*$|FILTERTHIS|' | \
 grep --binary-files=text -v "FILTERTHIS" | tr '\n' ' ' | sed 's|;|;\n|g;s|//|//\n|g;s/END\([|]\+\)/END\1\n/g;' | \
 grep --binary-files=text -viE "innodb_fil_make_page_dirty_debug|innodb_trx_rseg_n_slots_debug|innodb_spin_wait_delay|innodb_replication_delay|default_password_lifetime|restart_server_args|json_binary::parse_binary|^\-\-|^print|^Ob%&0Z_|^E/TB/]o|^no cipher request crashed|^[ \t]*DELIMITER|^[ \t]*KILL|^[ \t]*REVOKE|^[ \t]*[<>{}()\.\@\*\+\^\#\!\\\/\'\`\"\;\:\~\$\%\&\|\+\=0-9]|\\\q|\\\r|\\\u|^[ \t]*.[ \t]*$|^[ \t]*..[ \t]*$|^[ \t]*...[ \t]*$|^[ \t]*\-\-|^[ \t]*while.*let|^[ \t]*let|^[ \t]*while.*connect|^[ \t]*connect|^[ \t]*while.*disconnect|^[ \t]*disconnect|^[ \t]*while.*eval|^[ \t]*while.*find|^[ \t]*find|^[ \t]*while.*exit|^[ \t]*exit|^[ \t]*while.*send|^[ \t]*send|^[ \t]*file_exists|^[ \t]*enable_info|^[ \t]*call mtr.add_suppression|strict|delete.*mysql.user|drop.*mysql.user|update.*mysql.user|where.*user.*root|innodb[-_]track[-_]redo[-_]log[-_]now|innodb[-_]log[-_]checkpoint[-_]now|innodb[-_]purge[-_]stop[-_]now|innodb[-_]fil[-_]make[-_]page[-_]dirty[-_]debug|set[ @globalsession\.\t]*innodb[-_]track_changed[-_]pages[ \.\t]*=|yfos|set[ @globalsession\.\t]*debug[ \.\t]*=|^[# \t]$|^#" | \
 sed 's/$/ ;;;/' | sed 's/[ \t;]\+$/;/' | sed 's|^[ \t]\+||;s|[ \t]\+| |g' | \
 sed 's/^[|]\+ //' | sed 's///g' | \
 sed 's|end//;|end //;|gi' | \
 sed 's| t[0-9]\+ | t1 |gi' | \
 sed 's| m[0-9]\+ | t1 |gi' | \
 sed 's|mysqltest[\.0-9]*@|user@|gi' | \
 sed 's|mysqltest[\.0-9]*||gi' | \
 sed 's|user@|mysqltest@|gi' | \
 sed 's| .*mysqltest.*@| mysqltest@|gi' | \
 sed 's| test.[a-z]\+[0-9]\+[( ]\+| t1 |gi' | \
 sed 's| INTO[ \t]*[a-z]\+[0-9]\+| INTO t1 |gi' | \
 sed 's| TABLE[ \t]*[a-z]\+[0-9]\+\([;( ]\+\)| TABLE t1\1|gi' | \
 sed 's| PROCEDURE[ \t]*[psroc_-]\+[0-9]*[( ]\+| PROCEDURE p1(|gi' | \
 sed 's| FROM[ \t]*[a-z]\+[0-9]\+| FROM t1 |gi' | \
 sed 's|DROP PROCEDURE IF EXISTS .*;|DROP PROCEDURE IF EXISTS p1;|gi' | \
 sed 's|CREATE PROCEDURE.*BEGIN END;|CREATE PROCEDURE p1() BEGIN END;|gi' | \
 sed 's|^USE .*|USE test;|gi' | \
 sed 's|SLEEP[ \t]*([\.0-9]\+)|SLEEP(0.1)|gi' | \
 grep --binary-files=text -v "/^[ \t]*$" >> ${TEMP_SQL}

# Grammar variations
echoit "> Stage 3: Adding grammar variations..."
cat ${TEMP_SQL} >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*InnoDB"       | sed 's|InnoDB|Aria|gi'                >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*InnoDB"       | sed 's|InnoDB|MyISAM|gi'              >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*InnoDB"       | sed 's|InnoDB|MEMORY|gi'              >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*InnoDB"       | sed 's|InnoDB|SEQUENCE|gi'            >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*InnoDB"       | sed 's|InnoDB|RocksDB|gi'             >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*InnoDB"       | sed 's|InnoDB|TokuDB|gi'              >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MyISAM"       | sed 's|MyISAM|Aria|gi'                >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MyISAM"       | sed 's|MyISAM|InnoDB|gi'              >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MyISAM"       | sed 's|MyISAM|MEMORY|gi'              >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MyISAM"       | sed 's|MyISAM|SEQUENCE|gi'            >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MyISAM"       | sed 's|MyISAM|RocksDB|gi'             >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MyISAM"       | sed 's|MyISAM|TokuDB|gi'              >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MEMORY"       | sed 's|MEMORY|Aria|gi'                >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MEMORY"       | sed 's|MEMORY|MyISAM|gi'              >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MEMORY"       | sed 's|MEMORY|InnoDB|gi'              >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MEMORY"       | sed 's|MEMORY|SEQUENCE|gi'            >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MEMORY"       | sed 's|MEMORY|RocksDB|gi'             >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MEMORY"       | sed 's|MEMORY|TokuDB|gi'              >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*CSV"          | sed 's|CSV|Aria|gi'                   >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*CSV"          | sed 's|CSV|MyISAM|gi'                 >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*CSV"          | sed 's|CSV|InnoDB|gi'                 >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*CSV"          | sed 's|CSV|MEMORY|gi'                 >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*CSV"          | sed 's|CSV|SEQUENCE|gi'               >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*CSV"          | sed 's|CSV|RocksDB|gi'                >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*CSV"          | sed 's|CSV|TokuDB|gi'                 >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*Aria"         | sed 's|Aria|MyISAM|gi'                >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*Aria"         | sed 's|Aria|InnoDB|gi'                >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*Aria"         | sed 's|Aria|MEMORY|gi'                >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*Aria"         | sed 's|Aria|SEQUENCE|gi'              >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*Aria"         | sed 's|Aria|RocksDB|gi'               >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*Aria"         | sed 's|Aria|TokuDB|gi'                >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*SEQUENCE"     | sed 's|SEQUENCE|Aria|gi'              >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*SEQUENCE"     | sed 's|SEQUENCE|MyISAM|gi'            >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*SEQUENCE"     | sed 's|SEQUENCE|InnoDB|gi'            >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*SEQUENCE"     | sed 's|SEQUENCE|MEMORY|gi'            >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*SEQUENCE"     | sed 's|SEQUENCE|RocksDB|gi'           >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*SEQUENCE"     | sed 's|SEQUENCE|TokuDB|gi'            >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MRG_MyISAM"   | sed 's|ENGINE.*|ENGINE=Aria;|gi'      >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MRG_MyISAM"   | sed 's|ENGINE.*|ENGINE=MyISAM;|gi'    >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MRG_MyISAM"   | sed 's|ENGINE.*|ENGINE=InnoDB;|gi'    >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MRG_MyISAM"   | sed 's|ENGINE.*|ENGINE=MEMORY;|gi'    >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MRG_MyISAM"   | sed 's|ENGINE.*|ENGINE=SEQUENCE;|gi'  >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MRG_MyISAM"   | sed 's|ENGINE.*|ENGINE=RocksDB;|gi'   >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*MRG_MyISAM"   | sed 's|ENGINE.*|ENGINE=TokuDB;|gi'    >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*Merge.*UNION" | sed 's|ENGINE.*|ENGINE=Aria;|gi'      >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*Merge.*UNION" | sed 's|ENGINE.*|ENGINE=MyISAM;|gi'    >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*Merge.*UNION" | sed 's|ENGINE.*|ENGINE=InnoDB;|gi'    >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*Merge.*UNION" | sed 's|ENGINE.*|ENGINE=MEMORY;|gi'    >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*Merge.*UNION" | sed 's|ENGINE.*|ENGINE=SEQUENCE;|gi'  >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*Merge.*UNION" | sed 's|ENGINE.*|ENGINE=RocksDB;|gi'   >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "ENGINE.*Merge.*UNION" | sed 's|ENGINE.*|ENGINE=TokuDB;|gi'    >> ${FINAL_SQL}
cat ${TEMP_SQL} | grep --binary-files=text -i "DROP TABLE t1" | head -n 3000 >> ${FINAL_SQL}   # Ensure plenty of DROP TABLE t1
cat ${TEMP_SQL} | grep --binary-files=text -i "DROP TABLE t1" | head -n 3000 | sed 's|DROP TABLE t1|DROP VIEW v1|gi' >> ${FINAL_SQL} # Ensure plenty of DROP VIEW v1
sed -i "s|\(CREATE.*VIEW.*\)t1\(.*\)|\1v1\2|gi" ${FINAL_SQL}  # Avoid views with name t1

# Shuffle final grammar
echoit "> Stage 4: Shuffling final grammar..."
rm -f ${TEMP_SQL}; if [ -r ${TEMP_SQL} ]; then echoit "Assert: this script tried to remove ${TEMP_SQL}, but the file is still there afterwards."; exit 1; fi
mv ${FINAL_SQL} ${TEMP_SQL}; if [ ! -r ${TEMP_SQL} ]; then echoit "Assert: this script tried to mv ${FINAL_SQL} ${TEMP_SQL}, but the ${TEMP_SQL} file was not there afterwards."; exit 1; fi; if [ -r ${FINAL_SQL} ]; then echoit "Assert: this script tried to mv ${FINAL_SQL} ${TEMP_SQL}, but the ${FINAL_SQL} file is still there afterwards."; exit 1; fi
shuf --random-source=/dev/urandom ${TEMP_SQL} >> ${FINAL_SQL}
rm -f ${TEMP_SQL}; if [ -r ${TEMP_SQL} ]; then echoit "Assert: this script tried to remove ${TEMP_SQL}, but the file is still there afterwards."; exit 1; fi

echoit "Done! Generated ${FINAL_SQL} for use with pquery/pquery-run.sh"
