CREATE TABLE ti (id INT PRIMARY KEY) ENGINE=InnoDB;
SET SESSION wsrep_trx_fragment_size=1;
XA START 'test';
INSERT INTO ti VALUES (14);
SET SESSION wsrep_trx_fragment_unit='statements';
CREATE TEMPORARY SEQUENCE t1 ENGINE=InnoDB;
