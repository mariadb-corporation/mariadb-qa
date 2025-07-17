# mysqld options required for replay: --log-bin 
CREATE TABLE t (c INT);
SET SESSION binlog_format=STATEMENT;
CREATE TEMPORARY TABLE t LIKE information_schema.processlist;

# mysqld options required for replay: --log-bin
CREATE TEMPORARY TABLE t (c INT);
CREATE TABLE t2 (c INT);
LOCK TABLE t2 WRITE;
SET max_statement_time=0.0001;
CREATE OR REPLACE TABLE t2 LIKE t;

# mysqld options required for replay: --log-bin
CREATE TEMPORARY TABLE t (c INT);
CREATE TABLE t2 (c INT);
LOCK TABLE t2 WRITE;
SET max_session_mem_used=8192;
CREATE OR REPLACE TABLE t2 LIKE t;
