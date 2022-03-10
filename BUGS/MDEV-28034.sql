# Important note: This bug can only be reproduced by a C-based client, like pquery. CLI replay will not reproduce the bug
CREATE TABLE t (c INT,c2 CHAR AS (CONCAT ('',DAYNAME ('')))) COLLATE utf8_bin ENGINE=InnoDB;
SELECT * FROM t WHERE c2='2010-10-01 00:00:00' LIMIT 2;
INSERT INTO t SET c=CONCAT (REPEAT ('',0),'','');
