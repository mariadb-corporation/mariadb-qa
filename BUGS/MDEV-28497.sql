SET innodb_default_encryption_key_id=99;
PREPARE s FROM 'CREATE TABLE t (c INT) nonexistingoption="N" ENGINE=InnoDB';
EXECUTE s;
EXECUTE s;

SET innodb_default_encryption_key_id=99;
PREPARE stm FROM 'CREATE TABLE test.t (i INT) ENGINE=InnoDB ENCRYPTION="N"';
SET NAMES ujis;
EXECUTE stm;
SET NAMES latin1;
SELECT * FROM ((t1 LEFT JOIN (t2 JOIN t1 ON t2.c2=t3.a3) ON t1.pk=t2.d2) LEFT JOIN t1 ON t1.a1=t4.a4) LEFT JOIN t1 ON t3.a3=t5.a5;
EXECUTE stm;

SET innodb_default_encryption_key_id=99;
PREPARE stmt FROM 'CREATE TABLE test.t (i INT) ENCRYPTION="N"';
SET NAMES ujis;
EXECUTE stmt;
SET NAMES latin1;
SELECT * FROM ((t1 LEFT JOIN (t2 JOIN t1 ON t2.c2=t3.a3) ON t1.pk=t2.d2) LEFT JOIN t1 ON t1.a1=t4.a4) LEFT JOIN t1 ON t3.a3=t5.a5;
EXECUTE stmt;
SELECT 1;
