SET unique_checks=0,foreign_key_checks=0;
CREATE TABLE t1 (c INT) ENGINE=InnoDB;
ALTER TABLE t1 ADD CONSTRAINT cst1 UNIQUE INDEX (c);
INSERT t1 SELECT 1 FROM seq_1_to_15;  # 15 Rows affected
SELECT * FROM t1;  # 0 Rows
DELETE FROM t1;

INSERT INTO t VALUES(1),(1);
CREATE TABLE t1 (c INT UNIQUE) ENGINE=InnoDB;
SET unique_checks=0,foreign_key_checks=0;
INSERT INTO t1 SELECT 1 FROM t;
CHECK TABLE t1;
SELECT * FROM t1;  # InnoDB: Index 'c' contains 0 entries, should be 2.
DROP TABLE t1;  # ERROR 1712 (HY000): Index t1 is corrupted
