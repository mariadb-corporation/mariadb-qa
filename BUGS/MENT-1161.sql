XA START 'a';
XA END 'a';
XA PREPARE 'a';
SET @@global.debug_dbug="+d,ha_index_init_fail";
XA ROLLBACK 'a';
SELECT SLEEP(3);