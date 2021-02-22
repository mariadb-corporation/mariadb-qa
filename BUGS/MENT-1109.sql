USE test;
SELECT get_lock ('a',0);
SET GLOBAL wsrep_provider=DEFAULT;
XA START 'a';
XA END 'a';
XA ROLLBACK 'a';
SELECT 1;