CREATE  TABLE t (c TEXT(1) NOT NULL, INDEX (c)) ENGINE=InnoDB;
INSERT INTO t SET c='';

SET sql_mode='';
CREATE TABLE t (c SET('','','') KEY,c2 DECIMAL UNSIGNED ZEROFILL,c3 CHAR(1) BINARY);
INSERT INTO t VALUES ('',CURRENT_TIME,'');
UPDATE t SET c2=c2+5 WHERE c BETWEEN '' AND '';
