SELECT CAST(MD5(NOW()) AS CHAR) AS f, COUNT(*) FROM DUAL GROUP BY f;

CREATE TABLE t (f VARCHAR(512) COMPRESSED);
INSERT INTO t VALUES (REPEAT('a',357)),(REPEAT('b',360));
SELECT CASE (BINARY f) WHEN 'foo' THEN 1 END AS x FROM t GROUP BY x;