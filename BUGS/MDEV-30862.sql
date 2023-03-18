SET autocommit=0;
SET SESSION wsrep_trx_fragment_size=1;
CREATE TABLE t2 SELECT seq FROM seq_1_to_50;
