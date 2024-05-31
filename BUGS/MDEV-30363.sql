CREATE TABLE server_stopword (value VARCHAR(1));
SET GLOBAL innodb_ft_server_stopword_table='test/server_stopword';
CREATE TABLE t (t VARCHAR(1) COLLATE utf8_unicode_ci,FULLTEXT (t));
TRUNCATE TABLE t;

CREATE TABLE server_stopword (value VARCHAR(30)) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t1 (i INT) ENGINE=InnoDB;
CREATE TABLE t1 (a VARCHAR(255), FULLTEXT (a)) ENGINE=InnoDB;
SET GLOBAL innodb_ft_server_stopword_table="test/server_stopword";
DROP TABLE t1;
TRUNCATE t1;
