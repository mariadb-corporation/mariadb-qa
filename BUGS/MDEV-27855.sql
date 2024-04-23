# mysqld options required for replay:  --maximum-sort_buffer_size=1M                                                    
SET sql_mode='traditional';
SET STATEMENT sort_buffer_size=100000 FOR SHOW SESSION VARIABLES LIKE 'sort_buffer_size';  # Repeat until the crash is observed.

# mysqld options required for replay:  --maximum-max_join_size=1M
CREATE TABLE t (c INT);  # MyISAM and InnoDB both fail
SET @@sql_mode='traditional';
SET STATEMENT max_join_size=1000 FOR SELECT * FROM t;
