CREATE TABLE t1 (c INT) ENGINE=MyISAM;  # Or MEMORY,Aria
CREATE TABLE t2 (c INT);  # Engine choice does not matter
INSERT t2 SELECT SEQ FROM seq_1_to_200000;
XA START 'x';
DELETE FROM t2;
INSERT INTO t1 VALUES(1);
XA END 'x';
XA ROLLBACK 'x';
SHOW WARNINGS;  # Warning: 1196: Some non-transactional changed tables couldn't be rolled back
