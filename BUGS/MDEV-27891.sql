SET sql_mode='';
CREATE TABLE t1 (a INT NOT NULL, b INT, PRIMARY KEY(a)) ENGINE=InnoDB;
SET GLOBAL innodb_buffer_pool_size=21474836480;
INSERT INTO t1 VALUES (0,0,0);
DROP TABLE t1;
SET GLOBAL innodb_buffer_pool_size=@@innodb_buffer_pool_size + 1048576;
SELECT SLEEP (3);
