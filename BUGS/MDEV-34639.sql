INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock', DATABASE 'test', USER 'Spider', PASSWORD '');
CREATE TABLE t1 (c1 INT,c2 INT) ENGINE=MyISAM;
CREATE TABLE t2 (c1 INT,c2 INT) ENGINE=Spider COMMENT='WRAPPER "mysql", SRV "srv", TABLE "t1"';
CREATE VIEW v AS SELECT * FROM t2;
UPDATE v SET c1=1;