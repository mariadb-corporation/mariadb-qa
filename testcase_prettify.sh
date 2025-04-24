#!/bin/bash
# Created by Roel Van de Paar, MariaDB

# TCP = Test Case Prettify
# This script prettifies SQL code towards uppercase, and is made as an aid for testcase handling. It is also used by reducer.sh in one of it's testcase reduction/prettifying trials, and if uncessfull, the original testcase is left.

# NOTES: this script may work less well for SQL containing actual data, as SQL idioms like 'when' are changed to 'WHEN' without regards for wheter such word appears inside a text string or as a SQL idiom. ~/tcp is beta quality. Watch out for: ERROR 1064 (42000): You have an error in your SQL syntax during SQL replay. Even a small error like "COUNT(" vs "COUNT (" can make a testcase non-reproducible. There are also other shortcomings to this aid-tool, for example data text becoming uppercase which may affect reprodicibilty). For every error you find, please improve ~/tcp handling of the same. A common issue is the space in the "COUNT (" example, and such cases are handled near the end of the ~/tcp script! If your ~/tcp parsed testcase does not immediately work, try the original reducer-produced unparsed testcase! Thank you'

if [ -z "${1}" ]; then echo "Assert: please specify testcase to prettify!"; exit 1; fi
if [ ! -f "${1}" -o ! -r "${1}" ]; then echo "Assert: '${1}' is not readable by this script"; exit 1; fi

OPTIONS="$(grep --binary-files=text -i '^. mysqld options required for replay' "${1}" | head -n1 | sed "s|. mysqld options required for replay:[ \t]\+..sql_mode=[ \t]*$|SET sql_mode='';|" | sed "s|. mysqld options required for replay:[ \t]\+..plugin_load_add=ha_rocksdb[ \t]*$|INSTALL SONAME 'ha_rocksdb';|" | sed "s|. mysqld options required for replay:[ \t]\+..sql_mode=[ \t]*..plugin_load_add=ha_rocksdb|SET sql_mode='';\\\nINSTALL SONAME 'ha_rocksdb';|")"
set +H
# Note that there is one shortcoming in deleting '`' on the next line: if a certain keyword is used
# as a name, for example CREATE TABLE (`primary` INT) then removing the '`' will make it an actual
# keyword instead of a name, i.e. CREATE TABLE (PRIMARY INT), and that will fail at the command line
# Adding sed's to change this does not work as we do not know if the name is used elsehwere.
cat "${1}" | tr -d '`' | \
  sed "s|[ \t]\+| |g; \
       s|;#.*$|;|;s| ;$|;|g;s|;;$|;|g; \
       s|^ \+||;s|; \+$|;|; \
       s|srv \"srv\"|SRV \"srv\"|gi; \
       s|do |DO |gi; \
       s|open|OPEN|gi; \
       s|close|CLOSE|gi; \
       s|div|DIV|gi; \
       s|rollup|ROLLUP|gi; \
       s|execute|EXECUTE|gi; \
       s|index|INDEX|g; \
       s|leaves|LEAVES|g; \
       s|immediate|IMMEDIATE|g; \
       s|reverse|REVERSE|gi; \
       s|hex|HEX|gi; \
       s|length|LENGTH|gi; \
       s|scalar|SCALAR|gi; \
       s|declare|DECLARE|gi; \
       s|having|HAVING|gi; \
       s|lead|LEAD|gi; \
       s|analyse|ANALYSE|gi; \
       s|do |DO |gi; \
       s|pointfromtext|POINTFROMTEXT|gi; \
       s|multipointfromtext|MULTIPOINTFROMTEXT|gi; \
       s|json|JSON|gi; \
       s|btree|BTREE|gi; \
       s|sqlexception |SQLEXCEPTION |gi; \
       s|continue |CONTINUE |gi; \
       s|until |UNTIL |gi; \
       s|public|PUBLIC|gi; \
       s|round|ROUND|gi; \
       s|convert|CONVERT|gi; \
       s|persistent|PERSISTENT|gi; \
       s|kill|KILL|gi; \
       s|release|RELEASE|gi; \
       s|int|INT|gi;s|integer|INT|gi; \
       s|float|FLOAT|gi; \
       s|real|REAL|gi; \
       s|check|CHECK|gi; \
       s|spatial|SPATIAL|gi; \
       s|enum|ENUM|gi; \
       s|vector|VECTOR|gi; \
       s|varbinary|VARBINARY|gi;s|binary|BINARY|gi; \
       s|decimal|DECIMAL|gi; \
       s|numeric|NUMERIC|gi; \
       s|value|VALUE|gi; \
       s|server|SERVER|gi; \
       s|wrapper|WRAPPER|gi;s|wrapper \+mysql|WRAPPER mysql|gi; \
       s|options|OPTIONS|gi; \
       s|socket|SOCKET|gi;s|socket.sock|socket.sock|gi; \
       s|extractvalue|EXTRACTVALUE|gi; \
       s|fast|FAST|gi; \
       s|return|RETURN|gi; \
       s|returns|RETURNS|gi; \
       s|constraint|CONSTRAINT|gi; \
       s|deterministic|DETERMINISTIC|gi; \
       s|transaction|TRANSACTION|gi; \
       s|consistent|CONSISTENT|gi; \
       s|snapshot|SNAPSHOT|gi; \
       s|commit|COMMIT|gi; \
       s|committed|COMMITTED|gi; \
       s|uncommitted|UNCOMMITTED|gi; \
       s|isolation|ISOLATION|gi; \
       s|create|CREATE|gi; \
       s|data|DATA|gi; \
       s|over|OVER|gi; \
       s|references|REFERENCES|gi; \
       s|storage|STORAGE|gi; \
       s|disk|DISK|gi; \
       s|plugin|PLUGIN|gi; \
       s|plugins|PLUGINS|gi; \
       s|local|LOCAL|gi; \
       s|infile|INFILE|gi; \
       s|cascade|CASCADE|gi; \
       s|cascaded|CASCADED|gi; \
       s|ALLOCATE|ALLOCATE|gi; \
       s|deallocate|DEALLOCATE|gi; \
       s|duplicate|DUPLICATE|gi; \
       s|terminated by|TERMINATED BY|gi; \
       s|table|TABLE|gi; \
       s|tables|TABLES|gi; \
       s|view|VIEW|gi; \
       s|views|views|gi; \
       s|merge|MERGE|gi; \
       s|status|STATUS|gi; \
       s|using|USING|gi; \
       s|distinct|DISTINCT|gi; \
       s|check option|CHECK OPTION|gi; \
       s|comment|COMMENT|gi; \
       s|format|FORMAT|gi; \
       s|sformat|SFORMAT|gi; \
       s|nextval|NEXTVAL|gi; \
       s|next|NEXT|gi; \
       s|md5|MD5|gi; \
       s|locate|LOCATE|gi; \
       s|history|HISTORY|gi; \
       s|current|CURRENT|gi; \
       s|query|QUERY|gi; \
       s|schedule|SCHEDULE|gi; \
       s|every|EVERY|gi; \
       s|minute|MINUTE|gi; \
       s|hour|HOUR|gi; \
       s|day|DAY|gi; \
       s|week|WEEK|gi; \
       s|month|MONTH|gi; \
       s|year|YEAR|gi; \
       s|dayname|DAYNAME|gi; \
       s|begin|BEGIN|gi; \
       s| in | IN |gi;s| in(| IN(|gi; \
       s|end|END|gi; \
       s|end if|END IF|gi; \
       s|ends|ENDS|gi; \
       s|work|WORK|gi; \
       s|rollback|ROLLBACK|gi; \
       s|load|LOAD|gi; \
       s|load_file|LOAD_FILE|gi; \
       s|separator|SEPARATOR|gi; \
       s|serial|SERIAL|gi; \
       s|then|THEN|gi; \
       s|add|ADD|gi; \
       s|savepoint|SAVEPOINT|gi; \
       s|checksum|CHECKSUM|gi; \
       s|events|EVENTS|gi;s|event|EVENT|gi; \
       s|procedure|PROCEDURE|gi; \
       s|function|FUNCTION|gi; \
       s|install|INSTALL|gi; \
       s|soname|SONAME|gi; \
       s|seq|SEQ|gi; \
       s|sequence|SEQUENCE|gi; \
       s|exists|EXISTS|gi; \
       s|help|HELP|gi; \
       s|like|LIKE|gi; \
       s|partition|PARTITION|gi; \
       s|partition by|PARTITION BY|gi; \
       s|partitions|PARTITIONS|gi; \
       s|subpartition|SUBPARTITION|gi; \
       s|subpartitions|SUBPARTITIONS|gi; \
       s|by |BY |gi; \
       s|process|PROCESS|gi; \
       s|list|LIST|gi; \
       s|hash|HASH|gi; \
       s|algorithm|ALGORITHM|gi; \
       s|inplace|INPLACE|gi; \
       s|database|DATABASE|gi; \
       s|where|WHERE|gi; \
       s|start|START|gi; \
       s|stop|STOP|gi; \
       s|slave|SLAVE|gi; \
       s|xa |XA |gi; \
       s|shutdown|SHUTDOWN|gi; \
       s|elt|ELT|gi; \
       s|trim|TRIM|gi; \
       s|names|NAMES|gi; \
       s|case|CASE|gi; \
       s|when|WHEN|gi; \
       s|and|AND|gi; \
       s|or|OR|gi; \
       s|priority|PRIORITY|gi; \
       s|tbl |TBL |gi; \
       s|else|ELSE|gi; \
       s|substr|SUBSTR|gi; \
       s|substring_index|SUBSTRING_INDEX|gi; \
       s|handler|HANDLER|gi; \
       s|dual|DUAL|gi; \
       s|all|ALL|gi; \
       s|call|CALL|gi; \
       s|flush|FLUSH|gi; \
       s|privileges|PRIVILEGES|gi; \
       s| role | ROLE |gi; \
       s| admin | ADMIN |gi; \
       s|with|WITH|gi; \
       s|without|WITHOUT|gi; \
       s|overlaps|OVERLAPS|gi; \
       s|recursive|RECURSIVE|gi; \
       s|dynamic|DYNAMIC|gi; \
       s|transactional|TRANSACTIONAL|gi; \
       s|set @@global\.|SET GLOBAL |gi; \
       s|set @@session\.|SET SESSION |gi; \
       s|use|USE|gi; \
       s|concurrent|CONCURRENT|gi; \
       s|current|CURRENT|gi; \
       s|user|USER|gi; \
       s|host|HOST|gi; \
       s|password|PASSWORD|gi; \
       s|backup|BACKUP|gi; \
       s|alter|ALTER|gi; \
       s|desc|DESC|gi; \
       s|change|CHANGE|gi; \
       s|master|MASTER|gi; \
       s|asc|ASC|gi; \
       s|as |AS |gi; \
       s|ascii|ASCII|gi; \
       s|limit|LIMIT|gi; \
       s|DELIMITER|DELIMITER|gi; \
       s|group by|GROUP BY|gi; \
       s|count|COUNT|gi; \
       s|unsigned|UNSIGNED|gi; \
       s|versioning|VERSIONING|gi;s|system versioning|SYSTEM VERSIONING|gi; \
       s|trigger|TRIGGER|gi; \
       s|each|EACH|gi; \
       s|prepare|PREPARE|gi; \
       s|show|SHOW|gi; \
       s|row|ROW|gi; \
       s|grant|GRANT|gi; \
       s|grantee|GRANTEE|gi; \
       s|concat|CONCAT|gi; \
       s|cast|CAST|gi; \
       s|use_frm|USE_FRM|gi; \
       s|after|AFTER|gi; \
       s|before|BEFORE|gi; \
       s|foreign|FOREIGN|gi; \
       s|blob|BLOB|gi; \
       s|char|CHAR|gi; \
       s|varchar|VARCHAR|gi; \
       s|character|CHARACTER|gi; \
       s|collate|COLLATE|gi; \
       s|replace|REPLACE|gi; \
       s|delayed|DELAYED|gi; \
       s|lock|LOCK|gi; \
       s|read|READ|gi; \
       s|write|WRITE|gi; \
       s|big|BIG|gi; \
       s|small|SMALL|gi; \
       s|large|LARGE|gi; \
       s|medium|MEDIUM|gi; \
       s|from|FROM|gi; \
       s|union|UNION|gi; \
       s|select|SELECT|gi; \
       s|update|UPDATE|gi; \
       s|insert|INSERT|gi; \
       s|rename|RENAME|gi; \
       s|identified|IDENTIFIED|gi; \
       s|delete|DELETE|gi; \
       s|truncate|TRUNCATE|gi; \
       s|explain|EXPLAIN|gi; \
       s|extended|EXTENDED|gi; \
       s|date|DATE|gi; \
       s|curdate|CURDATE|gi; \
       s|period|PERIOD|gi; \
       s|datetime|DATETIME|gi; \
       s|time|TIME|gi; \
       s|timestamp|TIMESTAMP|gi; \
       s|repair|REPAIR|gi; \
       s|repeat|REPEAT|gi; \
       s|engine|ENGINE|gi; \
       s|temporary|TEMPORARY|gi; \
       s|replicate_do|REPLICATE_DO|gi; \
       s|order by|ORDER BY|gi; \
       s|drop|DROP|gi; \
       s|analyze|ANALYZE|gi; \
       s|bit|BIT|gi; \
       s|set|SET|gi; \
       s|reset|RESET|gi; \
       s|setval|SETVAL|gi; \
       s|fulltext|FULLTEXT|gi; \
       s|default|DEFAULT|gi; \
       s|session|SESSION|gi; \
       s|global|GLOBAL|gi; \
       s|primary|PRIMARY|gi; \
       s|disable|DISABLE|gi; \
       s|key|KEY|gi; \
       s|keys|KEYS|gi; \
       s|null|NULL|gi; \
       s|not |NOT |gi; \
       s|linestring|LINESTRING|gi; \
       s|polygon|POLYGON|gi; \
       s|geometry|GEOMETRY|gi; \
       s|geometrycollection|GEOMETRYCOLLECTION|gi; \
       s|cache|CACHE|gi; \
       s|cycle|CYCLE|gi; \
       s|if |IF |gi; \
       s| in | IN |gi; \
       s| on | ON |gi; \
       s| for | FOR |gi; \
       s|aria|Aria|gi; \
       s|memory|MEMORY|gi; \
       s|innodb|InnoDB|gi; \
       s|spider|Spider|gi; \
       s|spider_|spider_|gi; \
       s|myisam|MyISAM|gi; \
       s|rocksdb|RocksDB|gi; \
       s|csv|CSV|gi; \
       s|archive|ARCHIVE|gi; \
       s|against|AGAINST|gi; \
       s|key_block_size|KEY_BLOCK_SIZE|gi; \
       s|compressed|COMPRESSED|gi; \
       s|InnoDB_|innodb_|g; \
       s|GLOBAL_|global_|g; \
       s|least|LEAST|gi; \
       s|level|LEVEL|gi; \
       s|rpad|RPAD|gi; \
       s|lpad|LPAD|gi; \
       s|into|INTO|gi; \
       s|column|COLUMN|gi; \
       s|columns|COLUMNS|gi; \
       s|left|LEFT|gi; \
       s|right|RIGHT|gi; \
       s|threads|THREADS|gi; \
       s|unique|UNIQUE|gi; \
       s|point|POINT|gi; \
       s|variables|VARIABLES|gi; \
       s|generated|GENERATED|gi; \
       s|always|ALWAYS|gi; \
       s|invisible|INVISIBLE|gi; \
       s|virtual|VIRTUAL|gi; \
       s|path|PATH|gi; \
       s|minvalue|MINVALUE|gi; \
       s|maxvalue|MAXVALUE|gi; \
       s|increment|INCREMENT|gi; \
       s|increment by|INCREMENT BY|gi; \
       s|checkpoint|CHECKPOINT|gi; \
       s|coordinates|coordinates|gi; \
       s|_\([a-zA-Z]\+\)|_\L\1|gi;s|\([a-zA-Z]\+\)_|\L\1_|gi; \
       s|json_\([_a-zA-Z]\+\)|JSON_\U\1|gi; \
       s|\([^\.]\)st_|\1ST_|gi; \
       s|geomfromtext|GEOMFROMTEXT|gi; \
       s|ST_\([_a-zA-Z]\+\)|\UST_\1|gi; \
       s|crc32|CRC32|g; \
       s| ,|,|g; \
       s|( |(|g; \
       s| )|)|g; \
       s|(| (|g; \
       s| \([A-Z][A-Z][A-Z]\) (| \1(|g; \
       s|FLOAT *(|FLOAT(|gi;s|INT *(|INT(|gi;s|VARBINARY *(|VARBINARY(|gi;s|TIME *(|TIME(|gi;s|DECIMAL *(|DECIMAL(|gi;s|TRIM *(|TRIM(|gi;s|REAL *(|REAL(|gi;s|NUMERIC *(|NUMERIC(|gi;s|KEY *(|KEY(|gi;s|SUBSTR *(|SUBSTR(|gi;; \
       s|starts|STARTS|gi; \
       s|intersect|INTERSECT|gi; \
       s|interval|INTERVAL|gi; \
       s|ifnull|IFNULL|gi; \
       s|rand|RAND|gi; \
       s|seed|SEED|gi; \
       s|rowid|ROWID|gi; \
       s|serializable|SERIALIZABLE|gi; \
       s|tablespace|TABLESPACE|gi; \
       s|discard|DISCARD|gi; \
       s|fts_doc_id|FTS_DOC_ID|gi; \
       s|mysql\.\([^ ]\+\)|mysql.\L\1|gi; \
       s|range|RANGE|gi;s|_range|_range|gi; \
       s|less than|LESS THAN|gi; \
       s|column_format|COLUMN_FORMAT|gi; \
       s|column_create|COLUMN_CREATE|gi; \
       s|column_get|COLUMN_GET|gi; \
       s|low_priority|LOW_PRIORITY|gi; \
       s|row_format|ROW_FORMAT|gi; \
       s|row_start|ROW_START|gi; \
       s|row_end|ROW_END|gi; \
       s|use_frm|USE_FRM|gi; \
       s|from_base64[ ]*(|FROM_BASE64(|gi; \
       s|date_add|DATE_ADD|gi; \
       s|date_format|DATE_FORMAT|gi; \
       s|day_second|DAY_SECOND|gi; \
       s|day_minute|DAY_MINUTE|gi; \
       s|day_hour|DAY_HOUR|gi; \
       s|hour_micro|HOUR_MICRO|gi; \
       s|yearweek|YEARWEEK|gi; \
       s|minute_second|MINUTE_SECOND|gi; \
       s|system_time|SYSTEM_TIME|gi; \
       s|export_set|EXPORT_SET|gi; \
       s|unix_timestamp|UNIX_TIMESTAMP|gi; \
       s|key_block_size|KEY_BLOCK_SIZE|gi; \
       s|sql_big_result|SQL_BIG_RESULT|gi; \
       s|master_pos_wait|MASTER_POS_WAIT|gi; \
       s|initial_size|INITIAL_SIZE|gi; \
       s|no_write_to_binlog|NO_WRITE_TO_BINLOG|gi; \
       s|user@localhost|user@localhost|gi; \
       s|root@localhost|root@localhost|gi; \
       s|@localhost|@localhost|gi; \
       s|log_bin_trust_function_creators|log_bin_trust_function_creators|gi; \
       s|\.TABLES|\.tables|gi; \
       s|first|FIRST|gi; \
       s|second|SECOND|gi; \
       s|last|LAST|gi; \
       s|text|TEXT|gi; \
       s|date_sub *(|DATE_SUB(|gi; \
       s|concat_ws *(|CONCAT_WS(|gi; \
       s|coalesce *(|COALESCE(|gi; \
       s|char *(|CHAR(|gi; \
       s|if *(|IF(|gi; \
       s|current_user *(|CURRENT_USER(|gi; \
       s|current_time|CURRENT_TIME|gi; \
       s|current_timestamp|CURRENT_TIMESTAMP|gi; \
       s|mysql\.\([a-z]\+\)|mysql.\L\1|gi; \
       s|password *(|PASSWORD(|gi; \
       s|old_password *(|OLD_PASSWORD(|gi; \
       s|make_set *(|MAKE_SET(|gi; \
       s|makedate *(|MAKEDATE(|gi; \
       s|json_array_insert *(|JSON_ARRAY_INSERT(|gi; \
       s|substring_index *(|SUBSTRING_INDEX(|gi; \
       s|cast *(|CAST(|gi; \
       s|space *(|SPACE(|gi; \
       s|now *(|NOW(|gi; \
       s|sum *(|SUM(|gi; \
       s|min *(|MIN(|gi; \
       s|max *(|MAX(|gi; \
       s|avg *(|AVG(|gi; \
       s|oct *(|OCT(|gi; \
       s|pow *(|POW(|gi; \
       s|div *(|DIV(|gi; \
       s|exp *(|EXP(|gi; \
       s|bin *(|BIN(|gi; \
       s|lead *(|LEAD(|gi; \
       s|extract *(|EXTRACT(|gi; \
       s|date_add *(|DATE_ADD(|gi; \
       s|get_format *(|GET_FORMAT(|gi; \
       s|to_days *(|TO_DAYS(|gi; \
       s|from_days *(|FROM_DAYS(|gi; \
       s|year_month|YEAR_MONTH|gi; \
       s|group_concat *(|GROUP_CONCAT(|gi; \
       s|timestamp *(|TIMESTAMP(|gi; \
       s|insert_method|INSERT_METHOD|gi; \
       s|inet_aton|INET_ATON|gi; \
       s|inet6_aton|INET6_ATON|gi; \
       s|weight_string|WEIGHT_STRING|gi; \
       s|count *(|COUNT(|gi; \
       s|str_to_date *(|STR_TO_DATE(|gi; \
       s|substring *(|SUBSTRING(|gi; \
       s| \+| |g; \
       s|'IN |' IN |gi; \
       s|AND(|AND (|gi; \
       s|floor|FLOOR|gi; \
       s|LEFT *(|LEFT(|gi; \
       s|RIGHT *(|RIGHT(|gi; \
       s|CONV *(|CONV(|gi; \
       s|MONTHNAME *(|MONTHNAME(|gi; \
       s|RAND *(|RAND(|gi; \
       s|join|JOIN|gi; \
       s|straight|STRAIGHT|gi; \
       s|natural|NATURAL|gi; \
       s|transforms|transforms|gi; \
       s|identified by|IDENTIFIED BY|gi; \
       s|autocommit|autocommit|gi; \
       s|test\([^ ]*\)|test\L\1|gi; \
       s|greatest *(|GREATEST(|gi; \
       s|0x\([0-9A-Fa-f]\)|0x\1|gi; \
       s|)\([a-zA-Z]\+\)|) \1|gi; \
       s|) *\([\^\*+%/-]\+\) *(|)\1(|gi; \
       s| *\([\^\*+%/-]\+\) *|\1|gi; \
       s|\([a-zA-Z]\)\([\^\*+%/-]\+\)\([a-zA-Z]\)|\1 \2 \3|gi; \
       s|\*\([a-zA-Z]\)|* \1|gi; \
       s| ()|()|gi; \
       s|), (|),(|gi; \
       s|BY''|BY ''|gi; \
       s|port|PORT|gi; \
       s|portion|PORTION|gi; \
       s| of | OF |gi; \
       s| *= *|=|gi;s|sql_mode=\([^ ']\)|sql_mode= \1|; \
       s|=on;$|=ON;|g; \
       s|=off;$|=OFF;|g; \
       s|ignore|IGNORE|gi; \
       s|row_format|row_format|gi; \
       s|auto_increment|AUTO_INCREMENT|gi; \
       s|auto_increment_offset|AUTO_INCREMENT_OFFSET|gi; \
       s|auto_increment_increment|AUTO_INCREMENT_INCREMENT|gi; \
       s|date_format *(|DATE_FORMAT(|gi; \
       s|time_format *(|TIME_FORMAT(|gi; \
       s|world|world|gi; \
       s|engine innodb|ENGINE=InnoDB|gi; \
       s|engine spider|ENGINE=Spider|gi; \
       s|history|HISTORY|gi;s|_history|_history|gi; \
       s|sql_mode= |sql_mode=|gi; \
       s|semijoin|semijoin|gi; \
       s|transport|transport|gi; \
       s|master_port|master_port|gi; \
       s|performance_schema|performance_schema|gi; \
       s|performance_schema\.\([a-zA-Z]\+\)|performance_schema.\L\1|gi; \
       s|des_encrypt|DES_ENCRYPT|gi; \
       s|des_decrypt|DES_DECRYPT|gi; \
       s|sql_thread|SQL_THREAD|gi; \
       s|io_thread|IO_THREAD|gi; \
       s|column_json *(|COLUMN_JSON(|gi; \
       s|convert *(|CONVERT(|gi; \
       s|analyse *(|ANALYSE(|gi; \
       s|do *(|DO(|gi; \
       s|(VALUE|(value|g; \
       s|( (|((|g;s|) )|))|g; \
       s| \+(\([^)]\+\))VALUES(|(\1) VALUES (|gi; \
       s| \+| |g; \
       s| as | AS |gi; \
       s| to | TO |gi; \
       s| do | DO |gi; \
       s| on | ON |gi; \
       s| mod | MOD |gi; \
       s|cast[ ]*(|CAST(|gi; \
       s|mid[ ]*(|MID(|gi; \
       s|row[ ]*(|ROW(|gi; \
       s|uuid[ ]*(|UUID(|gi; \
       s|values|VALUES|gi; \
       s|values *(|VALUES (|gi; \
       s|JSON_ARRAYAGG[ ]*(|JSON_ARRAYAGG(|gi; \
       s|json_array_add|json_array_add|gi; \
       s|_JOIN_|_join_|gi; \
       s|row_format|ROW_FORMAT|gi; \
       s|innodb_default_row_format|INNODB_DEFAULT_ROW_FORMAT|gi; \
       s|remote_port|REMOTE_PORT|gi; \
       s|pk_name|PK_NAME|gi; \
       s|remote_server|REMOTE_SERVER|gi; \
       s|utc_timestamp|UTC_TIMESTAMP|gi; \
       s|from_unixtime|FROM_UNIXTIME|gi; \
       s|remote_table|REMOTE_TABLE|gi; \
       s|rownum|ROWNUM|gi; \
       s|monitoring_kind|MONITORING_KIND|gi; \
       s|spider_ignore_comments|SPIDER_IGNORE_COMMENTS|gi; \
       s|_INTERVAL|_interval|gi; \
       s|sql_no_cache|SQL_NO_CACHE|gi; \
       s|after_sync|AFTER_SYNC|gi; \
       s|max_execution_time|MAX_EXECUTION_TIME|gi; \
       s|information_schema\.PROCESSLIST|information_schema.processlist|gi; \
       s|DELIMITER;|DELIMITER ;|gi; \
       s|USERSTAT|userstat|gi; \
       s|test / |test/|gi; \
       s|_offset|_offset|gi; \
       s|sleep[ ]*(|SLEEP(|gi; \
       s|^. mysqld options required for replay.*|${OPTIONS}|i"  # mysqld options must be last line

# These seem to be incorrect as they change the server name
#       s|srv \"srv\"|SERVER \"s\"|gi;s|SERVER \"srv\"|SERVER \"s\"|gi;s|SERVER srv |SERVER s |gi; \
#       s|srv 'srv'|SERVER 's'|gi;s|SERVER 'srv'|SERVER 's'|gi;s|SERVER srv |SERVER s |gi; \

# Templates for copy/paste
#       s|||gi; \
