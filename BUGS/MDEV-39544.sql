CREATE TABLE t(c INT,c2 TEXT) ENGINE=InnoDB;
SET @@SESSION.sort_buffer_size=30839;  # up to 30839: error, 30840: no error
SELECT c,LAG(c,1) OVER w FROM t WINDOW w AS (PARTITION BY c2 ORDER BY c2);
DROP TABLE t;  # Cleanup
#CLI: ERROR 1038 (HY001): Out of sort memory, consider increasing server sort buffer size
#ERR: [ERROR] mariadbd: Out of sort memory, consider increasing server sort buffer size
