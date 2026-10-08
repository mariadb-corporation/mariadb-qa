# mysqld options required for replay:  --max_allowed_packet=1073741824
CREATE TABLE t1 (a LONGBLOB, b LONGBLOB) ENGINE=MyISAM;
INSERT INTO t1 VALUES (REPEAT('a',1073741824), REPEAT('b',1073741824));
SELECT LENGTH(a), LENGTH(b) FROM t1;
#CLI: ERROR 1194 (HY000): Table 't1' is marked as crashed and should be repaired
#ERR: [ERROR] Got error 127 when reading table './test/t1'
#ERR: [ERROR] mariadbd: Table 't1' is marked as crashed and should be repaired
