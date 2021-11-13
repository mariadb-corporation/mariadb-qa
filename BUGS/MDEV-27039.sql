# mysqld options required for replay: --log-bin --performance-schema
INSTALL PLUGIN spider SONAME 'ha_spider.so';
SET GLOBAL expire_logs_days=11;
SET GLOBAL binlog_checksum=NONE;
