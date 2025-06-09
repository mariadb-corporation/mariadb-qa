SET pseudo_slave_mode=1;
CREATE TABLE t (c1 INT,c2 INT AUTO_INCREMENT PRIMARY KEY,KEY(c1)) ENGINE=InnoDB;
XA START 'a';
INSERT INTO t VALUES (0,0);
XA END 'a';
XA PREPARE 'a';
XA START 'b';
SELECT * FROM t;
INSERT INTO t SELECT * FROM t;

# CLI: ERROR 1020 (HY000): Record has changed since last read in table 't'
# ERR: [ERROR] Got error 123 when reading table './test/t'
