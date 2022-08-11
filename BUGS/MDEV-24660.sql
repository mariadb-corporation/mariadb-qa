# mysqld options required for replay: --log-bin 
CREATE DATABASE transforms;
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET sql_mode='';
CREATE TEMPORARY TABLE `´´´`(`¹¹¹` char(1)) DEFAULT CHARSET=sjis engine=InnoDB;#NOERROR
delete from mysql.user where user='user1' or user='user2';#NOERROR
CREATE TABLE t1(c1 char(1)) DEFAULT CHARSET=ujis ENGINE=InnoDB;#ERROR: 1050 - Table 't1' already exists
INSERT INTO t1 VALUES(17509);#NOERROR
DELETE FROM t1;#NOERROR
create table t2 (a int auto_increment,b int,PRIMARY KEY (a)) ENGINE=InnoDB;#NOERROR
INSERT INTO t1 VALUES (-123.456e0);#NOERROR
LOAD DATA INFILE '../../tmp/proc.txt' INTO TABLE InnoDB.proc;#ERROR: 1100 - Table''was not locked with LOCK TABLES
CREATE TABLE `ï½±ï½±ï½±`(`ï½¶ï½¶ï½¶` char(1)) DEFAULT CHARSET=utf8 engine=InnoDB;#ERROR: 1100 - Table 'ï½±ï½±ï½±' was not locked with LOCK TABLES
INSERT INTO t1 VALUES(0xADBF);#ERROR: 1792 - Cannot execute statement in a READ ONLY transaction
CREATE TABLE ti (a SMALLINT UNSIGNED,b BIGINT UNSIGNED ,c CHAR(32) ,d VARCHAR(31) ,e VARCHAR(31),f VARBINARY(58),g TINYBLOB,h BLOB ,id BIGINT ,KEY(b),KEY(e),PRIMARY KEY(id)) ENGINE=InnoDB;#ERROR: 1792 - Cannot execute statement in a READ ONLY transaction
insert into t1 values (-1),(-2),(-3);#ERROR: 1792 - Cannot execute statement in a READ ONLY transaction
INSERT INTO ti VALUES (4023595403684610118,7836,'7swVX','xWYjZYSkX0P','JJgE','so18BIYlJMt8r05JqWP3Q7e5i8xMnZyp','1','7',11);#ERROR: 1792 - Cannot execute statement in a READ ONLY transaction
SET @@global.max_binlog_size=4095;#NOERROR
shutdown;#NOERROR
