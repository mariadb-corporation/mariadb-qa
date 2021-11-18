#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# TCP = Test Case Prettify
# This script prettifies SQL code towards uppercase, and is made as an aid for testcase handling. It is also used by reducer.sh in one of it's testcase reduction/prettifying trials, and if uncessfull, the original testcase is left.

# NOTES: this script may work less well for SQL containing actual data, as SQL idioms like 'when' are changed to 'WHEN' without regards for wheter such word appears inside a text string or as a SQL idiom. ~/tcp is beta quality. Watch out for: ERROR 1064 (42000): You have an error in your SQL syntax during SQL replay. Even a small error like "COUNT(" vs "COUNT (" can make a testcase non-reproducible. There are also other shortcomings to this aid-tool, for example data text becoming uppercase which may affect reprodicibilty). For every error you find, please improve ~/tcp handling of the same. A common issue is the space in the "COUNT (" example, and such cases are handled near the end of the ~/tcp script! If your ~/tcp parsed testcase does not immediately work, try the original reducer-produced unparsed testcase! Thank you'

if [ -z "${1}" ]; then echo "Assert: please specify testcase to prettify!"; exit 1; fi
if [ ! -f "${1}" -o ! -r "${1}" ]; then echo "Assert: '${1}' is not readable by this script"; exit 1; fi

OPTIONS="$(grep -i '^. mysqld options required for replay' "${1}" | head -n1 | sed "s|. mysqld options required for replay:[ \t]\+..sql_mode=[ \t]*$|SET sql_mode='';|")"
set +H
# Note that there is one shortcoming in deleting '`' on the next line: if a certain keyword is used
# as a name, for example CREATE TABLE (`primary` INT) then removing the '`' will make it an actual
# keyword instead of a name, i.e. CREATE TABLE (PRIMARY INT), and that will fail at the command line
# Adding sed's to change this does not work as we do not know if the name is used elsehwere.
cat "${1}" | tr -d '`' | \
  sed 's|;#.*$|;|;s| ;$|;|g;s|;;$|;|g' | \
  sed 's|^[ ]\+||;s|;[ ]\+$|;|' | \
  sed 's|open|OPEN|gi' | \
  sed 's|div|DIV|gi' | \
  sed 's|execute|EXECUTE|gi' | \
  sed 's|index|INDEX|g' | \
  sed 's|hex|HEX|gi' | \
  sed 's| as | AS |gi' | \
  sed 's|do |DO |gi' | \
  sed 's|convert|CONVERT|gi' | \
  sed 's|int|INT|gi;s|integer|INT|gi' | \
  sed 's|float|FLOAT|gi' | \
  sed 's|real|REAL|gi' | \
  sed 's|check|CHECK|gi' | \
  sed 's|enum|ENUM|gi' | \
  sed 's|varbinary|VARBINARY|gi;s|binary|BINARY|gi' | \
  sed 's|decimal|DECIMAL|gi' | \
  sed 's|numeric|NUMERIC|gi' | \
  sed 's|value|VALUE|gi' | \
  sed 's|extractvalue|EXTRACTVALUE|gi' | \
  sed 's|return|RETURN|gi' | \
  sed 's|returns|RETURNS|gi' | \
  sed 's|constraint|CONSTRAINT|gi' | \
  sed 's|deterministic|DETERMINISTIC|gi' | \
  sed 's|commit|COMMIT|gi' | \
  sed 's|create|CREATE|gi' | \
  sed 's|data|DATA|gi' | \
  sed 's|references|REFERENCES|gi' | \
  sed 's|plugin|PLUGIN|gi' | \
  sed 's|plugins|PLUGINS|gi' | \
  sed 's|local|LOCAL|gi' | \
  sed 's|infile|INFILE|gi' | \
  sed 's|terminated by|TERMINATED BY|gi' | \
  sed 's|table|TABLE|gi' | \
  sed 's|tables|TABLES|gi' | \
  sed 's|view|VIEW|gi' | \
  sed 's|merge|MERGE|gi' | \
  sed 's|status|STATUS|gi' | \
  sed 's|using|USING|gi' | \
  sed 's|distinct|DISTINCT|gi' | \
  sed 's|cascaded|CASCADED|gi' | \
  sed 's|check option|CHECK OPTION|gi' | \
  sed 's|comment|COMMENT|gi' | \
  sed 's|sformat|SFORMAT|gi' | \
  sed 's|md5|MD5|gi' | \
  sed 's|locate|LOCATE|gi' | \
  sed 's|query|QUERY|gi' | \
  sed 's|schedule|SCHEDULE|gi' | \
  sed 's|every|EVERY|gi' | \
  sed 's|minute|MINUTE|gi' | \
  sed 's|hour|HOUR|gi' | \
  sed 's|day|DAY|gi' | \
  sed 's|begin|BEGIN|gi' | \
  sed 's|end|END|gi' | \
  sed 's|ends|ENDS|gi' | \
  sed 's|rollback|ROLLBACK|gi' | \
  sed 's|load|LOAD|gi' | \
  sed 's|separator|SEPARATOR|gi' | \
  sed 's|serial|SERIAL|gi' | \
  sed 's|then|THEN|gi' | \
  sed 's|add|ADD|gi' | \
  sed 's|savepoint|SAVEPOINT|gi' | \
  sed 's|checksum|CHECKSUM|gi' | \
  sed 's|events|EVENTS|gi;s|event|EVENT|gi' | \
  sed 's|procedure|PROCEDURE|gi' | \
  sed 's|function|FUNCTION|gi' | \
  sed 's|install|INSTALL|gi' | \
  sed 's|soname|SONAME|gi' | \
  sed 's|seq|SEQ|gi' | \
  sed 's|sequence|SEQUENCE|gi' | \
  sed 's|exists|EXISTS|gi' | \
  sed 's|help|HELP|gi' | \
  sed 's|like|LIKE|gi' | \
  sed 's|partition|PARTITION|gi' | \
  sed 's|partition by|PARTITION BY|gi' | \
  sed 's|partitions|PARTITIONS|gi' | \
  sed 's|subpartition|SUBPARTITION|gi' | \
  sed 's|subpartitions|SUBPARTITIONS|gi' | \
  sed 's|by |BY |gi' | \
  sed 's|list|LIST|gi' | \
  sed 's|hash|HASH|gi' | \
  sed 's|algorithm|ALGORITHM|gi' | \
  sed 's|inplace|INPLACE|gi' | \
  sed 's|database|DATABASE|gi' | \
  sed 's|where|WHERE|gi' | \
  sed 's|start|START|gi' | \
  sed 's|xa|XA|gi' | \
  sed 's|shutdown|SHUTDOWN|gi' | \
  sed 's|elt|ELT|gi' | \
  sed 's|trim|TRIM|gi' | \
  sed 's|case|CASE|gi' | \
  sed 's|when|WHEN|gi' | \
  sed 's|and|AND|gi' | \
  sed 's|or|OR|gi' | \
  sed 's|else|ELSE|gi' | \
  sed 's|substring_index|SUBSTRING_INDEX|gi' | \
  sed 's|handler|HANDLER|gi' | \
  sed 's|dual|DUAL|gi' | \
  sed 's|all|ALL|gi' | \
  sed 's|call|CALL|gi' | \
  sed 's|flush|FLUSH|gi' | \
  sed 's|with|WITH|gi' | \
  sed 's|recursive|RECURSIVE|gi' | \
  sed 's|dynamic|DYNAMIC|gi' | \
  sed 's|transactional|TRANSACTIONAL|gi' | \
  sed 's|set @@global\.|SET GLOBAL |gi' | \
  sed 's|set @@session\.|SET SESSION |gi' | \
  sed 's|use|USE|gi' | \
  sed 's|concurrent|CONCURRENT|gi' | \
  sed 's|user|USER|gi' | \
  sed 's|host|HOST|gi' | \
  sed 's|password|PASSWORD|gi' | \
  sed 's|natural|NATURAL|gi' | \
  sed 's|join|JOIN|gi' | \
  sed 's|straight|STRAIGHT|gi' | \
  sed 's|backup|BACKUP|gi' | \
  sed 's|alter|ALTER|gi' | \
  sed 's|desc|DESC|gi' | \
  sed 's|change|CHANGE|gi' | \
  sed 's|master|MASTER|gi' | \
  sed 's|sql_thread|SQL_THREAD|gi' | \
  sed 's|io_thread|IO_THREAD|gi' | \
  sed 's|asc|ASC|gi' | \
  sed 's|limit|LIMIT|gi' | \
  sed 's|group by|GROUP BY|gi' | \
  sed 's|count|COUNT|gi' | \
  sed 's| as | AS |gi' | \
  sed 's| to | TO |gi' | \
  sed 's| do | DO |gi' | \
  sed 's| on | ON |gi' | \
  sed 's|unsigned|UNSIGNED|gi' | \
  sed 's|versioning|VERSIONING|gi;s|system versioning|SYSTEM VERSIONING|gi' | \
  sed 's|trigger|TRIGGER|gi' | \
  sed 's|each|EACH|gi' | \
  sed 's|prepare|PREPARE|gi' | \
  sed 's|show|SHOW|gi' | \
  sed 's|row|ROW|gi' | \
  sed 's|grant|GRANT|gi' | \
  sed 's|concat|CONCAT|gi' | \
  sed 's|cast|CAST|gi' | \
  sed 's|use_frm|USE_FRM|gi' | \
  sed 's|after|AFTER|gi' | \
  sed 's|before|BEFORE|gi' | \
  sed 's|foreign|FOREIGN|gi' | \
  sed 's|blob|BLOB|gi' | \
  sed 's|char|CHAR|gi' | \
  sed 's|varchar|VARCHAR|gi' | \
  sed 's|character|CHARACTER|gi' | \
  sed 's|replace|REPLACE|gi' | \
  sed 's|delayed|DELAYED|gi' | \
  sed 's|lock|LOCK|gi' | \
  sed 's|read|READ|gi' | \
  sed 's|write|WRITE|gi' | \
  sed 's|big|BIG|gi' | \
  sed 's|small|SMALL|gi' | \
  sed 's|large|LARGE|gi' | \
  sed 's|medium|MEDIUM|gi' | \
  sed 's|from|FROM|gi' | \
  sed 's|union|UNION|gi' | \
  sed 's|select|SELECT|gi' | \
  sed 's|update|UPDATE|gi' | \
  sed 's|insert|INSERT|gi' | \
  sed 's|rename|RENAME|gi' | \
  sed 's|identified|IDENTIFIED|gi' | \
  sed 's|delete|DELETE|gi' | \
  sed 's|truncate|TRUNCATE|gi' | \
  sed 's|explain|EXPLAIN|gi' | \
  sed 's|extended|EXTENDED|gi' | \
  sed 's|date|DATE|gi' | \
  sed 's|datetime|DATETIME|gi' | \
  sed 's|time|TIME|gi' | \
  sed 's|timestamp|TIMESTAMP|gi' | \
  sed 's|repair|REPAIR|gi' | \
  sed 's|repeat|REPEAT|gi' | \
  sed 's|engine|ENGINE|gi' | \
  sed 's|temporary|TEMPORARY|gi' | \
  sed 's|replicate_do|REPLICATE_DO|gi' | \
  sed 's|order by|ORDER BY|gi' | \
  sed 's|drop|DROP|gi' | \
  sed 's|bit|BIT|gi' | \
  sed 's|set|SET|gi' | \
  sed 's|setval|SETVAL|gi' | \
  sed 's|fulltext|FULLTEXT|gi' | \
  sed 's|default|DEFAULT|gi' | \
  sed 's|session|SESSION|gi' | \
  sed 's|global|GLOBAL|gi' | \
  sed 's|primary|PRIMARY|gi' | \
  sed 's|key|KEY|gi' | \
  sed 's|null|NULL|gi' | \
  sed 's|not |NOT |gi' | \
  sed 's|linestring|LINESTRING|gi' | \
  sed 's|polygon|POLYGON|gi' | \
  sed 's|geometry|GEOMETRY|gi' | \
  sed 's|cache|CACHE|gi' | \
  sed 's|if |IF |gi' | \
  sed 's| in | IN |gi' | \
  sed 's| on | ON |gi' | \
  sed 's| for | FOR |gi' | \
  sed 's|aria|Aria|gi' | \
  sed 's|memory|MEMORY|gi' | \
  sed 's|innodb|InnoDB|gi' | \
  sed 's|myisam|MyISAM|gi' | \
  sed 's|rocksdb|RocksDB|gi' | \
  sed 's|csv|CSV|gi' | \
  sed 's|archive|ARCHIVE|gi' | \
  sed 's|values|VALUES|gi' | \
  sed 's|against|AGAINST|gi' | \
  sed 's|row_format|ROW_FORMAT|gi' | \
  sed 's|key_block_size|KEY_BLOCK_SIZE|gi' | \
  sed 's|compressed|COMPRESSED|gi' | \
  sed 's|InnoDB_|innodb_|g' | \
  sed 's|GLOBAL_|global_|g' | \
  sed 's|least|LEAST|gi' | \
  sed 's|rpad|RPAD|gi' | \
  sed 's|lpad|LPAD|gi' | \
  sed 's|into|INTO|gi' | \
  sed 's|column|COLUMN|gi' | \
  sed 's|left|LEFT|gi' | \
  sed 's|right|RIGHT|gi' | \
  sed 's|threads|THREADS|gi' | \
  sed 's|unique|UNIQUE|gi' | \
  sed 's|point|POINT|gi' | \
  sed 's|variables|VARIABLES|gi' | \
  sed 's|generated|GENERATED|gi' | \
  sed 's|always|ALWAYS|gi' | \
  sed 's|invisible|INVISIBLE|gi' | \
  sed 's|virtual|VIRTUAL|gi' | \
  sed 's|minvalue|MINVALUE|gi' | \
  sed 's|maxvalue|MAXVALUE|gi' | \
  sed 's|increment by|INCREMENT BY|gi' | \
  sed 's|checkpoint|checkpoint|gi' | \
  sed 's|coordinates|coordinates|gi' | \
  sed 's|_\([a-zA-Z]\+\)|_\L\1|gi;s|\([a-zA-Z]\+\)_|\L\1_|gi' | \
  sed 's|json_\([_a-zA-Z]\+\)|JSON_\U\1|gi' | \
  sed 's|\([^\.]\)st_|\1ST_|gi' | \
  sed 's|geomfromtext|GEOMFROMTEXT|gi' | \
  sed 's|ST_\([_a-zA-Z]\+\)|\UST_\1|gi' | \
  sed "s|^. mysqld options required for replay.*|${OPTIONS}|i" | \
  sed 's|crc32|CRC32|g' | \
  sed 's|\t| |g' | \
  sed 's|  | |g' | \
  sed 's| ,|,|g' | \
  sed 's|( |(|g' | \
  sed 's| )|)|g' | \
  sed 's|(| (|g' | \
  sed 's|  | |g' | \
  sed 's| \([A-Z][A-Z][A-Z]\) (| \1(|g' | \
  sed 's|FLOAT[ ]*(|FLOAT(|gi;s|INT[ ]*(|INT(|gi;s|VARBINARY[ ]*(|VARBINARY(|gi;s|TIME[ ]*(|TIME(|gi;s|DECIMAL[ ]*(|DECIMAL(|gi;s|TRIM[ ]*(|TRIM(|gi;s|REAL[ ]*(|REAL(|gi;s|NUMERIC[ ]*(|NUMERIC(|gi;s|KEY[ ]*(|KEY(|gi;' | \
  sed 's|starts|STARTS|gi' | \
  sed 's|interval|INTERVAL|gi' | \
  sed 's|ifnull|IFNULL|gi' | \
  sed 's|rand|RAND|gi' | \
  sed 's|rowid|ROWID|gi' | \
  sed 's|tablespace|TABLESPACE|gi' | \
  sed 's|discard|DISCARD|gi' | \
  sed 's|fts_doc_id|FTS_DOC_ID|gi' | \
  sed 's|mysql\.\([^ ]\+\)|mysql.\L\1|gi' | \
  sed 's|to_days|TO_DAYS|gi' | \
  sed 's|range|RANGE|gi' | \
  sed 's|less than|LESS THAN|gi' | \
  sed 's|auto_increment|AUTO_INCREMENT|gi' | \
  sed 's|column_format|COLUMN_FORMAT|gi' | \
  sed 's|column_create|COLUMN_CREATE|gi' | \
  sed 's|column_get|COLUMN_GET|gi' | \
  sed 's|low_priority|LOW_PRIORITY|gi' | \
  sed 's|row_format|ROW_FORMAT|gi' | \
  sed 's|row_start|ROW_START|gi' | \
  sed 's|row_end|ROW_END|gi' | \
  sed 's|date_add|DATE_ADD|gi' | \
  sed 's|day_second|DAY_SECOND|gi' | \
  sed 's|day_minute|DAY_MINUTE|gi' | \
  sed 's|day_hour|DAY_HOUR|gi' | \
  sed 's|system_time|SYSTEM_TIME|gi' | \
  sed 's|export_set|EXPORT_SET|gi' | \
  sed 's|unix_timestamp|UNIX_TIMESTAMP|gi' | \
  sed 's|key_block_size|KEY_BLOCK_SIZE|gi' | \
  sed 's|sql_big_result|SQL_BIG_RESULT|gi' | \
  sed 's|master_pos_wait|MASTER_POS_WAIT|gi' | \
  sed 's|initial_size|INITIAL_SIZE|gi' | \
  sed 's|user@localhost|user@localhost|gi' | \
  sed 's|root@localhost|root@localhost|gi' | \
  sed 's|@localhost|@localhost|gi' | \
  sed 's|log_bin_trust_function_creators|log_bin_trust_function_creators|gi' | \
  sed 's|\.TABLES|\.tables|gi' | \
  sed 's|first|FIRST|gi' | \
  sed 's|second|SECOND|gi' | \
  sed 's|last|LAST|gi' | \
  sed 's|text|TEXT|gi' | \
  sed 's|date_sub[ ]*(|DATE_SUB(|gi' | \
  sed 's|concat_ws[ ]*(|CONCAT_WS(|gi' | \
  sed 's|greatest[ ]*(|GREATEST(|gi' | \
  sed 's|coalesce[ ]*(|COALESCE(|gi' | \
  sed 's|char[ ]*(|CHAR(|gi' | \
  sed 's|if[ ]*(|IF(|gi' | \
  sed 's|current_user[ ]*(|CURRENT_USER(|gi' | \
  sed 's|mysql\.\([a-z]\+\)|mysql.\L\1|gi' | \
  sed 's|password[ ]*(|PASSWORD(|gi' | \
  sed 's|old_password[ ]*(|OLD_PASSWORD(|gi' | \
  sed 's|make_set[ ]*(|MAKE_SET(|gi' | \
  sed 's|substring_index[ ]*(|SUBSTRING_INDEX(|gi' | \
  sed 's|cast[ ]*(|CAST(|gi' | \
  sed 's|space[ ]*(|SPACE(|gi' | \
  sed 's|now[ ]*(|NOW(|gi' | \
  sed 's|sum[ ]*(|SUM(|gi' | \
  sed 's|min[ ]*(|MIN(|gi' | \
  sed 's|max[ ]*(|MAX(|gi' | \
  sed 's|date_add[ ]*(|DATE_ADD(|gi' | \
  sed 's|year_month|YEAR_MONTH|gi' | \
  sed 's|group_concat[ ]*(|GROUP_CONCAT(|gi' | \
  sed 's|timestamp[ ]*(|TIMESTAMP(|gi' | \
  sed 's|insert_method|INSERT_METHOD|gi' | \
  sed 's|inet_aton|INET_ATON|gi' | \
  sed 's|weight_string|WEIGHT_STRING|gi' | \
  sed 's|count[ ]*(|COUNT(|gi' | \
  sed 's|values[ ]*(|VALUES (|gi' | \
  sed 's|substring[ ]*(|SUBSTRING(|gi' | \
  sed "s|'IN |' IN |gi" | \
  sed 's|AND(|AND (|gi' | \
  sed 's|transforms|transforms|gi' | \
  sed 's|identified by|IDENTIFIED BY|gi' | \
  sed 's|autocommit|autocommit|gi' | \
  sed 's|test\([^ ]*\)|test\L\1|gi' | \
  sed 's|0x\([0-9A-Fa-f]\)|0x\1|gi' | \
  sed 's|)\([a-zA-Z]\+\)|) \1|gi' | \
  sed 's| ()|()|gi' | \
  sed 's|), (|),(|gi' | \
  sed "s|BY''|BY ''|gi" | \
  sed "s|[ ]*=[ ]*|=|gi;s|sql_mode=\([^ ']\)|sql_mode= \1|" | \
  sed 's|[ \t]\+| |g' | \
  sed 's|=on;$|=ON;|g' | \
  sed 's|=off;$|=OFF;|g' | \
  sed 's|  | |gi'

# Templates for copy/paste
#  sed 's|||gi' | \
