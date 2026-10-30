CREATE TABLE t1 (a INT) PARTITION BY LINEAR HASH (a) PARTITIONS 9;
INSERT INTO t1 VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9);
ALTER TABLE t1 COALESCE PARTITION 7;
#CLI: ERROR 1863 (HY000): Found a row in wrong partition (2 != 1) a:3; expected no error
#ERR: [ERROR] Table '                                                                                                                                                                                              t1' corrupted: row in wrong partition: (2 != 1) a:3Please REPAIR the table!

CREATE TABLE t2 (a INT) PARTITION BY LINEAR KEY (a) PARTITIONS 17;
INSERT INTO t2 SELECT seq FROM seq_1_to_100;
ALTER TABLE t2 COALESCE PARTITION 13;
#CLI: ERROR 1863 (HY000): Found a row in wrong partition (2 != 1) a:4; expected no error
#ERR: [ERROR] Table '                                                                                                                                                                                              t2' corrupted: row in wrong partition: (2 != 1) a:4Please REPAIR the table!
