# mysqld options required for replay:  --innodb-ft-min-token-size=0
CREATE TABLE t (f CHAR,FULLTEXT (f)) ENGINE=INNODB;
INSERT INTO t VALUES ('');
