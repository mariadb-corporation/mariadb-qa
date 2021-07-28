XA START 'a';
SET GLOBAL wsrep_provider_options='repl.max_ws_size=512';
SET max_session_mem_used=50000;
XA END 'a';
XA PREPARE 'a';
CALL sys.statement_performance_analyzer ('overALL', NULL, 'with_full_table_scans');
CALL sys.statement_performance_analyzer ('overALL', NULL, 'with_full_table_scans');
