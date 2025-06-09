BINLOG ' O1ZVRw8BAAAAZgAAAGoAAAAAAAQANS4xLjIzLXJjLWRlYnVnLWxvZwAAAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAAA7VlVHEzgNAAgAEgAEBAQEEgAAUwAEGggAAAAICAgC ';
BINLOG '1iZAZwIBAAAAjQAAAHJ4AAAAACQAAAAAAAAABAAALQAAAAAAAQEAACBUAAAAAAYDc3RkBAgACAAACYEpAgAAAAAAAIIEnQAAAAAAAAB0ZXN0AGFsdGVyICB0YWJsZSB0NiBhZGQgY29sdW1uIGMgaW50LCBmb3JjZSwgYWxnb3JpdGhtPWNvcHlIBde4';

# CLI: ERROR 1800 (HY000): Unknown ALGORITHM 'copyH'
# ERR: [ERROR]  BINLOG_BASE64_EVENT: Error 'Unknown ALGORITHM 'copyH'' on query. Default database: 'test'. Query: 'alter  table t6 add column c int, force, algorithm=copyH^E׸', Internal MariaDB error code: 1800
# Reason: a corrupted ALTER in the BINLOG command: alter  table t6 add column c int, force, algorithm=copyH׸a
# While this ALTER when executed directly in the CLI will produce the same error there, it will not show an error in the error log, which can only be triggered by using BINLOG '...'. Using ' ... | base64 -di' can show the SQL for the 2nd statement
