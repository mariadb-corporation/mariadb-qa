# mysqld options required for replay: --log_bin
SET sql_mode='';
CREATE TEMPORARY TABLE t ENGINE=MyISAM AS SELECT @a AS c;
INSERT INTO t VALUES (0xABB0);
SET autocommit=OFF;
CREATE TABLE t (c INT PRIMARY KEY) ENGINE=MyISAM SELECT * FROM t FOR UPDATE;
