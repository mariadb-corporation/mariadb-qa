CHANGE MASTER TO MASTER_HOST='h', MASTER_USER='u';
SET @@GLOBAL.session_track_system_variables=NULL;
START SLAVE IO_THREAD;

SET @@GLOBAL.session_track_system_variables=NULL;
SET @@SESSION.session_track_system_variables=default;
SELECT 1;

SET @@global.session_track_system_variables=NULL;
INSERT DELAYED INTO t VALUES(0);

SET GLOBAL session_track_system_variables=NULL;
SET SESSION session_track_system_variables=DEFAULT;

USE test;
SET GLOBAL EVENT_SCHEDULER=ON;
CREATE EVENT e ON SCHEDULE EVERY 1 SECOND DO INSERT INTO execution_log VALUE('a');
SET GLOBAL session_track_system_variables=NULL;
SET GLOBAL session_track_system_variables=NULL;

# mysqld options required for replay: --log-bin --thread_handling=pool-of-threads --thread-pool-size=2047
CHANGE MASTER TO MASTER_DELAY=10, MASTER_HOST='a';
SET GLOBAL session_track_system_variables=NULL;
START SLAVE SQL_THREAD;
