INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER s FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
CREATE TABLE t (c BLOB) ENGINE=InnoDB;
CREATE TABLE ts (c BLOB) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "s",TABLE "t"';
SELECT TRIM(BOTH ' ' FROM c) FROM ts ORDER BY c;

INSTALL SONAME 'ha_spider';
CREATE TABLE ta_l(a int,b char,c DATE,KEY (a,b,c)) ENGINE=Spider DEFAULT CHARSET=utf8 COMMENT='DATABASE "test",table "ta_r_3"' CONNECTION='host "localhost",socket "../socket.sock",USER "Spider",PASSWORD ""';
CREATE TABLE ta_r_3(a INT DEFAULT 1,b CHAR DEFAULT'',c DATE DEFAULT '1-1-1 1:1:1')ENGINE=InnoDB DEFAULT CHARSET=utf8;
SELECT DISTINCT a,b,date_format(c,'%Y-%m-%d %H:%i:%s')FROM ta_l;
