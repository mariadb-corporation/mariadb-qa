CREATE TABLE t1 (a VARCHAR(1),FULLTEXT (a)) engine=ARIA;
INSERT INTO t1 SELECT table_rows FROM information_schema.tables;
HANDLER t1 OPEN AS t1;
INSERT INTO t1 VALUES (1);
