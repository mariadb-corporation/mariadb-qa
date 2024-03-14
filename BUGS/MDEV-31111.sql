INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SET GLOBAL sql_mode=(SELECT CONCAT (@@sql_mode,',pipes_as_concat'));
CREATE TABLE t2 (pk INT(1) NOT NULL,c_int_nokey INT(1),c_intk INT(1),cvck CHAR(1),cvc_nokey VARCHAR(1),PRIMARY KEY(pk),KEY c_intk (c_intk),KEY cvck (cvck,c_intk)) ENGINE=Spider AUTO_INCREMENT=+ 1 DEFAULT CHARSET=latin1;
CREATE TABLE t (i1 INT NOT NULL,a INT,PRIMARY KEY(i1)) ENGINE=Spider;
ALTER TABLE t2 ENGINE=InnoDB;
DROP TABLE t;
DROP TABLE t,t2,t3,t4;
CREATE TABLE t3 (c INT,c2 CHAR(1)) ENCRYPTION="Y" ENGINE=Spider;
RENAME TABLE t TO t2;

SET SESSION sql_mode='traditional', GLOBAL sql_mode='TRADITIONAL';
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t1 (c INT) ENGINE=Spider;
CREATE TABLE t2 (c INT) ENGINE=Spider;
ALTER TABLE t1 ENGINE=InnoDB;
DROP TABLE t1;
RENAME TABLE t2 TO t1,t2 TO t1;

SET sql_mode='traditional', GLOBAL sql_mode='NO_ZERO_DATE';
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t1 (c INT) ENGINE=Spider;
CREATE TABLE t2 (c INT) ENGINE=Spider;
ALTER TABLE t1 ENGINE=Spider;
DROP TABLE t1;
RENAME TABLE t2 TO t1,t2 TO t1;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t1 (c INT) ENGINE=Spider;
CREATE TABLE t2 (c INT) ENGINE=Spider;
ALTER TABLE t1 ENGINE=InnoDB;
DROP TABLE t1;
RENAME TABLE t2 TO t1,t2 TO t1;

SET sql_mode='traditional', GLOBAL sql_mode='NO_ZERO_DATE';
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t1 (c INT) ENGINE=Spider;
CREATE TABLE t2 (c INT) ENGINE=Spider;
ALTER TABLE t1 ENGINE=Spider;
DROP TABLE t1;

SET sql_mode='traditional', GLOBAL sql_mode='NO_ZERO_DATE';
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t1 (c INT) ENGINE=Spider;
CREATE TABLE t2 (c INT) ENGINE=Spider;
ALTER TABLE t1 ENGINE=Spider;
DROP TABLE t1;
RENAME TABLE t2 TO t1,t2 TO t1;

SET GLOBAL sql_mode=(SELECT CONCAT (@@sql_mode,',no_zero_date'));
INSTALL SONAME 'ha_spider';
