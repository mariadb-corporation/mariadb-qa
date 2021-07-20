CREATE TABLE t (a DATE);
SET GLOBAL innodb_thread_concurrency=1;
SELECT * FROM t;
