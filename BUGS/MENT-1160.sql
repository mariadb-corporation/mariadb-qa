SET SESSION wsrep_osu_method=NBO;
SET GLOBAL debug_dbug='d,sync.wsrep_alter_locked_tables';
DROP INDEX nonexisting_idx ON nonexisting_tbl;
