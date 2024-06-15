DROP DATABASE test;
INSTALL SONAME 'ha_spider';
SELECT spider_copy_tables ('a','','');
