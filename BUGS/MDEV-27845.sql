CHANGE MASTER TO master_host='127.0.0.1', master_user='DOES NOT EXIST',master_password='DOES NOT EXIST';
SET GLOBAL rpl_semi_sync_slave_enabled=1;
START SLAVE;
SHUTDOWN;
