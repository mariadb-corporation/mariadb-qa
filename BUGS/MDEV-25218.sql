SET GLOBAL debug_dbug='d,sync.alter_opened_table';
CREATE TABLE t (a TEXT,FULLTEXT KEY(a));
ALTER TABLE t ADD c TIMESTAMP;