# mysqld options required for replay: --log-bin 
SET SESSION binlog_format=STATEMENT;
CREATE TEMPORARY SEQUENCE s;
SELECT NEXT VALUE FOR s;
