SET SQL_MODE='';
SET SESSION log_slow_verbosity=5;
set slow_query_log=on;
SET @@long_query_time=0;
SET @@GLOBAL.slow_query_log=ON;
set global log_output=FILE;
SET @@MAX_STATEMENT_TIME=0.0001;
values((values (1)union values (1) union values (1)));
values((values (1)union values (1) union values (1)));
