SET GLOBAL log_output='FILE';
CHANGE MASTER 'aaaa' TO master_host='aaaa',master_use_gtid=slave_pos;
SET GLOBAL log_slow_verbosity='full';
SET GLOBAL init_slave='aaaa';
SET GLOBAL long_query_time=0;
SET GLOBAL slow_query_log=1;
START SLAVE 'aaaa';
SET GLOBAL log_output='FILE';
