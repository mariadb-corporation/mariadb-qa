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
