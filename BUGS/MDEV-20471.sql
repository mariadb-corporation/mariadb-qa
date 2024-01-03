# mysqld options required for replay: --log-bin
SET sql_mode='';
DROP TABLE IF EXISTS t;
DROP SEQUENCE IF EXISTS s;
SET MAX_STATEMENT_TIME=0.0001;
CREATE SEQUENCE s;
CREATE TABLE t LIKE s;
