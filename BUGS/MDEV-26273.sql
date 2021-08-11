# mysqld options required for replay: --log_bin --innodb-force-recovery=2
CREATE TABLE t (FTS_DOC_ID BIGINT UNSIGNED KEY,c CHAR(200),d TEXT) ENGINE=InnoDB;
ALTER TABLE t ADD FULLTEXT INDEX i(c);

# mysqld options required for replay:  --innodb-force-recovery=2
CREATE TABLE articles (id INT UNSIGNED KEY,title CHAR(1),body TEXT) DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci ENGINE=InnoDB;
CREATE FULLTEXT INDEX idx ON articles (body);
