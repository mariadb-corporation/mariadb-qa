CREATE TABLE t2 (a INT,b CHAR(20)) ENGINE=InnoDB;
CREATE UNIQUE INDEX bi USING HASH ON t2 (b);
INSERT INTO t2 VALUES (0,0);
SET sql_mode='pad_char_to_full_length';
DELETE FROM t2;