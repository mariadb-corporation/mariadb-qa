# mysqld options required for replay:  --skip-grant-tables=1
SET max_statement_time=0.001;
FLUSH PRIVILEGES;
CREATE VIEW v1 AS SELECT 1;
