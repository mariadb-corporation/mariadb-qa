# Requires a SBL m/s replication setup
CREATE GLOBAL TEMPORARY TABLE t (c INT) ON COMMIT PRESERVE ROWS SELECT 1 a;
DROP TABLE t;  # Cleanup

# Requires a SBL m/s replication setup
CREATE GLOBAL TEMPORARY TABLE t (c INT KEY);
ANALYZE TABLE t;
DROP TABLE t;  # Cleanup
