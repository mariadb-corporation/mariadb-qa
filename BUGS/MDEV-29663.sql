INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY 'PWD1';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE 'test',user 'Spider',PASSWORD 'PWD1');
CREATE TABLE t (c INT) ENGINE=InnoDB;
CREATE TABLE ts (c1 INT) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"';
SELECT c1 FROM ts;

# Then check CLI output for: ERROR 1054 (42S22): Unknown column 't0.c1' in 'field list'
