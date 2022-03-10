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
