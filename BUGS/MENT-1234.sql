SET @@session.pseudo_slave_mode=1;
SET SESSION TRANSACTION READ ONLY;
XA START 'a';
XA END 'a';
XA PREPARE 'a';
