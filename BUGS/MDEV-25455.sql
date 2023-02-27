SET SESSION wsrep_trx_fragment_size=3;
SET @@sql_mode= '';
SET SESSION wsrep_osu_method=RSU;
SET GLOBAL tx_read_only=ON;
CREATE TABLE t1 (id INT(16) NOT NULL AUTO_INCREMENT, PRIMARY KEY(id)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (1),(2);
SELECT SLEEP (3);
