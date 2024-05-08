# mysqld options required for replay:  --innodb-page-size=4k
SET GLOBAL innodb_autoextend_increment=FALSE;
SET @inserted_value=REPEAT (1,16777216);
CREATE TEMPORARY TABLE t (c LONGTEXT);
INSERT INTO t VALUES (@inserted_value);
