# Crashes or gives '[ERROR] RocksDB: Failed to get column family flags from CF with id = 2. MyRocks data dictionary may be corrupted.'. Sporadic.
INSTALL SONAME 'ha_rocksdb';
SET GLOBAL rocksdb_update_cf_options='DEFAULT={write_buffer_size=8m};';
SELECT COUNT(*) FROM information_schema.rocksdb_global_info;
SELECT SLEEP(10);
