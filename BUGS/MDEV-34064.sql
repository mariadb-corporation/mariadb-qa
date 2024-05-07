# mysqld options required for replay: --log-bin 
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c TEXT) ENGINE=Spider;
XA BEGIN 'a';
UPDATE t SET c=+1;
CHANGE MASTER TO master_host='a',master_port=1,master_user='a',master_demote_to_slave=1;
