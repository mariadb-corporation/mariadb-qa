SET sql_mode='NO_ZERO_DATE';
DROP TABLE IF EXISTS t1;
CREATE TABLE t1 (c1 DATE NOT NULL) ENGINE=CSV;
INSERT IGNORE INTO t1 VALUES();
SHOW WARNINGS;
SELECT * FROM t1;

SET sql_mode='no_zero_date';
CREATE TABLE t (a DATETIME NOT NULL) ENGINE=CSV;
CREATE TEMPORARY TABLE t (b INT) ENGINE=InnoDB;
DROP TABLE t;
INSERT INTO t VALUES (1);
SELECT * FROM t;

# Then check error log for:
# [ERROR] mysqld: Table 't' is marked as crashed and should be repaired
CREATE TABLE t1 (pk INT AUTO_INCREMENT, i INT, e ENUM('foo','bar') AS (i) VIRTUAL, PRIMARY KEY (pk)) ENGINE=InnoDB;
INSERT INTO t1 (i) VALUES (1),(NULL),(1),(NULL),(2),(1),(2),(NULL);
ALTER TABLE t1 ADD COLUMN f DECIMAL;
CHECKSUM TABLE t1;

SET SQL_MODE='';
CREATE TABLE t (a INT,b INT GENERATED ALWAYS AS (a+1),c INT) ENGINE=InnoDB PARTITION BY RANGE (b) (PARTITION p0 VALUES LESS THAN (6),PARTITION p VALUES LESS THAN (11),PARTITION p2 VALUES LESS THAN (16),PARTITION p3 VALUES LESS THAN (21));
ALTER TABLE t ENGINE=MyISAM;
INSERT INTO t VALUES (0,0,1);
CHECKSUM TABLE t;
CREATE TABLE t1 (i INT NOT NULL, KEY (i)) ROW_FORMAT=DYNAMIC PARTITION BY KEY(i) PARTITIONS 2;
CREATE TABLE t2 (i INT NOT NULL, KEY (i));
ALTER TABLE t1 EXCHANGE PARTITION p1 WITH TABLE t2;

SET SQL_MODE='';
CREATE TABLE t1 (a INT, b VARCHAR(55), PRIMARY KEY(a)) ENGINE=InnoDB PARTITION BY RANGE (a) (PARTITION p0 VALUES LESS THAN (10), PARTITION p1 VALUES LESS THAN (100), PARTITION p2 VALUES LESS THAN (1000));
CREATE TABLE t2 (a INT, b VARCHAR(55), PRIMARY KEY(a)) CHECKSUM=1, ENGINE=InnoDB;
ALTER TABLE t1 EXCHANGE PARTITION p0 WITH TABLE t2;
USE test;
CREATE TABLE t1 (i1 int, a int);
INSERT INTO t1 VALUES (1, 1), (2, 2),(3, 3);
CREATE TABLE t2 (i2 int);
INSERT INTO t2 VALUES (1),(2),(5),(1),(7),(4),(3);
SELECT a, RANK() OVER (ORDER BY SUM(DISTINCT i1)) FROM t1, t2 WHERE t2.i2 = t1.i1 GROUP BY a;
DROP TABLE t1, t2;

USE test;
SET SESSION SQL_BUFFER_RESULT=1;
CREATE TABLE t (a INT);
SELECT (SELECT 1 FROM t AS t_inner GROUP BY t_inner.a ORDER BY MAX(t_outer.a)) FROM t AS t_outer;
USE test;
SET @@global.log_bin_trust_function_creators=1;
CREATE TABLE t(pk TIMESTAMP DEFAULT '0000-00-00 00:00:00.00',b DATE,KEY (pk));
CREATE FUNCTION f() RETURNS INT RETURN (SELECT notthere FROM t LIMIT 1);
XA BEGIN 'a';
SELECT f(@b,'a');
XA END 'a';
XA PREPARE 'a';
SELECT f(@a,@b);
SET SESSION group_concat_max_len=0;
CREATE TABLE t0 (i INT,KEY USING BTREE (i)) ENGINE=InnoDB;
INSERT INTO t0 VALUES(0xA0C0);
INSERT INTO t0 SELECT DISTINCT i FROM t0;CREATE PROCEDURE p(IN c INT) SET max_connections=100;
EXECUTE IMMEDIATE 'CALL p(?)' USING DEFAULT;

EXECUTE IMMEDIATE 'CREATE OR REPLACE TABLE t1 (a INT DEFAULT ?)' USING DEFAULT;

EXECUTE IMMEDIATE 'CREATE OR REPLACE TABLE t1 (a INT DEFAULT ?)' USING IGNORE;
CREATE TABLE t1 (id INT PRIMARY KEY) ENGINE=InnoDB;
PREPARE stmt FROM "SELECT * FROM t1 ORDER BY ?";
CREATE TEMPORARY SEQUENCE t1 START WITH 100 INCREMENT BY 10;
EXECUTE stmt USING 1;

CREATE TABLE t1 (id INT PRIMARY KEY) ENGINE=InnoDB;
PREPARE stmt FROM "SELECT * FROM t1 ORDER BY ?";
CREATE TEMPORARY SEQUENCE t1 START WITH 100 INCREMENT BY 10;
EXECUTE stmt USING @LIKE;
CREATE TABLE t (a INT);
CREATE PROCEDURE p() RENAME TABLE t TO t2;
CREATE TRIGGER tt AFTER INSERT ON t FOR EACH ROW CALL p();
INSERT INTO t VALUES (0);
SET collation_connection=ucs2_general_ci;
INSERT INTO mysql.proc (db, name, type, specific_name, language, sql_data_access, is_deterministic, security_type, param_list, returns, body, definer, created, modified, sql_mode, comment, character_set_client, collation_connection, db_collation, body_utf8 ) VALUES ( 'a', 'a', 'FUNCTION', 'bug14233_1', 'SQL', 'READS_SQL_DATA', 'NO', 'DEFINER', '', 'int(10)', 'SELECT * FROM mysql.user', 'root@localhost', NOW(), '0000-00-00 00:00:00', '', '', '', '', '', 'SELECT * FROM mysql.user' );
SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME='a';

SET CHARACTER_SET_CONNECTION=ucs2;
INSERT INTO mysql.proc (db, name, type, specific_name, language, sql_data_access, is_deterministic, security_type, param_list, returns, body, definer, created, modified, sql_mode, comment, character_set_client, collation_connection, db_collation, body_utf8 ) VALUES ('test','bug14233_1','FUNCTION','bug14233_1','SQL','READS_SQL_DATA','NO','DEFINER','','int(10)','SELECT COUNT(*) FROM mysql.user','root@localhost', NOW() , '0000-00-00 00:00:00','','','','','','SELECT COUNT(*) FROM mysql.user');
SHOW FUNCTION STATUS WHERE db=DATABASE();

CREATE TABLE t1 (k INT);
CREATE PROCEDURE pr() ALTER TABLE t1 ADD CONSTRAINT CHECK (k != 5);
CALL pr;
CALL pr;
set join_cache_level=3;
CREATE TABLE t1 (col_blob text)engine=innodb;
CREATE TABLE t2 (col_blob text COMPRESSED)engine=innodb;
SELECT * FROM t1 JOIN t2 USING ( col_blob );

SET join_cache_level= 3;
CREATE TABLE t1 (b BLOB);
INSERT INTO t1 VALUES (''),('');
CREATE TABLE t2 (pk INT PRIMARY KEY, b BLOB COMPRESSED);
INSERT INTO t2 VALUES (1,''),(2,'');
SELECT * FROM t1 JOIN t2 USING (b);

USE test;
CREATE TABLE t (c CHAR(0) NOT NULL);
CREATE TABLE u LIKE t;
SET join_cache_level=3;
SELECT t.c,u.c FROM t JOIN u ON t.c=u.c;
USE test;
SET SQL_MODE='';
CREATE TABLE t (a INT PRIMARY KEY) ENGINE=MyISAM;
LOCK TABLE t WRITE;
CREATE TRIGGER t AFTER DELETE ON t FOR EACH ROW SET @log:= concat(@log, "(AFTER_DELETE: old=(id=", old.id, ", data=", old.data,"))");
SHOW TABLE STATUS LIKE 't';

CREATE TABLE t1 (a INT) ENGINE=MyISAM;
LOCK TABLE t1 WRITE;
ALTER TABLE t1 ADD b INT, LOCK=EXCLUSIVE, ORDER BY x;
SHOW TABLE STATUS;

CREATE TABLE t1 (a INT) ENGINE=MyISAM;
CREATE TRIGGER tr AFTER UPDATE ON t1 FOR EACH ROW SET @x=1;
CREATE TABLE t2 (b INT) ENGINE=MyISAM;
CREATE ALGORITHM=MERGE VIEW v2 AS SELECT * FROM t2;
LOCK TABLE v2 WRITE;
CREATE OR REPLACE TRIGGER tr BEFORE DELETE ON t2 FOR EACH ROW SET @x= 1;
SHOW TABLE STATUS;
SET SESSION aria_sort_buffer_size=10;
ALTER TABLE mysql.help_topic ENGINE=Aria;
# mysqld options required for replay: --log-bin 
SET GLOBAL ARIA_GROUP_COMMIT=HARD;
XA START 'A';
SET GLOBAL ARIA_CHECKPOINT_LOG_ACTIVITY=1;
SET GLOBAL ARIA_GROUP_COMMIT_INTERVAL=1000000000;
DELETE FROM mysql.tables_priv WHERE USER LIKE '_%';

USE test;
SET GLOBAL ARIA_CHECKPOINT_LOG_ACTIVITY = 254;
SET GLOBAL ARIA_GROUP_COMMIT=hard;
SET GLOBAL ARIA_GROUP_COMMIT_INTERVAL=1000000000;
CREATE ROLE a;
CREATE PROCEDURE p1() BEGIN END;

SET GLOBAL aria_group_commit_INTERVAL=1000000000;
SET GLOBAL aria_group_commit="HARD";
SET GLOBAL aria_checkpoint_log_activity=1;
DELETE FROM mysql.proc;
SELECT SLEEP (3);
# Sporadic, execute about 200 times
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET SQL_MODE='';
CREATE TABLE t (a INT(11) DEFAULT NULL, b INT(11) DEFAULT NULL, c INT(11) GENERATED ALWAYS AS (a+b) VIRTUAL, x INT(11) NOT NULL, h VARCHAR (10) DEFAULT NULL, KEY idx (c)) DEFAULT CHARSET=latin1;
INSERT INTO t VALUES (1,54,"zardosht", 'abcdefghijklmnopqrstuvwxyz', 3287);
SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT a FROM t WHERE b is NULL and c is NOT NULL ORDER BY a;

CREATE TABLE t1 (a INT, b INT, c INT, v INT AS (a) VIRTUAL, INDEX(c,v)) ENGINE=InnoDB;
SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
INSERT INTO t1 (c) VALUES (9);
SELECT * FROM t1 WHERE c BETWEEN 1 AND 6 ORDER BY b;
USE test;
CREATE TABLE t(a INT);
INSERT INTO t VALUES(0);
INSERT INTO t SELECT a FROM t LIMIT ROWS EXAMINED 0;

create table t1 (id int not null auto_increment primary key,k int, c char(20));
insert into t1 (k,c) values (0,'0'), (0,'0'),(0,'0'),(0,'0'),(0,'0'),(0,'0'),(0,'0');
insert into t1 (c) select k from t1 limit rows examined 2;
USE test;
CREATE TEMPORARY TABLE t(c INT) ENGINE=InnoDB;
LOCK TABLES t AS a WRITE;
ALTER TABLE t ADD COLUMN c2 INT;
REPAIR TABLE t USE_FRM;

USE test;
CREATE TABLE t (a INT PRIMARY KEY, b INT);
SET MAX_STATEMENT_TIME=0.001;
LOCK TABLE t WRITE;
ALTER TABLE t ALGORITHM=INPLACE, ADD d FLOAT;

CREATE DATABASE test;
USE test;
CREATE TEMPORARY TABLE t (c1 INT) ENGINE=InnoDB;
LOCK TABLES t AS a READ, t AS b READ LOCAL;
OPTIMIZE LOCAL TABLE t;
REPAIR LOCAL TABLE t USE_FRM;

# mysqld options required for replay: --log-bin
# Sporadic; repeat at least twice
USE test;
SET SQL_MODE='';
DROP TABLE t;
SET @@MAX_STATEMENT_TIME=0.0001;
CREATE TABLE t (a INT KEY, b TEXT) ROW_FORMAT=COMPACT ENGINE=InnoDB;
UPDATE t SET NAME='U+039B GREEK CAPITAL LETTER LAMDA' WHERE ujis=0xA6AB;
lock tables t write, t as t0 read, t as t2 read;
SET @@GLOBAL.OPTIMIZER_SWITCH="table_elimination=ON";
ALTER TABLE t ENGINE=InnoDB;

CREATE TABLE t1 (a INT) ENGINE=InnoDB;
SELECT * FROM t1;
SET SESSION MAX_SESSION_MEM_USED= @@max_session_mem_used + 1024;
LOCK TABLES t1 WRITE;
ALTER TABLE t1 FORCE;

CREATE TABLE t (c INT);
INSERT INTO t VALUES(1);
SET max_session_mem_used=8192;
LOCK TABLE t WRITE;
CREATE TRIGGER tr BEFORE INSERT ON t FOR EACH ROW INSERT INTO t VALUES(2);
CREATE TABLE t1 (pk int) ENGINE=InnoDB;
SELECT 1 FROM t1 GROUP BY  ROUND((CONVERT('1978-04-10', DECIMAL(61,36))),pk);

USE test;
CREATE TABLE t ENGINE=InnoDB SELECT 0.12345678901234567890123456789012345 AS f;
SELECT ROUND(f,f) FROM t GROUP BY 1;
# Repeat unlimited. Single thread repeats will eventually show the issue. Sometimes within 10 minutes.
# mysqld options used for replay:  --log-bin --sql_mode=ONLY_FULL_GROUP_BY --maximum-query_alloc_block_size=1M --maximum-query_prealloc_size=1M --maximum-range_alloc_block_size=1M --maximum-read_buffer_size=1M --maximum-read_rnd_buffer_size=1M --maximum-sort_buffer_size=1M --maximum-tmp_table_size=1M --maximum-transaction_alloc_block_size=1M --maximum-transaction_prealloc_size=1M --log-output=none --innodb_file_per_table=1 --innodb_flush_method=O_DIRECT --innodb_stats_persistent=off --loose-idle_write_transaction_timeout=0 --loose-idle_transaction_timeout=0 --loose-idle_readonly_transaction_timeout=0 --connect_timeout=60 --interactive_timeout=28800 --slave_net_timeout=60 --net_read_timeout=30 --net_write_timeout=60 --wait_timeout=28800 --lock-wait-timeout=86400 --innodb-lock-wait-timeout=50 --log_output=FILE --log_bin_trust_function_creators=1 --loose-max-statement-time=30 --loose-debug_assert_on_not_freed_memory=0 --innodb-buffer-pool-size=300M --max_allowed_packet=33554432 --maximum-bulk_insert_buffer_size=1M --maximum-join_buffer_size=1M --maximum-max_heap_table_size=1M --maximum-max_join_size=1M --maximum-myisam_max_sort_file_size=1M --maximum-myisam_mmap_size=1M --maximum-myisam_sort_buffer_size=1M --maximum-optimizer_trace_max_mem_size=1M
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET @@GLOBAL.rpl_semi_sync_master_enabled=1;
SET @@GLOBAL.innodb_status_output=1;
CREATE TABLE t3 (c1 VARCHAR(2049) BINARY CHARACTER SET 'latin1' COLLATE 'latin1_bin',c2 YEAR,c3 DATETIME(5)) ENGINE=RocksDB PARTITION BY LINEAR HASH((c2)) PARTITIONS 523;
TRUNCATE t3;
TRUNCATE t3;
SELECT 1;
SET sql_mode='';
CREATE TABLE t1 (a INT AUTO_INCREMENT KEY) ENGINE=InnoDB;
ALTER TABLE t1 ADD UNIQUE u USING HASH(a);
INSERT INTO t1 VALUES (0);
DELETE FROM t1;

CREATE TABLE t (c INT UNSIGNED AUTO_INCREMENT KEY);
CREATE UNIQUE INDEX i1 USING HASH ON t (c ASC);
INSERT INTO t VALUES();
DELETE FROM t;

SET sql_mode='';
CREATE TEMPORARY TABLE t (c INT AUTO_INCREMENT KEY, c2 VARCHAR(1025) BINARY CHARACTER SET 'utf8' COLLATE 'utf8_bin', c3 VARCHAR(1024), c4 VARCHAR(1) CHARACTER SET 'latin1' COLLATE 'latin1_bin') ROW_FORMAT=REDUNDANT ENGINE=InnoDB;
ALTER TABLE t ADD UNIQUE (c4,c3,c2,c);
INSERT INTO t VALUES ('','','fzu{HUd=F6I#A=zRZ6h+}f]]Q$bgIS/iwS&9AtjUYU7Q*LOPlQ[GQq=WDP79) 1=1 ( (G=1aOP0@',1.e+20);
UPDATE t SET c=0;
CREATE TABLE t1 (k1 varchar(10) DEFAULT 5);
CREATE TABLE t2 (i1 int);
ALTER TABLE t1 ALTER COLUMN k1 SET DEFAULT (SELECT 1 FROM t2 limit 1);

CREATE TABLE t1 (k1 text DEFAULT 4);
CREATE TABLE t2 (i1 int);
ALTER TABLE t1 ALTER COLUMN k1 SET DEFAULT (SELECT i1 FROM t2 WHERE i1 = 4 limit 1) ;

create table t1 (k1 varchar(10) default 5);
insert into t1 values (1),(2);
create table t2 (i1 int);
insert into t2 values (1),(2);
alter table t1 alter column k1 set default (select i1 from t2 where i1=2);

create table t1 (i int); #optional
create table t2 (i int); #optional
ALTER TABLE t1 PARTITION BY system_time INTERVAL (SELECT i FROM t2) DAY (PARTITION p1 HISTORY, PARTITION pn CURRENT) ;
CREATE TABLE t1 (d DATETIME(3), v DATETIME(2) AS (d));
CREATE VIEW v1 AS SELECT * FROM t1;
INSERT INTO t1 (d) VALUES ('2004-04-19 15:37:39.123'),('1985-12-24 10:15:08.456') ;
DELETE FROM v1 ORDER BY v LIMIT 4;

CREATE TABLE t1 (id INT NOT NULL AUTO_INCREMENT, f ENUM('a','b','c'), v ENUM('a','b','c') AS (f), KEY(v,id)) ENGINE=MyISAM;
INSERT INTO t1 (f) VALUES ('a'),('b');
INSERT IGNORE INTO t1 SELECT * FROM t1;

CREATE TABLE t1 (a INT, b INT, c BIT(4) NOT NULL DEFAULT b'0', pk INTEGER AUTO_INCREMENT, d BIT(4) AS (c) VIRTUAL, PRIMARY KEY(pk), KEY (b,d)) PARTITION BY HASH(pk);
INSERT INTO t1 () VALUES (),();
UPDATE t1 SET a = 0 WHERE b IS NULL ORDER BY pk;

# mysqld options required for replay:  --log-bin
SET SESSION binlog_row_image=1;
CREATE TEMPORARY TABLE t1 SELECT UUID();
CREATE TABLE t2 (a INT PRIMARY KEY, b TEXT, c INT GENERATED ALWAYS AS(b)) ENGINE=InnoDB;
INSERT INTO t2 (a,b) VALUES (1,1);

# mysqld options required for replay:  --log-bin
SET SESSION binlog_row_image=1;
CREATE TEMPORARY TABLE t1 SELECT UUID();
CREATE TABLE t2 (a INT PRIMARY KEY, b TEXT) ENGINE=InnoDB DEFAULT CHARSET=latin1;
ALTER TABLE t2 ADD COLUMN c INT GENERATED ALWAYS AS (b+1) VIRTUAL;
INSERT INTO t2 (a,b) VALUES (1,1);

SET @@session.default_tmp_storage_engine = MEMORY;
SET optimizer_trace="enabled=on";
CREATE TABLE t1(a INT, KEY USING BTREE (a)) ENGINE=RocksDB;
CREATE TEMPORARY TABLE t2 (b CHAR(60));
INSERT INTO t2 VALUES (59144+0.333333333);
EXPLAIN SELECT 1 FROM (SELECT 1 IN (SELECT 1 FROM t1 WHERE (SELECT 1 FROM t2 HAVING b) NOT IN (SELECT 1 FROM t2) ) FROM t2 ) AS z;

CREATE TABLE t1 (a INT, b BLOB DEFAULT '');
CREATE VIEW v1 AS SELECT * FROM t1;
CREATE VIEW v2 AS SELECT DEFAULT(b) && a FROM v1;
CREATE TABLE t1 (pk INT PRIMARY KEY) ENGINE=InnoDB ROW_FORMAT=REDUNDANT;
ALTER TABLE t1 DROP PRIMARY KEY;
ALTER TABLE t1 ADD d INT;
ALTER TABLE t1 CHANGE pk f INT;
CREATE SEQUENCE s1 nocache;
FLUSH TABLES;
CREATE SEQUENCE s2;
INSERT INTO s1 SELECT * FROM s2;SET @stats.save= @@innodb_stats_persistent;
SET GLOBAL innodb_stats_persistent= ON;
CREATE TABLE t1 (a CHAR(100), pk INTEGER AUTO_INCREMENT, b BIT(8), c CHAR(115) AS (a) VIRTUAL, PRIMARY KEY(pk), KEY(c), KEY(b)) ENGINE=InnoDB;
INSERT INTO t1 (a,b) VALUES ('foo',b'0'),('',NULL),(NULL,b'1');
CREATE TABLE t2 (f CHAR(100)) ENGINE=InnoDB;
SELECT t1a.* FROM t1 AS t1a JOIN t1 AS t1b LEFT JOIN t2  ON (f = t1b.a) WHERE t1a.b >= 0 AND t1a.c = t1b.a;
USE test;
CREATE TABLE t(a POINT GENERATED ALWAYS AS (POINT(1,1)) VIRTUAL, UNIQUE INDEX i(a(1))) ENGINE=MyISAM;
REPAIR LOCAL TABLE t;

CREATE TABLE t1 (a INT GENERATED ALWAYS AS (1) VIRTUAL) ENGINE=MyISAM;
ALTER TABLE t1 ADD KEY (a);

USE test;
CREATE TABLE t(c TEXT GENERATED ALWAYS AS (1) VIRTUAL, INDEX i(c(1))) ENGINE=MyISAM;
OPTIMIZE TABLE t;
CREATE TABLE tx (pk INT PRIMARY KEY) ENGINE=InnoDB;
CREATE TABLE t1 (a INT, CONSTRAINT fk FOREIGN KEY (a) REFERENCES tx(pk)) ENGINE=InnoDB;
ALTER IGNORE TABLE t1 DROP FOREIGN KEY fk, DROP FOREIGN KEY fk, ALGORITHM=COPY;
CREATE TABLE t1 (a INT);
CREATE TABLE t2 (b INT);
CREATE VIEW v2 AS SELECT * FROM t2 ;
LOCK TABLES t1 WRITE, v2 WRITE;
CREATE TABLE IF NOT EXISTS t1 LIKE t2;

USE test;
CREATE TABLE t1 (c INT);
CREATE TABLE t2 (c INT);
LOCK TABLES t1 WRITE,t2 WRITE;
CREATE TABLE IF NOT EXISTS t1 LIKE t2;
SET sql_mode='';
CREATE TABLE t0 (a CHAR(0),b INT,KEY a (a)) ENGINE=InnoDB;
INSERT INTO t0 VALUES (0,0);
ALTER TABLE t0 CHANGE COLUMN a a BINARY (0);
USE test;
CREATE TABLE t (c INT AUTO_INCREMENT NULL UNIQUE KEY);
ALTER TABLE t CHANGE c c INT NOT NULL;

CREATE TABLE t (c INT UNSIGNED AUTO_INCREMENT NULL UNIQUE KEY) ENGINE=InnoDB;
ALTER TABLE t MODIFY c INT ZEROFILL NOT NULL;
CREATE TABLE t1 (a INT);
CREATE TEMPORARY TABLE tmp (b INT);
LOCK TABLE t1 READ;
DROP SEQUENCE tmp;

CREATE TABLE t (a INT);
CREATE TEMPORARY TABLE s (f INT);
CREATE SEQUENCE s;
LOCK TABLE t WRITE;
DROP SEQUENCE s;
CREATE TABLE t1 ( c1 varchar(1) DEFAULT '4' );
ALTER TABLE t1 ALTER COLUMN c1 SET DEFAULT (SELECT 4);
CREATE TABLE t1 (FTS_DOC_ID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, c TINYTEXT, PRIMARY KEY (FTS_DOC_ID), FULLTEXT KEY (c)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (1,'txt');
UPDATE t1 SET FTS_DOC_ID = 4294967298;

CREATE TABLE t1 (FTS_DOC_ID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, c TINYTEXT, PRIMARY KEY (FTS_DOC_ID), FULLTEXT KEY (c)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (1,'txt');
UPDATE t1 SET FTS_DOC_ID = 197505260223;
SET @innodb_optimize_fulltext_only.save= @@innodb_optimize_fulltext_only;
SET GLOBAL innodb_optimize_fulltext_only = 1;
OPTIMIZE TABLE t1;

SET @@session.insert_id = 100000000000;
CREATE TABLE t (FTS_DOC_ID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, c TEXT) ENGINE=InnoDB;
INSERT INTO t (c) VALUES ('aaa');
CREATE FULLTEXT INDEX i ON t (c);
ALTER TABLE t PARTITION BY SYSTEM_TIME INTERVAL (SELECT i FROM t2) DAY (PARTITION p HISTORY;

CREATE TABLE t1 (i INT); 
CREATE TABLE t2 (i INT); 
ALTER TABLE t1 PARTITION BY SYSTEM_TIME INTERVAL (SELECT i FROM t2) DAY (PARTITION p1 HISTORY, PARTITION pn CURRENT);
USE test;
SET SQL_MODE='';
CREATE TABLE t (c DOUBLE PRECISION PRIMARY KEY) ENGINE=Memory;
INSERT INTO t VALUES (1);
REPLACE DELAYED INTO t (c) VALUES (1);
ALTER TABLE t MODIFY c FLOAT NOT NULL;

CREATE TABLE t1 (pk INT PRIMARY KEY) ENGINE=MEMORY;
INSERT INTO t1 VALUES (1),(2);
FLUSH STATUS; # not needed for the test case, only for cleanup
REPLACE DELAYED INTO t1 VALUES (1);CREATE TABLE t1 (pk INT PRIMARY KEY) ENGINE=MEMORY;
SELECT ST_GEOMFROMGEOJSON("{\"type\":[]}",1);

SELECT ST_GEOMFROMGEOJSON("{ \"type\": \"Feature\", \"geometry\": [10, 20] }");

SELECT ST_ASTEXT(ST_GEOMFROMGEOJSON("{ \"type\": [ \"Point\" ],\"coordinates\": [10,15] }",1,0));

SELECT ST_GEOMFROMGEOJSON("{\"\":\"\",\"coordinates\":[0]}");

SELECT ST_ASTEXT(ST_GEOMFROMGEOJSON("{ \"type\": \"GEOMETRYcLECTION\",\"coordinates\": [0.0,0.0]}"));

SELECT ST_GEOMFROMGEOJSON("{ \"type\": \"FeatureCollection\", \"coordinates\": [10, 10] }");

SELECT st_astext (st_geomfromgeojson ("{ \"type1234567890\": \"POINT\", \"coORdinates\": [102, 11]}"));

# mysqld options required for replay: --log-bin
SET SQL_MODE='';
SET @@enforce_storage_engine=MyISAM;
CREATE TABLE t1 (a INT) ENGINE=RocksDB SELECT 42 a;
SET GLOBAL wsrep_forced_binlog_format=STATEMENT;
REPLACE DELAYED t1 VALUES (5);
SELECT ST_ASTEXT (ST_GEOMFROMGEOJSON ("{ \"type1234567890\": \"POINT\", \"coordinates\": [102, 11]}"));

# mysqld options required for replay: --log-bin
CREATE TABLE t1 (ROWID INT, f1 INT, f2 INT, KEY i1 (f1, f2), KEY i2 (f2)) ENGINE=MyISAM;
SET GLOBAL wsrep_forced_binlog_format='STATEMENT';
INSERT DELAYED INTO t1 VALUES ('24','1','1');
SELECT ST_GEOMFROMGEOJSON ("{ \"type\": \"Feature\", \"GEOMETRY\": [10, 20] }");
# mysqld options required for replay:  --innodb_page_size=4k
CREATE TABLE t1 (a TEXT, PRIMARY KEY(a(1871))) ENGINE=InnoDB;
ALTER TABLE t1 MODIFY IF EXISTS b TINYINT AFTER c;

# mysqld options required for replay:  --innodb_page_size=4k
CREATE TABLE t (c1 BLOB,PRIMARY KEY(c1(3072))) ENGINE=InnoDB;
ALTER TABLE t ADD COLUMN j INT;

# mysqld options required for replay:  --innodb_page_size=4k
CREATE TABLE t (c1 TEXT (4000),c2 TEXT (4000),PRIMARY KEY(c1(3072))) ENGINE=InnoDB;
OPTIMIZE TABLE t;

# mysqld options required for replay:  --innodb_page_size=4k
CREATE TABLE t (c TEXT,PRIMARY KEY(c(1300))) ENGINE=InnoDB;

# mysqld options required for replay:  --innodb_page_size=4k
CREATE TABLE t (c TEXT,PRIMARY KEY(c(1300))) ENGINE=InnoDB;
ALTER TABLE t DROP PRIMARY KEY;
CREATE TABLE t1 (a POINT, KEY(a));
HANDLER t1 OPEN h;
HANDLER h READ a = (0);
use test;
create table t1 (a int) ;
delimiter $$
create procedure t1_data()
begin
  declare i int default 1;
  while i < 1000 do insert into t1 values (i); set i = i + 1;
  end while;
end$$
delimiter ;
call t1_data();
create procedure sp() select * from (select a from t1) tb;
call sp();
set optimizer_switch='derived_merge=off';
call sp();

USE test;
CREATE TABLE t AS SELECT {d'2001-01-01'},{d'2001-01-01 10:10:10'};
PREPARE p FROM "SELECT p.* FROM (SELECT t.* FROM t AS t) AS p";
EXECUTE p;
SET @@SESSION.OPTIMIZER_SWITCH="derived_merge=OFF";
EXECUTE p;

USE test;
CREATE TABLE t (a INT PRIMARY KEY);
PREPARE s FROM "SELECT a.* FROM (SELECT tt.* FROM t tt) AS a";
EXECUTE s;
SET SESSION optimizer_switch="derived_merge=OFF";
EXECUTE s;
SET GLOBAL innodb_encryption_threads=5;
SET GLOBAL innodb_encryption_rotate_key_age=0;
SELECT SLEEP(5);  # Somewhat delayed crash happens during sleep
SET @@GLOBAL.innodb_trx_rseg_n_slots_debug=1,@@SESSION.pseudo_slave_mode=ON;
CREATE TABLE t1 (a INT KEY) ENGINE=InnoDB;
CREATE TABLE t2 (a INT KEY) ENGINE=InnoDB;
XA START 'a';
INSERT INTO t2 VALUES (0);
XA END 'a';
XA PREPARE 'a';
DROP TABLE t1;   # ERROR 1637 (HY000): Too many active concurrent transactions
SELECT * FROM t1;  # ERROR 1030 (HY000): Got error 1877 "Unknown error 1877" from storage engine InnoDB
SELECT a FROM t1 WHERE a=(SELECT MAX(a) FROM t1);  # Crash
CREATE TABLE t1 (t TIMESTAMP NOT NULL) ENGINE=MyISAM;
SELECT * FROM t1 WHERE TRUNCATE( t, 1 );

CREATE OR REPLACE TABLE t1 (t TIMESTAMP NOT NULL) ENGINE=MyISAM;
SELECT * FROM t1 WHERE TRUNCATE( t, 1 );

USE test;
CREATE TABLE t (a TIMESTAMP,b TIMESTAMP);  # (ENGINE=InnoDB) 
INSERT INTO t VALUES (0,0);
SET SQL_MODE='TRADITIONAL';
SELECT TRUNCATE(a,b) AS c FROM t;

SET sql_mode='';
CREATE TABLE t5 (c TIMESTAMP KEY,c2 INT NOT NULL,c3 CHAR(1) NOT NULL);
INSERT INTO t5 (c) VALUES (1);
SET sql_mode=traditional;
SELECT ROUND (c,c2),TRUNCATE (c,c2) FROM t5;
CREATE  TABLE t1 (a INT, s BIGINT UNSIGNED AS ROW START, e BIGINT UNSIGNED AS ROW END, PERIOD FOR SYSTEM_TIME(s,e)) WITH SYSTEM VERSIONING ENGINE=InnoDB;
INSERT INTO t1 (a) VALUES (1),(2),(3),(4),(5),(6),(7),(8);
START TRANSACTION;
INSERT INTO t1 (a) VALUES (1),(2),(3),(4),(5),(6),(7),(8);
DELETE FROM t1;

CREATE TABLE t2 (a INT, KEY(a)) ENGINE=InnoDB;
INSERT INTO t2 (a) VALUES (1),(2),(3),(4),(5),(6),(7),(8);
CREATE  TABLE t1 (a INT, s BIGINT UNSIGNED AS ROW START, e BIGINT UNSIGNED AS ROW END, PERIOD FOR SYSTEM_TIME(s,e), FOREIGN KEY (a) REFERENCES t2(a)) WITH SYSTEM VERSIONING ENGINE=InnoDB;
INSERT INTO t1 (a) VALUES (1),(2),(3),(4),(5),(6),(7),(8);
START TRANSACTION;
INSERT INTO t1 (a) VALUES (1),(2),(3),(4),(5),(6),(7),(8);
DELETE FROM t1;

USE test;
CREATE TABLE t(i INT KEY,f INT) ENGINE=InnoDB;
INSERT INTO t VALUES (1,1);
ALTER TABLE t ADD COLUMN c1 BIGINT UNSIGNED AS ROW START INVISIBLE, ADD COLUMN c2 BIGINT UNSIGNED AS ROW END INVISIBLE, ADD PERIOD FOR SYSTEM_TIME(c1,c2), ADD SYSTEM VERSIONING;
START TRANSACTION WITH CONSISTENT SNAPSHOT;
INSERT INTO t VALUES (7,0),(6,0),(5,0),(4,0),(3,0),(2,0),(100,0);
DELETE FROM t;
INSERT INTO t VALUES (0,0);
DELETE FROM t;

# Longer, partially uncleaned testcase, which may produce better reproducibility, though in the end the testcase just above this one also resulted in crash on shutdown, ref bug report
USE test;
CREATE TABLE t(i INT NOT NULL PRIMARY KEY, f INT) ENGINE = InnoDB;
CREATE TABLE servers (dummy int) ENGINE=innodb;
CREATE TABLE t6 (`bit_key` bit(14), `bit` bit, key (`bit_key` )) ENGINE=RocksDB;
CREATE TABLE `visits_events` ( `event_id` mediumint(8) unsigned NOT NULL DEFAULT '0', `visit_id` int(11) unsigned NOT NULL DEFAULT '0', `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, `src` varchar(64) NOT NULL DEFAULT '', `data` varchar(255) NOT NULL DEFAULT '', `visits_events_id` int(11) unsigned NOT NULL AUTO_INCREMENT, PRIMARY KEY (`visits_events_id`), KEY `event_id` (`event_id`), KEY `visit_id` (`visit_id`), KEY `data` (`data`) ) ENGINE=MyISAM AUTO_INCREMENT=33900731 DEFAULT CHARSET=latin1;
CREATE TABLE mt2 (c1 INT NOT NULL PRIMARY KEY, c2 INTEGER, KEY(c2));
CREATE TABLE `Ｔ９` (`Ｃ１` char(12), INDEX(`Ｃ１`)) DEFAULT CHARSET = utf8 engine = MEMORY;
CREATE TABLE ti (a TINYINT UNSIGNED NOT NULL, b TINYINT UNSIGNED NOT NULL, c BINARY(50) NOT NULL, d VARCHAR(93) NOT NULL, e VARBINARY(56), f VARBINARY(36) NOT NULL, g LONGBLOB NOT NULL, h MEDIUMBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;
CREATE TABLE t2 (c1 CHAR(2) CHARACTER SET 'Binary' COLLATE 'Binary',c2 INTEGER ZEROFILL,c3 VARCHAR(2037) CHARACTER SET 'latin1' COLLATE 'latin1_bin') ENGINE=InnoDB;
CREATE TABLE `�ԣ�b` (`�ã�` char(1) PRIMARY KEY) DEFAULT CHARSET = ujis engine = TokuDB;
INSERT IGNORE INTO t VALUES (NULL,0),(NULL,0),(0,21),(4,0),(1,8),(5,66);
alter table t add column trx_start bigint(20) unsigned as row start invisible, add column trx_end bigint(20) unsigned as row end invisible, add period for system_time(trx_start, trx_end), add system versioning;
CREATE TABLE t1 ( id int(11) NOT NULL AUTO_INCREMENT, parent_id smallint(3) NOT NULL DEFAULT '0', col2 varchar(25) NOT NULL DEFAULT '', PRIMARY KEY (id) ) ENGINE=INNODB;
create table t11(a int) engine= Aria;
START TRANSACTION WITH CONSISTENT SNAPSHOT;
insert into t values (5390,0);
insert into t values (8677,0);
insert into t values (9563,0);
insert into t values (3207,0);
insert into t values (5123,0);
insert into t values (700,0);
set global table_open_cache=10;
insert into t values (757,0);
delete from t;
select constraint_name from information_schema.table_constraints where table_schema='test'; ;
select constraint_name from information_schema.table_constraints where table_schema='test'; ;
SELECT 1;

USE test;
SET SQL_MODE='';
CREATE TABLE t (i INT PRIMARY KEY, f INT) ENGINE = InnoDB;
INSERT IGNORE INTO t VALUES (NULL,0),(NULL,0),(0,21),(4,0),(1,8),(5,66);
ALTER TABLE t ADD COLUMN trx_start BIGINT(20) UNSIGNED AS ROW START INVISIBLE, ADD COLUMN trx_end BIGINT(20) UNSIGNED AS ROW END INVISIBLE, ADD PERIOD FOR SYSTEM_TIME(trx_start, trx_end), ADD SYSTEM VERSIONING;
START TRANSACTION WITH CONSISTENT SNAPSHOT;
INSERT INTO t VALUES (5390,0),(8677,0),(9563,0),(3207,0),(5123,0),(700,0),(757,0);
DELETE FROM t;
# Last statement immediately crashes debug. Optimized builds requires mysqladmin shutdown and then crashes.
do json_merge_patch((null ) ,concat_ws('','$',''),'[]' ,from_unixtime(1537014395));

select json_merge_patch((null ) ,concat_ws('','$',''),'[]' ,from_unixtime(1537014395));

select json_merge_patch(null,';. .*c *');

SELECT JSON_MERGE_PATCH(NULL,'a');

SET NAMES swe7;
SELECT JSON_MERGE_PATCH(NULL,'a');

SET NAMES swe7;
SELECT t2.id, t3.id, t4.id, t5.x FROM t1 , t3, t4, t1 WHERE (t2.id >= 1) AND (t2.id < t5.x) OR (t3.id <= 4) AND (t3.id < t5.id) OR (t4.x < 6) AND (t4.x < t5.x) OR (t5.id IN (5001, 5002, 5005, 5008, 5010, 5050, 6000)) FOR UPDATE NOWAIT;
SELECT JSON_MERGE_PATCH(NULL, 'abcdefghijklmnopqrstuvwxyz');
USE test;
CREATE TABLE t (a POLYGON NOT NULL, SPATIAL KEY i (a));
PREPARE s FROM "SHOW VARIABLES WHERE (1) IN (SELECT * FROM t)";
EXECUTE s;
EXECUTE s;

CREATE TABLE t1 (a GEOMETRY);
CREATE TABLE t2 (b INT);
# Data does not make any difference, it fails with empty tables too
INSERT INTO t1 VALUES (GeomFromText('POINT(0 0)')),(GeomFromText('POINT(1 1)'));
INSERT INTO t2 VALUES (1),(2);
PREPARE stmt FROM "SELECT * from t1 WHERE a IN (SELECT b FROM t2)";
EXECUTE stmt;
EXECUTE stmt;

CREATE PROCEDURE p (INOUT i1 INT,OUT i2 INT) MODIFIES SQL DATA SELECT c FROM t WHERE (c) IN (SELECT c3 FROM t);
CREATE TABLE t (c INT,c2 INT,c3 POLYGON);
CALL p (@b,@b);
CALL p (@c,@a);
CREATE TABLE t1 (a TIME NOT NULL);
CREATE VIEW v1 AS SELECT * FROM t1;
SET SQL_MODE= 'ONLY_FULL_GROUP_BY';
SELECT ROUND(a), COUNT(*) FROM v1;

# MDEV-21797
CREATE TABLE t1 (a time not null) engine=innodb;
SELECT STD(0) FROM t1 ORDER BY ROUND(a);
# See MDEV-22448.sql
CREATE TABLE t1 (a DATETIME);
INSERT INTO t1 VALUES ('1979-01-03 10:33:32'),('2012-12-12 12:12:12');
SELECT ROUND(a) AS f FROM t1 GROUP BY a WITH ROLLUP;
CREATE TABLE t1 (a INT AUTO_INCREMENT PRIMARY KEY) PARTITION BY HASH (a) PARTITIONS 3;
REPLACE INTO t1 PARTITION (p0) VALUES (3),(8);
create table t1 (pk int primary key, a int, b int, filler char(32), key (a), key (b)) engine=myisam  partition by range(pk) (partition p0 values less than (10), partition p1 values less than MAXVALUE);
insert into t1 select seq, MOD(seq, 100), MOD(seq, 100), 'filler-data-filler-data' from seq_1_to_50000;
explain select * from t1 partition (p1) where a=10 and b=10; 
flush tables;
select * from t1 partition (p1)where a=10 and b=10;
# Keep repeating the following testcase in quick succession till mysqld crashes. Definitely sporadic.
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE t (column_name_1 INT, column_name_2 VARCHAR(52)) ENGINE=InnoDB;
XA START 'a';
SET MAX_STATEMENT_TIME = 0.001;
INSERT INTO t VALUES (101,NULL),(102,NULL),(103,NULL),(104,NULL),(105,NULL),(106,NULL),(107,NULL),(108,NULL),(109,NULL),(1010,NULL);
CHECKSUM TABLE t, INFORMATION_SCHEMA.tables;
SELECT SLEEP(3);

CREATE TABLE t1 ( c1 int, c2 int, c3 int, c4 int, c5 int, key (c1), key (c5)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (NULL, 15, NULL, 2012, NULL) , (NULL, 12, 2008, 2004, 2021) , (2003, 11, 2031, NULL, NULL);
CREATE TABLE t2 SELECT c2 AS f FROM t1;
UPDATE t2 SET f = 0 WHERE f NOT IN ( SELECT c2 AS c1 FROM t1 WHERE c5 IS NULL AND c1 IS NULL );
# Repeat 1-10 times
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TABLE t (p1 POINT NOT NULL, p2 POINT NOT NULL, SPATIAL KEY k1 (p1), SPATIAL KEY k2 (p2)) ;
XA START 'x';
INSERT INTO t VALUES (ST_PointFromText('POINT(1.1 1.1)'), ST_PointFromText('POINT(1.1 1.1)')), (ST_PointFromText('POINT(1.1 1.1)'), ST_PointFromText('POINT(1.1 1.1)')), (ST_PointFromText('POINT(1.1 1.1)'), ST_PointFromText('POINT(1.1 1.1)')), (ST_PointFromText('POINT(1.1 1.1)'), ST_PointFromText('POINT(1.1 1.1)'));
XA END 'x';
LOAD INDEX INTO CACHE t1 IGNORE LEAVES;


# mysqld options required for replay: --log-bin --sql_mode= 
USE test;
SET @@SESSION.BINLOG_ROW_IMAGE=NOBLOB;
CREATE TEMPORARY TABLE t1 (c1 INT,c2 INT);
CREATE TABLE t2(c1 INT KEY,c2 TEXT UNIQUE);
UPDATE performance_schema.setup_objects SET ENABLED=0;
INSERT INTO t2 VALUES(0,0);

# mysqld options required for replay:  --log-bin --sql_mode=
USE test;
CREATE TEMPORARY TABLE t (c INT PRIMARY KEY, c2 BLOB UNIQUE);
SET @@SESSION.binlog_row_image=noblob;
SELECT * FROM performance_schema.hosts;
INSERT INTO t VALUES(0,0);

# mysqld options required for replay:  --log-bin --sql_mode=
USE test;
SET binlog_row_image= NOBLOB;
CREATE TABLE t1 (pk INT PRIMARY KEY, a TEXT, UNIQUE(a));
INSERT INTO t1 VALUES (1,'foo');
USE test;
CREATE TABLE t1 (c1 INT) ENGINE=Aria;
CREATE TABLE t2 (c1 INT) ENGINE=Aria;
LOCK TABLES t2 AS a WRITE, t1 AS b WRITE;
CREATE TRIGGER t BEFORE INSERT ON t2 FOR EACH ROW SET @a=1;

CREATE TABLE t1 (a INT) ENGINE=Aria PARTITION BY RANGE(a) (PARTITION p1 VALUES LESS THAN (10));
CREATE TABLE t2 (a INT) ENGINE=Aria;
LOCK TABLE t1 WRITE, t2 READ;
ALTER TABLE t1 ADD PARTITION (PARTITION p2 VALUES LESS THAN (20));

CREATE TABLE t1 (a INT) ENGINE=Aria;
CREATE TABLE t2 (b INT) ENGINE=Aria;
LOCK TABLE t2 WRITE, t1 WRITE;
CREATE TRIGGER tr BEFORE DELETE ON t1 FOR EACH ROW SET @a= 1;
INSTALL SONAME 'ha_rocksdb';
CREATE TABLE t1 (pk INT PRIMARY KEY, a INT) ENGINE=RocksDB;
INSERT INTO t1 VALUES (1,1),(2,1);
ALTER TABLE t1 ADD UNIQUE (a) COMMENT 'foo';
CREATE TABLE t2 (b INT) ENGINE=RocksDB;
DROP TABLE t2;
SELECT 1;
USE test;
CREATE TABLE t (a INT) ENGINE=INNODB;
ALTER TABLE t DISCARD TABLESPACE;
RENAME TABLE t TO t2;
BACKUP LOCK x;
RESET QUERY CACHE;

SET STATEMENT max_statement_time=180 FOR BACKUP LOCK t;
RESET SLAVE ALL;
XA BEGIN 'xid';
CREATE TEMPORARY SEQUENCE s;

SET GLOBAL READ_ONLY=1;
XA BEGIN '0';
CREATE TEMPORARY SEQUENCE s;
SET @@SESSION.max_sort_length=2000000;
USE INFORMATION_SCHEMA;
SELECT * FROM tables t JOIN columns c ON t.table_schema=c.table_schema WHERE c.table_schema=(SELECT COUNT(*) FROM INFORMATION_SCHEMA.columns GROUP BY column_type) GROUP BY t.table_name;
if(`systeminfo /FO LIST;

IF(`SELECT @@a=;

EXECUTE IMMEDIATE 'if(`systeminfo /FO LIST';

EXECUTE IMMEDIATE 'if(`systeminfo';

EXECUTE IMMEDIATE 'IF(`SELECT @@a=';

SET CHARACTER_SET_CLIENT=17;
SELECT doc.`Children`.0 FROM t1;

if (`select count(*) = 0 from information_schema.session_variables where variable_name = 'abcdefghijklmnopqrstuvwxyz' and variable_value = 'abcdefghijklmnopqrstuvwxyz';
SET NAMES sjis;
SET @@CHARACTER_SET_CLIENT='cp1257';
(a(b 'т'));
drop function a123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012;

USE test;
DROP FUNCTION f111111111122222222223333333333444444444455555555556666666666777777777788888888889999999999aaaaaaaaaabbbbbbbbbbccccccccccddddddddddeeeeeeeeeeffffffffffgggggggggghhhhhhhhhhiiiiiiiiiijjjjjjjjjjkk;
SET @cmd:="SET @@SESSION.SQL_MODE=(SELECT 'a')";
SET @@SESSION.OPTIMIZER_SWITCH="materialization=OFF";
SET @@SESSION.OPTIMIZER_SWITCH="in_to_exists=OFF";
PREPARE stmt FROM @cmd;

SET @cmd:="SET @x=(SELECT 'a')";
SET @@SESSION.OPTIMIZER_SWITCH="materialization=OFF,in_to_exists=OFF";
PREPARE stmt FROM @cmd;
USE test;
CREATE TABLE t (c INT KEY);
DELETE FROM t ORDER BY c LIMIT 1;

CREATE TABLE t1 (a INT NOT NULL, UNIQUE(a)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (1),(2);
DELETE FROM t1 ORDER BY a LIMIT 1;
CREATE TABLE t (id INT KEY,a YEAR,INDEX (id,a));
REPLACE INTO t (id,a)SELECT /*!99997 */ 1;SET max_heap_table_size= 1048576;
CREATE TABLE t1 (a INT);
INSERT INTO t1 VALUES (1),(2);
CREATE TABLE t2 (a INT,  b INT, c VARCHAR(3), d VARCHAR(35));
INSERT INTO t2 (a) SELECT seq FROM seq_1_to_130;
SET optimizer_switch = 'derived_merge=off';
SELECT * FROM t1, ( SELECT t2a.* FROM t2 AS t2a, t2 AS t2b ) AS sq;

SET max_heap_table_size= 1048576;
CREATE  TABLE t1 (a VARCHAR(4000), b INT);
INSERT INTO t1 SELECT '', seq FROM seq_1_to_258;
CREATE  TABLE t2 (c INT);
INSERT INTO t2 VALUES (1),(2);
CREATE ALGORITHM=TEMPTABLE VIEW v1 AS SELECT * FROM t1;
SELECT c FROM v1, t2 WHERE c = 1;
USE test;
SET @@SESSION.COLLATION_CONNECTION=utf16_hungarian_ci;
CREATE TABLE t(c ENUM('aaaaaaaa') CHARACTER SET 'Binary',d JSON);
CREATE TABLE t1(c ENUM('aaaaaaaaa') CHARACTER SET 'Binary',d JSON);
CREATE TABLE t2(c ENUM('aaaaaaaaaa') CHARACTER SET 'Binary',d JSON);

USE test;
SET @@SESSION.collation_connection=utf32_bin;
CREATE TABLE t(c1 ENUM('a','b','ac') CHARACTER SET 'Binary',c2 JSON,c3 INT) ENGINE=InnoDB;
USE test;
CREATE TABLE t (a INT) ROW_FORMAT=COMPRESSED;
SET GLOBAL innodb_buffer_pool_evict='uncompressed';
USE test;
CREATE TABLE t (c MULTIPOLYGON UNIQUE);
ALTER TABLE t ADD INDEX(c);

CREATE TABLE t (c GEOMETRYCOLLECTION UNIQUE);
ALTER TABLE t ADD INDEX(c);

CREATE TABLE t(c LINESTRING UNIQUE);
ALTER TABLE t ADD INDEX(c);

CREATE TABLE t (c YEAR KEY,e JSON,d GEOMETRY);
ALTER TABLE t ADD INDEX(d),ADD UNIQUE (d);
ALTER TABLE t ADD INDEX(d),ADD UNIQUE (d);
# mysqld options required for replay:  --sql_mode=
USE test;
CREATE TABLE t (c INT) ENGINE=Aria;
INSERT INTO t VALUES (0);
REPAIR TABLE t QUICK USE_FRM ;
INSERT INTO t SELECT * FROM t;
# mysqld options required for replay:  --sql_mode= 
CREATE TABLE t (c INT AUTO_INCREMENT KEY);
SET @@SESSION.insert_id=-0;  # Or -1, -2 etc.
INSERT INTO t VALUES(0);

USE test;
SET @@session.insert_id=0;
CREATE TABLE t (c INT KEY);
INSERT INTO t VALUES (0);
ALTER TABLE t CHANGE c c INT AUTO_INCREMENT;

SET sql_mode='';
CREATE TABLE t (c INT AUTO_INCREMENT KEY) ENGINE=InnoDB;
SET @@SESSION.insert_id=-0;  # Or -1, -2 etc.
INSERT INTO t VALUES(0);

SET SQL_MODE='';
SET GLOBAL stored_program_cache = 0;
SET @start_value=@@GLOBAL.stored_program_cache;
SET SESSION insert_id=@start_value;
INSERT INTO mysql.time_zone VALUES (NULL, 'a');

SET SESSION insert_id=0;
ALTER TABLE mysql.general_log ENGINE=MyISAM;
ALTER TABLE mysql.general_log ADD COLUMN seq INT AUTO_INCREMENT PRIMARY KEY;
SET GLOBAL log_output="TABLE";
SET GLOBAL general_log=1;
INSERT INTO non_existing VALUES (1);

SET SESSION insert_id=FALSE;
INSTALL PLUGIN ARCHIVE SONAME 'ha_archive.so';
CREATE TABLE t (a INT AUTO_INCREMENT,b BLOB,KEY (a)) ENGINE=ARCHIVE;
INSERT INTO t VALUES(0,'');

SET SESSION insert_id=0;
CREATE TABLE t (a SERIAL KEY,b INT);
INSERT INTO t (b) VALUES (1);

CREATE TEMPORARY TABLE t0 (id INT AUTO_INCREMENT KEY,a INT,INDEX (a));
SET SESSION insert_id=0;
INSERT INTO t0 (a) VALUES (0),(0),(0),(0);
SET @@CHARACTER_SET_RESULTS=NULL;
a;
SHOW WARNINGS;
RENAME TABLE mysql.procs_priv TO mysql.procs_gone;
CREATE USER a@localhost;

RENAME TABLE mysql.procs_priv TO mysql.procs_priv_backup;  # MDEV-22319 dup of MDEV-22133
DROP USER a;

RENAME TABLE mysql.procs_priv TO procs_priv_backup;
RENAME USER '0'@'0' to '0'@'0';

RENAME TABLE mysql.procs_priv TO mysql.procs_gone;
RENAME USER _B@'' TO _C@'';

USE test;
CREATE TABLE t (c1 SMALLINT(254),c2 BIGINT(254),c3 DECIMAL(65,30) ZEROFILL) ENGINE=MyISAM PARTITION BY HASH((c1)) PARTITIONS 852;
INSERT INTO t VALUES ('','','');
RENAME TABLE mysql.procs_priv TO procs_priv_backup;
CREATE USER 'test_user'@'localhost';

USE test;
CREATE TABLE t2 (c1 SMALLINT(254),c2 BIGINT(254),c3 DECIMAL(65,30) ZEROFILL) ENGINE=MyISAM PARTITION BY HASH((c1)) PARTITIONS 852;
INSERT INTO t2 VALUES  ('aaa','aaa','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
RENAME TABLE mysql.procs_priv TO procs_priv_backup;
create user 'test_user'@'localhost';
CHANGE MASTER TO MASTER_HOST='h', MASTER_USER='u';
SET @@GLOBAL.session_track_system_variables=NULL;
START SLAVE IO_THREAD;

SET @@GLOBAL.session_track_system_variables=NULL;
SET @@SESSION.session_track_system_variables=default;
SELECT 1;

SET @@global.session_track_system_variables=NULL;
INSERT DELAYED INTO t VALUES(0);

SET GLOBAL session_track_system_variables=NULL;
SET SESSION session_track_system_variables=DEFAULT;

USE test;
SET GLOBAL EVENT_SCHEDULER=ON;
CREATE EVENT e ON SCHEDULE EVERY 1 SECOND DO INSERT INTO execution_log VALUE('a');
SET GLOBAL session_track_system_variables=NULL;
SET GLOBAL session_track_system_variables=NULL;

# mysqld options required for replay: --log-bin --thread_handling=pool-of-threads --thread-pool-size=2047
CHANGE MASTER TO MASTER_DELAY=10, MASTER_HOST='a';
SET GLOBAL session_track_system_variables=NULL;
START SLAVE SQL_THREAD;
SET SESSION wsrep_trx_fragment_size=DEFAULT; ;
USE test;
SET @@SESSION.OPTIMIZER_SWITCH="index_merge_sort_union=OFF";
CREATE TABLE t (a INT, b INT, INDEX(a), INDEX(b)) ENGINE=InnoDB;
INSERT INTO t VALUES (0,0),(0,0);
SELECT * FROM t WHERE a>='2000-01-01 00:00:00' AND b='2030-01-01 00:00:00';
# mysqld options required for replay:  --sql_mode=
USE test;
SET @@SESSION.sort_buffer_size=200;
CREATE TEMPORARY TABLE t1(c1 CHAR(2) PRIMARY KEY,c2 INT ZEROFILL);
CREATE TEMPORARY TABLE t2(c1 CHAR(255) PRIMARY KEY,c2 CHAR (255));
INSERT INTO t1 VALUES(0,0);
INSERT INTO t1 VALUES('aaa',0);
INSERT INTO t2 VALUES('aaa',0);
INSERT INTO t2 SELECT * FROM t1;
DELETE FROM b,c USING t2 AS a JOIN t1 AS b JOIN t2 AS c;
# mysqld options required for replay:  --innodb-buffer-pool-size=-1
USE test;
CREATE TABLE t (c INT);
SELECT JSON_ARRAYAGG(TRUE) FROM t;

SELECT JSON_ARRAYAGG(1) FROM t;  # Same result

SELECT JSON_ARRAYAGG(0) FROM t;  # Same result

USE test;
CREATE TEMPORARY TABLE t0(a INT) ENGINE=InnoDB;
SELECT 0x0=JSON_ARRAYAGG(a) FROM t0;
USE test;
CREATE TEMPORARY TABLE t (a CHAR KEY,b BLOB);
DELETE FROM t ORDER BY a LIMIT 1;

USE test;
CREATE TABLE t (a INT KEY);
UPDATE t SET a=1 ORDER BY a LIMIT 1;
# mysqld options required for replay:  --sql_mode= 
CREATE TABLE t (c INT);
INSERT INTO t VALUES(0);
CREATE TEMPORARY TABLE t2 (c INT);
START TRANSACTION READ ONLY;
INSERT INTO t2 SELECT * FROM t;

# mysqld options required for replay:  --sql_mode= 
USE test;
CREATE TEMPORARY TABLE t (c INT,c2 INT);
START TRANSACTION READ ONLY;
INSERT INTO t VALUES(0);
SAVEPOINT s;
INSERT INTO t VALUES(0,0);

CREATE TEMPORARY TABLE t1 (a INT PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO t1 VALUES (1);
START TRANSACTION READ ONLY;
UPDATE t1 SET a= 2;

CREATE TEMPORARY TABLE t(c INT) ENGINE=InnoDB;
SET SESSION tx_read_only=TRUE;
LOCK TABLE test.t READ;
SELECT * FROM t;
INSERT INTO t VALUES(0xADC3);

CREATE TEMPORARY TABLE tmp (a INT) ENGINE=InnoDB;
INSERT INTO tmp () VALUES (),();
SET TX_READ_ONLY= 1;
INSERT INTO tmp SELECT * FROM tmp;

SET sql_mode='';
SET GLOBAL tx_read_only=TRUE;
CREATE TEMPORARY TABLE t (c INT);
SET SESSION tx_read_only=DEFAULT;
INSERT INTO t VALUES(1);
INSERT INTO t SELECT * FROM t;

SET SQL_MODE='';
CREATE TEMPORARY TABLE t3 (c1 INT PRIMARY KEY,c2 INT,c3 INT) ENGINE=InnoDB;
CREATE TABLE t2 (c1 INT,c2 INT,c3 INT) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t3 (c1 INT) ENGINE=InnoDB;
INSERT INTO t2 VALUES ('a','a','a');
START TRANSACTION WITH CONSISTENT SNAPSHOT, READ ONLY;
INSERT INTO t3 SELECT * FROM t2;
# mysqld options required for replay:  --sql_mode= 
SET @@SESSION.max_sort_length=4;
CREATE TABLE t (c TIMESTAMP(1));
INSERT INTO t VALUES(0);
DELETE FROM t ORDER BY c;

# mysqld options required for replay:  --sql_mode=
USE test;
SET @@SESSION.max_sort_length=1;
CREATE TEMPORARY TABLE t(c DATETIME);
INSERT INTO t VALUES(0);
DELETE FROM t ORDER BY c;

# mysqld options required for replay:  --sql_mode=
USE test;
SET @@SESSION.max_sort_length=4;
CREATE TEMPORARY TABLE t1(c INET6,d DATE);
INSERT INTO t1 VALUES(0,0);
SELECT c FROM t1 ORDER BY c;
# mysqld options required for replay:  --sql_mode=
USE test;
CREATE TEMPORARY TABLE t (c INT);
SET @@SESSION.tx_read_only=1;
INSERT INTO t VALUES(0);
UPDATE t SET c=NULL;

# mysqld options required for replay: --sql_mode=
USE test;
CREATE TEMPORARY TABLE t (c INT) ENGINE=InnoDB;
INSERT INTO t VALUES (1);
START TRANSACTION READ ONLY;
UPDATE t SET c=0;

# mysqld options required for replay: --sql_mode=
USE test;
CREATE TEMPORARY TABLE t (c INT KEY) ENGINE=InnoDB;
INSERT INTO t VALUES (1);
START TRANSACTION READ ONLY;
UPDATE t SET c=0;
SET @@GLOBAL.innodb_encryption_threads=10000;  # Will make server + CLI hang AND stop any new clients from connecting
USE test;
SET @@tmp_disk_table_size=1024;
CREATE VIEW v AS SELECT 'a';
SELECT table_name FROM INFORMATION_SCHEMA.views;
USE test;
SET @@SESSION.max_sort_length=5;
CREATE TABLE t(c TIME(6));
INSERT INTO t VALUES ('00:00:00');
UPDATE t SET c='00:00:00' ORDER BY c;

SET @@SESSION.max_sort_length=5;
CREATE OR REPLACE TABLE t1(c TIME(6));
INSERT INTO t1 VALUES ('00:00:00');
SELECT * FROM t1 ORDER BY c;
SET @@SESSION.div_precision_increment=0;
SELECT UTC_TIME / 0;
SET @@global.wsrep_start_position='00000000-0000-0000-0000-000000000000:-2';
USE test;
CREATE TABLE t(c int) ENGINE=Aria;
SET @@SESSION.default_master_connection='0';
CHANGE MASTER TO master_use_gtid=slave_pos;
SET @@GLOBAL.replicate_wild_ignore_table='';
SELECT 0 &(JSON_ARRAYAGG(1) OVER a) FROM (SELECT 0) AS b WINDOW a AS ();

select json_arrayagg(a) over () from (select 1 a) t;  # MDEV-21915

SELECT 0 &(JSON_ARRAYAGG(1)OVER w) FROM (select 1) as dt WINDOW w as ();  # MDEV-21915

CREATE TABLE t1(c1 INT);
INSERT INTO t1 VALUES(CONVERT(_ucs2 0x064506480631062F USING utf8));
SELECT JSON_ARRAYAGG(null)FROM t1;
USE test;
CREATE TABLE t(c CHAR) ENGINE=InnoDB;
ALTER TABLE t MODIFY c CHAR(3) COLLATE 'latin1_bin';
INSERT INTO t VALUES('a');
USE test;
CREATE TABLE t(a CHAR BINARY) ENGINE=InnoDB;
ALTER TABLE t CHANGE COLUMN a a CHAR(20);

USE test;
CREATE TABLE t (c CHAR(10) BINARY) ENGINE=InnoDB;
ALTER TABLE t CHANGE COLUMN c a CHAR(11);
SET @@SESSION.session_track_user_variables=1;
SET @a=REPEAT('X', 1029);

SET @@session.session_track_user_variables=1;
SET @b='?k;E1S={]8u?yV_ta=Gg"0N:pU,ENpD"/Gg.7N?A4Z0n=AF"$Yxw=y@-ESk$H0g390[]Fm]1JyD&X=_MlwGd"Mrh,VB[)S:mY].G/0OPo&kkAbuhI-_Opg&N:om$=~yTcR%E^ld{:PJcDx{cT,W1_w=[})u-"kY:bE9:NZO8zhb=J"OOZp?+@=l{0D$dL"2"R)TnwW+J-3b1}%gh$rQ4-WU=%r,SI-INq[+%b(^7ON5=[fDoy9uDD;xSV%@%qGh.YRwb]Ef=wNrg]wMn8FeSY;VIsnhh=FszZMQTFwhBXWv/HZE{4_gps_L~TndPl_B8^8[SDQ:?$:/91vn6WGd=bTO#=s=~ylr:){9%BuL,Hg=n&D?sCKXBF+iy_7;N(W#=9QtQKIYapEY@.mro)vu=rQVV6/Q/$ji7R0K{dy~*@~kD:&#%#&[G,LS^6=ZeJD5Wd9^x^#o+qP^x6+~U*(?PguiAeE1AM=tQE.Qzq~X{"~%WKC}[9p=wfTx6=dg#=q%k3p=Ym=24=6f@2(G$*zf1_fCYV[muJo3EhM=;CE&M,89-fQp/=pVYCWzd"YF]7=KjbV=ECSx4s#[i10~Ar:,PFL=7JnN_4gM1B^vA@(1s;*fn#5R-8VHtM&&QBCWf?tEg19S5mO)k.w+gR0UT-e6t}7.OfSck8#u~wN_PehioD;rKpn=pr[gex/=vad~"Lz=7TtB^[DoAL5F{+BNJ%LC3d(EX"92DlVtaj={CPDpKQ=CnE@xw5eX:f}gu5DRYy4Prv[Z=YXKi]Je0fifDMWjB0nb,QKPEf,f}e=tWpoE/v^i?KHI4Qv&;-:I';

SET @@session.session_track_user_variables=1;
SET @c='s$=WmKIk*t=X/E,X0+v#gc_]Pxy+-VzmE.%C*_W4:[+x@/lf/{k?{}9#k4Pjy_}IcoIY=qKrkey(c1Y_1zuFj7KVZ"4%.g7s#y4.$3Oo~jpX8hKs)K92-d64SXMxRGlq$~jyVhRG=%)cV,pM/Qv7Xh@db4i,%3^@B:2U%(&gbIhJ8e_1QbrVa?cAlRW#YH=sJwD%hR4*16c3FYZ)~BdRj2*V0D;Q@V7/0srEQEAfN@#4C*^LGd=@j.Hx&f23Pc*"J=.gUhL[X-[c}mEs@"GYQuu%tZC(g$E5:3_V;nH1fLP=7^QlTp6/wIb]=:%8=[#c72{s%Vbpd=r^C13w$=n$h(v4=N;*;i&="pbc&sGUUF$3}TQ[n[WxF)"7rCi1Z9.2MA{:6+^x%V;nd$Ke=4=ZbM,&{xSqmRauh?R2(&8h^/=o)E?:dgE^/9_/0GE&2n77GZKQ33%o)7iRPIv5z;6sP_]#i=0M72+5_Wh%K2I]-d,=E9=6{j9_TDV0]jv~2GI{6DLfSyiNgK:]T5^Whg=SN4cdM[j/$#M/)E+mAm{@=*Fvp=PV=S.7d98Dp$NxdZ+p]XT$@alvW#.wE+F+vDp[=f:J=u9-zIW]j^fjo854yhVP?~01m-E$N(iO}sXK$HeqNzT~]m)@t/_nemTJuIQVIjG?hDdIJy5q-%xUfVg=8O1#DA{JFZ0VfPRc;l-HAlqf6+6%"J.ci+bBH?[WS3ngu';
CREATE TABLE t1 (a CHAR(3) CHARACTER SET latin1 COLLATE latin1_general_ci NOT NULL) ENGINE=InnoDB;
INSERT INTO t1 VALUES ('foo');
ALTER TABLE t1 MODIFY a CHAR(6);

CREATE DATABASE test;
USE test;
CREATE TABLE t (a BLOB NOT NULL, b DATE NOT NULL);
ALTER TABLE t CHANGE COLUMN a a CHAR(150) BINARY;
INSERT INTO t VALUES (1261,0);
ALTER TABLE t CHANGE COLUMN a a CHAR(200) NOT NULL;
USE test;
CREATE FUNCTION f(c INT) RETURNS BLOB RETURN 0;
CREATE PROCEDURE p(IN c INT) SELECT f('a');
CALL p(0);
CALL p(0);
SET optimizer_trace="enabled=on";
SELECT 'a\0';
USE test;
SET @@SESSION.sql_mode=TRADITIONAL;
CREATE TABLE t (id INT) ENGINE=Aria;
ALTER TABLE t ADD COLUMN c DATETIME NOT NULL,ALGORITHM=INPLACE;
USE test;
CREATE TABLE t(c BIGINT);
SELECT 1 FROM t WHERE c<GEOMFROMTEXT('LINESTRING(-1 1)');
# Start up server with ASAN+UBSAN and observe issues seen during startup in error log
#/test/10.5_dbg/strings/ctype-mb.c:409:3: runtime error: null pointer passed as argument 2, which is declared to never be null
#/test/10.5_dbg/mysys/mf_iocache.c:825:3: runtime error: null pointer passed as argument 1, which is declared to never be null
#/test/10.5_dbg/sql/protocol.cc:61:9: runtime error: null pointer passed as argument 2, which is declared to never be null
SET @@SESSION.tmp_table_size=1048576;
SET @@SESSION.max_sort_length=5;
SET @@SESSION.sort_buffer_size=1024;
SET @@SESSION.max_length_for_sort_data=66556;
SELECT * FROM information_schema.session_variables ORDER BY variable_name;

USE test;
SET SQL_MODE='';
CREATE TABLE t (c1 TIME PRIMARY KEY,c2 TIMESTAMP(3),c3 VARCHAR(1025) CHARACTER SET 'utf8' COLLATE 'utf8_bin') ;
INSERT INTO t VALUES (SYSDATE(2),'',GET_FORMAT(DATETIME,'ISO'));
SET SESSION max_length_for_sort_data=8388608;
SET SESSION sort_buffer_size=16;
SELECT * FROM t WHERE c1 BETWEEN '00:00:00' AND '23:59:59' ORDER BY c1,c2;
USE test;
CREATE TABLE t1 (a TEXT CHARACTER SET utf16);
SELECT * FROM (VALUES (1) UNION SELECT * FROM t1) AS t;

VALUES (1) UNION SELECT _utf16 0x0020;
VALUES ('') UNION SELECT _utf16 0x0020 COLLATE utf16_bin;
VALUES ('') UNION VALUES( _utf16 0x0020 COLLATE utf16_bin);

VALUES (_latin1 0xDF) UNION SELECT _utf8'a' COLLATE utf8_bin;
VALUES (_latin1 0xDF) UNION VALUES(_utf8'a' COLLATE utf8_bin);
USE test;
CREATE TABLE t (a BINARY) ENGINE=InnoDB;
INSERT INTO t VALUES (1);
ALTER TABLE t CHANGE COLUMN a a CHAR(10);
ALTER TABLE t CHANGE COLUMN a a CHAR(100) BINARY;
SELECT a FROM t;
USE test;
SET SQL_MODE='';
CREATE TABLE t (c1 INT UNSIGNED,c2 CHAR) PARTITION BY KEY (c1) PARTITIONS 2;
INSERT INTO t VALUES (NULL,0),(NULL,1);
ALTER TABLE t ADD PRIMARY KEY (c1,c2);
DELETE FROM t;

CREATE TABLE t1 (f CHAR(6)) WITH SYSTEM VERSIONING PARTITION BY system_time LIMIT 1 (PARTITION p1 HISTORY, PARTITION p2 HISTORY, PARTITION pn CURRENT);
INSERT INTO t1 VALUES (NULL);
UPDATE t1 SET f = 'foo';
UPDATE t1 SET f = 'bar';
CREATE VIEW v1 AS SELECT * FROM t1 FOR SYSTEM_TIME ALL;
UPDATE v1 SET f = '';
# mysqld options required for replay: --log-bin 
USE test;
XA START '0';
CREATE TEMPORARY TABLE t(c INT);
XA END '0';
XA PREPARE '0';
DROP TEMPORARY TABLE t;
# shutdown of sever, or some delay, may be required before crash happens
SET @@local.sql_mode='no_field_options';
CREATE OR REPLACE TABLE t (a INT AS (b + 1), b INT, ROW_START BIGINT UNSIGNED AS ROW START INVISIBLE, ROW_END BIGINT UNSIGNED AS ROW END INVISIBLE, PERIOD FOR SYSTEM_TIME(ROW_START, ROW_END)) WITH SYSTEM VERSIONING ENGINE=InnoDB;
CREATE OR REPLACE TABLE t1 LIKE t;
INSERT IGNORE INTO t1 VALUES (1,1);
UPDATE t1 SET a=5 WHERE a !=3;SET max_session_mem_used = 50000;
help 'it is going to crash';
help 'it is going to crash';
help 'it is going to crash';
help 'it is going to crash';
help 'it is going to crash';  # Crashes
help 'it crashed'; 

SET SQL_MODE='';
SET GLOBAL wsrep_forced_binlog_format='STATEMENT';
HELP '%a';
CREATE TABLE t (c CHAR(8) NOT NULL) ENGINE=MEMORY;
SET max_session_mem_used = 50000;
REPLACE DELAYED t VALUES (5);
HELP 'a%';
SET @@SESSION.wsrep_causal_reads=ON;
SET SESSION wsrep_on=1;
START TRANSACTION READ WRITE;

SET NAMES utf8, collation_connection='utf16le_bin';
SET GLOBAL wsrep_provider='/invalid/libgalera_smm.so';
SET GLOBAL wsrep_cluster_address=AUTO;
SET GLOBAL wsrep_slave_threads=2;
USE test;
SET @@SESSION.optimizer_trace=1;
SET in_predicate_conversion_threshold=2;
CREATE TABLE t1(c1 YEAR);
SELECT * FROM t1 WHERE c1 IN(NOW(),NOW());

SET in_predicate_conversion_threshold=2;
CREATE TABLE t1(c1 YEAR);
SELECT * FROM t1 WHERE c1 IN(NOW(),NOW());
drop table t1;

USE test;
SET IN_PREDICATE_CONVERSION_THRESHOLD=2;
CREATE TABLE t(c BIGINT NOT NULL);
SELECT * FROM t WHERE c IN (CURDATE(),ADDDATE(CURDATE(),'a')) ORDER BY c;
USE test;
CREATE TABLE t (a INT KEY);
HANDLER t OPEN AS t;
XA START '0';
SELECT * FROM t;
XA END '0';
XA PREPARE '0';
HANDLER t READ NEXT;

CREATE TABLE t (i INT);
CREATE TABLE t2 (a INT, KEY(a));
XA BEGIN 'x';
SELECT DATE_SUB(a, INTERVAL 1 MINUTE) FROM t2 ORDER BY a;
HANDLER t OPEN;
XA END 'x';
XA PREPARE 'x';
HANDLER t READ FIRST;
USE test;
CREATE TABLE t(a INT);
ALTER TABLE t DISCARD TABLESPACE;
ALTER TABLE t ADD COLUMN c INT;
USE test;
SET GLOBAL GENERAL_LOG=ON;
SET GLOBAL log_output="FILE,TABLE";
CREATE TABLE t(a DATE);
EXPLAIN SELECT * FROM t LIMIT ROWS EXAMINED 0;
SELECT 1;
SELECT JSON_ARRAYAGG(NULL) FROM (SELECT 1 AS t) AS A;
# mysqld options required for replay: --log-bin 
RESET MASTER TO 5000000000;
CREATE DATABASE a;
CREATE TABLE t (i INT AUTO_INCREMENT PRIMARY KEY);
DELETE FROM t WHERE i IN (SELECT JSON_OBJECT('a','a') FROM DUAL WHERE 1);

create table t1 (a int );
insert into t1 values (1),(2),(3);
update t1 set a = 2 where a in (select a where a = a);

select 1 from dual where 1 in (select 5 where 1);

CREATE TABLE v0 ( v1 INT ) ;
INSERT INTO v0 ( v1 ) VALUES ( 9 ) ;
UPDATE v0 SET v1 = 2 WHERE v1 IN ( SELECT v1 WHERE v1 = v1 OR ( v1 = -1 AND v1 = 28 ) ) ;
INSERT INTO v0 ( v1 ) VALUES ( 60 ) , ( 0 ) ;
SELECT RANK ( v1 ) OVER w , STD ( v1 ) OVER w FROM v0 WINDOW v2 AS ( PARTITION BY v1 ORDER BY v1 * 0 ) ;
USE test;
SET SESSION sql_select_limit=0;
CREATE TABLE t(b INT);
CREATE TEMPORARY TABLE t(a INT);
DROP TABLE IF EXISTS t;
CREATE TABLE t2(a TEXT);
SELECT * FROM t2 HAVING a IN (SELECT a FROM t);
USE test;
SET @@SESSION.collation_connection=utf32_estonian_ci;
CREATE TABLE t1(c1 SET('a') COLLATE 'Binary',c2 JSON);
USE test;
SET SESSION aria_sort_buffer_size=1023;
CREATE TABLE t (c CHAR);
INSERT INTO t VALUES (''),('');
CREATE TABLE t2 (c TEXT,INDEX(c)) ENGINE=Aria;
INSERT INTO t2 SELECT * FROM t;

USE test;
SET SESSION aria_sort_buffer_size=1023;
CREATE TABLE t (c CHAR);
INSERT INTO t VALUES (''),('');
SELECT * FROM t INTO OUTFILE 'o';
CREATE TABLE t2 (c TEXT,INDEX(c)) ENGINE=Aria;
LOAD DATA INFILE 'o' INTO TABLE t2;

SET aria_sort_buffer_size=4096;
SET SESSION tmp_table_size = 65535;
SELECT COUNT(*) FROM information_schema.tables A WHERE NOT EXISTS (SELECT * FROM information_schema.COLUMNS B WHERE A.table_schema = B.table_schema AND A.table_name = B.table_name);
# mysqld options required for replay:  --innodb-data-file-size-debug=-1 
CREATE ROLE r;
SET ROLE r;
DROP ROLE r;
REVOKE ALL ON *.* FROM CURRENT_ROLE;
SET SESSION session_track_system_variables="*";
SET SESSION max_relay_log_size=3*1024*1024;
USE test;
CREATE TABLE t (c BLOB, UNIQUE(c)) ENGINE=MyISAM;
INSERT DELAYED INTO t VALUES (1);

CREATE  TABLE t1 (a BLOB, UNIQUE(a)) ENGINE=MyISAM;
INSERT DELAYED t1 () VALUES ();
CREATE TABLE t1 (id INT, f TEXT UNIQUE, d DATE, PRIMARY KEY (id)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (1,NULL,'2001-11-16'),(2,NULL,'2007-07-01'),(3,NULL,'2020-02-03'), (4,NULL,'1971-05-24'),(5,NULL,'1971-05-24'),(6,NULL,'1985-02-07'); 
ANALYZE TABLE t1 PERSISTENT FOR ALL;
CREATE TABLE t (a INT) ENGINE=MyISAM;
CREATE VIEW v AS SELECT * FROM performance_schema.table_handles ORDER BY INTERNAL_LOCK;
INSERT DELAYED INTO t VALUES (1);
SELECT * FROM v;

USE test;
SET SESSION default_storage_engine=MyISAM;
CREATE TABLE t1 (id INT);
INSERT DELAYED INTO t1 VALUES(69, 31), (NULL, 32), (NULL, 33);
SELECT * FROM performance_schema.table_handles;
SET GLOBAL keycache1.key_cache_segments=7;
SET GLOBAL keycache1.key_buffer_size=1*1024*1024;
SET GLOBAL keycache1.key_buffer_size=0;
SET GLOBAL keycache1.key_buffer_size=128*1024;
SET @@character_set_client = 3;
SET �='';
USE test;
SET SESSION innodb_compression_default=1;
SET GLOBAL innodb_compression_level=0;
CREATE TABLE t(c INT);

USE test;
SET GLOBAL innodb_compression_level=0;
SET SESSION innodb_compression_default=1;
CREATE TABLE t(c INT);

CREATE TABLE tp (a INT)ENGINE=InnoDB ROW_FORMAT=DYNAMIC page_compressed=1;
SET GLOBAL innodb_compression_level=-1;
ALTER TABLE tp ENGINE=InnoDB;

SET GLOBAL innodb_compression_default=1;
SET GLOBAL innodb_compression_level=0;
CREATE TABLE t (c INT);

SET GLOBAL innodb_compression_level=0;
CREATE TABLE t (a INT) ENGINE=InnoDB ROW_FORMAT=DYNAMIC page_compressed=1;
USE test;
CREATE TABLE t(a INT,b INT) ENGINE=MEMORY;
INSERT INTO t SET a=1;
SELECT JSON_ARRAYAGG(b LIMIT 2) FROM t;

USE test;
CREATE TABLE t1(a INT,b INT,KEY(a)) ENGINE=MEMORY;
SELECT EVENT_NAME,COUNT_STAR FROM performance_schema.events_waits_summary_global_by_event_name WHERE EVENT_NAME LIKE NULL;
INSERT INTO t1 SET a=3;
SELECT JSON_ARRAYAGG(b LIMIT 2)FROM t1;
USE test;
SET default_storage_engine=MyISAM;
SET SESSION alter_algorithm=4;
CREATE TABLE t(a INT) PARTITION BY RANGE(a) SUBPARTITION BY KEY(a) (PARTITION p0 VALUES LESS THAN (10) (SUBPARTITION s0,SUBPARTITION s1), PARTITION p1 VALUES LESS THAN (20) (SUBPARTITION s2,SUBPARTITION s3));
ALTER TABLE t ADD COLUMN c INT;
USE test;
CREATE TABLE t (c int) ENGINE=InnoDB key_block_size= 4;
SET GLOBAL innodb_buffer_pool_evict='uncompressed';
SET GLOBAL innodb_checksum_algorithm=strict_none;
SELECT SLEEP(10);  # Server crashes during sleep

USE test;
CREATE TABLE t(a INT) ENGINE=InnoDB ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=1;
SET GLOBAL innodb_buffer_pool_evict='uncompressed';
SET GLOBAL innodb_checksum_algorithm=3;
SELECT SLEEP(5);  # Server crashes during sleep
USE test;
CREATE TABLE t (c INT);
ALTER TABLE t ADD d INT FIRST;
ALTER TABLE t ADD e CHAR(255) CHARACTER SET UTF32;
USE test;
CREATE TEMPORARY TABLE t(a INT);
ALTER TABLE t ADD c0 INT;
ALTER TABLE t ADD CONSTRAINT CHECK(c0 NOT IN (0,0,0));
ALTER TABLE t ADD c0 BLOB;
INSERT INTO t VALUES(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0);
USE test;
SET GLOBAL innodb_simulate_comp_failures=99;  # (!)
CREATE TABLE t(c INT);
INSERT INTO t VALUES (1),(1),(1);
ALTER TABLE t KEY_BLOCK_SIZE=2;
# mysqld options required for replay: --log-bin
USE test;
CREATE FUNCTION f(c INT) RETURNS NUMERIC NO SQL RETURN 0;
CREATE OR REPLACE FUNCTION f(c INT) RETURNS INT RETURN 0;
CREATE OR REPLACE TABLE t1 (a INT);
ALTER TABLE t1 ADD row_start TIMESTAMP(6) AS ROW START, ADD row_end TIMESTAMP(6) AS ROW END, ADD PERIOD FOR SYSTEM_TIME(row_start,row_end), WITH SYSTEM VERSIONING, MODIFY row_end VARCHAR(8);

CREATE TEMPORARY TABLE t1 (i INT KEY, c CHAR(10)) ENGINE=MEMORY ROW_FORMAT=DYNAMIC;
CREATE TABLE t1 (a INT, b INT, KEY(a), INDEX b (b));
DROP TABLE t1;
ALTER TABLE t1 ADD ROW_START TIMESTAMP (6) AS ROW START, ADD ROW_END TIMESTAMP (6) AS ROW END, ADD PERIOD FOR SYSTEM_TIME(ROW_START,ROW_END), WITH SYSTEM VERSIONING, MODIFY ROW_END VARCHAR(8);
USE test;
CREATE TABLE t(c INT DEFAULT (1 LIKE (NOW() BETWEEN '' AND '')));
INSERT DELAYED INTO t VALUES(1);

SET SQL_MODE='';
CREATE TABLE t (a INT AS (b + 1), b INT, row_start BIGINT UNSIGNED AS ROW START INVISIBLE, row_end BIGINT UNSIGNED AS ROW END INVISIBLE, PERIOD FOR system_time (row_start, row_end)) WITH SYSTEM VERSIONING;
INSERT INTO test.t (a) VALUES (poINT (1,1));
SELECT * FROM t FOR system_time FROM '0-0-0' TO CURRENT_TIMESTAMP(6);
USE test;
SET @@in_predicate_conversion_threshold= 2;
CREATE TEMPORARY TABLE t(a INT);
SELECT HEX(a) FROM t WHERE a IN (CAST(0xffffffffffffffff AS INT),0);
USE test;
SET SQL_MODE='';
CREATE TABLE t (id INT);
INSERT INTO t VALUES (1);
INSERT INTO t VALUES (2);
INSERT INTO t VALUES (3);
INSERT INTO t VALUES (4);
ALTER TABLE mysql.help_keyword engine=InnoDB;
HELP going_to_crash;

# mysqld options required for replay:  --thread_handling=pool-of-threads
USE test;
SET SQL_MODE='';
CREATE TABLE t(c INT UNSIGNED AUTO_INCREMENT NULL UNIQUE KEY) AUTO_INCREMENT=10;
insert INTO t VALUES ('abcdefghijklmnopqrstuvwxyz');
ALTER TABLE t ALGORITHM=INPLACE, ENGINE=InnoDB;
DELETE FROM t ;
INSERT INTO t VALUES(3872);
ALTER TABLE mysql.help_topic ENGINE=InnoDB;
HELP no_such_topic;
CREATE TABLE t1 (a INT) ENGINE=InnoDB;
INSERT  INTO t1 VALUES (1),(2),(3),(4),(5),(6);
CREATE TABLE t2 (f BLOB UNIQUE) ENGINE=InnoDB WITH SYSTEM VERSIONING PARTITION BY system_time INTERVAL 1 WEEK (PARTITION p1 HISTORY, PARTITION pn CURRENT);
INSERT INTO t2 VALUES (NULL),('');
DELETE t2.* FROM t1, t2;
CREATE TABLE t1 (id INT PRIMARY KEY, a VARCHAR(1024) NOT NULL);
INSERT INTO t1 VALUES (1,'foo'),(2,'bar');
SET SQL_MODE= '';
SELECT GROUP_CONCAT( IF( id, '', a ), MID( a, 10, 0 ) ) AS f FROM t1;
CREATE OR REPLACE TABLE t1 (f TEXT UNIQUE, FULLTEXT(f)) ENGINE=InnoDB;
INSERT INTO t1 VALUES ('foo');
CREATE OR REPLACE TABLE t2 (a VARCHAR(255)) ENGINE=InnoDB;
INSERT INTO t2 VALUES ('foobar'),('qux');
UPDATE t1 JOIN t2 SET f = a;
CREATE OR REPLACE TABLE t1 (id INT, s DATE, e DATE, PERIOD FOR p(s,e), PRIMARY KEY(id, p WITHOUT OVERLAPS)) ENGINE=HEAP PARTITION BY HASH(id);
UPDATE t1 SET id = 1;
CREATE TABLE t1 (a VARCHAR(128), b VARCHAR(32), KEY(a) USING BTREE, KEY(b) USING BTREE) ENGINE=HEAP;
INSERT INTO t1 VALUES ('foo',NULL),('m','b'),(6,'j'),('bar','qux'),(NULL,NULL);
DELETE FROM t1 WHERE a <=> 'm' OR b <=> NULL;
create table t1 ( a2 time not null, a1 varchar(1) not null) engine=myisam;
create table t2 ( i1 int not null, i2 int not null) engine=myisam;
insert into t2 values (0,0);
select 1 from t2 where (i1, i2) in (select count((a1 div '1')), bit_or(a2) over () from t1);
create table t1 (a1 int, a2 decimal(10,0) not null) engine=myisam;
select min(1 mod a1), bit_or(a2) over () from t1;
SET GLOBAL auto_increment_increment=3;
CREATE SEQUENCE s START WITH -3 MINVALUE=-1000 INCREMENT 0;
SET GLOBAL init_slave='SELECT 1';
SET GLOBAL profiling=ON;
CHANGE MASTER TO master_host="0.0.0.0";
START SLAVE SQL_THREAD;
SELECT 1;
# mysqld options required for replay: --log-bin 
USE test;
SET GLOBAL wsrep_forced_binlog_format=1;
CREATE TABLE t1(c INT PRIMARY KEY) ENGINE=MEMORY;
INSERT DELAYED INTO t1 VALUES(),(),();
SELECT SLEEP(1);

# mysqld options required for replay: --log-bin
SET SQL_MODE='';
SET GLOBAL wsrep_forced_binlog_format='STATEMENT';
HELP '%a';
CREATE TABLE t (c CHAR(8) NOT NULL) ENGINE=MEMORY;
SET max_session_mem_used = 50000;
REPLACE DELAYED t VALUES (5);
HELP 'a%';

# mysqld options required for replay: --log-bin 
SET SQL_MODE='';
CREATE TABLE t (c INT) ENGINE=MEMORY;
SET GLOBAL wsrep_forced_binlog_format='STATEMENT';
INSERT DELAYED INTO t VALUES(1);
SET GLOBAL wsrep_start_position='00000000-0000-0000-0000-000000000000:-2';
SET SESSION session_track_user_variables=1;
SET @inserted_value=REPEAT(1,16777180);  # Only crashes when >=16777180 (max = 16777216)
USE test;
CREATE TABLE t(c INT,KEY(c));
INSERT INTO t VALUES(0);
INSERT INTO t VALUES(0);
set global innodb_file_per_table=OFF;
set global innodb_limit_optimistic_insert_debug=2;
set global innodb_change_buffering_debug=1;
CREATE TABLE t2(a INT) PARTITION BY HASH (a) PARTITIONS 13;
DROP TABLE t2;
INSERT INTO t VALUES(0);
ALTER TABLE t CHANGE COLUMN c c BINARY(1);
USE test;
SET SQL_MODE='';
SET SESSION insert_id=0;
CREATE TABLE t (a INT AUTO_INCREMENT KEY) PARTITION BY HASH (a) PARTITIONS 3;
INSERT INTO t VALUES ('');
USE test;
CREATE TABLE t1(bitk bit);
XA BEGIN '0';
INSERT INTO t1 VALUES(1);
BINLOG ' O1ZVRw8BAAAAZgAAAGoAAAAAAAQANS4xLjIzLXJjLWRlYnVnLWxvZwAAAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAAA7VlVHEzgNAAgAEgAEBAQEEgAAUwAEGggAAAAICAgC ';

CREATE TABLE t2 (c1 INT);
XA START 0x7465737462,0x2030405060,0xb;
INSERT INTO t2 VALUES (8513.33);
BINLOG ' mSKWVg8BAAAAdwAAAHsAAAAAAAQANS44LjAtbTE3LWRlYnVnLWxvZwAAAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAACZIpZWEzgNAAgAEgAEBAQEEgAAXwAEGggAAAAICAgCAAAACgoKKioAEjQA AYzz6oU= '/*!*/;

CREATE TABLE t (b INT);
XA START 'a';
INSERT INTO t VALUES(0);
BINLOG ' SOgWTg8BAAAAbgAAAHIAAAAAAAQANS42LjMtbTUtZGVidWctbG9nAAAAAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAABI6BZOEzgNAAgAEgAEBAQEEgAAVgAEGggAAAAICAgCAAAAAAVAYI8=';

CREATE TABLE t (c INT);
XA START 'a';
SELECT * FROM t WHERE c=0;
BINLOG ' O1ZVRw8BAAAAZgAAAGoAAAAAAAQANS4xLjIzLXJjLWRlYnVnLWxvZwAAAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAAA7VlVHEzgNAAgAEgAEBAQEEgAAUwAEGggAAAAICAgC ';
USE test;
CREATE TABLE t1(a CHAR BINARY);
SELECT(SELECT a FROM (SELECT 1 FROM t1)e ORDER BY (@f:=a)) FROM t1 GROUP BY a;
CREATE TABLE t1 (a INT) ENGINE=InnoDB;
INSERT INTO t1 VALUES (0),(NULL),(0);
CREATE TABLE t2 (f INT, s DATE, e DATE, PERIOD FOR p(s,e), UNIQUE(f, p WITHOUT OVERLAPS)) ENGINE=InnoDB;
INSERT INTO t2 VALUES (NULL,'2026-02-12','2036-09-16'), (NULL,'2025-03-09','2032-12-05');
UPDATE IGNORE t1 JOIN t2 SET f = a;

# mysqld options that were in use during reduction: --sql_mode=ONLY_FULL_GROUP_BY --performance-schema --performance-schema-instrument='%=on' --default-tmp-storage-engine=MyISAM --innodb_file_per_table=1 --innodb_flush_method=O_DIRECT
USE test;
CREATE TABLE t1(a BIGINT UNSIGNED) ENGINE=InnoDB;
set global innodb_limit_optimistic_insert_debug = 2;
INSERT INTO t1 VALUES(12979);
ALTER TABLE t1 algorithm=inplace, ADD f DECIMAL(5,2);
insert into t1 values (5175,'abcdefghijklmnopqrstuvwxyz');
DELETE FROM t1;
SELECT HEX(a), HEX(@a:=CONVERT(a USING utf8mb4)), HEX(CONVERT(@a USING utf16le)) FROM t1; ;
SET GLOBAL  sort_buffer_size=0;
SET SESSION sort_buffer_size=2097152;
SET SESSION max_sort_length =0;
USE test;
CREATE TEMPORARY TABLE t1(c1 NUMERIC(65)UNSIGNED ZEROFILL,c2 DECIMAL(0,0) UNSIGNED,c3 NUMERIC(1)) ENGINE=MEMORY;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;

set sort_buffer_size=20971;
SET max_sort_length=4;
CREATE TEMPORARY TABLE t1(c1 DECIMAL(65) UNSIGNED ,c2 DECIMAL(10,0) UNSIGNED,c3 DECIMAL(1))ENGINE=MEMORY;
INSERT INTO t1 SELECT 0, 0, 0 from seq_1_to_10000;
SELECT * FROM t1 ORDER BY c1,c2;

SET @start_global_value =@@global.low_priority_updates;
SET @@global.sort_buffer_size =@start_global_value;
SET SESSION sort_buffer_size =DEFAULT;
SET @@SESSION.max_sort_length=0;
USE test;
CREATE TEMPORARY TABLE t1(c1 NUMERIC(65)UNSIGNED ZEROFILL,c2 DECIMAL(0,0) UNSIGNED,c3 NUMERIC(1)) ENGINE=MEMORY;
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 VALUES(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0),(0,0,0);
INSERT INTO t1 SELECT * FROM t1;
SELECT * FROM t1 ORDER BY c1,c2;
USE test;
CREATE TEMPORARY TABLE t(a INT,b INT);
SET SESSION in_predicate_conversion_threshold=2;
SELECT 1 FROM t WHERE ROW(a,(a,a)) IN ((1,(1,1)),(2,(2,1)));
ALTER TABLE mysql.general_log ENGINE=Aria;
SET GLOBAL log_output='TABLE';
SET GLOBAL general_log=TRUE;
SET SESSION OPTIMIZER_SWITCH="derived_merge=OFF";
# Causes hangs on 10.4-10.5.4, and hangs on 10.1-10.3 on shutdown
USE test;
SET GLOBAL aria_group_commit=1;
SET GLOBAL aria_group_commit_interval=CAST(-1 AS UNSIGNED INT);
CREATE TABLE t (c INT KEY) ENGINE=Aria;
CREATE USER 'a' IDENTIFIED BY 'a';
# Shutdown
USE test;
SET SESSION OPTIMIZER_SWITCH="index_merge_sort_intersection=ON";
SET SESSION sort_buffer_size=2048;
CREATE TABLE t1(c1 VARCHAR(2049) BINARY PRIMARY KEY,c2 INT,c3 INT,INDEX(c2),UNIQUE (c1));
SELECT * FROM t1 WHERE c1>=69 AND c1<'' AND c2='';
# Causes hangs on 10.5.4 shutdown
USE test;
CREATE TABLE t(a INT);
XA START '0';
SET pseudo_slave_mode=1;
INSERT INTO t VALUES(7050+0.75);
XA PREPARE '0';
XA END '0';
XA PREPARE '0';
TRUNCATE TABLE t;
# Shutdown to observe hang (mysqladmin shutdown will hang)
USE test;
SET time_zone="-02:00";
CREATE TABLE t(c TIMESTAMP KEY);
SELECT * FROM t WHERE c='2010-00-01 00:00:00';
USE test;
CREATE FUNCTION f (i MEDIUMINT(254) UNSIGNED ZEROFILL) RETURNS MEDIUMINT ZEROFILL READS SQL DATA RETURN CONCAT('0000000000000',i);
SELECT f(1.e+1);
USE test;
CREATE TABLE t(c INT, c2 GEOMETRY NOT NULL, c3 GEOMETRY NOT NULL);
PREPARE p FROM "UPDATE t SET b = 1";

CREATE OR REPLACE TABLE t1(c INT, c2 INT NOT NULL, c3 INT NOT NULL);
PREPARE p FROM "UPDATE t SET b = 1";
SELECT 0 FROM (SELECT 0) t01, (SELECT 0) t02, (SELECT 0) t03, (SELECT 0) t04, (SELECT 0) t05, (SELECT 0) t06, (SELECT 0) t07, (SELECT 0) t08, (SELECT 0) t09, (SELECT 0) t10, (SELECT 0) t11, (SELECT 0) t12, (SELECT 0) t13, (SELECT 0) t14, (SELECT 0) t15, (SELECT 0) t16, (SELECT 0) t17, (SELECT 0) t18, (SELECT 0) t19, (SELECT 0) t20, (SELECT 0) t21, (SELECT 0) t22, (SELECT 0) t23, (SELECT 0) t24, (SELECT 0) t25, (SELECT 0) t26, (SELECT 0) t27, (SELECT 0) t28, (SELECT 0) t29, (SELECT 0) t30, (SELECT 0) t31, (SELECT 0) t32, (SELECT 0) t33, (SELECT 0) t34, (SELECT 0) t35, (SELECT 0) t36, (SELECT 0) t37, (SELECT 0) t38, (SELECT 0) t39, (SELECT 0) t40, (SELECT 0) t41, (SELECT 0) t42, (SELECT 0) t43, (SELECT 0) t44, (SELECT 0) t45, (SELECT 0) t46, (SELECT 0) t47, (SELECT 0) t48, (SELECT 0) t49, (SELECT 0) t50, (SELECT 0) t51, (SELECT 0) t52, (SELECT 0) t53, (SELECT 0) t54, (SELECT 0) t55, (SELECT 0) t56, (SELECT 0) t57, (SELECT 0) t58, (SELECT 0) t59, (SELECT 0) t60, (SELECT 0) t61;
CHANGE MASTER TO MASTER_USER='root', MASTER_SSL=0, MASTER_SSL_CA='', MASTER_SSL_CERT='', MASTER_SSL_KEY='', MASTER_SSL_CRL='', MASTER_SSL_CRLPATH='';
CHANGE MASTER TO MASTER_USER='root', MASTER_PASSWORD='', MASTER_SSL=0;
SELECT RIGHT('a', -10000000000000000000);

SELECT LPAD (0,-18446744073709551615,0);
SELECT RPAD (0,-18446744073709551615,0);

SELECT LOCATE (0,0,-18446744073709551615);

SELECT INSERT (0,18446744073709551616,1,0);

SELECT HEX(COLUMN_CREATE (1,99999999999999999999999999999 AS INT));

SELECT COLUMN_GET (COLUMN_CREATE (1,99999999999999999999999999999 AS DECIMAL),1 AS INT);

SELECT 0 + (10101010101010101010101010101010101010101010101010101010101010101<<4);
SET NAMES gbk;
SET SQL_MODE='';
CREATE USER очень_очень_очень_очень_длинный_юзер@localhost;
SELECT * FROM INFORMATION_SCHEMA.user_privileges WHERE GRANTEE LIKE "'abcdefghijklmnopqrstuvwxyz'%";
# mysqld options required for replay: --log-bin
USE test;
#SET SQL_MODE='';
CREATE TABLE t1 (a INT, KEY(a)) ENGINE=MyISAM;
CREATE TABLE t2 (a INT, b INT) ENGINE=InnoDB;
XA START 'a';
INSERT INTO t2 VALUES (1);
SAVEPOINT sp;
INSERT INTO t2 VALUES (1,1);
ROLLBACK TO sp;
INSERT INTO t1 VALUES (1);
XA END 'a';
XA PREPARE 'a';

# mysqld options required for replay: --log-bin
CREATE TABLE t1 (a INT) ENGINE=MyISAM;
INSERT INTO t1 VALUES (1),(2);
CREATE TABLE t2 (id INT PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO t2 VALUES (1),(2);
XA BEGIN 'x';
REPLACE INTO t1 SELECT * FROM t1;
REPLACE INTO t2 SELECT * FROM t2;
XA END 'x';
XA PREPARE 'x';
USE test;
SET SQL_MODE='';
SET AUTOCOMMIT=0;
CREATE TABLE t(c CHAR (0));
SET STATEMENT gtid_domain_id=0 FOR INSERT INTO t VALUES(0),(0);
SET GLOBAL init_connect="SET @a=0";
USE test;
SET SQL_MODE='';
SET @@GLOBAL.innodb_trx_rseg_n_slots_debug=1;
CREATE TABLE t (b VARCHAR(10) NOT NULL UNIQUE) ENGINE=InnoDB;
INSERT INTO t VALUES (12662),(54592);
SET GLOBAL innodb_monitor_enable='buffer_flush_batches';
INSERT INTO t VALUES (2822.75);
CREATE TABLE t2(a INT NOT NULL PRIMARY KEY, b INT) ENGINE=InnoDB SELECT * FROM t LOCK IN SHARE MODE;
INSERT INTO t VALUES (25215);
CREATE TEMPORARY TABLE m(a INT) ENGINE=INNODB;
SELECT SLEEP(5);
SELECT SLEEP(5);
# Then exit CLI, and shutdown using mysqladmin shutdown
USE test;
CREATE TABLE t (a CHAR(198));
ALTER TABLE t CHANGE COLUMN a a CHAR(220) BINARY;
ALTER TABLE t ADD COLUMN b INT FIRST;

CREATE TABLE t1 (a TEXT CHARSET utf8, b INT) ENGINE=InnoDB CHARSET utf8mb4;
ALTER TABLE t1 MODIFY a TEXT AFTER b;

USE test;
CREATE TABLE t (a TEXT,b CHAR(255) PRIMARY KEY) CHARSET=utf8;
SET GLOBAL innodb_default_row_format = 0;
ALTER TABLE t ADD COLUMN c INT FIRST;

USE test;
CREATE TABLE t (c CHAR(255), PRIMARY KEY (c)) CHARSET=utf8;
ALTER TABLE t ADD COLUMN b INT FIRST;
SET GLOBAL INNODB_DEFAULT_ROW_FORMAT = 0;
ALTER TABLE t ADD COLUMN a INT FIRST;
USE test;
SET SQL_MODE='';
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TABLE t (a INT) ENGINE=InnoDB;
ALTER TABLE t ADD COLUMN b INT FIRST;
INSERT INTO t VALUES (5,7),(8,9),(4,1);
DELETE FROM t;
SELECT GROUP_CONCAT(a) FROM t;
SELECT GROUP_CONCAT(a) FROM t;  # Will likely crash on this one
SELECT GROUP_CONCAT(a) FROM t;  # Or on this one
SELECT GROUP_CONCAT(a) FROM t;
SELECT GROUP_CONCAT(a) FROM t;
SELECT GROUP_CONCAT(a) FROM t;
SELECT GROUP_CONCAT(a) FROM t;
SELECT GROUP_CONCAT(a) FROM t;
SELECT GROUP_CONCAT(a) FROM t;
SELECT GROUP_CONCAT(a) FROM t;
SELECT GROUP_CONCAT(a) FROM t;
SELECT GROUP_CONCAT(a) FROM t;
SELECT GROUP_CONCAT(a) FROM t;
USE test;
SET SQL_MODE='';
CREATE TABLE t(a INT,KEY (a)) PARTITION BY KEY (a);
INSERT INTO t VALUES(0),(0);
DELETE FROM t WHERE a=(SELECT a FROM t);
VALUES ((VALUES(1)));

VALUES ((SELECT 1));
USE test;
CREATE TABLE t(a INT) PARTITION BY RANGE(a) SUBPARTITION BY HASH(a) (PARTITION p VALUES LESS THAN (5) (SUBPARTITION sp, SUBPARTITION sp1), PARTITION p1 VALUES LESS THAN MAXVALUE (SUBPARTITION sp2, SUBPARTITION sp3));
ALTER TABLE t DROP PARTITION p;

USE test;
CREATE TABLE t (c1 MEDIUMINT,name VARCHAR(30), purchased DATE) PARTITION BY RANGE(YEAR(purchased)) SUBPARTITION BY HASH(TO_DAYS(purchased)) (PARTITION p0 VALUES LESS THAN (1990) (SUBPARTITION s0, SUBPARTITION s1), PARTITION p1 VALUES LESS THAN (2000) (SUBPARTITION s2, SUBPARTITION s3), PARTITION p2 VALUES LESS THAN MAXVALUE (SUBPARTITION s4, SUBPARTITION s5));
ALTER TABLE t drop partition p2;

USE test;
CREATE TABLE t (c INT, d DATE) PARTITION BY RANGE(YEAR(d)) SUBPARTITION BY HASH(TO_DAYS(d)) (PARTITION p0 VALUES LESS THAN (1990) (SUBPARTITION s0, SUBPARTITION s1), PARTITION p1 VALUES LESS THAN MAXVALUE (SUBPARTITION s4, SUBPARTITION s5));
ALTER TABLE t DROP PARTITION p2;  # Error 1507
USE test;
CREATE TABLE t(id INT);
UPDATE t FOR PORTION OF APPTIME FROM (SELECT s FROM t LIMIT 1) TO h() SET t.id=t.id + 5;
USE test;
CREATE TABLE t (FTS_DOC_ID BIGINT UNSIGNED PRIMARY KEY,c2 VARCHAR(200),FULLTEXT(c2));
ALTER TABLE t PACK_KEYS=0;
USE test;
CREATE TABLE t (i INT, j INT, KEY(i)) ENGINE=InnoDB;
SELECT FIRST_VALUE(j) OVER (ORDER BY 0 + (SELECT FIRST_VALUE(upper.j) OVER (ORDER BY upper.j) FROM t LIMIT 1)) FROM t AS upper;

USE test;
CREATE TABLE t (i INT, j INT);
SELECT LAST_VALUE(j) OVER (ORDER BY 0 + (SELECT FIRST_VALUE(upper.j) OVER (ORDER BY upper.j) FROM t LIMIT 1)) FROM t AS upper;
USE test;
CREATE TABLE t1 (f1 INT) ENGINE=Aria;
CREATE TABLE t2 (f2 INT) ENGINE=Aria;
LOCK TABLES t2 WRITE, t1 WRITE;
INSERT INTO t1 VALUES (1);
CREATE TRIGGER ai AFTER INSERT ON t1 FOR EACH ROW UPDATE t1 SET v=1 WHERE b=new.a;
UNLOCK TABLES;

# Further testcases may not be deterministic 
DROP DATABASE test;CREATE DATABASE test;USE test;
SET SQL_MODE='';
SET SESSION storage_engine=Aria;
CREATE TABLE t3 (c1 DATE,c2 NUMERIC(65) UNSIGNED ZEROFILL,c3 DECIMAL(2)) ENGINE=Aria;
CREATE TABLE t2 (c1 VARCHAR(100)) ENGINE=Aria;
CREATE TABLE t1 (c1 INTEGER);
LOCK TABLES t3 WRITE,t2 WRITE,t1 WRITE;
INSERT INTO t1 VALUES (CONVERT(_ucs2 0x062C064706270646 USING utf8));
CREATE TRIGGER ai AFTER INSERT ON t1 FOR EACH ROW UPDATE t1 SET v=1 WHERE b=new.a;
INSERT INTO t1 VALUES (CONVERT(_ucs2 0x062C064706270646 USING utf8));
DROP DATABASE test;CREATE DATABASE test;USE test;
SET SQL_MODE='';
SET SESSION storage_engine=Aria;
CREATE TABLE t3 (c1 DATE,c2 NUMERIC(65) UNSIGNED ZEROFILL,c3 DECIMAL(2)) ENGINE=Aria;
CREATE TABLE t2 (c1 VARCHAR(100)) ENGINE=Aria;
CREATE TABLE t1 (c1 INTEGER);
LOCK TABLES t3 WRITE,t2 WRITE,t1 WRITE;
INSERT INTO t1 VALUES (CONVERT(_ucs2 0x062C064706270646 USING utf8));
CREATE TRIGGER ai AFTER INSERT ON t1 FOR EACH ROW UPDATE t1 SET v=1 WHERE b=new.a;
INSERT INTO t1 VALUES (CONVERT(_ucs2 0x062C064706270646 USING utf8));

DROP DATABASE test; CREATE DATABASE test; USE test;
SET default_storage_engine=InnoDB;
CREATE FUNCTION char not null(f1 char not null) returns char not null return f1;
CREATE TABLE t1 (c1 DECIMAL(1,1) PRIMARY KEY,c2 DECIMAL(40,30) UNSIGNED,c3 MEDIUMINT(1) ZEROFILL) ENGINE=Aria;
LOCK TABLES mysql.time_zone READ, mysql.proc READ, t1 WRITE;
SET @@global.max_statement_time = 0.123456;
INSERT INTO t1  (c1,c2,c3) VALUES ('a','a',8), ('a','a',2), ('a','b',3), ('a','c',4), ('a','d',5);
select insert('hello', -1, 1, 'hi');
CREATE TRIGGER t_after_insert AFTER INSERT ON t1 FOR EACH ROW SET @bug42188 = 10;
UNLOCK TABLES;
SELECT SLEEP(5);

DROP DATABASE transforms;
CREATE DATABASE transforms;
USE test;
select 1 FROM t1  order by t1.b;
SET @@SESSION.OPTIMIZER_SWITCH="subquery_cache=OFF";
SET @@SESSION.OPTIMIZER_SWITCH="index_merge_intersection=ON";
set session default_storage_engine='Aria';
SET @@GLOBAL.OPTIMIZER_SWITCH="use_index_extensions=ON";
INSERT INTO t3 VALUES(NULL,1,2,3,4,5,6);
SET @@GLOBAL.OPTIMIZER_SWITCH="mrr_sort_keys=ON";
SET @@SESSION.OPTIMIZER_SWITCH="derived_with_keys=ON";
CREATE TABLE t1(a INT, KEY (a)) ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=1 ENGINE=RocksDB;
CREATE TABLE t1( a VARCHAR(65532) COLUMN_FORMAT COMPRESSED ) ROW_FORMAT = COMPRESSED ENGINE=RocksDB;
lock TABLE t1 write, mysql.event read;
insert into t2 values (53698);
insert into t1 values ('a'),('a ');
SELECT @@log_warnings = @@global.log_warnings;
SET @@SESSION.OPTIMIZER_SWITCH="condition_pushdown_from_having=OFF";
SET @@SESSION.OPTIMIZER_SWITCH="index_merge_sort_union=ON";
SET GLOBAL innodb_monitor_reset='buffer_flush_avg_time';
CREATE TABLE t1 (c1 VARCHAR(10));
CREATE TRIGGER t1_bi BEFORE INSERT ON t1 FOR EACH ROW INSERT INTO t1  VALUES (NEW.i);
CREATE TABLE t1 (c1 varchar(100)) ENGINE=TokuDB;
UNLOCK TABLES;
UNLOCK TABLES;
UNLOCK TABLES;
UNLOCK TABLES;
UNLOCK TABLES;
UNLOCK TABLES;
SELECT 1;
SELECT SLEEP(5);

# mysqld options required for replay: --log-bin --sql_mode=ONLY_FULL_GROUP_BY --max_allowed_packet=33554432 --maximum-bulk_insert_buffer_size=1M --maximum-join_buffer_size=1M --maximum-max_heap_table_size=1M --maximum-max_join_size=1M --maximum-myisam_max_sort_file_size=1M --maximum-myisam_mmap_size=1M --maximum-myisam_sort_buffer_size=1M --maximum-optimizer_trace_max_mem_size=1M --maximum-preload_buffer_size=1M --maximum-query_alloc_block_size=1M --maximum-query_prealloc_size=1M --maximum-range_alloc_block_size=1M --maximum-read_buffer_size=1M --maximum-read_rnd_buffer_size=1M --maximum-sort_buffer_size=1M --maximum-tmp_table_size=1M --maximum-transaction_alloc_block_size=1M --maximum-transaction_prealloc_size=1M --log-output=none
USE test;
SET @@SESSION.OPTIMIZER_SWITCH="mrr_sortks=ON";
create or replace table t1 (f1 int,key(f1)) engine=Aria;
LOCK TABLES mysql.time_zone READ,mysql.proc READ,t1 WRITE;
INSERT INTO t1 VALUES(''),(''),('až'),('cčc'),('ggᵷg'),('¢¢');
CREATE TRIGGER tr1 BEFORE INSERT ON t1 FOR EACH ROW SET @aux = 1;
UNLOCK TABLES; ;
UNLOCK TABLES; ;
CREATE TABLE t1 (pk INT NOT NULL, c1 VARCHAR(1)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (1,NULL),(15,'o'),(16,'x'),(19,'t'),(35,'k'),(36,'h'),(42,'t'),(43,'h'),(53,'l'),(62,'a'),(71,NULL),(79,'u'),(128,'y'),(129,NULL),(133,NULL);
CREATE TABLE t2 (i1 INT, c1 VARCHAR(1) NOT NULL, KEY c1 (c1), KEY i1 (i1)) ENGINE=InnoDB;
INSERT INTO t2 VALUES (1,'1'),(NULL,'1'),(42,'t'),(NULL,'1'),(79,'u'),(NULL,'1'),(NULL,'4'),(NULL,'4'),(NULL,'1'),(NULL,'u'),(2,'1'),(NULL,'w');
INSERT INTO t2 SELECT * FROM t2;
SELECT * FROM t1 WHERE t1.c1 NOT IN (SELECT t2.c1 FROM t2, t1 AS a1 WHERE t2.i1=t1.pk AND t2.i1 IS NOT NULL);

SET sql_mode='';
SET join_cache_level=3;
CREATE TABLE t (c BIGINT, d INT, KEY c(c), KEY d(d)) ENGINE=InnoDB;
INSERT INTO t VALUES (0,0),(1,2),(1,3),(2,0),(3,0),(4,6),(5,0);
SELECT * FROM t,t AS b WHERE t.c=0 AND t.d=b.c AND t.c=b.d;
# mysqld options required for replay: --log-bin
USE test;
SET autocommit=0;
CREATE TABLE t1 (c INT) ENGINE=MyISAM;
SET GLOBAL gtid_slave_pos="0-1-100";
INSERT INTO t1 VALUES (0);
DROP TABLE not_there;

SET autocommit=0;
SET GLOBAL gtid_slave_pos= "0-1-50";
SAVEPOINT a;
USE test;
SET SQL_MODE='';
SET optimizer_switch='subquery_cache=off';
CREATE TABLE t1 (a INT,b INT);
INSERT INTO t1 VALUES (0,0),(0,0);
SELECT (SELECT DISTINCT 1 FROM t1 t1i GROUP BY t1i.a ORDER BY MAX(t1o.b)) FROM t1 AS t1o;
CREATE PROCEDURE p1(min INT,max INT) BEGIN DECLARE DONE INT DEFAULT FALSE;
USE test;
CREATE TABLE t(a INT) PARTITION BY KEY (a);
CREATE TRIGGER tr AFTER UPDATE ON t FOR EACH ROW DROP SERVER IF EXISTS s;
INSERT INTO t VALUES(0);
UPDATE t SET a = 1;
USE test;
CREATE TABLE t(c CHAR(255) CHARACTER SET UTF32, KEY k1(c)) ENGINE=MyISAM;
INSERT INTO t VALUES(100000);
ALTER TABLE t ENGINE=InnoDB;
USE test;
SET collation_connection='utf16_general_ci';
SET sql_buffer_result=1;
CREATE TABLE t(c INT);
INSERT INTO t VALUES(NULL);
SELECT PASSWORD(c) FROM t;
SET @@session.slow_query_log = ON;
alter table mysql.slow_log engine=Aria;
SET @@global.slow_query_log = 1;
SET @@session.long_query_time = 0;
SET @@global.log_output = 'TABLE,,FILE,,,';
SELECT SLEEP(5);
USE test;
CREATE TABLE t1 (pk INT, f GEOMETRY NOT NULL, PRIMARY KEY (pk), UNIQUE KEY (f(8))) ENGINE=InnoDB;
ALTER TABLE t1 DROP PRIMARY KEY;
INSERT INTO t1 VALUES (1, GEOMFROMTEXT('POINT(1 1)'));
SELECT * FROM t1 ORDER BY pk;
SET SQL_MODE='';
USE test;
SET STATEMENT max_statement_time=20 FOR BACKUP LOCK test.t1;
CREATE TABLE IF NOT EXISTS t3 (c1 CHAR(1) BINARY,c2 SMALLINT(10),c3 NUMERIC(1,0), PRIMARY KEY(c1(1))) ENGINE=InnoDB;
LOCK TABLES t3 AS a2 WRITE, t3 AS a1 READ LOCAL;
UNLOCK TABLES;
DROP TABLE t1,t2,t0;
# Shutdown (using mysqladmin shutdown), observe crash (or hang) during shutdown

USE test;
SET SQL_MODE='';
SET STATEMENT max_statement_time=180 FOR BACKUP LOCK test.t;
CREATE TABLE t (c1 INT PRIMARY KEY) ENGINE=Aria;
LOCK TABLES t AS a2 WRITE, t AS a1 READ LOCAL;
UNLOCK TABLES;
DROP TABLE t1,t2,t0;
# Shutdown (using mysqladmin shutdown), observe crash (or hang) during shutdown
SET SESSION max_heap_table_size=16384;
WITH RECURSIVE q (b) AS (SELECT 1 UNION ALL SELECT 1+b FROM q WHERE b<2000) SELECT MIN(q.b),MAX(q.b),AVG(q.b) FROM q, q AS q1;

USE test;
CREATE TABLE t (a INT) ROW_FORMAT=compressed, ENGINE=InnoDB;
ALTER TABLE t ADD COLUMN c2 INTEGER COMMENT 'a';
SET tmp_table_size=100;
INSERT INTO t  VALUES (94, 46), (31, 438), (61, 152), (78, 123), (88, 411), (122, 118), (0, 177), (75, 42), (108, 67), (79, 349), (59, 188), (68, 206), (49, 345);
SELECT * FROM ( SELECT * FROM t UNION SELECT * FROM t) a,(SELECT * FROM t UNION SELECT * FROM t) b;

USE test;
SET SQL_MODE='';
SET SESSION tmp_table_size=True;
CREATE TABLE t (f INT(10) UNSIGNED NOT NULL) ENGINE=InnoDB;
INSERT INTO t VALUES (CONVERT(_ucs2 0x062F06390648062A0650 USING utf8));
insert INTO t SELECT REPEAT('abcdefghijklmnopqrstuvwxyz',100);
INSERT INTO t VALUES(0xAAB6);
CREATE TEMPORARY TABLE t (e INT, f INT, PRIMARY KEY (f)) ENGINE=InnoDB;
SET SESSION OPTIMIZER_SWITCH="derived_merge=OFF";
DROP TABLE t;
SELECT 1 FROM ((SELECT * FROM (SELECT * FROM t) AS a) AS a, (SELECT * FROM t) AS b);

# MDEV-22104
SET max_heap_table_size= 1048576;
CREATE TABLE t1 (a INT);
INSERT INTO t1 VALUES (1),(2);
CREATE TABLE t2 (a INT,  b INT, c VARCHAR(3), d VARCHAR(35));
INSERT INTO t2 (a) SELECT seq FROM seq_1_to_130;
SET optimizer_switch = 'derived_merge=off';
SELECT * FROM t1, ( SELECT t2a.* FROM t2 AS t2a, t2 AS t2b ) AS sq;
USE TEST;
CREATE OR REPLACE TABLE t1 (x INT, y INT) WITH SYSTEM VERSIONING;
CREATE TRIGGER TRG BEFORE INSERT ON t1 FOR EACH ROW SET @a:=1;
SET @@TMP_DISK_TABLE_SIZE = 100;
SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='test' AND TABLE_NAME='t1';

CREATE TABLE t1 (a INT);
CREATE TRIGGER tr1 BEFORE INSERT ON t1 FOR EACH ROW SET @a=1;
CREATE TRIGGER tr2 BEFORE DELETE ON t1 FOR EACH ROW SET @b=1;
SET TMP_DISK_TABLE_SIZE= 1024;
SHOW TRIGGERS;

# Sporadic, repeat 100+
CREATE DATABASE transforms;
CREATE TABLE t1(c1 MEDIUMINT NULL, c2 BINARY(25) NOT NULL, c3 BIGINT(4) NULL, c4 BINARY(15) NOT NULL PRIMARY KEY, c5 MEDIUMINT NOT NULL UNIQUE KEY,c6 FIXED(10,8) NOT NULL DEFAULT 3.141592);
CREATE TRIGGER tr1_bu BEFORE UPDATE ON t1 FOR EACH ROW SET @a:=3;
create trigger trg1 before insert on t1 for each row set @a:= 1;
SET @@session.tmp_disk_table_size = False;
CREATE TABLE q(b TEXT CHARSET latin1, fulltext(b)) engine=TokuDB;
SELECT * FROM INFORMATION_SCHEMA.TRIGGERS WHERE trigger_name = 'trg1'; ;

# Sporadic, repeat 100+
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE t (c1 MEDIUMINT NULL, c2 BINARY (25) NOT NULL, c3 BIGINT (4) NULL, c4 BINARY (15) NOT NULL PRIMARY KEY, c5 MEDIUMINT NOT NULL UNIQUE KEY,c6 FIXED (10,8) NOT NULL DEFAULT 1);
CREATE TRIGGER trb BEFORE UPDATE ON t FOR EACH ROW SET @a:=3;
CREATE TRIGGER tr BEFORE INSERT ON t FOR EACH ROW SET @a:=1;
SET SESSION tmp_disk_table_size=false;
CREATE TABLE q (b TEXT CHARSET latin1, fullTEXT (b)) ENGINE=TokuDB;
SELECT * FROM INFORMATION_SCHEMA.TRIGGERS WHERE TRIGGER_name='tr';

# Sporadic, repeat 2000+
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE t (a TEXT, FULLTEXT KEY(a)) ENGINE = Aria;
CREATE TRIGGER t_ai AFTER INSERT ON t FOR EACH ROW call bug14233_3 ();
ALTER TABLE mysql.help_KEYword ENGINE=MEMORY;
CREATE TABLE t (a decimal (10,2)) ( (SELECT * FROM t WHERE a <=3));
CREATE TEMPORARY TABLE t (c1 INT) ENGINE=MyISAM;
CREATE TRIGGER t_TRIGGER BEFORE INSERT ON t FOR EACH ROW DELETE FROM s WHERE id=1000000;
RENAME TABLE t2 TO t,t2 TO t3,t2 TO t3;
SET GLOBAL TABLE_open_cache = -1;
SET SESSION tmp_disk_TABLE_size = True;
SELECT TRIGGER_name, CREATEd, action_order FROM information_schema.TRIGGERs WHERE TRIGGER_schema='test';


# mysqld options required for replay:  --tmp-disk-table-size=254
CREATE DATABASE mysqldump_test_db;
USE mysqldump_test_db;
CREATE TABLE t0 (f0 CHAR(0));
CREATE TRIGGER tr0 AFTER INSERT ON t0 FOR EACH ROW SET @test_var=0;
SELECT * FROM information_schema.TRIGGERS;
CREATE TABLE t1 (s TIMESTAMP);
INSERT INTO t1 VALUES ('2033-06-06'),('2015-09-10');
SELECT NULLIF( s, NULL ) AS f FROM t1 GROUP BY s WITH ROLLUP;

USE test;
SET SQL_MODE='';
CREATE TABLE t (a TIMESTAMP, b DATETIME, c TIME) ENGINE=InnoDB;
INSERT INTO t VALUES (NULL,NULL,NULL);
SELECT CASE a WHEN a THEN a END FROM t GROUP BY a WITH ROLLUP;
SET SQL_MODE='';
SET @cmd="ALTER TABLE non.existing ENGINE=NDB";
PREPARE stmt FROM @cmd;
EXECUTE stmt;
EXECUTE stmt;

SET sql_mode='';
CREATE PROCEDURE p1 (IN i INT) ALTER TABLE t ENGINE=none;
CALL p1 (1);
CALL p1 (1);

SET sql_mode='';
SET @c:="ALTER TABLE t ENGINE=none";
PREPARE s FROM @c;
EXECUTE s;
EXECUTE s;
# Keep testcase repeating until mysqld crashes (one time often if not always enough on debug, optimized may take 2-x attempts)
USE test;
SET SQL_MODE='';
SET SESSION enforce_storage_engine=MEMORY;
SET SESSION optimizer_trace='enabled=on';
CREATE TABLE t1( a INT, b INT, KEY( a ) ) ;
SELECT MAX(a), SUM(MAX(a)) OVER () FROM t1 WHERE a > 10;
SELECT * FROM information_schema.session_variables WHERE variable_name='innodb_ft_min_token_size';
UPDATE t1 SET b=REPEAT(LEFT(b,1),200) WHERE a=1;

USE test;
SET SQL_MODE='';
SET SESSION enforce_storage_engine=MEMORY ;
SET SESSION optimizer_trace='enabled=on';
CREATE TABLE t(a INT, b INT, KEY(a)) ;
SELECT MAX(a), SUM(MAX(a)) OVER () FROM t WHERE a>10;
SELECT * FROM information_schema.session_variables WHERE variable_name='innodb_ft_min_token_size';
UPDATE t SET b=repeat(left(b,1),200) WHERE a=1;

# mysqld options required for replay:  --sql_mode= 
USE test;
SET SESSION enforce_storage_engine=MEMORY;
SET @@SESSION.optimizer_trace='enabled=on';
CREATE TABLE t1( a INT, b INT, KEY( a ) ) ;
select max(a), sum(max(a)) over () FROM t1  where a > 10;
select * from information_schema.session_variables where variable_name='innodb_ft_min_token_size';
update t1 set b=repeat(left(b,1),200) where a=1; ;
# mysqld options required for replay:  --log-bin
SET autocommit = 0;
SET sql_mode='';
CREATE TABLE t (a INT) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t2 (id INT) ENGINE=InnoDB;
SELECT * FROM t LIMIT 1;
CREATE TRIGGER t BEFORE UPDATE ON t FOR EACH ROW SET @a=1;
LOCK TABLES t WRITE CONCURRENT;
INSERT INTO t VALUES (1);
SAVEPOINT B;
BEGIN;
SELECT * FROM non_existing;

# mysqld options required for replay:  --log-bin
SET autocommit=0;
CREATE TABLE t (a TEXT) ENGINE=InnoDB;
CREATE TEMPORARY TABLE tmp (id INT NOT NULL) ENGINE=MEMORY;
SELECT * FROM t WHERE c1 IN ('a','a') ORDER BY c1 DESC LIMIT 2;
CREATE TRIGGER tr BEFORE UPDATE ON t FOR EACH ROW SET @a:=1;
LOCK TABLES t WRITE CONCURRENT;
INSERT INTO t VALUES ('a');
SAVEPOINT B;
BEGIN;
SELECT * FROM t_bigint WHERE id IN ('a', 'a');
# mysqld options required for replay: --log-bin 
RESET MASTER TO 0x7FFFFFFF;
SET @@GLOBAL.binlog_checksum=NONE;

# mysqld options required for replay: --log-bin 
SET @@GLOBAL.OPTIMIZER_SWITCH="orderby_uses_equalities=ON";
RESET MASTER TO 0x7FFFFFFF;
SET @@GLOBAL.binlog_checksum=NONE;
USE test;
BINLOG 'AMqaOw8BAAAAdAAAAHgAAAAAAAQANS42LjM0LTc5LjEtZGVidWctbG9nAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAAAAAAAAEzgNAAgAEgAEBAQEEgAAXAAEGggAAAAICAgCAAAACgoKGRkAAYVx w2w=';
CREATE TABLE t1 (c INT);
BINLOG 'wlZOTxMBAAAAKgAAADwCAAAAACkAAAAAAAEABHRlc3QAAnQxAAIDAwAC wlZOTxcBAAAAJgAAAGICAAAAACkAAAAAAAEAAv/8AgAAAAgAAAA=';

USE test;
BINLOG 'AMqaOw8BAAAAdAAAAHgAAAAAAAQANS42LjM0LTc5LjEtZGVidWctbG9nAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAAAAAAAAEzgNAAgAEgAEBAQEEgAAXAAEGggAAAAICAgCAAAACgoKGRkAAYVx w2w=';
CREATE TABLE t2 (c INT);
BINLOG 'wlZOTxMBAAAAKgAAADwCAAAAACkAAAAAAAEABHRlc3QAAnQxAAIDAwAC wlZOTxcBAAAAJgAAAGICAAAAACkAAAAAAAEAAv/8AgAAAAgAAAA=';

USE test;
BINLOG 'AMqaOw8BAAAAdAAAAHgAAAAAAAQANS42LjM0LTc5LjEtZGVidWctbG9nAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAAAAAAAAEzgNAAgAEgAEBAQEEgAAXAAEGggAAAAICAgCAAAACgoKGRkAAYVx w2w=';
CREATE TABLE t1 (a MEDIUMBLOB, b MEDIUMBLOB, c BIGINT PRIMARY KEY);
BINLOG 'wlZOTxMBAAAAKgAAADwCAAAAACkAAAAAAAEABHRlc3QAAnQxAAIDAwAC wlZOTxcBAAAAJgAAAGICAAAAACkAAAAAAAEAAv/8AgAAAAgAAAA=';
USE test;
CREATE TABLE t(c INT) ENGINE=InnoDB;
ALTER TABLE t DISCARD TABLESPACE;
OPTIMIZE TABLE t;

CREATE TABLE t (a INT) ENGINE=INNODB;
ALTER TABLE t DISCARD TABLESPACE;
ALTER TABLE t ENGINE INNODB;

CREATE TABLE t (a INT) ENGINE=INNODB;
ALTER TABLE t DISCARD TABLESPACE;
ALTER TABLE t ENGINE INNODB;
SET NAMES latin1, COLLATION_CONNECTION=ucs2_general_ci, CHARACTER_SET_CLIENT=cp932;
SELECT SCHEMA_NAME from information_schema.schemata where schema_name='имя_базы_в_кодировке_утф8_длиной_больше_чем_45';

EXECUTE IMMEDIATE CONCAT('SELECT SCHEMA_NAME from information_schema.schemata where schema_name=''' , REPEAT('a',193), '''');

SELECT SCHEMA_NAME from information_schema.schemata where schema_name='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

SELECT SCHEMA_NAME from information_schema.schemata where schema_name=REPEAT('a',193);

SET COLLATION_CONNECTION=eucjpms_bin, SESSION CHARACTER_SET_CLIENT=cp932;
SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.schemata WHERE schema_name='имя_базы_в_кодировке_утф8_длиной_больше_чем_45';

SET @@global.character_set_connection=utf8; 
SET NAMES sjis; 
SET @@collation_connection=DEFAULT;
SELECT SCHEMA_NAME FROM information_schema.schemata WHERE SCHEMA_NAME='имя_базы_в_кодировке_утф8_длиной_больше_чем_45';
USE test;
SET SQL_MODE='';
CREATE TABLE t (v1 VARCHAR (255) AS (c1) PERSISTENT, c1 VARCHAR(50)) COLLATE=latin1_general_ci ENGINE=MyISAM;
INSERT INTO t VALUES(1,0xff00fef0);
CHECKSUM TABLE t EXTENDED;

USE test;
SET SQL_MODE='';
CREATE TABLE t (a BLOB, b BLOB GENERATED ALWAYS AS (a) VIRTUAL) ENGINE=MyISAM;
INSERT INTO t values (1,1),(2,2);
CHECKSUM TABLE t;
USE test;
CREATE TABLE t (a INT PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO t VALUES (2);
SELECT a % 2 AS i, JSON_OBJECTAGG(a,a) FROM t GROUP BY i;

CREATE TABLE t (e INTEGER, a VARCHAR(255), v VARCHAR(255));
INSERT INTO t VALUES (0, 'a1', '1'), (0, 'a2', '2'), (1, 'b1', '3');
SELECT e, JSON_OBJECTAGG(a, v) FROM t GROUP BY e;
# mysqld options required for replay: --log-bin 
SET SQL_MODE='';
USE test;
RESET MASTER TO 5000000000;
CREATE TABLE t (c INT);
XA BEGIN 'a';
INSERT INTO t  VALUES ('a');
XA END 'a';
XA PREPARE 'a';
USE test;
SET SQL_MODE='';
SET SESSION enforce_storage_engine=InnoDB;
CREATE TABLE t(f0 INT) ENGINE=InnoDB;
ALTER TABLE mysql.general_log ENGINE=MyISAM;
XA START '0';
INSERT INTO t VALUES (0);
XA END '0';
XA PREPARE '0';
SET GLOBAL general_log=ON;
USE test;
SET SQL_MODE='';
SET SESSION max_heap_table_size=1;
CREATE TABLE t(a INT,b DOUBLE,c INT,KEY i(b,a)) PARTITION BY HASH(c) PARTITIONS 3;
INSERT INTO t VALUES(0,0,0);
INSERT INTO t(b)VALUES (REPEAT(0,0)),(REPEAT(0,0)),(REPEAT(0,0));
SELECT a FROM t WHERE a NOT IN (SELECT a FROM t);
SET COLLATION_CONNECTION='utf16le_bin';
SET GLOBAL wsrep_provider='/invalid/libgalera_smm.so';
SET GLOBAL wsrep_cluster_address='OFF';
SET GLOBAL wsrep_slave_threads=10;
SELECT 1;

SET NAMES utf8, collation_connection='utf16le_bin';
SET @@global.wsrep_provider='/invalid/libgalera_smm.so';
SET @@global.wsrep_cluster_address=AUTO;
SET GLOBAL wsrep_slave_threads = 2;
SELECT SLEEP(2);
CREATE TABLE t (c INT);
CREATE TABLE t1 (a INT);
INSERT INTO t1 VALUES (1),(2),(3),(4),(5),(6),(7),(8);
INSERT INTO t1 SELECT * FROM t1;
ALTER TABLE t1 ADD SYSTEM VERSIONING;
INSERT INTO t1 VALUES (1),(2),(3),(4);
SET HISTOGRAM_SIZE= 5;
ANALYZE TABLE t1 PERSISTENT FOR ALL;
SELECT * from t1 WHERE row_start IN (SELECT row_end FROM t1);

CREATE TABLE t1 (a INT);
INSERT INTO t1 VALUES (1),(2),(3),(4),(5),(6),(7),(8);
INSERT INTO t1 SELECT * FROM t1;
INSERT INTO t1 VALUES (1),(2),(3),(4);
SET optimizer_use_condition_selectivity=4;
SET histogram_size= 5;
SET histogram_type= DOUBLE_PREC_HB;
SET use_stat_tables='preferably';
ANALYZE TABLE t1 PERSISTENT FOR ALL;
SELECT * from t1 where a=10;

SET use_stat_tables=PREFERABLY;
SET SESSION histogram_size=1;
CREATE TABLE t (c1 INT NOT NULL, c2 CHAR (5)) PARTITION BY HASH (c1);
INSERT INTO t VALUES (1,'a');
ANALYZE TABLE t;
SELECT * FROM t WHERE c2 >= '2000-00-01 00:00:00' AND c2 < '2020-10-10 00:00:00';
USE test;
CREATE TABLE t1 (a INT PRIMARY KEY) ENGINE=Aria ROW_FORMAT=COMPRESSED;
INSERT INTO t1 VALUES(1);
CREATE TEMPORARY TABLE t2(b INT);
EXPLAIN SELECT * FROM t1 WHERE a IN (SELECT MAX(a) FROM t2);

USE test;
SET SQL_MODE='';
CREATE TABLE t1 (c INT PRIMARY KEY) ENGINE=Aria;
CREATE TABLE t2 (d INT);
INSERT INTO t1 VALUES (1);
SELECT c FROM t1 WHERE (c) IN (SELECT MIN(c) FROM t2);

# mysqld options required for replay: --log-bin
USE test;
SET SQL_MODE='ONLY_FULL_GROUP_BY';
CREATE TABLE t3 (c1 DECIMAL(1,1) PRIMARY KEY,c2 DATE,c3 NUMERIC(10) UNSIGNED) ENGINE=Aria;
CREATE TABLE t2 (f1 INTEGER ) ENGINE=Aria;
INSERT INTO t3 VALUES ('','','');
SELECT c1 FROM t3 WHERE (c1) IN (SELECT MIN(DISTINCT c1) FROM t2);
USE test;
CREATE TABLE t (a INT);
EXPLAIN EXTENDED SELECT * FROM t WHERE a IN (SELECT a FROM t UNION SELECT a FROM t ORDER BY (SELECT a)) UNION SELECT * FROM t ORDER BY (SELECT a);
USE test;
SET GLOBAL innodb_limit_optimistic_INSERT_debug=2;
CREATE TABLE t (c INT, INDEX(c)) ENGINE=InnoDB;
REPLACE t VALUES (1),(1),(2),(3),(4),(5),(NULL);
INSERT INTO t VALUES (10000),(1),(1.1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1);
INSERT INTO t VALUES (10000),(1),(1.1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1);
INSERT INTO t VALUES (10000),(1),(1.1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1);
INSERT INTO t SELECT * FROM t;
INSERT INTO t SELECT * FROM t;
INSERT INTO t VALUES (NULL),(1);
INSERT INTO t SELECT * FROM t;
INSERT INTO t SELECT * FROM t;
INSERT INTO t SELECT * FROM t;
INSERT INTO t SELECT * FROM t;
INSERT INTO t SELECT * FROM t;
INSERT INTO t SELECT * FROM t;
INSERT INTO t SELECT * FROM t;
INSERT INTO t SELECT * FROM t;  # Approx crash location
INSERT INTO t SELECT * FROM t; 
INSERT INTO t SELECT * FROM t; 

SET SQL_MODE='';
USE test;
SET GLOBAL innodb_limit_optimistic_INSERT_debug=2;
CREATE TABLE t (a INT,b VARCHAR(20),KEY(a));
INSERT INTO t (a) VALUES ('a'),('b'),('c'),('d'),('e');
INSERT INTO t VALUES (1,''),(2,''),(3,''),(4,''),(5,''),(6,''),(7,'');
INSERT INTO t SELECT * FROM t;
INSERT INTO t SELECT a,a FROM t;
INSERT INTO t SELECT * FROM t;
INSERT INTO t SELECT * FROM t;
INSERT INTO t SELECT * FROM t;
INSERT INTO t SELECT * FROM t;
INSERT INTO t SELECT * FROM t;
INSERT INTO t SELECT * FROM t;

USE test;
CREATE TABLE t1 (a int not null primary key) ;
SET @commands= 'abcdefghijklmnopqrstuvwxyz';
set global innodb_simulate_comp_failures=99;
INSERT INTO t1  VALUES(1);
SET @@GLOBAL.OPTIMIZER_SWITCH="mrr=OFF";
INSERT INTO t1  VALUES ('abcdefghijklmnopqrstuvwxyz');
INSERT INTO t1  VALUES(0xA6E0);
ALTER TABLE t1 ROW_FORMAT=DEFAULT KEY_BLOCK_SIZE=2;
CREATE DEFINER=CURRENT_USER FUNCTION f3 (i1 DATETIME(2)) RETURNS DECIMAL(1) UNSIGNED SQL SECURITY INVOKER RETURN CONCAT('abcdefghijklmnopqrstuvwxyz',i1);

USE test;
CREATE TABLE t (a INT PRIMARY KEY);
SET GLOBAL innodb_simulate_comp_failures=99;
INSERT INTO t VALUES(1);
INSERT INTO t VALUES(0);
ALTER TABLE t ROW_FORMAT=DEFAULT KEY_BLOCK_SIZE=2;

SET SQL_MODE='';
USE test;
CREATE TABLE tab(c INT) ROW_FORMAT=COMPRESSED;
SET GLOBAL INNODB_LIMIT_OPTIMISTIC_INSERT_DEBUG=2;
CREATE TABLE t (c INT);
INSERT INTO t VALUES (1),(2),(3),(4);
INSERT INTO t SELECT t.* FROM t,t t2,t t3,t t4,t t5,t t6,t t7;
SET GLOBAL INNODB_RANDOM_READ_AHEAD=1;
INSERT INTO tab(c) VALUES(1);

CREATE TABLE t1 (ID INT(11) NOT NULL AUTO_INCREMENT, Name CHAR(35) NOT NULL DEFAULT '', country CHAR(3) NOT NULL DEFAULT '', Population INT(11) NOT NULL DEFAULT '0', PRIMARY KEY(ID), INDEX (Population), INDEX (country));
SET GLOBAL innodb_limit_optimistic_insert_debug = 2;
INSERT INTO  t1  VALUES (201,'Sarajevo','BIH',360000), (202,'Banja Luka','BIH',143079), (203,'Zenica','BIH',96027), (204,'Gaborone','BWA',213017), (205,'Francistown','BWA',101805), (206,'São Paulo','BRA',9968485), (207,'Rio de Janeiro','BRA',5598953), (208,'Salvador','BRA',2302832), (209,'Belo Horizonte','BRA',2139125), (210,'Fortaleza','BRA',2097757), (211,'Brasília','BRA',1969868), (212,'Curitiba','BRA',1584232), (213,'Recife','BRA',1378087), (214,'Porto Alegre','BRA',1314032), (215,'Manaus','BRA',1255049), (216,'Belém','BRA',1186926), (217,'Guarulhos','BRA',1095874), (218,'Goiânia','BRA',1056330), (219,'Campinas','BRA',950043), (220,'São Gonçalo','BRA',869254), (221,'Nova Iguaçu','BRA',862225), (222,'São Luís','BRA',837588), (223,'Maceió','BRA',786288), (224,'Duque de Caxias','BRA',746758), (225,'São Bernardo do Campo','BRA',723132), (226,'Teresina','BRA',691942), (227,'Natal','BRA',688955), (228,'Osasco','BRA',659604), (229,'Campo Grande','BRA',649593), (230,'Santo André','BRA',630073), (231,'João Pessoa','BRA',584029), (232,'Jaboatão dos Guararapes','BRA',558680), (233,'Contagem','BRA',520801), (234,'São José dos Campos','BRA',515553), (235,'Uberlândia','BRA',487222), (236,'Feira de Santana','BRA',479992), (237,'Ribeirão Preto','BRA',473276), (238,'Sorocaba','BRA',466823), (239,'Niterói','BRA',459884), (240,'Cuiabá','BRA',453813), (241,'Juiz de Fora','BRA',450288), (242,'Aracaju','BRA',445555), (243,'São João de Meriti','BRA',440052), (244,'Londrina','BRA',432257), (245,'Joinville','BRA',428011), (246,'Belford Roxo','BRA',425194), (247,'Santos','BRA',408748), (248,'Ananindeua','BRA',400940), (249,'Campos dos Goytacazes','BRA',398418), (250,'Mauá','BRA',375055), (251,'Carapicuíba','BRA',357552), (252,'Olinda','BRA',354732), (253,'Campina Grande','BRA',352497), (254,'São José do Rio Preto','BRA',351944), (255,'Caxias do Sul','BRA',349581), (256,'Moji das Cruzes','BRA',339194), (257,'Diadema','BRA',335078), (258,'Aparecida de Goiânia','BRA',324662), (259,'Piracicaba','BRA',319104), (260,'Cariacica','BRA',319033), (261,'Vila Velha','BRA',318758), (262,'Pelotas','BRA',315415), (263,'Bauru','BRA',313670), (264,'Porto Velho','BRA',309750), (265,'Serra','BRA',302666), (266,'Betim','BRA',302108), (267,'Jundíaí','BRA',296127), (268,'Canoas','BRA',294125), (269,'Franca','BRA',290139), (270,'São Vicente','BRA',286848), (271,'Maringá','BRA',286461), (272,'Montes Claros','BRA',286058), (273,'Anápolis','BRA',282197), (274,'Florianópolis','BRA',281928), (275,'Petrópolis','BRA',279183), (276,'Itaquaquecetuba','BRA',270874), (277,'Vitória','BRA',270626), (278,'Ponta Grossa','BRA',268013), (279,'Rio Branco','BRA',259537), (280,'Foz do Iguaçu','BRA',259425), (281,'Macapá','BRA',256033), (282,'Ilhéus','BRA',254970), (283,'Vitória da Conquista','BRA',253587), (284,'Uberaba','BRA',249225), (285,'Paulista','BRA',248473), (286,'Limeira','BRA',245497), (287,'Blumenau','BRA',244379), (288,'Caruaru','BRA',244247), (289,'Santarém','BRA',241771), (290,'Volta Redonda','BRA',240315), (291,'Novo Hamburgo','BRA',239940), (292,'Caucaia','BRA',238738), (293,'Santa RocksDB','BRA',238473), (294,'Cascavel','BRA',237510), (295,'Guarujá','BRA',237206), (296,'Ribeirão das Neves','BRA',232685), (297,'Governador Valadares','BRA',231724), (298,'Taubaté','BRA',229130), (299,'Imperatriz','BRA',224564), (300,'Gravataí','BRA',223011), (301,'Embu','BRA',222223), (302,'Mossoró','BRA',214901), (303,'Várzea Grande','BRA',214435), (304,'Petrolina','BRA',210540), (305,'Barueri','BRA',208426), (306,'Viamão','BRA',207557), (307,'Ipatinga','BRA',206338), (308,'Juazeiro','BRA',201073), (309,'Juazeiro do Norte','BRA',199636), (310,'Taboão da Serra','BRA',197550), (311,'São José dos Pinhais','BRA',196884), (312,'Magé','BRA',196147), (313,'Suzano','BRA',195434), (314,'São Leopoldo','BRA',189258), (315,'Marília','BRA',188691), (316,'São Carlos','BRA',187122), (317,'Sumaré','BRA',186205), (318,'Presidente Prudente','BRA',185340), (319,'Divinópolis','BRA',185047), (320,'Sete Lagoas','BRA',182984), (321,'Rio Grande','BRA',182222), (322,'Itabuna','BRA',182148), (323,'Jequié','BRA',179128), (324,'Arapiraca','BRA',178988), (325,'Colombo','BRA',177764), (326,'Americana','BRA',177409), (327,'Alvorada','BRA',175574), (328,'Araraquara','BRA',174381), (329,'Itaboraí','BRA',173977), (330,'Santa Bárbara d´Oeste','BRA',171657), (331,'Nova Friburgo','BRA',170697), (332,'Jacareí','BRA',170356), (333,'Araçatuba','BRA',169303), (334,'Barra Mansa','BRA',168953), (335,'Praia Grande','BRA',168434), (336,'Marabá','BRA',167795), (337,'Criciúma','BRA',167661), (338,'Boa Vista','BRA',167185), (339,'Passo Fundo','BRA',166343), (340,'Dourados','BRA',164716), (341,'Santa Luzia','BRA',164704), (342,'Rio Claro','BRA',163551), (343,'Maracanaú','BRA',162022), (344,'Guarapuava','BRA',160510), (345,'Rondonópolis','BRA',155115), (346,'São José','BRA',155105), (347,'Cachoeiro de Itapemirim','BRA',155024), (348,'Nilópolis','BRA',153383), (349,'Itapevi','BRA',150664), (350,'Cabo de Santo Agostinho','BRA',149964), (351,'Camaçari','BRA',149146), (352,'Sobral','BRA',146005), (353,'Itajaí','BRA',145197), (354,'Chapecó','BRA',144158), (355,'Cotia','BRA',140042), (356,'Lages','BRA',139570), (357,'Ferraz de Vasconcelos','BRA',139283), (358,'Indaiatuba','BRA',135968), (359,'Hortolândia','BRA',135755), (360,'Caxias','BRA',133980), (361,'São Caetano do Sul','BRA',133321), (362,'Itu','BRA',132736), (363,'Nossa Senhora do Socorro','BRA',131351), (364,'Parnaíba','BRA',129756), (365,'Poços de Caldas','BRA',129683), (366,'Teresópolis','BRA',128079), (367,'Barreiras','BRA',127801), (368,'Castanhal','BRA',127634), (369,'Alagoinhas','BRA',126820), (370,'Itapecerica da Serra','BRA',126672), (371,'Uruguaiana','BRA',126305), (372,'Paranaguá','BRA',126076), (373,'Ibirité','BRA',125982), (374,'Timon','BRA',125812), (375,'Luziânia','BRA',125597), (376,'Macaé','BRA',125597), (377,'Teófilo Otoni','BRA',124489), (378,'Moji-Guaçu','BRA',123782), (379,'Palmas','BRA',121919), (380,'Pindamonhangaba','BRA',121904), (381,'Francisco Morato','BRA',121197), (382,'Bagé','BRA',120793), (383,'Sapucaia do Sul','BRA',120217), (384,'Cabo Frio','BRA',119503), (385,'Itapetininga','BRA',119391), (386,'Patos de Minas','BRA',119262), (387,'Camaragibe','BRA',118968), (388,'Bragança Paulista','BRA',116929), (389,'Queimados','BRA',115020), (390,'Araguaína','BRA',114948), (391,'Garanhuns','BRA',114603), (392,'Vitória de Santo Antão','BRA',113595), (393,'Santa Rita','BRA',113135), (394,'Barbacena','BRA',113079), (395,'Abaetetuba','BRA',111258), (396,'Jaú','BRA',109965), (397,'Lauro de Freitas','BRA',109236), (398,'Franco da Rocha','BRA',108964), (399,'Teixeira de Freitas','BRA',108441), (400,'Varginha','BRA',108314);
CREATE DATABASE db CHARACTER SET utf32;
SET SESSION SESSION_TRACK_TRANSACTION_INFO= CHARACTERISTICS;
USE db;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;

SET SESSION_TRACK_TRANSACTION_INFO=CHARACTERISTICS;
SET SESSION COLLATION_DATABASE=utf32_general_ci;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION WITH CONSISTENT SNAPSHOT;
SET NAMES latin1;
CREATE TABLE t1 (f VARCHAR(8) CHARACTER SET utf8, i INT);
INSERT INTO t1 VALUES ('foo',1),('bar',2);
SET in_predicate_conversion_threshold= 3;
PREPARE stmt FROM "SELECT * FROM t1 WHERE (f IN ('a','b','c') AND i = 10)";
EXECUTE stmt;
EXECUTE stmt;

SET SESSION in_predicate_conversion_threshold=1;
CREATE TABLE H (c VARCHAR(1) PRIMARY KEY);
PREPARE p FROM 'SELECT * FROM H WHERE c NOT IN (\'a\', \'a\')';
EXECUTE p;
EXECUTE p;

SET collation_connection=utf32_czech_ci;
CREATE TABLE t1 (c VARCHAR(1));
SET in_predicate_conversion_threshold=2;
PREPARE p FROM 'SELECT * FROM t1 WHERE c NOT IN (\'a\',\'a\')';
EXECUTE p;
EXECUTE p;
CREATE TABLE t (a INT);
CREATE VIEW v AS SELECT 1 FROM t;
SET big_tables= 1; # Not needed for 10.5+
CREATE PROCEDURE p() SELECT 2 FROM v;
CREATE TEMPORARY TABLE v SELECT 3 AS b;
CALL p();
SET PSEUDO_THREAD_ID= 111;
CALL p();

CREATE TABLE t (a INT);
CREATE VIEW v AS SELECT 1 FROM t;
CREATE PROCEDURE p() SELECT 2 FROM v;
CREATE TEMPORARY TABLE v SELECT 3 AS b;
CALL p();
ALTER TABLE v RENAME TO vv;
CALL p();
USE test;
CREATE TEMPORARY TABLE t (c INT);
LOCK TABLE t WRITE;
DROP SEQUENCE IF EXISTS t;

CREATE TABLE t1 (a INT);
CREATE TEMPORARY TABLE tmp (b INT);
LOCK TABLE t1 READ;
DROP SEQUENCE tmp;
USE test;
SET GLOBAL innodb_adaptive_hash_index=ON;
CREATE TABLE t (c INT) ENGINE=InnoDB;
ALTER TABLE t DISCARD TABLESPACE;
DROP TABLE t;
USE test;
CREATE TEMPORARY TABLE t3 (c1 INT, INDEX(c1)) UNION=(t1,t2) ENGINE=InnoDB;
CREATE TABLE t2 (c1 INT, c2 INT) ENGINE=InnoDB;
CREATE TABLE t1 (a INT NOT NULL, b INT NOT NULL, pk INT NOT NULL, PRIMARY KEY (pk), KEY(a), KEY(b)) ENGINE=InnoDB PARTITION BY HASH(pk) PARTITIONS 10;
REPAIR TABLE t1, t2, t3;
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
USE test;
SET SQL_MODE='STRICT_TRANS_TABLES';
CREATE TABLE t (a DOUBLE PRIMARY KEY AUTO_INCREMENT);
INSERT INTO t VALUES (18446744073709551601);

USE test;
CREATE TABLE t (a DOUBLE PRIMARY KEY AUTO_INCREMENT);
INSERT INTO t VALUES (18446744073709551601);
USE test;
SET COLLATION_CONNECTION=utf32_myanmar_ci, CHARACTER_SET_CLIENT=binary;
CREATE TABLE t (a CHAR(1));
ALTER TABLE t CHANGE a a ENUM('a','a') CHARACTER SET utf32;

USE test;
SET SQL_MODE='';
SET MAX_SORT_LENGTH=29;
SET COLLATION_CONNECTION=utf32_unicode_ci;
CREATE TEMPORARY TABLE t1 (a INT);
INSERT INTO t1 VALUES (_ucs2 0x00fd),(_ucs2 0x00dd);
SELECT * FROM t1 ORDER BY (oct(a));

USE test;
SET COLLATION_CONNECTION=utf32_czech_ci;
CREATE TABLE t (a INT);
INSERT INTO t VALUES (1);
SELECT 1 FROM t ORDER BY @x:=makedate(a,a);
USE test;
CREATE TABLE t2(i int) ENGINE=MyISAM;
CREATE TEMPORARY TABLE t1 (a INT) ENGINE=Merge UNION=(t2);
CREATE TEMPORARY TABLE t1 SELECT * FROM t1;
USE test;
CREATE TABLE t1 (a INT);
INSERT INTO t1 VALUES (1);
CREATE TABLE t2 (i INT) DATA DIRECTORY = '/tmp', ENGINE=Aria;
CREATE TABLE t2 (i INT) DATA DIRECTORY = '/tmp', ENGINE=Aria;

# Repeat as needed, also attempt replay via pquery
# mysqld options required for replay:  --sql_mode=
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE   t1   (a TINYINT UNSIGNED, b SMALLINT UNSIGNED, c CHAR(61) NOT NULL, d VARBINARY(78), e VARCHAR(72), f VARCHAR(43) NOT NULL, g MEDIUMBLOB NOT NULL, h LONGBLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ;
set session default_storage_engine=Aria;
CREATE TABLE t(i int) DATA DIRECTORY = '/tmp', ENGINE = RocksDB;
create table tm (k int, index (k)) charset utf8mb4 ;
INSERT INTO   t1   VALUES (2890623675590946934,11482198,'Lo6MOErYmXjTta3P5lTt78F9Yv1BbFNxFma2','OnWYE1g7gL2DIQuFMmIRFJ3ZbDXB6sO3AOPx06mc0y7RDQNU2DSKisEuar8GQqb5dvQTr5JJLerMYKff9OeZc3jygymh0PDexjenuUVNtUVccrHnVCUwaOmYL','M82','R','h','v',12); ;
USE test;
SET tmp_table_size=1024;
SET tmp_disk_table_size=1024;
CREATE TABLE t1 (x INT(11), row_start BIGINT(20) UNSIGNED GENERATED ALWAYS AS ROW START INVISIBLE, row_end BIGINT(20) UNSIGNED GENERATED ALWAYS AS ROW END INVISIBLE, PERIOD FOR SYSTEM_TIME (row_start, row_end)) WITH SYSTEM VERSIONING;
INSERT INTO t1 VALUES(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1),(1);
SELECT * FROM t1 INTERSECT ALL SELECT * FROM t1 INTERSECT ALL SELECT * FROM t1;

SET GLOBAL query_cache_type=ON;
SET GLOBAL query_cache_size=1024*64;
USE test;
CREATE TABLE t (a INT) PARTITION BY KEY(a) PARTITIONS 99;
SET SESSION query_cache_type=DEFAULT;
SELECT COUNT(*) FROM t WHERE c1=2;
# $ rm -Rf data*
# $ ./scripts/mariadb-install-db --no-defaults --force --auth-root-authentication-method=normal --innodb-force-recovery=254 --basedir=${PWD} --datadir=${PWD}/data
# $ ./scripts/mysql_install_db --no-defaults --force --auth-root-authentication-method=normal --innodb-force-recovery=254 --basedir=${PWD} --datadir=${PWD}/data

# mysqld options required for replay:  --innodb-force-recovery=24
INSERT INTO mysql.innodb_table_stats SELECT database_name,''AS table_name,laST_UPDATE,123 AS n_rows,clustered_index_size,sum_of_other_index_sizes FROM mysql.innodb_table_stats WHERE table_name='';

# mysqld options required for replay:  --innodb-force-recovery=24
XA START 'a','a',0;
SELECT stat_value>0 FROM mysql.innodb_index_stats WHERE table_name LIKE 'a' IN (0);
SELECT * FROM information_schema.innodb_lock_waits;

# mysqld options required for replay:  --innodb-force-recovery=6
USE test;
SET GLOBAL innodb_log_checkpoint_now=TRUE;

# mysqld options required for replay:  --innodb-force-recovery=254
INSERT INTO mysql.innodb_table_stats SELECT database_name,''AS table_name,laST_UPDATE,0 AS n_rows,clustered_index_size,sum_of_other_index_sizes FROM mysql.innodb_table_stats WHERE table_name='';
# mysqld options required for replay: --innodb-force-recovery=6
SET GLOBAL innodb_status_output=0;
# mysqld options required for replay: --character-set-server=utf16
SET GLOBAL ft_boolean_syntax=' ~/!@#$%^&*()-';

# mysqld options required for replay:  --character-set-server=utf32
SET GLOBAL ft_boolean_syntax=DEFAULT;
CREATE TABLE t1 (b VARCHAR(1024), c CHAR(3), UNIQUE(b,c)) ENGINE=MyISAM;
INSERT INTO t1 VALUES ('foo','baz');
ALTER TABLE t1 DISABLE KEYS;
SET SESSION myisam_repair_threads= 2;
INSERT INTO t1 SELECT 'qux';

CREATE TABLE t1 (b VARCHAR(20) unique, c CHAR(3), d varchar(30) as (c)  invisible)  ENGINE=MyISAM;
CREATE INDEX idx ON t1(d);
SHOW CREATE TABLE t1;
INSERT INTO t1 VALUES ('foo','baz');
ALTER TABLE t1 DISABLE KEYS;
SET SESSION myisam_repair_threads= 2;
INSERT INTO t1 SELECT 'qux';

SET SQL_MODE='';
USE test;
CREATE TABLE t1 (c1 INT, c2 INT AS (100/c1), KEY(c2)) ENGINE=MyISAM;
CREATE TABLE t2 (a INT, b INT, UNIQUE(b)) ENGINE=MyISAM;
INSERT INTO t2 VALUES (1,2);
SET SESSION MyISAM_REPAIR_THREADS=100;
INSERT INTO t1 SELECT * FROM t2;

USE test;
SET SQL_MODE='';
CREATE TABLE t (a INT);
SET myisam_repair_threads=2;
INSERT INTO t VALUES (NULL), (1);
SELECT * FROM t INTO OUTFILE 'myfile';
CREATE TABLE t2 (a INT, b INT GENERATED ALWAYS AS (a+1) VIRTUAL, INDEX (b), CONSTRAINT x FOREIGN KEY(b) REFERENCES t (a)) ENGINE=MyISAM;
LOAD DATA INFILE 'myfile' INTO TABLE t2;
USE test;
SET SQL_MODE='';
CREATE TABLE t1(pk INT PRIMARY KEY) ENGINE=Aria;
SELECT * FROM t1 WHERE a IS NULL OR a > 0;
CREATE TEMPORARY TABLE t3 (c1 INT NOT NULL) ENGINE=Aria;
DELETE a3,a2 FROM t2 AS a1 INNER JOIN t3 AS a2, t3 AS a3;
REPAIR TABLE t1, t2, t3;
INSERT INTO t3 SELECT * FROM t3;
USE test;
CREATE FUNCTION f(z INT) RETURNS INT READS SQL DATA RETURN (SELECT * FROM t);
CREATE TABLE t(a INT) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t(c INT);
CREATE OR REPLACE TABLE t AS SELECT f();
SET sql_mode= 'STRICT_TRANS_TABLES'; # Only needed for 10.1, in higher versions it is default
CREATE TABLE t1 (a INT);
LOCK TABLE t1 WRITE;
CREATE OR REPLACE TABLE t1 (a CHAR(1)) AS SELECT 'foo' AS a;

CREATE TABLE t1 (a INT);
CREATE TABLE t2 (b INT);
LOCK TABLE t1 WRITE, t2 WRITE;
CREATE OR REPLACE TABLE t1 (a CHAR(1)) AS SELECT 'foo' AS a;

SET SESSION default_storage_engine=mrg_myisam;
CREATE TABLE t (a INT);
LOCK TABLES t WRITE;
CREATE or REPLACE TABLE t AS SELECT 1 AS a;
SET GLOBAL innodb_encryption_threads=5;
SET GLOBAL innodb_encryption_rotate_key_age=0;
SELECT SLEEP(5);  # Somewhat delayed crash happens during sleep
USE test;
INSTALL SONAME 'ha_archive';
CREATE TEMPORARY TABLE t2 (c1 INT UNSIGNED ZEROFILL) ENGINE=ARCHIVE;
REPAIR NO_WRITE_TO_BINLOG TABLE t2 EXTENDED;
SELECT * FROM t2 WHERE c1 < 1;
USE test;
CREATE TABLE  t1  ( `a` int(11) DEFAULT NULL, KEY `a` (`a`), CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa10` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa100` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa101` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa102` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa103` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa104` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa105` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa106` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa107` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa108` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa109` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa11` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa110` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa111` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa112` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa113` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa114` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa115` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa116` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa117` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa118` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa119` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa12` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa120` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa121` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa122` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa123` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa124` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa125` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa126` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa127` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa128` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa129` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa13` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa130` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa131` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa132` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa133` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa134` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa135` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa136` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa137` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa138` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa139` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa14` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa140` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa141` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa142` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa143` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa144` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa145` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa146` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa147` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa148` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa149` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa15` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa150` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa151` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa152` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa153` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa154` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa155` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa156` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa157` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa158` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa159` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa16` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa160` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa161` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa162` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa163` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa164` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa165` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa166` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa167` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa168` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa169` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa17` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa170` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa171` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa172` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa173` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa174` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa175` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa176` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa177` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa178` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa179` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa18` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa180` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa181` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa182` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa183` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa184` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa185` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa186` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa187` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa188` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa189` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa19` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa190` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa191` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa192` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa193` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa194` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa195` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa196` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa197` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa198` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa199` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa20` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa200` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa201` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa202` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa203` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa204` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa205` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa206` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa207` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa208` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa209` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa21` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa210` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa211` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa212` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa213` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa214` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa215` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa216` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa217` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa218` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa219` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa22` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa220` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa221` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa222` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa223` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa224` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa225` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa226` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa227` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa228` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa229` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa23` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa230` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa231` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa232` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa233` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa234` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa235` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa236` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa237` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa238` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa239` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa24` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa240` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa241` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa242` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa243` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa244` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa245` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa246` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa247` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa248` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa249` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa25` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa250` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa251` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa252` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa253` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa254` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa255` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa256` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa257` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa258` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa259` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa26` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa260` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa261` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa262` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa263` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa264` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa265` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa266` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa267` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa268` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa269` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa27` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa270` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa271` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa272` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa273` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa274` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa275` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa276` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa277` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa278` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa279` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa28` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa280` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa281` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa282` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa283` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa284` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa285` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa286` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa287` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa288` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa289` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa29` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa290` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa291` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa292` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa293` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa294` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa295` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa296` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa297` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa298` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa299` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa3` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa30` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa300` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa301` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa302` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa303` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa304` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa305` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa306` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa307` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa308` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa309` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa31` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa310` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa311` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa312` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa313` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa314` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa315` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa316` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa317` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa318` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa319` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa32` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa320` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa321` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa322` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa323` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa324` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa325` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa326` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa327` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa328` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa329` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa33` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa330` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa331` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa332` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa333` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa334` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa335` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa336` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa337` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa338` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa339` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa34` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa340` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa341` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa342` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa343` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa344` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa345` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa346` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa347` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa348` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa349` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa35` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa350` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa351` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa352` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa353` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa354` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa355` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa356` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa357` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa358` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa359` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa36` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa360` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa361` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa362` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa363` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa364` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa365` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa366` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa367` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa368` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa369` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa37` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa370` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa371` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa372` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa373` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa374` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa375` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa376` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa377` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa378` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa379` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa38` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa380` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa381` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa382` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa383` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa384` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa385` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa386` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa387` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa388` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa389` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa39` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa390` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa391` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa392` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa393` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa394` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa395` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa396` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa397` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa398` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa399` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa4` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa40` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa400` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa401` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa402` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa403` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa404` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa405` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa406` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa407` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa408` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa409` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa41` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa410` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa411` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa412` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa413` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa414` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa415` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa416` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa417` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa418` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa419` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa42` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa420` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa421` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa422` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa423` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa424` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa425` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa426` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa427` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa428` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa429` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa43` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa430` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa431` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa432` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa433` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa434` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa435` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa436` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa437` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa438` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa439` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa44` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa440` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa441` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa442` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa443` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa444` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa445` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa446` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa447` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa448` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa449` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa45` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa450` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa451` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa452` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa453` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa454` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa455` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa456` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa457` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa458` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa459` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa46` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa460` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa461` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa462` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa463` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa464` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa465` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa466` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa467` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa468` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa469` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa47` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa470` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa471` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa472` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa473` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa474` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa475` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa476` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa477` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa478` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa479` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa48` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa480` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa481` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa482` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa483` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa484` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa485` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa486` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa487` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa488` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa489` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa49` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa490` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa491` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa492` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa493` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa494` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa495` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa496` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa497` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa498` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa499` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa5` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa50` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa500` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa501` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa502` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa503` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa504` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa505` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa506` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa507` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa508` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa509` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa51` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa510` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa511` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa512` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa513` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa514` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa515` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa516` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa517` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa518` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa519` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa52` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa520` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa521` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa522` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa523` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa524` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa525` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa526` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa527` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa528` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa529` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa53` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa530` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa531` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa532` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa533` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa534` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa535` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa536` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa537` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa538` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa539` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa54` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa540` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa541` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa542` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa543` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa544` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa545` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa546` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa547` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa548` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa549` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa55` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa550` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa56` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa57` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa58` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa59` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa6` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa60` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa61` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa62` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa63` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa64` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa65` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa66` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa67` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa68` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa69` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa7` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa70` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa71` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa72` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa73` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa74` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa75` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa76` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa77` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa78` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa79` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa8` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa80` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa81` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa82` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa83` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa84` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa85` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa86` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa87` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa88` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa89` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa90` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa91` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa92` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa93` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa94` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa95` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa96` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa97` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa98` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL, CONSTRAINT `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa99` FOREIGN KEY (`a`) REFERENCES `bug56143_1` (`a`) ON UPDATE SET NULL );
USE test;
CREATE TABLE t (a INT, KEY(a)) ENGINE=MEMORY WITH SYSTEM VERSIONING;
INSERT DELAYED INTO t VALUES (1);
# MTR testcase, ref JIRA bug report, specifically https://jira.mariadb.org/browse/MDEV-23468?focusedCommentId=166641&page=com.atlassian.jira.plugin.system.issuetabpanels:comment-tabpanel#comment-166641
USE test;
SET SESSION default_master_connection='a';
CREATE TABLE t(a INT) UNION=(t);
CHANGE MASTER TO MASTER_USER='a', MASTER_PASSWORD='a';
SET GLOBAL REPLICATE_DO_TABLE=NULL;
USE test;
CREATE TABLE t1(a DATETIME);
CREATE TABLE t2(a VARCHAR(20));
SELECT (SELECT CONCAT(a),1 FROM t1) <=> (SELECT CONCAT(a),1 FROM t2);

USE test;
CREATE TEMPORARY TABLE t(a VARCHAR(20) NOT NULL, b VARCHAR(20));
ALTER TABLE t MODIFY a DATETIME;
INSERT INTO t VALUES (1, ST_GEOMFROMTEXT('abcdefghijklmnopqrstuvwxyz'));
CREATE TEMPORARY TABLE t2 (a VARCHAR(20), b VARCHAR(20), c VARCHAR(20)) ENGINE=MEMORY;
INSERT INTO t VALUES (45199,1184);#ERROR: 1114 - Tabulka 'abcdefghijklmnopqrstuvwxyz' je pln�
SET NAMES cp850;
SELECT (SELECT CONCAT(a),1 FROM t) <=> (SELECT CONCAT(a),1 FROM t2);
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
SET GLOBAL innodb_immediate_scrub_data_uncompressed=ON;
CREATE TABLE t (c INT) ENGINE=InnoDB;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;
TRUNCATE t;  # More if needed

USE test;
CREATE TABLE ti (a TINYINT NOT NULL, b SMALLINT, c CHAR(87) NOT NULL, d VARCHAR(73) NOT NULL, e VARCHAR(19), f VARCHAR(98) NOT NULL, g TINYBLOB, h BLOB NOT NULL, id BIGINT NOT NULL, KEY(b), KEY(e), PRIMARY KEY(id)) ENGINE=RocksDB;
SET @@GLOBAL.OPTIMIZER_SWITCH="index_merge_intersection=ON";
set global innodb_limit_optimistic_insert_debug = 2;
CREATE TABLE `龗龗龗`(`丄丄丄` char(1)) DEFAULT CHARSET = utf8 engine=RocksDB;
create table t4 (id int primary key) engine = TokuDB key_block_size = 2;
set global innodb_immediate_scrub_data_uncompressed=ON;
CREATE TABLE t1 (col_longtext_ucs2 longtext, col_longtext_utf8 longtext, col_varchar_255_ucs2_key varchar(255), col_set_utf8 set ('a','b'), col_char_255_ucs2 char(255), col_char_255_ucs2_key char(255), col_enum_ucs2 enum ('a','b'), col_varchar_255_ucs2 varchar(255), col_longtext_ucs2_key longtext, col_longtext_utf8_key longtext, col_enum_utf8 enum ('a','b'), col_varchar_255_utf8_key varchar(1024), col_varchar_255_utf8 varchar(255), col_enum_ucs2_key enum ('a','b'), col_enum_utf8_key enum ('a','b'), col_set_utf8_key set ('a','b'), col_char_255_utf8 char(255), pk integer auto_increment, col_set_ucs2_key set ('a','b'), col_char_255_utf8_key char(255), col_set_ucs2 set ('a','b'), primary key (pk)) ENGINE=InnoDB;
SELECT floor(cast(-2 as unsigned)), floor(18446744073709551614), floor(-2);
ALTER TABLE ti CHANGE COLUMN c c BINARY(69) NOT NULL;
TRUNCATE t1;
TRUNCATE t1;
TRUNCATE t1;
USE test;
SET SQL_MODE='';
CREATE TABLE t1 (a INT PRIMARY KEY, b INT, KEY(b)) ENGINE=Aria;
INSERT INTO t1 VALUES (0, 0),(1, 1);
CREATE TABLE t2 SELECT * FROM t1;
SELECT (SELECT 1 FROM t1 WHERE t1.a=t2.a ORDER BY t1.b LIMIT 1) AS c FROM t2;
USE test;
CREATE TABLE t (a INT, b INT DEFAULT (a+1));
INSERT INTO t VALUES (1,1);
UPDATE t SET b=DEFAULT;
USE test;
SET SQL_MODE='';
SET GLOBAL innodb_prefix_index_cluster_optimization=1;
CREATE TABLE t(c POINT GENERATED ALWAYS AS (POINT(1,1)) UNIQUE) ENGINE=InnoDB;
INSERT t SET c=1;
INSERT INTO t SELECT * FROM t WHERE c > (SELECT MAX(c) FROM t);

USE test;
SET GLOBAL innodb_prefix_index_cluster_optimization = 1;
CREATE TABLE t1(c INT, p POINT, KEY(p)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (103, ST_POINTFROMTEXT('POINT(1 1)'));
SELECT ST_ASTEXT(p) FROM t1 WHERE p = ST_POINTFROMTEXT('POINT(1 1)');
USE test;
CREATE TABLE t (h INT);
INSERT INTO t VALUES (0);
SELECT CAST(JSON_EXTRACT(h,0) as DECIMAL(1,1)) FROM t;
# mysqld options required for replay:  --performance-schema
SET @X2345678901234567890123456789012345678901234567890123456789012345 = 12;
SELECT * FROM performance_schema.user_variables_by_thread;
#
# Repeat 3-10000000 times. Random delays may help. Highly sporadic.
# Single thread enough to reproduce, multi-threaded is likely faster.
DROP DATABASE test;CREATE DATABASE test;USE test;
CREATE TABLE t2 (a INT) ENGINE=InnoDB;
XA BEGIN 'x1';
SET GLOBAL innodb_lru_scan_depth=10000;
SET GLOBAL innodb_checksum_algorithm=3;
INSERT INTO t2 VALUES (1),(1),(1);
USE test;
CREATE TEMPORARY TABLE t(c INT NOT NULL) ENGINE=CSV;
INSERT INTO t VALUES(1);
REPAIR TABLE t;
DELETE FROM t;
SET GLOBAL ARIA_CHECKPOINT_LOG_ACTIVITY=1;
SET GLOBAL ARIA_GROUP_COMMIT=HARD;
SET GLOBAL ARIA_GROUP_COMMIT_INTERVAL=100000000;
GRANT SELECT ON *.* TO root@localhost;

SET GLOBAL aria_checkpoint_log_activity=1;
SET GLOBAL aria_group_commit="HARD";
SET GLOBAL aria_group_commit_interval=100000000;
GRANT SELECT ON *.* to root@localhost;
CREATE TABLE t(c INT) ENGINE=InnoDB;
ALTER TABLE t DISCARD TABLESPACE;
RENAME TABLE t TO u;
TRUNCATE u;
TRUNCATE u;
CREATE TABLE t (a DECIMAL(10) PRIMARY KEY) ENGINE=InnoDB;
SELECT (SELECT SUM(t.a) FROM t x WHERE t.a = x.a) FROM t;

CREATE TABLE t (a INT NOT NULL AUTO_INCREMENT, b INT NOT NULL, c VARCHAR (11) NOT NULL, PRIMARY KEY(a), INDEX (b));
ALTER TABLE t MODIFY a DECIMAL(30,6), MODIFY b DECIMAL(30,6);
SET SQL_MODE=TRADITIONAL;
SELECT SQL_NO_CACHE (SELECT SUM(c.a) FROM t ttt, t ccc WHERE ttt.a = ccc.b AND ttt.a = t.a GROUP BY ttt.a) AS out FROM t t, t c WHERE t.a = c.b;
SET SQL_MODE='';
CREATE TABLE t (c INT) ENGINE=InnoDB PARTITION BY HASH (c) PARTITIONS 2;
LOCK TABLES t WRITE;
ANALYZE TABLE t PERSISTENT FOR COLUMNS (b) INDEXES (i);

CREATE TABLE t (a INT) PARTITION BY HASH (a) PARTITIONS 2;
LOCK TABLES t WRITE;
ANALYZE TABLE t PERSISTENT FOR COLUMNS (nonexisting) INDEXES (nonexisting);

SET SQL_MODE='';
CREATE TABLE t (a INT PRIMARY KEY) PARTITION BY HASH (a) PARTITIONS 2;
INSERT INTO t VALUES (1);
LOCK TABLES t WRITE;
ANALYZE TABLE t PERSISTENT FOR COLUMNS (nonexisting) INDEXES (nonexisting);
SET SESSION STORAGE_ENGINE = 'memory';
CREATE TABLE t1 (col1 BIGINT DEFAULT -1);
SELECT NULL IN (SELECT * FROM t1);
# Sporadic issue. Run the following about 60-120 times at the CLI to reproduce
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE view v1 AS SELECT 'abcdefghijklmnopqrstuvwxyz' AS col1;
LOCK TABLE v1 READ;
SELECT NEXT VALUE FOR v1;
# Repeat 90-3000 times
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE t3 (b VARCHAR (1));
CREATE TABLE t2 (c2 INT);
SET SESSION join_cache_level=3;
INSERT INTO t2 VALUES (14619+0.75);
CREATE TEMPORARY TABLE t1 AS SELECT * FROM mysql.user;
DELETE IGNORE a2,a3 FROM t2 AS a1 JOIN t AS a2 INNER JOIN t2 AS a3;
SELECT * FROM (SELECT * FROM t1 NATURAL JOIN t2) AS a NATURAL LEFT JOIN (SELECT * FROM t1 NATURAL JOIN t3) AS b;

# Repeat 30-500 times
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET default_tmp_storage_engine=InnoDB;
SET join_cache_level=3;
SET default_storage_engine=Aria, default_storage_engine="HEAP", GLOBAL default_storage_engine="MERGE";
CREATE TEMPORARY TABLE t AS SELECT * FROM mysql.user;
CREATE TABLE t2 (c INT);
SELECT * FROM (SELECT * FROM t NATURAL JOIN t2) AS a NATURAL JOIN (SELECT * FROM t NATURAL JOIN t2) AS b;

SET GLOBAL optimizer_search_depth=1;
SET SESSION join_cache_level=8;
CREATE TABLE t1 AS SELECT * FROM mysql.user LIMIT 0;
CREATE TABLE t2 (a INT PRIMARY KEY, b VARCHAR(1));
CREATE TABLE t4 (f1 INT, KEY f1_key (f1));
SET SESSION optimizer_search_depth = 62;
SELECT * FROM (SELECT * FROM t1 JOIN t2) AS a NATURAL JOIN (SELECT * FROM t1 JOIN t4) AS b;

SET GLOBAL optimizer_search_depth = 1;
SET SESSION join_cache_level=8;
CREATE TABLE t1 AS SELECT * FROM mysql.user LIMIT 0;
CREATE TABLE t2 (a INT NOT NULL AUTO_INCREMENT PRIMARY KEY, b VARCHAR(1));
CREATE TABLE t4 (f1 INT);
SET SESSION optimizer_search_depth=DEFAULT;
SELECT * FROM (SELECT * FROM t1 NATURAL JOIN t2) AS t1 NATURAL JOIN (SELECT * FROM t1 NATURAL JOIN t4) AS t34;

SET join_cache_level=8;
CREATE TEMPORARY TABLE t AS SELECT * FROM mysql.user;
CREATE TEMPORARY TABLE t2 LIKE t;
SELECT t.*,t2.* FROM t NATURAL JOIN t2;

USE test;
SET SQL_MODE='';
SET GLOBAL aria_encrypt_tables=ON;
CREATE TABLE t (C1 CHAR (1) PRIMARY KEY, FOREIGN KEY(C1) REFERENCES t (C1)) ENGINE=Aria;
CREATE TRIGGER tr1_bi BEFORE INSERT ON t FOR EACH ROW SET @a:=1;
INSERT INTO t VALUES (str_to_date ('abcdefghijklmnopqrstuvwxyz', 'abcdefghijklmnopqrstuvwxyz'));
RENAME TABLE t TO t3,t TO t,t2 TO t;
# Repeat 500k times
SELECT COUNT(*) FROM INFORMATION_SCHEMA.ALL_PLUGINS;
CREATE VIEW t AS SELECT 1;
LOCK TABLES t READ;
SELECT SETVAL (t,0);
USE test;
DROP DATABASE test;
WITH RECURSIVE a AS (SELECT 1 FROM DUAL UNION ALL SELECT * FROM (SELECT * FROM a) AS b) SELECT * FROM a;
SET sql_select_limit = 3;
CREATE TEMPORARY TABLE t (i INT);
INSERT INTO t VALUES (1), (2), (3), (4);
SET SESSION max_sort_length=4;
SELECT SUM(SUM(i)) OVER W FROM t GROUP BY i WINDOW w AS (PARTITION BY i ORDER BY i) ORDER BY SUM(SUM(i)) OVER w;

SET max_length_for_sort_data=30;
SET sql_select_limit = 3;
CREATE TABLE t1 (a DECIMAL(64,0), b INT);
INSERT INTO t1 VALUES (1,1), (2,2), (3,3), (4,4);
SET max_sort_length=8;
ANALYZE FORMAT=JSON SELECT * FROM t1 ORDER BY a+1;
SELECT * FROM t1 ORDER BY a+1;
CREATE TABLE t1 (a INT, b INT, UNIQUE(a)) ENGINE=MyISAM;
CREATE TRIGGER tr1 BEFORE INSERT ON t1 FOR EACH ROW SET NEW.a=1;
SET GLOBAL wsrep_replicate_myisam=ON;
INSERT INTO t1  (a,b) VALUES (10,20);
USE test;
CREATE TABLE t (a BLOB) ENGINE=InnoDB;
INSERT INTO t VALUES ('a');
ALTER TABLE t ADD COLUMN (c INT GENERATED ALWAYS AS (a+1) VIRTUAL), ADD INDEX idx1 (c);
ALTER TABLE t ADD d INT, ALGORITHM=INPLACE;
# mysqld options required for replay: --log-bin
SET SQL_MODE='';
SET SESSION binlog_format=1;
CREATE TABLE t (a INT);
LOCK TABLES t WRITE;
CREATE OR REPLACE TABLE t (c INT DEFAULT NULL, ROW_START BIGINT UNSIGNED GENERATED ALWAYS AS ROW START INVISIBLE, ROW_END BIGINT UNSIGNED GENERATED ALWAYS AS ROW END INVISIBLE, PERIOD FOR SYSTEM_TIME (ROW_START, ROW_END)) WITH system VERSIONING;
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
INSERT INTO t (c) VALUES (1);
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE VIEW v AS SELECT table_schema  AS object_schema, table_name  AS object_name, table_type AS object_type FROM information_schema.tables ORDER BY object_schema;
SELECT * FROM v LIMIT ROWS EXAMINED 9;
SET SESSION optimizer_switch="derived_merge=OFF";
CREATE TABLE t (c INT PRIMARY KEY) ENGINE=InnoDB;
PREPARE s FROM 'INSERT INTO t SELECT * FROM (SELECT * FROM t) AS a';
SET SESSION optimizer_switch="derived_merge=ON";
EXECUTE s;
RENAME TABLE mysql.procs_priv TO mysql.temp;
CREATE USER a IDENTIFIED WITH 'a';

RENAME TABLE mysql.procs_priv TO mysql.procs_gone;
CREATE USER a@a;

RENAME TABLE mysql.procs_priv TO mysql.procs_gone;
DROP USER a;
# Repeat 1-10 times
SELECT 0xF0 >> 4 | 0xFF, (0xF0 >> 4) | 0xFF, 0xF0 >> (4 | 0xFF);
DROP DATABASE test; 
CREATE DATABASE test; 
USE test; 
RENAME TABLE mysql.db TO mysql.db_bak;
CREATE TABLE mysql.db ENGINE=MEMORY SELECT * FROM mysql.db_bak;
GRANT SELECT ON mysql.* to 'a'@'a' IDENTIFIED BY 'a';
DROP DATABASE test; 
CREATE DATABASE test; 
USE test; 
SET SESSION SQL_BUFFER_RESULT=1;
CREATE TABLE t1 (a INT NOT NULL, b varchar (64), INDEX (b,a), PRIMARY KEY (a)) PARTITION BY RANGE (a) SUBPARTITION BY HASH (a) SUBPARTITIONS 3 (PARTITION pNeg VALUES LESS THAN (0) (SUBPARTITION subp0, SUBPARTITION subp1, SUBPARTITION subp2), PARTITION `p0-29` VALUES LESS THAN (30) (SUBPARTITION subp3, SUBPARTITION subp4, SUBPARTITION subp5), PARTITION `p30-299` VALUES LESS THAN (300) (SUBPARTITION subp6, SUBPARTITION subp7, SUBPARTITION subp8), PARTITION `p300-2999` VALUES LESS THAN (3000) (SUBPARTITION subp9, SUBPARTITION subp10, SUBPARTITION subp11), PARTITION `p3000-299999` VALUES LESS THAN (300000) (SUBPARTITION subp12, SUBPARTITION subp13, SUBPARTITION subp14));
SELECT b, COUNT(DISTINCT a) FROM t1 GROUP BY b HAVING b is NULL;
# Run in continually random SQL order, using 150 or 200 threads, perpetually
# About 50k-500k executions, and sufficient time to hit the 600sec timeout are necessary
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE t1 (a INT) ENGINE=InnoDB;
INSERT INTO t1 VALUES (NULL);
XA BEGIN 'x';
UPDATE t1 SET a = 1;
DELETE FROM t1;
ALTER TABLE t1 ADD COLUMN extra INT;
INSERT INTO t1 (a) VALUES (2);
ROLLBACK;
DELETE FROM t1;
INSERT INTO t1 (a) VALUES (2);
XA END 'x';
XA ROLLBACK 'x';
DROP TABLE t1;
SET SQL_MODE='';
SET SESSION optimizer_switch="not_null_range_scan=ON";
CREATE TEMPORARY TABLE t (a INT, b INT, PRIMARY KEY(a), INDEX (b)) ENGINE=MyISAM;
INSERT INTO t (a,b) VALUES (0,0),(1,1),(2,'a');
SET @a=0.0;
SELECT a,b FROM t AS d WHERE a=(SELECT a FROM t WHERE b=@a) AND b='a';
# mysqld options required for replay: --innodb-log-buffer-size=-1125899906842624
# Just start server, startup issue
CREATE DATABASE `db_new..............................................end`;
SET SESSION foreign_key_checks=0;
USE `db_new..............................................end`;
CREATE TABLE mytable_ref (id int,constraint FOREIGN KEY (id) REFERENCES FOO(id) ON DELETE CASCADE) ;
SELECT constraint_catalog, constraint_schema, constraint_name, table_catalog, table_schema, table_name, column_name FROM information_schema.key_column_usage WHERE (constraint_catalog IS NOT NULL OR table_catalog IS NOT NULL) AND table_name != 'abcdefghijklmnopqrstuvwxyz' ORDER BY constraint_name, table_name, column_name;
CREATE TABLE t (c INT);
LOCK TABLES t READ LOCAL;
CREATE TEMPORARY TABLE t (a INT) SELECT 1 AS a;
DROP SEQUENCE t;
CREATE PROCEDURE p() SELECT * FROM (SELECT 1 FROM mysql.user) AS a;
SET SESSION optimizer_switch="derived_merge=OFF";
CALL p();
SET SESSION optimizer_switch="derived_merge=ON";
CALL p();

CREATE TABLE t (id int PRIMARY KEY) ENGINE=InnoDB;
SET @@SESSION.OPTIMIZER_SWITCH="derived_merge=OFF";
CREATE TEMPORARY TABLE t2 (c1 VARBINARY(2)) BINARY CHARACTER SET 'latin1' PRIMARY KEY(c1)) ENGINE=MEMORY;
SET @cmd:="SELECT * FROM (SELECT * FROM t) AS a";
PREPARE stmt FROM @cmd;
EXECUTE stmt;
SET @@SESSION.OPTIMIZER_SWITCH="derived_merge=ON";
EXECUTE stmt;

CREATE TABLE t (c FLOAT(0,0) ZEROFILL,c2 INT,c3 REAL(0,0) ZEROFILL,KEY(c));
SET SESSION optimizer_switch='derived_merge=OFF';
CREATE PROCEDURE p2 (OUT i1 TEXT CHARACTER SET 'latin1' COLLATE 'latin1_bin',OUT i2 INT UNSIGNED) DETERMINISTIC NO SQL SELECT * FROM (SELECT c3 FROM t) AS a1;
CALL p2 (@a,@a);
DROP TABLE t;
SET SESSION optimizer_switch='derived_merge=on';
CREATE TABLE t (c INT UNSIGNED ZEROFILL,c2 INT,c3 BLOB,KEY(c));
CALL p2 (@b,@b);
INSTALL PLUGIN ARCHIVE SONAME 'ha_archive.so';
CREATE TABLE t1 (c1 VARCHAR(10)) ENGINE=ARCHIVE;
LOCK TABLE t1 WRITE;
REPAIR TABLE t1;
ALTER TABLE t1 ADD CONSTRAINT UNIQUE KEY i1 (c1);
SET foreign_key_checks=0;
CREATE TABLE t2(c688 INT,c68 INT,c170 INT,END INT) ENGINE=InnoDB;
CREATE TABLE t3(c76 INT,c687 INT,INDEX k20(c76)) ENGINE=InnoDB;
CREATE TABLE t4(c681 INT,c43 INT,c682 INT,c15 INT,CONSTRAINT co2 FOREIGN KEY(c15)REFERENCES t11 (c30)) ENGINE=InnoDB;
CREATE TABLE t5(c71 INT,c57 VARCHAR(120),c75 INT,INDEX k10(c71)) ENGINE=InnoDB;
CREATE TABLE t6(c52 INT,c53 INT NOT NULL,c69 INT) ENGINE=InnoDB;
CREATE TABLE t7(c48 INT,c75 INT,c76 INT,c71 INT,c69 INT ,c50 VARCHAR(100),c51 INT,KEY (c48),INDEX k30 (c48),INDEX k31 (c75,c76),INDEX ab91 (c75,c71),CONSTRAINT r_156 FOREIGN KEY (c75,c76) REFERENCES t19 (c75,c76),CONSTRAINT r_215 FOREIGN KEY (c75,c71) REFERENCES e5 (c75,c71)) ENGINE=InnoDB;
CREATE TABLE t8(c42 INT,c52 INT,c47 VARCHAR(2000),c423 VARCHAR(100),CONSTRAINT r_283 FOREIGN KEY(c42)REFERENCES t24 (c42)) ENGINE=InnoDB;
CREATE TABLE t9(c682 INT,c42 INT,c688 INT,c684 INT,c32 VARCHAR(2000),c69 INT ,c72 INT,c77 VARCHAR(2000),c35 VARCHAR(2000),CONSTRAINT co4 FOREIGN KEY(c42)REFERENCES t24 (c42)) ENGINE=InnoDB;
CREATE TABLE t10(c75 INT,c46 INT,INDEX i03(c75)) ENGINE=InnoDB;
CREATE TABLE t11(c30 INT,c31 INT,c69 INT ,INDEX k11(c30)) ENGINE=InnoDB;
CREATE TABLE t12(c42 INT,c20 INT,c683 INT,c151 INT,c23 INT,c24 VARCHAR(20),c44 VARCHAR(20),c38 INT,c39 INT,c28 INT,c29 INT,c001 INT,bl1 INT,KEY (c42),INDEX k42 (c42),INDEX i02 (c42),INDEX i04 (c20),INDEX al13 (c23),INDEX k44 (c24),INDEX k45 (c44),INDEX r_588 (c38,c39),INDEX i05 (c28),INDEX r_570 (c29),INDEX k43 (c001),INDEX k46 (bl1),CONSTRAINT r_1568 FOREIGN KEY (c001) REFERENCES t7 (c48),CONSTRAINT r_1569 FOREIGN KEY (bl1) REFERENCES t7 (c48),CONSTRAINT r_570 FOREIGN KEY (c29) REFERENCES t5 (c71),CONSTRAINT r_573 FOREIGN KEY (c23) REFERENCES k47 (c23),CONSTRAINT r_574 FOREIGN KEY (c24) REFERENCES u1 (u11),CONSTRAINT r_575 FOREIGN KEY (c44) REFERENCES u1 (u11),CONSTRAINT r_588 FOREIGN KEY (c38,c39) REFERENCES t19 (c75,c76),CONSTRAINT r_682 FOREIGN KEY (c20) REFERENCES t16 (c20),CONSTRAINT co7 FOREIGN KEY (c28) REFERENCES t16 (c20)) ENGINE=InnoDB;
CREATE TABLE t13(c42 INT,c44 INT,c69 INT ,c06 INT,c35 INT,CONSTRAINT r_658 FOREIGN KEY(c35)REFERENCES t23 (c35)) ENGINE=InnoDB;
CREATE TABLE t14(c44 INT,c428 INT,c69 INT ,INDEX i01(c44)) ENGINE=InnoDB;
CREATE TABLE t16(c20 INT,c680 INT,c69 INT ,c76 INT,c49 INT,KEY (c20),INDEX k50 (c20),INDEX r_489 (c76),INDEX ab92 (c49),CONSTRAINT r_489 FOREIGN KEY (c76) REFERENCES t3 (c76),CONSTRAINT r_686 FOREIGN KEY (c49) REFERENCES t3 (c76)) ENGINE=InnoDB;
CREATE TABLE t17(c170 INT,c42 INT,c48 VARCHAR(20),c53 VARCHAR(2000),c68 INT,ct1 INT DEFAULT CURRENT_TIMESTAMP,c69 INT ,CONSTRAINT r_272 FOREIGN KEY(c170)REFERENCES e6 (c170)) ENGINE=InnoDB;
CREATE TABLE t18(c18 INT,c47 INT,INDEX k2(c18)) ENGINE=InnoDB;
CREATE TABLE t19(c75 INT,c76 INT,c77 INT,UNIQUE KEY k3(c75,c76),CONSTRAINT r_593 FOREIGN KEY(c77,c76)REFERENCES ab74 (c77,c76)) ENGINE=InnoDB;
CREATE TABLE e7(c687 INT,c688 INT,c68 INT,ct1 INT ,c69 INT,c699 VARCHAR(20),c75 INT,c76 INT,c71 INT,c72 VARCHAR(3),c77 VARCHAR(20),KEY(c687),CONSTRAINT r_304 FOREIGN KEY(c75,c71)REFERENCES e5 (c75,c71)) ENGINE=InnoDB;
CREATE TABLE t21(c15 INT,c683 INT,c684 INT,c75 INT,CONSTRAINT r_328 FOREIGN KEY(c684)REFERENCES e7 (c687)) ENGINE=InnoDB;
CREATE TABLE t22(c42 INT,c43 INT,c44 INT,c45 VARCHAR(150),c420 VARCHAR(120),c46 INT,c47 INT,c423 INT,c48 INT,c425 DATE NULL,c49 DATE NULL,c427 INT,c428 INT,c429 INT,c50 DATE NULL,c51 INT,c52 VARCHAR(3),c53 DATE NULL,c54 DATE NULL,c55 VARCHAR(10),c56 DATE NULL,c57 VARCHAR(100),c75 INT,c71 INT,c680 VARCHAR(23),c681 INT) ENGINE=InnoDB;
CREATE TABLE t23(c35 INT,c36 INT,c37 INT,c38 INT,c39 INT,UNIQUE KEY k1(c35),CONSTRAINT r_945 FOREIGN KEY(c38,c39)REFERENCES t19 (c75,c76)) ENGINE=InnoDB;
CREATE TABLE t24(c42 INT,c44 INT,c15 INT,c45 VARCHAR(150),c17 VARCHAR(4000),c18 INT,c420 INT,c19 INT,c20 VARCHAR(2),c21 VARCHAR(2000),c22 INT,c23 INT,c24 INT,b3 INT,ct1 INT ,REF VARCHAR(20),c26 INT,c27 INT,c28 INT,c29 INT,c30 INT,c31 INT,c1702 INT,c1703 VARCHAR(2000),c72 INT,c77 INT,UNIQUE KEY ab1(c42),CONSTRAINT ab19 FOREIGN KEY(c30)REFERENCES t11 (c30)) ENGINE=InnoDB;
CREATE TABLE t25(c8 INT,c42 INT,c683 INT,c151 INT,c152 INT,c681 INT,CONSTRAINT r_607 FOREIGN KEY(c152)REFERENCES t11 (c30)) ENGINE=InnoDB;
CREATE TABLE t26(c170 INT,c8 INT,c5 VARCHAR(20),c68 INT,c69 INT,CONSTRAINT ab4 FOREIGN KEY(c170)REFERENCES e6 (c170)) ENGINE=InnoDB;
CREATE TABLE t27(c15 INT,c2 INT,UNIQUE KEY f1(c15)) ENGINE=InnoDB;
CREATE ALGORITHM=UNDEFINED DEFINER=root@localhost SQL SECURITY DEFINER VIEW ab55 AS SELECT pm.c42 AS c42,pm.c44 AS c44,CASE WHEN ab76.c75=2 THEN ab76.c57 ELSE(SELECT d1.c57 FROM t5 d1 WHERE d1.c71 IN (SELECT b.c52 FROM t6 b WHERE b.c53=pm.c420)AND d1.c75=2) END AS c420_lv2,ab76.c57 AS c420,em.c46 AS c46,ju.c57 AS ab60,ab31.c47 AS ab30,ab68.c31 AS c68,e2.ct1 AS ab73,ab21.c2 AS c2,pm.REF AS REF,pm.c45 AS c45,pm.c17 AS c17,CAST(ADDTIME(ab49.c52,'') AS DATE) AS c52,ab49.c423 AS c423,ab49.c47 AS c47,CAST(ADDTIME(pm.c28,'') AS DATE) AS ab3,ab11.c53 AS ab2,(SELECT ab93.c50 FROM t7 ab93 WHERE ab93.c48=pm.b3) AS c57,CONCAT(em.c75,'_',ab76.c71) AS c680,em.c75 AS c75,ab76.c71 AS c71 FROM ((((((((((((((((((t24 pm JOIN t8 ab49 on(ab49.c42=pm.c42)) JOIN t27 ab21 on(ab21.c15=pm.c15)) JOIN t9 ab54 on(ab54.c42=pm.c42)) JOIN t5 ab76 on(ab76.c71=pm.c420)) JOIN t5 ju on(ju.c71=pm.c19)) JOIN t10 em on(em.c75=pm.c26)) JOIN t11 ab68 on(ab68.c30=pm.c30)) JOIN t12 op on(op.c42=pm.c42)) JOIN t13 om on(om.c42=pm.c42 AND om.c06='')) JOIN t14 ab42 on(ab42.c44=om.c44)) JOIN t14 ab41 on(ab41.c428=om.c44)) JOIN t16 bb1 on(bb1.c20=op.c20)) JOIN t3 l on(bb1.c49=l.c76)) JOIN t16 ab8 on(ab8.c20=op.c28)) JOIN t5 ab15 on(ab15.c71=op.c29)) JOIN t17 ab11 on(ab11.c42=pm.c42 AND ab11.c48=40)) JOIN t17 e2 on(e2.c42=pm.c42 AND e2.c48=28)) JOIN t18 ab31 on(ab31.c18=pm.c18)) WHERE (pm.c24 IS NULL OR pm.c24='') AND pm.c15 IN (0,0);
CREATE ALGORITHM=UNDEFINED DEFINER=root@localhost SQL SECURITY DEFINER VIEW ab86 AS SELECT e7.c687 AS c683,e7.c688 AS _c688,e7.c68 AS c68,e7.ct1 AS ct1,e7.c69 AS c69,e7.c699 AS c699,e7.c75 AS c75,e7.c76 AS c76,e7.c71 AS c71,e7.c72 AS c72 FROM e7 WHERE e7.c77='a';
CREATE ALGORITHM=UNDEFINED DEFINER=root@localhost SQL SECURITY DEFINER VIEW ab51 AS SELECT pm.c42 AS c42,pm.c44 AS c44,ab37.c43 AS c43,CASE WHEN ab76.c75=2 THEN ab76.c57 ELSE(SELECT d1.c57 FROM t5 d1 WHERE d1.c71 IN (SELECT b.c52 FROM t6 b WHERE b.c53=pm.c420)AND d1.c75=2) END AS c420_lv2,ab76.c57 AS c420,em.c46 AS c46,ju.c57 AS ab60,ab32.c47 AS c47,ab68.c31 AS c31,ab21.c2 AS prab22al_typ_nm,pm.REF AS REF,pm.c45 AS c45,pm.c17 AS c17,CASE WHEN pm.c20=''THEN''WHEN pm.c20=''THEN''ELSE pm.c20 END AS c20,pm.c21 AS c21,CASE WHEN ab54.c72=''THEN''WHEN ab54.c72=''THEN''ELSE ab54.c72 END AS c72,ab54.c32 AS c32,ab54.c77 AS c77,ab54.c35 AS c35,CAST(ADDTIME(pm.ct1,'') AS DATE) AS ab69,CAST(ADDTIME(pm.c72,'') AS DATE) AS ap,CAST(ADDTIME(pm.c77,'') AS DATE) AS ab47,CAST(ADDTIME(pm.c29,'') AS DATE) AS c29,(SELECT GROUP_CONCAT(DISTINCT ab17._c688 SEPARATOR ',') FROM ab86 n WHERE n.c683=g3.c683) AS c427,GROUP_CONCAT(DISTINCT CASE WHEN g3.c152=29 THEN CONCAT('',g3.c8) WHEN g3.c152=4 THEN CONCAT('',g3.c8) WHEN g3.c152 IS NULL THEN CONCAT('',g3.c8) WHEN g3.c152=31 THEN (SELECT u.c50 FROM t7 u WHERE u.c48=prab22ale2.c68) END SEPARATOR ',') AS ab13,GROUP_CONCAT(DISTINCT CASE WHEN g3.c152=29 THEN CONCAT('',g3.c8,'-,') WHEN g3.c152=4 THEN CONCAT('',g3.c8,'-,') WHEN g3.c152 IS NULL THEN CONCAT('',g3.c8,'-,') WHEN g3.c152=31 THEN ADDTIME(prab22ale2.c69,'') END SEPARATOR ',') AS ab12,CAST(ADDTIME(pm.c22,'') AS DATE) AS c22,CASE WHEN g06.c688 IS NULL THEN d2.c688 ELSE CONCAT(d2.c688,',',g06.c688) END AS ab79,CASE WHEN (g06.c688 IS NULL AND ab11.c48=0) THEN (SELECT u.c50 FROM t7 u WHERE u.c48=ab11.c68) WHEN (g06.c688 is NOT NULL AND ab11.c48=0) THEN REPLACE(CONCAT(IFNULL(IFNULL((SELECT u.c50 FROM t7 u WHERE u.c48=ab9.c68),u3.c50),''),',',IFNULL(IFNULL((SELECT u.c50 FROM t7 u WHERE u.c48=ab11.c68),u.c50),'')),',','') WHEN (g06.c688 is NOT NULL AND ab9.c48=33) THEN CONCAT((SELECT IFNULL(u.c50,'') FROM t7 u WHERE u.c48=ab9.c68),',-',pm.c42) WHEN (d2.c688 is NOT NULL AND g06.c688 is NOT NULL) THEN CONCAT('',pm.c42,',','',pm.c42) WHEN (d2.c688 IS NULL AND g06.c688 IS NULL) THEN NULL ELSE CONCAT('',pm.c42) END AS ab78,REPLACE(CASE WHEN (g06.c688 IS NULL AND ab11.c48=0) THEN IFNULL(ADDTIME(ab11.ct1,''),'') WHEN (g06.c688 is NOT NULL AND ab11.c48=0) THEN CONCAT(IFNULL(ADDTIME(ab9.ct1,''),''),',',IFNULL(ADDTIME(ab11.ct1,''),'')) WHEN (g06.c688 is NOT NULL AND ab9.c48=33) THEN CONCAT(IFNULL(ADDTIME(ab9.ct1,''),''),',-',pm.c42,'-,') WHEN (d2.c688 is NOT NULL AND g06.c688 is NOT NULL) THEN CONCAT('',pm.c42,'-,',',','',pm.c42,'-,') WHEN (d2.c688 is NULL AND g06.c688 IS NULL) THEN NULL ELSE CONCAT('',pm.c42,'-,') END,',','') AS ab80,CAST(ADDTIME(pm.c31,'') AS DATE) AS prab22al_aaprv_dt,CAST(ADDTIME(pm.c1702,'') AS DATE) AS c1702,pm.c1703 AS c1703,CAST(ADDTIME(ab54.c688,'') AS DATE) AS c688,CAST(ADDTIME(pm.c23,'') AS DATE) AS c23,CAST(ADDTIME(ab54.c684,'') AS DATE) AS c684,CAST(ADDTIME(pm.c27,'') AS DATE) AS c27,CAST(ADDTIME(pm.c28,'') AS DATE) AS ab3,ab10.c53 AS ab2,ab42.c428 AS c428,bb1.c680 AS ab97,CASE WHEN op.c683=''THEN''WHEN op.c683=''THEN''ELSE op.c683 END AS c683,l.c687 AS c687,CASE WHEN op.c151=''THEN''WHEN op.c151=''THEN''ELSE op.c151 END AS c151,ab8.c680 AS c28ab87,ab15.c57 AS c29ab85,(SELECT ab93.c50 FROM t7 ab93 WHERE ab93.c48=pm.b3) AS c57,CONCAT(em.c75,'_',ab76.c71) AS c680,em.c75 AS c75,ab76.c71 AS c71,ab21.c15 AS c15,ab46.c37 AS c37,op.c001 AS c001,op.bl1 AS bl1,ab681.c31 AS c36 FROM (((((((((((((((((((((((((((((((((((t24 pm JOIN t27 ab21 on(ab21.c15=pm.c15 AND ab21.c15=6 AND ab21.c15=7)) JOIN t9 ab54 on(ab54.c42=pm.c42)) JOIN t5 ab76 on(ab76.c71=pm.c420)) JOIN t5 ju on(ju.c71=pm.c19)) JOIN t10 em on(em.c75=pm.c26)) JOIN t11 ab68 on(ab68.c30=pm.c30)) JOIN t12 op on(op.c42=pm.c42)) JOIN t13 om on(om.c42=pm.c42 AND om.c06='')) JOIN t14 ab42 on(ab42.c44=om.c44)) JOIN t14 ab41 on(ab41.c428=om.c44)) JOIN t16 bb1 on(bb1.c20=op.c20)) JOIN t3 l on(bb1.c49=l.c76)) JOIN t16 ab8 on(ab8.c20=op.c28)) JOIN t5 ab15 on(ab15.c71=op.c29)) JOIN t8 ab49 on(ab49.c42=pm.c42)) JOIN t4 ab37 on(ab37.c682=ab54.c682 AND ab37.c15=20)) JOIN t25 ag4 on(ag4.c42=pm.c42)) JOIN t25 g3 on(g3.c42=pm.c42 AND g3.c151=''AND g3.c681 IS NULL)) JOIN ab86 ab18 on(ab18.c683=ag4.c683)) JOIN ab86 ab17 on(ab17.c683=g3.c683)) JOIN t26 prab22alab11 on(prab22alab11.c8=g3.c8)) JOIN t26 prab22ale2 on(prab22ale2.c170=(SELECT ab22.c170 FROM t26 ab22 WHERE ab22.c5=31 AND ab22.c8=g3.c8 LIMIT 1))) JOIN t21 ab61 on(ab61.c15=pm.c15 AND ab61.c75=pm.c26)) JOIN e7 d2 on(d2.c687=ab61.c683)) JOIN e7 g06 on(g06.c687=ab61.c684)) JOIN t17 ab11 on(ab11.c42=pm.c42 AND ab11.c48=0)) JOIN t17 e2 on(e2.c42=pm.c42 AND e2.c48=29)) JOIN t17 ab10 on(ab10.c42=pm.c42 AND ab10.c48=40)) JOIN t17 ab9 on(ab9.c42=pm.c42 AND ab9.c48=33)) JOIN t18 ab32 on(ab32.c18=pm.c18)) JOIN t6 ab75 on(ab75.c53=pm.c420)) JOIN t23 ab46 on(ab46.c35=om.c35)) JOIN t11 ab681 on(ab681.c30=ab46.c36)) JOIN t7 u on(u.c48=ab11.c68)) JOIN t7 u3 on(u3.c48=ab9.c68)) WHERE (pm.c24 IS NULL OR pm.c24='') AND ab68.c31 is NOT NULL AND ab21.c2 is NOT NULL AND pm.c29 is NOT NULL AND pm.c42 NOT IN (0,0);
CREATE ALGORITHM=UNDEFINED DEFINER=root@localhost SQL SECURITY DEFINER VIEW e0 AS SELECT 'a' AS TYPE,ai.c680 AS ab100,ai.c75 AS c75,ai.c46 AS c46,l.c687 AS ab99,ai.c43 AS c43,p.c681 AS c681,ai.c47 AS PRODUCT,ai.c44 AS c44,ai.c42 AS c42,ai.c71 AS c71,ai.c420 AS c420,ai.c57 AS c57,ai.c31 AS c68,ai.c45 AS ab94,ai.ab3 AS ab3,substr(ai.prab22al_typ_nm,0,0)AS c423,ai.ab80 AS ab83,ai.ab79 AS approver_grouab22,ai.c22 AS ab82,l.c687 AS c687,ai.ab69 AS ab69,ai.c684 AS ab57,ai.c684 AS expected_ab57,ai.c683 AS ab98,ai.ab97 AS ab56,ai.c1702 AS c1702,ai.c428 AS ab40,ai.c27 AS ab39,ai.prab22al_aaprv_dt AS prab22al_aaprv_dt,ai.c72 AS a93,ai.c427 AS c427,ai.ab12 AS ab12,ai.ab12 AS ab14,ai.c20 AS c20,ai.c151 AS c151,ai.c28ab87 AS c28ab87,ai.ap AS ab7,CAST(NULL AS DATE) AS ab77,CAST(NULL AS char charSET utf8mb4) AS ab58,CAST(NULL AS char charSET utf8mb4) AS ab72,CAST(NULL AS DATE) AS ab71,CAST(NULL AS char charSET utf8mb4) AS ab70,CAST(NULL AS DATE) AS c56,CAST(NULL AS DATE) AS c55,CAST(NULL AS DATE) AS c53,CAST(NULL AS DATE) AS ab36,CAST(NULL AS DATE) AS ab35,CAST(NULL AS DATE) AS ab38_ab14,CAST(NULL AS char charSET utf8mb4) AS ab38_c427,CAST(NULL AS char charSET utf8mb4) AS c428,ai.c32 AS ab95,ai.c77 AS c77,ai.c35 AS ab84,CAST(NULL AS char charSET utf8mb4) AS c51,CASE WHEN ai.c15 IN (0,0,0) THEN ai.c23 + INTerval 12 month WHEN ai.c15 IN (0,0) THEN ai.c23 + INTerval 6 month END AS eb1,CAST(ADDTIME(ai.c23,'') AS DATE) AS c23 FROM (((ab51 ai JOIN t19 ab66 on(ai.c75=ab66.c75)) JOIN t3 l on(l.c76=ab66.c76)) JOIN t4 p on(p.c43=ai.c43)) UNION ALL SELECT 'no_a' AS TYPE,ai.c680 AS ab100,ai.c75 AS c75,ai.c46 AS c46,l.c687 AS ab99,NULL AS c43,NULL AS c681,ai.ab30 AS PRODUCT,ai.c44 AS c44,ai.c42 AS c42,ai.c71 AS c71,ai.c420 AS c420,ai.c57 AS c57,ai.c68 AS c68,ai.c45 AS ab94,ai.ab3 AS ab3,ai.c2 AS c423,NULL AS ab83,NULL AS approver_grouab22,NULL AS ab82,l.c687 AS c687,NULL AS ab69,NULL AS ab57,NULL AS expected_ab57,NULL AS ab98,NULL AS ab56,NULL AS c1702,NULL AS ab40,NULL AS ab39,NULL AS prab22al_aaprv_dt,NULL AS a93,NULL AS c427,NULL AS ab12,NULL AS ab14,NULL AS c20,NULL AS c151,NULL AS c28ab87,NULL AS ab7,ai.c52 AS ab77,ai.c47 AS ab58,CAST(NULL AS char charSET utf8mb4) AS ab72,CAST(NULL AS DATE) AS ab71,CAST(NULL AS char charSET utf8mb4) AS ab70,CAST(NULL AS DATE) AS c56,CAST(NULL AS DATE) AS c55,CAST(NULL AS DATE) AS c53,CAST(NULL AS DATE) AS ab36,CAST(NULL AS DATE) AS ab35,CAST(NULL AS DATE) AS ab38_ab14,CAST(NULL AS char charSET utf8mb4) AS ab38_c427,CAST(NULL AS char charSET utf8mb4) AS c428,CAST(NULL AS char charSET utf8mb4) AS ab95,CAST(NULL AS char charSET utf8mb4) AS c77,CAST(NULL AS char charSET utf8mb4) AS ab84,CAST(NULL AS char charSET utf8mb4) AS c51,CAST(NULL AS char charSET utf8mb4) AS eb1,CAST(NULL AS char charSET utf8mb4) AS c23 FROM ((ab55 ai JOIN t19 ab66 on(ai.c75=ab66.c75)) JOIN t3 l on(l.c76=ab66.c76)) UNION ALL SELECT 'ab54os_ab38' AS TYPE,nab38.c680 AS ab100,nab38.c75 AS c75,nab38.c46 AS c46,l.c687 AS ab99,nab38.c43 AS c43,nab38.c681 AS c681,nab38.c47 AS PRODUCT,nab38.c44 AS c44,nab38.c42 AS c42,nab38.c71 AS c71,nab38.c420 AS c420,nab38.c57 AS c57,nab38.c48 AS c68,nab38.c45 AS ab94,NULL AS ab3,nab38.c423 AS c423,NULL AS ab83,NULL AS approver_grouab22,NULL AS ab82,l.c687 AS c687,NULL AS ab69,NULL AS ab57,NULL AS expected_ab57,NULL AS ab98,NULL AS ab56,NULL AS c1702,NULL AS ab40,NULL AS ab39,NULL AS prab22al_aaprv_dt,NULL AS a93,NULL AS c427,NULL AS ab12,NULL AS ab14,NULL AS c20,NULL AS c151,NULL AS c28ab87,NULL AS ab7,CAST(NULL AS DATE) AS ab77,CAST(NULL AS char charSET utf8mb4) AS ab58,nab38.c52 AS ab72,nab38.c50 AS ab71,nab38.c429 AS ab70,nab38.c56 AS c56,nab38.c55 AS c55,nab38.c53 AS c53,nab38.c54 AS ab36,nab38.c49 AS ab35,nab38.c425 AS ab38_ab14,nab38.c427 AS ab38_c427,nab38.c428 AS c428,CAST(NULL AS char charSET utf8mb4) AS ab95,CAST(NULL AS char charSET utf8mb4) AS c77,CAST(NULL AS char charSET utf8mb4) AS ab84,nab38.c51 AS c51,CAST(NULL AS char charSET utf8mb4) AS eb1,CAST(NULL AS char charSET utf8mb4) AS c23 FROM ((t22 nab38 JOIN t19 ab66 on(nab38.c75=ab66.c75)) JOIN t3 l on(l.c76=ab66.c76));
DELIMITER //
CREATE PROCEDURE p() BEGIN DECLARE e3 INT; DECLARE e2 VARCHAR(30); INSERT INTO t2 VALUES (0,e2,e3,0); SELECT * FROM e0; INSERT INTO t2 VALUES (0,e2,e3,0); END//
DELIMITER ;
CALL p();
CALL p();
CREATE TABLE t (a INT);
INSERT DELAYED INTO t VALUES(1);
ALTER TABLE t AUTO_INCREMENT=1;

CREATE TABLE t1 (pk INT PRIMARY KEY) ENGINE=InnoDB;
ALTER TABLE t1 ADD CHECK (b <= 1);
COMMIT RELEASE;
ALTER TABLE t1 AUTO_INCREMENT=1;
SET SESSION sql_mode='NO_ZERO_DATE';
SET SESSION sql_buffer_result=ON;
SELECT CREATED INTO @c FROM information_schema.routines WHERE routine_schema='test' AND routine_name='a';

SET SESSION sql_buffer_result=1;
SET SQL_MODE='traditional';
SELECT event_name, created, last_altered FROM information_schema.events;

SET sql_buffer_result=1;
SET sql_mode=traditional;
SELECT created FROM information_schema.events;

SET @@sql_mode='no_zero_date';
SELECT * FROM sys.innodb_lock_waits;
SET storage_engine=MEMORY;
CREATE TABLE t5 SELECT NULL UNION SELECT NULL;
ALTER TABLE t5 ADD INDEX (`PRIMARY`);

SET storage_engine=InnoDB;
CREATE TABLE t5 SELECT NULL UNION SELECT NULL;
ALTER TABLE t5 ADD INDEX (`PRIMARY`);

SET storage_engine=MyISAM;
CREATE TABLE t5 SELECT NULL UNION SELECT NULL;
ALTER TABLE t5 ADD INDEX (`PRIMARY`);

SET storage_engine=Aria;
CREATE TABLE t5 SELECT NULL UNION SELECT NULL;
ALTER TABLE t5 ADD INDEX (`PRIMARY`);

SET SESSION storage_engine=MEMORY;
CREATE TABLE t SELECT NULL UNION SELECT NULL;
CREATE TABLE t2 AS SELECT * FROM t;
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TABLE t1 (c TEXT, UNIQUE(c(2))) ENGINE=InnoDB;
ALTER TABLE t1 ADD c2 TINYBLOB NOT NULL FIRST;
INSERT INTO t1 VALUES (1,'x'),(1,'d'),(1,'r'),(1,'f'),(1,'y'),(1,'u'),(1,'m'),(1,'b'),(1,'o'),(1,'w'),(1,'m'),(1,'q'),(1,'a'),(1,'d'),(1,'g'),(1,'x'),(1,'f'),(1,'p'),(1,'j'),(1,'c');

SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TABLE t1 (c VARCHAR(30) CHARACTER SET utf8, t TEXT CHARACTER SET utf8, UNIQUE (c (2)), UNIQUE (t (3))) ENGINE=InnoDB;
ALTER TABLE t1 ADD c2 TINYBLOB NOT NULL FIRST;
INSERT INTO t1 VALUES  (9,'w','w'), (2,'m','m'), (4,'q','q'), (0,NULL,NULL), (4,'d','d'), (8,'g','g'), (NULL,'x','x'), (NULL,'f','f'), (0,'p','p'), (NULL,'j','j'), (8,'c','c');

SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TABLE t1 (c VARCHAR(30) CHARACTER SET utf8, t TEXT CHARACTER SET utf8, UNIQUE (c (2)), UNIQUE (t (3)));
ALTER TABLE t1 ADD c2 TINYBLOB NOT NULL FIRST;
INSERT INTO t1 VALUES (8,'x','x'), (7,'d','d'), (1,'r','r'), (7,'f','f'), (9,'y','y'), (NULL,'u','u'), (1,'m','m'), (9,NULL,NULL), (2,'o','o'), (9,'w','w'), (2,'m','m'), (4,'q','q'), (0,NULL,NULL), (4,'d','d'), (8,'g','g'), (NULL,'x','x'), (NULL,'f','f'), (0,'p','p'), (NULL,'j','j'), (8,'c','c');
CREATE TABLE t1 (a TEXT, FULLTEXT INDEX (a));
SET SESSION sql_select_limit=0;
SELECT (SELECT 1 FROM (SELECT 1) f WHERE MATCH (a) AGAINST ('')) FROM t1;

SET SESSION sql_select_limit=0;
CREATE TABLE t (c TEXT CHARACTER SET utf8mb4, FULLTEXT INDEX (c));
SELECT (SELECT 1 FROM (SELECT 1) AS s WHERE MATCH (c) AGAINST ('')) FROM t;
SET character_set_connection=utf16;
INSERT INTO mysql.proc (db, name, type, specific_name, language, sql_data_access, is_deterministic, security_type, param_list, returns, body, definer, CREATEd, modified, sql_mode, COMMENT, character_set_client, collation_connection, db_collation, body_utf8) VALUES ('test', 'bug14233_1', 'FUNCTION', 'bug14233_1', 'SQL', 'reads_sql_data', 'NO', 'DEFINER', '', 'INT (10)', 'SELECT COUNT (*) FROM mysql.user', 'root@localhost', NOW(), '0000-00-00 00:00:00', '', '', '', '', '', 'SELECT COUNT (*) FROM mysql.user'), ('test', 'bug14233_2', 'FUNCTION', 'bug14233_2', 'SQL', 'reads_sql_data', 'NO', 'DEFINER', '', 'INT (10)', 'BEGIN declare x INT; SELECT COUNT (*) INTO x FROM mysql.user; END', 'root@localhost', NOW(), '0000-00-00 00:00:00', '', '', '', '', '', 'BEGIN declare x INT; SELECT COUNT (*) INTO x FROM mysql.user; END'), ('test', 'bug14233_3', 'PROCEDURE', 'bug14233_3', 'SQL', 'reads_sql_data','NO', 'DEFINER', '', '', 'alksj wpsj sa ^#!@ ', 'root@localhost', NOW(), '0000-00-00 00:00:00', '', '', '', '', '', 'alksj wpsj sa ^#!@ ');
SELECT * FROM information_schema.parameters WHERE specific_schema='test';

SET collation_connection=ucs2_general_ci;
INSERT INTO mysql.proc (db, name, type, specific_name, language, sql_data_access, is_deterministic, security_type, param_list, returns, body, definer, created, modified, sql_mode, comment, character_set_client, collation_connection, db_collation, body_utf8 ) VALUES ( 'a', 'a', 'FUNCTION', 'bug14233_1', 'SQL', 'READS_SQL_DATA', 'NO', 'DEFINER', '', 'int(10)', 'SELECT * FROM mysql.user', 'root@localhost', NOW(), '0000-00-00 00:00:00', '', '', '', '', '', 'SELECT * FROM mysql.user' );
SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME='a';

SET CHARACTER_SET_CONNECTION=ucs2;
INSERT INTO mysql.proc (db, name, type, specific_name, language, sql_data_access, is_deterministic, security_type, param_list, returns, body, definer, created, modified, sql_mode, comment, character_set_client, collation_connection, db_collation, body_utf8 ) VALUES ('test','bug14233_1','FUNCTION','bug14233_1','SQL','READS_SQL_DATA','NO','DEFINER','','int(10)','SELECT COUNT(*) FROM mysql.user','root@localhost', NOW() , '0000-00-00 00:00:00','','','','','','SELECT COUNT(*) FROM mysql.user');
SHOW FUNCTION STATUS WHERE db=DATABASE();

SET collation_connection='utf32_bin';
INSERT INTO mysql.proc (db, name, type, specific_name, language, sql_data_access, is_deterministic, security_type, param_list, returns, body, definer, CREATEd, modified, sql_mode, comment, CHARACTER_SET_client, collation_connection, db_collation, body_utf8) VALUES ('test', 'bug14233_1', 'FUNCTION', 'bug14233_1', 'SQL', 'READS_SQL_DATA', 'NO', 'DEFINER', '', 'INT (10)', 'SELECT COUNT (*) FROM mysql.USEr', 'root@localhost', NOW(), '0000-00-00 00:00:00', '', '', '', '', '', 'SELECT COUNT (*) FROM mysql.USEr'), ('test', 'bug14233_2', 'FUNCTION', 'bug14233_2', 'SQL', 'READS_SQL_DATA', 'NO', 'DEFINER', '', 'INT (10)', 'begin declare x INT; SELECT COUNT (*) INTO x FROM mysql.USEr; end', 'root@localhost', NOW(), '0000-00-00 00:00:00', '', '', '', '', '', 'begin declare x INT; SELECT COUNT (*) INTO x FROM mysql.USEr; end'), ('test', 'bug14233_3', 'PROCEDURE', 'bug14233_3', 'SQL', 'READS_SQL_DATA','NO', 'DEFINER', '', '', 'alksj wpsj sa ^#!@ ', 'root@localhost', NOW(), '0000-00-00 00:00:00', '', '', '', '', '', 'alksj wpsj sa ^#!@ ');
SELECT SPECIFIC_SCHEMA, SPECIFIC_NAME, PARAMETER_NAME, DATA_TYPE, DATETIME_PRECISION FROM INFORMATION_SCHEMA.PARAMETERS WHERE SPECIFIC_SCHEMA='i_s_parameters_test';
# mysqld options required for replay: --log-bin 
SET GLOBAL autocommit=0;
SET GLOBAL event_scheduler= ON;
SET timestamp=12345;
CREATE TABLE t1 (c1 INT ZEROFILL NULL);
CREATE EVENT e1 ON SCHEDULE AT current_timestamp + INTERVAL 1 DAY DO INSERT INTO t1 VALUES (1);
SELECT SLEEP (3);
CREATE TABLE t(c POINT NOT NULL) ENGINE=InnoDB;
DROP TABLE mysql.innodb_table_stats;
CREATE SPATIAL INDEX i ON t(c);
DELIMITER __
CREATE PROCEDURE p() BEGIN EXPLAIN INSERT INTO t SELECT 1;END__
DELIMITER ;
CREATE TABLE t (c int);
CALL p;
CALL p;
CREATE TABLE t(a VARCHAR(16383) CHARACTER SET UTF32, KEY k(a)) ENGINE=InnoDB;
SET SESSION sql_buffer_result=ON;
SET SESSION big_tables=ON;
SELECT DISTINCT COUNT(DISTINCT a) FROM t;

SET SESSION sql_buffer_result=1;
CREATE TABLE t (c INT) ENGINE=InnoDB;
SELECT GROUP_CONCAT(c ORDER BY 2) FROM t;

# Excute via C based client
CREATE TABLE t (grp INT,c CHAR);
SET sql_buffer_result=1;
SELECT grp,GROUP_CONCAT(c ORDER BY 2) FROM t GROUP BY grp;

# Must be executed at the command line
SET sql_buffer_result=1;
CREATE TABLE t (c1 INT,c2 INT);
SELECT c1,GROUP_CONCAT(c2 ORDER BY 2) FROM t GROUP BY c1;
CREATE TABLE t (pk INT PRIMARY KEY);
SELECT SHA(pk) IN (SELECT * FROM (SELECT '' FROM t) AS a) FROM t;
SET GLOBAL innodb_trx_rseg_n_slots_debug=1;
CREATE TABLE t (b TEXT, FULLTEXT (b)) ENGINE=InnoDB;
INSERT INTO t VALUES ('a');
DELETE FROM t;

CREATE TABLE t (a INT KEY,message CHAR,FULLTEXT (message)) ENGINE=InnoDB COMMENT='';
INSERT INTO t VALUES (11384,2),(11392,2);
DELETE FROM t;
SELECT SLEEP;
SET GLOBAL innodb_adaptive_flushing_lwm=0.0;
CREATE TABLE t (c DOUBLE) ENGINE=InnoDB;
SET GLOBAL innodb_io_capacity=18446744073709551615;
SELECT SLEEP (3);

SET GLOBAL innodb_adaptive_flushing_lwm=0.0;
SET GLOBAL innodb_max_dirty_pages_pct_lwm=0.000001;
CREATE TABLE t (c DOUBLE) ENGINE=InnoDB;
SET GLOBAL innodb_io_capacity=18446744073709551615;
SHOW WARNINGS;
SELECT @@innodb_io_capacity;
SELECT @@innodb_io_capacity_max;
SELECT SLEEP (3);
SET SQL_MODE='';
CREATE TABLE t (c BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY) ENGINE=MEMORY;
INSERT INTO t VALUES ('-9e999999');
ALTER TABLE t PARTITION BY KEY();
INSERT t VALUES (1);
SET optimizer_switch='derived_merge=off';
CREATE TABLE t (a INT) ENGINE=InnoDB;
PREPARE s FROM 'SELECT * FROM (SELECT * FROM t) AS d';
EXECUTE s;
SET optimizer_switch='default';
SET big_tables='on';
EXECUTE s;
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TABLE t (c INT) ENGINE=MyISAM;
INSERT INTO t VALUES (1),(2),(3),(4);
ALTER TABLE t ADD COLUMN (a INT);
DELETE FROM t;
ALTER TABLE t ADD COLUMN (b INT);

SET GLOBAL innodb_limit_optimistic_insert_debug = 2;
CREATE TABLE t1 (c1 VARCHAR(10));
INSERT INTO t1 VALUES (41), (42), (43), (44);
ALTER TABLE t1 ADD COLUMN (i INT);
DELETE FROM t1;
ALTER TABLE t1 ADD COLUMN (b INT);
SET SESSION optimizer_trace="enabled=on";
CREATE TABLE t1 (i INT) ENGINE=InnoDB;
CREATE TABLE t2 (c INT) ENGINE=MyISAM;
INSERT INTO t2 VALUES (1);
SELECT 1 FROM (SELECT 1 IN (SELECT 1 FROM t1 WHERE (SELECT 1 FROM t2 HAVING c)) FROM t2) AS z;

SET SESSION default_tmp_storage_engine=MEMORY;
SET optimizer_trace="enabled=on";
CREATE TABLE t1 (a INT, KEY USING BTREE (a)) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t2 (b CHAR(60));
INSERT INTO t2 VALUES (0);
SELECT 1 FROM (SELECT 1 IN (SELECT 1 FROM t1 WHERE (SELECT 1 FROM t2 HAVING b) NOT IN (SELECT 1 FROM t2)) FROM t2) AS z;

SET SESSION optimizer_trace=1;
CREATE TABLE t1 (c INT) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t2 (b INT) ENGINE=MEMORY;
INSERT INTO t2 VALUES (1);
EXPLAIN SELECT 1 FROM (SELECT 1 IN (SELECT 1 FROM t1 WHERE (SELECT 1 FROM t2 HAVING b) NOT IN (SELECT 1 FROM t2)) FROM t2) AS z;

SET SESSION optimizer_trace=1;
CREATE TABLE t1 (c VARCHAR(1)) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t2 (b VARCHAR(1)) ENGINE=MEMORY;
INSERT INTO t2 VALUES (1);
EXPLAIN SELECT 1 FROM (SELECT 1 IN (SELECT 1 FROM t1 WHERE (SELECT 1 FROM t2 HAVING b) NOT IN (SELECT 1 FROM t2)) FROM t2) AS z;

# mysqld options required for replay: --innodb-buffer-pool-size=300M
SET sql_mode='';
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
SET GLOBAL innodb_disable_resize_buffer_pool_debug=OFF;
CREATE TABLE t1 (a TIME, b DATETIME, KEY(a), KEY(b)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (2775,974),(2775,975),(2775,976),(2778,977),(2778,978),(2782,979),(2790,986),(2790,1139),(2792,840),(2792,984),(2792,989),(2793,982),(2793,992),(2793,993),(2793,994),(2795,323),(2795,332),(2797,980),(2797,997),(2797,998),(2798,1103),(2798,1104),(2799,841),(2799,985),(2799,988),(2833,983),(2833,990),(2833,991),(2834,981),(2834,995),(2834,996),(2835,316),(2835,317),(3007,854),(3007,856),(3008,855),(3008,857),(3009,823),(3009,824),(3014,1),(3015,1),(3016,2),(3017,2),(3018,3),(3019,3),(3024,842),(3024,843),(3024,844),(3025,845),(3025,846),(3025,847),(3040,31),(3041,32),(3042,52),(3042,55),(3043,53),(3043,54),(3044,278),(3044,279),(3044,280),(3044,281),(3044,282),(3044,283),(3044,284),(3044,285),(3045,1),(3046,1),(3049,220),(3050,221),(3050,222),(3051,2),(3052,2),(3053,223),(3054,224),(3055,225),(3056,226),(3057,227),(3058,228),(3059,229),(3060,327),(3066,236),(3067,237),(3068,238),(3069,239),(3070,240),(3080,241),(3081,242),(3082,247),(3083,248),(3084,249),(3085,250),(3086,251),(3087,252),(3088,253),(3089,254),(3090,255),(3091,256),(3092,257),(3093,258),(3094,259),(3096,263),(3097,264),(3100,273),(3100,302),(3101,266),(3102,267),(3103,268),(3104,269),(3105,270),(3111,275),(3112,238),(3113,272),(3115,286),(3116,318),(3116,319),(3117,290),(3117,292),(3118,238),(3119,291),(3119,293),(3120,304),(3121,305),(3122,306),(3123,307),(3124,308),(3125,309),(3126,310),(3127,311),(3128,312),(3128,336),(3129,313),(3129,350),(3130,314),(3131,315),(3131,351),(3132,325),(3132,328),(3134,502),(3138,334),(3139,338),(3139,339),(3140,340),(3140,341),(3141,344),(3141,345),(3142,346),(3142,347),(3149,351),(3149,354),(3150,351),(3150,356),(3152,358),(3152,359),(3153,361),(3153,370),(3154,363),(3154,369),(3156,350),(3156,371),(3159,376),(3160,377),(3160,379),(3160,384),(3161,378),(3161,380),(3161,383),(3162,388),(3162,389),(3162,390),(3169,392),(3169,393),(3169,394),(3170,395),(3170,396),(3170,397),(3171,398),(3171,399),(3171,400),(3172,401),(3172,402),(3172,403),(3173,404),(3173,405),(3173,406),(3178,351),(3178,421),(3190,411),(3190,412),(3191,413),(3191,414),(3192,415),(3192,416),(3193,417),(3193,418),(3194,419),(3194,420),(3195,353),(3195,424),(3196,425),(3196,426),(3197,427),(3197,428),(3198,429),(3198,430),(3199,431),(3199,432),(3200,433),(3200,434),(3201,435),(3201,436),(3202,437),(3202,438),(3203,439),(3203,440),(3204,441),(3204,442),(3205,443),(3205,444),(3206,445),(3206,446),(3207,447),(3207,448),(3208,449),(3208,450),(3209,451),(3209,452),(3210,453),(3210,454),(3211,455),(3211,456),(3212,457),(3212,458),(3213,459),(3213,460),(3214,461),(3214,462),(3215,463),(3215,464),(3218,466),(3218,467),(3218,468),(3219,469),(3219,470),(3219,471),(3220,474),(3220,475),(3220,476),(3221,477),(3221,478),(3221,479),(3222,480),(3222,481),(3223,482),(3223,483),(3224,484),(3224,485),(3225,486),(3225,487),(3227,503),(3227,505),(3228,506),(3228,507),(3230,508),(3230,509),(3231,510),(3231,511),(3232,512),(3232,513),(3233,514),(3233,515),(3234,516),(3234,517),(3235,518),(3235,519),(3237,521),(3237,522),(3239,524),(3239,525),(3240,526),(3240,527),(3241,528),(3241,529),(3242,530),(3242,531),(3243,532),(3243,533),(3244,534),(3244,535),(3245,536),(3245,537),(3246,538),(3246,539),(3252,540),(3252,541),(3254,543),(3254,544),(3254,545),(3255,547),(3255,548),(3255,571),(3256,550),(3256,551),(3256,572),(3257,553),(3257,554),(3257,573),(3258,556),(3258,557),(3258,574),(3259,559),(3259,560),(3259,575),(3260,561),(3260,562),(3260,563),(3261,565),(3261,576),(3262,566),(3262,567),(3263,568),(3263,569),(3263,570),(3264,577),(3264,578),(3265,579),(3265,580),(3266,581),(3266,582),(3266,591),(3267,583),(3267,584),(3267,592),(3268,585),(3268,586),(3268,593),(3269,587),(3269,588),(3269,594),(3270,589),(3270,590),(3271,595),(3271,596),(3271,597),(3272,598),(3272,599),(3273,600),(3273,601),(3273,602),(3274,603),(3274,604),(3274,605),(3275,606),(3275,607),(3275,608),(3276,609),(3276,610),(3276,611),(3277,612),(3277,613),(3277,614),(3278,615),(3278,616),(3279,617),(3279,618),(3279,619),(3279,628),(3279,629),(3280,620),(3280,621),(3280,622),(3281,623),(3281,624),(3281,625),(3282,626),(3282,825),(3283,630),(3283,631),(3284,632),(3284,633),(3284,634),(3285,635),(3285,940),(3286,638),(3286,639),(3286,640),(3287,641),(3287,642),(3287,643),(3288,644),(3288,645),(3288,646),(3289,647),(3289,648),(3289,649),(3290,650),(3290,651),(3290,652),(3291,653),(3291,654),(3291,655),(3292,656),(3292,657),(3292,658),(3293,659),(3293,660),(3293,661),(3294,662),(3294,663),(3294,664),(3295,665),(3295,666),(3295,667),(3296,668),(3296,669),(3296,670),(3297,671),(3297,672),(3297,673),(3298,674),(3298,675),(3298,676),(3299,677),(3299,678),(3299,679),(3300,680),(3300,681),(3300,682),(3301,683),(3301,684),(3301,685),(3302,686),(3302,687),(3302,688),(3303,689),(3303,690),(3303,691),(3304,692),(3304,693),(3304,694),(3305,695),(3305,696),(3305,697),(3306,698),(3306,699),(3306,700),(3307,701),(3307,702),(3307,703),(3308,704),(3308,705),(3308,706),(3309,707),(3309,708),(3310,709),(3310,710),(3311,711),(3311,712),(3311,713),(3312,714),(3312,715),(3312,716),(3313,717),(3313,1167),(3314,720),(3314,721),(3314,722),(3315,723),(3315,724),(3315,725),(3316,726),(3316,727),(3316,728),(3317,729),(3317,730),(3317,731),(3318,732),(3318,733),(3318,734),(3319,735),(3319,736),(3319,737),(3320,738),(3320,739),(3320,740),(3321,741),(3321,742),(3322,743),(3322,744),(3323,745),(3323,746),(3323,747),(3324,748),(3324,749),(3324,750),(3325,751),(3325,752),(3325,753),(3326,754),(3326,755),(3327,756),(3327,757),(3328,758),(3328,789),(3329,761),(3329,790),(3330,762),(3330,763),(3331,768),(3331,785),(3331,786),(3332,769),(3332,783),(3332,784),(3335,766),(3336,767),(3343,770),(3343,771),(3344,772),(3344,773),(3345,774),(3345,775),(3347,776),(3347,777),(3347,987),(3348,778),(3348,779),(3349,780),(3372,781),(3372,782),(3373,787),(3373,788),(3376,791),(3376,792),(3377,793),(3377,794),(3378,799),(3378,800),(3379,801),(3379,802),(3380,795),(3380,796),(3381,797),(3381,798),(3383,805),(3384,806),(3384,807),(3385,808),(3385,809),(3386,810),(3386,811),(3387,812),(3387,814),(3388,815),(3388,816),(3391,817),(3391,818),(3391,819),(3392,820),(3392,821),(3392,822),(3393,826),(3393,827),(3394,828),(3394,829),(3395,830),(3395,831),(3396,834),(3396,835),(3397,832),(3397,833),(3398,836),(3398,837),(3399,838),(3399,839),(3410,850),(3410,851),(3411,852),(3411,853),(3412,848),(3412,849),(3419,860),(3419,951),(3420,859),(3420,861),(3422,862),(3422,863),(3423,864),(3423,865),(3424,866),(3424,867),(3424,872),(3424,873),(3425,868),(3425,869),(3425,874),(3425,875),(3426,878),(3426,879),(3427,876),(3427,877),(3428,880),(3432,884),(3432,885),(3432,886),(3434,887),(3434,888),(3434,889),(3441,894),(3441,895),(3442,896),(3442,897),(3444,904),(3445,905),(3449,906),(3449,907),(3450,908),(3450,909),(3453,910),(3458,915),(3458,916),(3459,917),(3459,918),(3463,919),(3463,920),(3485,929),(3486,930),(3487,931),(3488,932),(3489,933),(3493,2),(3494,2),(3501,934),(3502,936),(3503,938),(3504,939),(3505,941),(3506,942),(3507,943),(3508,944),(3509,945),(3510,946),(3511,947),(3512,948),(3514,949),(3514,950),(3515,953),(3516,954),(3517,955),(3518,956),(3519,957),(3520,958),(3521,959),(3527,960),(3527,965),(3528,961),(3528,962),(3529,963),(3529,964),(3530,966),(3530,967),(3531,968),(3531,969),(3535,970),(3535,971),(3536,972),(3536,973),(3540,999),(3540,1000),(3541,1001),(8888,9999);
CREATE TEMPORARY TABLE t1 (a INT) ENGINE=InnoDB;
SET GLOBAL innodb_buffer_pool_size=16*1024*1024;
SELECT SLEEP(3);

# mysqld options required for replay: --max_allowed_packet=33554432 --innodb-buffer-pool-size=300M
SET GLOBAL innodb_disable_resize_buffer_pool_debug=OFF;
SET @inserted_value = REPEAT ('z', 33554431);
CREATE TEMPORARY TABLE t1 (c1 LONGTEXT NULL) ENGINE=InnoDB;
INSERT IGNORE INTO t1 VALUES (@inserted_value);
INSERT IGNORE INTO t1 VALUES (@inserted_value);
INSERT IGNORE INTO t1 VALUES (@inserted_value);
INSERT IGNORE INTO t1 VALUES (@inserted_value);
INSERT IGNORE INTO t1 VALUES (@inserted_value);
INSERT IGNORE INTO t1 VALUES (@inserted_value);
INSERT IGNORE INTO t1 VALUES (@inserted_value);
INSERT IGNORE INTO t1 VALUES (@inserted_value);
SET GLOBAL innodb_buffer_pool_size=1;
SELECT SLEEP (3);
# Repeat x times on 200 theads. x is usually very small.
# mysqld options required for replay: --log-bin
RESET MASTER TO 0x7FFFFFFF;
SET GLOBAL max_binlog_size=4096;
CREATE USER user@localhost;
SET PASSWORD FOR user@localhost=PASSWORD('a');
SET PASSWORD FOR user@localhost=PASSWORD('a');
SET PASSWORD FOR user@localhost=PASSWORD('a');
SET PASSWORD FOR user@localhost=PASSWORD('a');
SET PASSWORD FOR user@localhost=PASSWORD('a');
SET PASSWORD FOR user@localhost=PASSWORD('a');
SET PASSWORD FOR user@localhost=PASSWORD('a');
SET PASSWORD FOR user@localhost=PASSWORD('a');
SET PASSWORD FOR user@localhost=PASSWORD('a');
SET PASSWORD FOR user@localhost=PASSWORD('a');
CREATE TABLE t1 (c1 VARCHAR(10));
CREATE DEFINER=root@localhost EVENT e1 ON SCHEDULE EVERY '1' SECOND COMMENT 'a' DO DELETE FROM t1; 
SET GLOBAL innodb_lock_wait_timeout=347;
XA START 'b';
SET SESSION max_statement_time=65535;
INSERT INTO t1 VALUES (1),(2),(1);
SET GLOBAL event_scheduler=on;
CHANGE MASTER TO master_host='127.0.0.1';
START SLAVE sql_thread;
SELECT MASTER_POS_WAIT('MASTER-bin.000001', 1116, 300);

# mysqld options required for replay: --log-bin
SET sql_mode='';
SET GLOBAL max_binlog_size=2048;
RESET MASTER TO 2147483647;
CREATE TABLE t1 (c INT);
CREATE TEMPORARY TABLE t2 ENGINE=InnoDB AS SELECT * FROM performance_schema.file_summary_by_event_name;
CREATE TABLE t3 (a INT, b BINARY (70), c VARCHAR(70), d VARBINARY (70), e VARBINARY (70)) ENGINE=InnoDB;
INSERT INTO t3 VALUES (1111111111111111111,'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','aaaaaaaaaaaaaaaaaaaaaaaaa','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','a');
INSERT INTO t1 VALUES (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL), (NULL);
DROP TABLE t1;
CREATE TABLE t4 (c CHAR(70)) ENGINE=InnoDB;
CREATE TABLE t5 SELECT * FROM t4;

CREATE TABLE t (pk INT) ENGINE=InnoDB;
CREATE TRIGGER tr AFTER INSERT ON t FOR EACH ROW REPLACE INTO s VALUES(1);
XA START 'a';
INSERT INTO t VALUES(1);  # Gives error 'ERROR 1146 (42S02): Table 'test.s' doesn't exist'
REPLACE t VALUES(1);

CREATE TABLE t (a INT KEY,b CHAR(1)) ENGINE=InnoDB;
CREATE TABLE t2 (b INT,FOREIGN KEY(b)REFERENCES t (a)) ENGINE=InnoDB;
XA START 'x';
INSERT INTO t2 VALUES(1);  # Gives ERROR 1452 (23000): Cannot add or update a child row: a foreign key constraint fails (`test`.`t2`, CONSTRAINT `t2_ibfk_1` FOREIGN KEY (`b`) REFERENCES `t` (`a`))
REPLACE t2 VALUES(1);

SET sql_mode='';
CREATE TABLE t(a INT PRIMARY KEY) ENGINE=InnoDB;
CREATE TABLE t2(c INT);
XA START 'a';
SELECT d FROM t2;
SAVEPOINT x;
INSERT INTO t2 VALUES(0);
INSERT INTO t VALUES(0), (0);
INSERT INTO t VALUES(0);
ROLLBACK TO SAVEPOINT x;
CREATE OR REPLACE TABLE mysql.slow_log (a INT);
CREATE EVENT one_event ON SCHEDULE EVERY 10 SECOND DO SELECT 123;
SET GLOBAL slow_query_log=ON;
SET GLOBAL event_scheduler= 1;
SET GLOBAL log_output=',TABLE';
SET GLOBAL long_query_time=0.001;
SELECT SLEEP (3);

CREATE OR REPLACE TABLE mysql.slow_log (a INT);
DROP EVENT one_event;
CREATE EVENT one_event ON SCHEDULE EVERY 10 SECOND DO SELECT 123;
SET GLOBAL slow_query_log=ON;
SET GLOBAL event_scheduler= 1;
SET GLOBAL log_output=',TABLE';
SET GLOBAL long_query_time=0.001;
SELECT SLEEP (3);

SET sql_mode='';
CREATE OR REPLACE TABLE mysql.general_log (a INT) ENGINE=InnoDB;
CREATE TABLE t (c INT);
SET GLOBAL general_log=1;
SET GLOBAL log_output='TABLE,TABLE';
SET SESSION tx_read_only=1;
CREATE TABLE IF NOT EXISTS t1 (a INT UNIQUE, b INT) REPLACE SELECT 1 AS a, 1 AS b UNION SELECT 1 AS a, 2 AS b;
LOCK TABLES performance_schema.setup_consumers WRITE;
CREATE TEMPORARY TABLE t (c INT);
SET SESSION TRANSACTION READ ONLY;
INSERT INTO t VALUES(1);
INSERT INTO t VALUES(2);
CREATE TABLE t (c INT KEY) ENGINE=InnoDB;
INSERT INTO t VALUES(1),(2);
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
ALTER TABLE t ADD COLUMN d INT;
DELETE FROM t;
SELECT * FROM t WHERE c<>1 ORDER BY c DESC;

SET sql_mode='';
SET GLOBAL innodb_limit_optimistic_insert_debug=4;
CREATE TABLE t (c INT NOT NULL UNIQUE KEY);
INSERT INTO t VALUES(1),(2);
ALTER TABLE t ADD COLUMN c2 INT;
INSERT INTO t VALUES(3,0),(4,0);
DELETE FROM t;
SELECT * FROM t WHERE c<0 ORDER BY c DESC;
DELIMITER //
CREATE FUNCTION f() RETURNS INT BEGIN SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE,READ ONLY;RETURN 1;END;//
DELIMITER ;
CREATE TABLE t(c DECIMAL(0));
INSERT INTO t VALUES(f());

# mysqld options required for replay:  --log_bin_trust_function_creators=1
DELIMITER //
CREATE FUNCTION f() RETURNS INT BEGIN SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE,READ ONLY;RETURN 1;END;//
DELIMITER ;
CREATE TABLE t(c DECIMAL(0));
INSERT INTO t VALUES(f());
SET sql_mode='';
RENAME TABLE mysql.tables_priv TO mysql.tables_priv_bak;
CREATE TABLE t (c INT) ENGINE=InnoDB;
CREATE TABLE mysql.tables_priv SELECT * FROM mysql.tables_priv_bak;
GRANT SELECT ON t TO m@localhost;
# Repeat 2+ times
DROP DATABASE test;
CREATE DATABASE test;
USE test;
XA START 'a';
SET GLOBAL innodb_adaptive_hash_index='ON';
CREATE TEMPORARY TABLE t1(c INT) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t3(a INT) ENGINE=MERGE UNION=(t1,t2);
INSERT INTO t1(c) SELECT seq FROM seq_1_to_500;
LOAD INDEX INTO CACHE t3 KEY(b),t2 KEY(d);
INSERT INTO t1(c) SELECT seq FROM seq_1_to_500;
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET sql_mode='';
CREATE TABLE t3 (c1 VARCHAR(10));
ALTER TABLE t3 ENGINE=NonExistentEngine; SET GLOBAL wsrep_provider_options=NULL;SET GLOBAL query_cache_size=18446744073709547520;
# mysqld options required for replay:  --log_bin_trust_function_creators=1
SET sql_mode='';
DELIMITER //
CREATE FUNCTION f (arg CHAR(1)) RETURNS VARCHAR(1) BEGIN DECLARE v1 VARCHAR(1);DECLARE v2 VARCHAR(1);SET v1=CONCAT (LOWER (arg),UPPER (arg));SET v2=CONCAT (LOWER (v1),UPPER (v1));INSERT INTO t VALUES(v1), (v2);RETURN CONCAT (LOWER (arg),UPPER (arg));END;//
DELIMITER ;
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TEMPORARY TABLE t (c DEC);
INSERT INTO t SELECT f (1);

# mysqld options required for replay:  --log_bin_trust_function_creators=1
SET sql_mode='';
DELIMITER //
CREATE FUNCTION f () RETURNS INT BEGIN INSERT INTO t VALUES(1);RETURN 1;END; //
DELIMITER ;
CREATE TEMPORARY TABLE t(c INT);
INSERT INTO t SELECT f();
TRUNCATE TABLE mysql.user;SET collation_connection='tis620_bin';
SET @@session.character_set_server='tis620';
CREATE DATABASE a;
USE a;
CREATE TABLE t(c TEXT,FULLTEXT KEY f(c)) ENGINE=InnoDB;
INSERT INTO t VALUES(100);
ALTER TABLE t ADD (c2 INT);

SET collation_connection='tis620_bin';
SET @@session.character_set_server='tis620';
CREATE DATABASE a;
USE a
CREATE TABLE t1 (col text, FULLTEXT KEY full_text (col)) ENGINE = InnoDB;
INSERT INTO t1 VALUES(7693);
ALTER TABLE t1 ADD (col2 varchar(100) character set latin1);

SET collation_connection='tis620_bin';
SET @session_start_value=@@session.character_set_connection;
SET @@session.character_set_server=@session_start_value;
CREATE DATABASE `�\�\�\`;
USE `�\�\�\`;
CREATE TABLE t(col text,FULLTEXT KEY fullte (col));
INSERT INTO t VALUES(7693);
ALTER TABLE t ADD(col2 CHAR (100));

SET collation_connection='tis620_bin';#NOERROR
SET @session_start_value = @@session.character_set_connection;#NOERROR
SET @@session.character_set_server = @session_start_value;#NOERROR
CREATE DATABASE `�\�\�\`;#NOERROR
USE `�\�\�\`;#NOERROR
CREATE TABLE t1 (col text, FULLTEXT KEY full_text (col)) ENGINE = InnoDB;#NOERROR
INSERT INTO t1 VALUES(7693);#NOERROR
ALTER TABLE t1 ADD (col2 varchar(100) character set latin1); ;
SELECT SLEEP(3);
CREATE TABLE t (a VARCHAR(255), KEY k(a)) DEFAULT CHARSET=utf8 ENGINE=InnoDB;
ALTER TABLE t CHANGE a a VARCHAR(3000);
SELECT * FROM t WHERE a in ('');
SET SESSION TIME_ZONE= '+00:00';
CREATE TABLE t1 (pk INT PRIMARY KEY) ENGINE=InnoDB WITH SYSTEM VERSIONING PARTITION BY KEY() PARTITIONS 2;
INSERT INTO t1 VALUES (1),(2);
DELETE HISTORY FROM t1 BEFORE SYSTEM_TIME '2038-01-19 05:15:07.999999';
# mysqld options used (likely many or most are not required): --max_allowed_packet=33554432 --maximum-bulk_insert_buffer_size=1M --maximum-join_buffer_size=1M --maximum-max_heap_table_size=1M --maximum-max_join_size=1M --maximum-myisam_max_sort_file_size=1M --maximum-myisam_mmap_size=1M --maximum-myisam_sort_buffer_size=1M --maximum-optimizer_trace_max_mem_size=1M --maximum-preload_buffer_size=1M --maximum-query_alloc_block_size=1M --maximum-query_prealloc_size=1M --maximum-range_alloc_block_size=1M --maximum-read_buffer_size=1M --maximum-read_rnd_buffer_size=1M --maximum-sort_buffer_size=1M --maximum-tmp_table_size=1M --maximum-transaction_alloc_block_size=1M --maximum-transaction_prealloc_size=1M --log-output=none --sql_mode=ONLY_FULL_GROUP_BY --innodb_file_per_table=1 --innodb_flush_method=O_DIRECT --innodb_stats_persistent=off --loose-idle_write_transaction_timeout=0 --loose-idle_transaction_timeout=0 --loose-idle_readonly_transaction_timeout=0 --connect_timeout=60 --interactive_timeout=28800 --slave_net_timeout=60 --net_read_timeout=30 --net_write_timeout=60 --loose-table_lock_wait_timeout=50 --wait_timeout=28800 --lock-wait-timeout=86400 --innodb-lock-wait-timeout=50 --log_output=FILE --log-bin --log_bin_trust_function_creators=1 --loose-max-statement-time=30 --loose-debug_assert_on_not_freed_memory=0 --innodb-buffer-pool-size=300M
SET GLOBAL innodb_stats_persistent=1;#NOERROR
SET GLOBAL innodb_change_buffering_debug=1;#NOERROR
SET @@GLOBAL.innodb_limit_optimistic_insert_debug = 2;#NOERROR
CREATE TABLE t1(c1 DATE NULL, c2 BINARY(25) NOT NULL, c3 SMALLINT(4) NULL, c4 BINARY(15) NOT NULL PRIMARY KEY, c5 DATE NOT NULL UNIQUE KEY,c6 NUMERIC(10,8) NOT NULL DEFAULT 3.141592);#NOERROR                                               
ALTER TABLE t1 MODIFY COLUMN c2 YEAR(2); ;
SELECT SLEEP(3);   # Likely not required
use test
CREATE TABLE t1 (c1 int, UNIQUE INDEX (c1)) engine=innodb;
CREATE TABLE t2 (c1 int);
CREATE TEMPORARY TABLE t1 (c1 INT) ENGINE=MRG_MyISAM UNION=(t1,t2) INSERT_METHOD=LAST;
cache index t1,t2 in default;SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TABLE t (c INT(1)UNSIGNED AUTO_INCREMENT PRIMARY KEY,c2 CHAR(1)) ENGINE=InnoDB;
XA START 'a';
DELETE FROM t;
INSERT INTO t VALUES(0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (1,1);
INSERT INTO t VALUES(0,0), (0,0), (0,0), (0,0);

# Original testcase
SET sql_mode='';
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TABLE t (id INT(1)UNSIGNED AUTO_INCREMENT,fname CHAR(1),PRIMARY KEY(id)) DEFAULT CHARSET=latin1;
XA START 'xa_disconnect';
DELETE FROM t;
INSERT INTO t VALUES('',''), ('',''), ('',''), ('',''), ('',''), ('',''), ('-838:59:59','-838:59:59'), ('',''), ('',''), ('',''), ('00 00:00:04','00 00:00:04'), ('04 04:04:04','04 04:04:04'), ('34 22:59:57','34 22:59:57'), ('00 00:04','00 00:04'), ('05 05:05','05 05:05'), ('34 22:56','34 22:56'), ('05 05','05 05'), ('06 06','06 06'), ('34 22','34 22'), ('',''), ('','');
INSERT INTO t VALUES(0,'val8');
INSERT INTO t VALUES(0,'');
INSERT INTO t VALUES(0,1), (0,1), (0,1), (0,1);
CREATE TABLE t1 (a INT);
INSERT INTO t1 VALUES (1),(2);
CREATE TABLE t2 (b INT, c INT);
INSERT INTO t2 VALUES (1,10),(2,20);
CREATE TABLE t3 (d INT);
INSERT INTO t3 VALUES (1),(2);
CREATE PROCEDURE sp() SELECT * FROM t1 JOIN t2 JOIN t3 USING (x); 
CALL sp;
CALL sp;

CREATE TABLE t1 (c1 INT,c2 INT);
CREATE TABLE t2 (c INT,c2 INT);
CREATE PROCEDURE p2 (OUT i INT,OUT o INT) READS SQL DATA DELETE a2,a3 FROM t1 AS a1 JOIN t2 AS a2 NATURAL JOIN t2 AS a3;
CALL p2 (@c,@a);
CALL p2 (@a,@c);

CREATE TABLE t (c INT,c2 INT);
CREATE TABLE t2 (c INT,c2 INT);
CREATE PROCEDURE p (INOUT i1 INT,INOUT i2 TIME) DETERMINISTIC SELECT (SELECT (SELECT SUM(DISTINCT 'q')) OR (SELECT c3 FROM t AS a1 STRAIGHT_JOIN t AS a2 NATURAL JOIN t2 AS a3)) AND (SELECT (SELECT (SELECT c3 FROM t) AND(SELECT c3,c FROM t AS a1 JOIN t2 AS a2))) OR ( (SELECT c FROM t2) AND(SELECT c3,c FROM t)) OR (SELECT * FROM t);
CREATE TABLE t (c INT);
CALL p (@c,@b);
CREATE TEMPORARY TABLE t (c INT);
CALL p (@b,@c);
XA START 'a';
SET SESSION tx_read_only=1;
CREATE TEMPORARY TABLE t (c INT);
CREATE TEMPORARY TABLE t2 (c INT);
XA END 'a';
SET autocommit=0;
XA ROLLBACK 'a';
INSERT INTO t2 VALUES(0);
INSERT INTO t VALUES(0);
CREATE TABLE t (a INT KEY);
INSERT INTO t VALUES(0);
CREATE TEMPORARY TABLE t (c INT);
CREATE TEMPORARY TABLE t2 (c INT);
SET SESSION tx_read_only=ON;
SET autocommit=0;
INSERT INTO t2 VALUES(1);
INSERT INTO t VALUES(1);
CREATE TABLE t3 (c INT);
DELETE FROM t;
SET @value=REPEAT (1,5001);
CREATE TABLE t (a VARCHAR(5000),FULLTEXT (a));
INSERT IGNORE INTO t VALUES(@value);SET join_cache_level=3;
CREATE TABLE t1 (TEXT1 TEXT,TEXT2 TEXT,TEXT3 TEXT,TEXT4 TEXT,TEXT5 TEXT,TEXT6 TEXT,TEXT7 TEXT,TEXT8 TEXT,TEXT9 TEXT,TEXT10 TEXT,TEXT11 TEXT,TEXT12 TEXT,TEXT13 TEXT,TEXT14 TEXT,TEXT15 TEXT,TEXT16 TEXT,TEXT17 TEXT,TEXT18 TEXT,TEXT19 TEXT,TEXT20 TEXT,TEXT21 TEXT,TEXT22 TEXT,TEXT23 TEXT,TEXT24 TEXT,TEXT25 TEXT,TEXT26 TEXT,TEXT27 TEXT,TEXT28 TEXT,TEXT29 TEXT,TEXT30 TEXT,TEXT31 TEXT,TEXT32 TEXT,TEXT33 TEXT,TEXT34 TEXT,TEXT35 TEXT,TEXT36 TEXT,TEXT37 TEXT,TEXT38 TEXT,TEXT39 TEXT,TEXT40 TEXT,TEXT41 TEXT,TEXT42 TEXT,TEXT43 TEXT,TEXT44 TEXT,TEXT45 TEXT,TEXT46 TEXT,TEXT47 TEXT,TEXT48 TEXT,TEXT49 TEXT,TEXT50 TEXT) ENGINE=InnoDB;
EXPLAIN SELECT 1 FROM t1 NATURAL JOIN t1 AS t2;

# mysqld options required for replay:  --innodb_strict_mode=OFF
SET join_cache_level=6;
CREATE TABLE t1 (c01 CHAR(200), c02 CHAR(200), c03 CHAR(200), c04 CHAR(200), c05 CHAR(200), c06 CHAR(200), c07 CHAR(200), c08 CHAR(200), c09 CHAR(200), c10 CHAR(200), c11 CHAR(200), c12 CHAR(200), c13 CHAR(200), c14 CHAR(200), c15 CHAR(200), c16 CHAR(200), c17 CHAR(200), c18 CHAR(200), c19 CHAR(200), c20 CHAR(200), c21 CHAR(200), c22 CHAR(200), c23 CHAR(200), c24 CHAR(200), c25 CHAR(200), c26 CHAR(200), c27 CHAR(200), c28 CHAR(200), c29 CHAR(200), c30 CHAR(200), c31 CHAR(200), c32 CHAR(200), c33 CHAR(200), c34 CHAR(200), c35 CHAR(200), c36 CHAR(200), c37 CHAR(200), c38 CHAR(200), c39 CHAR(200), c40 CHAR(157)) ENGINE=InnoDB ROW_FORMAT=COMPRESSED;
CREATE TEMPORARY TABLE t3 LIKE t1;
SET optimizer_search_depth=1;
CREATE TABLE t4 (c1 INT NULL) ENGINE=InnoDB;
CREATE TABLE t2 (a INT NOT NULL, b INT, c INT, KEY(b), KEY(c), KEY(a)) ENGINE=InnoDB;
SELECT * FROM (t1 NATURAL JOIN t2) NATURAL LEFT JOIN (t3 NATURAL JOIN t4);
SET GLOBAL wsrep_provider_options='repl.max_ws_size=512';
DROP TABLE t1;SET GLOBAL join_buffer_space_limit=4095;
SET join_buffer_space_limit=DEFAULT;
CREATE TEMPORARY TABLE t (e INT,c CHAR(100),c2 CHAR(100),PRIMARY KEY(e),INDEX a(c)) ENGINE=InnoDB;
INSERT INTO t SELECT a.* FROM t a,t b,t c,t d,t e;
CREATE TABLE t (c DOUBLE,c2 INT,PRIMARY KEY(c));
SELECT GET_LOCK('a',1);
START TRANSACTION;
SET SESSION wsrep_trx_fragment_size=1;
INSERT INTO t VALUES(1,1), (1,2);
SELECT RELEASE_ALL_LOCKS();

SELECT GET_LOCK ("lock_bug26141_wait", 1000) INTO @a;
CREATE TABLE t (a BINARY (211));
CREATE TABLE t1 (c1 VARCHAR(10));
SET SESSION wsrep_trx_fragment_size=200;
SET AUTOCOMMIT=OFF;
INSERT INTO t1 VALUES(0xAADF);
SELECT QUOTE (REPLACE ('[SELECT COUNT(*) FROM t1 WHERE a=LEFT (@inserted_value, 130)]=1', CONCAT ('[', 'SELECT COUNT(*) FROM t1 WHERE a=LEFT (@inserted_value, 130)', ']'), '1'));
INSERT INTO t1 VALUES(123.4567e-1);
INSERT INTO t VALUES(34075,-70);
CREATE TABLE t570 (c1 INT);
SELECT RELEASE_ALL_LOCKS()=2 AS expect_1;CREATE TABLE t2 (d CHAR(1)KEY);
SET autocommit=0;
INSERT INTO t2 VALUES(1);
CREATE TEMPORARY SEQUENCE seq1 ROW_FORMAT=REDUNDANT;CREATE TABLE t (a INT,b INT,c INT,d INT,e INT,f INT GENERATED ALWAYS AS (a+b)VIRTUAL,g INT,h BLOB,i INT,UNIQUE KEY(d,h));
INSERT INTO t (a,b)VALUES(0,0), (0,0), (0,0), (0,0), (0,0);CREATE TABLE t (a CHAR,FULLTEXT KEY(a)) ENGINE=InnoDB;
ALTER TABLE t DISCARD TABLESPACE;
ALTER TABLE t ADD FULLTEXT INDEX (a);
# Repeat till server crashes (may take 20+ minutes)
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET GLOBAL innodb_limit_optimistic_insert_debug=7;
CREATE TABLE t1 (c1 INT) PARTITION BY HASH (c1) PARTITIONS 15;
SET GLOBAL innodb_change_buffering_debug=1;
DROP TABLE t1;
SELECT SUBSTRING ('00', 1, 1);
CREATE TABLE t (a DATE);
SET GLOBAL innodb_thread_concurrency=1;
SELECT * FROM t;
SET GLOBAL wsrep_ignore_apply_errors=0;
SET SESSION AUTOCOMMIT=0;
SET SESSION max_error_count=0;
CREATE TABLE t0 (id GEOMETRY,parent_id GEOMETRY)ENGINE=SEQUENCE;SET SQL_MODE='ORACLE';
CREATE TABLE t (c CHAR(1)) ENGINE=InnoDB;
INSERT INTO t VALUES(0), (1), (1), (1), (1);
SELECT * FROM t UNION SELECT * FROM t INTERSECT ALL SELECT * FROM t;

SET SQL_MODE='ORACLE';
CREATE TABLE t (c CHAR(1)) ENGINE=InnoDB;
SELECT * FROM t UNION SELECT * FROM t INTERSECT ALL SELECT * FROM t;USE mysql;
SELECT 1 INTO OUTFILE 'a' FROM DUAL;
DROP DATABASE mysql;
CREATE TABLE func (c INT) ENGINE=InnoDB;
DROP FUNCTION f;
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET GLOBAL binlog_checksum=NONE;
SHUTDOWN;
SET GLOBAL event_scheduler=1;
SELECT SLEEP (3);

SHUTDOWN;
SET GLOBAL event_scheduler=1;
SELECT SLEEP (3);
SET GLOBAL wsrep_replicate_myisam= ON;
CREATE TEMPORARY TABLE t1 (i INT, PRIMARY KEY pk (i)) ENGINE=MyISAM;
PREPARE stmt FROM "INSERT INTO t1 (id) SELECT * FROM (SELECT 4 AS i) AS y";
INSERT INTO t1 VALUES(4);

CREATE TABLE t (a INT KEY);
SET GLOBAL wsrep_replicate_myisam=ON;
PREPARE stmt FROM 'UPDATE mysql.user SET authentication_string=(?) WHERE USER=?';
INSERT INTO t VALUES (0xA7C3);CREATE TABLE t2 (c INT,d INT);
CREATE TABLE t (c CHAR(1)KEY,c2 CHAR(1));
ALTER TABLE t ADD COLUMN b INT;
CREATE VIEW v2 AS SELECT b FROM t2 JOIN t ON t2.b=t.a;
CREATE TABLE t (a TEXT,FULLTEXT KEY(a));
ALTER TABLE t ADD c TIMESTAMP;LOCK TABLES performance_schema.setup_instruments WRITE;
CREATE TEMPORARY TABLE t1 (i INT) ENGINE=InnoDB;
CREATE TEMPORARY TABLE tmp1 ENGINE=InnoDB SELECT * FROM t1;SET sql_mode='';
SET 'a';
SET collation_connection=utf6_unicode_520_ci;
SET GLOBAL session_track_system_variables='a';
SET GLOBAL event_scheduler=1;

SET sql_mode='ONLY_FULL_GROUP_BY';
SET 'a';
SET collation_connection=utf6_unicode_520_ci;
SET GLOBAL session_track_system_variables='a';
SET GLOBAL event_scheduler=1;
CREATE TEMPORARY TABLE t1 (c1 INT,c2 VARCHAR(3), INDEX (c1)) ENGINE=InnoDB;
CREATE TABLE t1 (c1 INT, c2 VARCHAR(3), KEY(c1,c2)) ENGINE=InnoDB;
DROP TABLE t1;
INSERT INTO t1 VALUES(1, 1), (2, 2);START SLAVE SQL_THREAD;
CHANGE MASTER TO IGNORE_DOMAIN_IDS=(1), MASTER_USE_GTID=SLAVE_POS;
FLUSH LOGS;
CHANGE MASTER TO master_use_gtid=current_pos;SET sql_mode='';
CREATE TABLE t (FTS_DOC_ID BIGINT UNSIGNED NOT NULL,title CHAR(1),body TEXT);
INSERT INTO t (title,body)VALUES(0,0), (0,0), (0,0), (0,0), (0,0), (0,0);
CREATE FULLTEXT INDEX idx1 ON t (title,body);
CREATE FULLTEXT INDEX idx1 ON t (title,body);
SET sql_mode='';
SET unique_checks=0;
SET foreign_key_checks=0;
CREATE TABLE ti (b INT,c INT,e INT,id INT,KEY (b),KEY (e),PRIMARY KEY(id));
INSERT INTO ti VALUES(0,0,0,0);
ALTER TABLE ti CHANGE COLUMN c c BINARY (1);
XA START 'a';
CREATE TEMPORARY TABLE t(a INT);
INSERT INTO t VALUES(1);
SAVEPOINT a3;
CREATE OR REPLACE TEMPORARY TABLE t (a INT,b INT);
INSERT INTO t VALUES(0,0);
INSERT INTO ti VALUES(0,0,0,0);
ROLLBACK TO SAVEPOINT a3;

CREATE TABLE t1 (c INT KEY) ENGINE=InnoDB;
SET SESSION foreign_key_checks=0;
SET SESSION unique_checks=0;
XA START 'a';
CREATE TEMPORARY TABLE t2 (c INT) ENGINE=InnoDB;
INSERT INTO t1 VALUES(0);
SAVEPOINT x;
INSERT INTO t2 VALUES(0);
INSERT INTO t1 VALUES(0);
ROLLBACK TO SAVEPOINT x;
SET SESSION foreign_key_checks=0;
SET SESSION unique_checks=0;
SET GLOBAL innodb_status_output_locks=1;
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE s (c1 INT KEY,c2 INT) ENGINE=InnoDB;
INSERT INTO s VALUES(1000000000,4618);
CREATE TABLE t (a INT,b VARCHAR(1),KEY (a)) ENGINE=InnoDB PARTITION BY RANGE (a) SUBPARTITION BY HASH (a) (PARTITION p0 VALUES LESS THAN (1) (SUBPARTITION sp0,SUBPARTITION sp),PARTITION p VALUES LESS THAN MAXVALUE (SUBPARTITION sp2,SUBPARTITION sp3));
XA START 'a';
INSERT INTO s VALUES(1000000000,0);
INSERT INTO t VALUES(2,0);
INSERT INTO s VALUES(8913,1), (8913,2), (8913,3), (8913,4), (8913,5), (8913,6), (8913,7), (8913,8), (8913,9);
SHOW ENGINE InnoDB STATUS;

DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET sql_mode='';
SET SESSION foreign_key_checks=OFF;
SET SESSION unique_checks=0;
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TABLE t1 (c1 INT PRIMARY KEY, c2 INT) ENGINE=InnoDB;
CREATE TABLE t2 (c1 VARBINARY (10) NULL) ENGINE=InnoDB;
XA START 'a';
DELETE FROM t2;
INSERT IGNORE INTO t2 VALUES(NULL);
INSERT INTO t2 VALUES(0),(0),(0),(0),(0),(0),(0),(0),(0);
INSERT INTO t1 VALUES(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0);
INSERT INTO t2 VALUES(0),(0),(0),(0);

DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET SESSION foreign_key_checks=0;
SET SESSION unique_checks=0;
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TABLE t (f INT,f1 INT);
CREATE TABLE t2 (id INT UNSIGNED AUTO_INCREMENT KEY,title CHAR(1),body TEXT,FULLTEXT idx (title,body));
XA START '0';
DELETE FROM t2 WHERE MATCH (title,body) AGAINST ('' IN BOOLEAN MODE);
INSERT INTO t2 (title) VALUES (''),(''),(''),(''),(''),(''),(''),(''),(''),('');
INSERT INTO t VALUES (1);
INSERT INTO t2 (title,body) VALUES ('','');
INSERT INTO t2 (title,body) VALUES ('','');
INSERT INTO t2 (title,body) VALUES ('','');

DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET sql_mode='';
SET foreign_key_checks=0;
SET unique_checks=0;
CREATE TABLE t (a INT)ENGINE= InnoDB PARTITION BY HASH (a) PARTITIONS 3;
INSERT INTO t VALUES (CONVERT (_ucs2 0x0645062C06440633 USING utf8));
INSERT INTO t VALUES (1),(2),(3),(4),(5);
# Ref bug report (add here later)

# Also test testcase with
# mysqld options required for replay:  --sql_mode=ONLY_FULL_GROUP_BY --maximum-range_alloc_block_size=1M --maximum-read_buffer_size=1M
SET @@session.max_error_count=-10;
SET profiling=1;
SELECT * FROM performance_schema.events_waits_history_long ORDER BY thread_id;
SET GLOBAL wsrep_slave_threads=12;CREATE FUNCTION f(i INT) RETURNS INT RETURN 1;
PREPARE s FROM "SELECT f('\0')";
EXECUTE s;
# Repeat 2-x times to crash
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET sql_mode='';
SET SESSION unique_checks=0,foreign_key_checks=0;
CREATE TABLE t (c INT,c2 INT) ENGINE=InnoDB;
INSERT INTO t VALUES (0,0);
XA START 'a';
UPDATE t SET c=0;
SAVEPOINT s;
CREATE TEMPORARY TABLE t2 (c INT PRIMARY KEY,c2 INT) ENGINE=InnoDB;
INSERT INTO t2 VALUES (0,0),(0,0);
UPDATE t SET c=0;
SAVEPOINT s;
SET @c:="SET SESSION collation_connection=utf32_spanish_ci";
PREPARE s FROM @c;
EXECUTE s;
CREATE PROCEDURE p (IN i INT) EXECUTE s;
SET SESSION character_set_connection=latin2;
SET @c:="SET @b=get_format(DATE,'EUR')";
PREPARE s FROM @c;
EXECUTE s;
CALL p (@a);
# Repeat until crash
# mysqld options required for replay: --log-bin 
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET @@SESSION.sql_mode='',@@GLOBAL.binlog_cache_size=256,@@GLOBAL.max_binlog_cache_size=18;
CREATE TABLE t(c BLOB,c2 INT,c3 DATE,KEY (c(1))) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t(c INT,c2 INT,c3 INT,KEY (c)) ENGINE=InnoDB;
CREATE TABLE t2(c DECIMAL(1),c2 YEAR,c3 BLOB) ENGINE=MyISAM;
SET @@GLOBAL.server_id=1;
XA START 'xid2';
INSERT INTO t2 VALUES('(QsMfc=^+N$=}t)nN8yC1wtrus_=X0q95en*rKi$-c2:8w&bh=VPpucn/&(FXO?F=c=/cwoDQ;#[:+V6N]_jw]Uk-,UF1=Ugb9q,zXOdviGa@9?xc:A','ﾟ･✿ヾ╲(｡◕‿◕｡)╱✿･ﾟ','#5i4=_@/X@^OfQgA"/bVL$p}=efKLIV{;H:p=iy0uN(=F8*[$#f)?qIbT6/]P*=@-s%WK=).,tH=A(;{cw@DcqyCiUu}E=:cA)v.c00OGc-GM,"P;o/t.Q;{ig%0)?Z$%qzLwO=),[1GDj;=(lSSmj3z{;r=r4=B+^Fdi;2K~Pq{@p46TnSNc4dIfiG]L&lW1K/:%n2lb;=+qYIUVt_w=-ae1N_Ke6~@}NWu"$6Pf{a22V"#Z$JRG1"qoNC${*S{Vt_ccvw([M+/S$xvSX}f)xSE=pJPemhngTv/Co1~:Oi:gHW9.5?G=)/*hQa=$uzgts7O;SvwI~EVtQ+-fw,]o;lShZHjG[AW5KVZiF[Ei)Cp3:~NRiPMVYjOk/UZYq4;$1jivN)BfgOHMfQquCzc0+%*tcD=_{A-a1#Qy3GMmNwc=~,$;ie[b=*{R@=#-(/%$r=O)01j=F1(V@Y$^ouupsApL~om?e~^gklTMl{("OgjRH6wSc$L~W+S;YtPG?Tdhxp;xZHJG=*%r+KnDnA)ps0_T9"7=ZP#=Ok)+t(meE.G;Wm::zuJ_0$rmH-yng*Y.}7gJYg*Vp=2+Vt~Nw5@=fEMwL_J^bOOz4&95bo)#=f"E;69x]R=qpJJt9=W[f8%FogGC=EO"vkdb6j');
INSERT INTO t SELECT * FROM t2;
SET @@SESSION.collation_connection=utf32_german2_ci;
INSERT INTO t VALUES('sk,fbr0/$g+Gn~BUkSCkx0+g=,2X=,^,cl~lcn=&[tqBOTHUTStz^j^-dn?=ud{/lR,LHtk,RN*(^4lKIDo=n^ONlBt$),=z60drS_20Js(_&A6ki?xyp;=d3a@RRyrH=eyTZoU=?uWMdp-yLas=Gg:+rH=%dH=VkfYyBw7K0/Tqa=R~dt=fW7#9=b3k_V:CA7sb98R=TtR=Y~lZ[pM["g=]JALi:$u/APg11*cp9Qcy_nT;G[Tg-c]7U{={)C=-eCia2=gQi.=:0KZnrqRJp8dUO~Rf@~$G=XU{ipdNs_]#PM+v*OdP{)"qW*lSE]=g06jc}Jaack4k,-s4iL~kHs#[Wz[WVN7X)H*I)TCIOXfax[#"gx?pRaqYQw_.:Vlm=b,+_-V3bccpQ?Plj3LiJxS]~oISRrW;G"*m27YhdHoyCl+~ZXi[v8ExpaD#=V=4huwy=Qoa#Jx={ItJo2dtT5+=Vs=35OHa:52=SI]6nWCLXzF3SPf}q"d%Un-iEzAm+v$pGh5*x0eum=H{&ws+T#KJy_Xa4Vo~*ARI,yp0lF{R("t=7#vM)?kVWz^qxrFBpH@/Nz,JG${]@dfAeV&dUdDVAI?$3)1iO,?JjxuW%@-DMt$9azV:YV=KugJkSuT?JyH)P47/vo={Wq_7(-No?Bh,9N=djSAYu&A,U^YF=J}:fEdc.mjv(*f*)o0+p[i,cjV^L1W=~h*5MwXlyKS%^=NW~qYt7a1#KA7;5.zTBAZ;*a3.f=U=&Q$:*_%nq~YDWMZcmEe:#IvV$P]:?nUVkoyn;02dR%FqL[4=9=sS6]d@$W{&8.[?{2l1Z$HFchrDr6-q{PdF9:','rn=dF;6ya3Mu#K/]jubOXhHbP)2Dg&X}PchQ^]Mqiqwsw0lF3S/Plks,+7Wi]hstBZ]fHk9olk_t}0-5N[w6J;ax0kg7DGlsxfVV9Ag~62Otvr#~P=a"@?HvLqc}(7t$b}8[dZlK1t(k"_1:GXj+97=-]8nh/]*"ILTGG"W(M=]:=JVy;Wt7slg(G$]~jh^=_^D,cd=_G?-YG:=t(xJ-em*eNW~zKdpBdLXM58=rq7*wa}=Eol9IY?o/{Od=dWR8L+X%@#Qd,hv;nIAO_=KQ1"Hk6:~pp67;reg8L)B+PRe,&z%bdD52kOl$vdLD~HBlslwno?w=s/)vP3/k9~I:&]}EGY=pk7q2O=SpgdBm*3?VwSwu]ZtBR6iX[d1wM@ea90A}A^cskt4#MsiDQ=gO+9p94dhaNN/Sd_Iig:BEW+D"L~zsKKDX9mitVZh?BsyjQ8F8E*="uK=W*wo-GNOP"(KFBS3DGCdnO,]TN-rYO2x%L-VfD,Hx}4R)K$}znE7@w=C@iMPI74kCA3[mCcvP}Zm,J(&7rckpaM6)0-{sM-;?#Kt_kTA{P2O"fsQRAr&8^NA77=?SNH;z=(:_}mMg.}=Ky#B5I^-wo+)&FFKq:c_n$dLqf"%L45KhZ8#@+zC/pZ=g=[D=v,$ha;BwPB+0QbJS.r=U&Y2lw#xMW+=G@a62~=@[;x"3rDRZ8).J*[.gcykBo=^t_rAQ=:Fk*llA=/$^Y.l}mQ;l=djh+F%8+Y{T;sqj[X9R#m-jX8=MrB4b;O3BplWAUl7-*FnY(-dMk.iG8fnE-.~v8&O^jMaKH~:OkhtXoJhtgMOZy_6#0zV0PK;x{@qjiR8:GBa+u{2p&SgI5+jwfN7^~q@9GDd0KTU}IqpFJKmB%QcEYu6gb%7uNO9XfZhkL6NLDT@+I.{tum}jS_&f=:XoyG:m"LhPw(G1ctH2sV:aI;6hfDx80QMhNI6?ownC;4iZsc5/{75NS].T60',CURRENT_TIMESTAMP(1));
DELETE FROM a3,a2 USING t AS a1 JOIN t AS a2 JOIN t2 AS a3;


# mysqld options required for replay: --log-bin 
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE t(c BLOB,c2 INT,c3 DATE,KEY (c(1))) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t(c INT,c2 INT,c3 INT,KEY (c)) ENGINE=InnoDB;
CREATE TABLE t2(c INT,c2 YEAR,c3 INT) ENGINE=MyISAM;
SET @@SESSION.sql_mode='',@@GLOBAL.binlog_cache_size=10,@@GLOBAL.max_binlog_cache_size=10,@@SESSION.collation_connection=utf32_german2_ci,@@GLOBAL.server_id=1;
XA START 'a';
INSERT INTO t2 VALUES(0,0,0);
INSERT INTO t SELECT * FROM t2;
INSERT INTO t VALUES('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',0);
DELETE FROM a,b USING t AS a JOIN t2 AS b;

# mysqld options required for replay: --log-bin 
SET GLOBAL binlog_cache_size=4096, max_binlog_cache_size=4096;
CREATE TABLE t(c TEXT) ENGINE=InnoDB;
CREATE TABLE t2(a INT) ENGINE=MyISAM;
INSERT INTO t VALUES(REPEAT('a',8192));
INSERT INTO t2 VALUES (1);
START TRANSACTION;
DELETE t.*, t2.* FROM t, t2;
CREATE TEMPORARY TABLE a (c INT) ENGINE=InnoDB;
CREATE TABLE b (c INT) ENGINE=InnoDB;
PREPARE s FROM 'SET STATEMENT binlog_format=ROW FOR SELECT * FROM b';
SELECT ST_ASTEXT (ST_GEOMFROMGEOJSON ("{ \"type\": \"GEOMETRYCOLLECTION\", \"coordinates\": [102.0, 0.0]}"));

SELECT ST_GEOMFROMGEOJSON ("{ \"type\": [ \"POINT\" ],\"coINates\": [0,0] }");
SET NAMES 'filename';
CREATE VIEW v2 AS SELECT 1;
SHOW TABLE STATUS;
SET @@global.wsrep_on=OFF;
XA START 'a';
SELECT GET_LOCK('test', 0) = 0 expect_1;
XA END 'a';
CACHE INDEX t1 PARTITION (ALL) KEY (`inx_b`,`PRIMARY`) IN default;
SELECT SLEEP(3);SET GLOBAL wsrep_cluster_address='a';
SET GLOBAL wsrep_slave_threads=0;SELECT * FROM ( ( (VALUES (3),(7),(1) LIMIT 2) ORDER BY 1 DESC)) AS dt;
CREATE TABLE t1 (a INT KEY, b TEXT) ENGINE=InnoDB;
XA START 'a';
SET unique_checks=0,foreign_key_checks=0,@@GLOBAL.innodb_limit_optimistic_insert_debug=2;
UPDATE t1 SET b=1;
CREATE TEMPORARY TABLE t2 (a INT, b INT) ENGINE=InnoDB;
INSERT INTO t1 VALUES (0,0),(1,1),(2,2);
INSERT INTO t2 VALUES (0);
INSERT INTO t1 VALUES (2,2),(3,3);
INSERT INTO t1 VALUES (4,4);

SET unique_checks=0,foreign_key_checks=0;
CREATE TABLE t1 (pk INT PRIMARY KEY) ENGINE=InnoDB;
START TRANSACTION;
DELETE FROM t1;
SAVEPOINT A;
INSERT t1 SELECT seq FROM seq_1_to_1000;
ROLLBACK TO SAVEPOINT A;
INSERT INTO t1 SELECT seq FROM seq_1_to_1000;
# mysqld options required for replay: --log-bin --sql_mode= --max_allowed_packet=20000000
SET GLOBAL max_binlog_stmt_cache_size=0;
CREATE TEMPORARY TABLE t (c INT) ENGINE=InnoDB;
SELECT @@GLOBAL.innodb_flush_method=variable_value FROM information_schema.global_variables;
DELETE FROM mysql.proc;
SET SESSION binlog_format=STATEMENT;
CREATE TEMPORARY TABLE t (i INT) UNION=(t);
ALTER TABLE t ADD extrac CHAR(1);SET foreign_key_checks=0,unique_checks=0;
CREATE TABLE t (i INT) ENGINE=InnoDB PARTITION BY HASH (i) PARTITIONS 3;
INSERT INTO t VALUES (0);
INSERT INTO t VALUES (0x40),(0x41),(0x42),(0x43),(0x44),(0x45),(0x46),(0x47);

SET foreign_key_checks=0, unique_checks=0;
CREATE TABLE t (i INT) ENGINE=InnoDB PARTITION BY HASH (i) PARTITIONS 3;
INSERT INTO t VALUES (0);
INSERT INTO t VALUES (64),(65),(66),(67);
DROP TABLE t;
SET GLOBAL session_track_system_variables='a';
SET SESSION session_track_system_variables=DEFAULT;
CREATE TABLE t1 (a INT NOT NULL) ENGINE=InnoDB;
ALTER TABLE t1 ADD c2 TEXT NOT NULL;
DROP TABLE t1;

CREATE TABLE t1 (a INT NOT NULL) ENGINE=InnoDB;
ALTER TABLE t1 FORCE;
DROP TABLE t1;
SET sql_mode='';
CREATE TABLE t (a INT,b INT) ENGINE=InnoDB PARTITION BY KEY(a) (PARTITION p0,PARTITION p);
INSERT INTO t (b) VALUES (1);
ALTER TABLE t ADD PRIMARY KEY(a);
DELETE FROM t;
CREATE TABLE t (a INT,b VARCHAR(1),KEY(a,b)) ENGINE=InnoDB;
ALTER TABLE t ADD COLUMN x INT GENERATED ALWAYS AS (a+b),ADD INDEX idx (x);
ALTER TABLE t CHANGE COLUMN b bb VARCHAR(256);
SET unique_checks=0,foreign_key_checks=0,autocommit=0;
CREATE TABLE t1 (c INT) ENGINE=InnoDB;
CREATE TABLE t2 (c INT) ENGINE=InnoDB;
LOCK TABLE t2 WRITE;
INSERT INTO t2 VALUES (1);
CREATE TABLE t1 (c INT) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t3 (a INT) ENGINE=InnoDB;
INSERT INTO t3 VALUES (1);
INSERT INTO t2 VALUES (2);
SET autocommit=OFF;
SET GLOBAL log_output=4;
CREATE TABLE t2 (user_str TEXT);
SET GLOBAL general_log=on;
INSERT INTO t2 VALUES (4978+0.75);
SET GLOBAL wsrep_cluster_address='';
SET SESSION wsrep_trx_fragment_size=1;
INSERT INTO t2 VALUES (10);
SAVEPOINT event_logging_1;
CREATE TABLE IF NOT EXISTS t3 (id INT) ENGINE=InnoDB;

CREATE TABLE t1 AS SELECT 1 AS c1;
SET GLOBAL wsrep_ignore_apply_errors=0;
SET SESSION wsrep_trx_fragment_size=1;
SET SESSION wsrep_trx_fragment_unit='statements';
SET AUTOCOMMIT=0;
CREATE TABLE t1 (id INT);
SAVEPOINT SVP001;CREATE TABLE t (t TEXT,FULLTEXT (t)) ENGINE=InnoDB;
ALTER TABLE t DISCARD TABLESPACE;
SET GLOBAL innodb_ft_aux_table='test/t';
SELECT * FROM information_schema.innodb_ft_deleted;
CREATE VIEW v1 AS SELECT table_name FROM information_schema.tables;
REPAIR VIEW v1;CREATE TABLE t1 (col INT);
INSERT INTO t1 VALUES (0xF4AB);
CREATE TEMPORARY TABLE t1 (c1 INT) ENGINE=mrg_myisam UNION=(t1) insert_method=FIRST;
SET GLOBAL wsrep_max_ws_rows=1;
DROP TABLES t1;
INSERT INTO t1 VALUES (6373);
CREATE TABLE t2 ENGINE=heap SELECT * FROM t1;

SET default_storage_engine="HEAP";
CREATE TABLE t1 (f1 BIGINT);
SET GLOBAL wsrep_max_ws_rows = 1;
INSERT INTO t1 VALUES (NOW()),(NOW()),(NOW());
INSTALL SONAME 'ha_rocksdb';
CREATE TEMPORARY TABLE tmp_rocksdb_0 (a CHAR(0)) ENGINE=RocksDB;
CREATE TABLE t1(c1 TIMESTAMP) ENGINE=INNODB;
CREATE UNIQUE INDEX i12 ON t1(c1);
SET GLOBAL wsrep_ignore_apply_errors=1;
CREATE TABLE t1 (a CHAR(1));
CREATE TABLE t1 (a CHAR(1));
SHOW PROCEDURE STATUS WHERE db = 'test';
SET GLOBAL read_only=1;

SET SESSION WSREP_ON=0;
FLUSH TABLES WITH READ LOCK AND DISABLE CHECKPOINT;
SET SESSION wsrep_on=1;
UNLOCK TABLES;
CREATE EVENT EVENT2 ON SCHEDULE AT current_timestamp ON COMPLETION NOT PRESERVE DO SELECT 1;
SET GLOBAL wsrep_cluster_address='';
SET GLOBAL event_scheduler=1;
SELECT SLEEP(1);
SELECT SLEEP(1);
SELECT SLEEP(1);

DROP DATABASE test;
SET GLOBAL wsrep_ignore_apply_errors=0;
CREATE USER dummy_user@localhost IDENTIFIED WITH dummy_plugin;
WITH t AS (SELECT * FROM t0 WHERE b=0) SELECT * FROM t0;

SET autocommit=FALSE;
ALTER TABLE mysql.columns_priv ENGINE=InnoDB;
FLUSH PRIVILEGES;

SET character_set_client=macroman,character_set_connection=36;
SELECT '' LIKE '' ESCAPE '�';
SET SESSION default_master_connection=REPEAT ('a',191);
SET lc_messages=ru_ru;
CHANGE MASTER TO master_host='dummy';
START SLAVE sql_thread;
CHANGE MASTER TO master_user='rpl',master_password='rpl';
CREATE TABLE t (a INT) ENGINE=InnoDB;
CREATE ALGORITHM=MERGE VIEW v AS SELECT 1*a AS a FROM t;
DROP TABLE t;
CREATE TABLE t (a GEOMETRY) ENGINE=InnoDB;
INSERT INTO v (a) VALUES (0);
SET @@global.slow_query_log = TRUE;
SET GLOBAL log_output = 'TABLE';
SET log_queries_not_using_indexes= TRUE;
SET @@local.slow_query_log = ON;
SET SESSION wsrep_trx_fragment_size = 64;
SELECT name, mtype, prtype, len FROM INFORMATION_SCHEMA.INNODB_SYS_COLUMNS WHERE name = 'p';
SELECT 1;
CREATE TABLE t1 (a INT, b CHAR(12), FULLTEXT KEY(b)) engine=InnoDB;
TRUNCATE t1;
CREATE TABLE t AS SELECT 1;SET character_set_client=filename;
CREATE VIEW v1 AS SELECT 1;
SELECT * FROM information_schema.geometry_columns;SET sql_mode='';
CREATE TABLE t1 (c INT PRIMARY KEY) ENGINE=MyISAM;
INSERT INTO t1 VALUES (0);
CREATE TABLE t2 (a INT NOT NULL) ENGINE=CSV;
CREATE TRIGGER tr AFTER INSERT ON t2 FOR EACH ROW INSERT INTO t2 VALUES (1);
INSERT INTO t2 VALUES (0); 
CHECK TABLE t2;
INSERT INTO t1 VALUES (0);
INSERT INTO t2 VALUES (0),(0); 
SET GLOBAL wsrep_mode=STRICT_REPLICATION;
CREATE VIEW v AS SELECT * FROM JSON_TABLE ('{"a":0}',"$" COLUMNS (a DECIMAL(1,1) path '$.a')) foo;SET @@global.wsrep_load_data_splitting=ON;
SET GLOBAL wsrep_replicate_myisam=ON;
CREATE TABLE t1 (c1 int) ENGINE=MYISAM;
LOAD DATA INFILE './t1.dat' IGNORE INTO TABLE t1 LINES TERMINATED BY '\n';CREATE TABLE t1 (id int(11)) ENGINE=InnoDB;
SET max_statement_time = 0.001;
LOCK TABLES t1 WRITE;
CREATE TRIGGER tr16 AFTER UPDATE ON t1 FOR EACH ROW INSERT INTO t1 VALUES (1);SET autocommit=0;
SET completion_type = 1;
CREATE TABLE t2(b TEXT CHARSET LATIN1) ENGINE=InnoDB;
INSERT INTO t2 VALUES (48717);
ROLLBACK RELEASE;

CREATE TABLE t3 (c1 INTEGER NOT NULL PRIMARY KEY, c2 FLOAT(3,2));
SET GLOBAL wsrep_provider_options = 'repl.max_ws_size=512';
SET @@autocommit=0;
INSERT INTO t3 VALUES (1000,0.00),(1001,0.25),(1002,0.50),(1003,0.75),(1008,1.00),(1009,1.25),(1010,1.50),(1011,1.75);
CREATE TABLE t1 ( pk int primary key) ENGINE=INNODB;# Repeat until server crashes (about 20 to 1000 attempts; quantity may vary signficantly)
SET MAX_STATEMENT_TIME=0.000001;
HELP 'a%';
HELP 'a%';
HELP 'a%';
HELP 'a%';
HELP 'a%';
HELP 'a%';
SET GLOBAL wsrep_provider_options='repl.max_ws_size=512';
CREATE TABLE t1 (c1 int);
CREATE TABLE t2 (c2 int);
CREATE TRIGGER tr AFTER INSERT ON t1 FOR EACH ROW UPDATE t2 SET t2.c2 = t2.c2+1;
DROP TABLE t1;
FLUSH TABLE t1;CREATE FUNCTION f() RETURNS INTEGER RETURN 1;
CREATE TABLE t (a INT);
CREATE VIEW v AS SELECT 2 FROM t WHERE f() < 3;
FLUSH TABLE v WITH READ LOCK;
CREATE TEMPORARY TABLE t (c INT) ENGINE=mrg_myisam UNION=(t,t2) insert_method=FIRST;
CREATE TABLE t2 LIKE t;# Warning: Memory not freed: 8/16/32

SET GLOBAL session_track_system_variables='a';
SHUTDOWN;
# mysqld options required for replay: --log_bin
CREATE TABLE a (c INT) ENGINE=InnoDB;
SET GLOBAL expire_logs_days=11;
SET GLOBAL innodb_disallow_writes=ON;
SET GLOBAL binlog_checksum=CRC32;
# mysqld options required for replay:  --log-bin
CREATE DATABASE db CHARACTER SET filename;
USE db;
CREATE TABLE t1 (a CHAR(209)) ENGINE=InnoDB;
CREATE TABLE t2 (c INT) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t3 (c INT) ENGINE=InnoDB;
SELECT * FROM t2 GROUP BY abc LIMIT 1;  # ERROR 1054 (42S22): Unknown column 'abc' in 'group statement'
INSERT INTO t1 VALUES (0);
SET @@character_set_client=swe7;
CREATE TABLE `#mysql50#abc``def`(id INT) ENGINE=InnoDB;

SET @@character_set_client=swe7;
CREATE TABLE `#mysql50#c@d`(a INT) ENGINE=InnoDB;
CREATE VIEW v AS SELECT 1 FROM (SELECT 1) AS d;
FLUSH TABLE v WITH READ LOCK;

CREATE VIEW v1 AS SELECT 1 FROM (SELECT 1) as d;
FLUSH TABLES v1 FOR EXPORT;

CREATE VIEW v(c) AS SELECT column_name FROM information_schema.columns;
FLUSH TABLE v WITH READ LOCK;
SET SESSION old_mode='';
ALTER TABLE mysql.innodb_index_stats MODIFY stat_description VARCHAR(1024) COLLATE utf8_bin;
CREATE TABLE t (a INT) ENGINE=InnoDB;

SET SESSION old_mode='';
CREATE TABLE t (a INT) ENGINE=InnoDB;
ALTER TABLE mysql.innodb_index_stats MODIFY stat_description VARCHAR(1024) COLLATE utf8_bin;
DROP TABLE t;

SET sql_mode='';
CREATE TABLE t (a ENUM ('','') DEFAULT'');
SET SESSION old_mode=no_progress_info;
ALTER TABLE mysql.innodb_index_stats MODIFY stat_description VARCHAR(1024) COLLATE utf8_bin;
INSERT INTO t VALUES (0,0,36,'','','','');
# Warning: Memory not freed: 32 on INSERT DELAYED
SET sql_mode='TRADITIONAL';
CREATE TABLE t (c BLOB) ENGINE=MyISAM;
INSERT DELAYED INTO t VALUES (''||'');
SHUTDOWN;
CREATE TABLE t (c1 INT, c2 DATE) TABLESPACE t STORAGE MEMORY;
PREPARE s FROM 'WITH RECURSIVE d AS (SELECT * FROM t UNION ALL SELECT 1 FROM d) SELECT * FROM d AS d1,d AS d2';
SHUTDOWN;
SET GLOBAL innodb_disallow_writes=ON;
# Exit the client, and execute: mysqladmin shutdown, server will hang

SET GLOBAL innodb_disallow_writes=ON;
SHUTDOWN;
SET GLOBAL wsrep_sst_auth=USER;
SHUTDOWN;
# Will lead to 'Warning: Memory not freed: 32' or similar
# mysqld options required for replay: --innodb-force-recovery=6
# mysqld options required for replay: --innodb-data-file-size-debug=1
SET foreign_key_checks=0;
SET SESSION unique_checks=0;
SET GLOBAL innodb_checksum_algorithm=CRC32;
SET SESSION AUTOCOMMIT=OFF;
CREATE TABLE t (c INT) ENGINE=InnoDB;
INSERT INTO t (c) VALUES (0);

SET sql_mode= '';
SET unique_checks=0;
SET GLOBAL innodb_checksum_algorithm=strict_CRC32;
CREATE TABLE t (c DOUBLE KEY,c2 BINARY (1),c3 TIMESTAMP);
SET foreign_key_checks=0;
INSERT INTO t VALUES ('','',''),('','','');
SET GLOBAL innodb_file_per_table=OFF;
CREATE TABLE t (c INT) ENGINE=InnoDB PARTITION BY LINEAR KEY(c) PARTITIONS 4;
LOCK TABLES t WRITE,t AS a READ;
ALTER TABLE t REBUILD PARTITION p0;
INSTALL PLUGIN spider SONAME 'ha_spider.so';
SET SESSION spider_same_server_link=ON;
CREATE SERVER d FOREIGN DATA WRAPPER mysql OPTIONS (HOST '127.0.0.1', DATABASE 'test', USER 'root', PORT 21562, PASSWORD '');
CREATE TABLE test_table (c1 int(11) NOT NULL, c2 TEXT DEFAULT NULL, PRIMARY KEY (c1)) ENGINE=SPIDER COMMENT='wrapper "mysql", table "test_table"'  PARTITION BY LIST (c1) (PARTITION pt0 VALUES IN (0) ENGINE = SPIDER, PARTITION pt1 VALUES IN (1) ENGINE=SPIDER COMMENT='srv "d"');
INSERT INTO test_table VALUES (100,'a');
SET sql_mode="no_zero_date";
SET GLOBAL wsrep_max_ws_rows=1;
CREATE TABLE t2 (a INT);
CREATE TABLE t1 (a INT NOT NULL PRIMARY KEY) ENGINE=InnoDB;
CREATE TRIGGER tgr BEFORE INSERT ON t1 FOR EACH ROW INSERT INTO t2 VALUES (0);
CREATE TABLE ti (id BIGINT NOT NULL PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO ti VALUES (1);
INSERT INTO t1 VALUES (0),(1);
# 280 bytes lost at 0x150bc0022480, allocated by T@0 at 0x55de58a978ba, mysys/array.c:71, mysys/hash.c:98, sql/sp.cc:2324, sql/sp.cc:2639, sql/item_create.cc:2601, sql/item_create.cc:2450, sql/sql_yacc.yy:10748
SET sql_mode= 'oracle';
WHILE f(8)<1 DO SELECT 1;
SHUTDOWN;
# mysqld options required for replay: --innodb_strict_mode=OFF
SET SESSION join_cache_level=5;
CREATE TABLE t3 (c INT) ENGINE=InnoDB;
CREATE TABLE t2 (c INT) ENGINE=InnoDB PARTITION BY RANGE (c)(PARTITION p0 VALUES LESS THAN (1),PARTITION p VALUES LESS THAN (2), PARTITION p2 VALUES LESS THAN (3));
CREATE TABLE t (c1 INT,c2 INT,c3 INT,c4 INT,c5 INT,c6 INT,c7 INT,c8 INT,c9 INT,c10 INT,c11 INT,c12 INT,c13 INT,c14 INT,c15 INT,c16 INT,c17 INT,c18 INT,c19 INT,c20 INT,c21 INT,c22 INT,c23 INT,c24 INT,c25 INT,c26 INT,c27 INT,c28 INT,c29 INT,c30 INT,c31 INT,c32 INT,c33 INT,c34 INT,c35 INT,c36 INT,c37 INT,c38 INT,c39 INT,c40 INT,c41 INT,c42 INT,c43 INT,c44 INT,c45 INT,c46 INT,c47 INT,c48 INT,c49 INT,c50 INT,c51 INT,c52 INT,c53 INT,c54 INT,c55 INT,c56 INT,c57 INT,c58 INT,c59 INT,c60 INT,c61 INT,c62 INT,c63 INT,c64 INT,c65 INT) ENGINE=InnoDB ROW_FORMAT=DYNAMIC;
SELECT * FROM (SELECT * FROM t NATURAL JOIN t3) as t NATURAL RIGHT JOIN (SELECT * FROM t NATURAL JOIN t2) AS t2;
DROP FUNCTION IF EXISTS f1;

SET SESSION join_cache_level=5;
CREATE TABLE t3 (c INT) ENGINE=InnoDB;
CREATE TABLE t2 (c INT) ENGINE=InnoDB PARTITION BY RANGE (c)(PARTITION p0 VALUES LESS THAN (1),PARTITION p VALUES LESS THAN (2), PARTITION p2 VALUES LESS THAN (3));
CREATE TABLE t1 (c1 INT,c2 INT,c3 INT,c4 INT,c5 INT,c6 INT,c7 INT,c8 INT,c9 INT,c10 INT,c11 INT,c12 INT,c13 INT,c14 INT,c15 INT,c16 INT,c17 INT,c18 INT,c19 INT,c20 INT,c21 INT,c22 INT,c23 INT,c24 INT,c25 INT,c26 INT,c27 INT,c28 INT,c29 INT,c30 INT,c31 INT,c32 INT,c33 INT,c34 INT,c35 INT,c36 INT,c37 INT,c38 INT,c39 INT,c40 INT) ENGINE=InnoDB;
SELECT * FROM (SELECT * FROM t1 JOIN t3) AS t NATURAL JOIN (SELECT * FROM t1 JOIN t2) AS t2;
DROP FUNCTION IF EXISTS f;
CREATE TABLE t1 (a VARCHAR(10)) ENGINE=InnoDB;
SET AUTOCOMMIT=0;
CREATE TABLE t3 (f1 INT) ENGINE=InnoDB;
ALTER TABLE t1 ADD c2 MEDIUMINT NOT NULL FIRST;
SET SESSION wsrep_trx_fragment_size=100;
HANDLER t3 OPEN;
INSERT INTO t1 VALUES (2,1),(NULL, 8);
CREATE TABLE t1 (a INT NOT NULL PRIMARY KEY) ENGINE=InnoDB;
SET GLOBAL default_tmp_storage_engine='DEFAULT';
USE test;
SET GLOBAL aria_encrypt_tables=1;
CREATE TABLE t (a INT AUTO_INCREMENT PRIMARY KEY, b INT) ENGINE=Aria;
INSERT INTO t VALUES (6,2);
ANALYZE NO_WRITE_TO_BINLOG TABLE t;

# mysqld options required for replay: --log-bin
SET SQL_MODE='',tmp_table_size = 65535;
CREATE TABLE t1(c INT) ENGINE=InnoDB;
CREATE TABLE t2(c INT) ENGINE=MyISAM;
XA BEGIN 'a';
SET GLOBAL aria_encrypt_tables=1;
INSERT INTO t1 SELECT * FROM t1;
CREATE TEMPORARY TABLE t1(a INT PRIMARY KEY) ENGINE=Aria;
INSERT INTO t1 VALUES (1);
DELETE FROM t2;
DELETE FROM t1;
LOAD INDEX INTO CACHE t1 IGNORE LEAVES;
SELECT * FROM INFORMATION_SCHEMA.user_privileges LIMIT 1;
INSERT INTO t1 VALUES (1);
INSERT INTO t1 VALUES (2);

SET SQL_MODE='',GLOBAL aria_encrypt_tables=1;
CREATE TABLE ti (a TINYINT, b TINYINT, c CHAR(79), d CHAR(63), e CHAR(24), f BINARY(8), g BLOB, h MEDIUMBLOB, id BIGINT PRIMARY KEY, KEY(b), KEY(e)) ENGINE=Aria;
CREATE TEMPORARY TABLE t1(a INT NOT NULL PRIMARY KEY, b INT, KEY(b)) ENGINE=Aria;
INSERT INTO t1 VALUES(0, 0);
DELETE FROM t1 WHERE a BETWEEN 0 AND 20;
INSERT INTO t1 SELECT a, b FROM t1;
INSERT INTO ti VALUES (1,2,'a','b','c','d','e','g',2);
INSERT INTO t1 VALUES(0, 'a');
INSERT INTO t1 VALUES(0, 'a');
# mysqld options required for replay: --log-bin
SET GLOBAL binlog_format=STATEMENT,GLOBAL event_scheduler=1;
CREATE EVENT e ON SCHEDULE EVERY 1 SECOND DO INSERT INTO t VALUES (1);
SET GLOBAL TRANSACTION ISOLATION LEVEL READ COMMITTED;
CREATE TABLE t (c INT);
# Then Check error log for: Event Scheduler: [root@localhost][test.e] Got error 170 "It is not possible to log this statement" from storage engine InnoDB
SET SESSION query_prealloc_size=8192;
SET max_session_mem_used=50000;
CREATE TABLE t1 (c1 INT NOT NULL) ENGINE=InnoDB ;
UPDATE t1 SET c1='1';
SET wsrep_trx_fragment_size=1;
SET SESSION AUTOCOMMIT=0;
INSERT INTO t1 VALUES (1);
SET @inserted_value=REPEAT ('z', 257);
CREATE TABLE t2 (a INT PRIMARY KEY) ENGINE=InnoDB ;
SELECT * FROM t1 WHERE c1='two';
UPDATE t1 SET c1='2';
INSERT INTO t2 VALUES (2);
INSERT INTO t2 VALUES (3);
INSERT INTO t2 VALUES (4);
INSERT INTO t2 VALUES (5);
CREATE VIEW v1 AS SELECT c1 FROM t1 WHERE c1 IN (SELECT a FROM t2) GROUP BY c1;
# mysqld options required for replay: --log_bin
SHOW BINLOG EVENTS FROM 120;
# Will produce 'Event invalid' in error log
# mysqld options required for replay: --log_bin --innodb-force-recovery=2
CREATE TABLE t (FTS_DOC_ID BIGINT UNSIGNED KEY,c CHAR(200),d TEXT) ENGINE=InnoDB;
ALTER TABLE t ADD FULLTEXT INDEX i(c);

# mysqld options required for replay:  --innodb-force-recovery=2
CREATE TABLE articles (id INT UNSIGNED KEY,title CHAR(1),body TEXT) DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci ENGINE=InnoDB;
CREATE FULLTEXT INDEX idx ON articles (body);
# mysqld options required for replay:  --tmp-disk-table-size=1024
SELECT * FROM information_schema.TRIGGERS ORDER BY trigger_name;
# Then check error log for: Incorrect information in file: './sys/sys_config.frm'
# mysqld options required for replay: --max-session-mem-used=8192
CREATE VIEW v AS SELECT 1;
PREPARE p FROM "SHOW CREATE VIEW v";
DROP VIEW v;
CREATE TABLE v ENGINE=InnoDB AS SELECT 1;
EXECUTE p;
SET GLOBAL log_bin_trust_function_creators=1;
DROP USER CURRENT_USER();
CREATE FUNCTION f1 (b INT) RETURNS INT RETURN 1;
CREATE VIEW v1 AS SELECT f1();
CREATE TABLE t1 (c1 INT UNSIGNED AUTO_INCREMENT NOT NULL UNIQUE KEY);
LOCK TABLES t1 WRITE, v1 READ;
CREATE VIEW v2 AS SELECT * FROM v1 WITH CASCADED CHECK OPTION;
SHUTDOWN;
# Then check error log for 'Warning: Memory not freed: 560' and similar
# mysqld options required for replay:  --innodb_page_size=4k --innodb_strict_mode=OFF
CREATE TABLE t (c1 INT,c2 INT,c3 INT,c4 INT,c5 INT,c6 INT,c7 INT,c8 INT,c9 INT,c10 INT,c11 INT,c12 INT,c13 INT,c14 INT,c15 INT,c16 INT,c17 INT,c18 INT,c19 INT,c20 INT,c21 INT,c22 INT,c23 INT,c24 INT,c25 INT,c26 INT,c27 INT,c28 INT,c29 INT,c30 INT,c31 INT,c32 INT,c33 INT,c34 INT,c35 INT,c36 INT,c37 INT,c38 INT,c39 INT,c40 INT,c41 INT,c42 INT,c43 INT,c44 INT,c45 INT,c46 INT,c47 INT,c48 INT,c49 INT,c50 INT,c51 INT,c52 INT,c53 INT,c54 INT,c55 INT,c56 INT,c57 INT,c58 INT,c59 INT,c60 INT,c61 INT,c62 INT,c63 INT,c64 INT,c65 INT,c66 INT,c67 INT,c68 INT,c69 INT,c70 INT,c71 INT,c72 INT,c73 INT,c74 INT,c75 INT,c76 INT,c77 INT,c78 INT,c79 INT,c80 INT,c81 INT,c82 INT,c83 INT,c84 INT,c85 INT,c86 INT,c87 INT,c88 INT,c89 INT,c90 INT,c91 INT,c92 INT,c93 INT,c94 INT,c95 INT,c96 INT,c97 INT,c98 INT,c99 INT,c100 INT,c101 INT,c102 INT,c103 INT,c104 INT,c105 INT,c106 INT,c107 INT,c108 INT,c109 INT,c110 INT,c111 INT,c112 INT,c113 INT,c114 INT,c115 INT,c116 INT,c117 INT,c118 INT,c119 INT,c120 INT,c121 INT,c122 INT,c123 INT,c124 INT,c125 INT,c126 INT,c127 INT,c128 INT,c129 INT,c130 INT,c131 INT,c132 INT,c133 INT,c134 INT,c135 INT,c136 INT,c137 INT,c138 INT,c139 INT,c140 INT,c141 INT,c142 INT,c143 INT,c144 INT,c145 INT,c146 INT,c147 INT,c148 INT,c149 INT,c150 INT,c151 INT,c152 INT,c153 INT,c154 INT,c155 INT,c156 INT,c157 INT,c158 INT,c159 INT,c160 INT,c161 INT,c162 INT,c163 INT,c164 INT,c165 INT,c166 INT,c167 INT,c168 INT,c169 INT,c170 INT,c171 INT,c172 INT,c173 INT,c174 INT,c175 INT,c176 INT,c177 INT,c178 INT,c179 INT,c180 INT,c181 INT,c182 INT,c183 INT,c184 INT,c185 INT,c186 INT,c187 INT,c188 INT,c189 INT,c190 INT,c191 INT,c192 INT,c193 INT,c194 INT,c195 INT,c196 INT,c197 INT,c198 INT,c199 INT,c200 INT,c201 INT,c202 INT,c203 INT,c204 INT,c205 INT,c206 INT,c207 INT,c208 INT,c209 INT,c210 INT,c211 INT,c212 INT,c213 INT,c214 INT,c215 INT,c216 INT,c217 INT,c218 INT,c219 INT,c220 INT,c221 INT,c222 INT,c223 INT,c224 INT,c225 INT,c226 INT,c227 INT,c228 INT,c229 INT,c230 INT,c231 INT,c232 INT,c233 INT,c234 INT,c235 INT,c236 INT,c237 INT,c238 INT,c239 INT,c240 INT,c241 INT,c242 INT,c243 INT,c244 INT,c245 INT,c246 INT,c247 INT,c248 INT,c249 INT,c250 INT,c251 INT,c252 INT,c253 INT,c254 INT,c255 INT,c256 INT,c257 INT,c258 INT,c259 INT,c260 INT,c261 INT,c262 INT,c263 INT,c264 INT,c265 INT,c266 INT,c267 INT,c268 INT,c269 INT,c270 INT,c271 INT,c272 INT,c273 INT,c274 INT,c275 INT,c276 INT,c277 INT,c278 INT,c279 INT,c280 INT,c281 INT,c282 INT,c283 INT,c284 INT,c285 INT,c286 INT,c287 INT,c288 INT,c289 INT,c290 INT,c291 INT,c292 INT,c293 INT,c294 INT,c295 INT,c296 INT,c297 INT,c298 INT,c299 INT,c300 INT,c301 INT,c302 INT,c303 INT,c304 INT,c305 INT,c306 INT,c307 INT,c308 INT,c309 INT,c310 INT,c311 INT,c312 INT,c313 INT,c314 INT,c315 INT,c316 INT,c317 INT,c318 INT,c319 INT,c320 INT,c321 INT,c322 INT,c323 INT,c324 INT,c325 INT,c326 INT,c327 INT,c328 INT,c329 INT,c330 INT,c331 INT,c332 INT,c333 INT,c334 INT,c335 INT,c336 INT,c337 INT,c338 INT,c339 INT,c340 INT,c341 INT,c342 INT,c343 INT,c344 INT,c345 INT,c346 INT,c347 INT,c348 INT,c349 INT,c350 INT,c351 INT,c352 INT,c353 INT,c354 INT,c355 INT,c356 INT,c357 INT,c358 INT,c359 INT,c360 INT,c361 INT,c362 INT,c363 INT,c364 INT,c365 INT,c366 INT,c367 INT,c368 INT,c369 INT,c370 INT,c371 INT,c372 INT,c373 INT,c374 INT,c375 INT,c376 INT,c377 INT,c378 INT,c379 INT,c380 INT,c381 INT,c382 INT,c383 INT,c384 INT,c385 INT,c386 INT,c387 INT,c388 INT,c389 INT,c390 INT,c391 INT,c392 INT,c393 INT,c394 INT,c395 INT,c396 INT,c397 INT,c398 INT,c399 INT,c400 INT,c401 INT,c402 INT,c403 INT,c404 INT,c405 INT,c406 INT,c407 INT,c408 INT,c409 INT,c410 INT,c411 INT,c412 INT,c413 INT,c414 INT,c415 INT,c416 INT,c417 INT,c418 INT,c419 INT,c420 INT,c421 INT,c422 INT,c423 INT,c424 INT,c425 INT,c426 INT,c427 INT,c428 INT,c429 INT,c430 INT,c431 INT,c432 INT,c433 INT,c434 INT,c435 INT,c436 INT,c437 INT,c438 INT,c439 INT,c440 INT,c441 INT,c442 INT,c443 INT,c444 INT,c445 INT,c446 INT,c447 INT,c448 INT,c449 INT,c450 INT,c451 INT,c452 INT,c453 INT,c454 INT,c455 INT,c456 INT,c457 INT,c458 INT,c459 INT,c460 INT,c461 INT,c462 INT,c463 INT,c464 INT,c465 INT,c466 INT,c467 INT,c468 INT,c469 INT,c470 INT,c471 INT,c472 INT,c473 INT,c474 INT,c475 INT,c476 INT,c477 INT,c478 INT,c479 INT,c480 INT,c481 INT,c482 INT,c483 INT,c484 INT,c485 INT,c486 INT,c487 INT,c488 INT,c489 INT,c490 INT,c491 INT,c492 INT,c493 INT,c494 INT,c495 INT,c496 INT,c497 INT,c498 INT,c499 INT,c500 INT,c501 INT,c502 INT,c503 INT,c504 INT,c505 INT,c506 INT,c507 INT,c508 INT,c509 INT,c510 INT,c511 INT,c512 INT,c513 INT,c514 INT,c515 INT,c516 INT,c517 INT,c518 INT,c519 INT,c520 INT,c521 INT,c522 INT,c523 INT,c524 INT,c525 INT,c526 INT,c527 INT,c528 INT,c529 INT,c530 INT,c531 INT,c532 INT,c533 INT,c534 INT,c535 INT,c536 INT,c537 INT,c538 INT,c539 INT,c540 INT,c541 INT,c542 INT,c543 INT,c544 INT,c545 INT,c546 INT,c547 INT,c548 INT,c549 INT,c550 INT,c551 INT,c552 INT,c553 INT,c554 INT,c555 INT,c556 INT,c557 INT,c558 INT,c559 INT,c560 INT,c561 INT,c562 INT,c563 INT,c564 INT,c565 INT,c566 INT,c567 INT,c568 INT,c569 INT,c570 INT,c571 INT,c572 INT,c573 INT,c574 INT,c575 INT,c576 INT,c577 INT,c578 INT,c579 INT,c580 INT,c581 INT,c582 INT,c583 INT,c584 INT,c585 INT,c586 INT,c587 INT,c588 INT,c589 INT,c590 INT,c591 INT,c592 INT,c593 INT,c594 INT,c595 INT,c596 INT,c597 INT,c598 INT,c599 INT,c600 INT,c601 INT,c602 INT,c603 INT,c604 INT,c605 INT,c606 INT,c607 INT,c608 INT,c609 INT,c610 INT,c611 INT,c612 INT,c613 INT,c614 INT,c615 INT,c616 INT,c617 INT,c618 INT,c619 INT,c620 INT,c621 INT,c622 INT,c623 INT,c624 INT,c625 INT,c626 INT,c627 INT,c628 INT,c629 INT,c630 INT,c631 INT,c632 INT,c633 INT,c634 INT,c635 INT,c636 INT,c637 INT,c638 INT,c639 INT,c640 INT,c641 INT,c642 INT,c643 INT,c644 INT,c645 INT,c646 INT,c647 INT,c648 INT,c649 INT,c650 INT,c651 INT,c652 INT,c653 INT,c654 INT,c655 INT,c656 INT,c657 INT,c658 INT,c659 INT,c660 INT,c661 INT,c662 INT,c663 INT,c664 INT,c665 INT,c666 INT,c667 INT,c668 INT,c669 INT,c670 INT,c671 INT,c672 INT,c673 INT,c674 INT,c675 INT,c676 INT,c677 INT,c678 INT,c679 INT,c680 INT,c681 INT,c682 INT,c683 INT,c684 INT,c685 INT,c686 INT,c687 INT,c688 INT,c689 INT,c690 INT,c691 INT,c692 INT,c693 INT,c694 INT,c695 INT,c696 INT,c697 INT,c698 INT,c699 INT,c700 INT,c701 INT,c702 INT,c703 INT,c704 INT,c705 INT,c706 INT,c707 INT,c708 INT,c709 INT,c710 INT,c711 INT,c712 INT,c713 INT,c714 INT,c715 INT,c716 INT,c717 INT,c718 INT,c719 INT,c720 INT,c721 INT,c722 INT,c723 INT,c724 INT,c725 INT,c726 INT,c727 INT,c728 INT,c729 INT,c730 INT,c731 INT,c732 INT,c733 INT,c734 INT,c735 INT,c736 INT,c737 INT,c738 INT,c739 INT,c740 INT,c741 INT,c742 INT,c743 INT,c744 INT,c745 INT,c746 INT,c747 INT,c748 INT,c749 INT,c750 INT,c751 INT,c752 INT,c753 INT,c754 INT,c755 INT,c756 INT,c757 INT,c758 INT,c759 INT,c760 INT,c761 INT,c762 INT,c763 INT,c764 INT,c765 INT,c766 INT,c767 INT,c768 INT,c769 INT,c770 INT,c771 INT,c772 INT,c773 INT,c774 INT,c775 INT,c776 INT,c777 INT,c778 INT,c779 INT,c780 INT,c781 INT,c782 INT,c783 INT,c784 INT,c785 INT,c786 INT,c787 INT,c788 INT,c789 INT,c790 INT,c791 INT,c792 INT,c793 INT,c794 INT,c795 INT,c796 INT,c797 INT,c798 INT,c799 INT,c800 INT,c801 INT,c802 INT,c803 INT,c804 INT,c805 INT,c806 INT,c807 INT,c808 INT,c809 INT,c810 INT,c811 INT,c812 INT,c813 INT,c814 INT,c815 INT,c816 INT,c817 INT,c818 INT,c819 INT,c820 INT,c821 INT,c822 INT,c823 INT,c824 INT,c825 INT,c826 INT,c827 INT,c828 INT,c829 INT,c830 INT,c831 INT,c832 INT,c833 INT,c834 INT,c835 INT,c836 INT,c837 INT,c838 INT,c839 INT,c840 INT,c841 INT,c842 INT,c843 INT,c844 INT,c845 INT,c846 INT,c847 INT,c848 INT,c849 INT,c850 INT,c851 INT,c852 INT,c853 INT,c854 INT,c855 INT,c856 INT,c857 INT,c858 INT,c859 INT,c860 INT,c861 INT,c862 INT,c863 INT,c864 INT,c865 INT,c866 INT,c867 INT,c868 INT,c869 INT,c870 INT,c871 INT,c872 INT,c873 INT,c874 INT,c875 INT,c876 INT,c877 INT,c878 INT,c879 INT,c880 INT,c881 INT,c882 INT,c883 INT,c884 INT,c885 INT,c886 INT,c887 INT,c888 INT,c889 INT,c890 INT,c891 INT,c892 INT,c893 INT,c894 INT,c895 INT,c896 INT,c897 INT,c898 INT,c899 INT,c900 INT,c901 INT,c902 INT,c903 INT,c904 INT,c905 INT,c906 INT,c907 INT,c908 INT,c909 INT,c910 INT,c911 INT,c912 INT,c913 INT,c914 INT,c915 INT,c916 INT,c917 INT,c918 INT,c919 INT,c920 INT,c921 INT,c922 INT,c923 INT,c924 INT,c925 INT,c926 INT,c927 INT,c928 INT,c929 INT,c930 INT,c931 INT,c932 INT,c933 INT,c934 INT,c935 INT,c936 INT,c937 INT,c938 INT,c939 INT,c940 INT,c941 INT,c942 INT,c943 INT,c944 INT,c945 INT,c946 INT,c947 INT,c948 INT,c949 INT,c950 INT,c951 INT,c952 INT,c953 INT,c954 INT,c955 INT,c956 INT,c957 INT,c958 INT,c959 INT,b BLOB) ENGINE=InnoDB;
ALTER TABLE t ROW_FORMAT=COMPRESSED;
# mysqld options required for replay: --enforce-storage-engine=InnoDB 
SET sql_mode='';
ALTER TABLE mysql.slow_log ENGINE=MyISAM;
SET tx_read_only=1;
SET SESSION long_query_time=0;
SET SESSION slow_query_log=1;
SET GLOBAL slow_query_log=1;
SET GLOBAL log_output='TABLE,FILE';
ALTER TABLE mysql.slow_log ENGINE=MyISAM;

# mysqld options required for replay: --log_bin --sql_mode=ONLY_FULL_GROUP_BY --max_allowed_packet=33554432 --maximum-bulk_insert_buffer_size=1M --maximum-join_buffer_size=1M --maximum-max_heap_table_size=1M --maximum-max_join_size=1M --maximum-myisam_max_sort_file_size=1M --maximum-myisam_mmap_size=1M --maximum-myisam_sort_buffer_size=1M --maximum-optimizer_trace_max_mem_size=1M --maximum-preload_buffer_size=1M --maximum-query_alloc_block_size=1M --maximum-query_prealloc_size=1M --maximum-range_alloc_block_size=1M --maximum-read_buffer_size=1M --maximum-read_rnd_buffer_size=1M --maximum-sort_buffer_size=1M --maximum-tmp_table_size=1M --maximum-transaction_alloc_block_size=1M --maximum-transaction_prealloc_size=1M --log-output=none --innodb_file_per_table=1 --innodb_flush_method=O_DIRECT --log-slow-rate-limit=2047 --tmp-memory-table-size=24
CREATE OR REPLACE TABLE mysql.general_log (a INT) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS t1 (a INT) SELECT 3 AS a;
SET GLOBAL general_log=ON;
SET GLOBAL log_output='TABLE,TABLE';
SET SESSION tx_read_only=1;
SET SESSION AUTOCOMMIT=0;
SELECT 't1 ROWs AFTER SMALL DELETE', COUNT(*) FROM t1;
SET SESSION tx_read_only=0;
INSERT INTO t1 VALUES (1);
SELECT SLEEP (3);
SET SESSION tx_read_only=1;  # added for looping
CREATE TABLE t (id INT KEY,a VARCHAR(16) collate utf8_unicode_ci DEFAULT'',INDEX (a (4))) DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci ENGINE=InnoDB;
ALTER TABLE t CHANGE a a VARCHAR(3000) CHARACTER SET utf8mb4;
INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) PARTITION BY LIST COLUMNS (c) (PARTITION p DEFAULT ENGINE=SPIDER);
INSERT INTO t VALUES (1);
DELETE FROM t;

INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) PARTITION BY LIST COLUMNS (c) (PARTITION p DEFAULT ENGINE=SPIDER);
DELETE FROM t;
DELETE FROM t;
CREATE TABLE t (a INT,b DATE,PRIMARY KEY(a,b)) ENGINE=InnoDB PARTITION BY RANGE (TO_DAYS (b)) SUBPARTITION BY HASH (a) SUBPARTITIONS 2 (PARTITION p0 VALUES LESS THAN (TO_DAYS ('2009-01-01')),PARTITION p VALUES LESS THAN (TO_DAYS ('2009-02-01')),PARTITION p2 VALUES LESS THAN (TO_DAYS ('2009-03-01')),PARTITION p3 VALUES LESS THAN MAXVALUE);
SELECT b,COUNT(DISTINCT a) FROM t GROUP BY b HAVING b is NULL;
SET sql_mode= '';
CREATE TEMPORARY TABLE t (c INT AUTO_INCREMENT KEY,c2 INT,INDEX idx (c2)) ENGINE=InnoDB;
CREATE UNIQUE INDEX i1 USING HASH ON t (c ASC);
INSERT INTO t VALUES ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','E0');
DELETE FROM t;
SET GLOBAL log_bin_trust_function_creators=ON;
CREATE FUNCTION f() RETURNS INT RETURN (SELECT 1 FROM t);
CREATE VIEW v AS SELECT f();
FLUSH TABLE v WITH READ LOCK;
SET sql_mode='', myisam_repair_threads=2;
CREATE TABLE t (id INT,a VARCHAR(1),b VARCHAR(1),c VARCHAR(1) GENERATED ALWAYS AS (CONCAT (a,b)),KEY(c)) ENGINE=MyISAM;
INSERT INTO t VALUES (0,0,9687,0);
REPAIR TABLE t QUICK;
CREATE TEMPORARY TABLE t (a INT) ENGINE=InnoDB;
CREATE TABLE t(a INT,b INT) ENGINE=InnoDB;
DROP TABLE t;
ALTER TABLE t DISCARD TABLESPACE;
SET sql_mode= 'TRADITIONAL';
ALTER TABLE t ADD c DATE NOT NULL;

CREATE TABLE t(a INT PRIMARY KEY) ENGINE=InnoDB;
ALTER TABLE t DISCARD TABLESPACE;
SET SQL_MODE='TRADITIONAL';
ALTER TABLE t ADD c DATE NOT NULL;
DROP TABLE t;
SET sort_buffer_size=1125899906842624;
CREATE TABLE t (a INT,b CHAR,KEY(a,b)) ENGINE=InnoDB;
DELETE a1 FROM t AS a1,t AS a2 WHERE a1.a=a2.a;

SET sort_buffer_size=100000000000;
CREATE TABLE t (a INT) ENGINE=InnoDB;
DELETE c FROM t AS c,t AS d WHERE c.a=d.a;
# mysqld options required for replay:  --innodb-read-only=1
# mysqld options required for replay:  --innodb-fatal-semaphore-wait-threshold=2
CREATE TABLE t (c INT) ENGINE=InnoDB;
SET GLOBAL innodb_disallow_writes=ON;
DROP TABLE t;
SET sql_mode='';
SET GLOBAL key_cache_segments=10;
SET GLOBAL key_buffer_size=20000;
CREATE TEMPORARY TABLE t (a INT KEY) ENGINE=MyISAM;
INSERT INTO t VALUES (1),(2);
SET GLOBAL key_cache_block_size=2048;
SELECT * FROM t UNION SELECT * FROM t;
SET SESSION tmp_disk_table_size=2047, big_tables=1;
SELECT table_name FROM information_schema.tables WHERE table_schema='sys' AND table_type='';
SET SESSION sql_mode='ALLOW_INVALID_DATES';
SELECT * FROM sys.x$innodb_lock_waits;
CREATE TABLE t (a INT,b TIME NOT NULL DEFAULT 1) ENGINE=MyISAM;
SELECT b FROM t GROUP BY b HAVING CEILING (b)>0;
INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=SPIDER PARTITION BY LIST COLUMNS (c) (PARTITION p DEFAULT ENGINE=SPIDER);
INSERT INTO t VALUES (1);
ALTER TABLE t CHECK PARTITION ALL;

INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=SPIDER PARTITION BY LIST COLUMNS (c) (PARTITION p DEFAULT ENGINE=SPIDER);
SELECT * FROM t;
ALTER TABLE t ENGINE=MEMORY;

CREATE TABLE t (c INT) PARTITION BY LIST COLUMNS (c) (PARTITION p DEFAULT ENGINE=SPIDER);
INSERT INTO t VALUES (0);
ALTER TABLE t ENGINE InnoDB;
INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT KEY,c2 INT,KEY(c2)) ENGINE=SPIDER PARTITION BY LIST COLUMNS (c) (PARTITION p DEFAULT ENGINE=SPIDER);
ALTER TABLE t ADD c2 BINARY FIRST;
SELECT * FROM t WHERE c2='' AND c2='' AND c='' ORDER BY c2 DESC;

# Then check error log for: [ERROR] Got error 12701 when reading table './test/t'

INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE SERVER d FOREIGN DATA WRAPPER mysql OPTIONS (HOST'',DATABASE'',USER'',PORT 10000,PASSWORD'');
CREATE TABLE t1 (c1 INT KEY,c2 INT) ENGINE=SPIDER PARTITION BY LIST COLUMNS(c1)(PARTITION p1 DEFAULT ENGINE=SPIDER);
SELECT c1,sum(c3) FROM t1;
SELECT * FROM t1 WHERE c1='838:59:59';

# Then check error log for: [ERROR] Got error 12701 when reading table './test/t1'
INSTALL PLUGIN spider SONAME 'ha_spider.so';
SET SQL_MODE='';
CREATE TABLE t (c INT AUTO_INCREMENT, KEY(c)) ENGINE=SPIDER PARTITION BY LIST COLUMNS (c) (PARTITION p DEFAULT ENGINE=SPIDER);
INSERT INTO t (c) VALUES (0);
INSERT INTO t (c) VALUES (0);
INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE m1 (c1 INT) ENGINE=SPIDER PARTITION BY LIST COLUMNS (c1) (PARTITION p1 DEFAULT ENGINE=SPIDER);
SHOW TABLE STATUS;
CREATE TEMPORARY TABLE m2 ENGINE=SPIDER PARTITION BY LIST COLUMNS (c1) (PARTITION p1 DEFAULT ENGINE=SPIDER);
SHOW TABLE STATUS;
SELECT SLEEP(10);
SHOW TABLE STATUS;
SET SESSION wsrep_on = OFF;
XA START 'xatest';
shutdown;
SELECT SLEEP(3);

SET sql_mode='';
CREATE TABLE t0 (a TIMESTAMP) ENGINE=CSV;
INSERT INTO t0 VALUES (0);
RENAME TABLE t0 TO t;
SET sql_mode='traditional';
UPDATE t SET a=0;

# Then check error log for [ERROR] mysqld: Table 't' is marked as crashed and should be repaired
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET sql_mode='';
INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t (i CHAR,n CHAR GENERATED ALWAYS AS (MD5 (i)) VIRTUAL) ENGINE=SPIDER;
INSERT INTO t VALUES (0,0);
CREATE TABLE t2 (c INT);
INSERT t SELECT 1 ON DUPLICATE KEY UPDATE c=1;

INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=SPIDER;
CREATE TABLE t0 (a INT) ENGINE=SPIDER;
INSERT INTO t0 VALUES (0);
SELECT MATCH (a) AGAINST (0x0) FROM t;
INSERT INTO t0 SELECT * FROM t0;
DROP DATABASE test;
CREATE DATABASE test;
USE test;
INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE SERVER d FOREIGN DATA WRAPPER mysql OPTIONS (HOST'',DATABASE'',USER'',PORT 10000,PASSWORD'');
SET SESSION spider_same_server_link=ON;
CREATE TABLE t (c INT AUTO_INCREMENT KEY,c2 INT,INDEX i (c2)) ENGINE=SPIDER ROW_FORMAT=COMPRESSED;
INSERT DELAYED INTO t VALUES (0,0),(0,0),(0,0);
SELECT SLEEP (3);
INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TEMPORARY TABLE t (c INT,c2 INT) ENGINE=SPIDER UNION=(t,t2) INSERT_METHOD=LAST;
INSERT INTO t VALUES (1,0),(1,0),(1,0);
EXPLAIN INSERT INTO t SELECT 1 QUERY;
CREATE TABLE t3 (c1 INTEGER NOT NULL PRIMARY KEY, c2 FLOAT(3,2));
SET GLOBAL wsrep_provider_options = 'repl.max_ws_size=512';
SET @@autocommit=0;
INSERT INTO t3 VALUES (1000,0.00),(1001,0.25),(1002,0.50),(1003,0.75),(1008,1.00),(1009,1.25),(1010,1.50),(1011,1.75);
CREATE TABLE t1 ( pk int primary key) ENGINE=INNODB;
# Sporadic. Loop till crash is seen.
SET GLOBAL innodb_defragment_stats_accuracy=1;
SET GLOBAL innodb_limit_optimistic_insert_debug=2;
CREATE TEMPORARY TABLE t (c INT) ENGINE=InnoDB;
INSERT INTO t VALUES (0);
INSERT INTO t VALUES (0);
INSERT INTO t VALUES (0);
ALTER TABLE t ENGINE=InnoDB;
ALTER TABLE t ENGINE=InnoDB;
ALTER TABLE t ENGINE=InnoDB;
ALTER TABLE t ENGINE=InnoDB;
DROP TABLE t;

# Highly sporadic. Loop till crash is seen. CLI reproducible in reducer
# mysqld options required:  --sql_mode=
CREATE TEMPORARY TABLE t1 (i INT) ENGINE=RocksDB;
CREATE UNIQUE INDEX i ON t1 (i);
ALTER TABLE t1 ADD COLUMN e ENUM ('a', 'b') FIRST;
DROP TABLE t1;
CREATE TEMPORARY TABLE temp_ignore (c1 INT) ENGINE=RocksDB;
CREATE TEMPORARY TABLE t1 (KEYc INT, c1 CHAR(100), c2 CHAR(100), PRIMARY KEY(KEYc)) ENGINE=RocksDB;
SET GLOBAL innodb_defragment_stats_accuracy=1;
CREATE TEMPORARY TABLE tmp (c1 CHAR(100));
DROP TABLE t1;
CREATE TEMPORARY TABLE t1 (c1 INT NOT NULL, c2 INT NOT NULL, c3 CHAR(255) NOT NULL, c4 TEXT (6000) NOT NULL, c5 BLOB (6000) NOT NULL, c6 VARCHAR(2000) NOT NULL, c7 VARCHAR(2000) NOT NULL, c8 DATETIME, c9 DECIMAL(6,3), PRIMARY KEY(c1), INDEX (c3,c4 (50),c5 (50)), INDEX (c2)) ENGINE=RocksDB;
INSERT INTO t1 VALUES (3792709,107,'bx9gGjR4CiwHK9V9lFmJ','wAMO93uhIrkQzodNeR8T7QxZMVzKcsQeECbyIkXAUZMDTQI0ZAgyjYD7VITQDK4W2LnSh3ZepFQiwNUh13piM6L0AcuaSfRpLEomxcjx9v1Mqfn5hL6RLT5OaNZDNs6I9wK24bvcmP21udCh5WA7I4RzPHFBOWe1OWjyTIvVOTr5HZx1gToLfcDKVQuFtUcTjCZvwMeHGJtbwd3ExPnXeRtA9nyBMLzsFnfDnp67Djrr4aH','FbPyKA2resmBzjRGP','H4boLxbibNiRR3Cc6aozLNXd8PwXAb9WBwS8D3hT8wqY7lPRDEVVfW5L4QD3JsgEq2CO4LGpXq3pXYttIn5XBKXdwYEWzsJcsokqyrFHvMuOQdGhp4meIrQ6','v','Hv',6);
INSERT INTO t1 VALUES (1941919362,-89,'o25lFD6yZcK','SxXR20TCKRZw8CytWCR90UBGgxCTFlSX3AO5','ZEOnEBYqDhkKwtYV0LvHIn0xMlJ7e4peXzLT1EFX3MB','OA','9','Z',3);
INSERT INTO t1 VALUES (1444293002,648016786,'HbY4xbRx9wLRvDGE4gr5pBKusm','Ku0bNy4Gaw4fjzfvEYKnZbyxsfsUX0ytFgdEVb2d0RJoM1qnI6aLhfmJEVf8qw4olJcT30IF8Yn053hwLaqpaGhPajxVwnDfb6SFtGEvnnkcrx6f4uNn8keoohRauRZC','1','1AxmkbgvnEbxlNTlXMh','j','H',3);
INSERT INTO t1 VALUES (-1448915294450022741,-187701819,'RSDp3D9UCeg65YN','KMV8x9SdMnQRlCEIo','aNLmbAmmnLelbKA0goXWais','GTcUltWVAFP','t','m',4);
INSERT INTO t1 VALUES (10437286018070182185,30439,'j0HIPFTkthYOm0KU3Qvxhpo4js6ZZPbTC6887KD','isQ1rH5omSjfzTbpGIjsSGgF3b1Rh1toIwfd5yOfH6xyfMoXknBanXvt3c1DEBciU9AoPRcgLcgZbuKqlQvHaM4EKkucH0XlrCJxiXyCiTZEJQY4TvdhgolYyu','qGJlDODgup0S','9W5PnxVs6GVejucJgrOEuGWhgWYsSzt','G','Lv',3);
INSERT INTO t1 VALUES (7118530,4126170,'yh','WODRNFoqXGb30szrmv2sdYIFQAOpZidHdvgT4nKmKSPim8d8XQyVdgIkU1rkjpmxWoLwdzxOmRGGIFPYHjjXUHkSUY4jNZeiVtsHUteuyvXkBQkurlB7C3tiXKdLT97ftxE5J2pypX26Y50z1DSLsqsHxIwgXwNfQdTKFaWIxMDmxG8hfGAkXwFXjWZG54CXnU5r','SivJexqd0Ao','ETMOtmlawEMLYI9VR4GpbUctDlLFVBHBvYQVBUwR041SFqvhqLawxoN9ERFzYDNA618KcWzjnz1Rta9fjEEE0dhTrs9XKSmxYrj0xgbuBTOJq231HqmcxOBxrQpLbploSHXcRfUIcyelak75gmQuaRA','ME','CJ',14);
INSERT INTO t1 VALUES (-108,37,'fV','Jz8VHylg','RRUdtmZQ1sElrfO7phsakzy2rBCDmCu3HjkbbOolR','PDAYF1zW7KqFFYaZZLsEKKC','j','A',5);
UPDATE t1 SET c4=REPEAT ("c4", 1024);
SET @dict_sql=0;
SET @=0;
# Crashes or gives '[ERROR] RocksDB: Failed to get column family flags from CF with id = 2. MyRocks data dictionary may be corrupted.'. Sporadic.
INSTALL SONAME 'ha_rocksdb';
SET GLOBAL rocksdb_update_cf_options='DEFAULT={write_buffer_size=8m};';
SELECT COUNT(*) FROM information_schema.rocksdb_global_info;
SELECT SLEEP(10);
USE mysql;
SELECT 0 INTO OUTFILE 'a';
DROP DATABASE mysql;   # ERROR 1010 (HY000): Error dropping database (can't rmdir './mysql', errno: 39 "Directory not empty") on all versions
CREATE TABLE mysql.user (c INT);   # ERROR 1005 (HY000): Can't create table `mysql`.`user` (errno: 168 "Unknown (generic) error from engine") on 10.2 and 10.3 only, 10.4+ succeeds
GRANT PROXY ON t1 TO b@c;
SET SESSION transaction isolation level SERIALIZABLE;
CREATE TABLE t2 (c1 INT NOT NULL PRIMARY KEY);
XA START 'test';
SELECT * FROM mysql.innodb_index_stats WHERE table_name='t2' AND index_name='SECOND';
INSERT INTO t2 VALUES (1);
INSERT INTO t2 VALUES (2);
UPDATE mysql.innodb_table_stats SET last_update="2020-01-01" WHERE database_name="mysql" AND table_name="t2";

SET SESSION SQL_MODE='';
CREATE TABLE t (c1 int) ;
SET max_session_mem_used=50000;
ALTER TABLE t ADD INDEX (c1);
LOCK TABLE t WRITE;
CREATE OR REPLACE SEQUENCE t;

SELECT ST_GEOMFROMWKB (0x01070000000100000002010000000000000000000000);
SELECT JSON_ARRAY_INSERT (0,NULL,1);
SELECT JSON_VALID ('{"开源数据库":"MariaDB"}');
CREATE TABLE t (a INT) ENGINE=Aria;
INSERT INTO t VALUES();
ALTER TABLE t ADD b GEOMETRY NOT NULL,ALGORITHM=copy;
ALTER TABLE t ADD INDEX i (b(1));

SET SQL_MODE='';
CREATE TABLE t (c INT,d BLOB (1) NOT NULL,INDEX (c,d(1))) ENGINE=Aria;
INSERT INTO t (c) VALUES (0);
CREATE TABLE t (a INT) ENGINE=InnoDB;
INSERT INTO t VALUES();
ALTER TABLE t ADD b GEOMETRY NOT NULL,ALGORITHM=copy;
USE test;
INSTALL PLUGIN tokudb SONAME 'ha_tokudb.so';
CREATE TEMPORARY TABLE t (c1 INT,c2 INT,c3 INT) ENGINE=InnoDB;
CREATE TABLE t (a INT) ENGINE=TokuDB;
DROP TABLE t;
XA START 'a';
INSERT INTO t VALUES (1);
SAVEPOINT sp1;
SAVEPOINT sp2;
ROLLBACK TO sp1;
USE test;
SELECT get_lock ('a',0);
SET GLOBAL wsrep_provider=DEFAULT;
XA START 'a';
XA END 'a';
XA ROLLBACK 'a';
SELECT 1;
SET pseudo_slave_mode=1;
XA START 'a';
XA END 'a';
XA PREPARE 'a';
SET SESSION TRANSACTION READ ONLY;
XA START 'a';
CREATE TABLE t1 (a INT);
XA START 'a';
INSERT INTO t1 VALUES(1);
SAVEPOINT abc;
XA END 'a';
XA PREPARE 'a';
XA COMMIT 'a';

CREATE TABLE t2 (c INT);
XA START 'a';
INSERT INTO t2 VALUES(1);
SET SESSION pseudo_slave_mode=1;
XA END 'a';
XA PREPARE 'a';
XA START 'a';
XA END 'a';
XA PREPARE 'a';
LOAD INDEX INTO cache t1 KEY(PRIMARY);
XA START 'a';
XA END 'a';
SET @arg0='a';
SET GLOBAL wsrep_provider=none;
XA PREPARE 'a';
SET GLOBAL wsrep_provider=DEFAULT;
XA START 'a';
XA END 'a';
XA PREPARE 'a';

XA START 'a';
SET GLOBAL wsrep_provider_options='repl.max_ws_size=0';
XA END 'a';
XA PREPARE 'a';
XA COMMIT 'a';
CREATE TABLE t0 (a INT,b INT)ENGINE=InnoDB;
SET sql_mode='';
SET SESSION wsrep_osu_method=NBO;
ALTER TABLE t0 ENGINE=none;
XA START 'a';
SET wsrep_on=OFF;
XA END 'a';
XA PREPARE 'a';
XA COMMIT 'a';
CREATE DATABASE one;
SET SESSION pseudo_slave_mode=ON;
CREATE TABLE t0 (c INT);
XA START 'a';
INSERT INTO t0 VALUES(0);
XA END 'a';
XA PREPARE 'a';
ALTER TABLE t0 ENGINE=InnoDB;
CREATE TABLE t1 (a INT);
CREATE TABLE t2 (a INT);
SET SESSION wsrep_osu_method=NBO;
OPTIMIZE TABLE t1, t2;
SET SESSION wsrep_osu_method=RSU;
CREATE TABLE t0 (a INT,b INT);
SET SESSION wsrep_osu_method=NBO;
INSERT INTO t0 VALUES();
ALTER TABLE t0 LOCK=EXCLUSIVE,RENAME TO t1;

SET SESSION wsrep_osu_method='RSU';
CREATE TABLE t1 (a MEDIUMINT UNSIGNED, b SMALLINT NOT NULL, KEY(b), PRIMARY KEY(a)) engine=innodb;
SET SESSION wsrep_osu_method=NBO;
DROP INDEX b ON t1;

SET SESSION wsrep_osu_method=RSU;
CREATE TABLE t0 (c0 INT);
SET SESSION wsrep_osu_method=NBO;
OPTIMIZE TABLE t0;
XA START 'b';
SET SESSION wsrep_trx_fragment_unit='statements';
DELETE FROM mysql.innodb_table_stats;
SET SESSION wsrep_trx_fragment_size=1;
CREATE TEMPORARY SEQUENCE s1;
XA START 'a';
XA END 'a';
XA PREPARE 'a';
SET GLOBAL wsrep_cluster_address='gcomm://';
SELECT SLEEP(3);
SET SESSION wsrep_osu_method=NBO;
DROP INDEX nonexisting_idx ON nonexisting_tbl;
XA START 'a';
XA END 'a';
XA PREPARE 'a';
XA ROLLBACK 'a';
SELECT SLEEP(3);
XA START 'a';
XA END 'a';
CACHE INDEX t1,t2 in default;
XA PREPARE 'a';

SET GLOBAL wsrep_mode=REPLICATE_ARIA;
XA START 'a';
DELETE FROM sys.sys_config WHERE variable = 'statement_performance_analyzer.view';
XA END 'a';
XA PREPARE 'a';

SET GLOBAL wsrep_mode=REPLICATE_ARIA;
XA START 'a';
DELETE FROM sys.sys_config WHERE variable = 'statement_performance_analyzer.view';
XA END 'a';
XA PREPARE 'a';
COMMIT;
SET @@global.wsrep_on=OFF;
XA START 'a';
SELECT GET_LOCK('test', 0) = 0 expect_1;
XA END 'a';
CACHE INDEX t1 PARTITION (ALL) KEY (`inx_b`,`PRIMARY`) IN default;
SELECT SLEEP(3);

SET SESSION wsrep_on=OFF;
XA START 'a';
XA END 'a';
SET GLOBAL KEYCACHE2.key_buffer_size=4*1024*1024;
CACHE INDEX t1 IN KEYCACHE2;
SELECT 1;
CREATE TABLE t1 (f1 VARCHAR(10)) ENGINE=InnoDB;
SET SESSION wsrep_trx_fragment_unit='statements';
SET SESSION wsrep_trx_fragment_size=1;
SET SESSION wsrep_on=OFF;
XA START 't';
SET GLOBAL wsrep_on=ON;
INSERT INTO t1 VALUES ('a');
SELECT * FROM t1 WHERE f1='a' ORDER BY c1;
SET @@session.pseudo_slave_mode=1;
SET SESSION TRANSACTION READ ONLY;
XA START 'a';
XA END 'a';
XA PREPARE 'a';
XA START 'a';
SET GLOBAL KEYCACHE1.key_buffer_size=128*1024;
XA END 'a';
CACHE INDEX t1 KEY(PRIMARY) IN KEYCACHE1;
SET GLOBAL wsrep_on=OFF;
XA COMMIT 'a';
ALTER SCHEMA test DEFAULT COLLATE ascii_general_ci;
XA START 'a';
SET GLOBAL wsrep_provider_options='repl.max_ws_size=0';
XA END 'a';
XA PREPARE 'a';
exit;
CREATE TABLE t1(a VARCHAR(1)) engine=InnoDB;
XA START 't3';
INSERT INTO t1  VALUES('a');
XA END 't3';
LOAD INDEX INTO CACHE t1 IGNORE LEAVES;
SET GLOBAL wsrep_on=OFF;

XA START 'tx1';
XA END 'tx1';
SET GLOBAL wsrep_provider_options='gmcast.isolate=1';
XA PREPARE 'tx1';
SET GLOBAL wsrep_on=OFF;
XA START 'y';
XA END 'y';
LOAD INDEX INTO CACHE t2 KEY (`PRIMARY`,`inx_b`);
SET GLOBAL wsrep_on=OFF;
SET SESSION wsrep_trx_fragment_size = 0;
XA START 'a';
SET GLOBAL wsrep_provider_options='repl.max_ws_size=512';
SET max_session_mem_used=50000;
XA END 'a';
XA PREPARE 'a';
CALL sys.statement_performance_analyzer ('overALL', NULL, 'with_full_table_scans');
CALL sys.statement_performance_analyzer ('overALL', NULL, 'with_full_table_scans');
XA START 'a';
SET GLOBAL wsrep_cluster_address = '';
XA END 'a';
XA PREPARE 'a';
SELECT SLEEP(3);
CREATE TABLE t1(c1 INT);
XA START 'a';
XA END 'a';
LOAD INDEX INTO CACHE t1 INDEX (`PRIMARY`) IGNORE LEAVES;
SET GLOBAL wsrep_on = OFF;
XA COMMIT 'a';
INSERT t1 VALUES (1);
# mysqld options required for replay: --log_bin=binlog --gtid_strict_mode=1
CREATE TABLE t1(id int) ENGINE=InnoDB;
XA START 'test';
INSERT INTO t1  VALUES(0);
SET SESSION wsrep_trx_fragment_size = 2;
SET GLOBAL wsrep_provider_options='repl.max_ws_size=4096';
SET SESSION wsrep_trx_fragment_unit = 'statements';
SET GLOBAL wsrep_on=OFF;
SET SESSION wsrep_trx_fragment_size = DEFAULT;
CREATE TABLE t3 (d INT) ENGINE=InnoDB;
SET tx_isolation='SERIALIZABLE';
SET SESSION default_storage_engine='MyISAM';
CREATE TABLE t2 (a INT);
XA START 't2';
INSERT INTO t3 VALUES (10),(30),(10),(20);
SET SESSION wsrep_trx_fragment_unit='statements';
CREATE TABLE t4 (c1 INT PRIMARY KEY) ENGINE=InnoDB;
SET SESSION wsrep_trx_fragment_size=3;
CREATE TABLE t4 (c1 INT PRIMARY KEY) ENGINE=InnoDB;
CREATE TABLE t4 (c1 INT PRIMARY KEY) ENGINE=InnoDB;
SELECT xid FROM mysql.wsrep_streaming_log;
CREATE TABLE t4(c1 INT PRIMARY KEY) engine=innodb;
CREATE TABLE ti (id BIGINT NOT NULL PRIMARY KEY) ENGINE=InnoDB;
SET GLOBAL wsrep_replicate_myisam=ON;
INSERT INTO t2 VALUES (439,126702);
INSERT INTO t2 VALUES (439,126702);
INSERT INTO t2 VALUES (439,126702);

DROP TABLE mysql.general_log;
CREATE TABLE mysql.general_log(a int);
SET GLOBAL general_log='ON';
SET GLOBAL log_output='TABLE';
SELECT 1;
INSERT INTO t0 VALUES(0);
# mysqld options required for replay:  --aria-encrypt-tables=1 --debug-assert-on-error
ALTER TABLE mysql.db ORDER BY db ASC;
# Leads to OOM, or ASAN requested allocation size...exceeds maximum supported (expected, filtered ftm)
SET GLOBAL key_buffer_size=18446744073709547520;
