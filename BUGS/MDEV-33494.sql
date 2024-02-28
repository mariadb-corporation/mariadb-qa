SET SESSION sql_mode=(SELECT CONCAT (@@sql_mode,',no_zero_date'));
SET GLOBAL sql_mode=(SELECT REPLACE (@@sql_mode,',strict_all_tables',''));
INSTALL SONAME 'ha_spider';
SHUTDOWN;

SET GLOBAL sql_mode=(SELECT CONCAT (@@sql_mode,',no_zero_date'));
INSTALL SONAME 'ha_spider';

SET sql_mode=traditional;
SET GLOBAL sql_mode=(SELECT REPLACE (@@sql_mode,',strict_trans_ts',''));
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SHUTDOWN;

SET @@sql_mode='TRADITIONAL';
SET GLOBAL sql_mode=(SELECT REPLACE (@@sql_mode,',pipes_as_concat',''));
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SHUTDOWN;
