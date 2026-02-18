SET character_set_connection=utf16;
SELECT '' LIKE '' ESCAPE EXPORT_SET (1,1,1,1,'');

CREATE TABLE t (a TEXT CHARACTER SET utf16, KEY a(a(768)));
SELECT * FROM t WHERE a IN (SELECT a FROM t WHERE a>'');
