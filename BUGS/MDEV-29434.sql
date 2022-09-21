SET GLOBAL general_log=ON;
DROP DATABASE mysql;
SET GLOBAL log_output='TABLE';
INSERT INTO dummy;

SET SESSION query_alloc_block_size=100;
SET GLOBAL general_log=1;
DROP TABLE mysql.general_log;
SET GLOBAL log_output='TABLE';
CREATE TABLE t1 (i INT) ENGINE MyISAM;
