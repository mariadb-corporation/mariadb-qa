SET sql_mode='';
CREATE TABLE t (c1 INT, c2 CHAR(255)) ENGINE=InnoDB;
INSERT INTO t VALUES (0,'a');
ALTER TABLE t KEY_BLOCK_SIZE=2;
INSERT INTO t VALUES (1,'b'),(2,'c'),(3,'c');
SET GLOBAL innodb_compression_level=0;
INSERT INTO t VALUES (4,'d'),(5,'e'),(6,'f');
INSERT INTO t VALUES (7,'e'); 
