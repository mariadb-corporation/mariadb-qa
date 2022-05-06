CREATE TABLE t1 (a INT, b CHAR(12), FULLTEXT KEY(b)) engine=InnoDB;
SET DEBUG_DBUG='+d,ib_create_table_fail_too_many_trx';
TRUNCATE t1;
DROP TABLE t1;
