DROP DATABASE test;
INSTALL SONAME 'ha_spider';
UNINSTALL SONAME IF EXISTS 'ha_spider';
SELECT spider_ping_table('',0,0,0,'',0,0,0,0,0);
