SELECT table_catalog,table_schema,table_name,index_schema,index_name FROM information_schema.statistics;
SET max_session_mem_used=32768;
SELECT * FROM performance_schema.session_status;
SET GLOBAL innodb_io_capacity_max=100;
