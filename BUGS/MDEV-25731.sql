SET @@global.wsrep_load_data_splitting=ON;
SET GLOBAL wsrep_replicate_myisam=ON;
CREATE TABLE t1 (c1 int) ENGINE=MYISAM;
LOAD DATA INFILE './t1.dat' IGNORE INTO TABLE t1 LINES TERMINATED BY '\n';