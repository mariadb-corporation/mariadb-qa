SET sql_mode='';
CREATE TABLE t (c1 INT,c2 CHAR AS (CONCAT ('',DAYNAME ('')))) COLLATE utf8_bin ENGINE=InnoDB;
INSERT INTO t VALUES (0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0);
SET collation_connection='utf32_bin';
INSERT INTO t VALUES (0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0);
SELECT * FROM t;
