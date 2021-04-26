SET @@GLOBAL.innodb_trx_rseg_n_slots_debug=1,@@SESSION.pseudo_slave_mode=ON;
CREATE TABLE t1 (a INT KEY) ENGINE=InnoDB;
CREATE TABLE t2 (a INT KEY) ENGINE=InnoDB;
XA START 'a';
INSERT INTO t2 VALUES (0);
XA END 'a';
XA PREPARE 'a';
DROP TABLE t1;   # ERROR 1637 (HY000): Too many active concurrent transactions
SELECT * FROM t1;  # ERROR 1030 (HY000): Got error 1877 "Unknown error 1877" from storage engine InnoDB
SELECT a FROM t1 WHERE a=(SELECT MAX(a) FROM t1);  # Crash
