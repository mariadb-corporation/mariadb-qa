INSTALL PLUGIN spider SONAME 'ha_spider.so';
SET spider_internal_sql_log_off=1;
DROP TABLE mysql.spider_link_mon_servers;
CREATE TABLE t1(c DATE) ENGINE=MyISAM;
CREATE TABLE t(c DATE,PRIMARY KEY(c)) ENGINE=Spider COMMENT='socket "../socket.sock",table "t1 t2"' CONNECTION='mkd "1"';
SELECT * FROM t WHERE c=0;
