SET SESSION wsrep_on=OFF;
XA START 'a';
DO get_lock ('a',0);
XA END 'a';
XA ROLLBACK 'a';
