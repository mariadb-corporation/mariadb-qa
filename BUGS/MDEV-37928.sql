# Requires standard MBR m/s setup
CREATE GLOBAL TEMPORARY TABLE t (x INT,t TEXT);
CREATE TEMPORARY TABLE t (id INT);
SET STATEMENT use_stat_tables=never FOR ANALYZE TABLE t;
# Cleanup (not finalized)
DROP TABLE t;
DROP TABLE t;

# Requires standard RBR m/s setup
CREATE GLOBAL TEMPORARY TABLE t (x INT);
CREATE TEMPORARY TABLE t (y INT);
ANALYZE TABLE t;
