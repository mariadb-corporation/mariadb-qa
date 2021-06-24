SET GLOBAL wsrep_provider=DEFAULT;
XA START 'a';
XA END 'a';
XA PREPARE 'a';

XA START 'a';
SET GLOBAL wsrep_provider_options='repl.max_ws_size=0';
XA END 'a';
XA PREPARE 'a';
XA COMMIT 'a';
