CREATE TABLE t (c TIMESTAMP);
PREPARE s FROM 'DELETE FROM t WHERE c=?';
EXECUTE s USING 1;
INSERT INTO t (c) VALUES (now());
EXECUTE s USING NULL;

PREPARE s FROM 'SELECT CONCAT(UNIX_TIMESTAMP(?))';
EXECUTE s USING 1;
SET character_set_database=ucs2;
SET CHARACTER SET cp1251_koi8;
EXECUTE s USING DEFAULT;
