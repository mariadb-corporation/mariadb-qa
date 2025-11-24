INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SET spider_same_server_link=on;
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (DATABASE "test", USER "root", SOCKET "../socket.sock");
CREATE TABLE t (c INT) ENGINE=InnoDB;
CREATE GLOBAL TEMPORARY TABLE gtt (id INT) ENGINE=Spider ON COMMIT PRESERVE ROWS COMMENT='WRAPPER "mysql", SRV "srv", TABLE "t"';
INSERT INTO gtt VALUES (1);
# CLI: ERROR 1478 (HY000): Table storage engine 'SPIDER' does not support the create option 'TEMPORARY'
