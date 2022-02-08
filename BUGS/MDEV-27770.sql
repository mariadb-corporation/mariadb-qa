CREATE TABLE t (a INT AUTO_INCREMENT KEY) ENGINE=InnoDB;
SET sql_mode='no_auto_value_on_zero';
INSERT INTO t VALUES ('a,b,c,d');
SET sql_mode='no_unsigned_subtraction';
INSERT INTO t VALUES (REPEAT ('1',200));
INSERT IGNORE INTO t SELECT a FROM t AS t2 ON DUPLICATE KEY UPDATE a=t.a+1;
