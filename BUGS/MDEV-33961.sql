SET storage_engine=InnoDB,default_storage_engine='MEMORY';   # Warning: 1287 | '@@storage_engine' is deprecated and will be removed in a future release. Please use '@@default_storage_engine' instead 
CREATE TABLE t (c INT) ROW_FORMAT=FIXED;
