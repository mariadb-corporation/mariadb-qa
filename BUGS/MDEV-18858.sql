SET debug_dbug="+d,test_completely_invisible,test_invisible_index";
CREATE TABLE t1 (i INT) PARTITION BY KEY (i) PARTITIONS 2;
SET debug_dbug="";
CREATE TABLE t2 (i INT);
ALTER TABLE t1 EXCHANGE PARTITION p1 WITH TABLE t2;

CREATE TABLE t1 (a INT, b CHAR(20), UNIQUE KEY (b) USING HASH) ENGINE=InnoDB PARTITION BY KEY (b);
INSERT INTO t1 VALUES (1, 'x');
CREATE TABLE t2 (a INT, b CHAR(20), UNIQUE KEY (b)) ENGINE=InnoDB;
ALTER TABLE t1 EXCHANGE PARTITION p0 WITH TABLE t2;
FLUSH TABLES;
SELECT * FROM t1;
SELECT * FROM t2;
#CLI: ERROR 1194 (HY000): Table 't1' is marked as crashed and should be repaired
#CLI: ERROR 1194 (HY000): Table 't2' is marked as crashed and should be repaired
#ERR: [Warning] InnoDB: Table test/t1#P#p0 contains 2 user defined columns in InnoDB, but 3 columns in MariaDB. Please check INFORMATION_SCHEMA.INNODB_SYS_COLUMNS and https://mariadb.com/docs/server/server-usage/storage-engines/innodb/innodb-troubleshooting/innodb-data-dictionary-troubleshooting for how to resolve the issue.
#ERR: [ERROR] mariadbd: Table 't1' is marked as crashed and should be repaired
#ERR: [Warning] InnoDB: Table test/t2 contains 3 user defined columns in InnoDB, but 2 columns in MariaDB. Please check INFORMATION_SCHEMA.INNODB_SYS_COLUMNS and https://mariadb.com/docs/server/server-usage/storage-engines/innodb/innodb-troubleshooting/innodb-data-dictionary-troubleshooting for how to resolve the issue.
#ERR: [ERROR] mariadbd: Table 't2' is marked as crashed and should be repaired

CREATE TABLE t1 (a INT, b CHAR(20), UNIQUE KEY (b) USING HASH) ENGINE=MyISAM PARTITION BY KEY (b);
INSERT INTO t1 VALUES (1, 'x');
CREATE TABLE t2 (a INT, b CHAR(20), UNIQUE KEY (b)) ENGINE=MyISAM;
ALTER TABLE t1 EXCHANGE PARTITION p0 WITH TABLE t2;
FLUSH TABLES;
SELECT * FROM t1;
#CLI: ERROR 1030 (HY000): Got error 190 "Incompatible key or row definition between the MariaDB .frm file and the information in the storage engine. You can try REPAIR TABLE ... USE_FRM possibly followed by ALTER TABLE ... FORCE or dump and restore the table to fix this" from storage engine MyISAM
#ERR: - (no error)

CREATE TABLE t1 (a INT, b CHAR(20), UNIQUE KEY (b) USING HASH) ENGINE=MyISAM PARTITION BY KEY (b);
INSERT INTO t1 VALUES (1, 'x');
CREATE TABLE t2 LIKE t1;
ALTER TABLE t2 REMOVE PARTITIONING;
ALTER TABLE t1 EXCHANGE PARTITION p0 WITH TABLE t2;
FLUSH TABLES;
SELECT * FROM t1;
#CLI: ERROR 1030 (HY000): Got error 190 "Incompatible key or row definition between the MariaDB .frm file and the information in the storage engine. You can try REPAIR TABLE ... USE_FRM possibly followed by ALTER TABLE ... FORCE or dump and restore the table to fix this" from storage engine MyISAM
#ERR: - (no error)

CREATE TABLE t1 (a INT, b CHAR(20), UNIQUE KEY (a, b) USING HASH) ENGINE=InnoDB PARTITION BY RANGE (a) (PARTITION p0 VALUES LESS THAN (10));
CREATE TABLE t2 (a INT, b CHAR(20), UNIQUE KEY (a, b)) ENGINE=InnoDB;
INSERT INTO t2 VALUES (15, 'y');
ALTER TABLE t1 CONVERT TABLE t2 TO PARTITION p1 VALUES LESS THAN (20);
FLUSH TABLES;
SELECT * FROM t1;
#CLI: ERROR 1194 (HY000): Table 't1' is marked as crashed and should be repaired
#ERR: [Warning] InnoDB: Table test/t1#P#p1 contains 2 user defined columns in InnoDB, but 3 columns in MariaDB. Please check INFORMATION_SCHEMA.INNODB_SYS_COLUMNS and https://mariadb.com/docs/server/server-usage/storage-engines/innodb/innodb-troubleshooting/innodb-data-dictionary-troubleshooting for how to resolve the issue.
#ERR: [ERROR] mariadbd: Table 't1' is marked as crashed and should be repaired

CREATE TABLE t1 (a INT, b CHAR(20), UNIQUE KEY (b) USING HASH) ENGINE=InnoDB PARTITION BY KEY (b);
INSERT INTO t1 VALUES (1, 'x');
CREATE TABLE t2 (a INT, b CHAR(20), UNIQUE KEY (b) USING HASH) ENGINE=InnoDB;
ALTER TABLE t1 EXCHANGE PARTITION p0 WITH TABLE t2;
#CLI: ERROR 1736 (HY000): Tables have different definitions
#ERR: - (no error)
