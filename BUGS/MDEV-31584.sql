SET SESSION sql_log_off=1;
CREATE OR REPLACE TABLE mysql.general_log (a INT);
SET GLOBAL general_log=ON,log_output='TABLE';
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SELECT SLEEP(1);  # Shows server is gone
