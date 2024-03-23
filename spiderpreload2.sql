INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE USER spider@localhost IDENTIFIED BY '';
GRANT ALL ON test.* TO spider@localhost;
FLUSH PRIVILEGES;
SET GLOBAL spider_same_server_link=ON;
CREATE server srv FOREIGN DATA wrapper mysql options (socket '../socket.sock', DATABASE 'test', USER 'spider', PASSWORD '');
