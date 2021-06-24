XA START 'a';
SET GLOBAL wsrep_provider_options='repl.max_ws_size=0';
XA END 'a';
XA PREPARE 'a';
exit;
