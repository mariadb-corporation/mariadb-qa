# mysqld options required for replay: --log-bin 
CREATE TABLE t (c INT);
SET SESSION binlog_format=STATEMENT;
CREATE TEMPORARY TABLE t LIKE information_schema.processlist;
