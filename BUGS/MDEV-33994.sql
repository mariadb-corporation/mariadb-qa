SET GLOBAL TRANSACTION READ ONLY;
SET GLOBAL wsrep_slave_threads=8;
SET SESSION wsrep_trx_fragment_size=128;
CREATE OR REPLACE TABLE t2 (a INT PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO t2 SELECT SEQ FROM seq_7000_to_10000;
INSERT INTO t2 VALUES ("1"),("2"),("3"),("7800");
SET character_set_collations='utf8mb3=uca1400_latvian_ai_ci';
SELECT COUNT(1) FROM t2;
SET GLOBAL read_only=1;
