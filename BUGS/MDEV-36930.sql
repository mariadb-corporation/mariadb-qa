SET GLOBAL init_slave=this_will_give_syntax_error;
CHANGE MASTER TO master_host='h',master_user='u';
START SLAVE SQL_THREAD;
