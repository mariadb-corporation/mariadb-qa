# mysqld options required for replay: --log-bin --sql_mode= --max_allowed_packet=20000000
SET GLOBAL max_binlog_stmt_cache_size=0;
CREATE TEMPORARY TABLE t (c INT) ENGINE=InnoDB;
SELECT @@GLOBAL.innodb_flush_method=variable_value FROM information_schema.global_variables;
DELETE FROM mysql.proc;