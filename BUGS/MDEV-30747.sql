SET GLOBAL wsrep_convert_lock_to_trx=ON;
LOCK TABLES performance_schema.events_transactions_history WRITE;
UNLOCK TABLES;
