SET unique_checks=0,foreign_key_checks=0,autocommit=0,sql_mode='traditional';
CREATE TABLE t (c CHAR(3)) DEFAULT CHARSET=sjis ENGINE=InnoDB;
INSERT t VALUES ('abc'),('abcd');
SHUTDOWN;
