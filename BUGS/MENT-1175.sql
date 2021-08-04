XA START 'a';
XA END 'a';
CACHE INDEX t1,t2 in default;
XA PREPARE 'a';

SET GLOBAL wsrep_mode=REPLICATE_ARIA;
XA START 'a';
DELETE FROM sys.sys_config WHERE variable = 'statement_performance_analyzer.view';
XA END 'a';
XA PREPARE 'a';

SET GLOBAL wsrep_mode=REPLICATE_ARIA;
XA START 'a';
DELETE FROM sys.sys_config WHERE variable = 'statement_performance_analyzer.view';
XA END 'a';
XA PREPARE 'a';
COMMIT;
