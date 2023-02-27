XA START 't';
XA END 't';
XA PREPARE 't';
SET GLOBAL wsrep_provider_options='repl.max_ws_size=0';
LOAD INDEX INTO CACHE tbl0;
