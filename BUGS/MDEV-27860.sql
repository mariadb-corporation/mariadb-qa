INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t ENGINE=SPIDER COMMENT="TABLE 't2'" PARTITION BY LIST COLUMNS (c) (PARTITION p DEFAULT COMMENT="srv 'a'" ENGINE=SPIDER);