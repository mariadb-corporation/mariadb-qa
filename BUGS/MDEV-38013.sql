INSTALL SONAME 'ha_connect';
CREATE TABLE t (c INT KEY) ENGINE=Connect PARTITION BY LIST (c) (PARTITION p VALUES IN (1,10));
LOCK TABLE t WRITE;
INSERT INTO t VALUES(0);  # Or 1,1 (two different errors; 0: 'ERROR 1526 (HY000): Table has no partition for value 0' or 1,1: 'ERROR 1136 (21S01): Column count doesn't match value count at row 1') - both result in the UBSAN error on the ALTER
ALTER TABLE t CHANGE c c BIT;  # UBSAN error
