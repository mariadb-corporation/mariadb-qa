SET @@in_predicate_conversion_threshold=1;
CREATE TABLE t1 (a BIGINT);
INSERT INTO t1 VALUES (1),(2),(3);
PREPARE s FROM "SELECT*FROM t1 WHERE a IN ('1','5','3')";
EXECUTE s;
EXECUTE s;

# Loop till it asserts
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET @@max_statement_time=0.00001;
ALTER TABLE ti ENGINE=InnoDB;
SET in_predicate_conversion_threshold=2;
SHOW TABLES;
CREATE TABLE t1 (c1 MEDIUMINT UNSIGNED AUTO_INCREMENT UNIQUE KEY);
SELECT HEX('b') FROM t1 LIMIT 1;
PREPARE p FROM "SELECT object_type,object_schema,object_name,count_star,count_read,count_write,count_read_normal,count_read_with_shared_locks,count_read_high_priority,count_read_no_insert,count_read_external,count_write_LOW_PRIORITY,count_write_external FROM performance_schema.table_lock_waits_summary_by_table WHERE object_type='TABLE' AND object_schema='test' AND object_name IN ('t1','t2','t3') ORDER BY object_type,object_schema,object_name";
SELECT found_rows();
EXECUTE p;
EXECUTE p;

# Loop till it asserts
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE t2 (b CHAR(1));
CREATE TABLE t (a INT);
CREATE TABLE ti LIKE t;
SET lc_time_names='en_us';
PREPARE stmt FROM 'SELECT * FROM t WHERE EXISTS (SELECT 1 FROM t2 WHERE t2.b=t.a)';
CREATE TABLE t4 (c INT);
INSERT INTO foo VALUES (1);
SET @@max_statement_time=0.00001;
EXECUTE stmt;
EXECUTE stmt;
