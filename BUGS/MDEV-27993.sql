SET sql_mode='';
CREATE TABLE t (c INT,KEY(c)) ENGINE=InnoDB;
SET debug_dbug='+d,do_page_reorganize';
INSERT INTO t VALUES ('');
