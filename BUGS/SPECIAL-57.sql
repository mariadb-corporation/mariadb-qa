SET SESSION max_recursive_iterations=100000;
CREATE TABLE t1 (c1 INT PRIMARY KEY, c2 TEXT, FULLTEXT(c2)) ENGINE=InnoDB;
SET SESSION max_statement_time=0.0001;
INSERT INTO t1 VALUES (1,'aaa b c');
SET SESSION max_statement_time=0.0005;
INSERT INTO t1 VALUES (2,'aaa b c');
SET SESSION max_statement_time=0.001;
INSERT INTO t1 VALUES (3,'aaa b c');
SET SESSION max_statement_time=0.002;
INSERT INTO t1 VALUES (4,'aaa b c');
#CLI: ERROR 1969 (70100): Query was interrupted: execution time limit 0.0001 sec exceeded
#ERR: [ERROR] InnoDB: (Operation interrupted) while getting next doc id for table `test`.`t1`
SET SESSION max_statement_time=0;
INSERT INTO t1 WITH RECURSIVE s AS (SELECT 5 n UNION ALL SELECT n+1 FROM s WHERE n<5000) SELECT n,CONCAT('aaa w',n) FROM s;
SET GLOBAL innodb_optimize_fulltext_only=ON;
OPTIMIZE TABLE t1;
SET SESSION max_statement_time=0.001;
SELECT COUNT(*) FROM t1 WHERE MATCH(c2) AGAINST('aaa');
#CLI: ERROR 188 (HY000): Operation was interrupted by end user (probably kill command?)
#ERR: [ERROR] InnoDB: (Operation interrupted) while reading FTS index.
SET SESSION max_statement_time=0;
SET GLOBAL innodb_optimize_fulltext_only=OFF;
DROP TABLE t1;

CREATE TABLE t1 (c1 INT PRIMARY KEY, c2 TEXT, FULLTEXT(c2)) ENGINE=InnoDB;
SET SESSION max_recursive_iterations=200000;
INSERT INTO t1 WITH RECURSIVE s AS (SELECT 1 n UNION ALL SELECT n+1 FROM s WHERE n<20000) SELECT n,CONCAT('w',n,' v',n%997,' aaa bbb ccc') FROM s;
DELETE FROM t1 WHERE c1%3=0;
SET GLOBAL innodb_optimize_fulltext_only=ON;
SET GLOBAL innodb_ft_num_word_optimize=20000;
SET SESSION max_statement_time=0.0005;
OPTIMIZE TABLE t1;
SET SESSION max_statement_time=0.002;
OPTIMIZE TABLE t1;
SET SESSION max_statement_time=0.01;
OPTIMIZE TABLE t1;
#ERR: [ERROR] InnoDB: (Operation interrupted) while reading words.
SET SESSION max_statement_time=0;
SET GLOBAL innodb_optimize_fulltext_only=OFF;
DROP TABLE t1;

CREATE TABLE t1 (c1 INT PRIMARY KEY, c2 TEXT, FULLTEXT(c2)) ENGINE=InnoDB;
SET SESSION max_recursive_iterations=200000;
INSERT INTO t1 WITH RECURSIVE s AS (SELECT 1 n UNION ALL SELECT n+1 FROM s WHERE n<20000) SELECT n,CONCAT('w',n,' v',n%997,' aaa bbb ccc') FROM s;
SET GLOBAL innodb_optimize_fulltext_only=ON;
SET GLOBAL innodb_ft_num_word_optimize=20000;
SET SESSION max_statement_time=0.05;
OPTIMIZE TABLE t1;
SET SESSION max_statement_time=0.3;
OPTIMIZE TABLE t1;
SET SESSION max_statement_time=1;
OPTIMIZE TABLE t1;
#CLI: every OPTIMIZE reports status OK, no client error
#ERR: [ERROR] InnoDB: (Operation interrupted) during SYNC of table `test`.`t1`
#ERR: [ERROR] InnoDB: (Operation interrupted) while getting next doc id for table `test`.`t1`
SET SESSION max_statement_time=0;
SET GLOBAL innodb_optimize_fulltext_only=OFF;
DROP TABLE t1;

CREATE TABLE t1 (c1 INT PRIMARY KEY, c2 TEXT, FULLTEXT(c2)) ENGINE=InnoDB;
SET SESSION max_recursive_iterations=200000;
INSERT INTO t1 WITH RECURSIVE s AS (SELECT 1 n UNION ALL SELECT n+1 FROM s WHERE n<20000) SELECT n,CONCAT('w',n,' aaa bbb ccc ddd eee') FROM s;
SET SESSION max_statement_time=0.1;
SELECT COUNT(*) FROM t1 WHERE MATCH(c2) AGAINST('"aaa bbb ccc"' IN BOOLEAN MODE);
SET SESSION max_statement_time=0.35;
SELECT COUNT(*) FROM t1 WHERE MATCH(c2) AGAINST('"bbb ccc ddd eee"' IN BOOLEAN MODE);
SET SESSION max_statement_time=1;
SELECT COUNT(*) FROM t1 WHERE MATCH(c2) AGAINST('"aaa bbb ccc ddd"' IN BOOLEAN MODE);
#CLI: ERROR 188 (HY000): Operation was interrupted by end user (probably kill command?)
#ERR: [ERROR] InnoDB: (Operation interrupted) matching document.
SET SESSION max_statement_time=0;
DROP TABLE t1;

# All five error log messages are filtered, tracked as MDEV-40806. The interrupt is the client's own
# max_statement_time, and the rows, the FTS index and the FTS CONFIG values are all correct
# afterwards. Only the error log line is wrong. On an INSERT or a SELECT the client also gets an
# error; on OPTIMIZE TABLE it does not, that statement reports status OK.
# Absent on a CS 13.1.0 build from before MDEV-28730, present after it.
# Keep each pattern narrow, matching one filed message. A broad 'Operation interrupted' pattern
# would also hide a new FTS config key, a different error code, or 'writing `use_stopword''
# (MDEV-40804), which loses data.
# The second block can also hit MDEV-40621 on a build before its fix, on a debug build as
# fts_decode_vlc and on an optimised build as fts_optimize_compact.
