# Highly sporadic
CREATE TABLE t (a1 VARCHAR(1), a2 VARCHAR(1)) ENGINE=InnoDB;
XA START 'a';
CREATE TEMPORARY TABLE t (c1 INT) ENGINE=InnoDB;
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7);
INSERT IGNORE INTO t VALUES (@inserted_value);
XA END 'a';
XA ROLLBACK 'a';
SET SESSION gtid_domain_id=10;