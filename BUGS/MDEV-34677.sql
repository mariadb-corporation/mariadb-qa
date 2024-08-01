# mysqld options required for replay:  --innodb-buffer-pool-chunk-size=1M
SET GLOBAL innodb_buffer_pool_size=@@innodb_buffer_pool_size+1;
