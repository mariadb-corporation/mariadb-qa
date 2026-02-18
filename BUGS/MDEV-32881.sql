INSTALL SONAME 'ha_mroonga';
CREATE TABLE t (f TEXT, FULLTEXT(f)) ENGINE=Mroonga CHARACTER SET gbk;

INSTALL SONAME 'ha_mroonga';
SET default_storage_engine=Mroonga;
CREATE TABLE t (id INT KEY,content TEXT,FULLTEXT INDEX (content) COMMENT 'TABLE "terms"') DEFAULT CHARSET=utf8;
