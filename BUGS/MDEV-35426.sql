INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE 'test',user 'Spider',PASSWORD '');
CREATE TABLE t (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"';
ALTER TABLE t ENGINE=InnoDB;
SET NAMES utf8,@@collation_connection=utf16le_bin;
CREATE TABLE ï¼´ï¼” (ï¼£ï¼‘ CHAR(1)) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"';
XA START 'xaaaaaaaaaaaaaaa1','xaaaaaaaaaaaaaaa2',1234567890;
SET NAMES cp932;
SELECT ‚b‚P,SUBSTRING(‚b‚P,4) FROM ‚s‚S;

