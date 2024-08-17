SET max_heap_table_size=1125899906842624;
SET use_stat_tables=preferably;
CREATE TABLE t (b INT);
ANALYZE TABLE t;
