SET @@max_statement_time=0.0001;
CHECKSUM TABLE performance_schema.rwlock_instances;
CHECKSUM TABLE performance_schema.table_io_waits_summary_by_table;
CHECKSUM TABLE performance_schema.users;
