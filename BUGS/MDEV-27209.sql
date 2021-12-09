# mysqld options required for replay: --sql_mode=
SET GLOBAL innodb_limit_optimistic_insert_debug=7;
CREATE TABLE t1 (a CHAR(10) unicode NOT NULL, INDEX a (a)) ENGINE=InnoDB;
INSERT INTO t1 VALUES ('2008-01-03'),('2008-01-03'),(0x0061),(0x0041),(0x00E0),(0x00C0),(0x1EA3),(0x1EA2),(0x00E3),(0x00C3),(0x00E1),(0x00C1),(0x1EA1),(0x1EA0);
INSERT INTO t1 VALUES ('ü'),(0x98),(0x99),(0x9A),(0x9B),(0x9C),(0x9D),(0x9E),(0x9F),(0xA9D7),(0xC840);
ALTER TABLE t1 CONVERT TO CHARACTER SET ucs2 collate ucs2_spanish2_ci;
INSERT INTO t1 VALUES (CONVERT (_ucs2 0x064706450647 USING utf8)),(0xAEDF);
INSERT INTO t1 (a) VALUES (GEOMFROMTEXT ('LINESTRING (0 0)'));

