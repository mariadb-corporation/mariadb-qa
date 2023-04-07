SELECT * FROM INFORMATION_SCHEMA.INNODB_SYS_INDEXES LIMIT ROWS EXAMINED 5;
SHUTDOWN;

SET max_statement_time=0.001;
SELECT sf.name,sf.pos FROM information_schema.innodb_sys_indexes si JOIN information_schema.innodb_sys_fields sf ON si.index_id=sf.index_id;
SHUTDOWN;
