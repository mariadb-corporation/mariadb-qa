CREATE FUNCTION f() RETURNS INTEGER RETURN 1;
CREATE TABLE t (a INT);
CREATE VIEW v AS SELECT 2 FROM t WHERE f() < 3;
FLUSH TABLE v WITH READ LOCK;
