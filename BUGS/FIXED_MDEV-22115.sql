USE test;
CREATE TABLE t (c MULTIPOLYGON UNIQUE);
ALTER TABLE t ADD INDEX(c);

CREATE TABLE t (c GEOMETRYCOLLECTION UNIQUE);
ALTER TABLE t ADD INDEX(c);

CREATE TABLE t(c LINESTRING UNIQUE);
ALTER TABLE t ADD INDEX(c);

CREATE TABLE t (c YEAR KEY,e JSON,d GEOMETRY);
ALTER TABLE t ADD INDEX(d),ADD UNIQUE (d);
ALTER TABLE t ADD INDEX(d),ADD UNIQUE (d);