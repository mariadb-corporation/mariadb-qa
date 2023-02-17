SET storage_engine=MyISAM, sql_mode='';
CREATE TABLE t (c1 INT KEY,c2 INT,c3 TIME,INDEX (c2));
INSERT INTO t VALUES (0,0,0),(1000,0,0);
EXECUTE x;
SET @@max_statement_time=0.0001;
SELECT * FROM t WHERE c1 >='00:00:00' AND c1 <'23:00:00' AND c2='13:13:13';
DROP TABLE t;
