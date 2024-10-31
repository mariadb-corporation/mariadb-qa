INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER mysql OPTIONS (SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
CREATE OR REPLACE TABLE mysql.general_log (a INT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
SET GLOBAL general_log=TRUE;
SET GLOBAL table_open_cache=0;
SET GLOBAL log_output='TABLE,FILE';
SHUTDOWN;
