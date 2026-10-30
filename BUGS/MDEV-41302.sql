CREATE TABLE t1 (id INT PRIMARY KEY, cnt INT);
INSERT INTO t1 VALUES (1,0);
DELIMITER //
CREATE FUNCTION bump_counter() RETURNS INT NOT DETERMINISTIC BEGIN UPDATE t1 SET cnt = cnt + 1 WHERE id = 1; RETURN 3; END//
DELIMITER ;
CREATE TABLE t2 (id INT PRIMARY KEY, c VARCHAR(50), KEY (c));
INSERT INTO t2 VALUES (1,'xxabcxxx');
SELECT id FROM t2 WHERE SUBSTR(c, (SELECT bump_counter()), 3) = 'abc';
SELECT cnt FROM t1 WHERE id = 1;
#CLI: 3; 2 for SUBSTR(CONCAT(c, ''), (SELECT bump_counter()), 3) = 'abc'
#ERR: - (no error)

CREATE TABLE t1 (a VARCHAR(10), b INT DEFAULT 1, KEY (a));
INSERT INTO t1 VALUES ('xab',2),('abc',1),('zzz',1),('ab',1),('yab',2);
FLUSH TABLES;
SELECT COUNT(*) FROM t1 WHERE SUBSTR(a, b, 2) = 'ab';
#CLI: 2; expected 4
#ERR: - (no error)

CREATE TABLE t1 (a VARCHAR(10), b INT DEFAULT 1, KEY (a));
INSERT INTO t1 VALUES ('xab',2),('abc',1),('zzz',1),('ab',1),('yab',2);
FLUSH TABLES;
SELECT COUNT(*) FROM t1 WHERE SUBSTRING(a, b) = 'ab';
#CLI: 1; expected 3
#ERR: - (no error)
