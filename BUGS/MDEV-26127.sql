SET GLOBAL innodb_file_per_table=OFF;
CREATE TABLE t (c INT) ENGINE=InnoDB PARTITION BY LINEAR KEY(c) PARTITIONS 4;
LOCK TABLES t WRITE,t AS a READ;
ALTER TABLE t REBUILD PARTITION p0;