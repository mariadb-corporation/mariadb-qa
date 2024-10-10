CREATE TABLE t (c INT);
CREATE TEMPORARY TABLE t (id INT);
DROP TABLE t;
SET GLOBAL general_log=ON,log_output='TABLE';
EXPLAIN SELECT * FROM t LIMIT ROWS EXAMINED 1;
INSERT INTO dummy SET a=0;

# Same outcome, but stack shows threadpool_process_request instead of do_handle_one_connection
# mysqld options required for replay:  --thread_handling=pool-of-threads
CREATE TABLE t (c INT KEY,c1 BLOB,c2 TEXT);
SET GLOBAL log_output='TABLE,FILE';
SET GLOBAL general_log=TRUE;
EXPLAIN SELECT * FROM t LIMIT ROWS EXAMINED 0;
EXPLAIN SELECT * FROM t JOIN customer2 ON customera=customer2.b;

SET GLOBAL log_output='TABLE', GLOBAL general_log=ON;
CREATE TABLE t (a INT) ;
EXPLAIN SELECT * FROM t LIMIT ROWS EXAMINED 0;
ALTER TABLE IF EXISTS t CHANGE a b INT;
