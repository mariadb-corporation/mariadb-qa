# Test all testcases both without and with these mysqld options
# mysqld options required for replay: --log-bin --sql_mode= --binlog_format=ROW

SET sql_mode='',max_error_count=1024;
CREATE TABLE t (a SET('a','b') NOT NULL) ENGINE=CSV;
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t SELECT A.a FROM t A,t B,t C;
UPDATE t SET a=NULL;
UPDATE t SET a=NULL;  # Repeat as needed #

SET sql_mode='',max_error_count=1024;
CREATE TABLE t (a SET('a','b') NOT NULL) ENGINE=CSV;
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t VALUES (1);
INSERT INTO t VALUES (1);
INSERT INTO t VALUES (1);
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t VALUES (1),(2),(3),(4);
INSERT INTO t SELECT A.a + 10* (B.a + 10*C.a) FROM t A,t B,t C;
INSERT INTO t2 VALUES (0);
SELECT * FROM t3;
UPDATE t SET a=NULL WHERE a=2;
UPDATE t SET a=NULL WHERE a=2;  # Repeat as needed #
SET sql_mode='';

CREATE TABLE t (a SET('foo','bar') NOT NULL) ENGINE=CSV;
SET max_error_count=1024;
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(),('-1e2'),(1),(CONVERT (_ucs2 0x062A1A0632 USING utf8)),(1),(-1),(65),(66);
INSERT INTO t SELECT A.a + 10* (B.a + 10*C.a) FROM t A,t B,t C;
INSERT INTO at (c,_dat) SELECT CONCAT ('_dat: ',c),JSON_EXTRACT(j,'$') FROM t WHERE c='opaque_mysql_typevb';
SELECT * FROM t3;
UPDATE t SET a=NULL WHERE a=2;
UPDATE t SET a=NULL WHERE a=2;  # Repeat as needed #

CREATE TABLE t (a SET('foo','bar') NOT NULL) ENGINE=CSV;
SET max_error_count=1024;
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t VALUES();
INSERT INTO t VALUES ('-1e2');
INSERT INTO t VALUES (1);
INSERT INTO t VALUES (CONVERT (_ucs2 0x062A1A0632 USING utf8));
INSERT INTO t VALUES (1),(-1),(65),(66);
INSERT INTO t SELECT A.a + 10* (B.a + 10*C.a) FROM t A,t B,t C;
INSERT INTO at (c,_dat) SELECT CONCAT ('_dat: ',c),JSON_EXTRACT(j,'$') FROM t WHERE c='opaque_mysql_typevb';
SELECT * FROM t3;
UPDATE t SET a=NULL WHERE a=2;
UPDATE t SET a=NULL WHERE a=2;  # Repeat as needed #

CREATE TABLE t (a SET('foo','bar') NOT NULL) ENGINE=CSV;
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t VALUES();
INSERT INTO t VALUES ('-1e2');
INSERT INTO t VALUES (1);
INSERT INTO t VALUES (CONVERT (_ucs2 0x1A1A1 USING utf8));
INSERT INTO t VALUES (1),(-1),(65),(66);
INSERT INTO t SELECT A.a + 10* (B.a + 10*C.a) FROM t A,t B,t C;
UPDATE t SET a=NULL WHERE a=2;
UPDATE t SET a=NULL WHERE a=2;  # Repeat as needed #

SET sql_mode='',max_error_count=1024;
CREATE TABLE t (a SET('a','b') NOT NULL) ENGINE=CSV;
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
INSERT INTO t SELECT A.a FROM t A,t B,t C;
UPDATE t SET a=NULL;
INSERT INTO t SELECT A.a FROM t A,t B,t C;
UPDATE t SET a=NULL;
INSERT INTO t SELECT A.a FROM t A,t B,t C;
UPDATE t SET a=NULL;
INSERT INTO t SELECT A.a FROM t A,t B,t C;
UPDATE t SET a=NULL;
INSERT INTO t SELECT A.a FROM t A,t B,t C;
UPDATE t SET a=NULL;
