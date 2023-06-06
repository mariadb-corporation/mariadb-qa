INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'test',USER'',PASSWORD'');
CREATE TABLE t (c INT KEY) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t1"';
CREATE TABLE t1 (c INT KEY) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"';
SELECT * FROM t1 WHERE c=0;  # CLI Error: An infinite loop is detected when opening table test.t (to be expected)

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'test',USER'',PASSWORD'');
CREATE TABLE t (c INT KEY) ENGINE=InnoDB COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"';
CREATE TABLE t1 (c INT KEY) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"';
SHOW CREATE TABLE t1;
ALTER TABLE t ENGINE=Spider;
SELECT * FROM t1 WHERE c=0;  # CLI + Error log error: idem, ref https://jira.mariadb.org/browse/MDEV-31409?focusedCommentId=260582&page=com.atlassian.jira.plugin.system.issuetabpanels:comment-tabpanel#comment-260582
