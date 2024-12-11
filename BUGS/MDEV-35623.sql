INSTALL SONAME 'ha_spider';
CREATE TABLE t1 (c DATE) ENGINE=InnoDB;
CREATE TABLE ts (c DATE) ENGINE=Spider COMMENT='DATABASE "test",table "t1"' CONNECTION='host "localhost",socket "../socket.sock",USER "Spider",PASSWORD ""';
SELECT DISTINCT DATE_FORMAT(c,'%Y-%m-%d %H:%i:%s') FROM ts;
