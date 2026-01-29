# mysqld options required for replay: --log_bin
CREATE TABLE t (t TEXT,FULLTEXT (t));
XA BEGIN 'a';
CREATE TEMPORARY TABLE t (c TEXT);
SET GLOBAL server_id=512;
DELETE FROM t LIMIT 2;
INSERT INTO t VALUES (REPEAT('बांग्लादे',1200));
DELETE FROM t;
XA END 'a';
SET max_tmp_session_space_usage=64*1024;
XA PREPARE 'a';
