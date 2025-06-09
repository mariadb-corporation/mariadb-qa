# Causes hangs on 10.5.4 shutdown
USE test;
CREATE TABLE t(a INT);
XA START '0';
SET pseudo_slave_mode=1;
INSERT INTO t VALUES(7050+0.75);
XA PREPARE '0';
XA END '0';
XA PREPARE '0';
TRUNCATE TABLE t;
# Shutdown to observe hang (mysqladmin shutdown will hang)

SET pseudo_slave_mode=1;
CREATE TABLE t (c1 INT,c2 INT AUTO_INCREMENT PRIMARY KEY,KEY(c1)) ENGINE=InnoDB;
XA START 'a';
INSERT INTO t VALUES (0,0);
XA END 'a';
XA PREPARE 'a';
XA START 'b';
SELECT * FROM t;
INSERT INTO t SELECT * FROM t;  # Will hang till lock wait timeout, and shutdown will hang if initiated
