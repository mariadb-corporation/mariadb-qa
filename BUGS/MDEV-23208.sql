USE test;
SET SQL_MODE='';
CREATE FUNCTION f(z INT) RETURNS INT READS SQL DATA RETURN (SELECT x FROM t WHERE x = z);
CREATE TEMPORARY TABLE t (c INT) ENGINE=InnoDB;
SELECT f('a');
DROP TEMPORARY TABLES t;
SHOW FUNCTION CODE f;

DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET INNODB_DEFAULT_ENCRYPTION_KEY_ID=99;
CREATE TABLE t(c INT) ENGINE=InnoDB;
CREATE FUNCTION f() RETURNS INT RETURN (SELECT * FROM t);
SELECT f();
ALTER TABLE t ADD COLUMN d INT;
SHOW FUNCTION CODE f;

set innodb_default_encryption_key_id = 99;
USE test;
CREATE TABLE t1(c1 VARBINARY(30) NOT NULL, INDEX i1 (c1));
select SQL_CALC_FOUND_ROWS b,count(*) as c FROM t1  group by b order by c desc limit 1;
CREATE FUNCTION f1 () RETURNS int RETURN (SELECT COUNT(*) FROM t1 );
DROP TABLE IF EXISTS t1;
create TABLE t1 (c1 int) engine=InnoDB pack_keys=0;
INSERT INTO t VALUES (-2954245530716247387,3303582,'Fs0j8Aoxn9zWAkm4hJx8IMXQLF3KIryMiFyvWj','A0OosL','nY05l6MK6PKBLwvYA1vDzAjBzkjHxaOmzEPi4VMMwalMVQqZrFI2F12E2idYFD','Ryw','R','O',7);
select test.f1();
ALTER TABLE `t1` ADD COLUMN `b` INT;
SHOW FUNCTION CODE f1; ;
SELECT SLEEP(3);

USE test;
CREATE TEMPORARY TABLE t1 ( i int) ;
CREATE TABLE ti (a SMALLINT UNSIGNED NOT NULL, b BIGINT UNSIGNED, c BINARY(94), d VARCHAR(56), e VARBINARY(95) NOT NULL, f VARCHAR(58) NOT NULL, g LONGBLOB, h TINYBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ;
CREATE TABLE  t2  (a BINARY(246));
CREATE TABLE t1 (a INT, b VARCHAR(20)) ;
create function f1() returns int deterministic return (select max(a) from  t4 );
CREATE TABLE  t4  (f1 INTEGER, PRIMARY KEY (f1)) ;
DROP TABLE t1;
SET @@global.table_open_cache = FALSE;
SELECT f1();
call mtr.add_suppression("Plugin keyring_vault reported");
SELECT EVENT_ID, EVENT_NAME, TIMER_WAIT FROM performance_schema.events_waits_history WHERE EVENT_NAME LIKE 'abcdefghijklmnopqrstuvwxyz';
UPDATE t1 SET field1 = 'abcdefghijklmnopqrstuvwxyz' WHERE field2 = 'abcdefghijklmnopqrstuvwxyz';
INSERT INTO ti VALUES (17667088284071814827,115,'abcdefghijklmnopqrstuvwxyz','abcdefghijklmnopqrstuvwxyz','abcdefghijklmnopqrstuvwxyz','abcdefghijklmnopqrstuvwxyz','abcdefghijklmnopqrstuvwxyz','abcdefghijklmnopqrstuvwxyz',10);
SELECT * FROM performance_schema.hosts;
INSERT INTO  t2  VALUES (-1340711133,14018,'abcdefghijklmnopqrstuvwxyz','abcdefghijklmnopqrstuvwxyz','abcdefghijklmnopqrstuvwxyz','abcdefghijklmnopqrstuvwxyz','abcdefghijklmnopqrstuvwxyz','abcdefghijklmnopqrstuvwxyz',4);
select * from t1 A, t1 B where B.rowkey=A.a;
show function code f1;

CREATE FUNCTION f0() RETURNS INT RETURN (SELECT * FROM t);
CREATE TABLE t (a INT);
CREATE TABLE t2 SELECT f0();
DROP TABLE IF EXISTS t;
SHOW FUNCTION CODE f0;

CREATE FUNCTION f1() RETURNS INT RETURN (SELECT * FROM t1);
CREATE TABLE t1 (c1 INT,c2 INT) ENGINE=MEMORY UNION=(t3,t4) INSERT_METHOD=LAST;
INSERT INTO t1 VALUES (f1(),"max");
DROP TABLE t1;
SHOW FUNCTION CODE f1;

SET GLOBAL log_bin_trust_function_creators=1;
CREATE FUNCTION f2() RETURNS INT RETURN (SELECT 1 FROM t1);
CREATE TABLE t1 (c1 CHAR BINARY CHARACTER SET 'latin1' COLLATE 'latin1_bin',c2 YEAR,c3 YEAR,PRIMARY KEY(c1)) ENGINE=InnoDB;
SELECT f2()='_u1@localhost';
DROP TABLE t1,t2,t3,t4,t5,t6;
SHOW FUNCTION CODE f2;
