CREATE TEMPORARY TABLE t1 (c1 INT,c2 VARCHAR(3), INDEX (c1)) ENGINE=InnoDB;
CREATE TABLE t1 (c1 INT, c2 VARCHAR(3), KEY(c1,c2)) ENGINE=InnoDB;
DROP TABLE t1;
SET debug_dbug='+d,do_page_reorganize,do_lock_reverse_page_reorganize';
INSERT INTO t1 VALUES(1, 1), (2, 2);

SET sql_mode='';
CREATE TABLE t (c INT KEY,c2 INT,INDEX i (c)) ENGINE=InnoDB;
SET debug_dbug='+d,do_page_reorganize';
INSERT INTO t VALUES (1,'a');

SET sql_mode='';
CREATE TABLE t (c INT KEY,c2 INT,INDEX i (c2)) ROW_FORMAT=COMPRESSED ENGINE=InnoDB;
SET debug_dbug='+d,do_page_reorganize,do_lock_reverse_page_reorganize';
INSERT INTO t VALUES (5,'a');

SET GLOBAL innodb_change_buffering=INSERTS;
SET GLOBAL innodb_change_buffering_debug=1;
SET debug_dbug='+d,do_page_reorganize,do_lock_reverse_page_reorganize';
SET unique_checks=0,foreign_key_checks=0,autocommit=0;
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TABLE t (id INT(1) UNSIGNED,id2 INT(1) UNSIGNED,item CHAR(1),FULLTEXT KEY item (item));
