# Requires two sessions: run the first INSERT in a second session, and the second INSERT within 0.5 seconds of it; ref bug report for MTR testcase
CREATE TABLE t1 (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, c INT) ENGINE=InnoDB PARTITION BY HASH (id) PARTITIONS 2;
INSERT INTO t1 (c) SELECT SLEEP(1) FROM seq_1_to_3;
INSERT INTO t1 (c) SELECT SLEEP(1) FROM seq_1_to_2;
#CLI: ERROR 1213 (40001): Deadlock found when trying to get lock; try restarting transaction, on the second INSERT in 3 of 3 runs; expected no error
#ERR: - (no error)
