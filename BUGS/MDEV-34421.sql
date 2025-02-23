SET sql_mode='';
INSTALL SONAME 'ha_spider';
CREATE TABLE t (c INT) ENGINE=Spider PARTITION BY KEY(c) (PARTITION p);
UNINSTALL SONAME IF EXISTS 'ha_spider';
INSERT INTO t SELECT 1;

SET sql_mode='';
INSTALL SONAME 'ha_spider';
CREATE SERVER s FOREIGN DATA WRAPPER MYSQL OPTIONS (HOST 'LOCALHOST', DATABASE 'test', USER 'Spider', PASSWORD '', SOCKET '../socket.sock');
CREATE TABLE t (pKEY INT NOT NULL, PRIMARY KEY(pKEY)) ENGINE=Spider COMMENT='TABLE "t"' PARTITION BY KEY(pKEY) (PARTITION pt1 COMMENT='SRV "s"', PARTITION pt2 COMMENT='SRV "s"', PARTITION pt3 COMMENT='SRV "s"');
UNINSTALL SONAME IF EXISTS "ha_spider";
SELECT * FROM t ORDER BY id;

SET sql_mode='';
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (a INT,KEY(a)) ENGINE=Spider;
UNINSTALL SONAME IF EXISTS 'ha_spider';
ALTER TABLE t ENGINE=Spider PARTITION BY KEY(a) (PARTITION p0 ENGINE=Spider);
