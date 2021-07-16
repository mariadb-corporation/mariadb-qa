XA START 'tx1';
XA END 'tx1';
SET GLOBAL wsrep_provider_options='gmcast.isolate=1';
XA PREPARE 'tx1';
SET GLOBAL wsrep_on=OFF;
