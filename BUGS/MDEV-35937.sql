CREATE TABLE t (a TEXT ,FULLTEXT (a)) ENGINE=INNODB;
ALTER TABLE t DISCARD TABLESPACE;
SET GLOBAL innodb_ft_aux_table='test/t';
SELECT * FROM information_schema.innodb_ft_config;
