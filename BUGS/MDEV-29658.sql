INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY 'PWD1';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE 'test',user 'Spider',PASSWORD 'PWD1');
CREATE TABLE t (c INT);
CREATE TABLE ts (c INT KEY,c2 INT) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"' PARTITION BY RANGE (c) (PARTITION p VALUES LESS THAN (1),PARTITION p2 VALUES LESS THAN (300),PARTITION p3 VALUES LESS THAN (400));
CREATE TRIGGER t_bi BEFORE INSERT ON ts FOR EACH ROW SET @a=1;
UPDATE ts SET c2=1;