SET @@global.slow_query_log = TRUE;
SET GLOBAL log_output = 'TABLE';
SET log_queries_not_using_indexes= TRUE;
SET @@local.slow_query_log = ON;
SET SESSION wsrep_trx_fragment_size = 64;
SELECT name, mtype, prtype, len FROM INFORMATION_SCHEMA.INNODB_SYS_COLUMNS WHERE name = 'p';
SELECT 1;
