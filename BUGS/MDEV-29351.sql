CREATE TABLE t (a INT);
UPDATE t SET c=1 ORDER BY (SELECT c);
UPDATE t SET c=1 ORDER BY (SELECT c);
# CLI: ERROR 1247 (42S22): Reference 'c' not supported (forward reference in item list)
