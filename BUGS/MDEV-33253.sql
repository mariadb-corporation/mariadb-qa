SET GLOBAL slow_query_log=ON;
SET @@enforce_storage_engine=innodb;
SET @@sql_mode=no_auto_create_user;
ALTER TABLE mysql.slow_log ENGINE = MyISAM;
SET SESSION wsrep_trx_fragment_size=1;
SET long_query_time = 0.001;
SET @@session.slow_query_log= ON;
SET GLOBAL log_output = 'TABLE,FILE';
create table t (f INT);
