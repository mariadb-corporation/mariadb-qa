INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=SPIDER PARTITION BY LIST COLUMNS (c) (PARTITION p DEFAULT ENGINE=SPIDER);
INSERT INTO t VALUES (1);
ALTER TABLE t CHECK PARTITION ALL;

INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=SPIDER PARTITION BY LIST COLUMNS (c) (PARTITION p DEFAULT ENGINE=SPIDER);
SELECT * FROM t;
ALTER TABLE t ENGINE=MEMORY;

CREATE TABLE t (c INT) PARTITION BY LIST COLUMNS (c) (PARTITION p DEFAULT ENGINE=SPIDER);
INSERT INTO t VALUES (0);
ALTER TABLE t ENGINE InnoDB;