SET GLOBAL log_bin_trust_function_creators=ON;
CREATE FUNCTION f() RETURNS INT RETURN (SELECT 1 FROM t);
CREATE VIEW v AS SELECT f();
FLUSH TABLE v WITH READ LOCK;

# mysqld options required for replay:  --log_bin_trust_function_creators=1
CREATE FUNCTION f() RETURNS INT RETURN (SELECT 1 FROM t);
CREATE VIEW v AS SELECT 0 AS a,f() AS DAYS;
FLUSH TABLES v FOR EXPORT;
