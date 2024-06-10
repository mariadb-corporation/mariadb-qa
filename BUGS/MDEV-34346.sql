# MASTER_EXTRA="--log_bin=binlog --binlog_format=STATEMENT"
# SLAVE_EXTRA="--slave-parallel-threads=10 --slave_skip_errors=ALL"
SET sql_mode='';
CREATE TABLE t (c INT) ENGINE=InnoDB;
INSERT INTO t VALUES (REPEAT (0,200000));
INSERT INTO t SELECT * FROM t;
INSERT INTO t VALUES (1);
