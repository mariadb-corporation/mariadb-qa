INSTALL PLUGIN simple_parser SONAME 'mypluglib';
CREATE TABLE t (title CHAR,body TEXT) ENGINE=INNODB;
INSERT INTO t VALUES ('a','xyz xyz');
ALTER TABLE t ADD FULLTEXT INDEX (title,body) WITH PARSER simple_parser;
