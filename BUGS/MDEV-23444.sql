SET div_precision_increment= 0;
SELECT * FROM (SELECT AVG(@x := 0)) sq;

SET SESSION div_precision_increment=0;
SELECT * FROM (SELECT WEEKDAY (0)/0) AS a0;

SET SESSION div_precision_increment=-2;
SELECT * FROM (SELECT AVG(@x :=0)) sq;

# mysqld options required for replay: --log-bin 
SET SESSION binlog_format=STATEMENT;
CREATE TABLE t (c INT);
SET SESSION div_precision_increment=0;
SET @a=(MOD (-1,62)) / (695 * 312);
INSERT INTO t VALUES (@a:=0),(@a:=@a+1),(@a:=@a+1);
