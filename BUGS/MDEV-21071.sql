CREATE OR REPLACE TABLE t1 ENGINE=INNODB SELECT NULL UNION SELECT NULL;

CREATE TABLE t ENGINE=InnoDB AS SELECT NULL AS a FROM (SELECT 1) AS b UNION ALL SELECT NULL AS c FROM (SELECT 1) AS d;

# Then observe in client ERROR 1005 (HY000): Can't create table `test`.`t` (errno: 168 "Unknown (generic) error from engine")
