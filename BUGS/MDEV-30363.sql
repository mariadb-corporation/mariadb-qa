CREATE TABLE server_stopword (value VARCHAR(1));
SET GLOBAL innodb_ft_server_stopword_table='test/server_stopword';
CREATE TABLE t (t VARCHAR(1) COLLATE utf8_unicode_ci,FULLTEXT (t));
TRUNCATE TABLE t;
