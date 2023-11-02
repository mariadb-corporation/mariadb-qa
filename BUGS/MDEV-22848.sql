# mysqld options required for replay: --log-bin
USE test;
SET autocommit=0;
CREATE TABLE t1 (c INT) ENGINE=MyISAM;
SET GLOBAL gtid_slave_pos="0-1-100";
INSERT INTO t1 VALUES (0);
DROP TABLE not_there;

SET autocommit=0;
SET GLOBAL gtid_slave_pos= "0-1-50";
SAVEPOINT a;

# mysqld options required for replay: --log-bin
CREATE TABLE t1 (id int  KEY) ENGINE=MyISAM;
SET GLOBAL gtid_slave_pos='100-100-100';
INSERT INTO t1 VALUES(1);
ALTER TABLE t4 CHANGE c1 c1 SMALLINT UNSIGNED ;
