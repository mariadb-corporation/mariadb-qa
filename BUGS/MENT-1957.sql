SET pseudo_slave_mode=1;
XA START 'a';
XA END 'a';
XA PREPARE 'a';
XA ROLLBACK 'a';

XA START 'a';
SET pseudo_slave_mode=1;
XA END 'a';
XA PREPARE 'a';
XA COMMIT 'a';
