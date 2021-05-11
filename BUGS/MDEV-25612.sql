SET SESSION default_master_connection=REPEAT ('a',191);
SET lc_messages=ru_ru;
CHANGE MASTER TO master_host='dummy';
START SLAVE sql_thread;
CHANGE MASTER TO master_user='rpl',master_password='rpl';
