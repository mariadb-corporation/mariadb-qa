DELETE FROM mysql.user;
CREATE FUNCTION f (i INT) RETURNS INT RETURN i;
FLUSH PRIVILEGES;
CREATE VIEW c AS SELECT f();
GRANT SELECT (f) ON c TO foo;
SHUTDOWN;
# Then check error log for 'Warning: Memory not freed: 280' or '264'
