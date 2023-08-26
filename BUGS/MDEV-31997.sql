INSTALL SONAME 'ha_rocksdb';
CHANGE MASTER 'm1' TO master_host='127.0.0.1',master_PORT=3307,master_user='';
ALTER TABLE mysql.gtid_slave_pos ENGINE=RocksDB;
CHANGE MASTER TO master_host='127.0.0.1',master_user='';
START ALL SLAVES;
