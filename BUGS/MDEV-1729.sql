XA START 'a';
XA END 'a';
SET @@session.pseudo_slave_mode=1;
CREATE DATABASE dummy;
XA PREPARE 'a';
SET GLOBAL wsrep_provider_options = 'gmcast.isolate=1';
XA ROLLBACK 'a';
SET GLOBAL wsrep_provider_options='gmcast.isolate=0';
XA COMMIT 'a';

