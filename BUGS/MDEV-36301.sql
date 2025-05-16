SET GLOBAL innodb_log_file_disabled=ON;
SET GLOBAL innodb_log_file_disabled=OFF;
CREATE TABLE t (a INT,KEY(a)) ENGINE=InnoDB;

SET max_statement_time=0.001;                                                                                                                                                                                         
SET GLOBAL innodb_log_file_disabled=ON;                                                                                                                                                                               
SET GLOBAL innodb_log_file_disabled=OFF;

CREATE TABLE t (c INT) ENGINE=InnoDB;
SET GLOBAL innodb_flush_log_at_trx_commit=2;
SET GLOBAL innodb_log_file_disabled=ON;
ALTER TABLE t ADD c2 CHAR FIRST;
XA START 'a';
INSERT INTO t VALUES (0,1);
SET @@max_statement_time=0.0001;
SET GLOBAL innodb_log_file_disabled=OFF;
