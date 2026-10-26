CREATE TABLE t1 (a INET6, KEY (a));
INSERT INTO t1 VALUES (NULL), ('::1'), ('::2');
SELECT COUNT(*) FROM t1 WHERE a <=> 'x';
#CLI: 0; expected 1 (as with IGNORE INDEX (a))
#ERR: - (no error)
