INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=Spider;
SET max_session_mem_used=8192;
UNINSTALL SONAME 'ha_spider';
SHUTDOWN;

SET @@max_session_mem_used=500000;  # Set smaller if needed
SET @@session.query_alloc_block_size=655536;
UNINSTALL PLUGIN IF EXISTS example;
SHUTDOWN;

SET max_session_mem_used=8192;
SET @@session.query_alloc_block_size=655536;
UNINSTALL PLUGIN IF EXISTS example;
SHUTDOWN;