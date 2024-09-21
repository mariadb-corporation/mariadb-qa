INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SET SESSION SPIDER_IGNORE_COMMENTS=1;
ALTER TABLE mysql.gtid_slave_pos ENGINE=Spider;
CHANGE MASTER TO master_host='1',master_user='',master_password='',master_port=1;
START SLAVE SQL_THREAD;
# ERR: [ERROR] Slave SQL: Error processing replication GTID position tables: The connect info 'Replication slave GTID position' is invalid, Internal MariaDB error code: 12501
