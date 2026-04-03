CREATE OR REPLACE GLOBAL TEMPORARY TABLE mysql.help_topic (help_topic_id INT UNSIGNED,name INT);
SET max_session_mem_used=0;
XA START 'a';
HELP'';
SHUTDOWN;
