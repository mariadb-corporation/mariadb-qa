INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE USER spider@localhost IDENTIFIED BY 'PWD123';
GRANT ALL ON test.* TO spider@localhost;
CREATE server srv FOREIGN DATA wrapper mysql options (socket '../socket.sock', DATABASE 'test', USER 'spider', PASSWORD 'PWD123');
CREATE TABLE t (c INT);
SET GLOBAL spider_same_server_link=ON;
CREATE TABLE t_s (c INT) ENGINE=Spider COMMENT='wrapper "mysql", srv "srv", TABLE "t"';
SHOW CREATE TABLE t_s;
INSERT INTO t_s VALUES (1),(2);
DELETE FROM t_s WHERE c=2;
SELECT * FROM t_s;  # 1
