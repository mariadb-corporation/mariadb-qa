SET @@max_statement_time=0.0001;
PREPARE p FROM 'CALL sys.statement_performance_analyzer(NULL,NULL,NULL);';  # Repeat till crash is seen (~5-10 tries)
