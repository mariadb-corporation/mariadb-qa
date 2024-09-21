INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t1 ( a varchar(32) character set utf8 collate utf8_bin,b varchar(32) character set utf8 collate utf8_bin ) ENGINE=Spider DEFAULT CHARSET=utf8;
delete from t1 where a < 500;
SET max_statement_time=0.000001;
SELECT 1 list;
handler t1 open;
handler t1 read next ;
