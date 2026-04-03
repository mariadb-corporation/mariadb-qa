CREATE OR REPLACE GLOBAL TEMPORARY TABLE mysql.help_topic (help_topic_id INT UNSIGNED,name CHAR);
HELP '';

CREATE OR REPLACE GLOBAL TEMPORARY TABLE mysql.help_topic (help_topic_id INT);
HELP'';

CREATE OR REPLACE GLOBAL TEMPORARY TABLE mysql.help_topic (help_topic_id INT UNSIGNED,name INT);
SET max_session_mem_used=8192;
HELP'';

SET sql_mode='',enforce_storage_engine=Aria;
CREATE GLOBAL TEMPORARY TABLE t (x INT);
SET max_session_mem_used=8192;
REPAIR TABLE t;
SET autocommit=0;
CREATE OR REPLACE GLOBAL TEMPORARY TABLE mysql.help_topic (help_topic_id INT UNSIGNED,name INT);
LOCK TABLES t WRITE;
HELP'';
LOCK TABLES t1 AS a1 WRITE,t AS a5 WRITE;
HELP'';
SHUTDOWN;

# mysqld options required for replay: --log-bin 
SET max_session_mem_used=0;
SET sql_mode='',enforce_storage_engine=Aria;
CREATE OR REPLACE GLOBAL TEMPORARY TABLE mysql.help_topic (help_topic_id INT UNSIGNED,name INT);
START TRANSACTION;
HELP'';
SHUTDOWN;
