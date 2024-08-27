# mysqld options required for replay: --log-bin
XA START 'a';
CHANGE MASTER TO master_demote_to_slave=1;
XA END 'a';
XA PREPARE 'a';

