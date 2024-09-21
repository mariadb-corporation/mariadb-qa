INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t1 (a VARCHAR(32) CHARACTER SET utf8 COLLATE utf8_bin,b VARCHAR(32) CHARACTER SET utf8 COLLATE utf8_bin) ENGINE=Spider DEFAULT CHARSET=utf8;
DELETE FROM t1 WHERE a < 500;
SET max_statement_time=0.000001;
SELECT 1 LIST;
HANDLER t1 OPEN;
HANDLER t1 READ NEXT;

# CLI: ERROR 1317 (70100): Query execution was interrupted
# ERR: [ERROR] mysql_ha_read: Got error 1317 when reading table 't1'
