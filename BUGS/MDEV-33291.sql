# Requires standard master/slave setup
CREATE TABLE t (c VARCHAR(2000) BINARY CHARACTER SET 'utf8') ENGINE=InnoDB;
ALTER TABLE t ADD UNIQUE (c);
SELECT c FROM t;
DELETE FROM mysql.innodb_table_stats;

# Requires standard master/slave setup and binlog_format=ROW on master
SET sql_mode='';
RESET MASTER;
CREATE TABLE t1(c INT);
GRANT ALL ON a.* to a;
CREATE TABLE t2(c INT);
DELETE FROM mysql.db;
SELECT SLEEP(2);

# Requires standard master/slave setup and binlog_format=ROW on master
SET sql_mode='';
CREATE TABLE t2 (c INT(1) ZEROFILL,c2 CHAR(1) CHARACTER SET 'utf8' COLLATE 'utf8_bin',c3 TIMESTAMP(1),KEY(c));
RESET MASTER;
INSERT INTO t2 VALUES (+1, (-1+PI()) DIV(ASIN (1)* CONV(-1,0,-1)%'w!N5Va?>wF9Gi}w0jXmz8O - g="9f2+,!>ht!)&gCH;,JZk[^fd$* Q3h!h{phYTBHsh3IN7RX3,_3cCEptYkB3oN0$K'),'D$2/m6I1?r6@x<RcP}M{7VTMi6M9"Qd1G9NZ3C"qRPCK$r * y.di~h"$Hx[ (h# (rt@6{t@ysui#b@Ia#tvCQWHxF[2ssqMe=AFjOwiPxNajl4_tiko');
SET GLOBAL binlog_checksum=NONE;
UPDATE t2 SET c2=+1;

# Requires standard master/slave setup and binlog_format=ROW on master. Execute SQL on the master.
SET sql_mode='';
CREATE TABLE t1 (col VARCHAR(10)) ENGINE=InnoDB;
RESET MASTER;
INSERT INTO t1 VALUES (1);
SET GLOBAL binlog_checksum=NONE;
DELETE FROM t1;

# Requires standard master/slave setup. Execute SQL on the master. Works with RBR, SBR, MBR.
CREATE TABLE t1 (c1 INT) PARTITION BY RANGE (c1) (PARTITION p0 VALUES LESS THAN (7));
RESET MASTER;
DROP TABLE t1;
CREATE TABLE t1 (c1 INT);
CREATE TABLE t2 (c1 INT);
CREATE TABLE t3 (c1 INT);
CREATE TABLE t4 (c1 INT);
INSERT INTO t1 VALUES (1+75);

# Requires standard master/slave setup. Execute SQL on the master. Requires RBR
# Likely another symptom of 'RESET MASTER' before improvement patch; slave becomes inconsistent; not added to bug. Retest after patch
CREATE TABLE t2 (c INT PRIMARY KEY) ENGINE=MyISAM;
RESET MASTER;
CREATE TABLE t (c INT) ENGINE=MyISAM;
DROP TABLE t2;
ALTER TABLE t RENAME TO t2;
CREATE TEMPORARY TABLE t (c INT) ENGINE=MyISAM;
CREATE TABLE t (c INT) INSERT_METHOD=LAST UNION=(t) ENGINE=MyISAM;
CREATE TABLE t4 (c INT) ENGINE=MyISAM;
INSERT INTO t VALUES(NULL);
INSERT INTO t VALUES();
INSERT INTO t2 SELECT * FROM t;
# [ERROR] Slave SQL: Could not execute Write_rows_v1 event on table test.t2; Column 'c' cannot be null, Error_code: 1048; Column 'c' cannot be null, Error_code: 1048; Duplicate entry '0' for key 'PRIMARY', Error_code: 1062; handler error HA_ERR_FOUND_DUPP_KEY; the event's master log binlog.000001, end_log_pos 1295, Gtid 0-1-6, Internal MariaDB error code: 1062
# [Warning] Slave: Column 'c' cannot be null Error_code: 1048
# [Warning] Slave: Column 'c' cannot be null Error_code: 1048
# [Warning] Slave: Duplicate entry '0' for key 'PRIMARY' Error_code: 1062
# [ERROR] Error running query, slave SQL thread aborted. Fix the problem, and restart the slave SQL thread with "SLAVE START". We stopped at log 'binlog.000001' position 1120; GTID position '0-1-5'

SET SESSION max_error_count=-1;
CREATE TABLE t1 (a INT);
BINLOG ' SOgWTg8CAAAAbgAAAHIAAAAAAAQANS42LjMtbTUtZGVidWctbG9nAAAAAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAABI6BZOEzgNAAgAEgAEBAQEEgAAVgAEGggAAAAICAgCAAAAAAVAYI8=';
binlog 'bBf2ZBMBAAAANAAAAHUkAAAAAHEAAAAAAAEABHRlc3QAAnQxAAQDDw8IBP0C4h0AaTGFIg==bBf2ZBgBAAAASAAAAL0kAAAAAHEAAAAAAAEABP//8I + kAAABAGIBAGWuv1VNCQAAAPBuWwAAAQBiAQBlrr9VTQkAAADxS9Lu';
# CLI: ERROR 1032 (HY000): Can't find record in 't1'
# ERR: [ERROR] mariadbd: Can't find record in 't1'
# ERR: [ERROR]  BINLOG_BASE64_EVENT: Could not execute Update_rows_v1 event on table test.t1; handler error HA_ERR_END_OF_FILE; the event's master log FIRST, end_log_pos 9405, Internal MariaDB error code: 1032
