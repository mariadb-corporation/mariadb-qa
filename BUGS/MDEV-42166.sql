CREATE TABLE t1 (c VARCHAR(10), KEY (c));
INSERT INTO t1 VALUES ('a"1'),('b"2'),('x'),('y');
SET optimizer_trace='enabled=on';
SELECT c FROM t1 WHERE c IN ('a"1', 'b"2');
SELECT INSTR(trace, CONCAT(CHAR(92), CHAR(92))) > 0 FROM information_schema.OPTIMIZER_TRACE;
#CLI: 1; expected 0
#ERR: - (no error)
