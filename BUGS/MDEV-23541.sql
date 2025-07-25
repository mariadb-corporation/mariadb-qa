CREATE TEMPORARY TABLE sbtest(a INT,b INT,INDEX i(a));
set optimizer_switch=`mrr=on,mrr_cost_based=off`;
truncate TABLE sbtest;
EXPLAIN SELECT * FROM sbtest WHERE a=0 AND(b=0 OR b=0 OR b>0);
