XA START 'a';
SET debug_dbug='+d,ib_create_table_fail_too_many_trx';
XA END 'a';
XA PREPARE 'a';
