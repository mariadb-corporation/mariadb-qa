# mysqld options required for replay: --log-bin
SET max_tmp_session_space_usage=64*1024;
SET default_storage_engine=MyISAM;
SET autocommit=0;
CREATE TABLE t SELECT 2 AS a,CONCAT (REPEAT (1,@@max_allowed_packet/10),1) AS b;

# mysqld options required for replay: --log_bin
SET sql_mode='';
SET max_tmp_session_space_usage=64*1024;
SET LOCAL enforce_storage_engine=Aria;
SET autocommit=0;
CREATE TABLE t SELECT 2 AS a,CONCAT (REPEAT (1,@@max_allowed_packet/10),1) AS b;
