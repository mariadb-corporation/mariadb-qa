SET sql_mode='';
CREATE TABLE t (FTS_DOC_ID BIGINT UNSIGNED NOT NULL,title CHAR(1),body TEXT);
INSERT INTO t (title,body)VALUES(0,0), (0,0), (0,0), (0,0), (0,0), (0,0);
CREATE FULLTEXT INDEX idx1 ON t (title,body);
CREATE FULLTEXT INDEX idx1 ON t (title,body);
