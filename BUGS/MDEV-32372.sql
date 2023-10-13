# mysqld options required for replay: --slave-parallel-threads=65
ALTER TABLE mysql.gtid_slave_pos DROP PRIMARY KEY;
CREATE TABLE t (c1 INT) ENGINE=InnoDB;
INSERT INTO t VALUES (1);
ALTER TABLE t ADD COLUMN c INT;

# mysqld options required for replay: --slave-parallel-threads=65
ALTER TABLE mysql.gtid_slave_pos DROP PRIMARY KEY;
CREATE TABLE t(c1 INT) DEFAULT CHARSET=ujis;
INSERT INTO t VALUES (0);
ALTER TABLE t ADD COLUMN c INT;

