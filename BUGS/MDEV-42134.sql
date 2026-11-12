CREATE TABLE t1 (pk INT PRIMARY KEY, a INT, g INT AS (a * 10) VIRTUAL, KEY (g)) ENGINE=MyISAM;
INSERT INTO t1 (pk, a) VALUES (1, 1), (2, 2), (3, 3);
SET optimizer_record_context=ON;
SELECT g FROM t1 WHERE pk = 2;
#CLI: 0; expected 20
#ERR: - (no error)

CREATE TABLE t1 (pk INT PRIMARY KEY, a INT, g INT AS (a * 10) VIRTUAL, KEY (g)) ENGINE=MyISAM;
INSERT INTO t1 (pk, a) VALUES (1, 1), (2, 2), (3, 3);
SET optimizer_record_context=ON;
SELECT MAX(g) FROM t1 WHERE g < 25;
#CLI: 25; expected 20
#ERR: - (no error)

CREATE TABLE t1 (pk INT PRIMARY KEY, a INT, g INT AS (a * 10) VIRTUAL, KEY (g)) ENGINE=InnoDB;
INSERT INTO t1 (pk, a) VALUES (1, 1), (2, 2), (3, 3);
SET optimizer_record_context=ON;
SELECT MAX(g) FROM t1;
#CLI: NULL; expected 30
#ERR: - (no error)

CREATE TABLE t1 (pk INT PRIMARY KEY, a INT, g INT AS (a * 10) VIRTUAL, KEY (g)) ENGINE=MyISAM;
INSERT INTO t1 (pk, a) VALUES (1, 1), (2, 2), (3, 3);
SET optimizer_record_context=ON;
SELECT MAX(g) FROM t1 WHERE g > 22 AND g < 25;
#CLI: 25; expected NULL (optimized build; a debug build asserts)
#ERR: - (no error)
