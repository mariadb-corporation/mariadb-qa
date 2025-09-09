# mysqld options required for replay: --log-bin 
CREATE TABLE metrics LIKE information_schema.innodb_metrics;
