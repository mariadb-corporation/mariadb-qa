# mysqld options required for replay: --slave_parallel_threads=10
# All testcases require m/s replication
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

SET @@session.pseudo_slave_mode=TRUE;
XA START 'a';
XA END 'a';
XA PREPARE 'a';
XA COMMIT 'a';
