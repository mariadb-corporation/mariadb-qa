CREATE TABLE t1 (c2 VARBINARY(47) UNIQUE);
INSERT INTO t1 VALUES ('F'),('R'),('T');
SELECT COUNT(*) FROM t1 WHERE c2 BETWEEN 'r' AND 1145;
#CLI: 0; expected 3 (as with IGNORE INDEX (c2))
#ERR: - (no error)

CREATE TABLE t1 (id INT, vb VARBINARY(10), KEY (vb));
INSERT INTO t1 VALUES (1,'1'),(2,0x00),(3,''),(4,' 5'),(5,'5'),(6,'+5');
SELECT id FROM t1 FORCE INDEX (vb) WHERE vb BETWEEN '0' AND 9;
#CLI: 1, 5; expected 1, 2, 3, 4, 5, 6 (as with IGNORE INDEX (vb))
#ERR: - (no error)
