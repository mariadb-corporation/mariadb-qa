# mysqld options required for replay: --max-session-mem-used=8192

CREATE TABLE t (a INT) ENGINE=MyISAM;
SET GLOBAL max_session_mem_used=8192;
INSERT DELAYED INTO t VALUES (0);

SET GLOBAL max_session_mem_used=8192;
SET GLOBAL event_scheduler=ON;

SET GLOBAL max_session_mem_used=8192;
CHANGE MASTER TO MASTER_HOST='127.0.0.1', MASTER_PORT=1, MASTER_USER='r';
START SLAVE;
