ET SESSION sql_mode='ORACLE';
CREATE TABLE t (a CHAR,b GEOMETRY) ENGINE InnoDB;
INSERT INTO t (a) VALUES (uuid_short());
UPDATE t SET a=a+12,b=3 LIMIT 3;
CREATE FULLTEXT INDEX i ON t (s2);
