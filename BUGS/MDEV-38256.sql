CREATE VIEW c AS SELECT * FROM information_schema.tables;
INSTALL SONAME 'ha_connect';
CREATE TABLE t (c INT KEY) ENGINE=Connect;
SELECT * FROM t JOIN c;
