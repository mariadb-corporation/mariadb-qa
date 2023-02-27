INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE USER spider@localhost IDENTIFIED BY 'PWD123';
GRANT ALL ON test.* TO spider@localhost;
CREATE server srv FOREIGN DATA wrapper mysql options (socket '/test/GAL_MD080822-mariadb-10.10.0-linux-x86_64-opt/node1/node1_socket.sock', DATABASE 'test', USER 'spider', PASSWORD 'PWD123');
CREATE TABLE t (c INT);
SET GLOBAL spider_same_server_link=ON;
CREATE TABLE t_s (c INT) ENGINE=Spider COMMENT='wrapper "mysql", srv "srv", TABLE "t"';
