# Needs the time zone tables: mariadb-tzinfo-to-sql /usr/share/zoneinfo | mariadb mysql
SET time_zone='MET';
SET timestamp= UNIX_TIMESTAMP('2026-03-29 06:00:00');
CREATE TABLE t1 (ts TIMESTAMP) PARTITION BY RANGE COLUMNS (ts) INTERVAL 1 HOUR (PARTITION p0 VALUES LESS THAN ('2026-03-29 00:00:00'));
INSERT INTO t1 VALUES ('2026-03-28 23:00:00');
#CLI: ERROR 1493 (HY000): VALUES LESS THAN value must be strictly increasing for each partition
#ERR: - (no error)
