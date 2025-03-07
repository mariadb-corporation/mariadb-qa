SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
CREATE TABLE t(a INT,b INT,c INT) ENGINE=INNODB;
INSERT INTO t VALUES(1,2,3),(4,5,6);
CREATE TABLE t2(a INT,b INT,c INT) ENGINE=INNODB;
XA START 'x';
UPDATE t SET a=20;
SET pseudo_slave_mode=1;
UPDATE t2 SET c=10;
XA END 'x';
XA PREPARE 'x';
CREATE TABLE t3(a INT) ENGINE=INNODB;
XA START '2';
CREATE TEMPORARY TABLE t3(a INT) ENGINE=INNODB;
SET unique_checks=0,foreign_key_checks=0;
INSERT INTO t3 VALUES(0);
SET SESSION server_id=12;
INSERT INTO t3 VALUES(1),(2),(3);
INSERT INTO t2 VALUES(1,2,3),(4,5,6),(7,8,9);

SET innodb_lock_wait_timeout=1;
SET SESSION pseudo_slave_mode=ON;
CREATE TABLE t1 (c INT PRIMARY KEY) ENGINE=InnoDB;
XA START 'a';
--error ER_DUP_ENTRY
INSERT INTO t1 VALUES (1),(1);
XA END 'a';
SET foreign_key_checks=0,unique_checks=0;
XA PREPARE 'a';
CREATE TABLE t2 (c INT) ENGINE=InnoDB PARTITION BY HASH (c) PARTITIONS 4;
XA START 'b';
INSERT INTO t2 VALUES (1);
SELECT * FROM t2;
INSERT INTO t2 VALUES (0);
INSERT INTO t1 VALUES (0);
