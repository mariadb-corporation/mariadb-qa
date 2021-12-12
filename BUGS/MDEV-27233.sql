# mysqld options required for replay:  --init-file=${PWD}/in.sql
 
# $ cat in.sql
INSTALL PLUGIN spider SONAME 'ha_spider.so';
USE test;
CREATE TABLE t (c INT) ENGINE=SPIDER;

# Will cause a hang for server + CLI on server startup, and/or CLI connection attempts
