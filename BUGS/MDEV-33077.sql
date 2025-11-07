INSTALL SONAME 'ha_connect';
CREATE TABLE t (f char(16)) ENGINE=Connect TABLE_TYPE=DOS CHARACTER SET utf16;
INSERT INTO t VALUES ('foo'),('bar');
SELECT * FROM t WHERE f IN ('baz','qux');

INSTALL SONAME 'ha_connect';
SET character_set_connection=ucs2;
CREATE TABLE t (c INT) ENGINE=Connect;
SELECT * FROM t WHERE c IN ('','1 1:1:1');
