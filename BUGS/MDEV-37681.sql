CREATE GLOBAL TEMPORARY TABLE t (c INT) ON COMMIT PRESERVE ROWS;
LOCK TABLE t WRITE;
SELECT * FROM t;
ALTER TABLE t RENAME a.t;   # ERROR 1025 (HY000): Error on rename of './test/t' to './a/t' (errno: 168 "Unknown (generic) error from engine")
TRUNCATE t;
