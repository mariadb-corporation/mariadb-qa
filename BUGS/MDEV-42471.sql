# mysqld options required for replay:  --max_allowed_packet=1073741824
CREATE TABLE t1 (a LONGBLOB, b LONGBLOB) ENGINE=Aria ROW_FORMAT=DYNAMIC;
INSERT INTO t1 VALUES (REPEAT('a',1073741824), REPEAT('b',1073741824));
SELECT LENGTH(a), LENGTH(b) FROM t1;
#CLI: ERROR 127 (HY000): Got error '127 "Table file is corrupted"' for './test/t1.MAI'
#ERR: [ERROR] mariadbd: Got error '127 "Table file is corrupted"' for './test/t1.MAI'
#ERR: [ERROR] Got error 127 when reading table './test/t1'
#ERR: [ERROR] mariadbd: Table 't1' is marked as crashed and should be repaired

# mysqld options required for replay:  --max_allowed_packet=1073741824
CREATE TABLE t1 (a LONGBLOB, b LONGBLOB) ENGINE=Aria;
INSERT INTO t1 VALUES (REPEAT('a',1073741824), REPEAT('b',1073741824)), ('c','d');
SELECT LENGTH(a), LENGTH(b) FROM (SELECT DISTINCT a, b FROM t1) dt;
#CLI: ERROR 127 (HY000): Got error '127 "Table file is corrupted"' for '#sql-temptable-2738f4-5-1.MAI'
#ERR: [ERROR] mariadbd: Got error '127 "Table file is corrupted"' for '#sql-temptable-2738f4-5-1.MAI'
#ERR: [ERROR] mariadbd: Table '(temporary)' is marked as crashed and should be repaired
