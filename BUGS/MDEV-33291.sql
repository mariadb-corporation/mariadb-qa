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
