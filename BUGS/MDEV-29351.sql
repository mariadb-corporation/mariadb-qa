CREATE TABLE t (a INT);
UPDATE t SET c=1 ORDER BY (SELECT c);
# CLI: ERROR 1247 (42S22): Reference 'c' not supported (forward reference in item list)
UPDATE t SET c=1 ORDER BY (SELECT c);

CREATE TABLE t (a CHAR(1),b VARCHAR(1),KEY(a)) ENGINE=InnoDB;
UPDATE t SET c=1 ORDER BY (SELECT c LIMIT 0);
