SET @@in_predicate_conversion_threshold=1;
CREATE TABLE t1 (a BIGINT);
INSERT INTO t1 VALUES (1),(2),(3);
PREPARE s FROM "SELECT*FROM t1 WHERE a IN ('1','5','3')";
EXECUTE s;
EXECUTE s;
