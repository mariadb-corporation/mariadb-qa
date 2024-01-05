# mysqld options required for replay: --log-bin
CREATE TABLE t (c INT) ENGINE=MyISAM;
XA START 'a';
INSERT INTO t VALUES (0);
CHANGE MASTER TO master_host='a',master_port=1,master_user='a',master_demote_to_slave=1;
