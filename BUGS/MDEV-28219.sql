INSTALL PLUGIN spider SONAME 'ha_spider.so';
SELECT SLEEP (5);  # Avoid MDEV-28218
DROP TABLE IF EXISTS mysql.spider_tables;
CREATE TEMPORARY TABLE t (c INT) ENGINE=Spider;
DROP TABLE t;

# Results in: [Warning] Could not remove temporary table: '/test/MD160322-mariadb-10.9.0-linux-x86_64-dbg/data/#sql-temptable-3544ff-4-0', error: 2 (in error log)
