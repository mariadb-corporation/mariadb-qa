CREATE TABLE t1 ( c1 varchar(10) NOT NULL, c2 varchar(10) DEFAULT NULL, c3 decimal(12,4) DEFAULT NULL, PRIMARY KEY (c1) ) ENGINE=InnoDB ;
INSERT INTO t1(c1) VALUES ('');
SET binlog_row_image=FULL_NODUP;
UPDATE t1 SET c2='';
