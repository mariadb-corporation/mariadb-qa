SET SESSION wsrep_on = OFF;
XA START 'xatest';
shutdown;
SELECT SLEEP(3);

