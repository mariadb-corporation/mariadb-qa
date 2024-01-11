INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t2(c INT) ENGINE=InnoDB;  # Same with MyISAM
CREATE TABLE t1(c INT) ENGINE=Spider COMMENT='socket "../socket.sock",table "t2 t3"';
ALTER TABLE t1 ENGINE=Spider;
TRUNCATE TABLE t1;
