CREATE TABLE t (c INT) ENGINE=InnoDB;
INSERT DELAYED INTO t VALUES (1);  
CREATE OR REPLACE TABLE t (c INT) ENGINE=InnoDB;
