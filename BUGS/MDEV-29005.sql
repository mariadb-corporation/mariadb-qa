SET sql_mode='';
CREATE TABLE t0 (a INT,b CHAR(0));
INSERT INTO t0 VALUES (NULL,0),(NULL,0),(NULL,0),(NULL,0),(NULL,0),(NULL,0);
SET @@optimizer_switch='in_to_exists=off,materialization=on,partial_match_ROWID_merge=on,partial_match_table_scan=off';
SET SESSION max_heap_table_size=0;
SELECT ROW(0,0) IN (SELECT t0.a,0 FROM t0) FROM t0;
