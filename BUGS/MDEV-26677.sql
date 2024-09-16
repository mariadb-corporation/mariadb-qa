# Crashes or gives '[ERROR] RocksDB: Failed to get column family flags from CF with id = 2. MyRocks data dictionary may be corrupted.'. Sporadic.
INSTALL SONAME 'ha_rocksdb';
SET GLOBAL rocksdb_update_cf_options='DEFAULT={write_buffer_size=8m};';
SELECT COUNT(*) FROM information_schema.rocksdb_global_info;
SELECT SLEEP(10);

# mysqld options required for replay: --sql_mode= 
INSTALL SONAME 'ha_rocksdb';
SET GLOBAL rocksdb_update_cf_options='cf1={write_buffer_size=8m;target_file_size_base=2m};cf2={write_buffer_size=16m;max_bytes_for_level_multiplier=8};cf3={target_file_size_base=4m};';
SELECT COUNT(*) FROM information_schema.rocksdb_global_info;
SELECT SLEEP(10);

# Crashes, less or not sporadic
INSTALL SONAME 'ha_rocksdb';
SET GLOBAL rocksdb_update_cf_options='cf0={prefix_extractor=capped:0};';
SELECT * FROM information_schema.rocksdb_global_info;
ERR: [ERROR] RocksDB: Failed to get column family flags from CF with id = 2. MyRocks data dictionary may be corrupted.
CLI
