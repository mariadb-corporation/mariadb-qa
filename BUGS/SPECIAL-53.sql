USE test;
CREATE TABLE t2 (f INT KEY,f2 INT);
SET GLOBAL innodb_ft_server_stopword_table='test/t2';
# CLI: ERROR 1231 (42000): Variable 'innodb_ft_server_stopword_table' can't be set to the value of 'test/t2'
# ERR: InnoDB: Invalid column name for stopword table test/t2. Its first column must be named as 'value'.
