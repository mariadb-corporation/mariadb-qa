# mysqld options required for replay:  --log-bin
INSTALL SONAME 'ha_connect';
CREATE TABLE t1 (c INT) ENGINE=InnoDB;
CREATE TABLE t2 (c BINARY, d DATE) ENGINE=Connect PARTITION BY RANGE COLUMNS (c) (PARTITION p VALUES LESS THAN (x'FF'));
INSERT INTO t2 VALUES (0,0);
BEGIN;
INSERT INTO t1 VALUES (1);
DELETE FROM t2;
# CLI: ERROR 1194 (HY000): Table 't2' is marked as crashed and should be repaired
# ERR: [ERROR] mariadbd: Table 't2' is marked as crashed and should be repaired

# mysqld options required for replay: --log-bin 
INSTALL SONAME 'ha_connect';
CREATE TABLE t (c INT,c2 INT,PRIMARY KEY(c2)) ENGINE=Connect PARTITION BY KEY(c2) PARTITIONS 4;
XA START 'a';
INSERT INTO t VALUES (0,0);
SAVEPOINT sp;
DELETE FROM t;
# CLI: ERROR 1194 (HY000): Table 't' is marked as crashed and should be repaired
# ERR: [ERROR] mariadbd: Table 't' is marked as crashed and should be repaired
