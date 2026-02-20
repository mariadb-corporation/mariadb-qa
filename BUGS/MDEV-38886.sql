INSTALL SONAME 'ha_connect';
CREATE TABLE t (i INT) ENGINE=Connect table_type=XML option_list='xmlsup=libxml2';
INSERT INTO t VALUES ();
DELETE FROM t;
