XA START 'a';
SET GLOBAL wsrep_cluster_address = '';
XA END 'a';
XA PREPARE 'a';
SELECT SLEEP(3);
