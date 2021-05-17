SET debug_dbug='+d,row_drop_table_add_to_background';
CREATE TABLE t1 (a INT NOT NULL) ENGINE=InnoDB;
ALTER TABLE t1 ADD c2 TEXT NOT NULL;
DROP TABLE t1;

SET debug_dbug='+d,row_drop_table_add_to_background';
CREATE TABLE t1 (a INT NOT NULL) ENGINE=InnoDB;
ALTER TABLE t1 FORCE;
DROP TABLE t1;
