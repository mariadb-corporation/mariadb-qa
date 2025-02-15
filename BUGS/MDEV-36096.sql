SET sql_select_limit=1,optimizer_join_limit_pref_ratio=1;
CREATE TABLE t (c INT NOT NULL UNIQUE) ENGINE=InnoDB;
INSERT INTO t VALUES (0),(1),(2),(3),(4),(5);
SELECT * FROM t ORDER BY c;
