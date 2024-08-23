SET innodb_compression_default=1;
CREATE TEMPORARY TABLE t (c INT);
SET GLOBAL innodb_compression_level=0;
TRUNCATE t;
DROP TABLE t;
