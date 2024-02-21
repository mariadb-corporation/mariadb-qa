SET GLOBAL old_mode=4;
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
# Then check error log for SPIDER plugin initialization failed at 'create table if not exists mysql.spider_tables and Warning: Memory not freed: 10720

SET SESSION sql_mode=(SELECT CONCAT (@@sql_mode,',no_zero_date'));
SET GLOBAL sql_mode=(SELECT REPLACE (@@sql_mode,',strict_all_tables',''));
INSTALL SONAME 'ha_spider';
SHUTDOWN;
# 2024-02-19 16:52:33 4 [ERROR] Plugin 'SPIDER' registration as a STORAGE ENGINE failed.
# Warning: Memory not freed: 10720
