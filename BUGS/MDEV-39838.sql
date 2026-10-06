SET GLOBAL log_output='FILE';
CHANGE MASTER 'aaaa' TO master_host='aaaa',master_use_gtid=slave_pos;
SET GLOBAL log_slow_verbosity='full';
SET GLOBAL init_slave='aaaa';
SET GLOBAL long_query_time=0;
SET GLOBAL slow_query_log=1;
START SLAVE 'aaaa';
SET GLOBAL log_output='FILE';

# mysqld options required for replay:  --log-bin --log_output=FILE --log_slow_verbosity=warnings --long_query_time=0 --slow_query_log=1
# Requires standard m/s replication setup
SET SESSION sql_log_bin=0;
CREATE TABLE t1 (a INT);
SET SESSION sql_log_bin=1;
SET SESSION binlog_format=STATEMENT;
INSERT INTO t1 VALUES (1);

# mysqld options required for replay:  --log-bin --log_output=FILE --log_slow_verbosity=warnings --long_query_time=0 --slow_query_log=1 --slave_parallel_threads=2
# Requires standard m/s replication setup
SET SESSION sql_log_bin=0;
CREATE TABLE t1 (a INT);
SET SESSION sql_log_bin=1;
SET SESSION binlog_format=STATEMENT;
INSERT INTO t1 VALUES (1);

SET GLOBAL log_output='FILE';
SET SESSION log_slow_verbosity='warnings';
SET SESSION long_query_time=0;
SET GLOBAL slow_query_log=1;
SET SESSION slow_query_log=1;
SELECT CAST('1a' AS INT);
SELECT * FROM t_missing;
