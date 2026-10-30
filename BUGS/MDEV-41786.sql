SET sql_mode= 'NO_BACKSLASH_ESCAPES';
CREATE TABLE t1 (id INT) PARTITION BY RANGE (id) (PARTITION p VALUES LESS THAN (MAXVALUE) COMMENT='O''Hara');
#CLI: ERROR 1064 (42000): You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' ENGINE = InnoDB)' at line 2; expected no error
#ERR: - (no error)

SET sql_mode= DEFAULT;
CREATE TABLE t2 (a INT) PARTITION BY HASH (a) (PARTITION p0, PARTITION p1 COMMENT 'it''s');
INSERT INTO t2 VALUES (1), (2);
FLUSH TABLES;
SET sql_mode= 'NO_BACKSLASH_ESCAPES';
SELECT COUNT(*) FROM t2;
#CLI: ERROR 1064 (42000): You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' ENGINE = InnoDB)' at line 3; expected 2
#ERR: - (no error)

SET sql_mode= DEFAULT;
CREATE TABLE t3 (c VARCHAR(5)) ENGINE=InnoDB PARTITION BY LIST COLUMNS (c) (PARTITION p0 VALUES IN ('', 'a'), PARTITION p1 DEFAULT);
INSERT INTO t3 VALUES (''), ('a'), ('b');
FLUSH TABLES;
SET sql_mode= 'EMPTY_STRING_IS_NULL';
ALTER TABLE t3 ADD COLUMN d INT;
SET sql_mode= DEFAULT;
SELECT COUNT(*) FROM t3 WHERE c = '';
#CLI: 0; expected 1
#ERR: - (no error)

SET sql_mode= DEFAULT;
CREATE TABLE t4 (a INT) PARTITION BY HASH (a) (PARTITION p0 COMMENT 'x\\y', PARTITION p1);
FLUSH TABLES;
SET sql_mode= 'NO_BACKSLASH_ESCAPES';
ALTER TABLE t4 ADD COLUMN b INT;
SET sql_mode= DEFAULT;
SELECT HEX(PARTITION_COMMENT) FROM INFORMATION_SCHEMA.PARTITIONS WHERE TABLE_SCHEMA='test' AND TABLE_NAME='t4' AND PARTITION_NAME='p0';
#CLI: 785C5C79; expected 785C79
#ERR: - (no error)

SET sql_mode= DEFAULT;
CREATE TABLE t5 (c VARCHAR(5)) PARTITION BY LIST COLUMNS (c) (PARTITION p0 VALUES IN (''), PARTITION p1 VALUES IN (NULL));
INSERT INTO t5 VALUES (''), (NULL);
FLUSH TABLES;
SET sql_mode= 'EMPTY_STRING_IS_NULL';
SELECT COUNT(*) FROM t5;
#CLI: ERROR 1495 (HY000): Multiple definition of same constant in list partitioning; expected 2
#ERR: - (no error)

SET sql_mode= DEFAULT;
CREATE TABLE t6 (c VARCHAR(5)) PARTITION BY RANGE COLUMNS (c) (PARTITION p0 VALUES LESS THAN (''), PARTITION p1 VALUES LESS THAN (MAXVALUE));
INSERT INTO t6 VALUES ('a');
FLUSH TABLES;
SET sql_mode= 'EMPTY_STRING_IS_NULL';
SELECT COUNT(*) FROM t6;
#CLI: ERROR 1566 (HY000): Not allowed to use NULL value in VALUES LESS THAN; expected 1
#ERR: - (no error)

SET sql_mode= 'NO_BACKSLASH_ESCAPES';
CREATE TABLE t7 (id INT) PARTITION BY RANGE (id) (PARTITION p VALUES LESS THAN (100));
ALTER TABLE t7 ADD PARTITION (PARTITION q VALUES LESS THAN (200) COMMENT='O''Hara');
SELECT COUNT(*) FROM t7;
#CLI: ERROR 1064 (42000): You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' ENGINE = InnoDB)' at line 3; expected 0
#ERR: - (no error)
