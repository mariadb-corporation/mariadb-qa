# mysqld options required for replay: --log-bin
CREATE TABLE t (c INT) ENGINE=MyISAM;
XA START 'a';
INSERT INTO t VALUES (0);
CHANGE MASTER TO master_host='a',master_port=1,master_user='a',master_demote_to_slave=1;

# mysqld options required for replay: --log_bin
SET max_session_mem_used=8192;
CREATE TABLE t (id INT KEY) ENGINE=INNODB;
XA START 'a';
CACHE INDEX t IN DEFAULT;
INSERT INTO t VALUES (1);

# mysqld options required for replay: --log_bin 
SET sql_mode='';
CREATE TABLE t1 (c1 REAL) ENGINE=MyISAM;
BEGIN;
SET GLOBAL TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET @@max_statement_time=0.00001;
#LOAD INDEX INTO CACHE t1 KEY(PRIMARY);   # Not needed, but may help to reproduce the issue better (likely just timing related)
INSERT INTO t1 VALUES (@@SESSION.TIMESTAMP);
