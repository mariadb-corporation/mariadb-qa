CREATE TABLE t (c INT NOT NULL UNIQUE) ENGINE=InnoDB;
INSERT INTO t VALUES (0),(1),(2),(3),(4),(5);
SET optimizer_scan_setup_cost=100000000;
SET optimizer_join_limit_pref_ratio=1;
EXPLAIN SELECT c FROM t ORDER BY c LIMIT 1;

CREATE TABLE t (c INT NOT NULL UNIQUE) ENGINE=InnoDB;
INSERT INTO t SELECT seq FROM seq_1_to_100000;
SET optimizer_join_limit_pref_ratio=1;
EXPLAIN SELECT c FROM t ORDER BY c LIMIT 28000;
