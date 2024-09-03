DROP DATABASE mysql;
CREATE TABLE t (c INT KEY);
# ERR: [ERROR] InnoDB: Table mysql.innodb_table_stats not found.
