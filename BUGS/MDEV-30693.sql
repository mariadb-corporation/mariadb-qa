SET optimizer_use_condition_selectivity=1;
CREATE TABLE t (c INT KEY) ENGINE=InnoDB;
SELECT * FROM (SELECT * FROM t) a JOIN (SELECT * FROM (SELECT * FROM t GROUP BY c) d WHERE c>1) b ON a.c=b.c;
