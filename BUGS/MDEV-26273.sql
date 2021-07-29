# mysqld options required for replay: --log_bin --innodb-force-recovery=2
CREATE TABLE t (FTS_DOC_ID BIGINT UNSIGNED KEY,c CHAR(200),d TEXT) ENGINE=InnoDB;
ALTER TABLE t ADD FULLTEXT INDEX i(c);
