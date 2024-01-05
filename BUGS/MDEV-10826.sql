# a --max_connections=10000
# ${HOME}/mariadb-qa/pquery/pquery2-md --database=test --infile=./in.sql --threads=8000 --user=root --socket=./socket.sock --log-all-queries --logdir=./log2  # Or without last two options
DROP DATABASE transforms;
CREATE DATABASE transforms;
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE t1(c1 DOUBLE PRECISION NULL, c2 VARBINARY(25) NOT NULL, c3 BIGINT(4) NULL, c4 VARBINARY(15) NOT NULL PRIMARY KEY, c5 DOUBLE PRECISION NOT NULL UNIQUE KEY,c6 FIXED(10,8) NOT NULL DEFAULT 3.141592);#NOERROR
CREATE TABLE t1 pk1 MEDIUMINT NOT NULL AUTO_INCREMENT PRIMARY KEY, c2 VARCHAR(200) NOT NULL, c3 INT NOT NULL, c4 BIT NOT NULL)ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'MEDIUMINT NOT NULL AUTO_INCREMENT PRIMARY KEY, c2 VARCHAR(200) NOT NULL, c3 I...' at line 1
SELECT SUBSTRING('1', 2);#NOERROR
INSERT INTO t VALUES (115,16898,'L','oImEmveCe7RK3sZZdH4czWsuqV','LBdLmXZSZzVXk2hkm8HDahnFK4WhnKn97rP5dRAwCzi','U2L','c','X',8);#ERROR: 1146 - Table 'test.t' doesn't exist
SELECT * FROM t1  ORDER BY s1;#ERROR: 1054 - Unknown column 's1' in 'order clause'
SELECT * FROM t1  WHERE c1 > -255 ORDER BY c1,c6 DESC;#NOERROR
INSERT INTO RocksDB.t1 VALUES (b'011');#ERROR: 1146 - Table 'RocksDB.t1' doesn't exist
show global variables like 'performance_schema_max_file_handles';#NOERROR
CREATE TABLE t2(c1 DECIMAL(10,5) NOT NULL, c2 DECIMAL, c3 INT);#NOERROR
SELECT SHA2( x'21ebecb914', 224 ) = '78f4a71c21c694499ce1c7866611b14ace70d905012c356323c7c713'  as NIST_SHA224_test_vector;#NOERROR
CREATE TABLE t1( a NATIONAL VARCHAR(8194) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=RocksDB' at line 1
CREATE TABLE `BB` ( `pk` int(11) NOT NULL AUTO_INCREMENT, `time_key` time DEFAULT NULL, `varchar_key` varchar(1) DEFAULT NULL, `varchar_nokey` varchar(1) DEFAULT NULL, PRIMARY KEY (`pk`), KEY `time_key` (`time_key`), KEY `varchar_key` (`varchar_key`) ) ENGINE=RocksDB AUTO_INCREMENT=11 DEFAULT CHARSET=latin1;#NOERROR
insert into t values (7688,0);#ERROR: 1146 - Table 'test.t' doesn't exist
SELECT SUBSTRING('1', 1, 1);#NOERROR
ALTER INSTANCE ROTATE INNODB MASTER KEY;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'INSTANCE ROTATE INNODB MASTER KEY' at line 1
SELECT REPEAT('.', 2 - 1);#NOERROR
insert into s values (5588,repeat('a', 2000)),(5588,repeat('b', 2000)),(5588,repeat('c', 2000)),(5588,repeat('d', 2000)),(5588,repeat('e', 2000)),(5588,repeat('f', 2000)),(5588,repeat('g', 2000)),(5588,repeat('h', 2000)),(5588,repeat('i', 2000)),(5588,repeat('j', 2000));#ERROR: 1146 - Table 'test.s' doesn't exist
INSERT INTO t2 VALUES (600,168502,29,'corny','flurried','sloping','A');#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT * FROM t1 ;#NOERROR
SELECT * FROM t1  WHERE c1 >= '0000-00-00' AND c1 < '9999-12-31 23:59:59' AND c2 = '2010-10-00 00:00:00' ORDER BY c1;#NOERROR
DROP VIEW  IF EXISTS test.t1_view;#NOERROR
CREATE TABLE t1 ( quantity decimal(60,0));#ERROR: 1050 - Table 't1' already exists
SET @@session.RocksDB_support_xa = -0.6;#ERROR: 1193 - Unknown system variable 'RocksDB_support_xa'
SELECT SUBSTRING_INDEX('default,', ',', 1);#NOERROR
insert INTO t1  set ujis=0x0B, name='U+000B VERTICAL TABULATION';#ERROR: 1054 - Unknown column 'ujis' in 'field list'
CREATE TABLE t1(c1 INT PRIMARY KEY, c2 char(20)) ENCRYPTION="Y" ENGINE = TokuDB;#ERROR: 1050 - Table 't1' already exists
insert into at(c,_tim) select concat('_tim: ',c), json_extract(j, '$') from t where c='opaque_RocksDB_type_mediumblob';#ERROR: 1146 - Table 'test.at' doesn't exist
INSERT INTO t1 PARTITION(`p10-99`,subp3) VALUES (1, "subp3"), (10, "p10-99");#ERROR: 1747 - PARTITION () clause on non partitioned table
CREATE TABLE worklog5743_key4 ( col_1_text TEXT (4000) , col_2_text TEXT (4000) , PRIMARY KEY (col_1_text(1964)) ) ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=4, engine = RocksDB;#NOERROR
DROP TABLE t1;#NOERROR
DROP PROCEDURE bug29770;#ERROR: 1305 - PROCEDURE test.bug29770 does not exist
insert into A values(1), (2);#ERROR: 1146 - Table 'test.A' doesn't exist
CREATE TABLE t1_will_crash ( a VARCHAR(255), b INT, c LONGTEXT, PRIMARY KEY (a, b)) ENGINE=RocksDB PARTITION BY HASH (b) PARTITIONS 7;#NOERROR
CALL add_child(1,1);#ERROR: 1305 - PROCEDURE test.add_child does not exist
CREATE TABLE ti (a INT UNSIGNED NOT NULL, b MEDIUMINT UNSIGNED NOT NULL, c BINARY(95) NOT NULL, d VARCHAR(82) NOT NULL, e VARCHAR(96) NOT NULL, f VARBINARY(71) NOT NULL, g LONGBLOB NOT NULL, h MEDIUMBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=myisam;#NOERROR
ALTER TABLE t3 MODIFY c1 FLOAT NULL;#ERROR: 1146 - Table 'test.t3' doesn't exist
CREATE TABLE t1 ( pk int(11) NOT NULL ) ENGINE=MEMORY DEFAULT CHARSET=latin1;#NOERROR
CREATE PROCEDURE p1() BEGIN declare i int default 10;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
CREATE TABLE ti (a TINYINT UNSIGNED, b BIGINT, c CHAR(97), d VARCHAR(69), e VARBINARY(7) NOT NULL, f VARCHAR(12) NOT NULL, g BLOB, h TINYBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
SELECT t1.c1,t3.c1 FROM t1  NATURAL RIGHT OUTER JOIN t1 WHERE t1.c1 <> 5;#ERROR: 1066 - Not unique table/alias: 't1'
SELECT SUBSTRING('default,default,', LENGTH('default') + 2);#NOERROR
CREATE TABLE t (a SMALLINT NOT NULL, b MEDIUMINT, c BINARY(3), d VARBINARY(52), e VARCHAR(81), f VARCHAR(99) NOT NULL, g LONGBLOB NOT NULL, h LONGBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), CLUSTERING KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'e), PRIMARY KEY(id)) ENGINE=RocksDB' at line 1
set global aria_group_commit=1;#NOERROR
DROP TABLE t1;#NOERROR
insert into t2 values (11787+0.33);#ERROR: 1136 - Column count doesn't match value count at row 1
insert into t2 values (1,2);#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO t1  VALUES (1),(7);#ERROR: 1146 - Table 'test.t1' doesn't exist
CREATE TABLE t1( a VARBINARY(8190) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = DYNAMIC ENGINE=InnoDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = DYNAMIC ENGINE=InnoDB' at line 1
SELECT LOCATE(']', '1 = 1');#NOERROR
execute stmt1 using @parm1;#ERROR: 1243 - Unknown prepared statement handler (stmt1) given to EXECUTE
select t1.auto,t2.auto from t1,t2 where t1.auto=t2.auto and not (t1.string<=>t2.string and t1.tiny<=>t2.tiny and t1.short<=>t2.short and t1.medium<=>t2.medium and t1.long_int<=>t2.long_int and t1.longlong<=>t2.longlong and t1.real_float<=>t2.real_float and t1.real_double<=>t2.real_double and t1.utiny<=>t2.utiny and t1.ushort<=>t2.ushort and t1.umedium<=>t2.umedium and t1.ulong<=>t2.ulong and t1.ulonglong<=>t2.ulonglong and t1.time_stamp<=>t2.time_stamp and t1.date_field<=>t2.date_field and t1.time_field<=>t2.time_field and t1.date_time<=>t2.date_time and t1.new_blob_col<=>t2.new_blob_col and t1.tinyblob_col<=>t2.tinyblob_col and t1.mediumblob_col<=>t2.mediumblob_col and t1.options<=>t2.options and t1.flags<=>t2.flags and t1.new_field<=>t2.new_field);#ERROR: 1146 - Table 'test.t1' doesn't exist
SELECT SHA2( x'9eabfcd3603337df3dcd119d6287a9bc8bb94d650ef29bcf1b32e60d425adc2a35e06577d0c7ce2456cf260efee9e8d8aeeddb3d068f37', 256 ) = '83eeed2dfeb8d2604ab5ec1ac9b5dcab8cc2222518468bc5c24c16ce72e70687'  as NIST_SHA256_test_vector;#NOERROR
INSERT INTO t VALUES (528337183,-1106050294,'YbMPYVyy7DAYCVzrbfPaJpHh8C5ykg','UBTqqKFxkhRQe0F48Xy2OnM3Pz3oCqFD4iFfBuxAt4Bfrl','tsttDiC34LayUJQ44mcGbaFV','3E0AT2yZOt5eQAiOl1841ZSRvyzkTJE22S5mF3WoafrmQKBKM41EYvyqNk56PRugZf8dEQy6t43kNPfQhJEpFLPMMLoMqBezFOYW5vcgxTihCew5kh2mrC7iTaZy37Kl7VfwIvOh4L0s16iEM4G0aIluhTFurmQ9TTgKy5','1','u',6);#ERROR: 1146 - Table 'test.t' doesn't exist
SELECT COUNT(@@local.RocksDB_log_files_in_group);#ERROR: 1193 - Unknown system variable 'RocksDB_log_files_in_group'
DROP TABLE t1;#ERROR: 1051 - Unknown table 'test.t1'
set @@global.master_verify_checksum = 2;#ERROR: 1231 - Variable 'master_verify_checksum' can't be set to the value of '2'
root@127.0.0.1:$SLAVE_MYPORT/test/t1';#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'root@127.0.0.1:$SLAVE_MYPORT/test/t1'' at line 1
INSERT INTO ti VALUES (1133707699,62,'kcepcQBVNSZVmzHL4Lw8yBuyK2zGrEOoN22tXOpaVkB2JybZuAata','bC1Hq14NiDqiYG0gsx6MRC20ZgJBZbZkbY2ceLDiqi4ZohFG1','VYOw','TdKiX5ws6TaMHotWsgPkBHYBkxeomI2pusGT5QyXq1UDx1HgWs40qsn3kltg0WEY9yqcJZU7pdQPtXLncnGf8DV9PQnouw527d2zLzwtZNyuRCmqS6PxfmRf4gmUr8GTh4NpRBwYTHOnJqEOOsOMtGBtkEhyIrrduo2i6PD7ugqiI2BnmhHa09KY0RaycnJY5','U','z5',15);#NOERROR
SELECT @@innodb_buffer_pool_instances = @@GLOBAL.innodb_buffer_pool_instances;#NOERROR
SELECT * FROM t1  WHERE c2 = '2010-10-01 00:00:00' ORDER BY c1,c2 LIMIT 2;#ERROR: 1146 - Table 'test.t1' doesn't exist
SELECT SUBSTRING('11', 2);#NOERROR
INSERT INTO ti VALUES (9723682997053403276,693425393,'A3nOaLzg86XWUOK','tgmjiAqb2GpPASh4Ai2ld0h91HxUbXpEYNkmYW5Xfo63pJwT3kq4oeEEFp1lpor4zpjqX2jKrcSpwrMF2aaorSBg3WcBkoYCMqRt4vVjxs6YEA44HokXcRUX9vtSIbeIPbrVl5ujHz6Y9am07qqFypEqdf0xw6eVlxBe2CZzRXJok0c9I658JjhKj2utejYX1pc2Rozw','2ymam1Cau1','CyIR2TnKfV0oAHfw','O','8l',3);#NOERROR
INSERT INTO ti VALUES (675196,690876,'jFXlb47zj1URxL','Vn0J4yPcF7TPhSAYlhE9ZqoDdo0V8cUlt9lwHdpAuDiiPgm3X7CTzGs4QHtdFSxgVqB38TSt68aRlaTF8eVFVisPzW1Sk7iol9q9vMTLWmIxSuOn4CHtWENx3JjcFUxPyy8N87Iat4Obzm2XQ3OPzBHJkn36MxkYI5v0oRojVfgQxCT3c3X7sBqXxluDCPmqFz','61x4Sldq7WQpehgshM','h33VuTrfBDai2jdRDdtXSphxq','0G','Z',3);#ERROR: 1062 - Duplicate entry '3' for key 'PRIMARY'
SELECT 19642 MOD 5000;#NOERROR
select * from v√º;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'º' at line 1
SELECT SUBSTRING('1', 1, 1);#NOERROR
INSERT INTO t1  VALUES (907,230503,37,'bloater','Kevin','ducks','');#ERROR: 1146 - Table 'test.t1' doesn't exist
CHANGE MASTER TO MASTER_USER="root" FOR CHANNEL "group_replication_recovery";#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'FOR CHANNEL "group_replication_recovery"' at line 1
CREATE TABLE t1 (f1 INTEGER AUTO_INCREMENT, PRIMARY KEY (f1));#NOERROR
SELECT @@global.innodb_adaptive_hash_index;#NOERROR
delete from s where a=1666;#ERROR: 1146 - Table 'test.s' doesn't exist
insert into t2 values (44016);#ERROR: 1136 - Column count doesn't match value count at row 1
DROP TABLE t621;#ERROR: 1051 - Unknown table 'test.t621'
CREATE TABLE t1( a LONGBLOB COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = REDUNDANT ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = REDUNDANT ENGINE=RocksDB' at line 1
set character_set_database=latin1;#NOERROR
show session variables like 'slave_checkpoint_group';#NOERROR
SELECT DATE_FORMAT('2001-01-07', '%w %a %W');#NOERROR
select @@session.relay_log;#ERROR: 1238 - Variable 'relay_log' is a GLOBAL variable
INSERT INTO t2 VALUES (368,108001,36,'honeybee','displacement','reexamines','A');#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE RocksDB.t1 ( `id` int(20) NOT NULL, `dummy` int(20) DEFAULT NULL, PRIMARY KEY (`id`)) ENGINE="RocksDB" DEFAULT CHARSET=latin1;#ERROR: 1049 - Unknown database 'RocksDB'
SET @@global.max_connections = 100000000000;#NOERROR
CREATE TABLE `ÇsÇV` (`ÇbÇP` char(20), INDEX(`ÇbÇP`)) DEFAULT CHARSET = sjis engine = InnoDB;#NOERROR
SELECT TIME('10000090000:10:10.1999999999999');#NOERROR
alter table mysql.memory_table ENGINE=MEMORY;#ERROR: 1146 - Table 'mysql.memory_table' doesn't exist
DROP TABLE if exists t2;#NOERROR
SELECT SUBSTRING('1', 1, 1);#NOERROR
CREATE TABLE t1 ( pk INT NOT NULL, PRIMARY KEY (pk) ) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE ti (a BIGINT NOT NULL, b SMALLINT UNSIGNED NOT NULL, c BINARY(13), d VARBINARY(17) NOT NULL, e VARBINARY(45) NOT NULL, f VARCHAR(38) NOT NULL, g LONGBLOB, h MEDIUMBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=myisam;#ERROR: 1050 - Table 'ti' already exists
CALL spexecute53();#ERROR: 1305 - PROCEDURE test.spexecute53 does not exist
explain format=json select t1.* FROM t1  inner join t1 where t1.a = t2.a group by t1.a;#ERROR: 1066 - Not unique table/alias: 't1'
INSERT INTO t334 VALUES(1);#ERROR: 1146 - Table 'test.t334' doesn't exist
CREATE TABLE m3(c1 INT NULL, c2 VARBINARY(25) NOT NULL, c3 BIGINT(4) NULL, c4 VARBINARY(15) NOT NULL PRIMARY KEY, c5 INT NOT NULL UNIQUE KEY,c6 NUMERIC(10,8) NOT NULL DEFAULT 3.141592);#NOERROR
grant show view on testdb_1.* to mysqltest_1@localhost;#NOERROR
CREATE TABLE stats_rename_old (a INT, PRIMARY KEY (a)) ENGINE=RocksDB STATS_PERSISTENT=1;#NOERROR
GRANT ALL PRIVILEGES ON * TO _1@localhost;#NOERROR
SELECT '1 = 1';#NOERROR
create view v2 as select qty from v1;#ERROR: 1146 - Table 'test.v1' doesn't exist
EXPLAIN SELECT * FROM t10000,t100,t10;#ERROR: 1146 - Table 'test.t10000' doesn't exist
CREATE TABLE t1( a VARCHAR(32769) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = COMPRESSED ENGINE=InnoDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = COMPRESSED ENGINE=InnoDB' at line 1
CREATE TABLE t1 ( id INT, a BLOB COLUMN_FORMAT COMPRESSED WITH COMPRESSION_DICTIONARY numbers, g BLOB GENERATED ALWAYS AS (LEFT(a, 3071)) STORED , INDEX(g(3071)) ) ENGINE=InnoDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED WITH COMPRESSION_DICTIONARY numbers, g BLOB GENERATED ALWAYS AS (L...' at line 1
INSERT INTO t1 VALUES (CONVERT(_ucs2 0x062A0623062B064A0631 USING utf8));#NOERROR
SELECT HEX(c), CONVERT(c USING utf8mb4) FROM t1 WHERE c LIKE CONCAT('%', _gb18030 0xC8CB, '%');#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '0xC8CB, '%')' at line 1
SELECT t1.c1,t4.c1 FROM t1  RIGHT JOIN t1 ON t1.c1 = t4.c1 WHERE t1.c1 <= 5;#ERROR: 1066 - Not unique table/alias: 't1'
create logfile group lg1 add undofile 'undofile.dat' initial_size 3276801 undo_buffer_size 294913 ENGINE=RocksDB;#NOERROR
SELECT * FROM t1  WHERE c1 IN ('1000-00-01','9999-12-31') ORDER BY c1,c2 DESC;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
call mtr.add_suppression("\\[Error\\] InnoDB: Failed to find tablespace for table");#ERROR: 1305 - PROCEDURE mtr.add_suppression does not exist
set global host_cache_size=0;#NOERROR
SET @@global.preload_buffer_size = 65530.34;#ERROR: 1232 - Incorrect argument type to variable 'preload_buffer_size'
SELECT * FROM t1  WHERE c2 <> 32767 ORDER BY c2,c7 LIMIT 2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
CREATE TABLE it ( pk INT NOT NULL, col_int_nokey INT NOT NULL, PRIMARY KEY (pk) ) ENGINE=TokuDB;#NOERROR
insert into t2 values (1792+0.33);#ERROR: 1146 - Table 'test.t2' doesn't exist
CREATE TABLE t1 ( a int unsigned not null auto_increment primary key, b int unsigned ) ENGINE=MyISAM;#ERROR: 1050 - Table 't1' already exists
SET @@global.auto_increment_offset = 65535.4;#ERROR: 1232 - Incorrect argument type to variable 'auto_increment_offset'
insert into at(c,_mpt) select concat('_mpt: ',c), json_extract(j, '$') from t where c='stringany';#ERROR: 1146 - Table 'test.at' doesn't exist
DROP DATABASE events_test;#ERROR: 1008 - Can't drop database 'events_test'; database doesn't exist
select * from performance_schema.setup_instruments limit 1;#NOERROR
SELECT @x, @y;#NOERROR
create table m1 (a int) ENGINE=TokuDB;#NOERROR
CREATE TEMPORARY TABLE t1 (c1 INT) ENGINE=MRG_RocksDB UNION=(t1,t2);#NOERROR
DROP TEMPORARY TABLE tmp_RocksDB_88;#ERROR: 1051 - Unknown table 'test.tmp_RocksDB_88'
INSERT INTO ti VALUES (12452951996966965202,-5887875395049130158,'Uf6YjJXIvdelpMpVWsCOJ92RPfdI','1zHEEYRCfHAaeQilfTyEMiqcvrpdgoQGjMp6B8ZN6m6GIK2vNkAc00ttvDdNI2HiZTKjWMCor2BN','sx7KihOBsQesN67k0iJQrWy4DmX9JMoFvg5mDeKNL6G','h1UId48XbpVs','A','G',13);#NOERROR
INSERT t1 VALUES (1),(2),(3);#NOERROR
INSERT INTO ti VALUES (-6049036833101064884,48933,'Q5w','wTQ8ZrJGP01RsfGwSa3RWjWG3AO0BqQMab','jyt89TBY3sOPvCLyHSyW8eEugtBU8ZH4bxbq2TGb0d0blYFM5pglcgB1xhJIFLP4snFjlN','Xg0K9McEKHXlOExQSlrhnGiloSWeIcKATDcFEwEs0NjpSLhn6160yQpwzz8v1OXJJTx3etF1S6C2ie0iUVflHRW5ApboGtfAJuMq334ebqsq1iwOETlbT5H5gjVvefmxXPLoxKJJ36H2Kliu9XmyJcvGVLIlAaaNNl5bgKV0UUiJTFP2hIJrMYrzDzjd26FV86oSQPOL0MoLCWEkr6QwEtXEbVWVxiTrnMn2la','4d','pQ',14);#NOERROR
SET @@session.sql_log_bin = 1;#NOERROR
CREATE TABLE `ÇsÇP` (`ÇbÇP` char(5), INDEX(`ÇbÇP`)) DEFAULT CHARSET = sjis engine = RocksDB;#NOERROR
CREATE TABLE `ÇsÇW` (`ÇbÇP` ENUM('Ç†','Ç¢','Ç§'), INDEX(`ÇbÇP`)) DEFAULT CHARSET = sjis engine = RocksDB;#NOERROR
select SUBSTRING_INDEX(_latin1'abcdabcdabcd' COLLATE latin1_bin,_latin1'd',2);#NOERROR
SELECT SUBSTRING('0', 2);#NOERROR
select friedrich from (select 1 as otto) as t1;#ERROR: 1054 - Unknown column 'friedrich' in 'field list'
set session innodb_adaptive_hash_index='OFF';#ERROR: 1229 - Variable 'innodb_adaptive_hash_index' is a GLOBAL variable and should be set with SET GLOBAL
CREATE TEMPORARY TABLE tti1 (a INT) ENGINE=MEMORY;#NOERROR
DROP TABLE IF EXISTS bug21825_A;#NOERROR
create TABLE t1 (a int not null auto_increment,b int, primary key (a)) engine=RocksDB auto_increment=3;#ERROR: 1050 - Table 't1' already exists
insert into t (id,a) values (3,92);#ERROR: 1146 - Table 'test.t' doesn't exist
INSERT INTO t1  SELECT * FROM t1 ;#NOERROR
RENAME TABLE t2 TO t1;#ERROR: 1146 - Table 'test.t2' doesn't exist
SELECT SUBSTRING_INDEX('default,default,', ',', 1);#NOERROR
CREATE TABLE t1(c1 INT, c2 char(20)) ENCRYPTION="Y" ENGINE=InnoDB;#ERROR: 1050 - Table 't1' already exists
INSERT INTO t1 values (1),(2),(3),(4),(5);#NOERROR
SELECT * FROM INFORMATION_SCHEMA.GLOBAL_VARIABLES WHERE VARIABLE_NAME='replicate_wild_ignore_table';#NOERROR
CREATE TABLE m3(c1 NUMERIC NULL, c2 VARCHAR(25) NOT NULL, c3 INT(4) NULL, c4 VARCHAR(15) NOT NULL PRIMARY KEY, c5 NUMERIC NOT NULL UNIQUE KEY,c6 NUMERIC(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 'm3' already exists
LOAD DATA LOCAL INFILE 'suite/engines/funcs/t/load_unique_error1.inc' REPLACE INTO TABLE t1 FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n';#ERROR: 2 - File 'suite/engines/funcs/t/load_unique_error1.inc' not found (Errcode: 2)
INSERT INTO t1 (subject) VALUES(0x616263F0909080646566);#ERROR: 1054 - Unknown column 'subject' in 'field list'
SELECT * FROM t4 WHERE c1 = 1 ORDER BY c1 LIMIT 2;#ERROR: 1146 - Table 'test.t4' doesn't exist
DROP PROCEDURE spexecute51;#ERROR: 1305 - PROCEDURE test.spexecute51 does not exist
SELECT pseudo FROM t8 WHERE pseudo=(SELECT pseudo FROM t8 WHERE pseudo LIKE '%joce%');#ERROR: 1146 - Table 'test.t8' doesn't exist
SELECT QUOTE(SUBSTRING('[SELECT COUNT(*) FROM t1 WHERE a IS NULL] = 1', 1 + 1, 41 - 1 - 1));#NOERROR
insert into t1 values (6962,6962,6962,6962);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT `ÇbÇP` FROM `ÇsÇXa` WHERE NOT EXISTS (SELECT `ÇbÇP` FROM `ÇsÇXb` WHERE `ÇsÇXa`.`ÇbÇP` = `ÇsÇXb`.`ÇbÇP`);#ERROR: 1146 - Table 'test.ÇsÇXa' doesn't exist
insert into t1 values(4635);#NOERROR
DROP TABLESPACE ts1 ENGINE=RocksDB;#NOERROR
CREATE TABLE t1( i INT) engine=INNODB;#ERROR: 1050 - Table 't1' already exists
INSERT INTO t1 VALUES('');#NOERROR
CREATE TABLE `ÔΩ±ÔΩ±ÔΩ±`(`ÔΩ∑ÔΩ∑ÔΩ∑` char(5)) DEFAULT CHARSET = utf8 engine=RocksDB;#NOERROR
SET @@global.large_pages= true;#ERROR: 1238 - Variable 'large_pages' is a read only variable
create table ti (k int, index using btree (k)) charset utf8mb4 engine=TokuDB;#ERROR: 1050 - Table 'ti' already exists
SELECT * FROM t2 WHERE c2 < '1983-09-05 13:28:00' ORDER BY c1,c2 DESC LIMIT 2;#ERROR: 1146 - Table 'test.t2' doesn't exist
DROP TABLE product;#ERROR: 1051 - Unknown table 'test.product'
CREATE TABLE table_bug30423 ( org_id int(11) default NULL, KEY(org_id) ) ENGINE=MEMORY DEFAULT CHARSET=latin1;#NOERROR
INSERT INTO t VALUES (-1252747820,4513693994075589190,'XeKnnAO48xsS9VsVJxRpw8qQa4HldZdA3laHCjPDiIdSrpvfZfDajkM2yLJANvSzowTmw4','iFOZ6ceAn9Fy8vxRmTh5eTrnGRx3Li3CGtFyzKRfnZr7fA2B4rM3VZ0LviQErTcaxtVm3Z3mNbmP6WRaIJ1','epHBePGniWSDZya7URhgPAbaOohT3Qzl6Wp2SQXR4Zhdc','WzQ9lO3Yd8ClOvVeLxPBMJ0JSDZcr281appgKxEVpgkKAUDAEMHBl64OF6O2Ea9pMzO','Un','urM',15);#ERROR: 1146 - Table 'test.t' doesn't exist
CREATE FUNCTION fn1(f1 numeric ) returns numeric return f1;#NOERROR
create TABLE t1 (a int unsigned, b int) partition by list (a) subpartition by hash (b) subpartitions 2 (partition p0 values in (0), partition p1 values in (1), partition pnull values in (null, 2), partition p3 values in (3));#ERROR: 1050 - Table 't1' already exists
INSERT INTO t VALUES (5810569,1167885442,'KdOSNFq284RTd8Jb1e','bRlzxEP','GTBZHes4J823z7r6jDNHDyYAFgZgel8daMuv4rYlvLImVS3J','B1X1DE','Y','3',0);#ERROR: 1146 - Table 'test.t' doesn't exist
replace INTO t1  values (1,1),(2,2);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT CONCAT('SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 65535)', 'ZZENDZZ') REGEXP '[a-zA-Z_][a-zA-Z0-9_]* *, *[0-9][0-9]* *ZZENDZZ';#NOERROR
SELECT * FROM myisam_innodb ORDER BY a;#ERROR: 1146 - Table 'test.myisam_innodb' doesn't exist
insert into t2 values (50818);#ERROR: 1146 - Table 'test.t2' doesn't exist
CREATE TABLE t1( a VARBINARY(128) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = REDUNDANT ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = REDUNDANT ENGINE=RocksDB' at line 1
ALTER TABLE t CHANGE COLUMN a a CHAR(100) NOT NULL;#ERROR: 1146 - Table 'test.t' doesn't exist
insert into s values (6554,0),(6554,1),(6554,2),(6554,3),(6554,4),(6554,5),(6554,6),(6554,7),(6554,8),(6554,9);#ERROR: 1146 - Table 'test.s' doesn't exist
SET @old_global=@@global.innodb_merge_sort_block_size;#ERROR: 1193 - Unknown system variable 'innodb_merge_sort_block_size'
DROP TABLE t1;#NOERROR
DROP TABLE t1,t2,t5,t12,t10;#ERROR: 1051 - Unknown table 'test.t2,test.t5,test.t12,test.t10'
create TABLE t1 (a enum ('a','b','c')) character set utf16;#NOERROR
create RocksDBtest@localhost identified by 'updatecruduser';#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'RocksDBtest@localhost identified by 'updatecruduser'' at line 1
DROP PROCEDURE bug15231_2a;#ERROR: 1305 - PROCEDURE test.bug15231_2a does not exist
SET TIME_ZONE="+03:00";#NOERROR
SET global query_cache_type = 0;#NOERROR
create TABLE t1 (p int, a int, INDEX i_a(a));#ERROR: 1050 - Table 't1' already exists
SELECT SUBSTRING_INDEX('default,default,', ',', 1);#NOERROR
CREATE TABLE t1 ( pk INT AUTO_INCREMENT, c_int_key INT, PRIMARY KEY (pk), KEY (c_int_key) ENGINE=MEMORY;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'ENGINE=MEMORY' at line 1
SELECT SUBSTRING('0', 2);#NOERROR
CREATE TABLE t1 (i int, KEY USING HASH (i)) ENGINE=MEMORY;#ERROR: 1050 - Table 't1' already exists
SET GLOBAL slave_parallel_type='DATABASE';#ERROR: 1193 - Unknown system variable 'slave_parallel_type'
insert into t1 values(62);#NOERROR
SET GLOBAL SLAVE_TYPE_CONVERSIONS='';#NOERROR
alter table t1 engine=InnoDB;#NOERROR
select * from ((t1 natural join t2) natural join t3) natural join t4;#ERROR: 1146 - Table 'test.t2' doesn't exist
SELECT hex(c1),hex(c2) FROM t5 WHERE c1 >  '4' ORDER BY c1;#ERROR: 1146 - Table 'test.t5' doesn't exist
SELECT QUOTE(REPLACE('1 = 1', '<1>', '1'));#NOERROR
INSERT INTO ti VALUES (7589692886289313275,-5699,'oUa7l','KdeLj8HV27JMmusAzEsIBs','EK7ACGsKbIXR4VtEGvxPeWogUMJ92oo3jdXwa2u03XHr','wuCZbZ45r9SeY6YlB8GM3TM','p','h',10);#NOERROR
INSERT INTO t1  VALUES (1,REPEAT('d',7000),REPEAT('e',100)), (2,REPEAT('g',7000),REPEAT('h',100));#ERROR: 1136 - Column count doesn't match value count at row 1
explain partitions select * FROM t1  where a >= 89;#NOERROR
SELECT ENGINE, SUPPORT FROM INFORMATION_SCHEMA.ENGINES WHERE ENGINE='FEDERATED';#NOERROR
CHANGE MASTER TO MASTER_USER= 'root', MASTER_PASSWORD = '';#NOERROR
CREATE TABLE t1(c1 INT, c2 char(20)) ENCRYPTION="Y" ENGINE=TokuDB;#ERROR: 1050 - Table 't1' already exists
INSERT INTO ti VALUES (-9162766727037262189,29,'ofqlVn6g6nD8KGsdfZ9HjhDKjVW33WhVMBs','Yr5DvHaN7uEo84l5yAP1IkSIKZ2PKH7OeX6bAhZzCFMfHRBe8NxKbMG8fozcDPcI9Q9o3wfmpzXZEbNGXsiWh57wetvaZi9sh33erftuW1IhKQn5UqhiTG3E3r2JGjzTUJ7qjvpI116x137ie6qsU6aVUG0uMmzs9SgIhWX2TEZhlo1c6s6kEnhYZJ2NMd8vNnHMUjExusP135RHVnZ2fO6kpG5273','E6QKUgp12VtWQ','NTwlPSvyaJIG9UqEO5VjpgUexTN5VlcESvqvqJwJF2zLfUirvhKHOl1eyiVvUFEDQy9JrHQ5DRSJ48IRhec4zl7Mkau0yvDFhIWlOEVRhOEis6Zz9mIHb4IY095W3SkXMis4rKoTeV0sE4kzeLmYxJk6Z6tFZr8wW1HDRAzm9TAWha','A','5',5);#NOERROR
INSERT INTO t1 VALUES(19122);#NOERROR
INSERT INTO t1  VALUES (7, 951910400,'z','it\'s');#ERROR: 1136 - Column count doesn't match value count at row 1
DROP PROCEDURE IF EXISTS p1;#NOERROR
create TABLE t1 (pk int key ,a1 MEDIUMINT, a2 MEDIUMINT UNSIGNED ) ENGINE=MEMORY;#ERROR: 1050 - Table 't1' already exists
query_vertical EXPLAIN SELECT * FROM t1  WHERE b=1 AND c=1 ORDER BY c,a;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'query_vertical EXPLAIN SELECT * FROM t1  WHERE b=1 AND c=1 ORDER BY c,a' at line 1
explain extended select b1, doc11.double FROM t1  where doc11.int = 5;#NOERROR
INSERT INTO t1  VALUES (1101010101.55);#NOERROR
exec kill -STOP `cat $mysqld_pid_file`;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'exec kill -STOP `cat $mysqld_pid_file`' at line 1
select keyring_key_fetch('Rob_DSA_1024') into @x;#ERROR: 1305 - FUNCTION test.keyring_key_fetch does not exist
CREATE TRIGGER t1_ai AFTER INSERT ON t1 FOR EACH ROW BEGIN UPDATE t1 SET c2= c2 + 1;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
INSERT INTO t1 (c1) VALUES(NULL);#ERROR: 1054 - Unknown column 'c1' in 'field list'
insert into t2 values (57190);#ERROR: 1146 - Table 'test.t2' doesn't exist
create event event2 on schedule every 2 second starts now() ends date_add(now(), interval 5 hour) comment "some" DO begin end;#NOERROR
CREATE TABLE `£‘£∑` (`£√£±` ENUM('é±','é≤','é≥'), INDEX(`£√£±`)) DEFAULT CHARSET = ujis engine = MEMORY;#NOERROR
CALL sp41(1.00e+00);#ERROR: 1305 - PROCEDURE test.sp41 does not exist
CREATE TABLE ti (a INT UNSIGNED NOT NULL, b BIGINT NOT NULL, c BINARY(34) NOT NULL, d VARCHAR(6) NOT NULL, e VARBINARY(89), f VARBINARY(21) NOT NULL, g LONGBLOB, h TINYBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
CREATE TABLE t1 (a TEXT CHARACTER SET utf8mb4, FULLTEXT INDEX(a));#ERROR: 1050 - Table 't1' already exists
SELECT 67 - LENGTH(SUBSTRING_INDEX(SUBSTR('[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 16777215)] = 1', 1, 67), '[', -1));#NOERROR
select @result /* must be zero either way */;#NOERROR
ALTER TABLE t5 ADD c2 CHAR(5)  NOT NULL FIRST;#ERROR: 1146 - Table 'test.t5' doesn't exist
ALTER TABLESPACE t10 ENCRYPTION='y';#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'ENCRYPTION='y'' at line 1
ALTER FUNCTION sf1  LANGUAGE SQL #DET# CONTAINS SQL SQL SECURITY INVOKER;#ERROR: 1305 - FUNCTION test.sf1 does not exist
INSERT INTO t VALUES (2789769429147606644,-99,'Ukt1ckRYmPO','9G4FGp6uu4rUUTUaZ','pHe3aA11dJO4XfINiiuqJXOAheFMW9uXbQtD0mRvxO0NjJr4mnE','NIEUpO4JJido9WOvJuGVIIvb80mcma0zqnjm','s','S3',5);#ERROR: 1146 - Table 'test.t' doesn't exist
create table tm_base_temp (i int) ENGINE=RocksDB;#NOERROR
DROP TABLE t1;#NOERROR
create table t2 (a int not null, b int not null auto_increment, primary key(a,b));#ERROR: 1075 - Incorrect table definition; there can be only one auto column and it must be defined as a key
SET @@global.log_output = 'FILE,TABLE';#NOERROR
set @arg36= 1;#NOERROR
create TABLE t1 (x integer not null primary key, y varchar(32), z integer, key(z)) ENGINE=TokuDB;#NOERROR
CREATE TABLE t1(c1 INT UNSIGNED AUTO_INCREMENT NULL UNIQUE KEY ) AUTO_INCREMENT=10;#ERROR: 1050 - Table 't1' already exists
GRANT usage on mysql.* to 'Tanjotuser1'@'localhost' ;#NOERROR
alter TABLE t1 order by a;#NOERROR
create table t7 (id int primary key) engine = RocksDB key_block_size = 16;#NOERROR
SELECT * FROM t1  WHERE c1 IN ('0000-00-00','9999-12-31 23:59:59') ORDER BY c1 DESC;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
insert INTO t1  values (0, "zero"),(1,"one"),(2,"two"),(3,"three"),(4,"four"),(5,"five"),(6,"six"),(7,"seven"),(8,"eight"),(9,"nine");#ERROR: 1136 - Column count doesn't match value count at row 1
DROP TABLE t192;#ERROR: 1051 - Unknown table 'test.t192'
SET GLOBAL RocksDB_buffer_pool_evict = 'uncompressed';#ERROR: 1193 - Unknown system variable 'RocksDB_buffer_pool_evict'
CREATE TABLE t (a BIGINT UNSIGNED NOT NULL, b BIGINT, c BINARY(44), d VARBINARY(61) NOT NULL, e VARBINARY(87) NOT NULL, f VARCHAR(61) NOT NULL, g BLOB NOT NULL, h BLOB NOT NULL, id BIGINT NOT NULL, KEY(b), CLUSTERING KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'e), PRIMARY KEY(id)) ENGINE=RocksDB' at line 1
INSERT INTO t1 VALUES ('aa', 1);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t1(c1 INT, c2 char(20)) ENCRYPTION="Y" ENGINE = MEMORY;#ERROR: 1050 - Table 't1' already exists
select trigger_schema, trigger_name, event_object_schema, event_object_table, action_statement from information_schema.triggers where event_object_schema = 'test' or event_object_schema = '';#NOERROR
DROP VIEW v1;#ERROR: 4092 - Unknown VIEW: 'test.v1'
LOAD INDEX INTO CACHE t1 PARTITION (p1);#NOERROR
set @tstlw = @@log_warnings;#NOERROR
INSERT INTO t VALUES (-164704,1342308683,'dO5oJx4LOlQXPduCvD7K8ifrg342TFAI1','dNDEwc9ibJB72','VJ78sTwaeAad8T','uOIballCKq','tj','8',0);#ERROR: 1146 - Table 'test.t' doesn't exist
ALTER TABLE t1 CHANGE COLUMN a a BLOB COLUMN_FORMAT COMPRESSED WITH COMPRESSION_DICTIONARY unknown, ALGORITHM = DEFAULT;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED WITH COMPRESSION_DICTIONARY unknown, ALGORITHM = DEFAULT' at line 1
SELECT * FROM t1 WHERE status < 'A' OR status > 'B';#ERROR: 1054 - Unknown column 'status' in 'where clause'
CREATE TABLESPACE ts1 ADD DATAFILE './table_space1/datafile.dat' USE LOGFILE GROUP lg INITIAL_SIZE 25M ENGINE=INNODB ENCRYPTION='Y';#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'ENCRYPTION='Y'' at line 1
SELECT * FROM t1  WHERE b=2 ORDER BY a ASC;#ERROR: 1054 - Unknown column 'b' in 'where clause'
SELECT 1 = 1;#NOERROR
SET @@global.RocksDB_commit_concurrency = OFF;#ERROR: 1193 - Unknown system variable 'RocksDB_commit_concurrency'
create TABLE t1(a varchar(255), b varchar(255), key using btree (a,b)) engine=RocksDB;#ERROR: 1050 - Table 't1' already exists
SELECT * FROM t2 WHERE c2 < 16777215 ORDER BY c2,c1;#ERROR: 1146 - Table 'test.t2' doesn't exist
INSERT INTO t1  VALUES('a');#ERROR: 1136 - Column count doesn't match value count at row 1
select f1, f2, v1.f1 as x1 FROM t1  order by v1.f1;#ERROR: 1054 - Unknown column 'f1' in 'field list'
insert into at(c,_smp) select concat('_smp: ',c), json_extract(j, '$') from t where c='opaque_mysql_type_binary';#ERROR: 1146 - Table 'test.at' doesn't exist
INSERT INTO t1  VALUES ('9999-12-31 23:59:58.000008');#ERROR: 1136 - Column count doesn't match value count at row 1
insert into t (id,a) values (260,56);#ERROR: 1146 - Table 'test.t' doesn't exist
CREATE TABLE ti (a INT UNSIGNED, b TINYINT UNSIGNED, c CHAR(59) NOT NULL, d VARCHAR(24) NOT NULL, e VARCHAR(2) NOT NULL, f VARBINARY(53) NOT NULL, g LONGBLOB NOT NULL, h LONGBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
insert into at(c,_blb) select concat('_blb: ',c),j from t where c='object';#ERROR: 1146 - Table 'test.at' doesn't exist
DROP TABLE t1;#NOERROR
CREATE TABLE t (a MEDIUMINT NOT NULL, b SMALLINT NOT NULL, c BINARY(52) NOT NULL, d VARBINARY(33), e VARCHAR(100) NOT NULL, f VARBINARY(63), g MEDIUMBLOB NOT NULL, h TINYBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), CLUSTERING KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'e), PRIMARY KEY(id)) ENGINE=RocksDB' at line 1
INSERT INTO t1 (ucs2_f,comment) VALUES (0x0536,'ARMENIAN CAPIT ZA');#ERROR: 1146 - Table 'test.t1' doesn't exist
SET GLOBAL slave_preserve_commit_order= TRUE;#ERROR: 1193 - Unknown system variable 'slave_preserve_commit_order'
select CLUST_INDEX_SIZE from information_schema.INNODB_SYS_TABLESTATS where NAME = 'test/t1';#NOERROR
CREATE TABLE ti (a SMALLINT UNSIGNED NOT NULL, b BIGINT UNSIGNED, c CHAR(75), d VARCHAR(90) NOT NULL, e VARBINARY(26) NOT NULL, f VARBINARY(89), g MEDIUMBLOB, h LONGBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
create trigger trg before delete on t1 for each row set new.i:=1;#ERROR: 1363 - There is no NEW row in on DELETE trigger
INSERT INTO test.regular_tbl VALUES (NULL, NOW(),  NAME_CONST('cur_user',_latin1'current_user@localhost' COLLATE 'latin1_swedish_ci'),  NAME_CONST('local_uuid',_latin1'36774b1c-6374-11df-a2ca-0ef7ac7a5f6c' COLLATE 'latin1_swedish_ci'),  NAME_CONST('ins_count',48),'Non partitioned table! Going to test replication for MySQL');#ERROR: 1146 - Table 'test.regular_tbl' doesn't exist
select @`endswithspace `;#NOERROR
INSERT IGNORE INTO t1 VALUES(@inserted_value);#ERROR: 1146 - Table 'test.t1' doesn't exist
SET @@global.sql_slave_skip_counter = 0;#NOERROR
SELECT * FROM t3 WHERE c2 <=> '1998-12-29 00:00:00' ORDER BY c1,c2 DESC LIMIT 2;#ERROR: 1146 - Table 'test.t3' doesn't exist
create table t0 (m int, n int, key(m)) engine=innodb;#NOERROR
SELECT SUBSTRING('00', 1, 1);#NOERROR
insert into t1 values (7207 div 10,7207 mod 100,   7207/100,7207/100,   7207/100,7207/100,7207/100,7207/100,7207/100, 7207 mod 100, 7207/1000,'filler-data-7207','filler2');#ERROR: 1146 - Table 'test.t1' doesn't exist
SELECT IF('SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 0)' REGEXP '^[a-zA-Z_][a-zA-Z_0-9]*:', LOCATE(':', 'SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 0)'), 0);#NOERROR
DELETE FROM t1;#ERROR: 1146 - Table 'test.t1' doesn't exist
SET @@global.collation_connection = 1.1;#ERROR: 1232 - Incorrect argument type to variable 'collation_connection'
SELECT COUNT(c1) FROM t1 WHERE c1 = 'd';#ERROR: 1146 - Table 'test.t1' doesn't exist
INSERT INTO ti VALUES (2833708847128026348,-112,'6PfBmgvpoSDQsDpU3bsGEg2w987oNo6M3L','tc4yu1OpMBajpTEi4TUpGUUZuy9f','KZwqSAWlKmOudRGePw6TE9G43IeHDSz2IlVR','A2Yz','gU','aT',12);#NOERROR
create table d1.t2m (a int) engine=RocksDB;#ERROR: 1049 - Unknown database 'd1'
insert into t2 values (63112+0.333333333);#ERROR: 1146 - Table 'test.t2' doesn't exist
insert into s values (1000000000,8753);#ERROR: 1146 - Table 'test.s' doesn't exist
explain format=json select SQL_BUFFER_RESULT * from t1;#ERROR: 1146 - Table 'test.t1' doesn't exist
SELECT * FROM t1  WHERE c1 <> 16777216 ORDER BY c1,c6 DESC;#ERROR: 1146 - Table 'test.t1' doesn't exist
GRANT mysqltest@localhost;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '@localhost' at line 1
INSERT INTO t VALUES (3481871912835900598,13,'jivvmW1V6kYKpj2JQ7UmpoF44vX2Aiy4K3n48i6JwVI931fDGWi6SRU5rgi72ZPofUXEH6oGcw3e1PODWikuAm','WobzYa','BnZ6BN9','EQ9AZiVQ6tbYiPp5Y9TLAoDC','Y','44',3);#ERROR: 1146 - Table 'test.t' doesn't exist
CREATE TABLE t1 (b BIT NOT NULL, i2 INTEGER NOT NULL, s VARCHAR(255) NOT NULL);#NOERROR
SET @inserted_value = REPEAT('z', 32765);#NOERROR
CREATE TABLE ti (a BIGINT UNSIGNED NOT NULL, b BIGINT NOT NULL, c BINARY(81) NOT NULL, d VARBINARY(7) NOT NULL, e VARCHAR(78), f VARBINARY(98), g TINYBLOB NOT NULL, h MEDIUMBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=MEMORY;#ERROR: 1050 - Table 'ti' already exists
select reserved, used from RocksDBinfo.resources where resource_name = 'DISK_OPERATIONS' order by node_id;#ERROR: 1146 - Table 'RocksDBinfo.resources' doesn't exist
savepoint first;#NOERROR
EXPLAIN FORMAT=JSON SELECT   SQL_SMALL_RESULT table2.col_varchar_key AS field1 , table2.col_time_key AS field2 , table1.col_time_key AS field3 , table1.col_datetime_key AS field4 , ( ( table1.col_int_key ) - ( table1.pk ) ) AS field5 FROM ( cc AS table1 STRAIGHT_JOIN a AS table2 ON (table2.col_int_key = table1.col_int_nokey  ) ) WHERE (   EXISTS ( (SELECT   subquery1_t1.col_varchar_key AS subquery1_field1 FROM ( c AS subquery1_t1 LEFT  JOIN b AS subquery1_t2 ON (subquery1_t2.col_int_nokey = subquery1_t1.pk  AND subquery1_t1.pk NOT IN (SELECT   child_subquery1_t1.col_int_key AS child_subquery1_field1 FROM b AS child_subquery1_t1    ) ) )  GROUP BY subquery1_field1 ) ) ) AND table2.col_varchar_key >= table1.col_varchar_key ORDER BY table1.col_date_key DESC /*+JavaDB:Postgres: NULLS LAST */ , field1 /*+JavaDB:Postgres: NULLS FIRST */, field2 /*+JavaDB:Postgres: NULLS FIRST */, field3 /*+JavaDB:Postgres: NULLS FIRST */, field4 /*+JavaDB:Postgres: NULLS FIRST */, field5 /*+JavaDB:Postgres: NULLS FIRST */;#ERROR: 1146 - Table 'test.cc' doesn't exist
select charset(group_concat(c1 order by c2)) FROM t1 ;#ERROR: 1054 - Unknown column 'c1' in 'field list'
select * from information_schema.global_variables where variable_name='old_alter_table';#NOERROR
SELECT * FROM t1  WHERE c2 >= '2010-10-00' ORDER BY c2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
SELECT QUOTE(SUBSTRING('[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 258)] = 1', 1 + 1, 62 - 1 - 1));#NOERROR
select count(*) from p1 where a < 0;#ERROR: 1146 - Table 'test.p1' doesn't exist
SELECT * FROM t1  WHERE c1 >= '1971-01-01 00:00:01' ORDER BY c1,c2 LIMIT 2;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
CREATE TABLE t1(c1 DECIMAL(1,0) NULL);#ERROR: 1050 - Table 't1' already exists
create TABLE t1 ( d date );#ERROR: 1050 - Table 't1' already exists
SET @save_show_compatibility_56=@@global.show_compatibility_56;#ERROR: 1193 - Unknown system variable 'show_compatibility_56'
INSERT INTO t1 VALUES(1, 'val1');#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT SUBSTRING('00', 1, 1);#NOERROR
SELECT ( SELECT 1 INTO OUTFILE 'file' );#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'INTO OUTFILE 'file' )' at line 1
CREATE TABLE t1(c1 DOUBLE NOT NULL, c2 SMALLINT NOT NULL, c3 INT NULL, c4 VARCHAR(10) NOT NULL);#ERROR: 1050 - Table 't1' already exists
INSERT INTO bug59733 SELECT 0,b FROM bug59733;#ERROR: 1146 - Table 'test.bug59733' doesn't exist
create table t1(o1 int, o2 int, o3 int not null, primary key(o2,o1)) engine = innodb;#ERROR: 1050 - Table 't1' already exists
alter table t2 drop index bi;#ERROR: 1146 - Table 'test.t2' doesn't exist
create table t2 (a int, b bit(2), c char(10));#NOERROR
CREATE VIEW v AS SELECT * FROM a;#ERROR: 1146 - Table 'test.a' doesn't exist
INSERT INTO t VALUES (6751246448100726173,51937,'J','wVpbF8JcwvEU2zYVODSvXZS5VDO5ZRQJnbCMZPLtuAV1iAoxopoK5xCLMjp0pkRK3BmlwpXH4sqm0tblmZ0CprEY0URRd43ujqSBHz4x6fe8MFbOF7Y93ocf5t','1SVJ5L72rjl6i2pWjMmi0z7m','vOQUTfSMQrLn3ZTPzjHF6PCPB6NrRgEvKrrykhKOGi14iqTmXTq8xdZySIVSJOsBV9nm9gyFCOcofxeZnmEl1FLIGML14PDNWv8WRcmnQZiCfrOyT63sPMZwMf1z21Ei0wPhtQe40msROTyieNjlLvK','ATh','B',14);#ERROR: 1146 - Table 'test.t' doesn't exist
SET @global_max_prepared_stmt_count = @@global.max_prepared_stmt_count;#NOERROR
CREATE TABLE t (a SMALLINT, b SMALLINT UNSIGNED, c BINARY(49), d VARBINARY(67) NOT NULL, e VARCHAR(35), f VARCHAR(99), g TINYBLOB NOT NULL, h TINYBLOB, id BIGINT NOT NULL, KEY(b), CLUSTERING KEY(e), PRIMARY KEY(id)) ENGINE=tokudb;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'e), PRIMARY KEY(id)) ENGINE=tokudb' at line 1
SELECT COUNT(*) FROM CountryLanguage;#ERROR: 1146 - Table 'test.CountryLanguage' doesn't exist
ALTER TABLE t CHANGE COLUMN a a CHAR(106);#ERROR: 1146 - Table 'test.t' doesn't exist
insert into t2 values (61348+0.755555555);#ERROR: 1136 - Column count doesn't match value count at row 1
update s set a=20000+5763 where a=5763;#ERROR: 1146 - Table 'test.s' doesn't exist
CREATE TABLE `t-26`(a VARCHAR(10),FULLTEXT KEY(a)) ENGINE=RocksDB;#NOERROR
LOCK TABLES performance_schema.events_waits_history READ;#ERROR: 1142 - SELECT, LOCK TABLES command denied to user 'root'@'localhost' for table 'events_waits_history'
INSERT INTO innodb_ndb VALUES (47);#ERROR: 1146 - Table 'test.innodb_ndb' doesn't exist
insert into at(c,_yea) select concat('_yea: ',c), (select j from t where c='opaque_RocksDB_type_geom') from t where c='opaque_RocksDB_type_geom';#ERROR: 1146 - Table 'test.at' doesn't exist
insert into at(c,_tim) select concat('_tim: ',c),j from t where c='null';#ERROR: 1146 - Table 'test.at' doesn't exist
create procedure test_signal() begin DECLARE not_found CONDITION FOR SQLSTATE "02000";#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
SELECT * FROM t1  WHERE c2 IN (NULL,'2069') ORDER BY c1,c2 LIMIT 2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
CREATE TABLE t1 (a INT, b INT, KEY(a));#ERROR: 1050 - Table 't1' already exists
SET @@global.init_connect = -1;#ERROR: 1232 - Incorrect argument type to variable 'init_connect'
SELECT `ÇbÇP`, SUBSTRING(`ÇbÇP` FROM 0) FROM `ÇsÇW`;#NOERROR
ALTER TABLE t1 MODIFY a VARCHAR(32) CHARACTER SET utf32 COLLATE utf32_unicode_ci;#ERROR: 1054 - Unknown column 'a' in 't1'
SET session RocksDB_file_format_max='Salmon';#ERROR: 1193 - Unknown system variable 'RocksDB_file_format_max'
select * from information_schema.global_variables where variable_name='performance_schema_digests_size';#NOERROR
update RocksDB.setup_consumers set enabled = 'NO';#ERROR: 1146 - Table 'RocksDB.setup_consumers' doesn't exist
SELECT 1 = 1;#NOERROR
CREATE TABLE t917 (c1 VARCHAR(10));#NOERROR
inc $count_debug_groups;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'inc $count_debug_groups' at line 1
INSERT INTO t304 VALUES('a');#ERROR: 1146 - Table 'test.t304' doesn't exist
SELECT ST_ASTEXT(ST_GEOMFROMGEOJSON(ST_ASGEOJSON(ST_GEOMFROMTEXT("POLYGON((30 10, 40 40, 20 40, 10 20,30 10))"), 20, 6)));#NOERROR
SELECT SUBSTRING('1', 2);#NOERROR
SELECT ST_DISTANCE_SPHERE(ST_GEOMFROMTEXT('POINT(0 0)'), ST_GEOMFROMTEXT('POINT(90 -45)'));#NOERROR
select a FROM t1 ;#ERROR: 1054 - Unknown column 'a' in 'field list'
select 't2',a FROM t1 ;#ERROR: 1054 - Unknown column 'a' in 'field list'
INSERT INTO t VALUES (4064836258219472432,5962821956591617402,'Uc7DpY5mUsVrX9j2XQedw8cYogvVQ1jKvB21H2WlIhTqoS','gSLwH2rkC1DQ2qxwb1i9baryo4Xpuf5Rvog6hCC9DMGDx','Ts9A0q','uDXfF8ak7UHQ5mnYN1zVEX9JFTxknR9lXy8WMKOzaX8b3kUZ74OoZGWy1W3C','c','2',8);#ERROR: 1146 - Table 'test.t' doesn't exist
select a as a from t1 union select a from t4;#ERROR: 1146 - Table 'test.t4' doesn't exist
drop index i2_1 on t2;#ERROR: 1091 - Can't DROP INDEX `i2_1`; check that it exists
UPDATE t1 SET c2='2009-06-31' WHERE c2='2001-01-14';#ERROR: 1054 - Unknown column 'c2' in 'where clause'
CREATE TABLE t1 c1 TINYINT, c2 SMALLINT, c3 MEDIUMINT, c4 INT, c5 INTEGER, c6 BIGINT, c7 FLOAT, c8 DOUBLE, c9 DOUBLE PRECISION, c10 REAL, c11 DECIMAL(7, 4), c12 NUMERIC(8, 4), c13 DATE, c14 DATETIME, c15 TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, c16 TIME, c17 YEAR, c18 TINYINT, c19 BOOL, c20 CHAR, c21 CHAR(10), c22 VARCHAR(30), c23 TINYBLOB, c24 TINYTEXT, c25 BLOB, c26 TEXT, c27 MEDIUMBLOB, c28 MEDIUMTEXT, c29 LONGBLOB, c30 LONGTEXT, c31 ENUM('one', 'two', 'three'), c32 SET('monday', 'tuesday', 'wednesday'), PRIMARY KEY(c1) ) ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'TINYINT, c2 SMALLINT, c3 MEDIUMINT, c4 INT, c5 INTEGER, c6 BIGINT, c7 FLOAT, ...' at line 1
select concat('From JSON func ',c, ' as DATETIME'), cast(json_extract(j, '$') as DATETIME) from t where c='opaque_RocksDB_type_longblob';#ERROR: 1146 - Table 'test.t' doesn't exist
CREATE TABLE t1 (c1 INT, INDEX(c1)) ENGINE=MRG_TokuDB UNION=(t1,t2);#ERROR: 1050 - Table 't1' already exists
INSERT INTO t1  VALUES (964,236113,37,'parenthood','stickers','ores','');#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO t1 VALUES(CONCAT(CONVERT(_ucs2 0x0066 USING gb18030), CONVERT(_ucs2 0x0066 USING gb18030), CONVERT(_ucs2 0x0069 USING gb18030)));#ERROR: 1115 - Unknown character set: 'gb18030'
INSERT INTO t730 VALUES('a');#ERROR: 1146 - Table 'test.t730' doesn't exist
SELECT 4584 MOD 5000;#NOERROR
SELECT MAX(ST_GEOMETRYTYPE(g)) FROM gis_geometry;#ERROR: 1146 - Table 'test.gis_geometry' doesn't exist
SELECT * FROM t1  WHERE c2 >= NULL AND c2 < '10:22:33' AND c1 = '491:22:33' ORDER BY c2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
CREATE USER plug IDENTIFIED WITH test_plugin_server AS plug_dest;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'plug_dest' at line 1
TRUNCATE information_schema.schema_privileges;#ERROR: 1044 - Access denied for user 'root'@'localhost' to database 'information_schema'
select length(a), length(b) FROM t1 ;#ERROR: 1054 - Unknown column 'a' in 'field list'
SELECT ST_ASTEXT(ST_CONVEXHULL(ST_GEOMFROMTEXT('LINESTRING(1 -1,1000 -1000,0.0001 0.000)')));#NOERROR
CREATE TABLE ti (a BIGINT, b BIGINT UNSIGNED, c BINARY(12) NOT NULL, d VARBINARY(59), e VARBINARY(49), f VARBINARY(81) NOT NULL, g BLOB, h BLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=InnoDB;#ERROR: 1050 - Table 'ti' already exists
show warnings limit 2, 1;#NOERROR
ALTER TABLE t1 DROP COLUMN c1;#ERROR: 1091 - Can't DROP COLUMN `c1`; check that it exists
DESCRIBE SELECT 1 LIKE ( 1 IN ( SELECT 1 ) );#NOERROR
remove_files_wildcard $_VARDIR/tmp/testdir;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'remove_files_wildcard $_VARDIR/tmp/testdir' at line 1
SELECT * FROM RocksDB.`t1%` ORDER BY id, name;#ERROR: 1146 - Table 'RocksDB.t1%' doesn't exist
SET @@session.div_precision_increment = 31;#NOERROR
CREATE TABLE t2(id INT);#ERROR: 1050 - Table 't2' already exists
CREATE TABLE t1(c1 CHAR(10) NOT NULL);#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t1 (a SERIAL, b CHAR(10)) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
SELECT SUBSTRING('11', 1, 1);#NOERROR
INSERT INTO t1  VALUES (NULL, -0.1e0);#ERROR: 1136 - Column count doesn't match value count at row 1
insert into tt values (1125, 1125, 1125, 0);#ERROR: 1146 - Table 'test.tt' doesn't exist
EXPLAIN PARTITIONS SELECT * FROM t1 WHERE a >= 2;#NOERROR
select * from performance_schema.events_transactions_history_long where event_name in ('transaction') order by timer_wait limit 1;#NOERROR
CREATE TABLE t5 (id INT NOT NULL PRIMARY KEY, a TEXT(500), b VARCHAR(255), FULLTEXT(b)) ENGINE=TokuDB ENCRYPTION='y';#ERROR: 1911 - Unknown option 'ENCRYPTION'
SELECT ST_LONGFROMGEOHASH("s000000001z7wsg7zzm6");#ERROR: 1305 - FUNCTION test.ST_LONGFROMGEOHASH does not exist
insert into at(c,_mls) select concat('_mls: ',c), (select j from t where c='null') from t where c='null';#ERROR: 1146 - Table 'test.at' doesn't exist
SELECT 14 < 1;#NOERROR
SHOW DATABASES LIKE '√É¬≥';#NOERROR
set global innodb_file_per_table = off;#NOERROR
DROP TABLE t1,t2,t3,t4;#ERROR: 1051 - Unknown table 'test.t3,test.t4'
SELECT DISTINCT (a DIV 254576881) FROM t1;#ERROR: 1146 - Table 'test.t1' doesn't exist
INSERT INTO t1 VALUES(10428);#ERROR: 1146 - Table 'test.t1' doesn't exist
LOCK TABLE t1 READ, t1 WRITE;#ERROR: 1066 - Not unique table/alias: 't1'
SELECT REPEAT('.', 1 - 1);#NOERROR
SET GLOBAL query_cache_type=DEMAND;#NOERROR
select 0 + b'1000000000000000';#NOERROR
SELECT SUBSTRING_INDEX('default,default,default,', ',', 1);#NOERROR
INSERT INTO too_deep_docs(x) SELECT CONCAT('{"a":', jarray, '}') FROM t;#ERROR: 1146 - Table 'test.too_deep_docs' doesn't exist
set ndb_join_pushdown = false;#ERROR: 1193 - Unknown system variable 'ndb_join_pushdown'
INSERT INTO t481 VALUES(1);#ERROR: 1146 - Table 'test.t481' doesn't exist
DROP TABLE t1;#ERROR: 1051 - Unknown table 'test.t1'
INSERT INTO t545 VALUES(1);#ERROR: 1146 - Table 'test.t545' doesn't exist
select * from information_schema.session_variables where variable_name='RocksDB_mmap_size';#NOERROR
PREPARE st1 FROM "INSERT INTO v1 (pk) VALUES (2)";#ERROR: 1146 - Table 'test.v1' doesn't exist
INSERT INTO t VALUES (2991573233,40159,'F4b6HKSz6AdXxx6WjyGPipziQ6fyPzJpTE6arkIQC1cuk','vfj52QAMUimFL8H32fXEEV3j63WVsF2DiBet8FFihce2Sh4LybNhQybLjCvX60yCYUY46zrxPi2PRfqL2NkRpos0OElWz2VMN58Vift9DFXI2And5eIKnCuFxrWml4KRHyFYdgOxiCqUd9ff','1sYVb','u9CsxW0CNabPmHaP0puaCn','4C','yh',15);#ERROR: 1146 - Table 'test.t' doesn't exist
create TABLE t1(i1 int not null auto_increment, a int, b int, primary key(i1)) engine=RocksDB;#NOERROR
create TABLE t1 (a int primary key, b int, key b_idx (b)) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
SELECT * FROM t1  WHERE c1 <> '838:59:59' ORDER BY c1,c2 DESC LIMIT 2;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
CREATE TABLE t1 (a6 VARCHAR(32));#ERROR: 1050 - Table 't1' already exists
insert t1 values ('933293329332933293329332933293329332933278987898789878987898789878987898789878');#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT SUBSTRING('11', 1, 1);#NOERROR
INSERT INTO tmyisam VALUES (132);#ERROR: 1146 - Table 'test.tmyisam' doesn't exist
INSERT INTO test.byrange_tbl VALUES (NULL, NOW(),  NAME_CONST('cur_user',_latin1'current_user@localhost' COLLATE 'latin1_swedish_ci'),  NAME_CONST('local_uuid',_latin1'36774b1c-6374-11df-a2ca-0ef7ac7a5f6c' COLLATE 'latin1_swedish_ci'),  NAME_CONST('ins_count',177) + 100,'Partitioned table! Going to test replication for MySQL');#ERROR: 1146 - Table 'test.byrange_tbl' doesn't exist
explain select * FROM t1  s00, t1 s01, t1 s02, t1 s03, t1 s04,t1 s05,t1 s06,t1 s07,t1 s08,t1 s09, t1 s10, t1 s11, t1 s12, t1 s13, t1 s14,t1 s15,t1 s16,t1 s17,t1 s18,t1 s19, t1 s20, t1 s21, t1 s22, t1 s23, t1 s24,t1 s25,t1 s26,t1 s27,t1 s28,t1 s29, t1 s30, t1 s31, t1 s32, t1 s33, t1 s34,t1 s35,t1 s36,t1 s37,t1 s38,t1 s39, t1 s40, t1 s41, t1 s42, t1 s43, t1 s44,t1 s45,t1 s46,t1 s47,t1 s48,t1 s49 where s00.a in ( select m00.a FROM t1  m00, t1 m01, t1 m02, t1 m03, t1 m04,t1 m05,t1 m06,t1 m07,t1 m08,t1 m09, t1 m10, t1 m11, t1 m12, t1 m13, t1 m14,t1 m15,t1 m16,t1 m17,t1 m18,t1 t1 );#NOERROR
SET @inserted_value = REPEAT('z', 8188);#NOERROR
select repeat('hello', -4294967295);#NOERROR
select 1/*!999992*/;#NOERROR
GRANT INSERT ON *.* TO CURRENT_USER() ;#NOERROR
DROP TABLE IF EXISTS db_datadict.t1;#NOERROR
show session variables like 'innodb_lru_scan_depth';#NOERROR
DROP FUNCTION IF EXISTS f1_two_inserts;#NOERROR
SET GLOBAL delay_key_write = ALL;#NOERROR
CREATE TEMPORARY TABLE t1 (c1 INT, c2 INT) ENGINE=MRG_MEMORY UNION=(t3,t4) INSERT_METHOD=LAST;#NOERROR
ALTER DATABASE d10 COLLATE utf8_spanish2_ci;#ERROR: 1 - Can't create/write to file './d10/db.opt' (Errcode: 2 "No such file or directory")
create TABLE t1 (p int not null primary key, u int not null, o int not null, unique (u), key(o)) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t1 ( auto int, fld1 int(6) unsigned zerofill DEFAULT '000000' NOT NULL, companynr tinyint(2) unsigned zerofill DEFAULT '00' NOT NULL, fld3 char(30) DEFAULT '' NOT NULL, fld4 char(35) DEFAULT '' NOT NULL, fld5 char(35) DEFAULT '' NOT NULL, fld6 char(4) DEFAULT '' NOT NULL ) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
ALTER TABLE t4 MODIFY c1 REAL UNSIGNED ZEROFILL NOT NULL;#ERROR: 1146 - Table 'test.t4' doesn't exist
SELECT @@local.slave_allow_batching;#ERROR: 1193 - Unknown system variable 'slave_allow_batching'
create table t1 (a varchar(1)) character set utf8 collate utf8_estonian_ci;#ERROR: 1050 - Table 't1' already exists
SELECT @@GLOBAL.sort_buffer_size = VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_VARIABLES WHERE VARIABLE_NAME='sort_buffer_size';#NOERROR
set optimizer_switch='index_RocksDB=';#ERROR: 1231 - Variable 'optimizer_switch' can't be set to the value of 'index_RocksDB='
my $r3 = $mc->get("bxx:test8");#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'my $r3 = $mc->get("bxx:test8")' at line 1
SET @bug20627_old_session_auto_increment_increment= @@session.auto_increment_increment;#NOERROR
CREATE TABLE t1 (a INT, b CHAR(9), c INT, key(b)) ENGINE=InnoDB PACK_KEYS=0;#ERROR: 1050 - Table 't1' already exists
SELECT * FROM t1  WHERE c1 > '1000-00-01 00:00:00' ORDER BY c1,c2 LIMIT 2;#NOERROR
CREATE TABLE t1 ( a int(11) NOT NULL default '0', b int(11) NOT NULL default '0', KEY a (a,b)) ENGINE=MRG_InnoDB UNION=(t1,t2);#ERROR: 1050 - Table 't1' already exists
select i FROM t1  where b=repeat(_utf8 'b',310);#ERROR: 1054 - Unknown column 'i' in 'field list'
SELECT SUBSTRING('00', 1, 1);#NOERROR
SELECT COUNT(*) FROM t1 WHERE a = "";#ERROR: 1054 - Unknown column 'a' in 'where clause'
SET @@global.optimizer_search_depth = @start_global_value;#ERROR: 1232 - Incorrect argument type to variable 'optimizer_search_depth'
DROP TABLE t1;#NOERROR
insert into t1 values(3683);#NOERROR
SELECT IF(@@GLOBAL.RocksDB_checksums, "ON", "OFF") = VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_VARIABLES WHERE VARIABLE_NAME='RocksDB_checksums';#ERROR: 1193 - Unknown system variable 'RocksDB_checksums'
select @@global.RocksDB_thread_sleep_delay >=0;#ERROR: 1193 - Unknown system variable 'RocksDB_thread_sleep_delay'
SELECT COUNT(c1) AS value FROM t1  WHERE c1 <=> 0;#ERROR: 1054 - Unknown column 'c1' in 'field list'
DROP FUNCTION IF EXISTS test.myfunc;#NOERROR
PREPARE stmt FROM "CREATE TABLE t1 AS SELECT CAST(DATE'2001-00-00' AS CHAR) AS c";#ERROR: 1054 - Unknown column 'CREATE TABLE t1 AS SELECT CAST(DATE'2001-00-00' AS CHAR) AS c' in 'field list'
SELECT hex(c1),hex(c2) FROM t1  WHERE c1 < '64' ORDER BY c1 DESC;#ERROR: 1054 - Unknown column 'c1' in 'field list'
SELECT @@innodb_use_native_aio = @@GLOBAL.innodb_use_native_aio;#NOERROR
SET GLOBAL per_user_session_var_default_val = "u1:u2:gap_lock_raise_error=0,gap_lock_write_log=0,,u3:big_tables=1";#ERROR: 1193 - Unknown system variable 'per_user_session_var_default_val'
update performance_schema.events_statements_summary_by_digest set count_star=12;#ERROR: 1142 - UPDATE command denied to user 'root'@'localhost' for table 'events_statements_summary_by_digest'
insert into t2 values (65508+0.333333333);#ERROR: 1146 - Table 'test.t2' doesn't exist
insert INTO t1  (a,b,c,d,t) values ('b',1110,'a',2,@v2);#ERROR: 1054 - Unknown column 'b' in 'field list'
SELECT ST_CROSSES(ST_GEOMFROMTEXT(@star_lines_near_vertical),ST_GEOMFROMTEXT(@star_line_vertical));#NOERROR
SELECT * FROM t2 WHERE c1 <=> -128 ORDER BY c1,c6 LIMIT 2;#ERROR: 1146 - Table 'test.t2' doesn't exist
SELECT * FROM t1;#NOERROR
create table t1 (i int, j int) engine=RocksDB;#ERROR: 1050 - Table 't1' already exists
INSERT INTO t1  VALUES (765,208113,37,'freest','teem','denounces','');#ERROR: 1136 - Column count doesn't match value count at row 1
SET default_storage_engine=RocksDB;#ERROR: 1286 - Unknown storage engine 'RocksDB'
INSERT INTO tt_archive VALUES(5);#ERROR: 1146 - Table 'test.tt_archive' doesn't exist
INSERT INTO t1  VALUES ('-99:00:00.000001');#NOERROR
INSERT INTO t VALUES (-8581319685136838195,147,'oUBak','zrniW3z5IGv4wjHVHszOn3rhi2kcrdr3J04XOzY7GEWqS1zUBDhqQO5a57t82w3XZeajfULo6LX0OpJKOT4CpilpGij35qLBNlTpBpgfSbN6d9rmfIzEupWs8cnI7GQ4GlK5ekCU6UVCOVKG55qkg1e','HDv6DCQT6jVk','W5eEOGYSLgyrjiG9Zx2vrN6JfkmIjew5b2cwwhC5uEvyXuvATCO4WXErTVKdfYpeotvuyGfuWMO8l5tgqNkXnGBcEfMW1aOEpdVKZb5tucGBtOTuBilacmCUg5bHjHnzSTRp4s3v6ZwZ','d','i',13);#ERROR: 1136 - Column count doesn't match value count at row 1
create TABLE t1(a int) ENGINE=MEMORY;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t1( a NATIONAL VARCHAR(8190) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = COMPRESSED ENGINE=InnoDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = COMPRESSED ENGINE=InnoDB' at line 1
CREATE EVENT e1 ON SCHEDULE EVERY 1 SECOND DO DROP DATABASE BUG52792;#NOERROR
SELECT SUBSTRING('11', 1, 1);#NOERROR
update v1 set x=x+1;#ERROR: 1146 - Table 'test.v1' doesn't exist
select hex(a), hex(@a:=convert(a using utf8mb4)), hex(convert(@a using utf16)) from t1;#NOERROR
SELECT 596 MOD 5000;#NOERROR
SELECT fid, AsText(GeometryN(g, 2)) from gis_multi_polygon;#ERROR: 1146 - Table 'test.gis_multi_polygon' doesn't exist
GRANT SELECT (a, b) ON TABLE    v2 TO mysqluser1@localhost;#ERROR: 1146 - Table 'test.v2' doesn't exist
select id FROM t1  where MATCH(a,b) AGAINST ("collections" WITH QUERY EXPANSION);#ERROR: 1054 - Unknown column 'id' in 'field list'
SET @@session.sql_buffer_result = -1;#ERROR: 1231 - Variable 'sql_buffer_result' can't be set to the value of '-1'
explain select * from t where "aa" <> x;#NOERROR
ALTER TABLE t1 CHANGE a id INT;#ERROR: 1283 - Column 'id' cannot be part of FULLTEXT index
CREATE TABLE t1(c1 SMALLINT NULL, c2 BINARY(25) NOT NULL, c3 TINYINT(4) NULL, c4 BINARY(15) NOT NULL PRIMARY KEY, c5 SMALLINT NOT NULL UNIQUE KEY,c6 DECIMAL(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 't1' already exists
INSERT INTO t1 VALUES (13,0),(8,1),(9,2),(6,3), (11,5),(11,6),(7,7),(7,8),(4,9),(6,10),(3,11),(11,12), (12,13),(7,14);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t1(c1 REAL NULL);#ERROR: 1050 - Table 't1' already exists
show databases like 't%';#NOERROR
SELECT ST_ASTEXT(ST_CONVEXHULL(NULL));#NOERROR
CREATE TABLE t2(c1 INT PRIMARY KEY, c2 char(20)) ENCRYPTION="Y" ENGINE = RocksDB;#ERROR: 1911 - Unknown option 'ENCRYPTION'
SET @@global.table_open_cache = FALSE;#NOERROR
ALTER TABLE t CHANGE COLUMN a b BINARY(139);#ERROR: 1054 - Unknown column 'a' in 't'
INSERT INTO t VALUES (11588466625448019355,-10316,'KSiC1F4IdN5nUhH1fNR2n4Shw','p20HiwtAK42QwrDyW2mmbmKoVxlX','qT9km9djrB5l8xpPZckruGFsPL3JqjUxpWUL3adedhUubfy2htYreC3w','gDtB6IgvMP5fC','i','A',11);#ERROR: 1136 - Column count doesn't match value count at row 1
create table t_dat select DISTINCT(_dat) FROM at;#ERROR: 1146 - Table 'test.at' doesn't exist
SET session query_cache_wlock_invalidate = 0;#NOERROR
update t1 set name='U+253C BOX DRAWINGS LIGHT VERTICAL AND HORIZONTAL' where ujis=0xA8AB;#ERROR: 1054 - Unknown column 'ujis' in 'where clause'
SELECT 'SELECT COUNT(*) FROM t1 WHERE a = ""';#NOERROR
INSERT INTO t1  VALUES(8, 'val8');#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE m3(c1 TIMESTAMP NULL, c2 VARCHAR(25) NOT NULL, c3 MEDIUMINT(4) NULL, c4 VARCHAR(15) NOT NULL PRIMARY KEY, c5 TIMESTAMP NOT NULL UNIQUE KEY,c6 FIXED(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 'm3' already exists
SELECT 38 - LENGTH(SUBSTRING_INDEX(SUBSTR('[SELECT COUNT(*) FROM t1 WHERE a = ""] = 1', 1, 38), '[', -1));#NOERROR
create definer=`test14256`@`%` view v1 as select 42;#NOERROR
show create function f5;#ERROR: 1305 - FUNCTION f5 does not exist
set global query_cache_size= 81920;#NOERROR
SELECT 38 - LENGTH(SUBSTRING_INDEX(SUBSTR('[SELECT COUNT(*) FROM t1 WHERE a = ""] = 1', 1, 38), '[', -1));#NOERROR
set net_read_timeout=100;#NOERROR
INSERT INTO ti VALUES (22902,2992917996,'BPHh4R7GkgjKWQtPXXPm9L4BMXcWZ6NozCdZLfOHSPoIqSR1qDa1fhPjPqquzx4RTbZDidRRI5','GaJCoXaYP8gY8Pu5BbynAC7','8e33e8dOlRTo','TmGsB5DbqW','2j','hg',11);#NOERROR
SELECT @@GLOBAL.INNODB_IO_CAPACITY;#NOERROR
INSERT INTO t1 VALUES (2,4,'6067169d','Y');#ERROR: 1136 - Column count doesn't match value count at row 1
set collation_server=9999998;#ERROR: 1273 - Unknown collation: '9999998'
SET @@session.pseudo_thread_id=100;#NOERROR
insert into t2 values (1891);#ERROR: 1146 - Table 'test.t2' doesn't exist
CREATE TABLE t1 (i int) ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=16;#ERROR: 1050 - Table 't1' already exists
SET @@auto_increment_increment = 10;#NOERROR
SET @@global.innodb_max_dirty_pages_pct = @pct_start_value;#ERROR: 1232 - Incorrect argument type to variable 'innodb_max_dirty_pages_pct'
DROP TABLE IF EXISTS `test2`;#NOERROR
SELECT 9223372036854775807 - -1;#NOERROR
SELECT SUBSTRING('11', 1, 1);#NOERROR
SELECT COUNT(@@GLOBAL.innodb_page_cleaners);#NOERROR
SELECT c1,ST_Astext(c4) FROM tab WHERE ST_Touches(tab.c4, @g1) ORDER BY c1;#ERROR: 1146 - Table 'test.tab' doesn't exist
CREATE TABLE t1 (c1 INT AUTO_INCREMENT, c2 INT, PRIMARY KEY(c1)) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
insert into t2 values (7764+0.75);#ERROR: 1146 - Table 'test.t2' doesn't exist
CREATE TABLE t1 (a SERIAL, c64 VARCHAR(64) UNIQUE) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
create table `#mysql50#t1-1` (a int) engine=RocksDB;#NOERROR
SELECT c1 FROM t1  WHERE c1 = SOME (SELECT c1 FROM t1 );#ERROR: 1054 - Unknown column 'c1' in 'field list'
CREATE TABLE ti (a MEDIUMINT UNSIGNED, b BIGINT NOT NULL, c CHAR(88) NOT NULL, d VARBINARY(40), e VARCHAR(89) NOT NULL, f VARCHAR(40) NOT NULL, g TINYBLOB NOT NULL, h TINYBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=TokuDB;#ERROR: 1050 - Table 'ti' already exists
CREATE TABLE innodb_InnoDB (a INT) ENGINE=InnoDB;#NOERROR
SET @@session.sql_mode = POSTGRESQL;#NOERROR
update t4 set a=2;#ERROR: 1146 - Table 'test.t4' doesn't exist
CREATE TABLE ti (a INT UNSIGNED NOT NULL, b SMALLINT UNSIGNED NOT NULL, c CHAR(27), d VARCHAR(74) NOT NULL, e VARBINARY(67), f VARCHAR(88) NOT NULL, g LONGBLOB, h LONGBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=myisam;#ERROR: 1050 - Table 'ti' already exists
CREATE TABLE t2 (a varchar(10));#NOERROR
set var1 = -9.22e+15;#ERROR: 1193 - Unknown system variable 'var1'
insert into t values (652,0);#NOERROR
prepare abc from "alter event xyz comment 'xyz'";#ERROR: 1054 - Unknown column 'alter event xyz comment 'xyz'' in 'field list'
SELECT `ÇbÇP`, SUBSTRING(`ÇbÇP`,3) FROM `ÇsÇV`;#NOERROR
INSERT INTO `table1_innodb` (`col_document_not_null`) VALUES (' [ true , [ "value" , "%" , true , "%" ] ] ');#ERROR: 1146 - Table 'test.table1_innodb' doesn't exist
INSERT INTO t312 VALUES('a');#ERROR: 1146 - Table 'test.t312' doesn't exist
UPDATE t1 set spatial_point=GeomFromText('POINT(230 9)') where c1 like 'y%';#ERROR: 1054 - Unknown column 'c1' in 'where clause'
INSERT INTO t1  VALUES(0xF4AD);#NOERROR
CREATE TEMPORARY TABLE `ÔΩ¥ÔΩ¥ÔΩ¥`(`ÔΩπÔΩπÔΩπ` char(1)) DEFAULT CHARSET = utf8 engine=RocksDB;#NOERROR
SELECT SHA2( x'b1f83a5ea85d72c9721d166b1e9c51d6cb0dd6fe6b2ac88fc728d883c4eaadf3e475882d0fa42808941ceb746b833755bded1892a5', 224 ) = '0a53a62f28cc4db2025dd9175e571912c1a8bd0b293d235f7a0c568a' as NIST_SHA224_test_vector;#NOERROR
ALTER TABLE t1 ADD COLUMN c INT GENERATED ALWAYS AS(a+b), ADD INDEX idx (c), ALGORITHM=INPLACE, LOCK=NONE;#ERROR: 1054 - Unknown column 'b' in 'GENERATED ALWAYS AS'
SET @old_max_heap_table_size = @@max_heap_table_size;#NOERROR
CREATE TABLE ti (a BIGINT UNSIGNED, b SMALLINT NOT NULL, c BINARY(30), d VARBINARY(23), e VARCHAR(2) NOT NULL, f VARCHAR(22) NOT NULL, g TINYBLOB NOT NULL, h BLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
SELECT * FROM t1  WHERE c1 <= 16777216 ORDER BY c1,c6 DESC LIMIT 2;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
SELECT a AS x, ROW(11, 12) = (SELECT MAX(x), 22), ROW(11, 12) IN (SELECT MAX(x), 22) FROM t1;#NOERROR
select concat('From JSON col ',c, ' as DECIMAL(5,2)'), cast(j as DECIMAL(5,2)) from t where c='opaque_mysql_type_year';#ERROR: 1054 - Unknown column 'c' in 'field list'
CREATE TABLE t1(a INT) ENGINE = RocksDB;#ERROR: 1050 - Table 't1' already exists
select count(*) from performance_schema.events_stages_summary_by_thread_by_event_name;#NOERROR
CREATE TABLE t1(b TEXT CHARSET LATIN1, FULLTEXT(b), PRIMARY KEY(b(10))) ENGINE=INNODB;#ERROR: 1050 - Table 't1' already exists
EXPLAIN PARTITIONS SELECT * FROM t1  WHERE a <= 1;#NOERROR
CREATE TABLE t2 (`bit_key` bit(4), `bit` bit, key (`bit_key` )) ENGINE=TokuDB;#ERROR: 1050 - Table 't2' already exists
SELECT IF('SELECT COUNT(*) FROM t1 WHERE a IS NULL' REGEXP '^[a-zA-Z_][a-zA-Z_0-9]*:', LOCATE(':', 'SELECT COUNT(*) FROM t1 WHERE a IS NULL'), 0);#NOERROR
SELECT SUBSTRING('1', 1, 1);#NOERROR
CREATE TABLE t1 (a DATETIME) PARTITION BY HASH (EXTRACT(DAY_HOUR FROM a));#ERROR: 1050 - Table 't1' already exists
UPDATE `table1_innodb` SET `col_document_not_null`.1.2.1.SetNotExists(`col_document`.2.1.2) WHERE `col_document_not_null` != DOCUMENT('  { "k1": false  } ');#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '.1.2.1.SetNotExists(`col_document`.2.1.2) WHERE `col_document_not_null` != DO...' at line 1
source extra/rpl_tests/rpl_innodb.test;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'source extra/rpl_tests/rpl_innodb.test' at line 1
INSERT INTO t1 VALUES(0xF4C6);#NOERROR
insert INTO t1 (b) values (10);#ERROR: 1054 - Unknown column 'b' in 'field list'
ALTER TABLE t1 ADD c2 TEXT  NULL FIRST;#NOERROR
select col1 from wl1612 where col1>4 and col2=1.0123456789;#ERROR: 1146 - Table 'test.wl1612' doesn't exist
CREATE TABLE t2(c1 INT PRIMARY KEY, c2 char(20)) ENCRYPTION="Y" ENGINE = MEMORY;#ERROR: 1050 - Table 't2' already exists
insert into t2 values (12234+0.75);#NOERROR
CREATE TABLE ti (a TINYINT UNSIGNED, b INT NOT NULL, c CHAR(93), d VARBINARY(13) NOT NULL, e VARBINARY(90) NOT NULL, f VARBINARY(67), g BLOB NOT NULL, h LONGBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=TokuDB;#ERROR: 1050 - Table 'ti' already exists
select IF(GET_JSON_WEIGHT(JSON_TYPE(CAST(a._mes as JSON)))=GET_JSON_WEIGHT(JSON_TYPE(CAST(b.col as JSON))),'2nd Level','1st Level') validation_stage, a._mes as side1, b.col as side2, JSON_TYPE(CAST(a._mes as JSON)) as side1_json_type, JSON_TYPE(CAST(b.col as JSON)) as side2_json_type, GET_JSON_WEIGHT(JSON_TYPE(CAST(a._mes as JSON))) as side1_json_weightage, GET_JSON_WEIGHT(JSON_TYPE(CAST(b.col as JSON))) as side2_json_weightage, a._mes <=> b.col as json_compare, GET_JSON_WEIGHT(JSON_TYPE(CAST(a._mes as JSON))) <=> GET_JSON_WEIGHT(JSON_TYPE(CAST(b.col as JSON))) as first_level_validation from t_mes a , jj b where a._mes is not NULL and b.col is not NULL and JSON_TYPE(CAST(a._mes as JSON))!='BLOB' and JSON_TYPE(CAST(b.col as JSON))!='BLOB' and ((a._mes <=> b.col) != ( GET_JSON_WEIGHT(JSON_TYPE(CAST(a._mes as JSON))) GET_JSON_WEIGHT(JSON_TYPE(CAST(b.col as JSON))) echo "Testcase for unsigned Medium Int";#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'JSON)))=GET_JSON_WEIGHT(JSON_TYPE(CAST(b.col as JSON))),'2nd Level','1st Leve...' at line 1
SET @@global.tx_read_only = TRUE;#NOERROR
SET @@session.lc_time_names=he_IL;#NOERROR
SELECT * FROM t1  WHERE c1 <=> 1 ORDER BY c1 DESC;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
create TABLE t1 (id int primary key) engine = RocksDB key_block_size = 1;#ERROR: 1050 - Table 't1' already exists
INSERT INTO ti VALUES (-1014489605,86,'7Pk2KsrOtQZDqKhVHilzukvOKTQmUf','IzK0zBQzN7VHvCuIDG64Wrzhxf1kwIAKsWtlgn0hBFRveFBNiS3FEBLKIngKjT5gioWphHpgStvNsWZbAOqpcaBVhP4eCOgxfXsIZCpZQCDrsnCgclV1aJsGQx5xDnOInDGCUUs3YEdTfCt','D4LwS4yrVRfekutSMAbfO','crpRh9NKYghR','u','i',4);#NOERROR
CREATE TABLE `table0` ( `col0` tinyint(1) DEFAULT NULL, `col1` tinyint(1) DEFAULT NULL, `col2` tinyint(4) DEFAULT NULL, `col3` date DEFAULT NULL, `col4` time DEFAULT NULL, `col5` set('test1','test2','test3') DEFAULT NULL, `col6` time DEFAULT NULL, `col7` text, `col8` decimal(10,0) DEFAULT NULL, `col9` set('test1','test2','test3') DEFAULT NULL, `col10` float DEFAULT NULL, `col11` double DEFAULT NULL, `col12` enum('test1','test2','test3') DEFAULT NULL, `col13` tinyblob, `col14` year(4) DEFAULT NULL, `col15` set('test1','test2','test3') DEFAULT NULL, `col16` decimal(10,0) DEFAULT NULL, `col17` decimal(10,0) DEFAULT NULL, `col18` blob, `col19` datetime DEFAULT NULL, `col20` double DEFAULT NULL, `col21` decimal(10,0) DEFAULT NULL, `col22` datetime DEFAULT NULL, `col23` decimal(10,0) DEFAULT NULL, `col24` decimal(10,0) DEFAULT NULL, `col25` longtext, `col26` tinyblob, `col27` time DEFAULT NULL, `col28` tinyblob, `col29` enum('test1','test2','test3') DEFAULT NULL, `col30` smallint(6) DEFAULT NULL, `col31` double DEFAULT NULL, `col32` float DEFAULT NULL, `col33` char(175) DEFAULT NULL, `col34` tinytext, `col35` tinytext, `col36` tinyblob, `col37` tinyblob, `col38` tinytext, `col39` mediumblob, `col40` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, `col41` double DEFAULT NULL, `col42` smallint(6) DEFAULT NULL, `col43` longblob, `col44` varchar(80) DEFAULT NULL, `col45` mediumtext, `col46` decimal(10,0) DEFAULT NULL, `col47` bigint(20) DEFAULT NULL, `col48` date DEFAULT NULL, `col49` tinyblob, `col50` date DEFAULT NULL, `col51` tinyint(1) DEFAULT NULL, `col52` mediumint(9) DEFAULT NULL, `col53` float DEFAULT NULL, `col54` tinyblob, `col55` longtext, `col56` smallint(6) DEFAULT NULL, `col57` enum('test1','test2','test3') DEFAULT NULL, `col58` datetime DEFAULT NULL, `col59` mediumtext, `col60` varchar(232) DEFAULT NULL, `col61` decimal(10,0) DEFAULT NULL, `col62` year(4) DEFAULT NULL, `col63` smallint(6) DEFAULT NULL, `col64` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00', `col65` blob, `col66` longblob, `col67` int(11) DEFAULT NULL, `col68` longtext, `col69` enum('test1','test2','test3') DEFAULT NULL, `col70` int(11) DEFAULT NULL, `col71` time DEFAULT NULL, `col72` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00', `col73` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00', `col74` varchar(170) DEFAULT NULL, `col75` set('test1','test2','test3') DEFAULT NULL, `col76` tinyblob, `col77` bigint(20) DEFAULT NULL, `col78` decimal(10,0) DEFAULT NULL, `col79` datetime DEFAULT NULL, `col80` year(4) DEFAULT NULL, `col81` decimal(10,0) DEFAULT NULL, `col82` longblob, `col83` text, `col84` char(83) DEFAULT NULL, `col85` decimal(10,0) DEFAULT NULL, `col86` float DEFAULT NULL, `col87` int(11) DEFAULT NULL, `col88` varchar(145) DEFAULT NULL, `col89` date DEFAULT NULL, `col90` decimal(10,0) DEFAULT NULL, `col91` decimal(10,0) DEFAULT NULL, `col92` mediumblob, `col93` time DEFAULT NULL, KEY `idx0` (`col69`,`col90`,`col8`), KEY `idx1` (`col60`), KEY `idx2` (`col60`,`col70`,`col74`), KEY `idx3` (`col22`,`col32`,`col72`,`col30`), KEY `idx4` (`col29`), KEY `idx5` (`col19`,`col45`(143)), KEY `idx6` (`col46`,`col48`,`col5`,`col39`(118)), KEY `idx7` (`col48`,`col61`), KEY `idx8` (`col93`), KEY `idx9` (`col31`), KEY `idx10` (`col30`,`col21`), KEY `idx11` (`col67`), KEY `idx12` (`col44`,`col6`,`col8`,`col38`(226)), KEY `idx13` (`col71`,`col41`,`col15`,`col49`(88)), KEY `idx14` (`col78`), KEY `idx15` (`col63`,`col67`,`col64`), KEY `idx16` (`col17`,`col86`), KEY `idx17` (`col77`,`col56`,`col10`,`col55`(24)), KEY `idx18` (`col62`), KEY `idx19` (`col31`,`col57`,`col56`,`col53`), KEY `idx20` (`col46`), KEY `idx21` (`col83`(54)), KEY `idx22` (`col51`,`col7`(120)), KEY `idx23` (`col7`(163),`col31`,`col71`,`col14`) ) ENGINE=InnoDB DEFAULT CHARSET=latin1 ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=2;#ERROR: 1005 - Can't create table `test`.`table0` (errno: 140 "Wrong create options")
INSERT INTO t1  VALUES (1, 'customer_over', '1');#ERROR: 1136 - Column count doesn't match value count at row 1
insert into t1 values (8429,'8429');#NOERROR
USE `é∆éŒé›é∫éﬁ`;#ERROR: 1049 - Unknown database 'é∆éŒé›é∫éﬁ'
insert into mysql.ndb_replication values ("test", "t3oneex", 3, 7, "NDB$EPOCH()");#ERROR: 1146 - Table 'mysql.ndb_replication' doesn't exist
select * from RocksDB.session_variables where variable_name='RocksDB_ft_min_token_size';#ERROR: 1146 - Table 'RocksDB.session_variables' doesn't exist
INSERT INTO t1 VALUES('');#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t589 (c1 VARCHAR(10));#NOERROR
DROP TABLE t1;#NOERROR
SELECT INTERVAL(1^1,0,1,2) + 1;#NOERROR
insert into t3 values (2,3);#ERROR: 1146 - Table 'test.t3' doesn't exist
CREATE TABLE t_RocksDB (id INTEGER) engine= RocksDB;#NOERROR
CREATE TABLE m3(c1 BIT NULL, c2 CHAR(25) NOT NULL, c3 BIGINT(4) NULL, c4 CHAR(15) NOT NULL PRIMARY KEY, c5 BIT NOT NULL UNIQUE KEY,c6 NUMERIC(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 'm3' already exists
SELECT * FROM (SELECT 1 a UNION (SELECT 1 a INTO DUMPFILE 'file' )) t1a;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'INTO DUMPFILE 'file' )) t1a' at line 1
CREATE TABLE t789 (c1 VARCHAR(10));#NOERROR
CREATE TABLE t1 (a int(10) , PRIMARY KEY (a)) Engine=InnoDB;#NOERROR
CREATE TABLE ti (a MEDIUMINT, b INT NOT NULL, c CHAR(12) NOT NULL, d VARBINARY(61) NOT NULL, e VARCHAR(12), f VARCHAR(77), g LONGBLOB NOT NULL, h BLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
SET @@session.sql_mode = DISABLE;#ERROR: 1231 - Variable 'sql_mode' can't be set to the value of 'DISABLE'
SELECT CONCAT('SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 4294967295)', 'ZZENDZZ') REGEXP '[a-zA-Z_][a-zA-Z0-9_]* *, *[0-9][0-9]* *ZZENDZZ';#NOERROR
CREATE PROCEDURE longblob() SELECT * FROM t1  where f2=f1;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'longblob() SELECT * FROM t1  where f2=f1' at line 1
SELECT COUNT(*) FROM t1 WHERE a IS NULL;#NOERROR
SELECT SUBSTRING('11', 2);#NOERROR
SELECT * FROM t3 WHERE c1 IN ('0000-00-00','2010-00-01') ORDER BY c1,c2 DESC LIMIT 2;#ERROR: 1146 - Table 'test.t3' doesn't exist
delete from performance_schema.threads;#ERROR: 1142 - DELETE command denied to user 'root'@'localhost' for table 'threads'
SELECT QUOTE(REPLACE('[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 16777215)] = 1', CONCAT('[', 'SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 16777215)', ']'), '1'));#NOERROR
DROP TABLE t1;#NOERROR
SET @@global.lc_messages = @start_global_value;#ERROR: 1231 - Variable 'lc_messages' can't be set to the value of 'NULL'
CREATE TABLE t1 ( val integer not null ) ENGINE = TokuDB;#NOERROR
INSERT INTO t1 VALUES(0xAAB3);#NOERROR
desc v1;#NOERROR
SELECT SUBSTRING('0', 1, 1);#NOERROR
CREATE TABLE IF NOT EXISTS `ÈæñÈæñÈæñ`(`‰∏Ç‰∏Ç‰∏Ç` char(1)) DEFAULT CHARSET = utf8 engine=RocksDB;#NOERROR
CREATE TABLE t1( a VARCHAR(257) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=InnoDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=InnoDB' at line 1
CREATE TABLE t1 (count INT, unix_time INT, local_time INT, comment CHAR(80));#ERROR: 1050 - Table 't1' already exists
CREATE TABLE ti (a MEDIUMINT UNSIGNED, b INT UNSIGNED NOT NULL, c CHAR(11) NOT NULL, d VARCHAR(91) NOT NULL, e VARBINARY(29), f VARCHAR(33) NOT NULL, g BLOB, h BLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
CREATE TABLE `£‘£±` (`£√£±` char(20)) DEFAULT CHARSET = ujis engine = RocksDB;#NOERROR
SET @@session.read_buffer_size = @start_session_value;#ERROR: 1232 - Incorrect argument type to variable 'read_buffer_size'
INSERT INTO t VALUES (3298531845,4164183,'s6XCcz0C6gmr0DSh','UpSZ6YDwjLWbtRi','jkjXxFvUiR8UTiKrNCxKoS8q648P28v0N9Jjt5DlY4PEkbv','2nM7LEtEzxk5jecyB5nJzXZR38f1ZBlLucGi0g2bg08U8dIXHsHKtPmnejEAEbSe','9','z',1);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT * FROM t3 WHERE c2 > -128 ORDER BY c2,c7 LIMIT 2;#ERROR: 1146 - Table 'test.t3' doesn't exist
SHOW FUNCTION STATUS LIKE 'fn5';#NOERROR
insert into at(c,_flo) select concat('_flo: ',c), (select j from t where c='stringdecimal') from t where c='stringdecimal';#ERROR: 1146 - Table 'test.at' doesn't exist
SET @var2='abcd\"ef';#NOERROR
select t1.i,t2.i,t3.i FROM t1  right join t1 on (t2.i=t3.i),t1 order by t1.i,t2.i,t3.i;#ERROR: 1066 - Not unique table/alias: 't1'
CREATE FULLTEXT INDEX i ON t1 ( s1);#ERROR: 1072 - Key column 's1' doesn't exist in table
INSERT INTO t1  VALUES ('0.5');#NOERROR
insert INTO t1  values (4,null, 2);#ERROR: 1136 - Column count doesn't match value count at row 1
SET GLOBAL innodb_buffer_pool_evict = 'uncompressed';#ERROR: 1193 - Unknown system variable 'innodb_buffer_pool_evict'
SELECT ST_DISJOINT(g,g2) FROM gis_geometrycollection,gis_geometrycollection_2 WHERE fid=103 and fid2=103;#ERROR: 1146 - Table 'test.gis_geometrycollection' doesn't exist
SELECT SUBSTRING('0', 2);#NOERROR
SELECT TIMESTAMP(CAST(a AS DATETIME(6)), CAST('00:00:00' AS TIME(0))) FROM t1;#ERROR: 1054 - Unknown column 'a' in 'field list'
SELECT 1 % .123456789123456789123456789123456789123456789123456789123456789123456789123456789 AS '%';#NOERROR
select host,db,user,table_name,column_name from RocksDB.columns_priv where user like '_%' order by host,db,user,table_name,column_name;#ERROR: 1146 - Table 'RocksDB.columns_priv' doesn't exist
SELECT * FROM t2 WHERE c1 < 18446744073709551616 ORDER BY c1,c6 DESC LIMIT 2;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
ALTER TABLE t1 ADD bin_f CHAR(1) BYTE NOT NULL default '';#NOERROR
SELECT IF('SELECT COUNT(*) FROM t1 WHERE a IS NULL' REGEXP '^[a-zA-Z_][a-zA-Z_0-9]*:', LOCATE(':', 'SELECT COUNT(*) FROM t1 WHERE a IS NULL'), 0);#NOERROR
CREATE TABLE t224 (c1 INTEGER);#NOERROR
INSERT INTO t576 VALUES('a');#ERROR: 1146 - Table 'test.t576' doesn't exist
SELECT * FROM t1 LEFT JOIN t2 ON t1.a = t2.a WHERE NOT(t1.a != t2.a AND t1.a BETWEEN t2.b AND t1.b);#ERROR: 1054 - Unknown column 't1.a' in 'where clause'
INSERT INTO ti VALUES (-9928400650497945,6408941533720907573,'jW26B','kjChAySaBMfCVNbZM3tsEYHvngbDhjEubB4mR0QFAEQsQCqCejmIerlem1Cxu95X0A6lcEFUjMFO3Vg4O0mwFUHaLIlvtRNPJsJU4aSgbmZDshZoBrIGw37uMOvRuQT5JtADMvOpIJHvHFPrRPeaFrttSFeSu3yix6tNd11yf3JHTASE3bR2yTqx2Q1lilcuMqsjBOwaPyCNAi6MxSeiaGFFDU','KdlVfubyhtb','FcuZq7aYOKMnv0LdcoIgogR4X0yoUgKnH343fJ6nu79miQLAOMCdEFXw9f3wjFXOXhAqVm2E5D9v7y4AbvfVqhQN8CdbkPMEsBa9EydPonpnpruI7QJQjEb9wrEvdzativ2uUai17iW60dBozr','g','1m',6);#NOERROR
create table t1 (a varchar(10), fulltext key(a)) ENGINE = RocksDB;#ERROR: 1050 - Table 't1' already exists
select round(1e0, -309), truncate(1e0, -309);#NOERROR
SELECT pos INTO @original_column_pos FROM information_schema.RocksDB_sys_columns WHERE table_id = @original_table_id AND name = 'a';#ERROR: 1109 - Unknown table 'RocksDB_sys_columns' in information_schema
CREATE TABLE `£‘£±a` (`£√£±` char(1) PRIMARY KEY) DEFAULT CHARSET = ujis engine = innodb;#NOERROR
CREATE TABLE t1 (word CHAR(20) NOT NULL) ENGINE=INNODB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t1 ( a int not null PRIMARY KEY, b int not null, c int not null) partition by list(a) partitions 2 (partition x123 values in (1,5,6), partition x234 values in (4,7,8));#ERROR: 1050 - Table 't1' already exists
CREATE TABLE m3(c1 DATETIME NULL, c2 BINARY(25) NOT NULL, c3 MEDIUMINT(4) NULL, c4 BINARY(15) NOT NULL PRIMARY KEY, c5 DATETIME NOT NULL UNIQUE KEY,c6 FIXED(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 'm3' already exists
ALTER TABLE t1 MODIFY c1 LONGTEXT NOT NULL;#ERROR: 1054 - Unknown column 'c1' in 't1'
CREATE TABLE t1 (c1 INT PRIMARY KEY, c2 INT, INDEX(c2)) ENGINE = RocksDB;#ERROR: 1050 - Table 't1' already exists
insert INTO t1  values(1,10),(1,20);#NOERROR
RENAME TABLE t1 TO T1;#NOERROR
CREATE PROCEDURE p1(in f1 float(23) zerofill, inout f2 float(23) zerofill, out f3 float(23) zerofill, in f4 bigint, inout f5 bigint, out f6 bigint, in f7 bigint, inout f8 bigint, out f9 bigint, in f10 bigint, inout f11 bigint, out f12 bigint) BEGIN set f1 = (f1 / 2);#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
CREATE TABLE IF NOT EXISTS `table1` (`col0` CHAR (113), `col1` FLOAT, `col2` BIGINT, `col3` DECIMAL, `col4` BLOB, `col5` LONGTEXT, `col6` SET ('test1','test2','test3'), `col7` BIGINT, `col8` BIGINT, `col9` TINYBLOB, KEY `idx0` (`col5`(101),`col7`,`col8`), KEY `idx1` (`col8`), KEY `idx2` (`col4`(177),`col9`(126),`col6`,`col3`), KEY `idx3` (`col5`(160)), KEY `idx4` (`col9`(242)), KEY `idx5` (`col4`(139),`col2`,`col3`), KEY `idx6` (`col7`), KEY `idx7` (`col6`,`col2`,`col0`,`col3`), KEY `idx8` (`col9`(66)), KEY `idx9` (`col5`(253)), KEY `idx10` (`col1`,`col7`,`col2`), KEY `idx11` (`col9`(242),`col0`,`col8`,`col5`(163)), KEY `idx12` (`col8`), KEY `idx13` (`col0`,`col9`(37)), KEY `idx14` (`col0`), KEY `idx15` (`col5`(111)), KEY `idx16` (`col8`,`col0`,`col5`(13)), KEY `idx17` (`col4`(139)), KEY `idx18` (`col5`(189),`col2`,`col3`,`col9`(136)), KEY `idx19` (`col0`,`col3`,`col1`,`col8`), KEY `idx20` (`col8`), KEY `idx21` (`col0`,`col7`,`col9`(227),`col3`), KEY `idx22` (`col0`), KEY `idx23` (`col2`), KEY `idx24` (`col3`), KEY `idx25` (`col2`,`col3`), KEY `idx26` (`col0`), KEY `idx27` (`col5`(254)), KEY `idx28` (`col3`), KEY `idx29` (`col3`), KEY `idx30` (`col7`,`col3`,`col0`,`col4`(220)), KEY `idx31` (`col4`(1),`col0`) )engine=TokuDB ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=1;#ERROR: 1005 - Can't create table `test`.`table1` (errno: 140 "Wrong create options")
SET @@global.RocksDB_data_pointer_size = 1;#ERROR: 1193 - Unknown system variable 'RocksDB_data_pointer_size'
CREATE TABLE t1(s1 INT UNIQUE) ENGINE=TokuDB;#NOERROR
insert into at(c,_boo) select concat('_boo: ',c), json_extract(j, '$') from t where c='opaque_mysql_type_year';#ERROR: 1146 - Table 'test.at' doesn't exist
INSERT INTO t1  SET c2='07:23:55';#ERROR: 1054 - Unknown column 'c2' in 'field list'
SELECT '1 = 1';#NOERROR
insert into t1 (a) values (3);#ERROR: 1054 - Unknown column 'a' in 'field list'
INSERT INTO t VALUES (-7246720873069788361,113,'b7w454UISQjc','VjshRl5A1wwApzhvl86dKmdlttHzN6UfeMcwRiwe5mEoCfuJyu8dwacSOlhgof','KOQS5hvVsEBBu5uh5LKljVebcSOseYwYA8qd5Y2vUzh7','Z0wqc7uI0bVDb1nBrOO82qZNHPxoQeCRZ','T','q',9);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t1(c1 DOUBLE NULL, c2 BINARY(25) NOT NULL, c3 TINYINT(4) NULL, c4 BINARY(15) NOT NULL PRIMARY KEY, c5 DOUBLE NOT NULL UNIQUE KEY,c6 DECIMAL(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 't1' already exists
SELECT SUBSTRING('1', 1, 1);#NOERROR
SELECT `£√£±`, SUBSTRING(`£√£±` FROM 6) FROM `£‘£±`;#NOERROR
insert into t1 values (2458,'2458');#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE ar_1114 (a INT, PRIMARY KEY (a)) ENGINE=RocksDB;#NOERROR
CREATE TABLE ti (a INT UNSIGNED, b SMALLINT NOT NULL, c BINARY(72), d VARCHAR(87), e VARCHAR(7), f VARBINARY(27) NOT NULL, g BLOB NOT NULL, h LONGBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
create temporary table t1_temp(i int) engine=RocksDB;#NOERROR
SELECT SUBSTRING_INDEX('Replicate_Wild_Ignore_Table,Last_Errno,Last_Error,Skip_Counter,Until_Condition,Until_Log_File,Until_Log_Pos,Master_SSL_Allowed,Master_SSL_CA_File,Master_SSL_CA_Path,Master_SSL_Cert,Master_SSL_Cipher,Master_SSL_Key,Seconds_Behind_Master,Master_SSL_Verify_Server_Cert,Last_SQL_Errno,Last_SQL_Error,Replicate_Ignore_Server_Ids,Master_Server_Id', ',', 1);#NOERROR
DROP PROCEDURE IF EXISTS p1;#NOERROR
insert into t1 values (1675,'1675');#ERROR: 1136 - Column count doesn't match value count at row 1
prepare stmt from "update t2 set a=a+1 where (1) in (select * from t1)";#ERROR: 1054 - Unknown column 'update t2 set a=a+1 where (1) in (select * from t1)' in 'field list'
select @@global.relay_log_space_limit;#NOERROR
SELECT MBRWITHIN(ST_GEOMFROMTEXT(@star_elem_vertical),ST_GEOMFROMTEXT('MULTIPOINT(0 0,30 25)'));#NOERROR
CREATE TABLE t1 (a INT PRIMARY KEY) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
insert into t values ("hello world");#ERROR: 1054 - Unknown column 'hello world' in 'field list'
INSERT INTO t1 VALUES (5,'2009-07-28 18:19:54','i');#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE db1.t0_temp ENGINE=InnoDB AS SELECT * FROM db1.t0_data;#ERROR: 1146 - Table 'db1.t0_data' doesn't exist
CREATE TABLE `£‘£±` (`£√£±` char(20)) DEFAULT CHARSET = ujis engine = TokuDB;#ERROR: 1050 - Table '£‘£±' already exists
SELECT LOCATE(']', '[SELECT COUNT(*) FROM t1 WHERE a = ""] = 1');#NOERROR
DROP PROCEDURE spexecute91;#ERROR: 1305 - PROCEDURE test.spexecute91 does not exist
insert into t1 values (2574,'2574');#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT * FROM t1  WHERE c2 BETWEEN 0 AND 16777215 ORDER BY c2,c1;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
create procedure f2 () begin select sql_cache * FROM t1  where s1=1;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
DROP TABLE t1;#NOERROR
insert into t values (4383,0);#NOERROR
SELECT SUBSTRING('default,', LENGTH('default') + 2);#NOERROR
SELECT * FROM t1  WHERE c1 BETWEEN '0000-00-00' AND '2010-00-01 00:00:' ORDER BY c1 DESC LIMIT 2;#ERROR: 1146 - Table 'test.t1' doesn't exist
insert into t3(a,b) values(1,1);#ERROR: 1146 - Table 'test.t3' doesn't exist
DROP PROCEDURE IF EXISTS spexecute46;#NOERROR
CHECK TABLE t2;#NOERROR
SELECT HEX('ç≤ìëÅ@å\') FROM DUAL;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near ''\008D≤ìë\0081@å\') FROM DUAL' at line 1
SELECT SUBSTRING('1', 2);#NOERROR
SELECT * FROM t1  WHERE c1 <=> 108 ORDER BY c1,c6 DESC;#ERROR: 1146 - Table 'test.t1' doesn't exist
INSERT into t1 VALUES (2,2,1);#ERROR: 1146 - Table 'test.t1' doesn't exist
CREATE TABLE `ÈæóÈæóÈæó`(`‰∏Ñ‰∏Ñ‰∏Ñ` char(1)) DEFAULT CHARSET = utf8 engine=INNODB;#NOERROR
CREATE INDEX IX ON t10(I);#ERROR: 1146 - Table 'test.t10' doesn't exist
ALTER TABLE t CHANGE COLUMN a b BINARY(160);#ERROR: 1054 - Unknown column 'a' in 't'
INSERT INTO t1  ( a ) SELECT 0 ON DUPLICATE KEY UPDATE a = a + VALUES (a);#ERROR: 1146 - Table 'test.t1' doesn't exist
insert into t2 values (31651);#NOERROR
CREATE TABLE t5(c1 BIGINT NOT NULL PRIMARY KEY, c2 INT NOT NULL, c3 CHAR(10) NOT NULL);#NOERROR
create TABLE t1 (f1 int primary key, f2 int, key k1(f2)) engine=RocksDB;#NOERROR
CREATE TABLE t708 (c1 INTEGER);#NOERROR
set max_join_size= @tmp_906385;#ERROR: 1232 - Incorrect argument type to variable 'max_join_size'
SELECT SUBSTRING('11', 1, 1);#NOERROR
SET @@global.gtid_precommit = FALSE;#ERROR: 1193 - Unknown system variable 'gtid_precommit'
CREATE TABLE t3(c1 CHAR(10) NOT NULL) ENGINE = TokuDB;#NOERROR
CREATE TABLE t1(c1 INTEGER NOT NULL, c2 TIME NOT NULL, c3 INT NULL, c4 VARCHAR(10) NOT NULL);#ERROR: 1050 - Table 't1' already exists
INSERT INTO test.t2 VALUES(NULL,0,'Testing MySQL databases is a cool ', 'MySQL Customers ROCK!',654321.4321,1.24521,0,YEAR(NOW()),NOW());#ERROR: 1136 - Column count doesn't match value count at row 1
SET GLOBAL innodb_thread_sleep_delay = @innodb_thread_sleep_delay_orig;#ERROR: 1232 - Incorrect argument type to variable 'innodb_thread_sleep_delay'
CREATE VIEW v2 AS SELECT * FROM v1;#ERROR: 1449 - The user specified as a definer ('test14256'@'%') does not exist
DROP PROCEDURE IF EXISTS sp7;#NOERROR
SELECT REPEAT('0', -2);#NOERROR
insert into t1 values (+.1);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT * FROM t1  WHERE c1 >= '1971-01-01 00:00:01' AND c1 < '2038-01-09 03:14:07' AND c2 = '2038-01-09 03:14:07' ORDER BY c1,c2 LIMIT 2;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
UPDATE v SET a=1 LIMIT 3;#ERROR: 1146 - Table 'test.v' doesn't exist
SELECT * FROM t1 WHERE c2 >= '-99999.99999' ORDER BY c1,c2 DESC;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
SELECT * FROM federated.t1 WHERE name = 'Third Name' AND other = '3333';#ERROR: 1146 - Table 'federated.t1' doesn't exist
DELETE FROM t1;#NOERROR
CREATE TABLE t (a VARCHAR(1000000)) ENGINE = InnoDB;#ERROR: 1050 - Table 't' already exists
SELECT * FROM t1  WHERE c1 >= '99999.99999' ORDER BY c1,c2;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
SELECT LOCATE(']', '1 = 1');#NOERROR
SET @start_global_value = @@global.rpl_semi_sync_slave_enabled;#NOERROR
SET GLOBAL RocksDB_kill_idle_transaction=0;#ERROR: 1193 - Unknown system variable 'RocksDB_kill_idle_transaction'
set @@sql_mode="mysql323";#NOERROR
SET @str=IF(@have_ndbinfo,'CREATE OR REPLACE DEFINER=`root`@`localhost` SQL SECURITY INVOKER VIEW `ndbinfo`.`memory_per_fragment` AS SELECT name.fq_name, parent_name.fq_name AS parent_fq_name, types.type_name AS type, table_id, node_id, block_instance, fragment_num, fixed_elem_alloc_bytes, fixed_elem_free_bytes, fixed_elem_size_bytes, fixed_elem_count, FLOOR(fixed_elem_free_bytes/fixed_elem_size_bytes) AS fixed_elem_free_count, var_elem_alloc_bytes, var_elem_free_bytes, var_elem_count, hash_index_alloc_bytes FROM ndbinfo.ndb$frag_mem_use AS space JOIN ndbinfo.ndb$dict_obj_info AS name ON name.id=space.table_id AND name.type<=6 JOIN ndbinfo.ndb$dict_obj_types AS types ON name.type=types.type_id LEFT JOIN ndbinfo.ndb$dict_obj_info AS parent_name ON name.parent_obj_id=parent_name.id AND name.parent_obj_type=parent_name.type','SET @dummy = 0');#NOERROR
SELECT @@session.max_heap_table_size = 16777216;#NOERROR
CREATE TABLE t1 ( a int not null, b int not null, c int not null, primary key(a,b)) partition by key (a) partitions 3 (partition x1 engine RocksDB, partition x2 engine RocksDB, partition x3 engine RocksDB);#ERROR: 1050 - Table 't1' already exists
select evend_id,server_id FROM t1  order by evend_id;#ERROR: 1054 - Unknown column 'evend_id' in 'field list'
XA PREPARE '4';#ERROR: 1399 - XAER_RMFAIL: The command cannot be executed when global transaction is in the  NON-EXISTING state
CREATE TABLE t1( a TINYTEXT COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = REDUNDANT ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = REDUNDANT ENGINE=RocksDB' at line 1
SELECT 1 = 1;#NOERROR
CREATE TABLE `ibstd_16_fk` ( `a` int(11) DEFAULT NULL, `d` int(11) DEFAULT NULL, `b` varchar(198) DEFAULT NULL, `c` char(179) DEFAULT NULL, `vbcol` char(2) GENERATED ALWAYS AS (substr(b,2,2)) VIRTUAL, `vbidxcol` char(3) GENERATED ALWAYS AS (substr(b,1,3)) VIRTUAL, UNIQUE KEY `b` (`b`(10),`a`,`d`), KEY `d` (`d`), KEY `a` (`a`), KEY `c` (`c`(99),`b`(33)), KEY `b_2` (`b`(5),`c`(10),`a`), KEY `vbidxcol` (`vbidxcol`), KEY `a_2` (`a`,`vbidxcol`), KEY `vbidxcol_2` (`vbidxcol`,`d`) ) ENGINE=RocksDB;#NOERROR
SELECT * FROM t1  WHERE a='01:02:03.45';#ERROR: 1054 - Unknown column 'a' in 'where clause'
SELECT SUBSTRING('11', 2);#NOERROR
insert INTO t1  set ujis=0x62, name='U+0062 LATIN SMALL LETTER B';#ERROR: 1054 - Unknown column 'ujis' in 'field list'
INSERT INTO t VALUES (14414839,108,'v4Ov8ukpOtPkzfQ','Js2uHC2KyE1T3','63nJneGlKYNpc6WhQ0q4hHchIpXxGmoF55US3S3qX9H1anXc604exRHZwdCjgxtyzGwbGdeVqvmzB4x6ODt','WLXfDX2rOTNMCfPJy5wpLxIlxMDjg52v43sQplOaa12rnvzreBN','F','5',7);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT * FROM t1  WHERE c1 BETWEEN '0000-00-00' AND '9999-12-31' ORDER BY c1 DESC;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
explain extended select lcase(_latin2'a');#NOERROR
insert into t1 values(3985);#ERROR: 1136 - Column count doesn't match value count at row 1
ALTER TABLE t CHANGE COLUMN a a VARBINARY(410);#ERROR: 1054 - Unknown column 'a' in 't'
SELECT 10573 MOD 5000;#NOERROR
CREATE PROCEDURE p1() BEGIN declare numeric unsigned not null x;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'numeric unsigned not null x' at line 1
update t1 set name='U+3079 HIRAGANA LETTER BE' where ujis=0xA4D9;#ERROR: 1054 - Unknown column 'ujis' in 'where clause'
CREATE TABLE ti (a INT, b SMALLINT, c CHAR(48), d VARCHAR(37), e VARBINARY(41) NOT NULL, f VARCHAR(52) NOT NULL, g MEDIUMBLOB, h BLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
SELECT SUBSTRING('1', 1, 1);#NOERROR
SET @@session.lc_time_names=mn_MN;#NOERROR
create table t2 (j int primary key) engine=RocksDB;#ERROR: 1050 - Table 't2' already exists
SELECT SUBSTRING('1', 1, 1);#NOERROR
create table t1 (c1 int, c2 int);#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t1(i int, id INT AUTO_INCREMENT, PRIMARY KEY (i, id)) ENGINE=MYISAM;#ERROR: 1050 - Table 't1' already exists
SELECT COUNT(*) = 0 AS original_dictionary_reference_cleared FROM information_schema.xtradb_zip_dict_cols WHERE table_id = @original_table_id AND column_pos = @original_column_pos;#ERROR: 1109 - Unknown table 'xtradb_zip_dict_cols' in information_schema
CREATE TABLE `ÈæñÈæñÈæñ`(`‰∏Ç‰∏Ç‰∏Ç` char(5)) DEFAULT CHARSET = utf8 engine=RocksDB;#ERROR: 1050 - Table 'ÈæñÈæñÈæñ' already exists
alter TABLE t1 add i int not null first;#NOERROR
SET @@global.innodb_buffer_pool_resizing_timeout = 10;#ERROR: 1193 - Unknown system variable 'innodb_buffer_pool_resizing_timeout'
SELECT 1 = 1;#NOERROR
CREATE TABLE t1( a TINYTEXT COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = REDUNDANT ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = REDUNDANT ENGINE=RocksDB' at line 1
CREATE TABLE t1 ( a INT PRIMARY KEY, b INT, c CHAR(1), d INT, KEY (c,d) ) PARTITION BY KEY () PARTITIONS 1;#ERROR: 1050 - Table 't1' already exists
INSERT INTO t766 VALUES('a');#ERROR: 1146 - Table 'test.t766' doesn't exist
SELECT GROUP_CONCAT(c1 ORDER BY c1) FROM t1 GROUP BY c1 COLLATE ucs2_turkish_ci;#ERROR: 1253 - COLLATION 'ucs2_turkish_ci' is not valid for CHARACTER SET 'latin1'
insert into t2 values (11780);#NOERROR
insert into s values (1000000000,8073);#ERROR: 1146 - Table 'test.s' doesn't exist
CREATE TABLE `£‘£∑` (`£√£±` char(20), INDEX(`£√£±`)) DEFAULT CHARSET = ujis engine = InnoDB;#ERROR: 1050 - Table '£‘£∑' already exists
insert into t (id,a) values (256,1);#ERROR: 1054 - Unknown column 'id' in 'field list'
SELECT SUBSTRING('1', 2);#NOERROR
CREATE TABLE t (a INT NOT NULL, b VARCHAR(200), c TEXT, d DATETIME NOT NULL, e BIGINT NOT NULL, KEY(d,e)) ENGINE=RocksDB;#ERROR: 1050 - Table 't' already exists
create TABLE t1 (pk int primary key, b int) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t1(c1 REAL NULL, c2 CHAR(25) NOT NULL, c3 INT(4) NULL, c4 CHAR(15) NOT NULL PRIMARY KEY, c5 REAL NOT NULL UNIQUE KEY,c6 NUMERIC(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 't1' already exists
SELECT LOCATE(']', '[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 8191)] = 1');#NOERROR
CREATE TABLE t1 (p POINT NOT NULL UNIQUE) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
create table parent ( a int primary key auto_increment, b int, c int, unique(b) using hash, index(c)) ENGINE=INNODB;#NOERROR
SELECT COUNT(*) FROM t1 WHERE a <= CURRENT_TIMESTAMP;#ERROR: 1054 - Unknown column 'a' in 'where clause'
CREATE TABLE t1(c1 BIGINT AUTO_INCREMENT NULL UNIQUE KEY ) AUTO_INCREMENT=10;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t1(a INT) engine=MEMORY;#ERROR: 1050 - Table 't1' already exists
DROP TABLE t1;#NOERROR
SELECT 7158278827 * 3221225472;#NOERROR
create TABLE t1(j int);#ERROR: 1050 - Table 't1' already exists
SELECT SHA2( x'78817bc3f6285eca108e54b14091d1ebb9ecb1b7555dcc5acf07cbab32153ad591a0de59f9d24852a44caafd6fc6ea788ef5f5ca7fb256243c580767b56e86', 384 ) = 'a0ed388522b9bf2737b10071c9e22c9d6db99bb3808ea3248959d075062d845b872d2eeabfa4e123b4f738a685a3c41d' as NIST_SHA384_test_vector;#NOERROR
CREATE TABLE t1 ( faq_group_id int(11) NOT NULL default '0', faq_id int(11) NOT NULL default '0', title varchar(240) default NULL, keywords text, description longblob, solution longblob, status tinyint(4) NOT NULL default '0', access_id smallint(6) default NULL, lang_id smallint(6) NOT NULL default '0', created datetime NOT NULL default '0000-00-00 00:00:00', updated datetime default NULL, last_access datetime default NULL, last_notify datetime default NULL, solved_count int(11) NOT NULL default '0', static_solved int(11) default NULL, solved_1 int(11) default NULL, solved_2 int(11) default NULL, solved_3 int(11) default NULL, solved_4 int(11) default NULL, solved_5 int(11) default NULL, expires datetime default NULL, notes text, assigned_to smallint(6) default NULL, assigned_group smallint(6) default NULL, last_edited_by smallint(6) default NULL, orig_ref_no varchar(15) binary default NULL, c$fundstate smallint(6) default NULL, c$contributor smallint(6) default NULL, UNIQUE KEY t1$faq_id (faq_id), KEY t1$group_id$faq_id (faq_group_id,faq_id), KEY t1$c$fundstate (c$fundstate) ) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
SELECT * FROM t1 ;#NOERROR
DROP TABLE t211;#ERROR: 1051 - Unknown table 'test.t211'
create table t_bug25347 (a int) engine=TokuDB;#NOERROR
CREATE TABLE RocksDBtest2.t1 (a char(10));#ERROR: 1049 - Unknown database 'RocksDBtest2'
SELECT c1 FROM t5 WHERE c1 > '10' ORDER BY c1;#ERROR: 1146 - Table 'test.t5' doesn't exist
insert into mt1 values (407,'aaaaaaaaaaaaaaaaaaaa');#ERROR: 1146 - Table 'test.mt1' doesn't exist
prepare stmt1 from @arg00;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'NULL' at line 1
SET @create_table_referencing_zip_dict_sql = 'CREATE TABLE t1(' ' id INT,' ' a BLOB COLUMN_FORMAT COMPRESSED WITH COMPRESSION_DICTIONARY dict' ') ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '') ENGINE=RocksDB' at line 1
DROP TABLE IF EXISTS table_12976_a;#NOERROR
select hex(substr(_utf32 0x000000e4000000e500000068,-2));#NOERROR
INSERT INTO t1  VALUES('a');#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO t VALUES (1033161083831064264,11597078335613159988,'AcxqCiaeP','TX9T4KyAnEUcNbOzn7XWYvwh832ICntAPSn4oti6hX8ZLDnSH3w9PxT87I2Jv3IoJbJvAJM7P2askLZll6qGsIP56cWSmsffGWc2FupBq6jnfZ4gEouNsknjZzxvb7V1KBoTWLJvqb2Ef9moOhVnLB2yomW8l2jgSilVNtFJbhsFuHahHGIsX9QSwAHcXievVZzopRCupCbKojvnpFbi6TDeVBNu4nR1386AVo','peLzhP','CXi8yQAXYd7klUta8wKm9EW4PyZ4jtYscXJZCEkzJyG0sBf15b98H5015jcW84qAoU7wQtUU48q74ex15jJ4WLPcMDr1hD4kwblFfTCH1PZVFW5cv5HPot99UsQ16ReaeCouTxfUsSGepaRjEARYeuKFXCMjXPzEQqVV5TiyI95miIkpGYPXyAt22JpsHpksxIBqoGmcbCgWFe2YtC7qh2H0l32BXN6re58COcdHJikrv9HbJKJpwUv','6','6',6);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t1(a INT) engine=TokuDB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t1 (c1 INT NOT NULL, c2 INT UNIQUE) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
select concat('From JSON func ',c, ' as CHAR(35))'), cast(json_extract(j, '$') as CHAR(35)) from t where c='null';#ERROR: 1054 - Unknown column 'c' in 'field list'
SET @@global.innodb_adaptive_flushing_lwm = 60;#NOERROR
SELECT 16383 + 3;#NOERROR
CREATE TABLE t (a SMALLINT, b SMALLINT UNSIGNED, c BINARY(71), d VARBINARY(75) NOT NULL, e VARCHAR(56), f VARBINARY(22), g TINYBLOB NOT NULL, h LONGBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), CLUSTERING KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'e), PRIMARY KEY(id)) ENGINE=RocksDB' at line 1
SELECT * FROM t4;#ERROR: 1146 - Table 'test.t4' doesn't exist
CREATE TABLE t1 ( id INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY, a VARCHAR(200), b TEXT ) ENGINE = RocksDB STATS_PERSISTENT=0;#ERROR: 1050 - Table 't1' already exists
INSERT INTO mysqltest.transtable (id) VALUES (69);#ERROR: 1146 - Table 'mysqltest.transtable' doesn't exist
CREATE TABLE ti (a TINYINT UNSIGNED, b TINYINT UNSIGNED NOT NULL, c BINARY(58) NOT NULL, d VARBINARY(49), e VARBINARY(27) NOT NULL, f VARBINARY(34), g TINYBLOB NOT NULL, h BLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
drop TABLE t1;#NOERROR
INSERT INTO t779 VALUES(1);#ERROR: 1146 - Table 'test.t779' doesn't exist
SET @@GLOBAL.slow_launch_time= 10000;#NOERROR
INSERT INTO t1 VALUES('');#ERROR: 1146 - Table 'test.t1' doesn't exist
INSERT INTO t1 VALUES(21999);#ERROR: 1146 - Table 'test.t1' doesn't exist
CREATE FUNCTION f1() RETURNS INT BEGIN DECLARE v INT;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
CREATE TABLE t1 (c1 VARCHAR(10));#NOERROR
call mtr.add_suppression("Error while storing key: key_id cannot be empty");#ERROR: 1305 - PROCEDURE mtr.add_suppression does not exist
insert into t2 values (64742);#NOERROR
INSERT INTO t3 VALUES (123456, 40), (123456, 40);#ERROR: 1136 - Column count doesn't match value count at row 1
insert into s values (298,repeat('a', 2000)),(298,repeat('b', 2000)),(298,repeat('c', 2000)),(298,repeat('d', 2000)),(298,repeat('e', 2000)),(298,repeat('f', 2000)),(298,repeat('g', 2000)),(298,repeat('h', 2000)),(298,repeat('i', 2000)),(298,repeat('j', 2000));#ERROR: 1146 - Table 'test.s' doesn't exist
SELECT COUNT(@@SESSION.RocksDB_log_file_size);#ERROR: 1193 - Unknown system variable 'RocksDB_log_file_size'
SELECT COUNT(@@local.RocksDB_log_file_size);#ERROR: 1193 - Unknown system variable 'RocksDB_log_file_size'
INSERT INTO ti VALUES (2599817910,-5527,'TQE','Nf0b0qkeHSHzvtKKy0c6CBqkeTihsQtwHiGzjtFUKVSesNvZFhkljZ6Vvl','M88','jE3E77PpbxyXQKn','hv','IH',15);#ERROR: 1062 - Duplicate entry '15' for key 'PRIMARY'
INSERT INTO ti VALUES (784645391,65,'N','JI','BB9ELGnNS93WVQ5EkWtZxeEUJS0GGq5v8kUVeqg7C6iCYmUKmx','8MfdcNtOHNOMO8O','Bg','j',10);#ERROR: 1062 - Duplicate entry '10' for key 'PRIMARY'
SELECT * FROM t3 WHERE c2 <=> -8388608 ORDER BY c2,c7 DESC LIMIT 2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
call mtr.add_suppression("Error while fetching key: key_id cannot be empty");#ERROR: 1305 - PROCEDURE mtr.add_suppression does not exist
select host,user from RocksDB.user where (host,user) = ('localhost','test');#ERROR: 1146 - Table 'RocksDB.user' doesn't exist
SELECT SUBSTRING('11', 2);#NOERROR
CREATE TABLE ti (a MEDIUMINT UNSIGNED, b SMALLINT UNSIGNED NOT NULL, c BINARY(59), d VARCHAR(74) NOT NULL, e VARBINARY(51), f VARBINARY(71), g LONGBLOB NOT NULL, h BLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
DROP DATABASE IF EXISTS bug42217_db;#NOERROR
insert into at(c,_tbl) select concat('_tbl: ',c), json_extract(j, '$') from t where c='opaque_mysql_type_blob';#ERROR: 1146 - Table 'test.at' doesn't exist
SELECT QUOTE(REPLACE('[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 65535)] = 1', CONCAT('[', 'SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 65535)', ']'), '1'));#NOERROR
CREATE TABLE t1 (col1 date);#ERROR: 1050 - Table 't1' already exists
insert into t2 values (32514);#NOERROR
select "RocksDBd2:",txt from raw_binlog_rows where txt like "### % `test`.`t1`" or txt like "### Extra row data %";#ERROR: 1146 - Table 'test.raw_binlog_rows' doesn't exist
CREATE DATABASE RocksDB_db1;#NOERROR
SELECT SUBSTRING('11', 2);#NOERROR
SELECT extractValue(@xml,'/a/b');#NOERROR
set global innodb_random_read_ahead='AUTO';#ERROR: 1231 - Variable 'innodb_random_read_ahead' can't be set to the value of 'AUTO'
insert into t (id,a) values (303,45);#ERROR: 1054 - Unknown column 'id' in 'field list'
SELECT LOCATE(']', '[SELECT COUNT(*) FROM t1 WHERE a IS NULL] = 1');#NOERROR
SELECT a+SUM(a) FROM t1 GROUP BY a WITH ROLLUP;#ERROR: 1054 - Unknown column 'a' in 'field list'
CREATE TABLE t1 (id INT) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE ti (a TINYINT UNSIGNED NOT NULL, b TINYINT UNSIGNED NOT NULL, c CHAR(23) NOT NULL, d VARCHAR(66) NOT NULL, e VARCHAR(11), f VARBINARY(12), g MEDIUMBLOB NOT NULL, h BLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=myisam;#ERROR: 1050 - Table 'ti' already exists
CREATE TABLE t1(i INTEGER);#ERROR: 1050 - Table 't1' already exists
SELECT * FROM t1, t2 WHERE a = b + (1 + 1);#ERROR: 1054 - Unknown column 'b' in 'where clause'
CREATE TABLE t1(c1 INT PRIMARY KEY, c2 char(20)) ENCRYPTION="Y" ENGINE = MEMORY;#ERROR: 1050 - Table 't1' already exists
select @@session.master_verify_checksum  as 'no session var';#ERROR: 1238 - Variable 'master_verify_checksum' is a GLOBAL variable
INSERT INTO t VALUES (3845235596,1013794983,'oS5T2yEnRK9','xtew291fofrpMSvcvDVwwv2XeiJYnYZqFRFBxnaMU0AYZUciMfs7eszKY2X3DAM88Klweff9pa','fT1btc','kF7NeWFfswE5z8vpd0xAi5sTTolhhL1kAfmxDCcRQIjNX','7','g',12);#ERROR: 1136 - Column count doesn't match value count at row 1
SET @commands= 'B T Drop-Temp-Xe-Temp N Drop-Temp-Xe-Temp C';#NOERROR
SHOW COLUMNS FROM RocksDBtest2.t2;#ERROR: 1146 - Table 'RocksDBtest2.t2' doesn't exist
INSERT INTO t1  VALUES(1, 2), (11, 12);#ERROR: 1136 - Column count doesn't match value count at row 1
set global large_page_size=1;#ERROR: 1238 - Variable 'large_page_size' is a read only variable
INSERT INTO t307 VALUES(1);#ERROR: 1146 - Table 'test.t307' doesn't exist
SET DEBUG_SYNC='before_row_ins_extern_latch SIGNAL rec_not_blob WAIT_FOR crash';#ERROR: 1193 - Unknown system variable 'DEBUG_SYNC'
SELECT ST_LENGTH(ST_MLINEFROMWKB(MULTILINESTRING(LINESTRING(POINT(0,0), POINT(1e308,1e308)))));#NOERROR
CREATE TABLE t1( id INT, dummy INT, a BLOB, last INT ) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
select * from t1 where a=b and b=0x01;#ERROR: 1054 - Unknown column 'a' in 'where clause'
SET collation_connection='gbk_chinese_ci';#NOERROR
insert into at(c,_dat) select concat('_dat: ',c), (select j from t where c='stringdecimal') from t where c='stringdecimal';#ERROR: 1146 - Table 'test.at' doesn't exist
CREATE TABLE ti (a SMALLINT UNSIGNED, b TINYINT UNSIGNED, c CHAR(35), d VARCHAR(33), e VARCHAR(7) NOT NULL, f VARBINARY(67), g BLOB, h MEDIUMBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
SELECT SHA2( x'a34dbe4c6f53b1a60cba0260124ba5b3a72395bb4664bccdbf2a130a7fc10a3412152ac1e669f92e524c1e96d6c9c583a5df45046031000025fd8bc9c85210f4607ef06906c6acb6d95b05a94689621d863073146778140650c174797fd976d29672576b56d392e5aacd00c0e7f1442852006612e3a3be88485c14', 384 ) = '723f8ef0f28a234f8dda9f687ab51b2874b91a69ac7a20b107064e7b7c87c849f3ea39471e11ba43499d458e9044d4c4'  as NIST_SHA384_test_vector;#NOERROR
insert INTO t1  values (0xF9,'LATIN SMALL LETTER U WITH RING ABOVE');#ERROR: 1136 - Column count doesn't match value count at row 1
set global slow_launch_time =@my_slow_launch_time;#ERROR: 1232 - Incorrect argument type to variable 'slow_launch_time'
select * from t2,t1 where t1.a<=>t2.a or (t1.a is null and t1.b <> 9);#ERROR: 1054 - Unknown column 't1.a' in 'where clause'
CREATE TABLE t1 (a int NOT NULL) ENGINE = CSV;#ERROR: 1050 - Table 't1' already exists
SELECT LOCATE(']', '1 = 1');#NOERROR
INSERT INTO t1 (col1) VALUES(128);#ERROR: 1054 - Unknown column 'col1' in 'field list'
DROP TABLE t1;#NOERROR
CREATE TABLE ti (a TINYINT NOT NULL, b INT, c CHAR(89) NOT NULL, d VARBINARY(35), e VARBINARY(54), f VARBINARY(16), g MEDIUMBLOB, h TINYBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=MEMORY;#ERROR: 1050 - Table 'ti' already exists
CREATE TABLE t1 (c1 DOUBLE PRECISION NOT NULL PRIMARY KEY, c2 BINARY(10), c3 DATE);#NOERROR
SELECT SUBSTRING('11', 2);#NOERROR
SELECT ST_INTERSECTS(ST_GEOMFROMTEXT(@star_top,123456),ST_GEOMFROMTEXT(@star_center,123456));#NOERROR
SET @@session.sql_log_off = ON;#NOERROR
CREATE TABLE ti (a BIGINT, b INT, c BINARY(32), d VARCHAR(24), e VARCHAR(60), f VARCHAR(26) NOT NULL, g TINYBLOB NOT NULL, h LONGBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
CREATE TABLE t8(c1 TINYINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, c2 TINYINT NULL, c3 SMALLINT, c4 MEDIUMINT , c5 INT, c6 INTEGER, c7 BIGINT);#NOERROR
create procedure bug6857() begin declare t0, t1 int;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
drop function keyring_key_fetch;#ERROR: 1305 - FUNCTION test.keyring_key_fetch does not exist
call mtr.add_suppression("Could not delete from Slave Workers info repository.");#ERROR: 1305 - PROCEDURE mtr.add_suppression does not exist
call mtr.add_suppression("Can't generate a unique log-filename master-bin");#ERROR: 1305 - PROCEDURE mtr.add_suppression does not exist
CREATE TABLE t1 (c1 SMALLINT NOT NULL);#ERROR: 1050 - Table 't1' already exists
INSERT INTO ti VALUES (-26124,-5114549400465575024,'WqOVrUoFGKdSfyDeAnRYwv19uETmStcUe','nZUfQyc94eZJ4qzdbrItD9G73d5TpVElAPLWWYcHjoZ','9cZk0QI','XEBGAbIHrQM0D70LtuU46kIXRpwlfU22w6hUNRE7rWbo8yvB5U3qHkSyrCKCbUp3mMrS6kxsA0RpvMVjSKUco2zejwZsDIbXqAHtii95gniHNEU6taYlg6AqI8YSk5RMH1uEy3uqqPhAvq2wq5pqOuAxkd6AyVF0BGJSGG3Vllh1R1xz','x','o',13);#ERROR: 1062 - Duplicate entry '13' for key 'PRIMARY'
INSERT INTO ti VALUES (3134863602,3804620856474876916,'0A','yRrjF','Yv2UJoLCeaoxGUJ5H3axUOWoewP8kD98biV6MK70NwWlrCoh3cCaSaDDBXB8WucCQC','cHjGY0W18wg5ibypagt0bkaJ8R1YXqKwqLJL60YmsTIZ2yNwtrPBApB3M86YNP89judx4VGAURocksDBvZo4wZw2po9','Fu','f',2);#NOERROR
INSERT INTO t1  VALUES ('2003-11-24 06:30:37.06','18:49:53');#ERROR: 1136 - Column count doesn't match value count at row 1
ALTER TABLE t CHANGE COLUMN a a CHAR(99) BINARY;#ERROR: 1054 - Unknown column 'a' in 't'
SELECT DISTINCT TABLESPACE_NAME, FILE_NAME, LOGFILE_GROUP_NAME, EXTENT_SIZE, INITIAL_SIZE, ENGINE FROM INFORMATION_SCHEMA.FILES WHERE FILE_TYPE = 'DATAFILE' AND TABLESPACE_NAME IN (SELECT DISTINCT TABLESPACE_NAME FROM INFORMATION_SCHEMA.PARTITIONS WHERE TABLE_SCHEMA='mysqldump_test_db' AND TABLE_NAME IN ('\\d-2-1.sql')) ORDER BY TABLESPACE_NAME, LOGFILE_GROUP_NAME;#NOERROR
select str_to_date('04 /30/2004', '%m /%d/%Y');#NOERROR
call mtr.add_suppression("\\[Error\\] Couldn't load plugin named 'keyring_vault' with soname 'keyring_vault.dll'.");#ERROR: 1305 - PROCEDURE mtr.add_suppression does not exist
INSERT INTO ti VALUES (7718394658895087058,-3656019474774807457,'jZjR3WfLO5HkbFZF0f6o3OcZSg5mJfw3px','dUcMoPZLJsJF4pH3yEKOQd92Nbt5bOyrCXBQbIViCpd5HGvuw0VrZS6ETnh697zHI0GEoxYB7F0MEPwZIyGJltQbWO0ECk70WjtIWQ9NCr6yMffueBDfw5aPkWkHbVko1aibbI8LYNJWrBezhMk6oK84TR5guLxZQuLWkDRneQU19T18JRiLvu2dNP06fHVomaGA4z7TanTcMORnZ1jD7eGL57wSOmYuTqkrrXoTlDjjqNpEH6','iOPsniZLHlZY1KY5r','jDI30otLyRxXnmj7xpifFPSnkN6p4MzMmP0X2YhTzaHsboo98pv6F8w1Hw07f3LZsHkmpamvG9Qgp9g0Dbs2hgzO9RD2GNrPMjkrD9vWPtSCU5ryxW8jD3hndlAhAUX0L10fQqbn1CDHL8egrrucFnk02MHzQgZgGW2f17cKIT3cODfTXmxAnnr5h27uouiiWH7hd2k6PLiMSTJ4z','SL','z',5);#ERROR: 1062 - Duplicate entry '5' for key 'PRIMARY'
CREATE TEMPORARY TABLE t14169459_1 (a INT, b TEXT) engine=RocksDB;#NOERROR
CREATE TABLE t1 ( word VARCHAR(64) , PRIMARY KEY (word)) ENGINE=RocksDB CHARSET utf32 COLLATE utf32_general_ci;#ERROR: 1050 - Table 't1' already exists
create temporary table parent ( i int primary key ) engine = MEMORY;#NOERROR
SET @old_autocommit=@@AUTOCOMMIT;#NOERROR
INSERT INTO t1  VALUES(1);#ERROR: 1136 - Column count doesn't match value count at row 1
select * from performance_schema.memory_summary_by_account_by_event_name where event_name like 'memory/%' limit 1;#NOERROR
insert into at(c,_ttx) select concat('_ttx: ',c), (select j from t where c='opaque_mysql_type_date') from t where c='opaque_mysql_type_date';#ERROR: 1146 - Table 'test.at' doesn't exist
set global RocksDB_file_format_max = Bear;#ERROR: 1193 - Unknown system variable 'RocksDB_file_format_max'
EXPLAIN SELECT * FROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA='test';#NOERROR
CREATE TABLE t1(c1 INT, c2 char(20)) ENCRYPTION="Y" ENGINE=InnoDB;#ERROR: 1050 - Table 't1' already exists
INSERT INTO t970 VALUES(1);#ERROR: 1146 - Table 'test.t970' doesn't exist
CREATE TABLE t (a CHAR(24));#ERROR: 1050 - Table 't' already exists
SELECT SUM( DISTINCT e ) FROM t1  GROUP BY b,c,d HAVING (b,c,d) IN ((AVG( 1 ), 1 + c, 1 + d), (AVG( 1 ), 2 + c, 2 + d));#ERROR: 1054 - Unknown column 'e' in 'field list'
CREATE TABLE t1 (a int) ENGINE = RocksDB;#ERROR: 1050 - Table 't1' already exists
create table t5 (a int , b int);#NOERROR
set @@sql_big_selects = @old_sql_big_selects;#ERROR: 1231 - Variable 'sql_big_selects' can't be set to the value of 'NULL'
alter table t1 add column (c int);#NOERROR
select count(length(a) + length(filler)) from t2 where a>='a-1000-a' and a <'a-1001-a';#ERROR: 1054 - Unknown column 'filler' in 'field list'
CREATE TABLE t897 (c1 INTEGER);#NOERROR
INSERT INTO t1  VALUES (590,166102,50,'hamming','simultaneous','endpoint','');#ERROR: 1136 - Column count doesn't match value count at row 1
select * from t1 where user_id>=10292;#ERROR: 1054 - Unknown column 'user_id' in 'where clause'
SELECT HEX(c1),HEX(c2) FROM t5;#ERROR: 1054 - Unknown column 'c1' in 'field list'
declare cmd_2 varchar(512);#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'declare cmd_2 varchar(512)' at line 1
select * FROM t1  where b=1 and c=1;#ERROR: 1054 - Unknown column 'b' in 'where clause'
show session variables like 'RocksDB_ft_num_word_optimize';#NOERROR
INSERT INTO t VALUES (11520575787038079422,2862268,'tyMKL8g1R','ttaGt8WFuX7IO6U73Z8Rn5Qo6iR8z4ghfUPxIET0Zsk41CEARjyaKAm5yxCDEDHsYCuItfO','H3Gcqq','HgcwsvxfhgQHJr8','y','7',12);#ERROR: 1136 - Column count doesn't match value count at row 1
SET @@global.RocksDB_autoextend_increment = "Y";#ERROR: 1193 - Unknown system variable 'RocksDB_autoextend_increment'
CREATE TABLE t1 ( a VARCHAR(10) CHARACTER SET utf16le, b VARCHAR(10) CHARACTER SET utf16le);#ERROR: 1050 - Table 't1' already exists
INSERT INTO t1  VALUES(3,'abc','1996-01-01');#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO t VALUES (-6985228304427136974,3035070911310391493,'E1LQfpubI2omKRDpcn2B2wXNvT8laO5ij642IChtAeHeEYiQaAr','9yC6wQdaaZljcxP','f0dx6zUZHSc89Gtq6DidH','ZAq7QfbL','K','cI',5);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT col_1_blob = REPEAT("c", 4000) FROM t1 _key2;#ERROR: 1054 - Unknown column 'col_1_blob' in 'field list'
insert into t2 values (782+0.75);#NOERROR
INSERT INTO tp VALUES (162, "Hundred sixty-two"), (164, "Hundred sixty-four"), (166, "Hundred sixty-six"), (168, "Hundred sixty-eight");#ERROR: 1146 - Table 'test.tp' doesn't exist
EXECUTE my_stmt;#ERROR: 1243 - Unknown prepared statement handler (my_stmt) given to EXECUTE
truncate table RocksDB.file_summary_by_instance;#ERROR: 1146 - Table 'RocksDB.file_summary_by_instance' doesn't exist
SELECT * FROM t2 WHERE c2 <=> '9999-12-31 23:59:59' ORDER BY c1,c2 DESC LIMIT 2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
SET SESSION query_cache_type = 1;#NOERROR
SELECT @@sync_binlog;#NOERROR
SELECT @@global.time_zone AS res_is_05_00;#NOERROR
SELECT QUOTE(REPLACE('[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 16386)] = 1', CONCAT('[', 'SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 16386)', ']'), '1'));#NOERROR
CREATE TABLE t1 (a varchar(1)) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t5(c1 INTEGER UNSIGNED NOT NULL AUTO_INCREMENT, c2 INTEGER SIGNED NULL, c3 INTEGER SIGNED NOT NULL, c4 TINYINT, c5 SMALLINT, c6 MEDIUMINT, c7 INT, c8 BIGINT, PRIMARY KEY(c1,c2), UNIQUE INDEX(c3));#ERROR: 1050 - Table 't5' already exists
SET @@session.innodb_lock_wait_timeout=" ";#ERROR: 1232 - Incorrect argument type to variable 'innodb_lock_wait_timeout'
select log(-2,1);#NOERROR
select * from RocksDBdump_myDB.u1;#ERROR: 1146 - Table 'RocksDBdump_myDB.u1' doesn't exist
create table t1 (a char(36) not null)engine=RocksDB;#ERROR: 1050 - Table 't1' already exists
create table t2(b text)engine=MEMORY;#ERROR: 1050 - Table 't2' already exists
insert into t2 values (58041+0.755555555);#NOERROR
insert into s values (5,9,6);#ERROR: 1146 - Table 'test.s' doesn't exist
EXPLAIN PARTITIONS SELECT * FROM t1  WHERE b > CAST('2009-04-02 23:59:59' AS DATETIME);#NOERROR
SELECT var1,var2;#ERROR: 1054 - Unknown column 'var1' in 'field list'
CREATE TABLE `Ôº¥Ôºîa` (`Ôº£Ôºë` char(1) PRIMARY KEY) DEFAULT CHARSET = utf8 engine = MEMORY;#NOERROR
select right('hello', -18446744073709551616);#NOERROR
SELECT SUBSTRING('1', 2);#NOERROR
SELECT SUBSTRING('00', 1, 1);#NOERROR
insert into s values (1000000000,200);#ERROR: 1146 - Table 'test.s' doesn't exist
SELECT    alias1.col_date_key AS field1 FROM ( ( SELECT   sq1_alias1.* FROM b AS sq1_alias1  ) AS alias1 LEFT OUTER JOIN d AS alias2 ON (alias2.col_varchar_key = alias1.col_varchar_key  ) ) WHERE (  alias1.col_varchar_nokey >= SOME (SELECT   sq2_alias1.col_varchar_key AS sq2_field1 FROM cc AS sq2_alias1 WHERE sq2_alias1.col_varchar_nokey <> alias2.col_varchar_key AND sq2_alias1.col_varchar_nokey != alias2.col_varchar_nokey ) ) AND  alias1.col_int_nokey < ANY (SELECT 7 UNION SELECT 3 )  HAVING field1 >= 1;#ERROR: 1146 - Table 'test.b' doesn't exist
INSERT INTO t1 (bar) VALUES (1612);#ERROR: 1054 - Unknown column 'bar' in 'field list'
drop table first_db.t1;#ERROR: 1051 - Unknown table 'first_db.t1'
insert into t1 values (2, @x1, 1, @x2, 2);#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO t2 VALUES (1084,258104,68,'shuttered','botany','Willy','');#ERROR: 1136 - Column count doesn't match value count at row 1
SET GLOBAL RocksDB_compressed_columns_zip_level = @old_RocksDB_compressed_columns_zip_level;#ERROR: 1193 - Unknown system variable 'RocksDB_compressed_columns_zip_level'
SELECT 'SELECT COUNT(*) FROM t1 WHERE a = CAST(@inserted_value AS JSON)';#NOERROR
DROP PROCEDURE IF EXISTS p1;#NOERROR
SELECT SUBSTRING('11', 2);#NOERROR
SELECT SUBSTRING('11', 2);#NOERROR
SELECT * FROM t2 WHERE a = '1000-00-00';#NOERROR
SELECT MAX(c1) AS value FROM t1 WHERE c1 >= 0;#NOERROR
update v1 set a=2 where a=1;#NOERROR
ALTER TABLE `Ôº¥Ôºë` ADD `Ôº£Ôºí` CHAR(1) NOT NULL FIRST;#NOERROR
CREATE TABLE t2 ( broj int(4) unsigned NOT NULL default '0',  naziv char(25) NOT NULL default 'NEPOZNAT',  PRIMARY KEY  (broj)) ENGINE=RocksDB;#ERROR: 1050 - Table 't2' already exists
SELECT COUNT(@@have_rtree_keys);#NOERROR
SELECT '1 = 1';#NOERROR
SELECT * FROM t2 WHERE c1 BETWEEN '1901' AND '2020' ORDER BY c1,c2 LIMIT 2;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
SELECT COUNT(@@local.version_comment);#ERROR: 1238 - Variable 'version_comment' is a GLOBAL variable
create table t1 (a int, b int, primary key(b));#ERROR: 1050 - Table 't1' already exists
INSERT INTO t VALUES (2696785444531068534,3732738,'SSw2OLXTKQqRT','Piv9t4XI6TZVRGhFtfxzR7i86UUevDCzMhCaWraLx4VU4AvtZAc0kR6PyAUMmKuuucrzXe3','ukgAwkCxskMa8x0B0NaOKHB','r2SYrZQi6wFPkCEQuDz9dG4LC7Rx2xqm6f6ZFo4pOebKSJ6OzDAw3aL03DhHoe0PmJukly6HU','gp','e',14);#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO t1 (c1,c2,c3) VALUES(11,10,10);#NOERROR
INSERT INTO t VALUES (346163522201016963,-1816747,'IAf8','wz','CqDB1b4EM8I5Kvb','ea5S','C','f',0);#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO t1  VALUES (107,018061,37,'trimmings','sorters','reporters','');#ERROR: 1136 - Column count doesn't match value count at row 1
SET @@local.rpl_recovery_rank = 4;#ERROR: 1193 - Unknown system variable 'rpl_recovery_rank'
DROP TABLE `sql_1`;#ERROR: 1051 - Unknown table 'test.sql_1'
SELECT REPEAT('.', 1 - 1);#NOERROR
list_files_write_file $_VARDIR/tmp/testdir/file2.txt $_VARDIR/tmp/testdir *;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'list_files_write_file $_VARDIR/tmp/testdir/file2.txt $_VARDIR/tmp/testdir *' at line 1
CREATE TABLE ti (a TINYINT UNSIGNED NOT NULL, b INT, c CHAR(71), d VARBINARY(45), e VARBINARY(20) NOT NULL, f VARCHAR(49) NOT NULL, g LONGBLOB, h BLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=myisam;#ERROR: 1050 - Table 'ti' already exists
SELECT MAKETIME(1, 1, 1.00000);#NOERROR
SELECT 22312 MOD 5000;#NOERROR
DELETE FROM t1;#NOERROR
CREATE TABLE t1 (col1 BIGINT, col2 BIGINT UNSIGNED);#ERROR: 1050 - Table 't1' already exists
CREATE TABLE ADDRESS ( PERSON_ID VARCHAR(50) NOT NULL, DOB VARCHAR(50) NOT NULL, ADDRESS_ID VARCHAR(50) NOT NULL, ADDRESS_DETAILS NVARCHAR(250) NULL, CONSTRAINT PK_ADDRESS PRIMARY KEY (PERSON_ID, DOB, ADDRESS_ID), CONSTRAINT FK_ADDRESS_2_PERSON FOREIGN KEY (PERSON_ID, DOB) REFERENCES PERSON (PERSON_ID, DOB) ON DELETE CASCADE )Engine=RocksDB;#ERROR: 1005 - Can't create table `test`.`ADDRESS` (errno: 150 "Foreign key constraint is incorrectly formed")
SET @create_table_referencing_zip_dict_sql = 'CREATE TABLE t1('   '  id INT,'   '  a BLOB COLUMN_FORMAT COMPRESSED WITH COMPRESSION_DICTIONARY dict'   ') ENGINE=InnoDB;';#NOERROR
set timestamp=100000000;#NOERROR
INSERT INTO t4 VALUES("c373e9f59cf15a59b08a444553544200", "NoFieldDocType", "plain doc type", NULL, "2003-06-06 07:48:40", "admin", NULL);#ERROR: 1146 - Table 'test.t4' doesn't exist
INSERT INTO t1  VALUES(0);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT @@session.character_set_client = (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.SESSION_VARIABLES WHERE VARIABLE_NAME='character_set_client') AS res;#NOERROR
USE test;#NOERROR
insert into t1 values (5604,5604,5604,5604);#NOERROR
SELECT REPEAT('.', 2 - 1);#NOERROR
SELECT QUOTE(REPLACE('[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 2)] = 1', CONCAT('[', 'SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 2)', ']'), '1'));#NOERROR
INSERT INTO t1 VALUES ('2004-01-13'),('2004-01-20'),('2004-01-30');#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT SUBSTRING_INDEX('default,', ',', 1);#NOERROR
SELECT SUBSTRING('00', 2);#NOERROR
SELECT t1.c1,t5.c1 FROM t1  INNER JOIN t1 ON t1.c1 = t5.c1;#ERROR: 1066 - Not unique table/alias: 't1'
INSERT INTO t1 VALUES(2, "ccccc");#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO worklog5743_key2 VALUES(REPEAT("b", 4000) , REPEAT("p", 4000));#ERROR: 1146 - Table 'test.worklog5743_key2' doesn't exist
INSERT INTO t1 VALUES(NULL);#ERROR: 1136 - Column count doesn't match value count at row 1
DROP TABLE t1;#NOERROR
CREATE TABLE ti (a INT UNSIGNED NOT NULL, b INT UNSIGNED NOT NULL, c CHAR(32) NOT NULL, d VARBINARY(82), e VARBINARY(7) NOT NULL, f VARCHAR(13), g BLOB NOT NULL, h MEDIUMBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
SELECT COUNT(@@SESSION.innodb_max_purge_lag_delay);#ERROR: 1238 - Variable 'innodb_max_purge_lag_delay' is a GLOBAL variable
query_vertical SELECT user,ssl_type,ssl_cipher,x509_issuer,x509_subject, plugin,authentication_string,password_expired, password_last_changed,password_lifetime FROM mysql.user WHERE USER='u1';#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'query_vertical SELECT user,ssl_type,ssl_cipher,x509_issuer,x509_subject, plug...' at line 1
SELECT * FROM t1 WHERE c1 < '0000-00-00 00:00:00' ORDER BY c1 DESC;#ERROR: 1146 - Table 'test.t1' doesn't exist
CREATE TABLE t1(c1 MEDIUMINT NULL, c2 BINARY(25) NOT NULL, c3 INT(4) NULL, c4 BINARY(15) NOT NULL PRIMARY KEY, c5 MEDIUMINT NOT NULL UNIQUE KEY,c6 DECIMAL(10,8) NOT NULL DEFAULT 3.141592);#NOERROR
insert into t (id,a) values (193,37);#ERROR: 1054 - Unknown column 'id' in 'field list'
update _1.t2, _2.t2 set d=20 where d=1;#ERROR: 1146 - Table '_1.t2' doesn't exist
INSERT INTO t VALUES (2685773002587256051,-13547,'PswRwFoMBJQmwkwsyVajfBzCRukgH4BscpvRL','OqKYoac8bLRRBRKcSJiAxk3nvUH0D4ZnmNZWRZDOrHTJha5Cg6dsdeL2KVTfdrynRHgGa64qBKAJDLwqFXNVUwlTjZYOtkSwla5DVExXKdqnhC0YfYw','hysUI9nqX1pWMhPR83L','Zve8vU6OBM3pBGVUljyUCDxw9eyRiDtOM5BsjbH3luRsU7awnKiNy6FdkzoMqFgL4CDCJzwgCWldnGizNuNLY5Kw2EUBEIDeyJTJ2yMQ5Xh3ODQRrQsGRYLyQlFscXNoaWFSs3RS6vLT438Hr7OKKY6OwINh5d6ZT0GuHPa2lBYSoXMgkY56','z','Fg',13);#ERROR: 1136 - Column count doesn't match value count at row 1
DELETE QUICK IGNORE d1.t1, d2.t2 FROM d1.t1, d2.t2, d3.t3 WHERE d1.t1.c1=d2.t2.c2 AND d2.t2.c1=d3.t3.c2;#ERROR: 1146 - Table 'd1.t1' doesn't exist
SELECT SUBSTRING('1', 1, 1);#NOERROR
select count(*) from t5;#NOERROR
CREATE TABLE t1(c1 INT NOT NULL PRIMARY KEY, c2 REAL NULL, c3 REAL NULL);#ERROR: 1050 - Table 't1' already exists
set session RocksDB_large_prefix='OFF';#ERROR: 1193 - Unknown system variable 'RocksDB_large_prefix'
SELECT t1.c1,t5.c1 FROM t1  LEFT OUTER JOIN t1 ON t1.c1 = t5.c1 WHERE t1.c1 >= 5;#ERROR: 1066 - Not unique table/alias: 't1'
insert into t (id,a) values (175,52);#ERROR: 1054 - Unknown column 'id' in 'field list'
DO 1;#NOERROR
INSERT INTO t1  VALUES (NULL, NULL, 98);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t1(c1 LONGBLOB NULL) COMMENT = 'This table has a LONGBLOB column';#ERROR: 1050 - Table 't1' already exists
create temporary TABLE t1(a int);#NOERROR
update t1 set b="updated t1.b from master";#ERROR: 1054 - Unknown column 'b' in 'field list'
SELECT session character_set_connection;#ERROR: 1054 - Unknown column 'session' in 'field list'
CREATE TABLE ti (a TINYINT NOT NULL, b MEDIUMINT, c BINARY(54), d VARBINARY(77) NOT NULL, e VARCHAR(60) NOT NULL, f VARCHAR(16) NOT NULL, g LONGBLOB NOT NULL, h MEDIUMBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=TokuDB;#ERROR: 1050 - Table 'ti' already exists
SELECT SUBSTRING('11', 2);#NOERROR
SET @a= 800;#NOERROR
explain select * from t where x not in ("","aa","b");#NOERROR
call mtr.add_suppression("Error while generating key: invalid key_type");#ERROR: 1305 - PROCEDURE mtr.add_suppression does not exist
SELECT SUBSTRING('1', 2);#NOERROR
CREATE TABLE t1(c1 char(3)) DEFAULT CHARSET = ujis ENGINE = RocksDB;#ERROR: 1050 - Table 't1' already exists
DROP USER 'select_only_c1'@'localhost';#ERROR: 1396 - Operation DROP USER failed for 'select_only_c1'@'localhost'
INSERT INTO t1  VALUES (410, 'READ ONLY');#ERROR: 1136 - Column count doesn't match value count at row 1
select * FROM t1  where word like CAST(0xDF as CHAR);#ERROR: 1054 - Unknown column 'word' in 'where clause'
ALTER TABLE `ÈæñÈæñÈæñ` DROP `‰∏Ñ‰∏Ñ`;#ERROR: 1091 - Can't DROP COLUMN `‰∏Ñ‰∏Ñ`; check that it exists
SELECT SUM(c1) AS value FROM t1  WHERE c1 = 0;#ERROR: 1054 - Unknown column 'c1' in 'field list'
INSERT INTO ti VALUES (-9217115494122930111,3377031,'HWBsA25RAoSDQLuFEhy','neSFWlu8WScGI9kYpO7VobTJx0bnRtgzByDv8szgIKOhCmgrxaTIxNDCRS7DIiM7CxhqZrnkRFEoho01dYRDzZkfwKnOix62hA0KdjIvaHNCYVKEJwgiBO2aosOTIu45tFJc9KUGjfiyBOJfyVulVksxTp5eL7WR3AhqGrUdyisJ7U47Me84kYrDnvMyvYuIICqDpXoux6m60SdIZbil54Xu8Si48Wvbo','2mj','rNW3rkFMKg4Q6kJJ7CAyqqVgdlJNqdnk7Dd9cwxF','d','J',12);#ERROR: 1062 - Duplicate entry '12' for key 'PRIMARY'
update t1 set name='U+25BD WHITE DOWN-POINTING TRIANGLE' where ujis=0xA2A6;#ERROR: 1054 - Unknown column 'ujis' in 'where clause'
CREATE TABLE t1 ( i int not null, v int not null,index (i));#ERROR: 1050 - Table 't1' already exists
ALTER INSTANCE ROTATE INNODB MASTER KEY;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'INSTANCE ROTATE INNODB MASTER KEY' at line 1
INSERT INTO t VALUES (209735629,-81462,'QaavwfaGveEEHNcjB0tOYNvwBRBCblxs5aEq0','eoWEp1LywQ1zFs6HJ2H2Okw9lLdz','QAIIR','FBAycKRoWZmXbmVnb','L','I',0);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE ti (a TINYINT UNSIGNED NOT NULL, b SMALLINT UNSIGNED NOT NULL, c BINARY(38), d VARCHAR(27), e VARCHAR(46), f VARCHAR(90) NOT NULL, g TINYBLOB, h BLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
SELECT SUBSTRING_INDEX('default,', ',', 1);#NOERROR
CREATE TABLE `ÇsÇX` (`ÇbÇP` char(5)) DEFAULT CHARSET = sjis engine = RocksDB;#NOERROR
INSERT INTO t VALUES (9624792,-1758783034988367344,'Dia7MZaXwrgK8nH2','3awSt9JCx9IWjMjCuRKWbl0PD7zA5imhINffSM4WXL6lvsKyt','Tvb','yjekLo1Tv8ugGJPnCGzmRM2dH0wioXE3n4ha3Sw344J','N','E',5);#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO arddl VALUES (3, 10);#ERROR: 1146 - Table 'test.arddl' doesn't exist
SELECT UNIX_TIMESTAMP();#NOERROR
set global skip_networking=1;#ERROR: 1238 - Variable 'skip_networking' is a read only variable
SELECT QUOTE(SUBSTRING('[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 8192)] = 1', 1 + 1, 63 - 1 - 1));#NOERROR
select * from t5 /* must be 1 after reconnection */;#NOERROR
DROP DATABASE IF EXISTS RocksDBtest_db2;#NOERROR
SET @@global.innodb_flush_log_at_timeout = @global_start_value;#ERROR: 1232 - Incorrect argument type to variable 'innodb_flush_log_at_timeout'
DROP TABLE tm1, t1, t9;#ERROR: 1051 - Unknown table 'test.tm1,test.t9'
delete from performance_schema.performance_timers;#ERROR: 1142 - DELETE command denied to user 'root'@'localhost' for table 'performance_timers'
insert into jj select DISTINCT(CAST(_mtx as JSON)) from at where _mtx is not NULL and cast(_mtx as JSON) not in ( select col from jj);#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'JSON)) from at where _mtx is not NULL and cast(_mtx as JSON) not in ( select ...' at line 1
delete FROM t1  where a > 5;#ERROR: 1054 - Unknown column 'a' in 'where clause'
CREATE TABLE m3(c1 SMALLINT NULL, c2 BINARY(25) NOT NULL, c3 BIGINT(4) NULL, c4 BINARY(15) NOT NULL PRIMARY KEY, c5 SMALLINT NOT NULL UNIQUE KEY,c6 NUMERIC(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 'm3' already exists
insert into t1 values (9734,9734,9734,9734);#ERROR: 1136 - Column count doesn't match value count at row 1
declare var2 float(23) zerofill;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'declare var2 float(23) zerofill' at line 1
EXPLAIN SELECT * FROM t1 ORDER BY word;#NOERROR
SELECT SUBSTRING('11', 2);#NOERROR
SELECT LOCATE(']', '[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 16385)] = 1');#NOERROR
SELECT * FROM t1  WHERE c2 <=> -2147483649 ORDER BY c2,c7;#ERROR: 1054 - Unknown column 'c7' in 'order clause'
CREATE TABLE t1 (c1 VARCHAR(10));#ERROR: 1050 - Table 't1' already exists
insert into t values (837,0);#NOERROR
INSERT INTO t1  VALUES('a');#ERROR: 1136 - Column count doesn't match value count at row 1
select * FROM t1  where a=if(b<10,_ucs2 0x00C0,_ucs2 0x0062);#ERROR: 1054 - Unknown column 'a' in 'where clause'
CREATE FUNCTION f1() RETURNS CHAR(10) RETURN '‘≈”‘';#NOERROR
SELECT REPEAT('.', 1 - 1);#NOERROR
insert into t1 values (2851,2851,2851,2851);#ERROR: 1136 - Column count doesn't match value count at row 1
insert into t2 values (51186+0.755555555);#NOERROR
CREATE TABLE ti (a BIGINT, b INT NOT NULL, c CHAR(81), d VARBINARY(35) NOT NULL, e VARCHAR(36) NOT NULL, f VARBINARY(43), g LONGBLOB NOT NULL, h TINYBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
INSERT INTO t1  VALUES(0xAFFA);#ERROR: 1136 - Column count doesn't match value count at row 1
insert into epochs_in_binlog select substring_index(right(txt, length(txt) - instr(txt, '@2=') - 3),' ', 1) from binlog_stmts where txt like '%RocksDB_apply_status%' order by txt;#ERROR: 1146 - Table 'test.epochs_in_binlog' doesn't exist
INSERT INTO t VALUES (495679365,-1344361794,'T44BFumP2','kAoX8E8v2GuNPoCcFT','QcvdBZewKzTszw','CHNvQ1XJ9IAaWi2LbvPgC3PyeIcw1C1V','V','3',3);#ERROR: 1136 - Column count doesn't match value count at row 1
select json_array_insert( '{ "a": [1, 2, 3, 4] }', '$.a[1]', false );#NOERROR
SELECT a FROM t1  GROUP BY a HAVING IFNULL((SELECT b FROM t1  WHERE b > 4), (SELECT c FROM t1  WHERE c=a AND b > 1 ORDER BY b)) > 3;#ERROR: 1054 - Unknown column 'a' in 'field list'
INSERT INTO ti VALUES (-750537694,41,'nyiLJqVXQ','VOlvaicijBNCguxdMKnQKPfj7YgezltdG2UOg1hgHhEBY1oywH1skR7VMItYqxo8PNEmynLw1CbQ4uoPJD5G9OlO2hojM2dHnXAkZNTCQxDN21RuXMTVElmD4UgTjXTpW7kn2QrVuxPPW89ckGk6ObTJUAgIjwI5QwbPF54QPOsvZRmMZ','8CxOulmcHEreZPWINfFF4bDkE7UzG3RVc8','VpG9l2eplDbhQVRWXPkfFXQ1m3EvHfJLh03psHCxDFAQ8','h','Xc',4);#ERROR: 1062 - Duplicate entry '4' for key 'PRIMARY'
CREATE TABLE t1 ( id bigint(20) unsigned NOT NULL, id2 bigint(20) unsigned NOT NULL, dob date DEFAULT NULL, address char(100) DEFAULT NULL, city char(35) DEFAULT NULL, hours_worked_per_week smallint(5) unsigned DEFAULT NULL, weeks_worked_last_year tinyint(3) unsigned DEFAULT NULL, KEY dob (dob), KEY address (address), KEY city (city), KEY hours_worked_per_week (hours_worked_per_week), KEY weeks_worked_last_year (weeks_worked_last_year) ) ENGINE=MyISAM DEFAULT CHARSET=latin1 PARTITION BY KEY (id) PARTITIONS 5;#ERROR: 1050 - Table 't1' already exists
insert into s values (1000000000,6334);#ERROR: 1146 - Table 'test.s' doesn't exist
select oref, a FROM t1  where a not in (select min(ie) FROM t1  where oref=t2.oref group by grp having min(ie) > 1);#ERROR: 1054 - Unknown column 'oref' in 'field list'
INSERT INTO t1  VALUES (105959.1234567);#ERROR: 1136 - Column count doesn't match value count at row 1
GRANT CREATE ON *.* TO proxy_native@localhost;#NOERROR
INSERT INTO t1  VALUES ( UNHEX('0000000001D007000000000000000000000000000000000000'));#ERROR: 1136 - Column count doesn't match value count at row 1
create table bug19145c (e enum('a','b','c') not null default 'b' , s set('x', 'y', 'z') not null default 'y' ) engine=MEMORY;#NOERROR
SELECT * FROM t1  WHERE c1 BETWEEN '1970' AND '2020' ORDER BY c1,c2 DESC;#NOERROR
SELECT * FROM t1 WHERE c2 >= '-99999.99999' ORDER BY c1,c2;#NOERROR
select * FROM t1  order by f1;#ERROR: 1054 - Unknown column 'f1' in 'order clause'
create database RocksDBtest2 character set latin2;#NOERROR
CREATE TABLE t1(a INT) ENGINE=InnoDB;#ERROR: 1050 - Table 't1' already exists
SELECT REPEAT('.', 2 - 1);#NOERROR
CREATE TABLE t1 ( a int ) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
SELECT @@GLOBAL.proxy_user;#ERROR: 1238 - Variable 'proxy_user' is a SESSION variable
INSERT INTO t1 VALUES(6100);#ERROR: 1136 - Column count doesn't match value count at row 1
prepare stmt from "DROP VIEW v1;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '"DROP VIEW v1' at line 1
CREATE TABLE t1 (c1 INT) ENGINE=MRG_RocksDB UNION=(t1,t2) INSERT_METHOD=LAST;#ERROR: 1050 - Table 't1' already exists
SELECT QUOTE(REPLACE('[SELECT COUNT(*) FROM t1 WHERE a = ""] = 1', CONCAT('[', 'SELECT COUNT(*) FROM t1 WHERE a = ""', ']'), '1'));#NOERROR
INSERT INTO t1  VALUES(1);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT REPEAT('.', 2 - 1);#NOERROR
set global default_storage_engine=MEMORY;#NOERROR
CREATE TABLE m3(c1 MEDIUMINT NULL, c2 CHAR(25) NOT NULL, c3 TINYINT(4) NULL, c4 CHAR(15) NOT NULL PRIMARY KEY, c5 MEDIUMINT NOT NULL UNIQUE KEY,c6 NUMERIC(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 'm3' already exists
call test.sp_bug29050();#ERROR: 1305 - PROCEDURE test.sp_bug29050 does not exist
insert into t1 values ('sasha@mysql.com'),('monty@mysql.com'),('foo@hotmail.com'),('foo@aol.com'),('bar@aol.com');#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t1(c1 DOUBLE PRECISION NULL, c2 VARCHAR(25) NOT NULL, c3 INT(4) NULL, c4 VARCHAR(15) NOT NULL PRIMARY KEY, c5 DOUBLE PRECISION NOT NULL UNIQUE KEY,c6 NUMERIC(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 't1' already exists
insert into t2 values (46231);#NOERROR
INSERT INTO t VALUES (1180024,182781823,'C9I','OZK9SUvXdtwSSaHYbkwEUSQVU5BcW33KZesFZVb2342','are3jXKlvyAWS4RZNWPKVbUbT74xQpYef6aQkCR0J9PgRUnNOWRWvhI732ZnmvGOHf','9KW05gfGY8YfhmMe9','2','9',3);#ERROR: 1136 - Column count doesn't match value count at row 1
create procedure q () insert INTO t1  values (2);#NOERROR
select fld3 FROM t2 where fld3 like "%cultivation";#ERROR: 1054 - Unknown column 'fld3' in 'field list'
CREATE TABLE t1( a NATIONAL VARCHAR(65532) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=InnoDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=InnoDB' at line 1
INSERT INTO t119 VALUES('a');#ERROR: 1146 - Table 'test.t119' doesn't exist
INSERT INTO t811 VALUES(1);#ERROR: 1146 - Table 'test.t811' doesn't exist
CREATE TEMPORARY TABLE t1(c1 LONGTEXT NOT NULL);#NOERROR
create TABLE t1 (a int, b varchar(2), c int) partition by range columns (a, b, c) (partition p0 values less than (1, 'A', 1), partition p1 values less than (1, 'B', 1));#ERROR: 1050 - Table 't1' already exists
SELECT table_id INTO @table_id FROM information_schema.RocksDB_sys_tables WHERE name = CONCAT(DATABASE(), '/', 't1');#ERROR: 1109 - Unknown table 'RocksDB_sys_tables' in information_schema
CREATE TABLE t1 ENGINE=RocksDB SELECT a FROM (SELECT pt AS a FROM geometries UNION SELECT mls FROM geometries) t;#ERROR: 1050 - Table 't1' already exists
select @1, @2;#NOERROR
CREATE TABLE ti (a MEDIUMINT NOT NULL, b INT NOT NULL, c BINARY(56) NOT NULL, d VARCHAR(10), e VARBINARY(52) NOT NULL, f VARBINARY(33) NOT NULL, g TINYBLOB NOT NULL, h TINYBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
CREATE TABLE t1( a VARBINARY(129) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = DYNAMIC ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = DYNAMIC ENGINE=RocksDB' at line 1
INSERT INTO t VALUES (8317323972672332486,2,'n13yZwDWojN52SfYKoj0ZV36WCZ2OQjl8fTsJnwRJOJENWJhw1fJzEyE','u','0movtLWbRxs4LhgPwcSMN2obgCQfcE','lOjs3fN7K9wgR','S','W',4);#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO t VALUES (7917,1046576138,'ukpbxY9sKpWrUJZBDH4z6QNY9N','xuDOgNvjNYWeFTh','hqen1Bni9Rlgkarsn9gjENK9en9s1M7PJnKoo8UB0rYbwbfKK4NuAHYWRHWyy6x7t','TRocksDBH24vqgtt8k9HE','OI','U',9);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t1(c1 MEDIUMINT UNSIGNED AUTO_INCREMENT NULL UNIQUE KEY ) AUTO_INCREMENT=10;#ERROR: 1050 - Table 't1' already exists
insert INTO t1  values("aaa ");#NOERROR
GRANT UPDATE (s2) ON t6 to RocksDBtest_u1@localhost;#ERROR: 1146 - Table 'test.t6' doesn't exist
DROP EVENT e3;#ERROR: 1539 - Unknown event 'e3'
INSERT INTO t2 VALUES (980,242102,41,'Britannic','bibliography','heaving','');#ERROR: 1136 - Column count doesn't match value count at row 1
insert into t2 values (50835+0.333333333);#NOERROR
update mt1,mt2 set mt1.b=mt1.b+10 where mt1.b=2;#ERROR: 1146 - Table 'test.mt1' doesn't exist
CREATE TABLE IF NOT EXISTS `èÌ›èÌ›èÌ›`(`è∞°è∞°è∞°` char(1)) DEFAULT CHARSET = ucs2 engine=RocksDB;#NOERROR
call mtr.add_suppression("\\[Error\\] InnoDB: Could not find a valid tablespace file for");#ERROR: 1305 - PROCEDURE mtr.add_suppression does not exist
SELECT * FROM t2 WHERE c2 >= '-838:59:59' AND c2 < '10:00:00' AND c1 = '00:11:12' ORDER BY c1,c2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
DROP DATABASE database_master_temp_01;#ERROR: 1008 - Can't drop database 'database_master_temp_01'; database doesn't exist
CREATE TABLE t1(a INT NOT NULL, b TINYBLOB, KEY(a)) PARTITION BY RANGE(a) ( PARTITION p0 VALUES LESS THAN (32));#ERROR: 1050 - Table 't1' already exists
SET @@global.lc_time_names=ca_ES;#NOERROR
select * from performance_schema.file_summary_by_instance where event_name='FOO';#NOERROR
SELECT IF('SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 127)' REGEXP '^[a-zA-Z_][a-zA-Z_0-9]*:', LOCATE(':', 'SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 127)'), 0);#NOERROR
CREATE TABLE db1.t1(c1 INT) ENGINE=InnoDB;#ERROR: 1049 - Unknown database 'db1'
insert into s values (1000000000,190);#ERROR: 1146 - Table 'test.s' doesn't exist
DECLARE CONTINUE HANDLER FOR SQLWARNING SELECT 'Wrong:H5:2' AS HandlerId;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'DECLARE CONTINUE HANDLER FOR SQLWARNING SELECT 'Wrong:H5:2' AS HandlerId' at line 1
SELECT JSON_CONTAINS('{"a":1}', '{"a":1,"b":2}');#NOERROR
INSERT INTO t1  VALUES('a');#NOERROR
insert into t2 values (57914);#NOERROR
SET DEBUG_SYNC = 'innodb_inplace_alter_table_enter SIGNAL start_create WAIT_FOR go_ahead';#ERROR: 1193 - Unknown system variable 'DEBUG_SYNC'
INSERT INTO t2 VALUES (3, 't2_Hamburg', 0, 0, 0);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT ST_ASTEXT(ST_BUFFER(ST_GEOMFROMTEXT('MULTIPOLYGON(((0 0,0 10,10 10,10 0,0 0)),((10 10,10 20,20 20,20 10,10 10)))'), -10));#NOERROR
select max(dardtestard) FROM t1 _c;#ERROR: 1054 - Unknown column 'dardtestard' in 'field list'
SET @commands= 'B T Drop-Temp-If-NXe-Temp N Drop-Temp-If-NXe-Temp C';#NOERROR
create TABLE t1 (a char(20), unique (a(5))) engine=innodb;#ERROR: 1050 - Table 't1' already exists
insert INTO t1  values(1)/ insert INTO t1  values(2);#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '/ insert INTO t1  values(2)' at line 1
INSERT INTO t1  VALUES (2,4,8);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE DATABASE bug19550875;#NOERROR
SELECT ST_GEOHASH(,10);#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '10)' at line 1
insert into t1 values (b'00'), (b'01'), (b'10'), (b'100');#NOERROR
SET @@global.tx_isolation = 'REPEATABLE-READ';#NOERROR
CREATE TABLE t3(c1 CHAR(50) NOT NULL);#ERROR: 1050 - Table 't3' already exists
DROP TABLE t1;#NOERROR
CREATE TABLE ti (a INT NOT NULL, b SMALLINT UNSIGNED, c CHAR(67) NOT NULL, d VARBINARY(13) NOT NULL, e VARBINARY(7), f VARBINARY(13) NOT NULL, g MEDIUMBLOB NOT NULL, h LONGBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=myisam;#ERROR: 1050 - Table 'ti' already exists
DROP TABLE t1;#NOERROR
SELECT REPEAT('.', 2 - 1);#NOERROR
INSERT INTO t VALUES (5088164147254559321,10618340961095214462,'W6OfzaFNSgAmVzNAgsdgQZEfOLelSAMJvQamMORjDcCBc1LpeZ83Bhczm3ECRC9','zAY2LgRBaA9OEbdrF7asJ7HaQlkb6HI7CnUiCTtkbH8ltKXI6St1n7mZA','HyTQEdZIO2IGvxNmwgF9ADRMJJHxryIs','KdHBwam7CaHxph','g','k',10);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT COUNT(*) FROM t1 WHERE a IS NULL;#ERROR: 1146 - Table 'test.t1' doesn't exist
select (@orig_max_data_length > @changed_max_data_length);#NOERROR
insert into t2 values (25740);#NOERROR
CREATE TABLE t1 (i INT NOT NULL PRIMARY KEY) ENGINE=InnoDB;#NOERROR
insert into showtemp.t3 values(999);#ERROR: 1146 - Table 'showtemp.t3' doesn't exist
ALTER TABLE t CHANGE COLUMN a a CHAR(31);#ERROR: 1054 - Unknown column 'a' in 't'
CREATE TABLE t1 ( a bigint unsigned NOT NULL, b bigint unsigned not null, c bigint unsigned NOT NULL, d int unsigned, PRIMARY KEY(a, b, c) ) ENGINE=RocksDBcluster;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t1 (c1 INT) PARTITION BY LINEAR HASH (c1) PARTITIONS 5;#ERROR: 1050 - Table 't1' already exists
insert into t2 values (60409+0.755555555);#NOERROR
select AUTO_INCREMENT from information_schema.tables where table_name = 't1';#NOERROR
INSERT INTO t1(a,c) VALUES (4, b'01');#ERROR: 1054 - Unknown column 'a' in 'field list'
select @category1_id:= 10001;#NOERROR
CREATE TABLE t1(c1 FLOAT NOT NULL);#ERROR: 1050 - Table 't1' already exists
INSERT INTO t VALUES (3680373026094320015,4063677,'RT1g4q0qyMDlF6kU','okdb9UNAJakCQ6PNXRrSd6wGCbxouwgkE5K15ojw2kOp8jU8jBy6nhFuZ52SOAiu9sCt836LoWZCqx2y03rwXVXiWfItw6aLHq4dwvwFkEvFkVfBzKyJYDZdcV2pQIS2cSAMkcF99KHbxbOdQ0WnPFjUAgZ9KvPIkW2NMoejQfznC4lH3lEBOKRqRhG3jt27imZYf3iNc','xdzbnS2dugk','63NITKPtpgeEE8t4iBVZjkHce04VLcNHffBBwGMcMLblS2A3GymdjcdhKauEwcYX9713urvjuC66XVMmFmGSqE5gv1rUbQcCgJFtz8sl3zc8OAnAqppHOvbPIfQD34B8P1yuQg7Kbh0FGGrMkgP594Kb4Rrh1','B','VNz',6);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE ti (a TINYINT, b INT NOT NULL, c BINARY(13), d VARCHAR(3) NOT NULL, e VARCHAR(4), f VARBINARY(39) NOT NULL, g LONGBLOB, h MEDIUMBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=InnoDB;#ERROR: 1050 - Table 'ti' already exists
insert into s values (7351,0),(7351,1),(7351,2),(7351,3),(7351,4),(7351,5),(7351,6),(7351,7),(7351,8),(7351,9);#ERROR: 1146 - Table 'test.s' doesn't exist
INSERT INTO ti VALUES (7161573,2591899714,'9Pi1kdb0apw','hw0fHzE8vQeofqjMT','6','mQs9jL939f5whmO8gyf1r4k94xS7vMdZOWZZUMNP0JVWCaif44FuX3CVkuyOe4Ik0FNkJiPnJkC0e8C6q6mowzqEmIyhbBH5SOcZfiVl26MFlvHObnNVYon5EU6UKJ8gGMIOkcNpHHJ7u0tyRaFDXbiu0wssYTSi73GjFH1vyPLy3Lf0fed1ncDsVNKcBgBbRilGEco2K0C','t','Ss7',15);#ERROR: 1062 - Duplicate entry '15' for key 'PRIMARY'
set global rocksdb_bulk_load=0;#ERROR: 1193 - Unknown system variable 'rocksdb_bulk_load'
CREATE TABLE ti (a SMALLINT NOT NULL, b INT UNSIGNED NOT NULL, c BINARY(87), d VARCHAR(56) NOT NULL, e VARCHAR(37) NOT NULL, f VARBINARY(20) NOT NULL, g TINYBLOB NOT NULL, h TINYBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=TokuDB;#ERROR: 1050 - Table 'ti' already exists
DROP TABLESPACE `RocksDB_temporary`;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
INSERT IGNORE INTO t1 VALUES(@inserted_value);#NOERROR
SELECT TIMESTAMP(f1,'1') FROM t1 ;#ERROR: 1054 - Unknown column 'f1' in 'field list'
SELECT '1 = 1';#NOERROR
CREATE TABLE t1( a TEXT COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = COMPRESSED ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = COMPRESSED ENGINE=RocksDB' at line 1
create TABLE t1 (id int not null, text varchar(20) not null default '', primary key (id));#ERROR: 1050 - Table 't1' already exists
DROP TABLE t1;#NOERROR
CREATE TABLE t1(c1 INT UNSIGNED AUTO_INCREMENT NOT NULL KEY ) AUTO_INCREMENT=10;#NOERROR
SELECT * FROM t1  WHERE c2 IN ('1000-00-01 00:00:00','2010-10-00 00:00:00') ORDER BY c2 DESC LIMIT 2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
CREATE TABLE t267 (c1 VARCHAR(10));#NOERROR
USE test;#NOERROR
insert into t2 values (63999);#NOERROR
CREATE TABLE ti (a MEDIUMINT NOT NULL, b SMALLINT UNSIGNED, c BINARY(27) NOT NULL, d VARBINARY(17) NOT NULL, e VARBINARY(41), f VARCHAR(42), g TINYBLOB, h TINYBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=MEMORY;#ERROR: 1050 - Table 'ti' already exists
set global RocksDB_ft_result_cache_limit=1000000;#ERROR: 1193 - Unknown system variable 'RocksDB_ft_result_cache_limit'
UPDATE performance_schema.setup_timers SET TIMER_NAME = 'NANOSECOND' WHERE NAME = 'wait';#NOERROR
DROP VIEW RocksDBtest1.v_ts;#ERROR: 4092 - Unknown VIEW: 'RocksDBtest1.v_ts'
select 7777777777777777777777777777777777777 * 10;#NOERROR
SELECT LOCATE(']', '1 = 1');#NOERROR
create table RocksDBtest.t3 (a int not null) engine= heap;#ERROR: 1049 - Unknown database 'RocksDBtest'
SELECT SUBSTRING('0', 2);#NOERROR
CREATE TABLE t1(c1 DATE NULL, c2 VARCHAR(25) NOT NULL, c3 SMALLINT(4) NULL, c4 VARCHAR(15) NOT NULL PRIMARY KEY, c5 DATE NOT NULL UNIQUE KEY,c6 NUMERIC(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 't1' already exists
INSERT INTO t VALUES (-4478793457302213040,-2845,'mwcqLtGPXACu8WUwOINwoa6gzpQX6ZNf6gq','Zex9XLNiSMwVuwEims','ZQpd0nMb','y2HbiRo5GEvfgo6ei2WkB1buAfvlLw13yhgpv2hBt70BDuEgJtgwii9FhyKnE5XxCwcmEmNXZVD6zOLv4zxY2Yjh','U','F',4);#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO t1 VALUES(REPEAT('A',512)),(REPEAT('B',512));#NOERROR
SELECT MBROVERLAPS(ST_GEOMFROMTEXT(@star_top),ST_GEOMFROMTEXT(@star_collection_elems));#NOERROR
create TABLE t1(a char(1)) default charset utf16;#ERROR: 1050 - Table 't1' already exists
select @@optimizer_prune_level;#NOERROR
CREATE TABLE t1(f1 INT NOT NULL AUTO_INCREMENT PRIMARY KEY, f2 INT NOT NULL, f3 INT NOT NULL, KEY(f2, f3))ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t1(c1 INT, c2 char(20)) ENCRYPTION="Y" ENGINE=TokuDB;#ERROR: 1050 - Table 't1' already exists
update t1 set ie=3 where oref='ff' and ie=1;#ERROR: 1054 - Unknown column 'oref' in 'where clause'
create table t1 (f1 int,f2 int);#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t_cmp_in_2k (a int, b text) ROW_FORMAT=Compact TABLESPACE s_2k;#NOERROR
INSERT INTO ti VALUES (14780240912118914505,3582528244,'v','hrpgcEce8EtZ59WJYLToBCRh1pK8E9dk9i5O2YxaX6XNZNVOhGF1zaBGPhwQpl5tsMAFXlyT35SXB4AeguISKgBPMEvD1TjniST','3GQttz4J','LHt7XUPx1JP3HPeOt4mlgOu851gUBeV8xlLacqnENpDbpdByE8TwCbr4LjEFYjaCYM529OiH2QSN73Xm1qAvsWrcxaMX2KCHfgbj4ZsIpaHwzy3x0BP9dWzhDB72X3tv2jty','O','X7',14);#ERROR: 1062 - Duplicate entry '14' for key 'PRIMARY'
SHOW INDEX FROM t1 ;#NOERROR
SELECT SUBSTRING('11', 1, 1);#NOERROR
CREATE TABLE t1 (a DATETIME) PARTITION BY HASH (EXTRACT(SECOND_MICROSECOND FROM a));#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t1(id INT PRIMARY KEY, fts_field VARCHAR(10), FULLTEXT INDEX f(fts_field)) ENGINE=TokuDB;#ERROR: 1050 - Table 't1' already exists
CREATE FUNCTION fn1(f1 char ascii ) returns char ascii return f1;#ERROR: 1304 - FUNCTION fn1 already exists
create table t1 (id int, dt datetime);#ERROR: 1050 - Table 't1' already exists
declare var2 year;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'declare var2 year' at line 1
select concat('From JSON subselect ',c, ' as DATE'), cast(j as DATE) from t where c='opaque_RocksDB_type_datetime';#ERROR: 1054 - Unknown column 'c' in 'field list'
SELECT ST_ASGEOJSON(ST_GEOMFROMTEXT("MULTIPOINT(10 40, 40 30, 20 20, 30 10)"));#NOERROR
SELECT * FROM t4;#ERROR: 1146 - Table 'test.t4' doesn't exist
SELECT SUBSTRING('11', 2);#NOERROR
insert into t2 values (1851+0.33);#NOERROR
CREATE TABLE t1 (f1 int);#ERROR: 1050 - Table 't1' already exists
insert into t values (cast(7 as json), '7'),  (cast(2 as json), '2');#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'json), '7'),  (cast(2 as json), '2')' at line 1
insert into t2 values (15373);#NOERROR
update t1 set name='U+2520 BOX DRAWINGS VERTICAL HEAVY AND RIGHT LIGHT' where ujis=0xA8B7;#ERROR: 1054 - Unknown column 'ujis' in 'where clause'
SELECT 15076 MOD 5000;#NOERROR
DROP TABLE t1;#NOERROR
SELECT SUBSTRING('11', 2);#NOERROR
SELECT * FROM t1 WHERE c1 <> '0000-00-00' ORDER BY c1;#ERROR: 1146 - Table 'test.t1' doesn't exist
UPDATE t1 SET b = CONCAT(b, '+con1') WHERE a = 1;#ERROR: 1146 - Table 'test.t1' doesn't exist
CREATE TABLE t1(c1 INT, c2 char(20)) ENCRYPTION="Y" ENGINE=RocksDB;#ERROR: 1911 - Unknown option 'ENCRYPTION'
PREPARE stmt3 FROM @stmt;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'NULL' at line 1
select locate(_ujis 0xa2a1,_ujis 0xa1a2a1a3 collate ujis_bin);#NOERROR
INSERT INTO t1  VALUES(0, "aaaaa");#ERROR: 1146 - Table 'test.t1' doesn't exist
explain extended select rand(999999),rand();#NOERROR
SELECT * FROM t1  WHERE c1 <= '838:59:59' ORDER BY c1 DESC;#ERROR: 1146 - Table 'test.t1' doesn't exist
INSERT INTO t1  VALUES(1);#ERROR: 1146 - Table 'test.t1' doesn't exist
SELECT * FROM t1 WHERE c2 >= '1000-00-01' AND c2 < '2010-10-00' AND c1 = '2010-00-01' ORDER BY c2;#ERROR: 1146 - Table 'test.t1' doesn't exist
insert into t3 values (adddate(19700101000000,interval 10-1 month));#NOERROR
SET SESSION DEFAULT_STORAGE_ENGINE='RocksDB';#ERROR: 1286 - Unknown storage engine 'RocksDB'
SELECT * FROM t1  WHERE c1 = '0000-00-00' ORDER BY c1 LIMIT 2;#ERROR: 1146 - Table 'test.t1' doesn't exist
INSERT INTO ti VALUES (7663375919056424391,88,'G3CpVsOZSyO0k','BR7sU1iKTOB14hO3c7CRp','2CVsA','X5WMPzRsv5BNLVZtHQ8ElJqshn4SW77dNvPj9','Dm','c',1);#NOERROR
GRANT SELECT ON test1.t1 TO user_name_len_22_01234@localhost;#ERROR: 1146 - Table 'test1.t1' doesn't exist
replace into s values (1, 1000000000,1027);#ERROR: 1146 - Table 'test.s' doesn't exist
SELECT DATE'01';#ERROR: 1525 - Incorrect DATE value: '01'
INSERT INTO RocksDB.st_spatial_reference_systems(id, catalog_id, name, organization, organization_coordsys_id, definition, description) VALUES (1040003, 1, 'TEST1040003 WGS 84 / TM 116 SE', 'EPSG', 2309, 'PROJCS["WGS 84 / TM 116 SE",GEOGCS["WGS 84",DATUM["World Geodetic System 1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],TOWGS84[0,0,0,0,0,0,0],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.017453292519943278,AUTHORITY["EPSG","9122"]],AXIS["Lat",NORTH],AXIS["Long",EAST],AUTHORITY["EPSG","4326"]],PROJECTION["Transverse Mercator",AUTHORITY["EPSG","9807"]],PARAMETER["Latitude of natural origin",0,AUTHORITY["EPSG","8801"]],PARAMETER["Longitude of natural origin",116,AUTHORITY["EPSG","8802"]],PARAMETER["Scale factor at natural origin",0.9996,AUTHORITY["EPSG","8805"]],PARAMETER["False easting",500000,AUTHORITY["EPSG","8806"]],PARAMETER["False northing",10000000,AUTHORITY["EPSG","8807"]],PARAMETER["Foo",0],UNIT["metre",1,AUTHORITY["EPSG","9001"]],AXIS["E",EAST],AXIS["N",NORTH],AUTHORITY["EPSG","2309"]]', '');#ERROR: 1146 - Table 'RocksDB.st_spatial_reference_systems' doesn't exist
SELECT * FROM t1  WHERE c1 < 16777216 ORDER BY c1,c6 DESC;#ERROR: 1146 - Table 'test.t1' doesn't exist
SELECT count(*) as total_rows, min(c1) as min_value, max(c1) as max_value, sum(c1) as sum, avg(c1) as avg FROM t1 ;#ERROR: 1146 - Table 'test.t1' doesn't exist
DROP PROCEDURE proc_19194_nested_2;#ERROR: 1305 - PROCEDURE test.proc_19194_nested_2 does not exist
CREATE TABLE t1(a int) engine=InnoDB;#NOERROR
set f9 = (f8 * 2);#ERROR: 1193 - Unknown system variable 'f9'
show status like 'Table_locks_waited';#NOERROR
INSERT INTO t VALUES (3695027962133579405,-737750862,'mPyu9uez88ye8sEYCreuFrlWRYYPKUBjwTeR71zwG51J3402WxYME','fPltfLDYFuoF3SICRAwnmzLLxhX8bzdOJKbajeoKOlxk0sDeBx4f9Ul7GD4pwZpbayFL','5IEMt38KbMvZ4CgSzBRa','oAD4xmouxr6MmmoEPTKLfSVAdnFKaboqIbAHqNMA2yw3AnUfsXfhIgI6a6KjnNMpph0nblz0VigVyEoDVmRVvsI7Q9kT','s','h',4);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT * FROM t1  WHERE c2 <> '9999-12-31 23:59:59' ORDER BY c1,c2 LIMIT 2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
SELECT SUBSTRING('11', 2);#NOERROR
SELECT * FROM t3 WHERE c2 >= -9223372036854775809 AND c2 < 9223372036854775808 AND c7 = 35 ORDER BY c2,c7 LIMIT 2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
CREATE PROCEDURE p1(OUT p1 BIGINT, IN p2 BIGINT) CONTAINS SQL SQL SECURITY INVOKER COMMENT 'comment' BEGIN SELECT COUNT(*) INTO t1  FROM t1  WHERE c1 = p2;#ERROR: 1327 - Undeclared variable: t1
DROP TABLE t1;#NOERROR
SELECT schema_name, digest, digest_text, count_star FROM RocksDB.events_statements_summary_by_digest;#ERROR: 1146 - Table 'RocksDB.events_statements_summary_by_digest' doesn't exist
explain select distinct b FROM t1  where (a2 >= 'b') and (b = 'a') group by a1,a2,b;#ERROR: 1146 - Table 'test.t1' doesn't exist
SELECT @@global.max_user_connections;#NOERROR
SET @@global.query_cache_strip_comments = @start_global_value;#NOERROR
CREATE TABLE t1 ( b int(11) default NULL, index(b) ) ENGINE=HEAP;#NOERROR
insert t1 values (1,100);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t (a BIGINT, b SMALLINT UNSIGNED, c CHAR(74), d VARCHAR(99) NOT NULL, e VARBINARY(88) NOT NULL, f VARBINARY(34) NOT NULL, g LONGBLOB NOT NULL, h BLOB, id BIGINT NOT NULL, KEY(b), CLUSTERING KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'e), PRIMARY KEY(id)) ENGINE=RocksDB' at line 1
INSERT INTO t VALUES (20187,2047631996219341321,'Iq7ZDW','WlXbB4NI8YvFn72wY0YYMm','wzygJeAIPBt7BNXfT5M1ptWw2nzgCf7cffqEq5ypjx6mEAzLBbYCg6A8NA3od1PL5EOm8L','lNNUm5c0tz0elJjg4Hzp7tQCqgOU3ROP2uN8df7anNqUQHtQWvJPrfRQ5ZxK43OTMyeBM5HgJ4VTPyQEgB6fo4','X','f',2);#ERROR: 1136 - Column count doesn't match value count at row 1
SET @@global.innodb_old_blocks_pct = @start_global_value;#NOERROR
explain select max(a3) FROM t1  where a2 = 2 and a3 < 'SEA';#NOERROR
SELECT * FROM t1  WHERE c1 <> '0000-00-00 00:00:00' ORDER BY c1,c2;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
CREATE TABLE ti (a MEDIUMINT UNSIGNED, b MEDIUMINT UNSIGNED, c BINARY(60) NOT NULL, d VARCHAR(76), e VARBINARY(40) NOT NULL, f VARBINARY(76), g LONGBLOB NOT NULL, h LONGBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=TokuDB;#ERROR: 1050 - Table 'ti' already exists
SELECT id INTO @modified_dict_id FROM information_schema.xtradb_zip_dict WHERE name = 'dict1';#ERROR: 1109 - Unknown table 'xtradb_zip_dict' in information_schema
SELECT @@global.rocksdb_tmpdir;#ERROR: 1193 - Unknown system variable 'rocksdb_tmpdir'
select dayofmonth("1997-01-02"),dayofmonth(19970323);#NOERROR
drop procedure empty;#ERROR: 1305 - PROCEDURE test.empty does not exist
SELECT IS_IPV4_MAPPED(INET6_ATON('::')), IS_IPV4_COMPAT(INET6_ATON('::'));#NOERROR
DROP PROCEDURE IF EXISTS p3;#NOERROR
set session skip_external_locking=1;#ERROR: 1238 - Variable 'skip_external_locking' is a read only variable
ALTER TABLESPACE ts1 ADD DATAFILE 'datafile2.dat' INITIAL_SIZE=1M ENGINE=RocksDB;#NOERROR
SET lock_wait_timeout = 2;#NOERROR
SET @@session.innodb_table_locks = ’N;#ERROR: 1231 - Variable 'innodb_table_locks' can't be set to the value of '’N'
INSERT INTO t1  VALUES (0x68),(0x69),(0x6A),(0x6B),(0x6C),(0x6D),(0x6E),(0x6F);#NOERROR
INSERT INTO t1 VALUES(1549);#NOERROR
insert into t2 values (20704);#NOERROR
SELECT '1 = 1';#NOERROR
CREATE TABLE t1(c1 INT, c2 char(20)) ENCRYPTION="Y" ENGINE = RocksDB;#ERROR: 1050 - Table 't1' already exists
INSERT INTO t VALUES (8541099,34314,'nqZaIoAireKy1D5p3jn8NNqiOX8TgZKkXlGyt0','hdOM8NRFptb6qoDD0aoy1TKgvXH77WDJ7jaSqSqeDoFyjoyq5ttWQlHUINHku7ngaxjv5V','xNFRMVKuPEJjYRDkbnEzK36slKd0tZZOgHcPz9K9SLTmXjy0aiLX','7IJJAiDlNK6TMQNSEnxb5mQ3','z','ud',9);#ERROR: 1136 - Column count doesn't match value count at row 1
delete from t1 where b=1;#NOERROR
create TABLE t1(a int not null, b int, primary key(a)) engine=RocksDB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t1m (m INT, n INT) ENGINE=RocksDB;#NOERROR
update t set b=a;#ERROR: 1054 - Unknown column 'b' in 'field list'
select * from t1 group by f1, f2;#ERROR: 1054 - Unknown column 'f1' in 'group statement'
INSERT INTO ti VALUES (7921528,14817040,'vsf2hVPdve','EvLLkE1irJd9VnG1hQIe0rvqardBBJlEjE1ubfr76itO9qKuRxOwJSqp70oB5pGg4u1SARO772fRrqhNz4K0ezuxETvN5Tja2hcymGTfyA5XMiT2gTo0iF2FbiJnX2GMTCx2hijk','qk58VY','hYGoVrwDrSGW2UZO1y','K','Y',5);#ERROR: 1062 - Duplicate entry '5' for key 'PRIMARY'
ALTER TABLE t1 CHANGE c3 üò≤ INT;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'ò≤ INT' at line 1
SET @@global.key_cache_age_threshold = -1024;#NOERROR
CREATE TABLE t1 ( siteid varchar(25) NOT NULL default '', rate_code varchar(10) NOT NULL default '', base_rate float NOT NULL default '0', PRIMARY KEY (siteid,rate_code), FULLTEXT KEY rate_code (rate_code) ) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE ti (a MEDIUMINT UNSIGNED NOT NULL, b TINYINT UNSIGNED NOT NULL, c CHAR(97) NOT NULL, d VARBINARY(78) NOT NULL, e VARBINARY(4) NOT NULL, f VARBINARY(79) NOT NULL, g BLOB, h LONGBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
SELECT SUBSTRING('default,', LENGTH('default') + 2);#NOERROR
INSERT INTO t1 VALUES (CONVERT(_ucs2 0x0648067E0646062C USING utf8));#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TEMPORARY TABLE t1 (c1 INT) ENGINE=MRG_RocksDB UNION=(t1,t2);#NOERROR
INSERT INTO t VALUES (2467209489,-16,'XaouemX','s6rIkZGycQd843Ngur45XThYUKw2ZHSJJ6Z5A31eLkQaaqnHC6zb3iqqZCQ4AnzO9HuYhIdeBBhLB8eaXgZo32xKWCBBAeMZikRlRfAPv2q4Jfa9zzOpSL4Ct4ee2ajr8F1HB8i','h244','M6gNTObZEGPMLr7GEmZmGxnSDPAxoxDQ2qhRhU4nmVzRjnU6BACQc3RocksDBKvkhKJY23Ici1s7dttwLQQ7LOVaLefKfA2TG0W4sdZ8UZ0IJCzqGjvtv9N8T6naEN03','87','B',4);#ERROR: 1136 - Column count doesn't match value count at row 1
CALL sp6(-1.00e+09);#ERROR: 1305 - PROCEDURE test.sp6 does not exist
insert into at(c,_dat) select concat('_dat: ',c),j from t where c='null';#ERROR: 1146 - Table 'test.at' doesn't exist
INSERT INTO t VALUES (3180705111895225726,49690,'ALCtLOw9vL4nJX8EEJc6yIcAYdDNT','RYIqIhA8uqHthN3Nh1PRrdkh3G0XnRhFV6hQiGKRxml2675ge4GkxlK6YIiVD4k7Po4CbRJunjJfDjDdL3MmLfmTyGBkNxQzlBbuJTPeIyPG1LhGwbhiWUIViKtVi5CWnnBcR28kbiKPIlOuSy3gDGBCN1tiIpBf9chV4tS8zJHTXDGoE5M4rvFjg7kRVieX7LzqHuSCMsn3FzcEAQiiLPiueeyi','DJpRJoCGZC2YAfDDGH3Z0hHk','qFizulzKXrc27iMiio9UySUoP4ygDyIUmGq2xRidRfyViqPBaON','f','m',13);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE ti (a SMALLINT, b INT UNSIGNED, c CHAR(75), d VARCHAR(87), e VARBINARY(51), f VARCHAR(44) NOT NULL, g TINYBLOB NOT NULL, h BLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=myisam;#ERROR: 1050 - Table 'ti' already exists
ALTER TABLE ti CHANGE COLUMN a a CHAR(7);#NOERROR
SELECT keep_files_on_create = @@session.keep_files_on_create;#ERROR: 1054 - Unknown column 'keep_files_on_create' in 'field list'
CREATE TABLE t1 ( a INT ) ENGINE = RocksDB;#ERROR: 1050 - Table 't1' already exists
insert into t2 values (64678+0.755555555);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t1( a VARBINARY(32769) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=InnoDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=InnoDB' at line 1
INSERT INTO t1  VALUES('2002-01-01','2002-01-02',3),('2002-01-04','2002-01-02',4);#ERROR: 1136 - Column count doesn't match value count at row 1
select @@session.innodb_compression_level;#ERROR: 1238 - Variable 'innodb_compression_level' is a GLOBAL variable
update t1 set name='U+03BA GREEK SMALL LETTER KAPPA' where ujis=0xA6CA;#ERROR: 1054 - Unknown column 'ujis' in 'where clause'
DELETE FROM t1  WHERE MATCH (a,b) AGAINST ('+MySQL' IN BOOLEAN MODE);#ERROR: 1054 - Unknown column 'a' in 'where clause'
CREATE TABLE t2 (primary key (a)) engine=RocksDB select * from t1;#ERROR: 1050 - Table 't2' already exists
CREATE TABLE t1 (t0 TIME, t1 TIME(1), t1 TIME(3), t1 TIME(4), t1 TIME(6));#ERROR: 1050 - Table 't1' already exists
SELECT QUOTE(SUBSTRING('[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 258)] = 1', 1 + 1, 62 - 1 - 1));#NOERROR
SHOW GLOBAL variables LIKE 'early-plugin-load';#NOERROR
INSERT INTO t1  VALUES(DATE_ADD(CAST('2001-01-01 00:00:00' AS DATETIME(6)), INTERVAL 1 SECOND));#NOERROR
select * FROM t1  where a=0 and (( b > 0 and b < 3) or ( b > 5 and b < 10) or ( b > 22 and b < 50)) order by c;#ERROR: 1054 - Unknown column 'a' in 'where clause'
update worklog5743 set a = (repeat("x", 25000));#ERROR: 1146 - Table 'test.worklog5743' doesn't exist
select @@global.ft_stopword_file;#NOERROR
select Name, convert_tz('2004-11-30 12:00:00', Name, 'UTC') from mysql.time_zone_name;#NOERROR
DROP TABLE t592;#ERROR: 1051 - Unknown table 'test.t592'
RENAME TABLE t1 TO d1.t3;#NOERROR
INSERT INTO t1  VALUES(0,-128,0),(1,1,1),(2,2,2),(0,\N,3),(101,-101,4),(102,-102,5),(103,-103,6),(104,-104,7),(105,-105,8);#ERROR: 1062 - Duplicate entry '1' for key 'PRIMARY'
SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 4294967295);#NOERROR
INSERT INTO t1 VALUES(17118);#ERROR: 1136 - Column count doesn't match value count at row 1
SET @@session.max_error_count = 9;#NOERROR
SELECT * FROM t2 WHERE c2 = NULL ORDER BY c1,c2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
DROP VIEW IF EXISTS mysqltest1.v4;#NOERROR
SELECT LOCATE(']', '1 = 1');#NOERROR
insert into foo values (10000);#ERROR: 1136 - Column count doesn't match value count at row 1
insert INTO t1 _30237_bool values (FALSE, FALSE, FALSE), (FALSE, FALSE, NULL), (FALSE, FALSE, TRUE), (FALSE, NULL, FALSE), (FALSE, NULL, NULL), (FALSE, NULL, TRUE), (FALSE, TRUE, FALSE), (FALSE, TRUE, NULL), (FALSE, TRUE, TRUE), (NULL, FALSE, FALSE), (NULL, FALSE, NULL), (NULL, FALSE, TRUE), (NULL, NULL, FALSE), (NULL, NULL, NULL), (NULL, NULL, TRUE), (NULL, TRUE, FALSE), (NULL, TRUE, NULL), (NULL, TRUE, TRUE), (TRUE, FALSE, FALSE), (TRUE, FALSE, NULL), (TRUE, FALSE, TRUE), (TRUE, NULL, FALSE), (TRUE, NULL, NULL), (TRUE, NULL, TRUE), (TRUE, TRUE, FALSE), (TRUE, TRUE, NULL), (TRUE, TRUE, TRUE);#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '_30237_bool values (FALSE, FALSE, FALSE), (FALSE, FALSE, NULL), (FALSE, FALSE...' at line 1
SELECT * FROM t1  WHERE c1 IN ('1000-00-01','9999-12-31') ORDER BY c1 DESC;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
insert into t1 (a,b) values (a,b);#NOERROR
INSERT INTO t VALUES (-229671,-54187693,'29ZmLOpwAUAY9KZ2N99zoXOfIusIGC','snZgH3TL2ukUPg3H5jmfhRJAtO2jchxUPjKXM','di1pDyXlrxL7K3pc9hTp8kGfhE8aKM1p9gyTaliXRm8cPyfF3lxyO6xwOMbDDNqveah8J3G5mzvF','J6ofH6zVY7kNNtPDlwx2Tz16RV1BoI2UNAiIxiac7HIBP5si8ehyhsGPuRxRTYnGaUKXqDGZ2NCiBLlOyl1VRoJ4wHaY7PezLBscz26br9XDcnpcjvEjHzNt9p2UCR5ofcE03rYnhVyDbcsMdat7eUPsRn','V','c',6);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t1( a VARBINARY(128) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = DYNAMIC ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = DYNAMIC ENGINE=RocksDB' at line 1
INSERT INTO t2 VALUES (1,'master/slave');#ERROR: 1136 - Column count doesn't match value count at row 1
insert into t2 values (60448);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT QUOTE(SUBSTRING('[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 16385)] = 1', 1 + 1, 64 - 1 - 1));#NOERROR
SELECT REPEAT('.', 2 - 1);#NOERROR
insert into t1 (id, warehouse_id) values(4, 2);#ERROR: 1054 - Unknown column 'id' in 'field list'
CREATE TABLE m3(c1 BIGINT NULL, c2 BINARY(25) NOT NULL, c3 INTEGER(4) NULL, c4 BINARY(15) NOT NULL PRIMARY KEY, c5 BIGINT NOT NULL UNIQUE KEY,c6 DECIMAL(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 'm3' already exists
INSERT DELAYED INTO t1  SET a = 2, b = '1980-01-02 10:20:30.405060';#ERROR: 1792 - Cannot execute statement in a READ ONLY transaction
SET @@SESSION.group_replication_recovery_ssl_ca= "";#ERROR: 1193 - Unknown system variable 'group_replication_recovery_ssl_ca'
INSERT INTO t VALUES (-3287242504141229993,14623220475842147454,'LbSvX80I912voVofgDhVfBdfy14wdRQWhlN5wEc64pK2Ve5nA0H8Cxv1LgYpgXWmJJAm6c','gj','Tb','2Ue','Vb','v',11);#ERROR: 1136 - Column count doesn't match value count at row 1
replace into s values (1, 1000000000,451);#ERROR: 1146 - Table 'test.s' doesn't exist
set @@optimizer_switch=@old_opt_switch;#ERROR: 1231 - Variable 'optimizer_switch' can't be set to the value of 'NULL'
CREATE TABLE `Ç†Ç†Ç†`(`Ç´Ç´Ç´` char(5)) DEFAULT CHARSET = sjis engine=RocksDB;#ERROR: 1300 - Invalid utf8mb4 character string: '\x82\xA0\x82\xA0\x82\xA0'
create table tt (id bigint unsigned primary key, f0 int null, v0 varchar(32) null, b0 longblob null, b1 longblob null, b2 blob null ) engine=RocksDB;#ERROR: 1050 - Table 'tt' already exists
INSERT INTO `t1` VALUES (2085,'2012-01-01 00:00:00','2013-01-01 00:00:00');#NOERROR
INSERT INTO t set c = concat(repeat('x',28),'g','w');#ERROR: 1054 - Unknown column 'c' in 'field list'
INSERT INTO t1 VALUES ('13:02:46',NULL,'x');#NOERROR
SELECT ST_ASTEXT(ST_BUFFER(ST_GEOMFROMTEXT('MULTIPOLYGON(((0 0,1 1,2 0,0 0)),((3 3,4 4,5 3,3 3)))'), 1, ST_BUFFER_STRATEGY('point_circle', 10)));#ERROR: 1582 - Incorrect parameter count in the call to native function 'ST_BUFFER'
delete from RocksDB.ndb_replication where db="Europe%" and table_name="netherlands" and server_id=0;#ERROR: 1146 - Table 'RocksDB.ndb_replication' doesn't exist
SELECT @start_RocksDB_max_capacity;#NOERROR
select * from ti /* that is what slave would miss - bug#28960 */;#NOERROR
set global thread_cache_size         =@my_thread_cache_size;#ERROR: 1232 - Incorrect argument type to variable 'thread_cache_size'
drop function keyring_key_fetch;#ERROR: 1305 - FUNCTION test.keyring_key_fetch does not exist
SET TIME_ZONE = "+00:00";#NOERROR
CREATE TABLE t1( a NATIONAL VARCHAR(8192) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = DYNAMIC ENGINE=InnoDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = DYNAMIC ENGINE=InnoDB' at line 1
select max(fld1) from t2 where fld1>= 098024;#ERROR: 1054 - Unknown column 'fld1' in 'field list'
INSERT INTO t87 VALUES('a');#ERROR: 1146 - Table 'test.t87' doesn't exist
INSERT INTO t1(a) VALUES (REPEAT('abcd', 128));#NOERROR
CREATE TABLE t12(c1 INT, c2 char(20)) ENCRYPTION="Y" ENGINE = TokuDB;#ERROR: 1911 - Unknown option 'ENCRYPTION'
INSERT INTO t VALUES (8479770912562238679,-4348506185467972376,'SG94KY1ryv4h4mfJIhgDzFR8DlG32NIr7sxovdynkSK6lFSxXP0oYCXaFBhw6WP5JLirXX','ZLqOgk1YSkoEOPLUu8','aTzEl8oIPB3bGPsjS1graCdbFyELQH3ZsXFiHAvgFJRoY73CZD2KY4TPXQLYI3v','aLlKxGOgAGtq','Wv','b',4);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE ti (a TINYINT, b BIGINT UNSIGNED, c CHAR(76) NOT NULL, d VARCHAR(70), e VARCHAR(53) NOT NULL, f VARCHAR(81) NOT NULL, g LONGBLOB NOT NULL, h MEDIUMBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
INSERT INTO t1 VALUES(22602);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT SUBSTRING('1', 1, 1);#NOERROR
end while hmm;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'end while hmm' at line 1
SELECT a FROM t1  HAVING COUNT(*)>2;#NOERROR
insert into t2 values (65331+0.333333333);#ERROR: 1136 - Column count doesn't match value count at row 1
create TABLE t1 (c1 char(10), c2 char(10)) engine=RocksDB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t2 (a INT NOT NULL PRIMARY KEY, b VARCHAR(10)) ENGINE=MEMORY;#ERROR: 1050 - Table 't2' already exists
create table mysqltest.t1 (i int not null);#ERROR: 1049 - Unknown database 'mysqltest'
SELECT a,c FROM t1 ;#ERROR: 1054 - Unknown column 'c' in 'field list'
SELECT ST_TOUCHES(g,ST_GEOMFROMTEXT(@star_elem_vertical)) FROM gis_geometrycollection WHERE fid=114;#ERROR: 1146 - Table 'test.gis_geometrycollection' doesn't exist
insert into t2 values (10604);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT CAST(NULL AS JSON) = NULL;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'JSON) = NULL' at line 1
CREATE TABLE t (a INT UNSIGNED NOT NULL, b TINYINT UNSIGNED, c BINARY(58), d VARCHAR(71) NOT NULL, e VARBINARY(79), f VARCHAR(72) NOT NULL, g BLOB, h LONGBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), CLUSTERING KEY(e), PRIMARY KEY(id)) ENGINE=tokudb;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'e), PRIMARY KEY(id)) ENGINE=tokudb' at line 1
SELECT HEX(LPAD(0x20, 2, _utf8 0xD18F));#NOERROR
SELECT * FROM t1  WHERE MATCH (a,b) AGAINST ('"Œ≥œÖŒ±ŒªŒπ·Ω∞ œáœâœÅ·Ω∂œÇ"@2' IN BOOLEAN MODE);#ERROR: 1191 - Can't find FULLTEXT index matching the column list
explain SELECT * FROM t1  force index(idx) WHERE c1 <> '1' ORDER BY c1 DESC;#NOERROR
SELECT 41 - LENGTH(SUBSTRING_INDEX(SUBSTR('[SELECT COUNT(*) FROM t1 WHERE a IS NULL] = 1', 1, 41), '[', -1));#NOERROR
purge master logs before (select adddate(current_timestamp(), interval -4 day));#ERROR: 1970 - PURGE..BEFORE does not support subqueries or stored functions
INSERT INTO t1  set c = concat(repeat('x',28),'r','x');#ERROR: 1054 - Unknown column 'c' in 'field list'
SELECT * FROM t2 WHERE c2 <= '-838:59:59' ORDER BY c1,c2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
set @@sql_mode=@org_mode;#ERROR: 1231 - Variable 'sql_mode' can't be set to the value of 'NULL'
SELECT IF(32766 > 0, 32766, 1);#NOERROR
SELECT SUBSTRING('1', 2);#NOERROR
create table t1 (id int) engine=RocksDB;#ERROR: 1050 - Table 't1' already exists
EXPLAIN SELECT a,b,c FROM t1  WHERE b = 2 AND a = 2 AND c > 0 AND c < 100;#NOERROR
explain select * FROM t1  where a=5 and a=6;#NOERROR
CREATE PROCEDURE p1(f1 decimal (63, 30) zerofill) BEGIN set f1 = (f1 / 2);#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
INSERT INTO t VALUES (3);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t1(c1 BLOB NULL COMMENT 'This is a BLOB column');#ERROR: 1050 - Table 't1' already exists
INSERT INTO t1 VALUES(1690);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT SUBSTRING('1', 2);#NOERROR
SELECT ST_ASTEXT(ST_VALIDATE(0x000000000200000001000000050000000000000000));#ERROR: 1305 - FUNCTION test.ST_VALIDATE does not exist
set password for rpl_do_grant@localhost=password('does it work?');#ERROR: 1133 - Can't find any matching row in the user table
ALTER TABLE RocksDB.tables_priv ENGINE = RocksDB;#ERROR: 1146 - Table 'RocksDB.tables_priv' doesn't exist
INSERT INTO t1 (c1,c2) VALUES('34 9:23','34 9:23') ON DUPLICATE KEY UPDATE c1='32 9:23',c2='33 9:23';#ERROR: 1054 - Unknown column 'c1' in 'field list'
SELECT * FROM articles where MATCH(title, body) AGAINST ('MySQL - (- tutorial database) -Tricks' IN BOOLEAN MODE);#ERROR: 1146 - Table 'test.articles' doesn't exist
SET default_storage_ENGINE=RocksDB;#ERROR: 1286 - Unknown storage engine 'RocksDB'
SELECT SUBSTRING('1', 2);#NOERROR
UPDATE t1 SET a=CONCAT('-', a);#NOERROR
SELECT SUBSTRING('00', 1, 1);#NOERROR
SET @@lc_time_names = 10;#NOERROR
SELECT SUBSTRING('11', 1, 1);#NOERROR
CREATE TABLE ti (a INT, b INT UNSIGNED, c CHAR(86) NOT NULL, d VARBINARY(14), e VARCHAR(23) NOT NULL, f VARBINARY(69) NOT NULL, g LONGBLOB NOT NULL, h TINYBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=InnoDB;#ERROR: 1050 - Table 'ti' already exists
ALTER INSTANCE ROTATE INNODB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'INSTANCE ROTATE INNODB' at line 1
CREATE TABLE t2( id INT, a BLOB COLUMN_FORMAT COMPRESSED ) ENGINE=MyISAM;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ENGINE=MyISAM' at line 1
CREATE TABLE t1 (id tinyint(3) default NULL, data varchar(255) default NULL);#ERROR: 1050 - Table 't1' already exists
select @@IDENTITY,last_insert_id(), @@identity;#NOERROR
ALTER TABLE t1 ADD PARTITION (PARTITION p2 VALUES IN ((71),(72),(73),(74),(75),(76),(77),(78),(79),(80), (81),(82),(83),(84),(85),(86),(87),(88),(89),(90)));#ERROR: 1064 - Row expressions in VALUES IN only allowed for multi-field column partitioning near '))' at line 1
create table t1 (a int) engine= RocksDB;#ERROR: 1050 - Table 't1' already exists
select * from information_schema.global_variables where variable_name='RocksDB_file_format';#NOERROR
INSERT INTO t VALUES (10637694389491105381,119,'nMOe4Qm','at2N3P41z9Dw7C7f2anXf3SqdwwRacGenInIKlWWv2sClyQlCieMTWqCvxVsNRVyOaWS4haHJmAj0JMOpo6NFOxq8HyVm9mPBVFLUVJ4D1VQqoSfIgMCC59Rf8ormZsoOr3R4dnsQLQZtNvLertyvpf2fTV4ZUinig2Nb57h912reeUvsj16UjklicRwLzDOQnLZv9OxqGOgkcwZA43','jM','1SXbpmRZSTx8JSGZauLENHtXjn7AW0','Z','G',4);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT * FROM `ÇsÇQ` WHERE `ÇbÇP` LIKE '%Å@%';#ERROR: 1300 - Invalid utf8mb4 character string: '\x82s\x82Q'
SELECT QUOTE(REPLACE('[SELECT COUNT(*) FROM t1 WHERE a = ""] = 1', CONCAT('[', 'SELECT COUNT(*) FROM t1 WHERE a = ""', ']'), '1'));#NOERROR
SELECT * FROM `test/1`.m1;#ERROR: 1146 - Table 'test/1.m1' doesn't exist
SET @saved_log_slow_verbosity=@@GLOBAL.log_slow_verbosity;#NOERROR
insert INTO t1  (bandID,payoutID) VALUES (1,6),(2,6),(3,4),(4,9),(5,10),(6,1),(7,12),(8,12);#ERROR: 1054 - Unknown column 'bandID' in 'field list'
SELECT `ÇbÇP`, SUBSTRING(`ÇbÇP` FROM 1 FOR 2) FROM `ÇsÇT`;#ERROR: 1300 - Invalid utf8mb4 character string: '\x82b\x82P'
INSERT INTO t VALUES (5676972585360535098,1051405245,'R','5b7VXeLWSHOYyH4UKuM6','hlwuzYVXXfV7RMsU','udVoWe','p','A',10);#ERROR: 1136 - Column count doesn't match value count at row 1
prepare stmt from "select * from v1 where a";#NOERROR
create TABLE t1 ( a int primary key, b int not null, c int not null, unique(b) using hash, index(c) ) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE m3(c1 SMALLINT NULL, c2 VARCHAR(25) NOT NULL, c3 INT(4) NULL, c4 VARCHAR(15) NOT NULL PRIMARY KEY, c5 SMALLINT NOT NULL UNIQUE KEY,c6 DEC(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 'm3' already exists
create TABLE t1 (a int not null, b int not null, c blob not null, d int not null, e int, primary key (a,b,c(255),d)) engine=RocksDB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t2 ( f1 INTEGER );#ERROR: 1050 - Table 't2' already exists
alter table t1 modify text1 char(32) binary not null;#ERROR: 1054 - Unknown column 'text1' in 't1'
SELECT SUBSTRING('00', 2);#NOERROR
SELECT LOCATE(']', '1 = 1');#NOERROR
INSERT INTO t2 VALUES (643,188010,37,'commencements','registration','workers','W');#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO t1 VALUES(0xADBE);#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO t1  VALUES (551,148503,29,'fifteenth','disobedience','lacerating','A');#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT CONCAT('SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 255)', 'ZZENDZZ') REGEXP '[a-zA-Z_][a-zA-Z0-9_]* *, *[0-9][0-9]* *ZZENDZZ';#NOERROR
SELECT * FROM federated.t1 WHERE name = 'Third name';#ERROR: 1146 - Table 'federated.t1' doesn't exist
INSERT INTO t1  VALUES ('1972-02-06'), ('1972-07-29');#ERROR: 1136 - Column count doesn't match value count at row 1
update s set a=20000+4112 where a=4112;#ERROR: 1146 - Table 'test.s' doesn't exist
SELECT c2,MIN(c7) FROM t3 GROUP BY c2;#ERROR: 1054 - Unknown column 'c2' in 'field list'
CREATE TABLE t2 (a int) ENGINE=RocksDB;#ERROR: 1050 - Table 't2' already exists
CREATE TABLE m3(c1 REAL NULL, c2 CHAR(25) NOT NULL, c3 INTEGER(4) NULL, c4 CHAR(15) NOT NULL PRIMARY KEY, c5 REAL NOT NULL UNIQUE KEY,c6 DEC(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 'm3' already exists
SELECT a, a+1, SUM(a) FROM t1 GROUP BY a WITH ROLLUP;#NOERROR
DROP VIEW v1;#ERROR: 4092 - Unknown VIEW: 'test.v1'
insert into at(c,_blb) select concat('_blb: ',c),j from t where c='opaque_mysql_type_datetime';#ERROR: 1146 - Table 'test.at' doesn't exist
CREATE TABLE t1(id INT NOT NULL PRIMARY KEY, data TEXT) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
CREATE EVENT e1 ON SCHEDULE EVERY 5 HOUR DO SELECT 1;#ERROR: 1537 - Event 'e1' already exists
select NULL IS FALSE IS FALSE IS FALSE;#NOERROR
select * from t1 where v='This is a test' order by v;#ERROR: 1054 - Unknown column 'v' in 'where clause'
SELECT 'a\0' < 'a' collate utf8_bin;#ERROR: 1253 - COLLATION 'utf8_bin' is not valid for CHARACTER SET 'utf8mb4'
INSERT INTO t1 (rollno, name) VALUES(5, 'Record_13');#ERROR: 1054 - Unknown column 'rollno' in 'field list'
SELECT SUBSTRING('00', 1, 1);#NOERROR
INSERT INTO t VALUES (4293441793,-541461847,'gQn2MTUAWoTAsxwoJZsQOE','Vv1lSJvCWlVzZoxBSACxUdu3mYwy79mNwKRZYL8dogeqRflzvcQvG3QixsGOf8AFQzDrnQnyTLMWWdRDrJXcSmOgdTK8KBI6','WCXSgNBkWuzqQ1cE9AOD','3Lkp5N6knhemERZObBojRzVH5XNND60ZCSQlZZl42DFM8KF5xZb83Cs','Vm','X',13);#ERROR: 1136 - Column count doesn't match value count at row 1
DROP VIEW v1;#ERROR: 4092 - Unknown VIEW: 'test.v1'
INSERT INTO t1 (a) VALUES ('00:00:00.000001');#NOERROR
SELECT * FROM t1 _child;#NOERROR
call mtr.add_suppression("Out of sort RocksDB; increase server sort buffer size");#ERROR: 1305 - PROCEDURE mtr.add_suppression does not exist
INSERT INTO t341 VALUES(1);#ERROR: 1146 - Table 'test.t341' doesn't exist
UPDATE performance_schema.setup_instruments SET enabled = 'YES' WHERE name in ('wait/io/table/sql/handler', 'wait/lock/table/sql/handler');#NOERROR
update t1 set c3 = repeat('D', 20000) where c1 = 1;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
select i1 FROM t1  where i1=1;#NOERROR
SELECT REPEAT('.', 1 - 1);#NOERROR
update t1 set name='U+0398 GREEK CAPITAL LETTER THETA' where ujis=0xA6A8;#ERROR: 1054 - Unknown column 'ujis' in 'where clause'
DROP USER mysqluser1;#ERROR: 1396 - Operation DROP USER failed for 'mysqluser1'@'%'
SELECT SUBSTRING('11', 1, 1);#NOERROR
SET @@global.character_set_database = latin1;#NOERROR
select t1.name, t2.name, t2.id, t2.owner, t3.id from t1 left join t2 on (t1.id = t2.owner) right join t1 as t3 on t3.id=t2.owner;#ERROR: 1054 - Unknown column 't1.name' in 'field list'
SELECT SUBSTRING('1', 1, 1);#NOERROR
CREATE TABLE t1(a BLOB COLUMN_FORMAT COMPRESSED);#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED)' at line 1
CREATE TABLE `£‘£¥` (c1 char(20), INDEX(c1)) DEFAULT CHARSET = ujis engine = RocksDB;#ERROR: 1300 - Invalid utf8mb4 character string: '\xA3\xD4\xA3\xB4'
INSERT INTO t1 (koi8_ru_f,comment) VALUES ('N','LAT CAPIT N');#ERROR: 1054 - Unknown column 'koi8_ru_f' in 'field list'
INSERT INTO t1  VALUES ('11:22:33');#ERROR: 1136 - Column count doesn't match value count at row 1
call mtr.add_suppression("\\[Error\\] InnoDB: Failed to find tablespace for table");#ERROR: 1305 - PROCEDURE mtr.add_suppression does not exist
create TABLE t1 (a int, b int, c int, d int, e int, primary key (a,b,c), key (a,c,d,e)) engine=RocksDB;#ERROR: 1050 - Table 't1' already exists
INSERT INTO `Ôº¥Ôºì` VALUES ('ÈæîÈæñÈæóÈæûÈæ°„ÄÄ„ÄÄ„ÄÄ');#ERROR: 1146 - Table 'test.Ôº¥Ôºì' doesn't exist
set session rpl_semi_sync_master_trace_level=99;#ERROR: 1229 - Variable 'rpl_semi_sync_master_trace_level' is a GLOBAL variable and should be set with SET GLOBAL
CREATE TABLE `èÌ›èÌ›èÌ›`(`è∞°è∞°è∞°` char(5)) DEFAULT CHARSET = ujis engine=RocksDB;#ERROR: 1300 - Invalid utf8mb4 character string: '\x8F\xED\xDD\x8F\xED\xDD\x8F\xED\xDD'
create TABLE t1 (a int, b char(255)) engine=RocksDB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t1(a TEXT, fulltext(a)) ENGINE = RocksDB;#ERROR: 1050 - Table 't1' already exists
prepare stmt from "select * from mysql.general_log where argument='IMPOSSIBLE QUERY STRING'";#NOERROR
ALTER TABLE ti CHANGE COLUMN c c CHAR(47) NOT NULL;#NOERROR
SELECT * FROM t1  WHERE c2 >= '2010-10-00' ORDER BY c1,c2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
ALTER TABLE t CHANGE COLUMN a a CHAR(43);#ERROR: 1054 - Unknown column 'a' in 't'
ALTER SCHEMA d8   CHARACTER SET binary;#ERROR: 1 - Can't create/write to file './d8/db.opt' (Errcode: 2 "No such file or directory")
CREATE TABLE t1(c1 TINYINT NULL, c2 VARBINARY(25) NOT NULL, c3 BIGINT(4) NULL, c4 VARBINARY(15) NOT NULL PRIMARY KEY, c5 TINYINT NOT NULL UNIQUE KEY,c6 FIXED(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 't1' already exists
SET NAMES cp1251;#NOERROR
CREATE TABLE t1b (b INT, c INT) ENGINE=BLACKHOLE;#NOERROR
insert into at(c,_bin) select concat('_bin: ',c), (select j from t where c='opaque_mysql_type_mediumblob') from t where c='opaque_mysql_type_mediumblob';#ERROR: 1146 - Table 'test.at' doesn't exist
ALTER TABLE t1 ENGINE=RocksDB;#NOERROR
SELECT SUBSTRING_INDEX('default,default,', ',', 1);#NOERROR
insert into t2 values(2,3);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT ST_TOUCHES(ST_GEOMFROMTEXT(@star_line_horizontal),ST_GEOMFROMTEXT('MULTIPOLYGON(((11 15,19 15,19 25,11 15,11 15)),((25 0,0 15,25 10,25 0)))'));#NOERROR
alter table bar drop column ccc, drop column cc;#ERROR: 1146 - Table 'test.bar' doesn't exist
CREATE TABLE m3(c1 TINYINT NULL, c2 VARBINARY(25) NOT NULL, c3 MEDIUMINT(4) NULL, c4 VARBINARY(15) NOT NULL PRIMARY KEY, c5 TINYINT NOT NULL UNIQUE KEY,c6 NUMERIC(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 'm3' already exists
INSERT INTO ti VALUES (78,2531883683,'7FKwE9','Qo8SHuX43aNMXOibcLgYr4UCFWloni70asW06eV55aEzcHx88O2zPme9AzyUMP5Cz9059JOxf1UH6wQm5P9o','abDAyaDWXsXhnC21NuVZ','SDm3ng94rRT2RfG2hiWD8kX4qzfjkZJhj0Ba4b9Me4tAs2vyupBPsHAxFpmB85uNRaOrHzyhZsDhhrWkL7qXQ2lLwyq3NawTan8hBK8l1B5dy52CwL0Ra6MsvyMnbAZkkuCwybn1tAogR8srEnnPgs9eLrUHgMrxb7vIaWgUIDnHn8HwtbAnkb9T8r4w00lpZ4TcruBVqUw3fR545z13tLLncKOmDQHnjZL','66','tN',6);#ERROR: 1062 - Duplicate entry '6' for key 'PRIMARY'
insert into t1 set f1=0x3F3F9DC73F;#ERROR: 1054 - Unknown column 'f1' in 'field list'
SELECT COUNT(@@local.RocksDB_buffer_pool_chunk_size);#ERROR: 1193 - Unknown system variable 'RocksDB_buffer_pool_chunk_size'
SELECT * FROM t3 WHERE c2 <> '9999-12-31' ORDER BY c1,c2 LIMIT 2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
CALL proc();#ERROR: 1305 - PROCEDURE test.proc does not exist
SELECT SUBSTRING('11', 1, 1);#NOERROR
SELECT MASTER_POS_WAIT('master-bin.000001', 222836, 1);#NOERROR
DROP TABLE t1;#NOERROR
insert into t2 values (49717);#ERROR: 1136 - Column count doesn't match value count at row 1
create table t1 (col1 integer primary key, col2 integer) engine=RocksDB;#NOERROR
SHOW FIELDS FROM gis_geometrycollection;#ERROR: 1146 - Table 'test.gis_geometrycollection' doesn't exist
drop table STDDEV;#ERROR: 1051 - Unknown table 'test.STDDEV'
DROP USER proxied, userW, userX, userY, userZ, userPROXY;#ERROR: 1396 - Operation DROP USER failed for 'proxied'@'%','userW'@'%','userX'@'%','userY'@'%','userZ'@'%','userPROXY'@'%'
update _2.t1, _2.t2 set c=500,d=600;#ERROR: 1146 - Table '_2.t1' doesn't exist
select * from performance_schema.events_statements_summary_global_by_event_name where count_star > 0;#NOERROR
CREATE TABLE t1 ( id_algo int(11) NOT NULL, id_agente int(11) NOT NULL, PRIMARY KEY (id_algo,id_agente), KEY another_data (id_agente) ) ENGINE=InnoDB DEFAULT CHARSET=latin1;#ERROR: 1050 - Table 't1' already exists
insert into t2 values (34182);#ERROR: 1136 - Column count doesn't match value count at row 1
alter table RocksDB.db order by db desc;#ERROR: 1146 - Table 'RocksDB.db' doesn't exist
EXPLAIN EXTENDED SELECT (SELECT 150) AS field5 FROM (SELECT * FROM t1 ) AS alias1 GROUP BY field5;#NOERROR
update RocksDB.setup_consumers set enabled='NO' where name like 'event%';#ERROR: 1146 - Table 'RocksDB.setup_consumers' doesn't exist
SET GLOBAL innodb_corrupt_table_action='salvage';#ERROR: 1193 - Unknown system variable 'innodb_corrupt_table_action'
CREATE TABLE ti (a MEDIUMINT UNSIGNED NOT NULL, b MEDIUMINT, c BINARY(91), d VARBINARY(66), e VARCHAR(41), f VARCHAR(83) NOT NULL, g LONGBLOB NOT NULL, h LONGBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
select json_contains_path('{ "a": true, "b": [ 1, 2 ] }', 'one', '$.b[0]', '$.c', '$**[1]' );#NOERROR
show global variables like 'RocksDB_max_statement_classes';#NOERROR
SELECT f1_simple_insert(NULL),f1_simple_insert(1);#ERROR: 1305 - FUNCTION test.f1_simple_insert does not exist
INSERT INTO ti VALUES (7151726147270113,4224443,'2gKBtbrBpe54tXt4FKeKg4nHpEqVooBDW9Sg','G','NZx08DgylpnZ','xP062RtnOmi2Jua5oRnb7cufIlK','d','8',10);#ERROR: 1062 - Duplicate entry '10' for key 'PRIMARY'
SELECT 'SELECT COUNT(*) FROM t1 WHERE a = CAST(@inserted_value AS JSON)';#NOERROR
CREATE TABLE t1(c1 BIGINT NULL);#ERROR: 1050 - Table 't1' already exists
create algorithm=temptable view v4 (c) as select c+1 FROM t1 ;#ERROR: 1054 - Unknown column 'c' in 'field list'
truncate table performance_schema.file_instances;#ERROR: 1683 - Invalid performance_schema usage
create table t1 (sint64 bigint not null);#ERROR: 1050 - Table 't1' already exists
ALTER TABLE query_rewrite.rewrite_rules ENGINE = RocksDB;#ERROR: 1146 - Table 'query_rewrite.rewrite_rules' doesn't exist
SELECT MBRTOUCHES(ST_GEOMFROMTEXT('POINT(20 20)'),ST_GEOMFROMTEXT('GEOMETRYCOLLECTION(GEOMETRYCOLLECTION(POLYGON((0 0,10 0,10 10,0 10,0 0))))'));#NOERROR
SET @OLD_SQL_MODE=@@SESSION.SQL_MODE;#NOERROR
explain extended select X(g),Y(g) FROM gis_point;#ERROR: 1146 - Table 'test.gis_point' doesn't exist
CREATE TEMPORARY TABLE t1(c1 TINYBLOB NOT NULL);#NOERROR
DROP TABLE t1;#NOERROR
SET @@session.expire_logs_days = 0;#ERROR: 1229 - Variable 'expire_logs_days' is a GLOBAL variable and should be set with SET GLOBAL
update t1 set name='U+30DE KATAKANA LETTER MA' where ujis=0xA5DE;#ERROR: 1054 - Unknown column 'ujis' in 'where clause'
CREATE USER nopriv_user@localhost;#NOERROR
CREATE TABLE m3(c1 DOUBLE NULL, c2 BINARY(25) NOT NULL, c3 SMALLINT(4) NULL, c4 BINARY(15) NOT NULL PRIMARY KEY, c5 DOUBLE NOT NULL UNIQUE KEY,c6 DECIMAL(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 'm3' already exists
SELECT LOCATE(']', '[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 126)] = 1');#NOERROR
delete from RocksDB.tables_priv where user like "RocksDBtest%";#ERROR: 1146 - Table 'RocksDB.tables_priv' doesn't exist
SELECT * from mysql.proc where specific_name='fn3' and db='d1';#NOERROR
CREATE PROCEDURE p1() DROP DATABASE ;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
select * from wl1612;#ERROR: 1146 - Table 'test.wl1612' doesn't exist
set session performance_schema_hosts_size=1;#ERROR: 1238 - Variable 'performance_schema_hosts_size' is a read only variable
SELECT SUBSTRING_INDEX('default,default,', ',', 1);#NOERROR
CREATE TABLE t1(c1 INT)ENGINE=INNODB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t1(col_1 TINYBLOB, col_2 TINYTEXT,col_3 BLOB, col_4 TEXT,col_5 MEDIUMBLOB,col_6 MEDIUMTEXT, col_7 LONGBLOB,col_8 LONGTEXT,col_9 VARCHAR(255)) ENGINE=INNODB ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=1;#ERROR: 1050 - Table 't1' already exists
SELECT SUBSTRING('11', 2);#NOERROR
SET SESSION GTID_NEXT=AUTOMATIC;#ERROR: 1193 - Unknown system variable 'GTID_NEXT'
INSERT INTO t2 VALUES (1144,083402,00,'founder','honeysuckle','Colombo','');#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT local.completion_type;#ERROR: 1109 - Unknown table 'local' in field list
SELECT REPEAT('.', 2 - 1);#NOERROR
SELECT id, IF(date IS NULL, '-', FROM_UNIXTIME(date, '%d-%m-%Y')) AS date_ord, text FROM t1  ORDER BY date_ord ASC;#ERROR: 1054 - Unknown column 'id' in 'field list'
insert into t (id,a) values (119,26);#ERROR: 1054 - Unknown column 'id' in 'field list'
SET @@global.mts_dependency_size = -1024;#ERROR: 1193 - Unknown system variable 'mts_dependency_size'
DROP TABLE t1;#NOERROR
SELECT SUBSTRING('11', 2);#NOERROR
CREATE TABLE t1 (title text) ENGINE=MyISAM;#NOERROR
DROP TABLE t1;#NOERROR
CREATE TABLE t1 (c1 INT NOT NULL, c2 CHAR(5)) PARTITION BY LINEAR KEY(c1) PARTITIONS 99;#NOERROR
ALTER TABLE t CHANGE COLUMN a b BINARY(197);#ERROR: 1054 - Unknown column 'a' in 't'
SELECT SUBSTRING('00', 1, 1);#NOERROR
ALTER TABLE `èÌ›èÌ›èÌ›` ADD `è∞¢è∞¢è∞¢` char(1) FIRST;#ERROR: 1146 - Table 'test.èÌ›èÌ›èÌ›' doesn't exist
CREATE TABLE t1 (id int(11) NOT NULL PRIMARY KEY, name varchar(20), INDEX (name)) ENGINE=MEMORY;#ERROR: 1050 - Table 't1' already exists
SELECT SUBSTRING('default,default,', LENGTH('default') + 2);#NOERROR
SELECT * FROM t1  WHERE c1 <= '1998-12-29 00:00:00' ORDER BY c1,c2;#NOERROR
SELECT SUBSTRING('00', 1, 1);#NOERROR
ALTER TABLE t CHANGE COLUMN a a CHAR(140) BINARY;#ERROR: 1054 - Unknown column 'a' in 't'
INSERT INTO t1  VALUES ('0000-00-00 00:00:01.000000');#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT GROUP_CONCAT(a SEPARATOR '###') AS names FROM t1  HAVING LEFT(names, 1) ='J';#ERROR: 1054 - Unknown column 'a' in 'field list'
SELECT * FROM t1 ;#NOERROR
CREATE PROCEDURE p1() BEGIN DECLARE x NUMERIC ZEROFILL;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
insert into t (id,a) values (139,23);#ERROR: 1054 - Unknown column 'id' in 'field list'
CREATE TABLE t_general (a int, b text) TABLESPACE `S_DEF` engine=RocksDB;#NOERROR
DROP VIEW v1;#ERROR: 4092 - Unknown VIEW: 'test.v1'
explain select * FROM t1 ,t1 where t0.key1 = 5 and (t1.key1 = t0.key1 or t1.key8 = t0.key1);#ERROR: 1066 - Not unique table/alias: 't1'
show global variables like "RocksDB_max_file_classes";#NOERROR
CREATE TABLE t1 (id int unsigned auto_increment, name char(50), primary key (id)) engine=RocksDB;#ERROR: 1050 - Table 't1' already exists
insert into mt1 values (639,'aaaaaaaaaaaaaaaaaaaa');#ERROR: 1146 - Table 'test.mt1' doesn't exist
UPDATE t1 SET c = 10 LIMIT 5;#ERROR: 1054 - Unknown column 'c' in 'field list'
DROP TABLE IF EXISTS RocksDB_stats_drop_locked;#NOERROR
SET @@max_sort_length=default;#NOERROR
SET @@character_set_client= 'cp1256';#NOERROR
SET @@global.early-plugin-load="keyring_vault=keyring_vault.so";#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '-plugin-load="keyring_vault=keyring_vault.so"' at line 1
CREATE TABLE t1( a NATIONAL VARCHAR(8194) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=InnoDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=InnoDB' at line 1
insert into t2 values (61549);#ERROR: 1136 - Column count doesn't match value count at row 1
create TABLE t1(a2 int);#ERROR: 1050 - Table 't1' already exists
SELECT SUBSTRING('1', 1, 1);#NOERROR
drop function if exists bug13825_0;#NOERROR
create TABLE t1 (a int not null auto_increment, b char(16) not null, primary key (a)) engine=RocksDB;#ERROR: 1050 - Table 't1' already exists
SELECT LOCATE(']', '1 = 1');#NOERROR
CREATE TABLE t1(a INT, b INT, KEY inx (a), UNIQUE KEY uinx (b)) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
INSERT INTO `£‘£±;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '`\00A3\0634\00A3±' at line 1
CREATE TABLE `ÇsÇS` (`ÇbÇP` char(5)) DEFAULT CHARSET = sjis engine = TokuDB;#NOERROR
CALL mtr.add_suppression("Failed to set NUMA RocksDB policy of buffer pool page frames to MPOL_INTERLEAVE \\(error: Function not implemented\\)");#ERROR: 1305 - PROCEDURE mtr.add_suppression does not exist
SET @@GLOBAL.keyring_vault_timeout = ' ';#ERROR: 1193 - Unknown system variable 'keyring_vault_timeout'
SET @inserted_value = REPEAT('z', 255);#NOERROR
SELECT SUBSTRING_INDEX('default,', ',', 1);#NOERROR
SELECT INET6_NTOA(INET6_ATON('::1.2.3.00'));#NOERROR
INSERT INTO t1 VALUES(23028);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t1(a LINESTRING NOT NULL, b GEOMETRY NOT NULL, SPATIAL KEY(a), SPATIAL KEY(b)) ENGINE=MEMORY;#ERROR: 1050 - Table 't1' already exists
alter TABLE t1 add primary key (i);#ERROR: 1072 - Key column 'i' doesn't exist in table
CREATE TABLE t1(c1 DECIMAL NULL, c2 CHAR(25) NOT NULL, c3 TINYINT(4) NULL, c4 CHAR(15) NOT NULL PRIMARY KEY, c5 DECIMAL NOT NULL UNIQUE KEY,c6 NUMERIC(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 't1' already exists
SESSION # SET @global_character_set_server = @@global.character_set_server;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'SESSION # SET @global_character_set_server = @@global.character_set_server' at line 1
select @@global.auto_generate_certs;#ERROR: 1193 - Unknown system variable 'auto_generate_certs'
SELECT COUNT(*) FROM t1 ;#NOERROR
CREATE TABLE t1 ( col_time_1_not_null_key time(1) NOT NULL, pk timestamp NOT NULL DEFAULT '0000-00-00 00:00:00', col_datetime_3_not_null_key datetime(3) NOT NULL, col_time_2_key time(2) DEFAULT NULL, PRIMARY KEY (pk), KEY col_time_1_not_null_key (col_time_1_not_null_key), KEY col_datetime_3_not_null_key (col_datetime_3_not_null_key), KEY col_time_2_key (col_time_2_key) ) ENGINE=InnoDB DEFAULT CHARSET=latin1 /*!50100 PARTITION BY KEY (pk)PARTITIONS 2 */;#ERROR: 1050 - Table 't1' already exists
CREATE DATABASE test2;#NOERROR
set global RocksDB_status_output=0;#ERROR: 1193 - Unknown system variable 'RocksDB_status_output'
INSERT INTO t1 VALUES (1,1,'1A3240'), (1,2,'4W2365');#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO ti VALUES (1394250026,16095,'XjhiTmAt9LMgBCy8sANvSifXgKBTMhAXivX5WFnu2XZ1','h','KN','DCM','A','WY',1);#ERROR: 1062 - Duplicate entry '1' for key 'PRIMARY'
select password('abc');#NOERROR
drop table City;#ERROR: 1051 - Unknown table 'test.City'
SELECT * FROM t3 WHERE c2 < '9999-12-31' ORDER BY c1,c2 LIMIT 2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
select C.a, c.a FROM t1  c, t1 C;#ERROR: 1054 - Unknown column 'C.a' in 'field list'
insert into t2 values (58906);#ERROR: 1136 - Column count doesn't match value count at row 1
set session myisam_mmap_size=1;#ERROR: 1238 - Variable 'myisam_mmap_size' is a read only variable
create table t1 (f text) engine=innodb;#ERROR: 1050 - Table 't1' already exists
DELETE FROM t1;#NOERROR
CREATE USER user1@localhost IDENTIFIED WITH 'RocksDB_native_password' AS 'auth_string';#ERROR: 1524 - Plugin 'RocksDB_native_password' is not loaded
CREATE PROCEDURE p1(f1 decimal (0)) BEGIN set f1 = (f1 / 2);#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
SET @@SESSION log_queries_not_using_indexes= TRUE;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'log_queries_not_using_indexes= TRUE' at line 1
SELECT QUOTE(REPLACE('[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 8193)] = 1', CONCAT('[', 'SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 8193)', ']'), '1'));#NOERROR
INSERT INTO t VALUES (1622757766822494550,-21816,'UZclHkB9XMvLdI8a8ByaqJr3xRErIUdgsw1LgIadXx9dBdQESEybHxwJd1yC9y7C2w6','5eGWZ4y9p2orBxUGkLifGf2u0Tmse0LJRftrSCSZs9JxzlpGpn7q8tlwKnKy2','VDTim3TO','4dYSGenMFMNK5t0bqvbGG3XGoqW23uDdXYKc','3','I',8);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE ti (a MEDIUMINT, b MEDIUMINT, c BINARY(5), d VARCHAR(2), e VARBINARY(3), f VARBINARY(65), g MEDIUMBLOB NOT NULL, h BLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
SET @@session.optimizer_search_depth = 65550;#NOERROR
CREATE TABLE ti (a INT, b TINYINT NOT NULL, c BINARY(84) NOT NULL, d VARCHAR(86) NOT NULL, e VARBINARY(42) NOT NULL, f VARBINARY(50), g BLOB, h LONGBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=MEMORY;#ERROR: 1050 - Table 'ti' already exists
insert into t1 values (3977,3977,3977,3977);#ERROR: 1136 - Column count doesn't match value count at row 1
create table t1(a bit(2) not null);#ERROR: 1050 - Table 't1' already exists
SESSION # SET @start_global_value = @@global.long_query_time;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'SESSION # SET @start_global_value = @@global.long_query_time' at line 1
set f6 = (f6 * 2);#ERROR: 1193 - Unknown system variable 'f6'
CREATE TABLE t1 (a int, INDEX idx(a));#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t2 (I INTEGER);#ERROR: 1050 - Table 't2' already exists
CREATE TABLE `é±é±é±`(`é∂é∂é∂` char(1)) DEFAULT CHARSET = ujis engine=RocksDB;#NOERROR
insert into t values (4482,0);#NOERROR
select wss_type FROM t1  where wss_type ='102935229216544104';#ERROR: 1054 - Unknown column 'wss_type' in 'field list'
INSERT INTO ti VALUES (11623795584367032768,3088758,'ry9poaN93SyRhVa2ZA','gjCYpASwwz0c2MLnOFOM6DkdBNOUHtzoQggUrjPxN4IqtbuyC7Lh23l2iT2GDmpajUGyafDWaMJ2a6jsURoJU9Li14VsLnEXq5IIwGblgGivzo6eq38sRvS4E58Kbl0R54uwD7wqa9wCMYGwoY77b9aBgxaWRCkBtadPTVjV7U2Qoy3P','AbO2iVwpkeG8H4XuNBbwMDFlju7M7U6uYTDn5','oxYEbJ6xXVaiL8FtqyfjI6dwxXJ','W2','7',6);#ERROR: 1062 - Duplicate entry '6' for key 'PRIMARY'
CREATE TABLE m3(c1 INT NULL, c2 BINARY(25) NOT NULL, c3 INTEGER(4) NULL, c4 BINARY(15) NOT NULL PRIMARY KEY, c5 INT NOT NULL UNIQUE KEY,c6 DEC(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 'm3' already exists
CREATE TABLE `£‘£∑` (`£√£±` char(12), INDEX(`£√£±`)) DEFAULT CHARSET = ujis engine = RocksDB;#NOERROR
EXPLAIN EXTENDED SELECT 'abcd√Å√Ç√É√Ñ√Ö', _latin1'abcd√Å√Ç√É√Ñ√Ö', _utf8'abcd√Å√Ç√É√Ñ√Ö' AS u;#NOERROR
update t1 set name='U+305A HIRAGANA LETTER ZU' where ujis=0xA4BA;#ERROR: 1054 - Unknown column 'ujis' in 'where clause'
SELECT COUNT(c1) AS value FROM t1 WHERE c1 IS NOT NULL;#NOERROR
replace into s values (1, 1000000000,9733);#ERROR: 1146 - Table 'test.s' doesn't exist
select 1E-500 = 0;#NOERROR
CREATE TABLE t1( a VARBINARY(257) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = DYNAMIC ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = DYNAMIC ENGINE=RocksDB' at line 1
SELECT CURTIME(7);#ERROR: 1426 - Too big precision 7 specified for 'curtime'. Maximum is 6
SELECT SUBSTRING('11', 2);#NOERROR
CREATE TABLE t1 ( cid bigint(20) unsigned NOT NULL auto_increment, cap varchar(255) NOT NULL default '', PRIMARY KEY (cid), UNIQUE KEY (cid, cap) ) ENGINE=RocksDBcluster;#ERROR: 1050 - Table 't1' already exists
SET @param1='%%';#NOERROR
create TABLE t1 select 1 as 'a';#ERROR: 1050 - Table 't1' already exists
replace into s values (1, 1000000000,5354);#ERROR: 1146 - Table 'test.s' doesn't exist
set global net_write_timeout =@my_net_write_timeout;#ERROR: 1232 - Incorrect argument type to variable 'net_write_timeout'
SELECT * FROM t2 WHERE c2 IS NULL ORDER BY c2,c1;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
create TABLE t1 (id int primary key, data int);#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t1 ( col_int_key int, pk int, col_int int, key(col_int_key), primary key (pk) ) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
SELECT routine_type, routine_name FROM information_schema.routines WHERE routine_schema='test';#NOERROR
SELECT t1.c1,t4.c1 FROM t1  LEFT OUTER JOIN t1 ON t1.c1 = t4.c1;#ERROR: 1066 - Not unique table/alias: 't1'
CREATE FUNCTION sf1 (p1 BIGINT) RETURNS BIGINT LANGUAGE SQL DETERMINISTIC MODIFIES SQL DATA COMMENT 'comment' BEGIN DECLARE ret INT DEFAULT 0;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
SELECT SUBSTRING('11', 1, 1);#NOERROR
set @i=1;#NOERROR
CREATE TABLE `t` ( `a` INT GENERATED ALWAYS AS (1) VIRTUAL, `b` INT GENERATED ALWAYS AS (1) VIRTUAL, `c` INT GENERATED ALWAYS AS (1) VIRTUAL, `d` INT GENERATED ALWAYS AS (1) VIRTUAL, `e2` POINT GENERATED ALWAYS AS (1) STORED NOT NULL, `d2` INT GENERATED ALWAYS AS (1) VIRTUAL, `e` int ) ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'NOT NULL, `d2` INT GENERATED ALWAYS AS (1) VIRTUAL, `e` int ) ENGINE=RocksDB' at line 1
SELECT * FROM t1  WHERE c1 <> 0 ORDER BY c1,c6 DESC;#ERROR: 2013 - Lost connection to MySQL server during query
CREATE TABLE t1(c1 BIT NOT NULL);#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1(b) VALUES ('bbb');#ERROR: 2006 - MySQL server has gone away
SELECT SLEEP(0.01);#ERROR: 2006 - MySQL server has gone away
EXPLAIN SELECT 1 FROM (SELECT COUNT(DISTINCT c1) FROM t1  WHERE c2 IN (1, 1) AND c3 = 2 GROUP BY c2) x;#ERROR: 2006 - MySQL server has gone away
SELECT SUBSTRING('1', 2);#ERROR: 2006 - MySQL server has gone away
CREATE TABLESPACE test/s_bad ADD DATAFILE 's_bad.ibd';#ERROR: 2006 - MySQL server has gone away
CREATE TABLE ti (a INT UNSIGNED, b BIGINT, c CHAR(45), d VARBINARY(20) NOT NULL, e VARBINARY(85), f VARBINARY(64) NOT NULL, g BLOB, h LONGBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=TokuDB;#ERROR: 2006 - MySQL server has gone away
INSERT INTO t212 VALUES('a');#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1(g) SELECT ST_GeomFromWKB(ST_AsBinary(g)) FROM t1 ORDER BY pk;#ERROR: 2006 - MySQL server has gone away
INSERT INTO t VALUES (13645267,244,'KtTNb9x0xdzVMmHtGtgEXBFrjDIHkbw1KdYv236pI','J2PWGhL6RYtBRUJeroy4xhDABWvmeRNEJy3AGiPPRVxo2iwCjwKRuf9Szr9o9W1alseKwRg6mzbkFYSRm','CcGuSoc3O3fshzih5XwAmRMyqocf1HYqT7UpVys2rM3EWRM0h5WO','etAm6n1yeV0ZlE8Cmel','S','C',1);#ERROR: 2006 - MySQL server has gone away
SELECT 1798 MOD 5000;#ERROR: 2006 - MySQL server has gone away
LOCK TABLE t1 READ;#ERROR: 2006 - MySQL server has gone away
insert into mt1 values (642,'aaaaaaaaaaaaaaaaaaaa');#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1 VALUES ('2000-01-01 10:11:12.000000');#ERROR: 2006 - MySQL server has gone away
SELECT SUBSTRING('11', 2);#ERROR: 2006 - MySQL server has gone away
SELECT 41 - LENGTH(SUBSTRING_INDEX(SUBSTR('[SELECT COUNT(*) FROM t1 WHERE a IS NULL] = 1', 1, 41), '[', -1));#ERROR: 2006 - MySQL server has gone away
SELECT 6881 MOD 5000;#ERROR: 2006 - MySQL server has gone away
call mtr.add_suppression("\\[Error\\] Function 'keyring_vault' already exists");#ERROR: 2006 - MySQL server has gone away
create TABLE t1 ( a int primary key, b int, c int, key xb (b), key xc (c), foreign key fkb (b) references t1 (a), foreign key fkc (c) references t1 (a) ) ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
DROP TABLE t1;#ERROR: 2006 - MySQL server has gone away
SELECT SUBSTRING('11', 2);#ERROR: 2006 - MySQL server has gone away
select cast('18446744073709551616' as signed);#ERROR: 2006 - MySQL server has gone away
SET TIMESTAMP=UNIX_TIMESTAMP('2013-01-31 09:00:00');#ERROR: 2006 - MySQL server has gone away
SELECT MBROVERLAPS(fid,ST_GEOMFROMTEXT(@star_top)) FROM gis_geometrycollection,gis_geometrycollection_2 WHERE fid=103 and fid2=103;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1(c1 DOUBLE NOT NULL PRIMARY KEY);#ERROR: 2006 - MySQL server has gone away
ALTER TABLE t1 ADD FULLTEXT INDEX idx (a,b);#ERROR: 2006 - MySQL server has gone away
CREATE TABLE ti (a BIGINT UNSIGNED, b INT NOT NULL, c BINARY(89) NOT NULL, d VARCHAR(80) NOT NULL, e VARCHAR(22), f VARCHAR(25), g MEDIUMBLOB, h MEDIUMBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
SELECT * FROM information_schema.global_variables WHERE variable_name='innodb_stats_method';#ERROR: 2006 - MySQL server has gone away
insert into t1 values (303,'303');#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1  VALUES('a');#ERROR: 2006 - MySQL server has gone away
create TABLE t1(c1 int primary key, c2 char(10), ref_t1 int) engine=RocksDB;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1(c1 INT, c2 char(20)) ENGINE = InnoDB;#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1 VALUES(11677);#ERROR: 2006 - MySQL server has gone away
PREPARE stmt FROM SELECT t1field FROM t1  WHERE t1field IN (SELECT * FROM t1 );#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1 (`bit_key` bit, `bit` bit, key (`bit_key` )) ENGINE=MyISAM;#ERROR: 2006 - MySQL server has gone away
CREATE TEMPORARY TABLE t1 (c1 INT, INDEX(c1)) ENGINE=MyISAM;#ERROR: 2006 - MySQL server has gone away
SHOW COLUMNS IN `RocksDB_SYS_TABLESTATS` FROM `information_schema`;#ERROR: 2006 - MySQL server has gone away
INSERT IGNORE INTO t1 VALUES(@inserted_value);#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1 (a int(11), b text, FULLTEXT KEY (b)) ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
create TABLE t1 (b int primary key) engine = RocksDB;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE ti (a TINYINT UNSIGNED NOT NULL, b BIGINT, c CHAR(7) NOT NULL, d VARCHAR(11) NOT NULL, e VARBINARY(87), f VARBINARY(51) NOT NULL, g TINYBLOB NOT NULL, h BLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=myisam;#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1  VALUES(0xA9D3);#ERROR: 2006 - MySQL server has gone away
SET @@global.thread_pool_min_threads = @start_global_value;#ERROR: 2006 - MySQL server has gone away
INSERT INTO t VALUES (2587053,235250888,'vFbAsKBV1S20CSlVsSIwQ3eDfKH71mRhmwRHnyJug8JVQ','KS8xKQUS2pUag0zUqLjs','AXxoAqE98PmopSNYe7o8FpmfKQhgI3GK985uSus35sig5QxoZrdXKr5hAE1hIyd3UlIFAeA6Eon','IB8ULA','M','yz',6);#ERROR: 2006 - MySQL server has gone away
SELECT * FROM t1  WHERE c1 > '1000-00-01' ORDER BY c1,c2;#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1 VALUES (null), ('foo'), ('bar'), (null);#ERROR: 2006 - MySQL server has gone away
insert INTO t1  values ("3","30","300","3000","30000","300000");#ERROR: 2006 - MySQL server has gone away
create TABLE t1 (a int not null, b int not null auto_increment, primary key(a,b)) ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE user_stopword(value varchar(30)) ENGINE = MEMORY DEFAULT CHARACTER SET latin1 COLLATE latin1_general_ci;#ERROR: 2006 - MySQL server has gone away
alter event event_35981 disable;#ERROR: 2006 - MySQL server has gone away
std.........UTCt;#ERROR: 2006 - MySQL server has gone away
set @my_max_RocksDB_table_size =@@global.max_RocksDB_table_size;#ERROR: 2006 - MySQL server has gone away
select keyring_key_remove('Rob_AES_512');#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1  VALUES (1, 1.789);#ERROR: 2006 - MySQL server has gone away
DELETE FROM t1;#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1 (b) VALUES ('aaa');#ERROR: 2006 - MySQL server has gone away
INSERT INTO 2byte_collation SELECT 0,b,c+50,z+50 FROM 2byte_collation;#ERROR: 2006 - MySQL server has gone away
INSERT IGNORE INTO t1 VALUES(@inserted_value);#ERROR: 2006 - MySQL server has gone away
SELECT t1.c1,t2.c1 FROM t1  INNER JOIN t1 ON t1.c1 = t2.c1 WHERE t1.c1 >= 5;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE ti (a MEDIUMINT, b BIGINT UNSIGNED, c BINARY(18), d VARCHAR(21) NOT NULL, e VARCHAR(23) NOT NULL, f VARCHAR(77) NOT NULL, g TINYBLOB, h MEDIUMBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=myisam;#ERROR: 2006 - MySQL server has gone away
DELETE FROM t1;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE RocksDB.t1 (id int NOT NULL auto_increment, code char(20) NOT NULL, fileguts blob NOT NULL, creation_date datetime, entered_time datetime default '2004-04-04 04:04:04', PRIMARY KEY(id), index(code), index(fileguts(10))) DEFAULT CHARSET=latin1;#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1 VALUES(8315);#ERROR: 2006 - MySQL server has gone away
SELECT * FROM t1  WHERE c3 = '2007-05-24 09:15:28';#ERROR: 2006 - MySQL server has gone away
CREATE PROCEDURE sp1() BEGIN declare x tinytext; SELECT f1 into x from t2 limit 1; END;#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1  (t1_id, t3_id, amount) VALUES (1, 1, 100.00), (2, 2, 200.00), (4, 4, 400.00);#ERROR: 2006 - MySQL server has gone away
CREATE TABLE db1.t2 (b INT, KEY(b)) engine=RocksDB;#ERROR: 2006 - MySQL server has gone away
SELECT GROUP_CONCAT(a1.name ORDER BY a1.name) AS overlaps FROM t1  a1 WHERE Overlaps(a1.square, @horiz1) GROUP BY a1.name;#ERROR: 2006 - MySQL server has gone away
SELECT '1 = 1';#ERROR: 2006 - MySQL server has gone away
ALTER TABLE t CHANGE COLUMN c c CHAR(19) NOT NULL;#ERROR: 2006 - MySQL server has gone away
SHOW GRANTS FOR bug23721446_u2@'%';#ERROR: 2006 - MySQL server has gone away
ALTER TABLE t1 MODIFY c1 MEDIUMINT NOT NULL;#ERROR: 2006 - MySQL server has gone away
SELECT SUBSTRING('1', 1, 1);#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t (a INT UNSIGNED, b MEDIUMINT UNSIGNED NOT NULL, c CHAR(51) NOT NULL, d VARCHAR(19), e VARCHAR(41), f VARBINARY(92), g BLOB NOT NULL, h TINYBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), CLUSTERING KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
update t1 set name='U+044F CYRILLIC SMALL LETTER YA' where ujis=0xA7F1;#ERROR: 2006 - MySQL server has gone away
DROP FUNCTION f3;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1( a INT AUTO_INCREMENT PRIMARY KEY, b CHAR(1), c INT, INDEX(b)) ENGINE=RocksDB STATS_PERSISTENT=0;#ERROR: 2006 - MySQL server has gone away
insert INTO t1  values (0), (1);#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1  VALUES ('00:00:00.000000');#ERROR: 2006 - MySQL server has gone away
delete from t1 where a > 0 order by a desc limit 1;#ERROR: 2006 - MySQL server has gone away
select "do something";#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1( a NATIONAL VARCHAR(65532) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = DYNAMIC ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
declare exit handler for table set @var2 = 1;#ERROR: 2006 - MySQL server has gone away
UPDATE t1 SET intcol1 = 614980131,intcol2 = 2027947119,charcol1 = '4xMpYR8w8o74pPs3Q0ZXgAAzy9rtNaOJOe0wx8k5pj9e01ZJu7iQ9kPzu8k9i0K6fLvcTXiA7jg7dEIXD0xMlMDXMygwy03dLq6jDglKNQK0YeNlfKzGaCnwARl1Jg',charcol2 = 'WZWc8bGtwYB8OjeoS98JPbOCNaX8RjoyGAaGmj1aFDifwKRHMScn300IRXRuEFkMIJW4uYe9dCgZO0imKBaF3QZMx0H481IQCpM6Ds7q4gFSgq701Z74zgRoZckZT3',charcol3 = 'rakDYp5gX1KeLsSSkT1rQsNlhwDPTaKC84PhtMDGNPvdHN51lzk3r7oOwtqHRAWc7n9s2E9Hf4uoRshCrPFaOvzKope8r0kynlrpzs7Ww1INlzScOb3gN213jfBQfn' WHERE id =  '2bed485f-a4da-11e6-85d3-902b3462';#ERROR: 2006 - MySQL server has gone away
set f8 = f8 + 51;#ERROR: 2006 - MySQL server has gone away
select max(7) from t1i;#ERROR: 2006 - MySQL server has gone away
SELECT MBREQUALS(ST_GEOMFROMTEXT(@star_collection_elems),ST_GEOMFROMTEXT('POLYGON((0 0,15 25,35 0,0 0,0 0))'));#ERROR: 2006 - MySQL server has gone away
select hex(soundex(_utf8 0xE99885E8A788E99A8FE697B6E69BB4E696B0E79A84E696B0E997BB));#ERROR: 2006 - MySQL server has gone away
grant SELECT on RocksDBtest1.t1 to "zedjzlcsjhd"@127.0.0.1;#ERROR: 2006 - MySQL server has gone away
ALTER TABLE `ÈæñÈæñÈæñ` ADD INDEX (`‰∏Ñ‰∏Ñ‰∏Ñ`);#ERROR: 2006 - MySQL server has gone away
UPDATE mysql.engine_cost SET cost_value = 2 * cost_value;#ERROR: 2006 - MySQL server has gone away
insert into t2 values (10301+0.33);#ERROR: 2006 - MySQL server has gone away
EXPLAIN SELECT * FROM t1  WHERE NULL>t1.col3;#ERROR: 2006 - MySQL server has gone away
SELECT IF('SELECT COUNT(*) FROM t1 WHERE a = ""' REGEXP '^[a-zA-Z_][a-zA-Z_0-9]*:', LOCATE(':', 'SELECT COUNT(*) FROM t1 WHERE a = ""'), 0);#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1  VALUES ('a', 'a', 0x61, 0x61, 'a', 'a', 'a', 'a', 'a', 'a', 'a', 'a');#ERROR: 2006 - MySQL server has gone away
SELECT 1;#ERROR: 2006 - MySQL server has gone away
SELECT ST_CONTAINS(ST_INTERSECTION(ST_GEOMFROMTEXT(@star),ST_GEOMFROMTEXT(@star_elem_vertical)), ST_SYMDIFFERENCE(ST_GEOMFROMTEXT(@star),ST_GEOMFROMTEXT(@star_elem_vertical)));#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1( a VARBINARY(8193) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = COMPRESSED ENGINE=InnoDB;#ERROR: 2006 - MySQL server has gone away
drop table if exists t1;#ERROR: 2006 - MySQL server has gone away
CREATE TEMPORARY TABLE temp_1 ( i INT ) ENGINE = RocksDB;#ERROR: 2006 - MySQL server has gone away
SELECT local.transaction_prealloc_size;#ERROR: 2006 - MySQL server has gone away
UPDATE `table1_innodb` SET `col_document`.k1.SetNotExists(DOCUMENT(' [ null , false , [ false ] ] ')) WHERE `col_document_not_null` CONTAINS DOCUMENT('  { "k1": "value"  } ') ORDER BY `col_document` , `col_document_not_null`.1.1;#ERROR: 2006 - MySQL server has gone away
INSERT INTO t VALUES (1281992579,207,'tcwYHj0CqpqexeMtnm2psfkiQUCtMCkGrhNPu','14cNHZWSulnLhFTzpOohryM7TpVLXqn6bafpwh6p8zbwf9C7XSRZpm1hE5S1cZdFe5osEluotlgkDTAwF5d04M3jWDiSPWrHl8NHbClUPP3B0KEt30wYhJegVYsEL02plxpilhpJHx1a1L3e6F2mqLTBsObjaKFfbyBkIeA1KEGsKmFeGHOfg3NFszKtQ9oEKudHIhskoiixQkdMs4nbdoGJqns5HqakSZSzfp5qW0DzUWO5cQY2DT3','nseXn1VjFTGaCzEWbtGinT84USGNwWF7YSplGoUmJCUme7tXmLbicXijT','uY8pnzk9s25XeDXHjiGzbyf0KuNJlITvJ1jBobJjxPpHvlozwef1Zv6oOVFV5V','Z','n',13);#ERROR: 2006 - MySQL server has gone away
CREATE TABLESPACE s_empty1 ADD DATAFILE 's_empty1.ibd' ENGINE RocksDB ENCRYPTION='Y';#ERROR: 2006 - MySQL server has gone away
DROP TABLE `Ôº¥Ôºña`;#ERROR: 2006 - MySQL server has gone away
create table t1(f1 varchar(1000))engine=MEMORY;#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1  VALUES(1);#ERROR: 2006 - MySQL server has gone away
SELECT CONCAT('SELECT COUNT(*) FROM t1 WHERE a = ""', 'ZZENDZZ') REGEXP '[a-zA-Z_][a-zA-Z0-9_]* *, *[0-9][0-9]* *ZZENDZZ';#ERROR: 2006 - MySQL server has gone away
create event e_26 on schedule at '2017-01-01 00:00:00' disable do set @a = 5;#ERROR: 2006 - MySQL server has gone away
SELECT INSERT('abc', 6, 3, '1234');#ERROR: 2006 - MySQL server has gone away
SELECT 'SELECT COUNT(*) FROM t1 WHERE g = LEFT(@long_value, 255)';#ERROR: 2006 - MySQL server has gone away
DESC t4;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE ti (a MEDIUMINT NOT NULL, b INT UNSIGNED NOT NULL, c CHAR(87), d VARCHAR(60), e VARBINARY(22), f VARCHAR(90), g TINYBLOB NOT NULL, h TINYBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
SELECT doc = doc FROM t2;#ERROR: 2006 - MySQL server has gone away
set ggg= repeat("G", 64);#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t (a MEDIUMINT UNSIGNED, b SMALLINT UNSIGNED NOT NULL, c BINARY(59), d VARCHAR(74) NOT NULL, e VARBINARY(51), f VARBINARY(71), g LONGBLOB NOT NULL, h BLOB, id BIGINT NOT NULL, KEY(b), CLUSTERING KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
SHOW VARIABLES like 'log_slave_updates';#ERROR: 2006 - MySQL server has gone away
insert into t1 values (5186,'5186');#ERROR: 2006 - MySQL server has gone away
select count(*) from t1, t2 where t1.i = t2.i;#ERROR: 2006 - MySQL server has gone away
SET @@global.RocksDB_purge_batch_size = "Y";#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1(c1 INTEGER NULL UNIQUE);#ERROR: 2006 - MySQL server has gone away
SELECT @@SESSION.sql_safe_updates;#ERROR: 2006 - MySQL server has gone away
insert into t2 values (528+0.755555555);#ERROR: 2006 - MySQL server has gone away
SELECT * FROM t2 WHERE c1 > 16777215 ORDER BY c1,c6 DESC LIMIT 2;#ERROR: 2006 - MySQL server has gone away
SELECT * FROM t1  PARTITION (foo);#ERROR: 2006 - MySQL server has gone away
SELECT * FROM t1 WHERE c1='d' LIMIT 100;#ERROR: 2006 - MySQL server has gone away
SHOW VARIABLES LIKE 'innodb_compressed_columns_threshold';#ERROR: 2006 - MySQL server has gone away
INSERT INTO `t5` ( `bit` ) VALUES ( 0 );#ERROR: 2006 - MySQL server has gone away
select ExtractValue('<a>a</a>', '/a[@x=$y0123456789_0123456789_0123456789_0123456789]');#ERROR: 2006 - MySQL server has gone away
select (PLUGIN_LIBRARY LIKE 'ha_innodb_plugin%') as `TRUE` from information_schema.plugins where PLUGIN_NAME='InnoDB';#ERROR: 2006 - MySQL server has gone away
INSERT INTO ti VALUES (164656216,92,'NOzvr5ipLYCTVPyx7wBFeYh7PEBMoEvo5e','RBm4PLQqvqBwJ','YKVY1wt1Hmo','VFlRAirmCwFCny9XLCJKI2nIa4LJyhRbthnMZikZBTRxgijc','C','jq',1);#ERROR: 2006 - MySQL server has gone away
insert into at(c,_jsn) select concat('_jsn: ',c), (select j from t where c='stringint') from t where c='stringint';#ERROR: 2006 - MySQL server has gone away
SELECT * FROM t3 WHERE c2 IN (NULL,-123) ORDER BY c2,c7 LIMIT 2;#ERROR: 2006 - MySQL server has gone away
select MIN(c) FROM t1 ;#ERROR: 2006 - MySQL server has gone away
SELECT hex(c1),hex(c2) FROM t1  WHERE c1 = '16' ORDER BY c1 DESC;#ERROR: 2006 - MySQL server has gone away
DROP TABLE t1;#ERROR: 2006 - MySQL server has gone away
INSERT INTO tt_2(ddl_case) VALUES(0);#ERROR: 2006 - MySQL server has gone away
call bug6129();#ERROR: 2006 - MySQL server has gone away
INSERT INTO ti VALUES (-9032141086987400471,913829983,'Jcy','APs7CKAE4dmsZEwWJWf233WpXuxTfUXGoFgGRbMmuXLIwAaEh39YhaCs2xWdtsZkoIJmF9rnMt6P2M1Pdr7SYpMjOkITFftPUzGQyXkw6B5SD5RfJijKdg3p21v6SL5rIXsivBXVsCciTkygND5NOd4BGmCaLw5FQy4pegmiTfwzMacB61i26HsoyVwx9lZwYkTNt5qHZiMOcrkTxKXbp7J','hFHzo6Lo8KkawxZjIPXSMNFZAw0yQBta1ASdjbAAEXYktnUj','QrmkDpZn1YMFYAbdOTt2IGsUxFZR9Efk1AHFJlG','iP7','c',5);#ERROR: 2006 - MySQL server has gone away
SELECT SUBSTRING('11', 1, 1);#ERROR: 2006 - MySQL server has gone away
SELECT SUBSTRING('default,', LENGTH('default') + 2);#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1 VALUES ('1970-01-01 00:00:02.999900');#ERROR: 2006 - MySQL server has gone away
SELECT 0 + (1010101010101010101010101010101010101010101010101010101010101010<<0);#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1 (a INT, INDEX(a)) ENGINE=InnoDB;#ERROR: 2006 - MySQL server has gone away
select * from t1 where a is null or b is null;#ERROR: 2006 - MySQL server has gone away
INSERT INTO t2 VALUES (588,160301,29,'helmsman','sash','commercially','');#ERROR: 2006 - MySQL server has gone away
SET @@global.reset_seconds_behind_master = 1;#ERROR: 2006 - MySQL server has gone away
SELECT b FROM t1  JOIN (t2 JOIN t1 USING (a) JOIN t1 USING (a) JOIN t1 USING (a)) USING (a);#ERROR: 2006 - MySQL server has gone away
CALL sp13();#ERROR: 2006 - MySQL server has gone away
INSTALL PLUGIN keyring_vault SONAME 'keyring_vault.so';#ERROR: 2006 - MySQL server has gone away
select soundex(_utf8 0xD091D092D093);#ERROR: 2006 - MySQL server has gone away
CREATE TABLE ti (a BIGINT UNSIGNED NOT NULL, b INT UNSIGNED NOT NULL, c BINARY(70) NOT NULL, d VARCHAR(77), e VARBINARY(87) NOT NULL, f VARBINARY(91) NOT NULL, g BLOB, h BLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
SET @@global.sync_frm = ON;#ERROR: 2006 - MySQL server has gone away
SELECT i, SUM(d1) AS a, SUM(d2) AS b FROM t1  GROUP BY i HAVING a <> b;#ERROR: 2006 - MySQL server has gone away
SELECT AVG(c1) AS no_results FROM t1  WHERE c1 = 2;#ERROR: 2006 - MySQL server has gone away
SELECT QUOTE(REPLACE('[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 257)] = 1', CONCAT('[', 'SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 257)', ']'), '1'));#ERROR: 2006 - MySQL server has gone away
SELECT QUOTE(REPLACE('1 = 1', '<1>', '1'));#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t (a INT NOT NULL, b SMALLINT UNSIGNED, c BINARY(93) NOT NULL, d VARBINARY(7) NOT NULL, e VARCHAR(28) NOT NULL, f VARCHAR(70), g MEDIUMBLOB, h LONGBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), CLUSTERING KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
create table t1 (t_column int);#ERROR: 2006 - MySQL server has gone away
SELECT LOCATE(']', '1 = 1');#ERROR: 2006 - MySQL server has gone away
SELECT REPEAT('.', 2 - 1);#ERROR: 2006 - MySQL server has gone away
select group_concat(c1 order by binary c1 separator '') FROM t1  group by c1 collate utf32_slovenian_ci;#ERROR: 2006 - MySQL server has gone away
SET @@GLOBAL.histogram_step_size_delete_command='32';#ERROR: 2006 - MySQL server has gone away
insert into t1 values (7262,7262,7262,7262);#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1  VALUES (5952,1232607,37,'appendixes','willed','Adlerian','');#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1  VALUES(1);#ERROR: 2006 - MySQL server has gone away
create TABLE t1 (column_format int storage disk column_format FIXED, storage int storage disk column_format FIXED) TABLESPACE ts1 ENGINE=MEMORY;#ERROR: 2006 - MySQL server has gone away
create table t1 (this int unsigned);#ERROR: 2006 - MySQL server has gone away
SELECT a FROM t1  WHERE a < ANY (SELECT a FROM t1  WHERE b = 2 UNION SELECT a FROM t1  WHERE b = 2);#ERROR: 2006 - MySQL server has gone away
SELECT SHA2( x'd564b9e358cbee4766391e8679cc41c7f1f64f3713765ea151860a40cb', 224 ) = '9b93bf21dd9b587b1e7dccf3cc5df4f193a744a1a082ebf8df65c577'  as NIST_SHA224_test_vector;#ERROR: 2006 - MySQL server has gone away
create table t1_base(i int) engine=TokuDB;#ERROR: 2006 - MySQL server has gone away
DROP TABLE old;#ERROR: 2006 - MySQL server has gone away
insert into mt3(id3,t) values (35,'1');#ERROR: 2006 - MySQL server has gone away
select @@session.performance_schema_max_prepared_statements_instances;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE ti (a SMALLINT NOT NULL, b SMALLINT UNSIGNED NOT NULL, c BINARY(98), d VARCHAR(7) NOT NULL, e VARCHAR(23), f VARBINARY(31) NOT NULL, g LONGBLOB NOT NULL, h LONGBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1  VALUES(33);#ERROR: 2006 - MySQL server has gone away
GRANT ALL PRIVILEGES ON FUNCTION db3.f1 TO grantee WITH GRANT OPTION;#ERROR: 2006 - MySQL server has gone away
SELECT SUBSTRING('1', 1, 1);#ERROR: 2006 - MySQL server has gone away
echo [ status of semi-sync on master should be OFF ];#ERROR: 2006 - MySQL server has gone away
SET @@global.table_definition_cache = FALSE;#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1 VALUES ('10:10:10.6');#ERROR: 2006 - MySQL server has gone away
SELECT * FROM t1  WHERE c2 = -9223372036854775808 ORDER BY c2,c7 DESC LIMIT 2;#ERROR: 2006 - MySQL server has gone away
INSERT INTO ti VALUES (17632437778399790242,-4044974,'x9V14O','ESi07y74nwbNk5DvGNvLS73EXsoZoDURJlcVADsU2gDOLpsSIIv9iFrCIcAArSX3BEUVNJVcnVM6LoLJ2ZQmGn4a6JhxlGtZduTJKJLToaxPCe7tLOEFSTiH7o6Kq8WDwhAugtlwF7uzse4u1Jl1Jnk11SCZaD6EjPXrHzC8WBVkhz9XVeYJSN3jf3ur9P85Y9NF4icWAoCs0lvqNjq','uKR0pysBr791cvW66q1bFAuD7ehyLits7PmWRegzK2P82ElcuQbfXvFfCCaFQzrlvgE2fIk','QHSYtMauVZ3WLRDoeskJI1UIN2DfWpUulAj49jUoeJAWd8tGOzg1tlsxgA96WSnz6mU2RfOuzkac8NU73rv1CzGCftV7WQoW0oxUBHHbaY706zGhBhjFYRLfzqOKfUTO1fAE1cgLK8tspbp7Xg1mi69bCEcQWm5y0IECioXK8cgrs9siC8mn2amQwKfl6ACLkP5IgpgBpnFiE4H9xLWdp1vhKXFRhLxZL9P8XVdWK0xxI1LHHoDolzwn','Cbo','Ub',15);#ERROR: 2006 - MySQL server has gone away
CREATE TABLE ti (a INT NOT NULL, b SMALLINT UNSIGNED NOT NULL, c BINARY(45) NOT NULL, d VARBINARY(69) NOT NULL, e VARCHAR(45) NOT NULL, f VARBINARY(36), g LONGBLOB, h BLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
set global RocksDB_monitor_enable="%%%%%%%%%%%%%%%%%%%%%%%%%%%";#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1 VALUES ('2001-01-01 10:10:10.97');#ERROR: 2006 - MySQL server has gone away
drop function f;#ERROR: 2006 - MySQL server has gone away
INSERT INTO RocksDBtest.transtable (id) VALUES (433);#ERROR: 2006 - MySQL server has gone away
SELECT 'SELECT COUNT(*) FROM t1 WHERE a = CAST(@inserted_value AS JSON)';#ERROR: 2006 - MySQL server has gone away
select count(*)-8 FROM t1  use index (dt) where dt <= '2001-01-01 10:11:11';#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1 (a int not null primary key) PARTITION BY KEY(a) (PARTITION p0 ENGINE=RocksDB, PARTITION p1 ENGINE=RocksDB);#ERROR: 2006 - MySQL server has gone away
SELECT * from t1 where id=1;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1(a INT,b INT,KEY (b)) engine=rocksdb PARTITION BY HASH(a) PARTITIONS 2;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE ti (a INT NOT NULL, b INT, c CHAR(84), d VARCHAR(64) NOT NULL, e VARBINARY(45), f VARBINARY(20) NOT NULL, g TINYBLOB NOT NULL, h MEDIUMBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=InnoDB;#ERROR: 2006 - MySQL server has gone away
INSERT INTO ti VALUES (17783808918339516206,3794128184821702497,'Sw30X','0QyTccdB8Bdp4fgsp605H6oJWDTCG6MGGoYxmr4v9xGI9gi5XBrNZrcRfwz7UsbB2AtguNyj9L0PO8ziXF94E5e8iHHDJW9yXyzrnfr8J0Wy53mSYSuT5Y6nJyytyK4Ixb4vaio32mvRbQ9LJhfJ84liTiV4GAy1YyCricbpvdlPT67a0FSOjqSV6ivBMB','AsnCouylN4KozuwWMjxCbfaERevmKt3wshMQopOdlpsbNPBKcrfifikPYNyqOdV40mdSC3Ngva','fRZPWFvPx4HnLkeWVPxYybN1AS3yZlKxeToLvNhjuh2jjbxxAx8ybl7zik2EEI6tossAJJqjxICp8elhQWSqA8VltLeLgXkkL5dVzGSBctHWBdi4Yy53hGGrK7Dn5tZOOnCGQa2tAC0QJP0yOXcaXrX0biLuXUTbqjYfK5xEbQGr8CCH3fQAKjYkyF3EQl2GBell0HQK8OSu','g0','voI',15);#ERROR: 2006 - MySQL server has gone away
create TABLE t1 (a int, index `PRIMARY` (a));#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1( a VARBINARY(32767) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=InnoDB;#ERROR: 2006 - MySQL server has gone away
SELECT DISTINCT t3.b FROM t3,t2,t1 WHERE t3.a=t1.b AND t1.a=t2.a;#ERROR: 2006 - MySQL server has gone away
show status like "performance_schema_socket_instances_lost";#ERROR: 2006 - MySQL server has gone away
CREATE TABLE bug21114_child( pk int not null, fk_col1 int not null, fk_col2 int not null, fk_col3 int not null, fk_col4 int not null, CONSTRAINT fk_fct FOREIGN KEY (fk_col1, fk_col2) REFERENCES ltrim(col1, col2), CONSTRAINT fk_fct_space FOREIGN KEY (fk_col3, fk_col4) REFERENCES ltrim (col1, col2) ) ENGINE InnoDb;#ERROR: 2006 - MySQL server has gone away
insert into t2 values (53878);#ERROR: 2006 - MySQL server has gone away
SHOW SLAVE STATUS;#ERROR: 2006 - MySQL server has gone away
insert into t1_old values (1, repeat('Initial X=1',1000), 1);#ERROR: 2006 - MySQL server has gone away
CREATE TABLE `£‘£∑` (`£√£±` char(20)) DEFAULT CHARSET = ujis engine = MEMORY;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1 (c1 MEDIUMINT NULL, c2 CHAR(5)) PARTITION BY KEY(c1) PARTITIONS 4;#ERROR: 2006 - MySQL server has gone away
create table mysqltest.v3 (b int);#ERROR: 2006 - MySQL server has gone away
if (!$is_temporary) --let $diff_tables= master:t1,slave:t1 --source include/diff_tables.inc let binlog_start= query_get_value(SHOW MASTER STATUS, Position, 1);#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t (c1 int NOT NULL AUTO_INCREMENT, c2 int, c3 blob, primary key(c1,c2));#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t985 (c1 INTEGER);#ERROR: 2006 - MySQL server has gone away
INSERT INTO t VALUES (1653323447,22661,'xox48kce2','eVjDFC0EiuRVcyJwfA1DHv8m7d','9v','843VlC4G2aipvtqTMuM0CyrnLxil1utoR9Q5YzZgK0gpetAeTGYPBEIfz817FIe1sHRInNzFRVDaBhppsmbL1QA3S1HouFTxzzK4DFPaKSny3rvvZfhWj','UXI','4',14);#ERROR: 2006 - MySQL server has gone away
create table db5.t2(a int);#ERROR: 2006 - MySQL server has gone away
INSERT INTO t1  VALUES (1147,088005,00,'lemons','crushers','masked','');#ERROR: 2006 - MySQL server has gone away
INSERT INTO t VALUES (4570340454358649846,205,'DAIpSK1N','Wqt','PBHCBqTbBQqXki3gg','15PpB3xXCW','Y','3',11);#ERROR: 2006 - MySQL server has gone away
CREATE TABLE ti (a BIGINT NOT NULL, b SMALLINT NOT NULL, c CHAR(12), d VARBINARY(63), e VARBINARY(10) NOT NULL, f VARCHAR(79), g MEDIUMBLOB NOT NULL, h TINYBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
SELECT SUBSTRING('0', 2);#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1(a INT) engine=RocksDB;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1(days set('1','2','3','4','5','6','7'));#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1(c_key1 INT, c_key3 INT, c_not_key INT, c_key2 INT, PRIMARY KEY(c_key1, c_key2, c_key3));#ERROR: 2006 - MySQL server has gone away
delete FROM t1  where i8=1;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE ti (a INT UNSIGNED, b BIGINT UNSIGNED NOT NULL, c BINARY(68) NOT NULL, d VARBINARY(7), e VARBINARY(75) NOT NULL, f VARBINARY(60), g MEDIUMBLOB NOT NULL, h MEDIUMBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=myisam;#ERROR: 2006 - MySQL server has gone away
update t1 set name='U+9F02 <CJK>' where ujis=0x8FEDA3;#ERROR: 2006 - MySQL server has gone away
DROP DATABASE IF EXISTS test_wl5522;#ERROR: 2006 - MySQL server has gone away
SELECT REPEAT('.', 2 - 1);#ERROR: 2006 - MySQL server has gone away
update s set a=20000+2473 where a=2473;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t11(c1 INT, c2 char(20)) ENCRYPTION="Y" ENGINE = InnoDB;#ERROR: 2006 - MySQL server has gone away
SELECT `ÇbÇP`, SUBSTRING(`ÇbÇP`,3) FROM `ÇsÇU`;#ERROR: 2006 - MySQL server has gone away
INSERT INTO ti VALUES (188099814769692987,-8986055046730782119,'AVwxa5jYQagpscw7swR0zaFGMfKDoAvIpP8m9csGZ7','V76OybQPOqA61GVc2nTNQD232TZIPizOb06re24lka3sRpsAfh8ul308F5gxWB1kzsRO1XLB','MEQUjBxAhZjQvQ0f0Z4E6WUpYZFwwFyNkkkr05MchD','BGwj3sHZWqxMYuybrBfLwzGGxswMj4qwItWvcjPznEG3ZVtO6Fc2AfuoAHQqA','p','O',3);#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1(c1 TINYINT UNSIGNED ZEROFILL NOT NULL);#ERROR: 2006 - MySQL server has gone away
CREATE TABLE bug41904 (id INT PRIMARY KEY, uniquecol CHAR(15)) ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
call proc_25411_a();#ERROR: 2006 - MySQL server has gone away
ALTER PROCEDURE p1(#DET# NO SQL SQL SECURITY DEFINER COMMENT 'comment';#ERROR: 2006 - MySQL server has gone away
CREATE TABLE ti (a MEDIUMINT UNSIGNED, b MEDIUMINT, c BINARY(34) NOT NULL, d VARBINARY(5), e VARCHAR(56), f VARCHAR(12) NOT NULL, g BLOB NOT NULL, h BLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
delete from t1 where b=4;#ERROR: 2006 - MySQL server has gone away
SET @@global.connect_timeout = -1024;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1 ( a INT AUTO_INCREMENT, b VARCHAR(10), INDEX (a), INDEX (b) ) ENGINE=RocksDB;#ERROR: 2006 - MySQL server has gone away
SELECT * FROM t1  WHERE c1 BETWEEN '1000-00-01 00:00:00' AND '9999-12-31 23:59:59' ORDER BY c1,c2 DESC LIMIT 2;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1 (a VARCHAR(10) CHARACTER SET utf8 COLLATE utf8_general_RocksDB500_ci);#ERROR: 2006 - MySQL server has gone away
select distinct i FROM t1  order by mod(i,2),i;#ERROR: 2006 - MySQL server has gone away
SELECT @table_name,@table_schema;#ERROR: 2006 - MySQL server has gone away
create database sp_db3;#ERROR: 2006 - MySQL server has gone away
alter TABLE t1 change column b b int NOT NULL storage memory;#ERROR: 2006 - MySQL server has gone away
create table bug19145a (e enum('a','b','c') default 'b' , s set('x', 'y', 'z') default 'y' ) engine=RocksDB;#ERROR: 2006 - MySQL server has gone away
DELETE FROM t_archive;#ERROR: 2006 - MySQL server has gone away
UPDATE t1, t1 SET t1.b = (t2.b+4) WHERE t1.a = t2.a;#ERROR: 2006 - MySQL server has gone away
SET GLOBAL RocksDB_analyze_throttle = 'foobar';#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1(c1 INT, c2 char(20)) ENCRYPTION="Y" ENGINE = TokuDB;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE variant (a int primary key, b timestamp NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=INNODB;#ERROR: 2006 - MySQL server has gone away
SELECT * FROM t1  WHERE c1 <> 0 ORDER BY c1,c6 DESC; ;
SELECT * FROM t1  WHERE c1 <> 0 ORDER BY c1,c6 DESC; ;
SELECT * FROM t1  WHERE c1 <> 0 ORDER BY c1,c6 DESC; ;
SELECT * FROM t1  WHERE c1 <> 0 ORDER BY c1,c6 DESC; ;

SELECT * FROM t1  WHERE c1 <> 0 ORDER BY c1,c6 DESC; ;

SELECT * FROM t1  WHERE c1 <> 0 ORDER BY c1,c6 DESC; ;

SELECT 1;
SELECT 1;
SELECT 1;
SELECT SLEEP(3);
SELECT SLEEP(3);
SELECT SLEEP(3);
DROP DATABASE transforms;
CREATE DATABASE transforms;
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE t1(c1 DOUBLE PRECISION NULL, c2 VARBINARY(25) NOT NULL, c3 BIGINT(4) NULL, c4 VARBINARY(15) NOT NULL PRIMARY KEY, c5 DOUBLE PRECISION NOT NULL UNIQUE KEY,c6 FIXED(10,8) NOT NULL DEFAULT 3.141592);#NOERROR
CREATE TABLE t1 pk1 MEDIUMINT NOT NULL AUTO_INCREMENT PRIMARY KEY, c2 VARCHAR(200) NOT NULL, c3 INT NOT NULL, c4 BIT NOT NULL)ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'MEDIUMINT NOT NULL AUTO_INCREMENT PRIMARY KEY, c2 VARCHAR(200) NOT NULL, c3 I...' at line 1
SELECT SUBSTRING('1', 2);#NOERROR
INSERT INTO t VALUES (115,16898,'L','oImEmveCe7RK3sZZdH4czWsuqV','LBdLmXZSZzVXk2hkm8HDahnFK4WhnKn97rP5dRAwCzi','U2L','c','X',8);#ERROR: 1146 - Table 'test.t' doesn't exist
SELECT * FROM t1  ORDER BY s1;#ERROR: 1054 - Unknown column 's1' in 'order clause'
SELECT * FROM t1  WHERE c1 > -255 ORDER BY c1,c6 DESC;#NOERROR
INSERT INTO RocksDB.t1 VALUES (b'011');#ERROR: 1146 - Table 'RocksDB.t1' doesn't exist
show global variables like 'performance_schema_max_file_handles';#NOERROR
CREATE TABLE t2(c1 DECIMAL(10,5) NOT NULL, c2 DECIMAL, c3 INT);#NOERROR
SELECT SHA2( x'21ebecb914', 224 ) = '78f4a71c21c694499ce1c7866611b14ace70d905012c356323c7c713'  as NIST_SHA224_test_vector;#NOERROR
CREATE TABLE t1( a NATIONAL VARCHAR(8194) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=RocksDB' at line 1
CREATE TABLE `BB` ( `pk` int(11) NOT NULL AUTO_INCREMENT, `time_key` time DEFAULT NULL, `varchar_key` varchar(1) DEFAULT NULL, `varchar_nokey` varchar(1) DEFAULT NULL, PRIMARY KEY (`pk`), KEY `time_key` (`time_key`), KEY `varchar_key` (`varchar_key`) ) ENGINE=RocksDB AUTO_INCREMENT=11 DEFAULT CHARSET=latin1;#NOERROR
insert into t values (7688,0);#ERROR: 1146 - Table 'test.t' doesn't exist
SELECT SUBSTRING('1', 1, 1);#NOERROR
ALTER INSTANCE ROTATE INNODB MASTER KEY;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'INSTANCE ROTATE INNODB MASTER KEY' at line 1
SELECT REPEAT('.', 2 - 1);#NOERROR
insert into s values (5588,repeat('a', 2000)),(5588,repeat('b', 2000)),(5588,repeat('c', 2000)),(5588,repeat('d', 2000)),(5588,repeat('e', 2000)),(5588,repeat('f', 2000)),(5588,repeat('g', 2000)),(5588,repeat('h', 2000)),(5588,repeat('i', 2000)),(5588,repeat('j', 2000));#ERROR: 1146 - Table 'test.s' doesn't exist
INSERT INTO t2 VALUES (600,168502,29,'corny','flurried','sloping','A');#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT * FROM t1 ;#NOERROR
SELECT * FROM t1  WHERE c1 >= '0000-00-00' AND c1 < '9999-12-31 23:59:59' AND c2 = '2010-10-00 00:00:00' ORDER BY c1;#NOERROR
DROP VIEW  IF EXISTS test.t1_view;#NOERROR
CREATE TABLE t1 ( quantity decimal(60,0));#ERROR: 1050 - Table 't1' already exists
SET @@session.RocksDB_support_xa = -0.6;#ERROR: 1193 - Unknown system variable 'RocksDB_support_xa'
SELECT SUBSTRING_INDEX('default,', ',', 1);#NOERROR
insert INTO t1  set ujis=0x0B, name='U+000B VERTICAL TABULATION';#ERROR: 1054 - Unknown column 'ujis' in 'field list'
CREATE TABLE t1(c1 INT PRIMARY KEY, c2 char(20)) ENCRYPTION="Y" ENGINE = TokuDB;#ERROR: 1050 - Table 't1' already exists
insert into at(c,_tim) select concat('_tim: ',c), json_extract(j, '$') from t where c='opaque_RocksDB_type_mediumblob';#ERROR: 1146 - Table 'test.at' doesn't exist
INSERT INTO t1 PARTITION(`p10-99`,subp3) VALUES (1, "subp3"), (10, "p10-99");#ERROR: 1747 - PARTITION () clause on non partitioned table
CREATE TABLE worklog5743_key4 ( col_1_text TEXT (4000) , col_2_text TEXT (4000) , PRIMARY KEY (col_1_text(1964)) ) ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=4, engine = RocksDB;#NOERROR
DROP TABLE t1;#NOERROR
DROP PROCEDURE bug29770;#ERROR: 1305 - PROCEDURE test.bug29770 does not exist
insert into A values(1), (2);#ERROR: 1146 - Table 'test.A' doesn't exist
CREATE TABLE t1_will_crash ( a VARCHAR(255), b INT, c LONGTEXT, PRIMARY KEY (a, b)) ENGINE=RocksDB PARTITION BY HASH (b) PARTITIONS 7;#NOERROR
CALL add_child(1,1);#ERROR: 1305 - PROCEDURE test.add_child does not exist
CREATE TABLE ti (a INT UNSIGNED NOT NULL, b MEDIUMINT UNSIGNED NOT NULL, c BINARY(95) NOT NULL, d VARCHAR(82) NOT NULL, e VARCHAR(96) NOT NULL, f VARBINARY(71) NOT NULL, g LONGBLOB NOT NULL, h MEDIUMBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=myisam;#NOERROR
ALTER TABLE t3 MODIFY c1 FLOAT NULL;#ERROR: 1146 - Table 'test.t3' doesn't exist
CREATE TABLE t1 ( pk int(11) NOT NULL ) ENGINE=MEMORY DEFAULT CHARSET=latin1;#NOERROR
CREATE PROCEDURE p1() BEGIN declare i int default 10;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
CREATE TABLE ti (a TINYINT UNSIGNED, b BIGINT, c CHAR(97), d VARCHAR(69), e VARBINARY(7) NOT NULL, f VARCHAR(12) NOT NULL, g BLOB, h TINYBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
SELECT t1.c1,t3.c1 FROM t1  NATURAL RIGHT OUTER JOIN t1 WHERE t1.c1 <> 5;#ERROR: 1066 - Not unique table/alias: 't1'
SELECT SUBSTRING('default,default,', LENGTH('default') + 2);#NOERROR
CREATE TABLE t (a SMALLINT NOT NULL, b MEDIUMINT, c BINARY(3), d VARBINARY(52), e VARCHAR(81), f VARCHAR(99) NOT NULL, g LONGBLOB NOT NULL, h LONGBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), CLUSTERING KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'e), PRIMARY KEY(id)) ENGINE=RocksDB' at line 1
set global aria_group_commit=1;#NOERROR
DROP TABLE t1;#NOERROR
insert into t2 values (11787+0.33);#ERROR: 1136 - Column count doesn't match value count at row 1
insert into t2 values (1,2);#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO t1  VALUES (1),(7);#ERROR: 1146 - Table 'test.t1' doesn't exist
CREATE TABLE t1( a VARBINARY(8190) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = DYNAMIC ENGINE=InnoDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = DYNAMIC ENGINE=InnoDB' at line 1
SELECT LOCATE(']', '1 = 1');#NOERROR
execute stmt1 using @parm1;#ERROR: 1243 - Unknown prepared statement handler (stmt1) given to EXECUTE
select t1.auto,t2.auto from t1,t2 where t1.auto=t2.auto and not (t1.string<=>t2.string and t1.tiny<=>t2.tiny and t1.short<=>t2.short and t1.medium<=>t2.medium and t1.long_int<=>t2.long_int and t1.longlong<=>t2.longlong and t1.real_float<=>t2.real_float and t1.real_double<=>t2.real_double and t1.utiny<=>t2.utiny and t1.ushort<=>t2.ushort and t1.umedium<=>t2.umedium and t1.ulong<=>t2.ulong and t1.ulonglong<=>t2.ulonglong and t1.time_stamp<=>t2.time_stamp and t1.date_field<=>t2.date_field and t1.time_field<=>t2.time_field and t1.date_time<=>t2.date_time and t1.new_blob_col<=>t2.new_blob_col and t1.tinyblob_col<=>t2.tinyblob_col and t1.mediumblob_col<=>t2.mediumblob_col and t1.options<=>t2.options and t1.flags<=>t2.flags and t1.new_field<=>t2.new_field);#ERROR: 1146 - Table 'test.t1' doesn't exist
SELECT SHA2( x'9eabfcd3603337df3dcd119d6287a9bc8bb94d650ef29bcf1b32e60d425adc2a35e06577d0c7ce2456cf260efee9e8d8aeeddb3d068f37', 256 ) = '83eeed2dfeb8d2604ab5ec1ac9b5dcab8cc2222518468bc5c24c16ce72e70687'  as NIST_SHA256_test_vector;#NOERROR
INSERT INTO t VALUES (528337183,-1106050294,'YbMPYVyy7DAYCVzrbfPaJpHh8C5ykg','UBTqqKFxkhRQe0F48Xy2OnM3Pz3oCqFD4iFfBuxAt4Bfrl','tsttDiC34LayUJQ44mcGbaFV','3E0AT2yZOt5eQAiOl1841ZSRvyzkTJE22S5mF3WoafrmQKBKM41EYvyqNk56PRugZf8dEQy6t43kNPfQhJEpFLPMMLoMqBezFOYW5vcgxTihCew5kh2mrC7iTaZy37Kl7VfwIvOh4L0s16iEM4G0aIluhTFurmQ9TTgKy5','1','u',6);#ERROR: 1146 - Table 'test.t' doesn't exist
SELECT COUNT(@@local.RocksDB_log_files_in_group);#ERROR: 1193 - Unknown system variable 'RocksDB_log_files_in_group'
DROP TABLE t1;#ERROR: 1051 - Unknown table 'test.t1'
set @@global.master_verify_checksum = 2;#ERROR: 1231 - Variable 'master_verify_checksum' can't be set to the value of '2'
root@127.0.0.1:$SLAVE_MYPORT/test/t1';#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'root@127.0.0.1:$SLAVE_MYPORT/test/t1'' at line 1
CREATE TEMPORARY TABLE t1 (c1 INT) ENGINE=MRG_RocksDB UNION=(t1,t2);#NOERROR
DROP TEMPORARY TABLE tmp_RocksDB_88;#ERROR: 1051 - Unknown table 'test.tmp_RocksDB_88'
INSERT INTO ti VALUES (12452951996966965202,-5887875395049130158,'Uf6YjJXIvdelpMpVWsCOJ92RPfdI','1zHEEYRCfHAaeQilfTyEMiqcvrpdgoQGjMp6B8ZN6m6GIK2vNkAc00ttvDdNI2HiZTKjWMCor2BN','sx7KihOBsQesN67k0iJQrWy4DmX9JMoFvg5mDeKNL6G','h1UId48XbpVs','A','G',13);#NOERROR
INSERT t1 VALUES (1),(2),(3);#NOERROR
INSERT INTO ti VALUES (-6049036833101064884,48933,'Q5w','wTQ8ZrJGP01RsfGwSa3RWjWG3AO0BqQMab','jyt89TBY3sOPvCLyHSyW8eEugtBU8ZH4bxbq2TGb0d0blYFM5pglcgB1xhJIFLP4snFjlN','Xg0K9McEKHXlOExQSlrhnGiloSWeIcKATDcFEwEs0NjpSLhn6160yQpwzz8v1OXJJTx3etF1S6C2ie0iUVflHRW5ApboGtfAJuMq334ebqsq1iwOETlbT5H5gjVvefmxXPLoxKJJ36H2Kliu9XmyJcvGVLIlAaaNNl5bgKV0UUiJTFP2hIJrMYrzDzjd26FV86oSQPOL0MoLCWEkr6QwEtXEbVWVxiTrnMn2la','4d','pQ',14);#NOERROR
SET @@session.sql_log_bin = 1;#NOERROR
CREATE TABLE `ÇsÇP` (`ÇbÇP` char(5), INDEX(`ÇbÇP`)) DEFAULT CHARSET = sjis engine = RocksDB;#NOERROR
CREATE TABLE `ÇsÇW` (`ÇbÇP` ENUM('Ç†','Ç¢','Ç§'), INDEX(`ÇbÇP`)) DEFAULT CHARSET = sjis engine = RocksDB;#NOERROR
select SUBSTRING_INDEX(_latin1'abcdabcdabcd' COLLATE latin1_bin,_latin1'd',2);#NOERROR
SELECT SUBSTRING('0', 2);#NOERROR
select friedrich from (select 1 as otto) as t1;#ERROR: 1054 - Unknown column 'friedrich' in 'field list'
set session innodb_adaptive_hash_index='OFF';#ERROR: 1229 - Variable 'innodb_adaptive_hash_index' is a GLOBAL variable and should be set with SET GLOBAL
CREATE TEMPORARY TABLE tti1 (a INT) ENGINE=MEMORY;#NOERROR
DROP TABLE IF EXISTS bug21825_A;#NOERROR
create TABLE t1 (a int not null auto_increment,b int, primary key (a)) engine=RocksDB auto_increment=3;#ERROR: 1050 - Table 't1' already exists
insert into t (id,a) values (3,92);#ERROR: 1146 - Table 'test.t' doesn't exist
INSERT INTO t1  SELECT * FROM t1 ;#NOERROR
RENAME TABLE t2 TO t1;#ERROR: 1146 - Table 'test.t2' doesn't exist
SELECT SUBSTRING_INDEX('default,default,', ',', 1);#NOERROR
CREATE TABLE t1(c1 INT, c2 char(20)) ENCRYPTION="Y" ENGINE=InnoDB;#ERROR: 1050 - Table 't1' already exists
INSERT INTO t1 values (1),(2),(3),(4),(5);#NOERROR
SELECT * FROM INFORMATION_SCHEMA.GLOBAL_VARIABLES WHERE VARIABLE_NAME='replicate_wild_ignore_table';#NOERROR
CREATE TABLE m3(c1 NUMERIC NULL, c2 VARCHAR(25) NOT NULL, c3 INT(4) NULL, c4 VARCHAR(15) NOT NULL PRIMARY KEY, c5 NUMERIC NOT NULL UNIQUE KEY,c6 NUMERIC(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 'm3' already exists
LOAD DATA LOCAL INFILE 'suite/engines/funcs/t/load_unique_error1.inc' REPLACE INTO TABLE t1 FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n';#ERROR: 2 - File 'suite/engines/funcs/t/load_unique_error1.inc' not found (Errcode: 2)
INSERT INTO t1 (subject) VALUES(0x616263F0909080646566);#ERROR: 1054 - Unknown column 'subject' in 'field list'
SELECT * FROM t4 WHERE c1 = 1 ORDER BY c1 LIMIT 2;#ERROR: 1146 - Table 'test.t4' doesn't exist
DROP PROCEDURE spexecute51;#ERROR: 1305 - PROCEDURE test.spexecute51 does not exist
SELECT pseudo FROM t8 WHERE pseudo=(SELECT pseudo FROM t8 WHERE pseudo LIKE '%joce%');#ERROR: 1146 - Table 'test.t8' doesn't exist
SELECT QUOTE(SUBSTRING('[SELECT COUNT(*) FROM t1 WHERE a IS NULL] = 1', 1 + 1, 41 - 1 - 1));#NOERROR
insert into t1 values (6962,6962,6962,6962);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT `ÇbÇP` FROM `ÇsÇXa` WHERE NOT EXISTS (SELECT `ÇbÇP` FROM `ÇsÇXb` WHERE `ÇsÇXa`.`ÇbÇP` = `ÇsÇXb`.`ÇbÇP`);#ERROR: 1146 - Table 'test.ÇsÇXa' doesn't exist
insert into t1 values(4635);#NOERROR
DROP TABLESPACE ts1 ENGINE=RocksDB;#NOERROR
CREATE TABLE t1( i INT) engine=INNODB;#ERROR: 1050 - Table 't1' already exists
INSERT INTO t1 VALUES('');#NOERROR
CREATE TABLE `ÔΩ±ÔΩ±ÔΩ±`(`ÔΩ∑ÔΩ∑ÔΩ∑` char(5)) DEFAULT CHARSET = utf8 engine=RocksDB;#NOERROR
SET @@global.large_pages= true;#ERROR: 1238 - Variable 'large_pages' is a read only variable
create table ti (k int, index using btree (k)) charset utf8mb4 engine=TokuDB;#ERROR: 1050 - Table 'ti' already exists
SELECT * FROM t2 WHERE c2 < '1983-09-05 13:28:00' ORDER BY c1,c2 DESC LIMIT 2;#ERROR: 1146 - Table 'test.t2' doesn't exist
DROP TABLE product;#ERROR: 1051 - Unknown table 'test.product'
CREATE TABLE table_bug30423 ( org_id int(11) default NULL, KEY(org_id) ) ENGINE=MEMORY DEFAULT CHARSET=latin1;#NOERROR
INSERT INTO t VALUES (-1252747820,4513693994075589190,'XeKnnAO48xsS9VsVJxRpw8qQa4HldZdA3laHCjPDiIdSrpvfZfDajkM2yLJANvSzowTmw4','iFOZ6ceAn9Fy8vxRmTh5eTrnGRx3Li3CGtFyzKRfnZr7fA2B4rM3VZ0LviQErTcaxtVm3Z3mNbmP6WRaIJ1','epHBePGniWSDZya7URhgPAbaOohT3Qzl6Wp2SQXR4Zhdc','WzQ9lO3Yd8ClOvVeLxPBMJ0JSDZcr281appgKxEVpgkKAUDAEMHBl64OF6O2Ea9pMzO','Un','urM',15);#ERROR: 1146 - Table 'test.t' doesn't exist
CREATE FUNCTION fn1(f1 numeric ) returns numeric return f1;#NOERROR
create TABLE t1 (a int unsigned, b int) partition by list (a) subpartition by hash (b) subpartitions 2 (partition p0 values in (0), partition p1 values in (1), partition pnull values in (null, 2), partition p3 values in (3));#ERROR: 1050 - Table 't1' already exists
INSERT INTO t VALUES (5810569,1167885442,'KdOSNFq284RTd8Jb1e','bRlzxEP','GTBZHes4J823z7r6jDNHDyYAFgZgel8daMuv4rYlvLImVS3J','B1X1DE','Y','3',0);#ERROR: 1146 - Table 'test.t' doesn't exist
replace INTO t1  values (1,1),(2,2);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT CONCAT('SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 65535)', 'ZZENDZZ') REGEXP '[a-zA-Z_][a-zA-Z0-9_]* *, *[0-9][0-9]* *ZZENDZZ';#NOERROR
SELECT * FROM myisam_innodb ORDER BY a;#ERROR: 1146 - Table 'test.myisam_innodb' doesn't exist
insert into t2 values (50818);#ERROR: 1146 - Table 'test.t2' doesn't exist
CREATE TABLE t1( a VARBINARY(128) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = REDUNDANT ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = REDUNDANT ENGINE=RocksDB' at line 1
ALTER TABLE t CHANGE COLUMN a a CHAR(100) NOT NULL;#ERROR: 1146 - Table 'test.t' doesn't exist
insert into s values (6554,0),(6554,1),(6554,2),(6554,3),(6554,4),(6554,5),(6554,6),(6554,7),(6554,8),(6554,9);#ERROR: 1146 - Table 'test.s' doesn't exist
SET @old_global=@@global.innodb_merge_sort_block_size;#ERROR: 1193 - Unknown system variable 'innodb_merge_sort_block_size'
DROP TABLE t1;#NOERROR
DROP TABLE t1,t2,t5,t12,t10;#ERROR: 1051 - Unknown table 'test.t2,test.t5,test.t12,test.t10'
create TABLE t1 (a enum ('a','b','c')) character set utf16;#NOERROR
create RocksDBtest@localhost identified by 'updatecruduser';#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'RocksDBtest@localhost identified by 'updatecruduser'' at line 1
DROP PROCEDURE bug15231_2a;#ERROR: 1305 - PROCEDURE test.bug15231_2a does not exist
SET TIME_ZONE="+03:00";#NOERROR
SELECT REPEAT('.', 1 - 1);#NOERROR
SET GLOBAL query_cache_type=DEMAND;#NOERROR
select 0 + b'1000000000000000';#NOERROR
SELECT SUBSTRING_INDEX('default,default,default,', ',', 1);#NOERROR
INSERT INTO too_deep_docs(x) SELECT CONCAT('{"a":', jarray, '}') FROM t;#ERROR: 1146 - Table 'test.too_deep_docs' doesn't exist
set ndb_join_pushdown = false;#ERROR: 1193 - Unknown system variable 'ndb_join_pushdown'
INSERT INTO t481 VALUES(1);#ERROR: 1146 - Table 'test.t481' doesn't exist
DROP TABLE t1;#ERROR: 1051 - Unknown table 'test.t1'
INSERT INTO t545 VALUES(1);#ERROR: 1146 - Table 'test.t545' doesn't exist
select * from information_schema.session_variables where variable_name='RocksDB_mmap_size';#NOERROR
PREPARE st1 FROM "INSERT INTO v1 (pk) VALUES (2)";#ERROR: 1146 - Table 'test.v1' doesn't exist
INSERT INTO t VALUES (2991573233,40159,'F4b6HKSz6AdXxx6WjyGPipziQ6fyPzJpTE6arkIQC1cuk','vfj52QAMUimFL8H32fXEEV3j63WVsF2DiBet8FFihce2Sh4LybNhQybLjCvX60yCYUY46zrxPi2PRfqL2NkRpos0OElWz2VMN58Vift9DFXI2And5eIKnCuFxrWml4KRHyFYdgOxiCqUd9ff','1sYVb','u9CsxW0CNabPmHaP0puaCn','4C','yh',15);#ERROR: 1146 - Table 'test.t' doesn't exist
create TABLE t1(i1 int not null auto_increment, a int, b int, primary key(i1)) engine=RocksDB;#NOERROR
create TABLE t1 (a int primary key, b int, key b_idx (b)) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
SELECT * FROM t1  WHERE c1 <> '838:59:59' ORDER BY c1,c2 DESC LIMIT 2;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
CREATE TABLE t1 (a6 VARCHAR(32));#ERROR: 1050 - Table 't1' already exists
insert t1 values ('933293329332933293329332933293329332933278987898789878987898789878987898789878');#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT SUBSTRING('11', 1, 1);#NOERROR
INSERT INTO tmyisam VALUES (132);#ERROR: 1146 - Table 'test.tmyisam' doesn't exist
INSERT INTO test.byrange_tbl VALUES (NULL, NOW(),  NAME_CONST('cur_user',_latin1'current_user@localhost' COLLATE 'latin1_swedish_ci'),  NAME_CONST('local_uuid',_latin1'36774b1c-6374-11df-a2ca-0ef7ac7a5f6c' COLLATE 'latin1_swedish_ci'),  NAME_CONST('ins_count',177) + 100,'Partitioned table! Going to test replication for MySQL');#ERROR: 1146 - Table 'test.byrange_tbl' doesn't exist
explain select * FROM t1  s00, t1 s01, t1 s02, t1 s03, t1 s04,t1 s05,t1 s06,t1 s07,t1 s08,t1 s09, t1 s10, t1 s11, t1 s12, t1 s13, t1 s14,t1 s15,t1 s16,t1 s17,t1 s18,t1 s19, t1 s20, t1 s21, t1 s22, t1 s23, t1 s24,t1 s25,t1 s26,t1 s27,t1 s28,t1 s29, t1 s30, t1 s31, t1 s32, t1 s33, t1 s34,t1 s35,t1 s36,t1 s37,t1 s38,t1 s39, t1 s40, t1 s41, t1 s42, t1 s43, t1 s44,t1 s45,t1 s46,t1 s47,t1 s48,t1 s49 where s00.a in ( select m00.a FROM t1  m00, t1 m01, t1 m02, t1 m03, t1 m04,t1 m05,t1 m06,t1 m07,t1 m08,t1 m09, t1 m10, t1 m11, t1 m12, t1 m13, t1 m14,t1 m15,t1 m16,t1 m17,t1 m18,t1 t1 );#NOERROR
SET @inserted_value = REPEAT('z', 8188);#NOERROR
select repeat('hello', -4294967295);#NOERROR
select 1/*!999992*/;#NOERROR
GRANT INSERT ON *.* TO CURRENT_USER() ;#NOERROR
DROP TABLE IF EXISTS db_datadict.t1;#NOERROR
show session variables like 'innodb_lru_scan_depth';#NOERROR
DROP FUNCTION IF EXISTS f1_two_inserts;#NOERROR
SET GLOBAL delay_key_write = ALL;#NOERROR
CREATE TEMPORARY TABLE t1 (c1 INT, c2 INT) ENGINE=MRG_MEMORY UNION=(t3,t4) INSERT_METHOD=LAST;#NOERROR
explain select * from t where "aa" <> x;#NOERROR
ALTER TABLE t1 CHANGE a id INT;#ERROR: 1283 - Column 'id' cannot be part of FULLTEXT index
CREATE TABLE t1(c1 SMALLINT NULL, c2 BINARY(25) NOT NULL, c3 TINYINT(4) NULL, c4 BINARY(15) NOT NULL PRIMARY KEY, c5 SMALLINT NOT NULL UNIQUE KEY,c6 DECIMAL(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 't1' already exists
INSERT INTO t1 VALUES (13,0),(8,1),(9,2),(6,3), (11,5),(11,6),(7,7),(7,8),(4,9),(6,10),(3,11),(11,12), (12,13),(7,14);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t1(c1 REAL NULL);#ERROR: 1050 - Table 't1' already exists
show databases like 't%';#NOERROR
SELECT ST_ASTEXT(ST_CONVEXHULL(NULL));#NOERROR
CREATE TABLE t2(c1 INT PRIMARY KEY, c2 char(20)) ENCRYPTION="Y" ENGINE = RocksDB;#ERROR: 1911 - Unknown option 'ENCRYPTION'
SET @@global.table_open_cache = FALSE;#NOERROR
ALTER TABLE t CHANGE COLUMN a b BINARY(139);#ERROR: 1054 - Unknown column 'a' in 't'
INSERT INTO t VALUES (11588466625448019355,-10316,'KSiC1F4IdN5nUhH1fNR2n4Shw','p20HiwtAK42QwrDyW2mmbmKoVxlX','qT9km9djrB5l8xpPZckruGFsPL3JqjUxpWUL3adedhUubfy2htYreC3w','gDtB6IgvMP5fC','i','A',11);#ERROR: 1136 - Column count doesn't match value count at row 1
create table t_dat select DISTINCT(_dat) FROM at;#ERROR: 1146 - Table 'test.at' doesn't exist
SET session query_cache_wlock_invalidate = 0;#NOERROR
update t1 set name='U+253C BOX DRAWINGS LIGHT VERTICAL AND HORIZONTAL' where ujis=0xA8AB;#ERROR: 1054 - Unknown column 'ujis' in 'where clause'
SELECT 'SELECT COUNT(*) FROM t1 WHERE a = ""';#NOERROR
INSERT INTO t1  VALUES(8, 'val8');#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE m3(c1 TIMESTAMP NULL, c2 VARCHAR(25) NOT NULL, c3 MEDIUMINT(4) NULL, c4 VARCHAR(15) NOT NULL PRIMARY KEY, c5 TIMESTAMP NOT NULL UNIQUE KEY,c6 FIXED(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 'm3' already exists
SELECT 38 - LENGTH(SUBSTRING_INDEX(SUBSTR('[SELECT COUNT(*) FROM t1 WHERE a = ""] = 1', 1, 38), '[', -1));#NOERROR
create definer=`test14256`@`%` view v1 as select 42;#NOERROR
show create function f5;#ERROR: 1305 - FUNCTION f5 does not exist
set global query_cache_size= 81920;#NOERROR
SELECT 38 - LENGTH(SUBSTRING_INDEX(SUBSTR('[SELECT COUNT(*) FROM t1 WHERE a = ""] = 1', 1, 38), '[', -1));#NOERROR
set net_read_timeout=100;#NOERROR
INSERT INTO ti VALUES (22902,2992917996,'BPHh4R7GkgjKWQtPXXPm9L4BMXcWZ6NozCdZLfOHSPoIqSR1qDa1fhPjPqquzx4RTbZDidRRI5','GaJCoXaYP8gY8Pu5BbynAC7','8e33e8dOlRTo','TmGsB5DbqW','2j','hg',11);#NOERROR
SELECT @@GLOBAL.INNODB_IO_CAPACITY;#NOERROR
INSERT INTO t1 VALUES (2,4,'6067169d','Y');#ERROR: 1136 - Column count doesn't match value count at row 1
set collation_server=9999998;#ERROR: 1273 - Unknown collation: '9999998'
SET @@session.pseudo_thread_id=100;#NOERROR
insert into t2 values (1891);#ERROR: 1146 - Table 'test.t2' doesn't exist
CREATE TABLE t1 (i int) ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=16;#ERROR: 1050 - Table 't1' already exists
SET @@auto_increment_increment = 10;#NOERROR
SET @@global.innodb_max_dirty_pages_pct = @pct_start_value;#ERROR: 1232 - Incorrect argument type to variable 'innodb_max_dirty_pages_pct'
DROP TABLE IF EXISTS `test2`;#NOERROR
SELECT 9223372036854775807 - -1;#NOERROR
SELECT SUBSTRING('11', 1, 1);#NOERROR
SELECT COUNT(@@GLOBAL.innodb_page_cleaners);#NOERROR
SELECT c1,ST_Astext(c4) FROM tab WHERE ST_Touches(tab.c4, @g1) ORDER BY c1;#ERROR: 1146 - Table 'test.tab' doesn't exist
CREATE TABLE t1 (c1 INT AUTO_INCREMENT, c2 INT, PRIMARY KEY(c1)) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
insert into t2 values (7764+0.75);#ERROR: 1146 - Table 'test.t2' doesn't exist
CREATE TABLE t1 (a SERIAL, c64 VARCHAR(64) UNIQUE) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
create table `#mysql50#t1-1` (a int) engine=RocksDB;#NOERROR
SELECT c1 FROM t1  WHERE c1 = SOME (SELECT c1 FROM t1 );#ERROR: 1054 - Unknown column 'c1' in 'field list'
CREATE TABLE ti (a MEDIUMINT UNSIGNED, b BIGINT NOT NULL, c CHAR(88) NOT NULL, d VARBINARY(40), e VARCHAR(89) NOT NULL, f VARCHAR(40) NOT NULL, g TINYBLOB NOT NULL, h TINYBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=TokuDB;#ERROR: 1050 - Table 'ti' already exists
CREATE TABLE innodb_InnoDB (a INT) ENGINE=InnoDB;#NOERROR
SET @@session.sql_mode = POSTGRESQL;#NOERROR
update t4 set a=2;#ERROR: 1146 - Table 'test.t4' doesn't exist
CREATE TABLE ti (a INT UNSIGNED NOT NULL, b SMALLINT UNSIGNED NOT NULL, c CHAR(27), d VARCHAR(74) NOT NULL, e VARBINARY(67), f VARCHAR(88) NOT NULL, g LONGBLOB, h LONGBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=myisam;#ERROR: 1050 - Table 'ti' already exists
CREATE TABLE t2 (a varchar(10));#NOERROR
set var1 = -9.22e+15;#ERROR: 1193 - Unknown system variable 'var1'
insert into t values (652,0);#NOERROR
prepare abc from "alter event xyz comment 'xyz'";#ERROR: 1054 - Unknown column 'alter event xyz comment 'xyz'' in 'field list'
SELECT `ÇbÇP`, SUBSTRING(`ÇbÇP`,3) FROM `ÇsÇV`;#NOERROR
INSERT INTO `table1_innodb` (`col_document_not_null`) VALUES (' [ true , [ "value" , "%" , true , "%" ] ] ');#ERROR: 1146 - Table 'test.table1_innodb' doesn't exist
INSERT INTO t312 VALUES('a');#ERROR: 1146 - Table 'test.t312' doesn't exist
UPDATE t1 set spatial_point=GeomFromText('POINT(230 9)') where c1 like 'y%';#ERROR: 1054 - Unknown column 'c1' in 'where clause'
INSERT INTO t1  VALUES(0xF4AD);#NOERROR
CREATE TEMPORARY TABLE `ÔΩ¥ÔΩ¥ÔΩ¥`(`ÔΩπÔΩπÔΩπ` char(1)) DEFAULT CHARSET = utf8 engine=RocksDB;#NOERROR
SELECT SHA2( x'b1f83a5ea85d72c9721d166b1e9c51d6cb0dd6fe6b2ac88fc728d883c4eaadf3e475882d0fa42808941ceb746b833755bded1892a5', 224 ) = '0a53a62f28cc4db2025dd9175e571912c1a8bd0b293d235f7a0c568a' as NIST_SHA224_test_vector;#NOERROR
ALTER TABLE t1 ADD COLUMN c INT GENERATED ALWAYS AS(a+b), ADD INDEX idx (c), ALGORITHM=INPLACE, LOCK=NONE;#ERROR: 1054 - Unknown column 'b' in 'GENERATED ALWAYS AS'
SET @old_max_heap_table_size = @@max_heap_table_size;#NOERROR
CREATE TABLE ti (a BIGINT UNSIGNED, b SMALLINT NOT NULL, c BINARY(30), d VARBINARY(23), e VARCHAR(2) NOT NULL, f VARCHAR(22) NOT NULL, g TINYBLOB NOT NULL, h BLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
SELECT * FROM t1  WHERE c1 <= 16777216 ORDER BY c1,c6 DESC LIMIT 2;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
SELECT a AS x, ROW(11, 12) = (SELECT MAX(x), 22), ROW(11, 12) IN (SELECT MAX(x), 22) FROM t1;#NOERROR
select concat('From JSON col ',c, ' as DECIMAL(5,2)'), cast(j as DECIMAL(5,2)) from t where c='opaque_mysql_type_year';#ERROR: 1054 - Unknown column 'c' in 'field list'
CREATE TABLE t1(a INT) ENGINE = RocksDB;#ERROR: 1050 - Table 't1' already exists
select count(*) from performance_schema.events_stages_summary_by_thread_by_event_name;#NOERROR
CREATE TABLE t1(b TEXT CHARSET LATIN1, FULLTEXT(b), PRIMARY KEY(b(10))) ENGINE=INNODB;#ERROR: 1050 - Table 't1' already exists
EXPLAIN PARTITIONS SELECT * FROM t1  WHERE a <= 1;#NOERROR
CREATE TABLE t2 (`bit_key` bit(4), `bit` bit, key (`bit_key` )) ENGINE=TokuDB;#ERROR: 1050 - Table 't2' already exists
SELECT IF('SELECT COUNT(*) FROM t1 WHERE a IS NULL' REGEXP '^[a-zA-Z_][a-zA-Z_0-9]*:', LOCATE(':', 'SELECT COUNT(*) FROM t1 WHERE a IS NULL'), 0);#NOERROR
SELECT SUBSTRING('1', 1, 1);#NOERROR
CREATE TABLE t1 (a DATETIME) PARTITION BY HASH (EXTRACT(DAY_HOUR FROM a));#ERROR: 1050 - Table 't1' already exists
UPDATE `table1_innodb` SET `col_document_not_null`.1.2.1.SetNotExists(`col_document`.2.1.2) WHERE `col_document_not_null` != DOCUMENT('  { "k1": false  } ');#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '.1.2.1.SetNotExists(`col_document`.2.1.2) WHERE `col_document_not_null` != DO...' at line 1
source extra/rpl_tests/rpl_innodb.test;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'source extra/rpl_tests/rpl_innodb.test' at line 1
INSERT INTO t1 VALUES(0xF4C6);#NOERROR
insert INTO t1 (b) values (10);#ERROR: 1054 - Unknown column 'b' in 'field list'
ALTER TABLE t1 ADD c2 TEXT  NULL FIRST;#NOERROR
select col1 from wl1612 where col1>4 and col2=1.0123456789;#ERROR: 1146 - Table 'test.wl1612' doesn't exist
CREATE TABLE t2(c1 INT PRIMARY KEY, c2 char(20)) ENCRYPTION="Y" ENGINE = MEMORY;#ERROR: 1050 - Table 't2' already exists
insert into t2 values (12234+0.75);#NOERROR
CREATE TABLE ti (a TINYINT UNSIGNED, b INT NOT NULL, c CHAR(93), d VARBINARY(13) NOT NULL, e VARBINARY(90) NOT NULL, f VARBINARY(67), g BLOB NOT NULL, h LONGBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=TokuDB;#ERROR: 1050 - Table 'ti' already exists
select IF(GET_JSON_WEIGHT(JSON_TYPE(CAST(a._mes as JSON)))=GET_JSON_WEIGHT(JSON_TYPE(CAST(b.col as JSON))),'2nd Level','1st Level') validation_stage, a._mes as side1, b.col as side2, JSON_TYPE(CAST(a._mes as JSON)) as side1_json_type, JSON_TYPE(CAST(b.col as JSON)) as side2_json_type, GET_JSON_WEIGHT(JSON_TYPE(CAST(a._mes as JSON))) as side1_json_weightage, GET_JSON_WEIGHT(JSON_TYPE(CAST(b.col as JSON))) as side2_json_weightage, a._mes <=> b.col as json_compare, GET_JSON_WEIGHT(JSON_TYPE(CAST(a._mes as JSON))) <=> GET_JSON_WEIGHT(JSON_TYPE(CAST(b.col as JSON))) as first_level_validation from t_mes a , jj b where a._mes is not NULL and b.col is not NULL and JSON_TYPE(CAST(a._mes as JSON))!='BLOB' and JSON_TYPE(CAST(b.col as JSON))!='BLOB' and ((a._mes <=> b.col) != ( GET_JSON_WEIGHT(JSON_TYPE(CAST(a._mes as JSON))) GET_JSON_WEIGHT(JSON_TYPE(CAST(b.col as JSON))) echo "Testcase for unsigned Medium Int";#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'JSON)))=GET_JSON_WEIGHT(JSON_TYPE(CAST(b.col as JSON))),'2nd Level','1st Leve...' at line 1
SET @@global.tx_read_only = TRUE;#NOERROR
SET @@session.lc_time_names=he_IL;#NOERROR
SELECT * FROM t1  WHERE c1 <=> 1 ORDER BY c1 DESC;#ERROR: 1054 - Unknown column 'c1' in 'where clause'
create TABLE t1 (id int primary key) engine = RocksDB key_block_size = 1;#ERROR: 1050 - Table 't1' already exists
INSERT INTO ti VALUES (-1014489605,86,'7Pk2KsrOtQZDqKhVHilzukvOKTQmUf','IzK0zBQzN7VHvCuIDG64Wrzhxf1kwIAKsWtlgn0hBFRveFBNiS3FEBLKIngKjT5gioWphHpgStvNsWZbAOqpcaBVhP4eCOgxfXsIZCpZQCDrsnCgclV1aJsGQx5xDnOInDGCUUs3YEdTfCt','D4LwS4yrVRfekutSMAbfO','crpRh9NKYghR','u','i',4);#NOERROR
CREATE TABLE `table0` ( `col0` tinyint(1) DEFAULT NULL, `col1` tinyint(1) DEFAULT NULL, `col2` tinyint(4) DEFAULT NULL, `col3` date DEFAULT NULL, `col4` time DEFAULT NULL, `col5` set('test1','test2','test3') DEFAULT NULL, `col6` time DEFAULT NULL, `col7` text, `col8` decimal(10,0) DEFAULT NULL, `col9` set('test1','test2','test3') DEFAULT NULL, `col10` float DEFAULT NULL, `col11` double DEFAULT NULL, `col12` enum('test1','test2','test3') DEFAULT NULL, `col13` tinyblob, `col14` year(4) DEFAULT NULL, `col15` set('test1','test2','test3') DEFAULT NULL, `col16` decimal(10,0) DEFAULT NULL, `col17` decimal(10,0) DEFAULT NULL, `col18` blob, `col19` datetime DEFAULT NULL, `col20` double DEFAULT NULL, `col21` decimal(10,0) DEFAULT NULL, `col22` datetime DEFAULT NULL, `col23` decimal(10,0) DEFAULT NULL, `col24` decimal(10,0) DEFAULT NULL, `col25` longtext, `col26` tinyblob, `col27` time DEFAULT NULL, `col28` tinyblob, `col29` enum('test1','test2','test3') DEFAULT NULL, `col30` smallint(6) DEFAULT NULL, `col31` double DEFAULT NULL, `col32` float DEFAULT NULL, `col33` char(175) DEFAULT NULL, `col34` tinytext, `col35` tinytext, `col36` tinyblob, `col37` tinyblob, `col38` tinytext, `col39` mediumblob, `col40` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, `col41` double DEFAULT NULL, `col42` smallint(6) DEFAULT NULL, `col43` longblob, `col44` varchar(80) DEFAULT NULL, `col45` mediumtext, `col46` decimal(10,0) DEFAULT NULL, `col47` bigint(20) DEFAULT NULL, `col48` date DEFAULT NULL, `col49` tinyblob, `col50` date DEFAULT NULL, `col51` tinyint(1) DEFAULT NULL, `col52` mediumint(9) DEFAULT NULL, `col53` float DEFAULT NULL, `col54` tinyblob, `col55` longtext, `col56` smallint(6) DEFAULT NULL, `col57` enum('test1','test2','test3') DEFAULT NULL, `col58` datetime DEFAULT NULL, `col59` mediumtext, `col60` varchar(232) DEFAULT NULL, `col61` decimal(10,0) DEFAULT NULL, `col62` year(4) DEFAULT NULL, `col63` smallint(6) DEFAULT NULL, `col64` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00', `col65` blob, `col66` longblob, `col67` int(11) DEFAULT NULL, `col68` longtext, `col69` enum('test1','test2','test3') DEFAULT NULL, `col70` int(11) DEFAULT NULL, `col71` time DEFAULT NULL, `col72` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00', `col73` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00', `col74` varchar(170) DEFAULT NULL, `col75` set('test1','test2','test3') DEFAULT NULL, `col76` tinyblob, `col77` bigint(20) DEFAULT NULL, `col78` decimal(10,0) DEFAULT NULL, `col79` datetime DEFAULT NULL, `col80` year(4) DEFAULT NULL, `col81` decimal(10,0) DEFAULT NULL, `col82` longblob, `col83` text, `col84` char(83) DEFAULT NULL, `col85` decimal(10,0) DEFAULT NULL, `col86` float DEFAULT NULL, `col87` int(11) DEFAULT NULL, `col88` varchar(145) DEFAULT NULL, `col89` date DEFAULT NULL, `col90` decimal(10,0) DEFAULT NULL, `col91` decimal(10,0) DEFAULT NULL, `col92` mediumblob, `col93` time DEFAULT NULL, KEY `idx0` (`col69`,`col90`,`col8`), KEY `idx1` (`col60`), KEY `idx2` (`col60`,`col70`,`col74`), KEY `idx3` (`col22`,`col32`,`col72`,`col30`), KEY `idx4` (`col29`), KEY `idx5` (`col19`,`col45`(143)), KEY `idx6` (`col46`,`col48`,`col5`,`col39`(118)), KEY `idx7` (`col48`,`col61`), KEY `idx8` (`col93`), KEY `idx9` (`col31`), KEY `idx10` (`col30`,`col21`), KEY `idx11` (`col67`), KEY `idx12` (`col44`,`col6`,`col8`,`col38`(226)), KEY `idx13` (`col71`,`col41`,`col15`,`col49`(88)), KEY `idx14` (`col78`), KEY `idx15` (`col63`,`col67`,`col64`), KEY `idx16` (`col17`,`col86`), KEY `idx17` (`col77`,`col56`,`col10`,`col55`(24)), KEY `idx18` (`col62`), KEY `idx19` (`col31`,`col57`,`col56`,`col53`), KEY `idx20` (`col46`), KEY `idx21` (`col83`(54)), KEY `idx22` (`col51`,`col7`(120)), KEY `idx23` (`col7`(163),`col31`,`col71`,`col14`) ) ENGINE=InnoDB DEFAULT CHARSET=latin1 ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=2;#ERROR: 1005 - Can't create table `test`.`table0` (errno: 140 "Wrong create options")
INSERT INTO t1  VALUES (1, 'customer_over', '1');#ERROR: 1136 - Column count doesn't match value count at row 1
insert into t1 values (8429,'8429');#NOERROR
USE `é∆éŒé›é∫éﬁ`;#ERROR: 1049 - Unknown database 'é∆éŒé›é∫éﬁ'
insert into mysql.ndb_replication values ("test", "t3oneex", 3, 7, "NDB$EPOCH()");#ERROR: 1146 - Table 'mysql.ndb_replication' doesn't exist
select * from RocksDB.session_variables where variable_name='RocksDB_ft_min_token_size';#ERROR: 1146 - Table 'RocksDB.session_variables' doesn't exist
INSERT INTO t1 VALUES('');#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t589 (c1 VARCHAR(10));#NOERROR
INSERT INTO t1 VALUES(0xAAB3);#NOERROR
desc v1;#NOERROR
SELECT SUBSTRING('0', 1, 1);#NOERROR
CREATE TABLE IF NOT EXISTS `ÈæñÈæñÈæñ`(`‰∏Ç‰∏Ç‰∏Ç` char(1)) DEFAULT CHARSET = utf8 engine=RocksDB;#NOERROR
CREATE TABLE t1( a VARCHAR(257) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=InnoDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=InnoDB' at line 1
CREATE TABLE t1 (count INT, unix_time INT, local_time INT, comment CHAR(80));#ERROR: 1050 - Table 't1' already exists
CREATE TABLE ti (a MEDIUMINT UNSIGNED, b INT UNSIGNED NOT NULL, c CHAR(11) NOT NULL, d VARCHAR(91) NOT NULL, e VARBINARY(29), f VARCHAR(33) NOT NULL, g BLOB, h BLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
CREATE TABLE `£‘£±` (`£√£±` char(20)) DEFAULT CHARSET = ujis engine = RocksDB;#NOERROR
SET @@session.read_buffer_size = @start_session_value;#ERROR: 1232 - Incorrect argument type to variable 'read_buffer_size'
call mtr.add_suppression("Can't generate a unique log-filename master-bin");#ERROR: 1305 - PROCEDURE mtr.add_suppression does not exist
CREATE TABLE t1 (c1 SMALLINT NOT NULL);#ERROR: 1050 - Table 't1' already exists
INSERT INTO ti VALUES (-26124,-5114549400465575024,'WqOVrUoFGKdSfyDeAnRYwv19uETmStcUe','nZUfQyc94eZJ4qzdbrItD9G73d5TpVElAPLWWYcHjoZ','9cZk0QI','XEBGAbIHrQM0D70LtuU46kIXRpwlfU22w6hUNRE7rWbo8yvB5U3qHkSyrCKCbUp3mMrS6kxsA0RpvMVjSKUco2zejwZsDIbXqAHtii95gniHNEU6taYlg6AqI8YSk5RMH1uEy3uqqPhAvq2wq5pqOuAxkd6AyVF0BGJSGG3Vllh1R1xz','x','o',13);#ERROR: 1062 - Duplicate entry '13' for key 'PRIMARY'
INSERT INTO ti VALUES (3134863602,3804620856474876916,'0A','yRrjF','Yv2UJoLCeaoxGUJ5H3axUOWoewP8kD98biV6MK70NwWlrCoh3cCaSaDDBXB8WucCQC','cHjGY0W18wg5ibypagt0bkaJ8R1YXqKwqLJL60YmsTIZ2yNwtrPBApB3M86YNP89judx4VGAURocksDBvZo4wZw2po9','Fu','f',2);#NOERROR
INSERT INTO t1  VALUES ('2003-11-24 06:30:37.06','18:49:53');#ERROR: 1136 - Column count doesn't match value count at row 1
ALTER TABLE t CHANGE COLUMN a a CHAR(99) BINARY;#ERROR: 1054 - Unknown column 'a' in 't'
SELECT DISTINCT TABLESPACE_NAME, FILE_NAME, LOGFILE_GROUP_NAME, EXTENT_SIZE, INITIAL_SIZE, ENGINE FROM INFORMATION_SCHEMA.FILES WHERE FILE_TYPE = 'DATAFILE' AND TABLESPACE_NAME IN (SELECT DISTINCT TABLESPACE_NAME FROM INFORMATION_SCHEMA.PARTITIONS WHERE TABLE_SCHEMA='mysqldump_test_db' AND TABLE_NAME IN ('\\d-2-1.sql')) ORDER BY TABLESPACE_NAME, LOGFILE_GROUP_NAME;#NOERROR
select str_to_date('04 /30/2004', '%m /%d/%Y');#NOERROR
call mtr.add_suppression("\\[Error\\] Couldn't load plugin named 'keyring_vault' with soname 'keyring_vault.dll'.");#ERROR: 1305 - PROCEDURE mtr.add_suppression does not exist
INSERT INTO ti VALUES (7718394658895087058,-3656019474774807457,'jZjR3WfLO5HkbFZF0f6o3OcZSg5mJfw3px','dUcMoPZLJsJF4pH3yEKOQd92Nbt5bOyrCXBQbIViCpd5HGvuw0VrZS6ETnh697zHI0GEoxYB7F0MEPwZIyGJltQbWO0ECk70WjtIWQ9NCr6yMffueBDfw5aPkWkHbVko1aibbI8LYNJWrBezhMk6oK84TR5guLxZQuLWkDRneQU19T18JRiLvu2dNP06fHVomaGA4z7TanTcMORnZ1jD7eGL57wSOmYuTqkrrXoTlDjjqNpEH6','iOPsniZLHlZY1KY5r','jDI30otLyRxXnmj7xpifFPSnkN6p4MzMmP0X2YhTzaHsboo98pv6F8w1Hw07f3LZsHkmpamvG9Qgp9g0Dbs2hgzO9RD2GNrPMjkrD9vWPtSCU5ryxW8jD3hndlAhAUX0L10fQqbn1CDHL8egrrucFnk02MHzQgZgGW2f17cKIT3cODfTXmxAnnr5h27uouiiWH7hd2k6PLiMSTJ4z','SL','z',5);#ERROR: 1062 - Duplicate entry '5' for key 'PRIMARY'
CREATE TEMPORARY TABLE t14169459_1 (a INT, b TEXT) engine=RocksDB;#NOERROR
CREATE TABLE t1 ( word VARCHAR(64) , PRIMARY KEY (word)) ENGINE=RocksDB CHARSET utf32 COLLATE utf32_general_ci;#ERROR: 1050 - Table 't1' already exists
create temporary table parent ( i int primary key ) engine = MEMORY;#NOERROR
SET @old_autocommit=@@AUTOCOMMIT;#NOERROR
INSERT INTO t1  VALUES(1);#ERROR: 1136 - Column count doesn't match value count at row 1
select * from performance_schema.memory_summary_by_account_by_event_name where event_name like 'memory/%' limit 1;#NOERROR
insert into at(c,_ttx) select concat('_ttx: ',c), (select j from t where c='opaque_mysql_type_date') from t where c='opaque_mysql_type_date';#ERROR: 1146 - Table 'test.at' doesn't exist
set global RocksDB_file_format_max = Bear;#ERROR: 1193 - Unknown system variable 'RocksDB_file_format_max'
EXPLAIN SELECT * FROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA='test';#NOERROR
CREATE TABLE t1(c1 INT, c2 char(20)) ENCRYPTION="Y" ENGINE=InnoDB;#ERROR: 1050 - Table 't1' already exists
INSERT INTO t970 VALUES(1);#ERROR: 1146 - Table 'test.t970' doesn't exist
CREATE TABLE t (a CHAR(24));#ERROR: 1050 - Table 't' already exists
SELECT SUM( DISTINCT e ) FROM t1  GROUP BY b,c,d HAVING (b,c,d) IN ((AVG( 1 ), 1 + c, 1 + d), (AVG( 1 ), 2 + c, 2 + d));#ERROR: 1054 - Unknown column 'e' in 'field list'
CREATE TABLE t1 (a int) ENGINE = RocksDB;#ERROR: 1050 - Table 't1' already exists
create table t5 (a int , b int);#NOERROR
set @@sql_big_selects = @old_sql_big_selects;#ERROR: 1231 - Variable 'sql_big_selects' can't be set to the value of 'NULL'
alter table t1 add column (c int);#NOERROR
select count(length(a) + length(filler)) from t2 where a>='a-1000-a' and a <'a-1001-a';#ERROR: 1054 - Unknown column 'filler' in 'field list'
CREATE TABLE t897 (c1 INTEGER);#NOERROR
INSERT INTO t1  VALUES (590,166102,50,'hamming','simultaneous','endpoint','');#ERROR: 1136 - Column count doesn't match value count at row 1
select * from t1 where user_id>=10292;#ERROR: 1054 - Unknown column 'user_id' in 'where clause'
SELECT HEX(c1),HEX(c2) FROM t5;#ERROR: 1054 - Unknown column 'c1' in 'field list'
declare cmd_2 varchar(512);#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'declare cmd_2 varchar(512)' at line 1
select * FROM t1  where b=1 and c=1;#ERROR: 1054 - Unknown column 'b' in 'where clause'
show session variables like 'RocksDB_ft_num_word_optimize';#NOERROR
INSERT INTO t VALUES (11520575787038079422,2862268,'tyMKL8g1R','ttaGt8WFuX7IO6U73Z8Rn5Qo6iR8z4ghfUPxIET0Zsk41CEARjyaKAm5yxCDEDHsYCuItfO','H3Gcqq','HgcwsvxfhgQHJr8','y','7',12);#ERROR: 1136 - Column count doesn't match value count at row 1
SET @@global.RocksDB_autoextend_increment = "Y";#ERROR: 1193 - Unknown system variable 'RocksDB_autoextend_increment'
CREATE TABLE t1 ( a VARCHAR(10) CHARACTER SET utf16le, b VARCHAR(10) CHARACTER SET utf16le);#ERROR: 1050 - Table 't1' already exists
INSERT INTO t1  VALUES(3,'abc','1996-01-01');#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO t VALUES (-6985228304427136974,3035070911310391493,'E1LQfpubI2omKRDpcn2B2wXNvT8laO5ij642IChtAeHeEYiQaAr','9yC6wQdaaZljcxP','f0dx6zUZHSc89Gtq6DidH','ZAq7QfbL','K','cI',5);#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT col_1_blob = REPEAT("c", 4000) FROM t1 _key2;#ERROR: 1054 - Unknown column 'col_1_blob' in 'field list'
insert into t2 values (782+0.75);#NOERROR
INSERT INTO tp VALUES (162, "Hundred sixty-two"), (164, "Hundred sixty-four"), (166, "Hundred sixty-six"), (168, "Hundred sixty-eight");#ERROR: 1146 - Table 'test.tp' doesn't exist
EXECUTE my_stmt;#ERROR: 1243 - Unknown prepared statement handler (my_stmt) given to EXECUTE
truncate table RocksDB.file_summary_by_instance;#ERROR: 1146 - Table 'RocksDB.file_summary_by_instance' doesn't exist
SELECT * FROM t2 WHERE c2 <=> '9999-12-31 23:59:59' ORDER BY c1,c2 DESC LIMIT 2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
SET SESSION query_cache_type = 1;#NOERROR
SELECT @@sync_binlog;#NOERROR
SELECT @@global.time_zone AS res_is_05_00;#NOERROR
SELECT QUOTE(REPLACE('[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 16386)] = 1', CONCAT('[', 'SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 16386)', ']'), '1'));#NOERROR
CREATE TABLE t1 (a varchar(1)) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t5(c1 INTEGER UNSIGNED NOT NULL AUTO_INCREMENT, c2 INTEGER SIGNED NULL, c3 INTEGER SIGNED NOT NULL, c4 TINYINT, c5 SMALLINT, c6 MEDIUMINT, c7 INT, c8 BIGINT, PRIMARY KEY(c1,c2), UNIQUE INDEX(c3));#ERROR: 1050 - Table 't5' already exists
SET @@session.innodb_lock_wait_timeout=" ";#ERROR: 1232 - Incorrect argument type to variable 'innodb_lock_wait_timeout'
select log(-2,1);#NOERROR
select * from RocksDBdump_myDB.u1;#ERROR: 1146 - Table 'RocksDBdump_myDB.u1' doesn't exist
create table t1 (a char(36) not null)engine=RocksDB;#ERROR: 1050 - Table 't1' already exists
create table t2(b text)engine=MEMORY;#ERROR: 1050 - Table 't2' already exists
insert into t2 values (58041+0.755555555);#NOERROR
insert into s values (5,9,6);#ERROR: 1146 - Table 'test.s' doesn't exist
EXPLAIN PARTITIONS SELECT * FROM t1  WHERE b > CAST('2009-04-02 23:59:59' AS DATETIME);#NOERROR
SELECT var1,var2;#ERROR: 1054 - Unknown column 'var1' in 'field list'
CREATE TABLE `Ôº¥Ôºîa` (`Ôº£Ôºë` char(1) PRIMARY KEY) DEFAULT CHARSET = utf8 engine = MEMORY;#NOERROR
select right('hello', -18446744073709551616);#NOERROR
SELECT SUBSTRING('1', 2);#NOERROR
SELECT SUBSTRING('00', 1, 1);#NOERROR
CALL sp6(-1.00e+09);#ERROR: 1305 - PROCEDURE test.sp6 does not exist
insert into at(c,_dat) select concat('_dat: ',c),j from t where c='null';#ERROR: 1146 - Table 'test.at' doesn't exist
INSERT INTO t VALUES (3180705111895225726,49690,'ALCtLOw9vL4nJX8EEJc6yIcAYdDNT','RYIqIhA8uqHthN3Nh1PRrdkh3G0XnRhFV6hQiGKRxml2675ge4GkxlK6YIiVD4k7Po4CbRJunjJfDjDdL3MmLfmTyGBkNxQzlBbuJTPeIyPG1LhGwbhiWUIViKtVi5CWnnBcR28kbiKPIlOuSy3gDGBCN1tiIpBf9chV4tS8zJHTXDGoE5M4rvFjg7kRVieX7LzqHuSCMsn3FzcEAQiiLPiueeyi','DJpRJoCGZC2YAfDDGH3Z0hHk','qFizulzKXrc27iMiio9UySUoP4ygDyIUmGq2xRidRfyViqPBaON','f','m',13);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE ti (a SMALLINT, b INT UNSIGNED, c CHAR(75), d VARCHAR(87), e VARBINARY(51), f VARCHAR(44) NOT NULL, g TINYBLOB NOT NULL, h BLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=myisam;#ERROR: 1050 - Table 'ti' already exists
ALTER TABLE ti CHANGE COLUMN a a CHAR(7);#NOERROR
SELECT keep_files_on_create = @@session.keep_files_on_create;#ERROR: 1054 - Unknown column 'keep_files_on_create' in 'field list'
CREATE TABLE t1 ( a INT ) ENGINE = RocksDB;#ERROR: 1050 - Table 't1' already exists
insert into t2 values (64678+0.755555555);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t1( a VARBINARY(32769) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=InnoDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=InnoDB' at line 1
INSERT INTO t1  VALUES('2002-01-01','2002-01-02',3),('2002-01-04','2002-01-02',4);#ERROR: 1136 - Column count doesn't match value count at row 1
select @@session.innodb_compression_level;#ERROR: 1238 - Variable 'innodb_compression_level' is a GLOBAL variable
update t1 set name='U+03BA GREEK SMALL LETTER KAPPA' where ujis=0xA6CA;#ERROR: 1054 - Unknown column 'ujis' in 'where clause'
DELETE FROM t1  WHERE MATCH (a,b) AGAINST ('+MySQL' IN BOOLEAN MODE);#ERROR: 1054 - Unknown column 'a' in 'where clause'
CREATE TABLE t2 (primary key (a)) engine=RocksDB select * from t1;#ERROR: 1050 - Table 't2' already exists
CREATE TABLE t1 (t0 TIME, t1 TIME(1), t1 TIME(3), t1 TIME(4), t1 TIME(6));#ERROR: 1050 - Table 't1' already exists
SELECT QUOTE(SUBSTRING('[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 258)] = 1', 1 + 1, 62 - 1 - 1));#NOERROR
SHOW GLOBAL variables LIKE 'early-plugin-load';#NOERROR
INSERT INTO t1  VALUES(DATE_ADD(CAST('2001-01-01 00:00:00' AS DATETIME(6)), INTERVAL 1 SECOND));#NOERROR
select * FROM t1  where a=0 and (( b > 0 and b < 3) or ( b > 5 and b < 10) or ( b > 22 and b < 50)) order by c;#ERROR: 1054 - Unknown column 'a' in 'where clause'
update worklog5743 set a = (repeat("x", 25000));#ERROR: 1146 - Table 'test.worklog5743' doesn't exist
select @@global.ft_stopword_file;#NOERROR
select Name, convert_tz('2004-11-30 12:00:00', Name, 'UTC') from mysql.time_zone_name;#NOERROR
DROP TABLE t592;#ERROR: 1051 - Unknown table 'test.t592'
RENAME TABLE t1 TO d1.t3;#NOERROR
INSERT INTO t1  VALUES(0,-128,0),(1,1,1),(2,2,2),(0,\N,3),(101,-101,4),(102,-102,5),(103,-103,6),(104,-104,7),(105,-105,8);#ERROR: 1062 - Duplicate entry '1' for key 'PRIMARY'
SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 4294967295);#NOERROR
INSERT INTO t1 VALUES(17118);#ERROR: 1136 - Column count doesn't match value count at row 1
SET @@session.max_error_count = 9;#NOERROR
SELECT * FROM t2 WHERE c2 = NULL ORDER BY c1,c2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
DROP VIEW IF EXISTS mysqltest1.v4;#NOERROR
SELECT SUBSTRING('11', 2);#NOERROR
CREATE TABLE t1 (title text) ENGINE=MyISAM;#NOERROR
DROP TABLE t1;#NOERROR
CREATE TABLE t1 (c1 INT NOT NULL, c2 CHAR(5)) PARTITION BY LINEAR KEY(c1) PARTITIONS 99;#NOERROR
ALTER TABLE t CHANGE COLUMN a b BINARY(197);#ERROR: 1054 - Unknown column 'a' in 't'
SELECT SUBSTRING('00', 1, 1);#NOERROR
ALTER TABLE `èÌ›èÌ›èÌ›` ADD `è∞¢è∞¢è∞¢` char(1) FIRST;#ERROR: 1146 - Table 'test.èÌ›èÌ›èÌ›' doesn't exist
CREATE TABLE t1 (id int(11) NOT NULL PRIMARY KEY, name varchar(20), INDEX (name)) ENGINE=MEMORY;#ERROR: 1050 - Table 't1' already exists
SELECT SUBSTRING('default,default,', LENGTH('default') + 2);#NOERROR
SELECT * FROM t1  WHERE c1 <= '1998-12-29 00:00:00' ORDER BY c1,c2;#NOERROR
SELECT SUBSTRING('00', 1, 1);#NOERROR
ALTER TABLE t CHANGE COLUMN a a CHAR(140) BINARY;#ERROR: 1054 - Unknown column 'a' in 't'
INSERT INTO t1  VALUES ('0000-00-00 00:00:01.000000');#ERROR: 1136 - Column count doesn't match value count at row 1
SELECT GROUP_CONCAT(a SEPARATOR '###') AS names FROM t1  HAVING LEFT(names, 1) ='J';#ERROR: 1054 - Unknown column 'a' in 'field list'
SELECT * FROM t1 ;#NOERROR
CREATE PROCEDURE p1() BEGIN DECLARE x NUMERIC ZEROFILL;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
insert into t (id,a) values (139,23);#ERROR: 1054 - Unknown column 'id' in 'field list'
CREATE TABLE t_general (a int, b text) TABLESPACE `S_DEF` engine=RocksDB;#NOERROR
DROP VIEW v1;#ERROR: 4092 - Unknown VIEW: 'test.v1'
explain select * FROM t1 ,t1 where t0.key1 = 5 and (t1.key1 = t0.key1 or t1.key8 = t0.key1);#ERROR: 1066 - Not unique table/alias: 't1'
show global variables like "RocksDB_max_file_classes";#NOERROR
CREATE TABLE t1 (id int unsigned auto_increment, name char(50), primary key (id)) engine=RocksDB;#ERROR: 1050 - Table 't1' already exists
insert into mt1 values (639,'aaaaaaaaaaaaaaaaaaaa');#ERROR: 1146 - Table 'test.mt1' doesn't exist
UPDATE t1 SET c = 10 LIMIT 5;#ERROR: 1054 - Unknown column 'c' in 'field list'
DROP TABLE IF EXISTS RocksDB_stats_drop_locked;#NOERROR
SET @@max_sort_length=default;#NOERROR
SET @@character_set_client= 'cp1256';#NOERROR
SET @@global.early-plugin-load="keyring_vault=keyring_vault.so";#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '-plugin-load="keyring_vault=keyring_vault.so"' at line 1
CREATE TABLE t1( a NATIONAL VARCHAR(8194) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=InnoDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = COMPACT ENGINE=InnoDB' at line 1
insert into t2 values (61549);#ERROR: 1136 - Column count doesn't match value count at row 1
create TABLE t1(a2 int);#ERROR: 1050 - Table 't1' already exists
SELECT SUBSTRING('1', 1, 1);#NOERROR
drop function if exists bug13825_0;#NOERROR
create TABLE t1 (a int not null auto_increment, b char(16) not null, primary key (a)) engine=RocksDB;#ERROR: 1050 - Table 't1' already exists
SELECT LOCATE(']', '1 = 1');#NOERROR
CREATE TABLE t1(a INT, b INT, KEY inx (a), UNIQUE KEY uinx (b)) ENGINE=RocksDB;#ERROR: 1050 - Table 't1' already exists
INSERT INTO `£‘£±;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '`\00A3\0634\00A3±' at line 1
CREATE TABLE `ÇsÇS` (`ÇbÇP` char(5)) DEFAULT CHARSET = sjis engine = TokuDB;#NOERROR
CALL mtr.add_suppression("Failed to set NUMA RocksDB policy of buffer pool page frames to MPOL_INTERLEAVE \\(error: Function not implemented\\)");#ERROR: 1305 - PROCEDURE mtr.add_suppression does not exist
SET @@GLOBAL.keyring_vault_timeout = ' ';#ERROR: 1193 - Unknown system variable 'keyring_vault_timeout'
SET @inserted_value = REPEAT('z', 255);#NOERROR
SELECT SUBSTRING_INDEX('default,', ',', 1);#NOERROR
SELECT INET6_NTOA(INET6_ATON('::1.2.3.00'));#NOERROR
INSERT INTO t1 VALUES(23028);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE t1(a LINESTRING NOT NULL, b GEOMETRY NOT NULL, SPATIAL KEY(a), SPATIAL KEY(b)) ENGINE=MEMORY;#ERROR: 1050 - Table 't1' already exists
alter TABLE t1 add primary key (i);#ERROR: 1072 - Key column 'i' doesn't exist in table
CREATE TABLE t1(c1 DECIMAL NULL, c2 CHAR(25) NOT NULL, c3 TINYINT(4) NULL, c4 CHAR(15) NOT NULL PRIMARY KEY, c5 DECIMAL NOT NULL UNIQUE KEY,c6 NUMERIC(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 't1' already exists
SESSION # SET @global_character_set_server = @@global.character_set_server;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'SESSION # SET @global_character_set_server = @@global.character_set_server' at line 1
select @@global.auto_generate_certs;#ERROR: 1193 - Unknown system variable 'auto_generate_certs'
SELECT COUNT(*) FROM t1 ;#NOERROR
CREATE TABLE t1 ( col_time_1_not_null_key time(1) NOT NULL, pk timestamp NOT NULL DEFAULT '0000-00-00 00:00:00', col_datetime_3_not_null_key datetime(3) NOT NULL, col_time_2_key time(2) DEFAULT NULL, PRIMARY KEY (pk), KEY col_time_1_not_null_key (col_time_1_not_null_key), KEY col_datetime_3_not_null_key (col_datetime_3_not_null_key), KEY col_time_2_key (col_time_2_key) ) ENGINE=InnoDB DEFAULT CHARSET=latin1 /*!50100 PARTITION BY KEY (pk)PARTITIONS 2 */;#ERROR: 1050 - Table 't1' already exists
CREATE DATABASE test2;#NOERROR
set global RocksDB_status_output=0;#ERROR: 1193 - Unknown system variable 'RocksDB_status_output'
INSERT INTO t1 VALUES (1,1,'1A3240'), (1,2,'4W2365');#ERROR: 1136 - Column count doesn't match value count at row 1
INSERT INTO ti VALUES (1394250026,16095,'XjhiTmAt9LMgBCy8sANvSifXgKBTMhAXivX5WFnu2XZ1','h','KN','DCM','A','WY',1);#ERROR: 1062 - Duplicate entry '1' for key 'PRIMARY'
select password('abc');#NOERROR
drop table City;#ERROR: 1051 - Unknown table 'test.City'
SELECT * FROM t3 WHERE c2 < '9999-12-31' ORDER BY c1,c2 LIMIT 2;#ERROR: 1054 - Unknown column 'c2' in 'where clause'
select C.a, c.a FROM t1  c, t1 C;#ERROR: 1054 - Unknown column 'C.a' in 'field list'
insert into t2 values (58906);#ERROR: 1136 - Column count doesn't match value count at row 1
set session myisam_mmap_size=1;#ERROR: 1238 - Variable 'myisam_mmap_size' is a read only variable
create table t1 (f text) engine=innodb;#ERROR: 1050 - Table 't1' already exists
DELETE FROM t1;#NOERROR
CREATE USER user1@localhost IDENTIFIED WITH 'RocksDB_native_password' AS 'auth_string';#ERROR: 1524 - Plugin 'RocksDB_native_password' is not loaded
CREATE PROCEDURE p1(f1 decimal (0)) BEGIN set f1 = (f1 / 2);#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
SET @@SESSION log_queries_not_using_indexes= TRUE;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'log_queries_not_using_indexes= TRUE' at line 1
SELECT QUOTE(REPLACE('[SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 8193)] = 1', CONCAT('[', 'SELECT COUNT(*) FROM t1 WHERE a = LEFT(@inserted_value, 8193)', ']'), '1'));#NOERROR
INSERT INTO t VALUES (1622757766822494550,-21816,'UZclHkB9XMvLdI8a8ByaqJr3xRErIUdgsw1LgIadXx9dBdQESEybHxwJd1yC9y7C2w6','5eGWZ4y9p2orBxUGkLifGf2u0Tmse0LJRftrSCSZs9JxzlpGpn7q8tlwKnKy2','VDTim3TO','4dYSGenMFMNK5t0bqvbGG3XGoqW23uDdXYKc','3','I',8);#ERROR: 1136 - Column count doesn't match value count at row 1
CREATE TABLE ti (a MEDIUMINT, b MEDIUMINT, c BINARY(5), d VARCHAR(2), e VARBINARY(3), f VARBINARY(65), g MEDIUMBLOB NOT NULL, h BLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;#ERROR: 1050 - Table 'ti' already exists
SET @@session.optimizer_search_depth = 65550;#NOERROR
CREATE TABLE ti (a INT, b TINYINT NOT NULL, c BINARY(84) NOT NULL, d VARCHAR(86) NOT NULL, e VARBINARY(42) NOT NULL, f VARBINARY(50), g BLOB, h LONGBLOB, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=MEMORY;#ERROR: 1050 - Table 'ti' already exists
insert into t1 values (3977,3977,3977,3977);#ERROR: 1136 - Column count doesn't match value count at row 1
create table t1(a bit(2) not null);#ERROR: 1050 - Table 't1' already exists
SESSION # SET @start_global_value = @@global.long_query_time;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'SESSION # SET @start_global_value = @@global.long_query_time' at line 1
set f6 = (f6 * 2);#ERROR: 1193 - Unknown system variable 'f6'
CREATE TABLE t1 (a int, INDEX idx(a));#ERROR: 1050 - Table 't1' already exists
CREATE TABLE t2 (I INTEGER);#ERROR: 1050 - Table 't2' already exists
CREATE TABLE `é±é±é±`(`é∂é∂é∂` char(1)) DEFAULT CHARSET = ujis engine=RocksDB;#NOERROR
insert into t values (4482,0);#NOERROR
select wss_type FROM t1  where wss_type ='102935229216544104';#ERROR: 1054 - Unknown column 'wss_type' in 'field list'
INSERT INTO ti VALUES (11623795584367032768,3088758,'ry9poaN93SyRhVa2ZA','gjCYpASwwz0c2MLnOFOM6DkdBNOUHtzoQggUrjPxN4IqtbuyC7Lh23l2iT2GDmpajUGyafDWaMJ2a6jsURoJU9Li14VsLnEXq5IIwGblgGivzo6eq38sRvS4E58Kbl0R54uwD7wqa9wCMYGwoY77b9aBgxaWRCkBtadPTVjV7U2Qoy3P','AbO2iVwpkeG8H4XuNBbwMDFlju7M7U6uYTDn5','oxYEbJ6xXVaiL8FtqyfjI6dwxXJ','W2','7',6);#ERROR: 1062 - Duplicate entry '6' for key 'PRIMARY'
CREATE TABLE m3(c1 INT NULL, c2 BINARY(25) NOT NULL, c3 INTEGER(4) NULL, c4 BINARY(15) NOT NULL PRIMARY KEY, c5 INT NOT NULL UNIQUE KEY,c6 DEC(10,8) NOT NULL DEFAULT 3.141592);#ERROR: 1050 - Table 'm3' already exists
CREATE TABLE `£‘£∑` (`£√£±` char(12), INDEX(`£√£±`)) DEFAULT CHARSET = ujis engine = RocksDB;#NOERROR
EXPLAIN EXTENDED SELECT 'abcd√Å√Ç√É√Ñ√Ö', _latin1'abcd√Å√Ç√É√Ñ√Ö', _utf8'abcd√Å√Ç√É√Ñ√Ö' AS u;#NOERROR
update t1 set name='U+305A HIRAGANA LETTER ZU' where ujis=0xA4BA;#ERROR: 1054 - Unknown column 'ujis' in 'where clause'
SELECT COUNT(c1) AS value FROM t1 WHERE c1 IS NOT NULL;#NOERROR
replace into s values (1, 1000000000,9733);#ERROR: 1146 - Table 'test.s' doesn't exist
select 1E-500 = 0;#NOERROR
CREATE TABLE t1( a VARBINARY(257) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = DYNAMIC ENGINE=RocksDB;#ERROR: 1064 - You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'COMPRESSED ) ROW_FORMAT = DYNAMIC ENGINE=RocksDB' at line 1
SELECT CURTIME(7);#ERROR: 1426 - Too big precision 7 specified for 'curtime'. Maximum is 6
SELECT SUBSTRING('11', 2);#NOERROR
CREATE TABLE t1 ( cid bigint(20) unsigned NOT NULL auto_increment, cap varchar(255) NOT NULL default '', PRIMARY KEY (cid), UNIQUE KEY (cid, cap) ) ENGINE=RocksDBcluster;#ERROR: 1050 - Table 't1' already exists
create table bug19145a (e enum('a','b','c') default 'b' , s set('x', 'y', 'z') default 'y' ) engine=RocksDB;#ERROR: 2006 - MySQL server has gone away
DELETE FROM t_archive;#ERROR: 2006 - MySQL server has gone away
UPDATE t1, t1 SET t1.b = (t2.b+4) WHERE t1.a = t2.a;#ERROR: 2006 - MySQL server has gone away
SET GLOBAL RocksDB_analyze_throttle = 'foobar';#ERROR: 2006 - MySQL server has gone away
CREATE TABLE t1(c1 INT, c2 char(20)) ENCRYPTION="Y" ENGINE = TokuDB;#ERROR: 2006 - MySQL server has gone away
CREATE TABLE variant (a int primary key, b timestamp NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=INNODB;#ERROR: 2006 - MySQL server has gone away
SELECT * FROM t1  WHERE c1 <> 0 ORDER BY c1,c6 DESC; ;
SELECT * FROM t1  WHERE c1 <> 0 ORDER BY c1,c6 DESC; ;
SELECT * FROM t1  WHERE c1 <> 0 ORDER BY c1,c6 DESC; ;
SELECT * FROM t1  WHERE c1 <> 0 ORDER BY c1,c6 DESC; ;

SELECT * FROM t1  WHERE c1 <> 0 ORDER BY c1,c6 DESC; ;

SELECT * FROM t1  WHERE c1 <> 0 ORDER BY c1,c6 DESC; ;

SELECT 1;
SELECT 1;
SELECT 1;
SELECT SLEEP(3);
SELECT SLEEP(3);
SELECT SLEEP(3);
