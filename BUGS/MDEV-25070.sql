CREATE TABLE t (a CHAR,FULLTEXT KEY(a)) ENGINE=InnoDB;
ALTER TABLE t DISCARD TABLESPACE;
ALTER TABLE t ADD FULLTEXT INDEX (a);