SET use_stat_tables=PREFERABLY, histogram_type=1;
CREATE TABLE t (c ENUM ('') CHARACTER SET utf32 COLLATE utf32_spanish2_ci);
INSERT INTO t VALUES (1);
ANALYZE TABLE t;
