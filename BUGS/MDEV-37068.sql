SET sql_mode='';
CREATE TABLE t1 (v VECTOR (1) NOT NULL,VECTOR vec (v),UNIQUE vu (v)) ENGINE=InnoDB;
XA START 'a';
INSERT INTO t1 SELECT * FROM seq_10_to_20;  # Any value
INSERT INTO t1 VALUES (1);  # Any value
# CLI: ERROR 1032 (HY000): Can't find record in 't1'
# ERR: [ERROR] mariadbd: Can't find record in 't1'
