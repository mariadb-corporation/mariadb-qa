SET @@log_slow_verbosity=1;
CREATE TEMPORARY TABLE t (c INT) ENGINE=InnoDB;
INSERT INTO t VALUES(1);
SHOW TABLES;
# Repeat the following till a crash is seen
UPDATE t SET c=1;#aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
SELECT * FROM t ORDER BY c;#aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

SHOW TRIGGERS;
SET SESSION log_slow_verbosity='engine';
SET NAMES character_set_connection=ucs;
# Repeat the following till a crash is seen
CREATE TEMPORARY TABLE t (c INT) ENGINE=InnoDB;
UPDATE t SET c=0 WHERE c>0;#AAAAAAA;
SELECT hex(c),hex(c),c FROM t ORDER BY c;#AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
DROP TABLE t;
