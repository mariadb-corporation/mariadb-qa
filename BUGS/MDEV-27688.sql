# mysqld options required for replay:  --maximum-sort_buffer_size=1M
SET SESSION sql_mode='traditional';
CREATE TABLE t (c CHAR(1024) PARTITION BY RANGE COLUMNs(a)(PARTITION p0 VALUES LESS THAN(),PARTITION p1 VALUES LESS THAN(),PARTITION p2 VALUES LESS THAN());
SET STATEMENT sort_buffer_size=150000 FOR SELECT 1;
